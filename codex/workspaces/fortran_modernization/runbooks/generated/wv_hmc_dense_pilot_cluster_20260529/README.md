# WV-HMC Dense Pilot Cluster Readback 20260529

Scope: pre-matrix-free WV-HMC dense backend pilot on Stephanov `n=2`.

Execution policy: no local simulation evidence is used here.  Both runs were
executed on cluster02 through `cluster02_qsub_gate.sh` from the detached
isolated worktree
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_wv_pilot_01f58ba`.

## Cluster Jobs

| job | queue/node | commit | grid | cycles | result | scan real time | artifacts |
|---|---|---|---|---:|---|---:|---|
| `17913.anode01` | `C8` / `cnode17` | `02d2891` | `initial` | 100 | exit 0; WV math + constraint tests passed | 18.43 s | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_pilot_20260529/wv_hmc_dense_pilot_scan_20260529_17913.anode01` |
| `17914.anode01` | `C8` / `cnode17` | `b75c5a8` | `wall_epsilon` | 200 | exit 0; WV math + constraint tests passed | 28.55 s | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_pilot_20260529/wv_hmc_wall_epsilon_scan_20260529_17914.anode01` |

## Initial Grid

| label | W profile | eps | nstep | L | accepted | RG reject | fail | flow mean | flow max | phase coherence |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `flat_eps0p0005_s5` | zero | 0.0005 | 5 | 0.0025 | 100/100 | 0 | 0 | 0.002470 | 0.005408 | 0.999073 |
| `flat_eps0p001_s5` | zero | 0.001 | 5 | 0.005 | 100/100 | 0 | 0 | 0.006731 | 0.017493 | 0.995760 |
| `flat_eps0p003_s1` | zero | 0.003 | 1 | 0.003 | 99/100 | 1 | 0 | 0.002467 | 0.006009 | 0.998629 |
| `wall_g0p2_eps0p0005_s5` | paper wall | 0.0005 | 5 | 0.0025 | 100/100 | 0 | 0 | 0.010133 | 0.017387 | 0.994944 |
| `wall_g1_eps0p0005_s5` | paper wall | 0.0005 | 5 | 0.0025 | 100/100 | 0 | 0 | 0.010141 | 0.017402 | 0.994949 |
| `wall_g1_eps0p001_s5` | paper wall | 0.001 | 5 | 0.005 | 98/100 | 0 | 1 | 0.022719 | 0.053619 | 0.997246 |
| `wall_g1_eps0p001_s1` | paper wall | 0.001 | 1 | 0.001 | 100/100 | 0 | 0 | 0.006386 | 0.007932 | 0.998789 |
| `wall_g1_eps0p003_s1` | paper wall | 0.003 | 1 | 0.003 | 100/100 | 0 | 0 | 0.012086 | 0.022761 | 0.994857 |

Readback: flat `W(t)` still concentrates near small flow time.  A tilted wall
profile moves the chain to larger flow time, so `epsilon`/`L` must be retuned
under the tilted profile.

## Wall-Epsilon Grid

Fixed profile: `paper_wall`, `gamma=1`, `T0=0.005`, `T1=0.2`, `d0=0.005`,
`d1=0.05`.

| label | eps | nstep | L | accepted | RG reject | fail | flow mean | flow max | phase coherence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `wall_g1_eps0p001_s1` | 0.001 | 1 | 0.001 | 200/200 | 0 | 0 | 0.006980 | 0.009148 | 0.992043 |
| `wall_g1_eps0p002_s1` | 0.002 | 1 | 0.002 | 197/200 | 0 | 3 | 0.010932 | 0.020324 | 0.963915 |
| `wall_g1_eps0p003_s1` | 0.003 | 1 | 0.003 | 183/200 | 6 | 11 | 0.018638 | 0.040894 | 0.974608 |
| `wall_g1_eps0p005_s1` | 0.005 | 1 | 0.005 | 172/200 | 8 | 20 | 0.022162 | 0.061186 | 0.967616 |
| `wall_g1_eps0p008_s1` | 0.008 | 1 | 0.008 | 145/200 | 22 | 32 | 0.020347 | 0.082597 | 0.931567 |
| `wall_g1_eps0p002_s2` | 0.002 | 2 | 0.004 | 194/200 | 2 | 3 | 0.034643 | 0.107113 | 0.974106 |
| `wall_g1_eps0p003_s2` | 0.003 | 2 | 0.006 | 170/200 | 7 | 22 | 0.075886 | 0.196413 | 0.984431 |
| `wall_g1_eps0p005_s2` | 0.005 | 2 | 0.010 | 162/200 | 14 | 23 | 0.082212 | 0.199416 | 0.945999 |

## Pre-Matrix-Free Working Point

Use `paper_wall gamma=1`, `T0=0.005`, `T1=0.2`, `d0=0.005`, `d1=0.05`,
`epsilon=0.002`, `nstep=2` as the current conservative dense working point.

Reason: it moves substantially beyond the small-flow region (`flow_mean ~
0.0346`, `flow_max ~ 0.107`) while keeping pressure moderate in the 200-cycle
pilot (`194/200` accepted, `2` reverse-gate rejects, `3` construction
failures).  `epsilon=0.003, nstep=2` reaches deeper (`flow_mean ~0.0759`) but
already has much higher failure pressure (`7` reverse-gate rejects, `22`
construction failures).

This is not a physics-production setting.  It is the dense-oracle starting
point for matrix-free / BiCGStab trajectory wiring and later high-dimensional
WV-HMC tuning.
