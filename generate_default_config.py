"""
generate_default_config.py

合成データでグリッドサーチを実行し、最も高精度だった閾値を
`configs/default_thresholds.json` に保存します。

出力:
 - configs/default_thresholds.json
 - logs/optimizer_results.csv（既存）
 - logs/accuracy_heatmap.png（既存）

"""
import json
import os
from threshold_optimizer import generate_synthetic_reference, generate_synthetic_user, grid_search


def main():
    refs = generate_synthetic_reference(duration=60.0, n_keyframes=30)
    users = generate_synthetic_user(refs, timing_jitter_std=0.8, angle_noise_std=8.0, miss_prob=0.12)

    angle_thresholds = list(range(8, 31, 2))
    perfect_ts = [1.0, 1.5, 2.0, 2.5, 3.0]

    records, heat = grid_search(refs, users, angle_thresholds, perfect_ts)

    # find best
    best_idx = heat.argmax()
    import numpy as np
    i, j = np.unravel_index(best_idx, heat.shape)
    best = {
        'angle_threshold': int(angle_thresholds[j]),
        'perfect_t': float(perfect_ts[i]),
        'great_t': float(perfect_ts[i] + 2.0),
        'good_t': float(perfect_ts[i] + 4.0),
        'accuracy': float(heat[i,j])
    }

    os.makedirs('configs', exist_ok=True)
    out_path = 'configs/default_thresholds.json'
    with open(out_path, 'w') as f:
        json.dump(best, f, indent=2)

    print('Wrote recommended defaults to', out_path)
    print('Recommended:', best)

if __name__ == '__main__':
    main()
