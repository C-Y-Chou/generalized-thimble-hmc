# Stephanov N6 Four-Z Convergence - 2026-05-28

Common-prefix rows use the same prefix length for all 512 seeds in that method.
The all-available endpoint uses the current live data with `x_cycle = mean samples per seed`.

withfb common-prefix max: `5001`
nofb common-prefix max: `15001`

Selected z rows:

| method | cut | x cycle | seeds | samples | chiral Re z | chiral Im z | density Re z | density Im z |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| withfb | prefix_500 | 500.0 | 512 | 256,000 | -2.163 | -0.525 | +0.988 | -0.778 |
| withfb | prefix_1000 | 1000.0 | 512 | 512,000 | -1.180 | +0.406 | +0.409 | -0.288 |
| withfb | prefix_1500 | 1500.0 | 512 | 768,000 | -0.537 | +0.146 | -0.169 | +0.546 |
| withfb | prefix_2000 | 2000.0 | 512 | 1,024,000 | -0.886 | +0.744 | +0.052 | -0.779 |
| withfb | prefix_2500 | 2500.0 | 512 | 1,280,000 | -0.348 | +1.445 | -0.805 | -1.440 |
| withfb | prefix_3000 | 3000.0 | 512 | 1,536,000 | -0.800 | +1.529 | +0.153 | -1.664 |
| withfb | prefix_3500 | 3500.0 | 512 | 1,792,000 | -0.707 | +1.272 | +0.924 | -1.456 |
| withfb | prefix_5000 | 5000.0 | 512 | 2,560,000 | -1.741 | +1.801 | +1.555 | -1.864 |
| withfb | prefix_5001 | 5001.0 | 512 | 2,560,512 | -1.736 | +1.798 | +1.556 | -1.867 |
| withfb | all_available_endpoint | 5001.0 | 512 | 2,560,512 | -1.736 | +1.798 | +1.556 | -1.867 |
| nofb | prefix_500 | 500.0 | 512 | 256,000 | +0.535 | +0.071 | +0.351 | -1.254 |
| nofb | prefix_1000 | 1000.0 | 512 | 512,000 | +0.626 | +0.064 | -0.197 | -1.469 |
| nofb | prefix_1500 | 1500.0 | 512 | 768,000 | +0.824 | -0.536 | -0.451 | -0.852 |
| nofb | prefix_2000 | 2000.0 | 512 | 1,024,000 | +0.901 | -0.621 | -0.909 | -0.477 |
| nofb | prefix_2500 | 2500.0 | 512 | 1,280,000 | +1.270 | -0.409 | -0.883 | -0.926 |
| nofb | prefix_3000 | 3000.0 | 512 | 1,536,000 | +1.109 | -0.744 | -0.719 | -0.428 |
| nofb | prefix_3500 | 3500.0 | 512 | 1,792,000 | +1.113 | -0.358 | -0.708 | -0.340 |
| nofb | prefix_5000 | 5000.0 | 512 | 2,560,000 | +1.198 | -0.530 | -0.964 | +0.724 |
| nofb | prefix_7500 | 7500.0 | 512 | 3,840,000 | +0.555 | -0.945 | -0.266 | +0.382 |
| nofb | prefix_10000 | 10000.0 | 512 | 5,120,000 | +0.427 | -1.108 | -0.987 | +0.572 |
| nofb | prefix_15001 | 15001.0 | 512 | 7,680,512 | +0.962 | -1.027 | -0.535 | +0.266 |
| nofb | all_available_endpoint | 15001.0 | 512 | 7,680,512 | +0.962 | -1.027 | -0.535 | +0.266 |

Artifacts:

- `z_convergence_curve.csv`
- `z_convergence_curve.png`
- `withfb_prefix.dat`, `nofb_prefix.dat`
- `withfb_endpoint.dat`, `nofb_endpoint.dat`
