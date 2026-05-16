# F18b.4m Hairer Outer Controller Remote Screen

Date: 2026-05-16 JST
Status: complete; valid affected-baseline readback, route decision pending

## Scope

This is the corrected opt-in screen for the Hairer outer-controller slice after
F18b.4j was invalidated by the missing official DFO-LS Python bridge.

Policy under test:

- `TLTM_ODE_CONTROLLER_POLICY=hairer_experimental`
- `TLTM_ODE_BACKEND=odex`
- official DFO-LS bridge enabled
- explicit `npt5_r0055` controls:
  `QN_OFFICIAL_DFOLS_NPT=5`, `QN_OFFICIAL_DFOLS_MAXFUN=500`,
  `QN_OFFICIAL_DFOLS_RHOBEG=0.055`, `QN_OFFICIAL_DFOLS_RHOEND=1e-16`
- true Stage2 RNG v2
- method-level solver assist off
- methods: `no_fb` and `fb_norefine`
- seeds: 10
- cycles per seed: 10000

## Local Execution Boundary

The user explicitly set the operational rule: do not run TLTM simulation screens
locally.  After that instruction, the in-progress local 10seed/10k F18b.4m run
was terminated and all remaining screen execution was moved to PBS.

Allowed local work for this line is limited to code inspection, file edits,
provenance/readback, and control-plane documentation.  TLTM Stage2/Stage3 screen
runs must use the remote PBS route.

## PBS Submission

Remote worktree:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization
```

The remote worktree is at base commit:

```text
243c09ceb99fd435b83b570db805174e6fa965ef
```

The current experimental source was rsynced to the remote worktree as a dirty
working tree.  The PBS job records `GIT_DIRTY_COUNT`, `git_status_short.txt`,
and `git_diff_stat.txt` in the output directory instead of pretending this is a
clean production commit.

Submitted jobs:

```text
15534.anode01  C16  failed before simulation: link could not find -lpython3.11
15535.anode01  C16  failed before simulation: .deps libpython symlink was broken
15536.anode01  C16  running after fallback to /usr/lib64/libpython3.11.so.1.0; cancelled at user request because paired 10-worker shape was too slow
15537.anode01  C16  completed with Exit_status=0; task-parallel replacement with ncpus=20, jobs=20, schedule=task
```

The earlier C12 submission `15533.anode01` was still queued with
`Insufficient amount of resource: Qlist`, so it was cancelled before execution
and replaced by the C16 jobs.  The `15534` and `15535` failures happened during
the PBS build/link step, before Stage2/Stage3 simulation began.

PBS script:

```text
codex/workspaces/fortran_modernization/tasks/pbs/f18b4m_hairer_outer_npt5_r0055_10seed_10k_20260516.pbs
```

Current artifact root:

```text
output/tests/f18b4n_hairer_outer_controller_npt5_r0055_10seed_10k_task20_20260516T170524_243c09ceb99f/paired
output/logs/f18b4n_hairer_outer_controller_npt5_r0055_10seed_10k_task20_20260516T170524_243c09ceb99f/paired
```

Initial boot/provenance readback passed:

- `PBS_JOBID=15537.anode01`
- `PBS_QUEUE=C16`
- `Resource_List.ncpus=20`
- `TLTM_RUN_JOBS=20`
- `SCHEDULE=task`
- `GIT_DIRTY_COUNT=45`
- `PYTHON_EMBED_LDFLAGS=/usr/lib64/libpython3.11.so.1.0 -lpthread -ldl -lutil -lm`
- `TLTM_ODE_CONTROLLER_POLICY=hairer_experimental`
- `QN_SOLVER_BACKEND=official_dfols`
- `QN_OFFICIAL_DFOLS_NPT=5`
- `QN_OFFICIAL_DFOLS_MAXFUN=500`
- `QN_OFFICIAL_DFOLS_RHOBEG=0.055`
- `TLTM_OFFICIAL_DFOLS_PYTHONPATH=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/.venv-dfols/lib/python3.11/site-packages`
- build/preflight reached the Stage3 run path; `run_tltm_stage2` and
  `evaluate_expectations` were already up to date from the repaired build
- qstat readback confirmed the task-parallel replacement is running on
  `cnode01/1*20`; Python runner output may be file-buffered until task output
  or completion artifacts are flushed

## Final Readback

PBS historical readback:

```text
15537.anode01  job_state=F  Exit_status=0  walltime=00:20:00
queue=C16      ncpus=20     cput=04:52:43
```

Generated artifacts:

```text
aggregated_summary_table.csv
per_seed_summary_table.csv
f18b4m_hairer_outer_npt5_r0055_10k_report.md
```

Manifest readback confirmed:

- `PBS_JOBID=15537.anode01`
- `GIT_DIRTY_COUNT=45`
- `CAMPAIGN=f18b4n_hairer_outer_controller_npt5_r0055_10seed_10k_task20_20260516T170524_243c09ceb99f`
- `SCHEDULE=task`
- `TASK_METHOD_ORDER=no_fb_first`
- `N_SEEDS=10`
- `CYCLES_PER_SEED=10000`
- `TLTM_ODE_CONTROLLER_POLICY=hairer_experimental`
- `QN_SOLVER_BACKEND=official_dfols`
- `QN_OFFICIAL_DFOLS_NPT=5`
- `QN_OFFICIAL_DFOLS_MAXFUN=500`
- `QN_OFFICIAL_DFOLS_RHOBEG=0.055`
- `QN_OFFICIAL_DFOLS_RHOEND=1e-16`
- `TLTM_OFFICIAL_DFOLS_PYTHONPATH=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/.venv-dfols/lib/python3.11/site-packages`

Log scan:

```text
ModuleNotFoundError                                      count=0   files=0
No module named dfols                                    count=0   files=0
QN solver backend=official_dfols                         count=10  files=10
official DFO-LS preset npt=5 maxfun=500                  count=10  files=10
rhobeg= 5.500E-02                                        count=10  files=10
Official DFO-LS bridge failed                            count=10  files=10
RuntimeError: TLTM residual callback failed              count=112 files=10
Traceback                                                count=112 files=10
```

The bridge-failure/residual-callback counts are not the F18b.4j environment
failure.  The accepted F18b.4b 10seed/10k reference has the same import/preset
shape, zero `ModuleNotFoundError`, and comparable residual-callback counts
(`119`), so this readback is valid for the controller route decision.

Aggregate comparison against accepted F18b.4b 10seed/10k:

| method | metric | F18b.4b accepted | F18b.4n hairer_experimental | delta |
| --- | ---: | ---: | ---: | ---: |
| `fb_norefine` | proposal failures | 166 | 164 | -2 |
| `fb_norefine` | reverse-gate rejects | 1274 | 1293 | +19 |
| `fb_norefine` | mean Re | 0.02311080440482635 | 0.01785509409267819 | -0.005255710312148162 |
| `fb_norefine` | mean Im | 0.004007786293613718 | -0.0027746433596665537 | -0.006782429653280271 |
| `fb_norefine` | Zmean Re | 0.4197458251236253 | 0.32496204954662317 | -0.09478377557700213 |
| `fb_norefine` | Zmean Im | 0.10935044927261645 | -0.08152739034564842 | -0.19087783961826488 |
| `fb_norefine` | mean runtime | 844.1522926 | 1122.4772538000002 | +278.3249612 (+32.97%) |
| `fb_norefine` | QN eval-flow successes | 1764442 | 1816036 | +51594 |
| `no_fb` | proposal failures | 8300 | 8253 | -47 |
| `no_fb` | reverse-gate rejects | 1076 | 1018 | -58 |
| `no_fb` | mean Re | 0.0019528482220934804 | 0.004357625029658546 | +0.002404776807565066 |
| `no_fb` | mean Im | -0.02786044660484825 | -0.030944450937682166 | -0.003084004332833918 |
| `no_fb` | Zmean Re | 0.03382818583627952 | 0.07533238767174515 | +0.04150420183546563 |
| `no_fb` | Zmean Im | -0.6644160270087625 | -0.705294915826479 | -0.04087888881771651 |
| `no_fb` | mean runtime | 494.7982082 | 634.8367814000001 | +140.0385732 (+28.30%) |

## Interpretation Boundary

This PBS run is an experimental affected-baseline screen for the opt-in
Hairer-controller slice.  It is not a clean production-comparison promotion
because the remote source is intentionally dirty and records patch provenance
through status/diff artifacts.

The corrected screen is valid evidence.  It rules out the F18b.4j interface/env
failure explanation and shows that the opt-in Hairer outer-controller slice is
not numerically catastrophic at this scale.  The failure/reverse-gate/observable
surface stays close to the accepted F18b.4b neighborhood.

It also shows a material runtime cost: about `+33%` for `fb_norefine` and
`+28%` for `no_fb`.  Therefore this screen should not promote
`hairer_experimental` to default behavior by itself.  The next route decision is
`keep opt-in and tune`, `accept the runtime cost for stronger paper alignment`,
or `remove/back out the outer-controller behavior and keep only the hardened
F18b.4i/F18b.4b default`.

## Cluster Parallelism Note

The paired 10-worker `15536` shape was cancelled because it serialized the
second method inside each seed and was taking too long.  The replacement
`15537` job uses full seed-method task parallelism: 20 CPUs, 20 jobs, and
`--schedule task`, so all 20 seed-method tasks enter the worker pool at once.
