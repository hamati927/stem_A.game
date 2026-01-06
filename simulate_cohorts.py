"""
simulate_cohorts.py

合成データで複数コホート（若年/高齢/初心者）をシミュレートし、各コホートに対して閾値最適化を行う。
結果を `logs/cohort_results.csv` と `configs/cohort_defaults.json` に保存する。

使い方:
  python rhythm_game/simulate_cohorts.py

"""
import json
import os
import numpy as np
from pose_judge_sim import generate_synthetic_reference, generate_synthetic_user, evaluate_session
from threshold_optimizer import grid_search

COHORTS = {
    'young_active': {
        'timing_jitter_std': 0.4,
        'angle_noise_std': 4.0,
        'miss_prob': 0.05
    },
    'adult_novice': {
        'timing_jitter_std': 0.8,
        'angle_noise_std': 7.0,
        'miss_prob': 0.12
    },
    'elderly': {
        'timing_jitter_std': 1.2,
        'angle_noise_std': 10.0,
        'miss_prob': 0.2
    }
}

angle_thresholds = list(range(8, 31, 2))
perfect_ts = [1.0, 1.5, 2.0, 2.5, 3.0]

os.makedirs('logs', exist_ok=True)

cohort_summary = []
cohort_defaults = {}

for name, params in COHORTS.items():
    print('Simulating cohort:', name)
    # generate single reference and multiple user samples (simulate several participants)
    refs = generate_synthetic_reference(duration=60.0, n_keyframes=30)
    # to model variability across participants, create several user lists and aggregate by averaging heat maps
    heat_accum = np.zeros((len(perfect_ts), len(angle_thresholds)))
    trials = 8
    for seed in range(trials):
        users = generate_synthetic_user(refs,
                                        timing_jitter_std=params['timing_jitter_std'],
                                        angle_noise_std=params['angle_noise_std'],
                                        miss_prob=params['miss_prob'])
        records, heat = grid_search(refs, users, angle_thresholds, perfect_ts)
        heat_accum += heat
    heat_mean = heat_accum / trials
    best_idx = heat_mean.argmax()
    i, j = np.unravel_index(best_idx, heat_mean.shape)
    best_pt = perfect_ts[i]
    best_th = angle_thresholds[j]
    best_accuracy = float(heat_mean[i,j])

    cohort_defaults[name] = {
        'angle_threshold': int(best_th),
        'perfect_t': float(best_pt),
        'great_t': float(best_pt + 2.0),
        'good_t': float(best_pt + 4.0),
        'accuracy': best_accuracy
    }

    cohort_summary.append({
        'cohort': name,
        'angle_threshold': best_th,
        'perfect_t': best_pt,
        'accuracy': best_accuracy
    })

# save results
with open('logs/cohort_results.csv', 'w') as f:
    f.write('cohort,angle_threshold,perfect_t,accuracy\n')
    for r in cohort_summary:
        f.write(f"{r['cohort']},{r['angle_threshold']},{r['perfect_t']},{r['accuracy']}\n")

os.makedirs('configs', exist_ok=True)
with open('configs/cohort_defaults.json', 'w') as f:
    json.dump(cohort_defaults, f, indent=2)

print('Saved cohort defaults to configs/cohort_defaults.json')
print(json.dumps(cohort_defaults, indent=2))
