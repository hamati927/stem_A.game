"""
pose_judge_sim.py

目的：見本（reference）キーフレームとユーザポーズの時系列を用いて
判定アルゴリズムの閾値（角度・時間）をチューニングするためのシミュレーションとロギング用スクリプト。

使い方（基本）:
  - スクリプトを実行すると合成データで評価を行い、 results.csv と details.json を出力します。
  - 実データがある場合は load_real_data(json_path) を使って読み込み、evaluate_session() に渡せます。

出力:
  - logs/results.csv: 閾値ごとのサマリ
  - logs/details.json: 各キーフレームの詳細な判定ログ

実装上のポイント（初心者向け注釈）:
  - ジョイント角度差の平均を "角度誤差" として用いる。
  - 各見本キーフレームに対し、ユーザの最初の成功フレーム（角度誤差 <= threshold）を探索し、時間差(dt)で判定を行う。
  - 時間閾値はパラメータ化されており、簡単に変更できる。

"""

from typing import List, Dict, Tuple, Any
import numpy as np
import json
import csv
import os
import random

# --------------------------- ユーティリティ関数 ---------------------------

def angle_between(a: Tuple[float,float], b: Tuple[float,float], c: Tuple[float,float]) -> float:
    """点 a-b-c における角度（度）を返す。"""
    ax, ay = a; bx, by = b; cx, cy = c
    v1 = (ax - bx, ay - by)
    v2 = (cx - bx, cy - by)
    dot = v1[0]*v2[0] + v1[1]*v2[1]
    mag1 = np.hypot(v1[0], v1[1])
    mag2 = np.hypot(v2[0], v2[1])
    if mag1 * mag2 == 0:
        return 0.0
    cosv = max(-1.0, min(1.0, dot/(mag1*mag2)))
    return float(np.degrees(np.arccos(cosv)))


def compute_angles_from_landmarks(landmarks: Dict[str, Tuple[float,float]]) -> Dict[str, float]:
    """ランドマーク(dict)から主要関節角度を計算して返す。
    landmarks のキーは MediaPipe 風の名前を想定（'left_hip','left_knee','left_ankle', ...）
    返り値は角度の dict（例: 'left_knee': 35.0）
    """
    angles = {}
    # 膝角：hip - knee - ankle
    try:
        angles['left_knee'] = angle_between(landmarks['left_hip'], landmarks['left_knee'], landmarks['left_ankle'])
        angles['right_knee'] = angle_between(landmarks['right_hip'], landmarks['right_knee'], landmarks['right_ankle'])
        # 股関節（肩と膝を使った近似）: shoulder - hip - knee
        angles['left_hip'] = angle_between(landmarks['left_shoulder'], landmarks['left_hip'], landmarks['left_knee'])
        angles['right_hip'] = angle_between(landmarks['right_shoulder'], landmarks['right_hip'], landmarks['right_knee'])
    except KeyError:
        # 必要なランドマークがない場合はゼロで埋める
        for k in ['left_knee','right_knee','left_hip','right_hip']:
            if k not in angles:
                angles[k] = 0.0
    return angles


def mean_angle_diff(a: Dict[str,float], b: Dict[str,float], joints: List[str]) -> float:
    """指定した joints の平均絶対角度差を計算。"""
    diffs = []
    for j in joints:
        diffs.append(abs(a.get(j, 0.0) - b.get(j, 0.0)))
    return float(np.mean(diffs)) if diffs else float('inf')


# --------------------------- 合成データ生成 ---------------------------

def generate_synthetic_reference(duration: float = 60.0, n_keyframes: int = 20) -> List[Dict[str,Any]]:
    """参考: 単純なキーフレーム列（時刻と擬似ランドマーク）を生成する
    戻り値: [{'t': float, 'landmarks': {name:(x,y)}},...]
    """
    times = np.linspace(0, duration, n_keyframes)
    refs = []
    for t in times:
        # 簡易：スクワット/ステップの2状態を混ぜた角度パターン
        phase = (np.sin(2 * np.pi * t / max(1.0, duration / 4)) + 1) / 2  # 0..1
        # ランドマークを簡易的に形作る（左右対称）: y 値を変えることで角度が変わる
        base_shoulder_y = 0.2
        base_hip_y = 0.5
        base_knee_y = 0.7 + 0.15 * phase
        # landmarks は正規化座標 (x,y)
        landmarks = {
            'left_shoulder': (0.35, base_shoulder_y),
            'right_shoulder': (0.65, base_shoulder_y),
            'left_hip': (0.4, base_hip_y),
            'right_hip': (0.6, base_hip_y),
            'left_knee': (0.42, base_knee_y),
            'right_knee': (0.58, base_knee_y),
            'left_ankle': (0.43, 0.95),
            'right_ankle': (0.57, 0.95)
        }
        refs.append({'t': float(t), 'landmarks': landmarks})
    return refs


def generate_synthetic_user(refs: List[Dict[str,Any]], timing_jitter_std: float = 0.8, angle_noise_std: float = 6.0, miss_prob: float = 0.1) -> List[Dict[str,Any]]:
    """参考キーフレームを元にユーザの実際のフレーム系列（成功イベント）を生成する。
    各 ref に対して、ある確率でミス（イベント無し）にし、それ以外は t = t_ref + jitter, angles = ref_angles + noise
    戻り値: [{'t': float, 'landmarks': {...}}, ...]
    """
    users = []
    for ref in refs:
        if random.random() < miss_prob:
            continue
        dt = max(-1.5, np.random.normal(0.5, timing_jitter_std))  # 遅れが一般的
        t_user = max(0.0, ref['t'] + dt)
        # add angle noise by perturbing knee positions vertically
        lmk = ref['landmarks'].copy()
        # perturb kneey position y to simulate angle change
        perturb = lambda y: y + np.random.normal(0.0, angle_noise_std/100.0)
        lmk['left_knee'] = (lmk['left_knee'][0], perturb(lmk['left_knee'][1]))
        lmk['right_knee'] = (lmk['right_knee'][0], perturb(lmk['right_knee'][1]))
        # small shift to hips
        lmk['left_hip'] = (lmk['left_hip'][0], lmk['left_hip'][1] + np.random.normal(0.0, angle_noise_std/200.0))
        lmk['right_hip'] = (lmk['right_hip'][0], lmk['right_hip'][1] + np.random.normal(0.0, angle_noise_std/200.0))
        users.append({'t': float(t_user), 'landmarks': lmk})
    # sort by time
    users.sort(key=lambda x: x['t'])
    return users


# --------------------------- 評価関数 ---------------------------

def evaluate_session(refs: List[Dict[str,Any]], users: List[Dict[str,Any]],
                     angle_threshold: float = 20.0,
                     perfect_t: float = 2.0, great_t: float = 4.0, good_t: float = 6.0,
                     joints: List[str] = ['left_knee','right_knee','left_hip','right_hip']) -> Tuple[List[Dict[str,Any]], Dict[str,int]]:
    """セッションを評価する。
    戻り値: (detailed_results, summary_counts)
    detailed_results: list of {t_ref, matched, t_user, dt, angle_diff, judgment}
    summary_counts: dict of counts
    """
    user_idx = 0
    n_users = len(users)
    details = []
    counts = {'Perfect':0,'Great':0,'Good':0,'Miss':0}

    for ref in refs:
        t_ref = ref['t']
        ref_angles = compute_angles_from_landmarks(ref['landmarks'])
        matched = False
        # search forward from current user index for first match
        while user_idx < n_users and users[user_idx]['t'] < t_ref - good_t:
            # this user event is too early for this ref, skip
            user_idx += 1
        search_idx = user_idx
        found = None
        while search_idx < n_users and users[search_idx]['t'] <= t_ref + good_t:
            user = users[search_idx]
            user_angles = compute_angles_from_landmarks(user['landmarks'])
            angle_diff = mean_angle_diff(user_angles, ref_angles, joints)
            if angle_diff <= angle_threshold:
                found = {'t_user': user['t'], 'angle_diff': angle_diff}
                break
            search_idx += 1
        if found is None:
            details.append({'t_ref': t_ref, 'matched': False, 't_user': None, 'dt': None, 'angle_diff': None, 'judgment': 'Miss'})
            counts['Miss'] += 1
        else:
            dt = found['t_user'] - t_ref
            if abs(dt) <= perfect_t:
                j = 'Perfect'
            elif abs(dt) <= great_t:
                j = 'Great'
            elif abs(dt) <= good_t:
                j = 'Good'
            else:
                j = 'Miss'
            details.append({'t_ref': t_ref, 'matched': True, 't_user': found['t_user'], 'dt': dt, 'angle_diff': found['angle_diff'], 'judgment': j})
            counts[j] += 1
            # advance user_idx to search after this matched event to avoid reuse
            user_idx = search_idx + 1
    return details, counts


# --------------------------- ロギング ---------------------------

def ensure_logs_dir():
    os.makedirs('logs', exist_ok=True)


def save_results_csv(records: List[Dict[str,Any]], csv_path: str = 'logs/results.csv'):
    ensure_logs_dir()
    keys = list(records[0].keys()) if records else []
    with open(csv_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=keys)
        writer.writeheader()
        for r in records:
            writer.writerow(r)


def save_details_json(details: Any, json_path: str = 'logs/details.json'):
    ensure_logs_dir()
    with open(json_path, 'w') as f:
        json.dump(details, f, indent=2)


# --------------------------- 実験ルーチン ---------------------------

def sweep_thresholds_and_log(refs, users, angle_thresholds=[10,15,20,25,30], perfect_t=2.0, great_t=4.0, good_t=6.0):
    records = []
    all_details = {}
    total_refs = len(refs)
    for th in angle_thresholds:
        details, counts = evaluate_session(refs, users, angle_threshold=th, perfect_t=perfect_t, great_t=great_t, good_t=good_t)
        avg_dt_list = [d['dt'] for d in details if d['dt'] is not None]
        avg_dt = float(np.mean(avg_dt_list)) if avg_dt_list else None
        rec = {'angle_threshold': th, 'total_ref': total_refs, 'Perfect': counts['Perfect'], 'Great': counts['Great'], 'Good': counts['Good'], 'Miss': counts['Miss'], 'avg_dt_matched': avg_dt}
        records.append(rec)
        all_details[th] = details
    save_results_csv(records)
    save_details_json(all_details)
    return records, all_details


# --------------------------- 実データの読み込み（例） ---------------------------

def load_real_data(json_path: str) -> Tuple[List[Dict[str,Any]], List[Dict[str,Any]]]:
    """JSON から refs と users を読み込む。形式は上の合成データと同様を期待。
    例:
    {
      "refs": [{"t":0.0, "landmarks": {"left_hip":[x,y], ...}}, ...],
      "users": [{"t":0.5, "landmarks": {...}}, ...]
    }
    """
    with open(json_path, 'r') as f:
        d = json.load(f)
    return d.get('refs', []), d.get('users', [])


# --------------------------- 実行例 ---------------------------

if __name__ == '__main__':
    # 生成
    refs = generate_synthetic_reference(duration=60.0, n_keyframes=20)
    users = generate_synthetic_user(refs, timing_jitter_std=0.8, angle_noise_std=8.0, miss_prob=0.12)

    # スイープ
    angle_thresholds = [8,10,12,15,18,20,25]
    records, details = sweep_thresholds_and_log(refs, users, angle_thresholds=angle_thresholds)

    print('Sweep complete. Results:')
    for r in records:
        print(r)

    print('\n詳細は logs/results.csv と logs/details.json を参照してください。')

# EOF
