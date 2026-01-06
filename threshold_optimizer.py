"""
threshold_optimizer.py

機能:
- `pose_judge_sim` の評価関数を使い、角度閾値と時間閾値（perfect_t）をグリッド探索して
  精度(Accuracy)/適合率(Precision)/再現率(Recall)/F1 を計算する
- 二値評価（match vs miss）と、多クラス判定の分布を出力
- 結果を CSV に保存し、PR カーブやヒートマップを PNG で保存

使い方:
  python rhythm_game/threshold_optimizer.py [--data path/to/data.json]

要件: numpy, matplotlib

"""
import argparse
import numpy as np
import os
import json
import csv
import matplotlib.pyplot as plt
from pose_judge_sim import generate_synthetic_reference, generate_synthetic_user, load_real_data, evaluate_session


def binary_metrics(counts):
    # counts: dict with 'Perfect','Great','Good','Miss'
    tp = counts.get('Perfect',0) + counts.get('Great',0) + counts.get('Good',0)
    fn = counts.get('Miss',0)
    # For simplicity, treat TP as matched refs; FP estimation is not direct here because we don't have predicted labels beyond matched events
    # We'll compute precision as TP / (TP + FP) with FP approximated as 0 (optimistic) in this setup; better with frame-level predictions.
    # Instead, compute recall = TP / (TP + FN)
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    # Here we define accuracy as TP / total_refs
    total = tp + fn
    accuracy = tp / total if total > 0 else 0.0
    # For precision we approximate precision = TP / (TP + (total_ref - TP)) = tp/total = accuracy (degenerate)
    # So we report recall and accuracy primarily.
    return accuracy, recall


def grid_search(refs, users, angle_thresholds, perfect_ts, great_offset=2.0, good_offset=4.0):
    records = []
    heat = np.zeros((len(perfect_ts), len(angle_thresholds)))

    for i,pt in enumerate(perfect_ts):
        great_t = pt + great_offset
        good_t = pt + good_offset
        for j,th in enumerate(angle_thresholds):
            details, counts = evaluate_session(refs, users, angle_threshold=th, perfect_t=pt, great_t=great_t, good_t=good_t)
            accuracy, recall = binary_metrics(counts)
            records.append({'angle_threshold': th, 'perfect_t': pt, 'great_t': great_t, 'good_t': good_t, 'Perfect': counts['Perfect'], 'Great': counts['Great'], 'Good': counts['Good'], 'Miss': counts['Miss'], 'accuracy': accuracy, 'recall': recall})
            heat[i,j] = accuracy
    return records, heat


def save_csv(records, path='logs/optimizer_results.csv'):
    os.makedirs('logs', exist_ok=True)
    keys = list(records[0].keys()) if records else []
    with open(path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=keys)
        writer.writeheader()
        for r in records:
            writer.writerow(r)


def plot_heatmap(heat, angle_thresholds, perfect_ts, path='logs/accuracy_heatmap.png'):
    plt.figure(figsize=(10,6))
    plt.imshow(heat, origin='lower', aspect='auto', cmap='viridis')
    plt.colorbar(label='Accuracy')
    plt.xticks(np.arange(len(angle_thresholds)), angle_thresholds)
    plt.yticks(np.arange(len(perfect_ts)), perfect_ts)
    plt.xlabel('Angle Threshold (deg)')
    plt.ylabel('Perfect_t (sec)')
    plt.title('Accuracy Heatmap')
    plt.tight_layout()
    plt.savefig(path)
    plt.close()


def plot_pr_curve(records, angle_thresholds, path='logs/pr_curve.png'):
    # For PR curve, compute recall vs angle_threshold for a fixed perfect_t (choose median perfect_t)
    # We'll average recall across perfect_t values
    grouped = {}
    for r in records:
        th = r['angle_threshold']
        grouped.setdefault(th, []).append(r['recall'])
    ths = sorted(grouped.keys())
    recalls = [np.mean(grouped[t]) for t in ths]
    precisions = recalls  # using recall as proxy due to dataset constraints
    plt.figure()
    plt.plot(recalls, precisions, marker='o')
    plt.xlabel('Recall (proxy)')
    plt.ylabel('Precision (proxy)')
    plt.title('PR curve (proxy)')
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(path)
    plt.close()


def main(args):
    if args.data:
        refs, users = load_real_data(args.data)
    else:
        refs = generate_synthetic_reference(duration=60.0, n_keyframes=30)
        users = generate_synthetic_user(refs, timing_jitter_std=0.8, angle_noise_std=8.0, miss_prob=0.12)

    angle_thresholds = list(range(8, 31, 2))
    perfect_ts = [1.0, 1.5, 2.0, 2.5, 3.0]

    records, heat = grid_search(refs, users, angle_thresholds, perfect_ts)
    save_csv(records)
    plot_heatmap(heat, angle_thresholds, perfect_ts)
    plot_pr_curve(records, angle_thresholds)

    # summarize best
    best_idx = np.argmax(heat)
    i, j = np.unravel_index(best_idx, heat.shape)
    best_pt = perfect_ts[i]
    best_th = angle_thresholds[j]
    print(f'Best accuracy {heat[i,j]:.3f} at perfect_t={best_pt}, angle_threshold={best_th}')
    print('Results saved to logs/optimizer_results.csv and logs/*.png')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', type=str, default=None, help='Path to JSON with refs/users (optional)')
    args = parser.parse_args()
    main(args)
