# TLTM Codex L0 Boot

Generated: 2026-05-10T19:55:02+09:00
Remote refreshed: 2026-05-10T19:36:11+09:00

## Hard Rules

- Heavy TLTM execution must use PBS compute nodes, not the login/frontend node.
- Before remote SSH/PBS/git cleanup work, run `bash codex/tasks/refresh_remote_state.sh` and `bash codex/tasks/render_l0_boot.sh`.
- If a remote worktree has active pinned jobs, do not fast-forward or clean it.
- For cluster02 queue choice, work splitting, submission, or job repair, use the cluster02 scheduling agent.
- Do not use `qmove` as the official repair path; cancel/resubmit/rebuild dependencies.
- Default read set is `HANDOFF_MIN -> L0_BOOT -> L1_INDEX -> chosen workspace STATE_BRIEF`.

## Active Remote Risk

- `fortran_modernization_m6_active`: branch `codex/qn-error-handling-validation`, commit `a1028ad6d68eabfd6c400ec135b3df9cab1e4af2`, 35 active jobs, examples: 14579.anode01,14580.anode01,14581.anode01,14582.anode01,14583.anode01,14584.anode01,14595.anode01,14596.anode01, pinned `a1028ad6d68eabfd6c400ec135b3df9cab1e4af2`. Do not fast-forward.

## Active/Pending Jobs

- `14579.anode01` `m6R4nofb00` queue `C8` state `R` dataset `m6_r4_128seed_100k`.
- `14580.anode01` `m6R4fbnorefine00` queue `C8` state `R` dataset `m6_r4_128seed_100k`.
- `14581.anode01` `m6R4nofb01` queue `C8` state `R` dataset `m6_r4_128seed_100k`.
- `14582.anode01` `m6R4fbnorefine01` queue `C8` state `R` dataset `m6_r4_128seed_100k`.
- `14583.anode01` `m6R4nofb02` queue `C12` state `R` dataset `m6_r4_128seed_100k`.
- `14584.anode01` `m6R4fbnorefine02` queue `C12` state `R` dataset `m6_r4_128seed_100k`.
- `14595.anode01` `m6R4nofb08` queue `F` state `R` dataset `m6_r4_128seed_100k`.
- `14596.anode01` `m6R4fbnorefine08` queue `F` state `R` dataset `m6_r4_128seed_100k`.
- `14597.anode01` `m6R4nofb09` queue `G` state `R` dataset `m6_r4_128seed_100k`.
- `14598.anode01` `m6R4fbnorefine09` queue `G` state `R` dataset `m6_r4_128seed_100k`.
- `14599.anode01` `m6R4nofb10` queue `C8-LONG` state `R` dataset `m6_r4_128seed_100k`.
- `14600.anode01` `m6R4fbnorefine10` queue `C8-LONG` state `R` dataset `m6_r4_128seed_100k`.
- ... 23 more jobs in `codex/state/JOBS.tsv`.

## High-Priority Open Items

- `CP-001` control_plane: Keep L0/L1 current after remote/job changes Next: Run refresh_remote_state and render_l0_boot before remote/PBS work
- `CP-003` cluster02: Record new queue failures/successes into scheduler observations Next: Use fresh qstat/probes for current scheduling; record notable future outcomes as priors, not fixed availability

## Recent Decisions

- 2026-05-10 `cluster02`: Blacklist C17/C17-LONG for M6 8-core chunk shape
- 2026-05-10 `cluster02`: Prefer probe-verified C8/C12 and use C12-LONG as pressure release for M6 chunks
- 2026-05-10 `cluster02`: Treat cluster02 as a shared dynamic resource rather than a fixed machine
- 2026-05-10 `fortran_modernization`: Track modernization by workstream matrix, not linear M0-M6 completion
- 2026-05-10 `stage3_4`: Stage3_4 queue optimization playbook is superseded for current scheduling
- 2026-05-10 `remote`: Rename control-plane target id to fortran_modernization_m6_active

## Pointers

- L1 index: `codex/indexes/L1_INDEX.tsv`
- Remote live cache: `codex/state/REMOTE_LIVE_CACHE.json`
- Jobs: `codex/state/JOBS.tsv`
- Worktrees: `codex/state/WORKTREES.tsv`
- Control-plane plan: `codex/runbooks/CONTROL_PLANE_MEMORY_COMPACTION_PLAN.md`
- Read policy: `codex/runbooks/READ_POLICY.md`
