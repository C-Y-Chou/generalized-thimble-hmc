# M6 Queue Probe And Resubmission - 2026-05-10

Updated: 2026-05-10 19:45 JST

Scope: probe-first queue optimization for M6 reference dataset generation on `fortran_modernization_m6_active`.

Remote safety boundary:

- Active worktree: `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation`
- Branch: `codex/qn-error-handling-validation`
- Pinned commit: `a1028ad6d68eabfd6c400ec135b3df9cab1e4af2`
- Do not fast-forward, rename, or clean this worktree while active M6 jobs remain.

## Probe Result

Production-shape probe means `select=1:ncpus=8:mpiprocs=8:mem=16gb`.

| Job | Queue | State | Exit | Node | Interpretation |
| --- | --- | --- | --- | --- | --- |
| `14664` | `C8` | `F` | `0` | `cnode17` | production-shape probe passed |
| `14665` | `C12` | `F` | `0` | `cnode35` | production-shape probe passed |
| `14668` | `C12-LONG` | `F` | `0` | `cnode35` | production-shape probe passed |
| `14666` | `C16` | canceled while queued | `NA` | `NA` | no failure evidence; not useful for immediate optimization |
| `14667` | `F` | canceled while queued | `NA` | `NA` | no failure evidence; not useful for immediate optimization |

Conclusion:

- `C8`, `C12`, and `C12-LONG` are verified for the M6 8-core TLTM chunk shape.
- The `C8-LONG` replacement backlog was not a correctness failure, but it was a scheduling bottleneck.
- `C16` and `F` remain eligible fallback queues, but they did not provide immediate-start evidence in this probe.

## Replacement Action

The old queued chunks and held merges were superseded by cancel/resubmit/rebuild-merge, not by `qmove`.

Remote manifest:

```text
output/logs/fortran_modernization/reference_datasets/submit/probe_optimized_resub_20260510T193413.env
```

R3:

| Old job | Old state | New job | Queue | State at readback |
| --- | --- | --- | --- | --- |
| `14657` `m6R3fnofb02` | `Q` on `C8-LONG` | `14669` `m6R3pnofb02` | `C12` | `R` |
| `14658` `m6R3mergeF` | `H` | `14670` `m6R3mergeP` | `C8` | `H` |

R4:

| Old job | Old state | New job | Queue | State at readback |
| --- | --- | --- | --- | --- |
| `14645` `m6R4enofb04` | `Q` on `C8-LONG` | `14671` `m6R4pnofb04` | `C8` | `R` |
| `14649` `m6R4efbnorefine06` | `Q` on `C8-LONG` | `14672` `m6R4pfbnorefine06` | `C12-LONG` | `R` |
| `14660` `m6R4fnofb13` | `Q` on `C8-LONG` | `14673` `m6R4pnofb13` | `C12` | `R` |
| `14662` `m6R4ffbnorefine15` | `Q` on `C8-LONG` | `14674` `m6R4pfbnorefine15` | `C8` | `R` |
| `14663` `m6R4mergeF` | `H` | `14675` `m6R4mergeP` | `C8` | `H` |

## Current Interpretation

- Probe-first optimization worked: all replacement chunks started immediately.
- Merge jobs are correctly held on dependencies.
- The active remote worktree still has active pinned jobs, so local control-plane/source updates must not be pushed into that worktree until M6 jobs finish.

## Next Readback

- Monitor `14669` and `14670` for R3 completion and merge.
- Monitor `14671`, `14672`, `14673`, `14674`, and `14675` for R4 completion and merge.
- Once R3 merge completes, run full readback for R1-R3 while R4 may continue.
- Once R4 merge completes, run full M6 readback and update `state/M6_REFERENCE_PACKAGES.tsv`.
