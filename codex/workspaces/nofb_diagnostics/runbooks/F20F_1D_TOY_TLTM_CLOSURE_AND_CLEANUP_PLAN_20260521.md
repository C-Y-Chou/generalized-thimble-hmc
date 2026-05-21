# F20F 1D Toy TLTM Closure And Cleanup Plan

Date: 2026-05-21 JST

Status: provisional closure and planning only. Do not rebuild the file library,
move remote outputs, or delete datasets until the active top-up finishes and is
read back.

## Current Scientific Closure

The one-dimensional toy model now supports a narrower and cleaner claim than
the original fallback-centered interpretation.

### What Is Demonstrated

Fixed flow time can fail as a sampling method at large enough flow time.

- At `t=0.3`, fixed-flow `no_fb` has many failures/rejections, but the paired
  `512 seeds x 200000 cycles` fixed-flow dataset did not show a meaningful
  `no_fb` versus `fb_norefine` observable or support difference.
- At `t=0.5`, fixed-flow `no_fb` is a genuine pathology: every seed stays in a
  single high-flow `Re z` sign sector and the real observable shifts to
  `mean_Ohat_re ~= -0.241256`.

Two-replica TLTM repairs the fixed-flow `t=0.5` undercoverage in this model.

- The `low005 = [0.05, 0.5]` ladder was the smallest tested TLTM ladder that
  restored high-flow sign motion in the short scan.
- Paired TLTM at `32 seeds x 50000 cycles` restored sign motion in both
  `no_fb` and `fb_norefine`.
- TLTM `no_fb`, low005, `L=1.0`, `nstep=2`, `32 seeds x 50000 cycles` gave
  `mean_Ohat_re = 0.0038188152`, `mean_Ohat_im = -0.0038477163`,
  `Zmean_re = 0.4332`, `Zmean_im = -0.5448`, with protocol audit `32/32 pass`.

Fallback improves numerical robustness, but this 1D model has not yet shown
that fallback is required for unbiased observables once TLTM is used.

- In paired TLTM `32 seeds x 50000 cycles`, `fb_norefine` reduced unresolved
  failures from `255406` to `11727`, but paired `no_fb - fb_norefine` was only
  `Z = -1.296` in Re and `Z = 0.709` in Im.
- In paired TLTM `32 seeds x 200000 cycles`, Re was still insignificant
  (`Z ~= -0.900`), while Im was a candidate signal (`Z ~= 2.995`).
- The independent top-up to 128 paired seeds did not support that Im candidate:
  topup96 had Im `Z ~= 0.864`, and the base32+topup96 combined128 result had
  Im `Z ~= 1.933`.

### Claim Boundary

Use this wording as the current paper-level boundary:

> In the 1D toy model, fixed-flow sampling at large flow time can create a real
> undercoverage and observable-bias pathology. A two-replica TLTM ladder repairs
> the fixed-flow pathology. The BTN fallback route substantially reduces solver
> failures, but this 1D evidence does not yet prove that fallback is necessary
> for unbiased TLTM observables.

Do not claim from this model alone:

- solver failures imply sampling bias;
- fallback is required for unbiased observables in TLTM;
- the 1D toy result is enough to justify the strongest BTN fallback claim;
- `no_fb` and `fb_norefine` have different distributions if raw distribution
  checks remain compatible.

The useful positive result is still strong: TLTM itself is necessary to repair
the fixed-flow `t=0.5` pathology in this stress test. The fallback claim should
be presented as robustness/solver-health evidence unless a later, harder model
leaves a stable observable shift.

## Final Merge State

The paired top-up method-level merge artifact is complete by direct invocation
of the existing merge script:

```text
output/tests/f20f_tltm_t050_pair_validation/
  f20f_tltm_t050_low005_pair_topup96_to128_x_200000cycles_8c76fdf710ff
```

Current state:

- top-up `no_fb` chunks `04..15` have 8 data rows each;
- top-up `fb_norefine` chunks `04..15` have 8 data rows each;
- direct method-level merge completed at `2026-05-21T20:51:20+09:00`;
- top-up method-level rows are `96/96` for both methods;
- protocol audit verdicts are `pass`;
- stale PBS merge job `16547` was cancelled after the direct merge completed.

Final 128seed readback combines:

```text
base32:
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8

topup96:
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_topup96_to128_x_200000cycles_8c76fdf710ff
```

Decision after top-up:

- paired Re remains insignificant: combined128 `Z ~= -0.772`;
- paired Im is below the gate: topup96 `Z ~= 0.864`, combined128
  `Z ~= 1.933`;
- seed-level distribution checks remain small (`Ohat_re` KS `0.125`,
  `Ohat_im` KS `0.140625`);
- close the 1D model as "TLTM repairs fixed flow; fallback improves robustness
  but has no demonstrated observable necessity here."

## Dataset Compatibility Policy

Many datasets are downward-compatible: a larger or combined dataset can replace
smaller raw datasets for physics evidence, while smaller runs remain useful as
compact provenance for parameter selection.

The cleanup rule is:

1. Keep raw roots only for the maximal dataset that is still needed to reproduce
   the current claim.
2. Keep compact readback packets for lower-scale scans that made decisions
   possible.
3. Do not keep duplicate raw `z_history.dat` or `phi_history.dat` payloads when
   a larger compatible raw root supersedes them.
4. Never delete a root that is needed as a component of a combined dataset.
5. Never delete while PBS jobs, held merges, or pending readback depend on the
   root.

## Minimal Evidence Set After Top-Up

Keep these raw or near-raw remote roots until publication decisions are made:

| Dataset | Keep level | Reason |
| --- | --- | --- |
| fixed-flow `t=0.3` 512seed x 200k paired | raw roots or stable archive | main negative-control evidence that failures alone did not bias observables |
| fixed-flow `t=0.5` nofb 128seed x 200k | raw root | positive fixed-flow pathology evidence |
| TLTM low005 paired 32seed x 200k base | raw root while combined 128 uses it | component of base32 + topup96 combined 128seed dataset |
| TLTM low005 paired topup96 x 200k | raw root | component of combined 128seed dataset |
| TLTM nofb low005 `L=1,nstep=2` 32seed x 50k | compact packet only after 128 nofb scale-up | speed and sanity gate, not final physics scale |
| TLTM nofb low005 `L=1,nstep=2` 128seed x 200k | pending; raw root if run after maintenance | nofb-only production-scale check for selected HMC parameters |

Keep these as compact readback/manifest only:

| Dataset | Compact reason |
| --- | --- |
| TLTM ladder scan 4seed x 5k | ladder-selection provenance |
| TLTM paired 32seed x 50k | early paired validation and finite-cycle motivation |
| fixed-flow L/epsilon short scans | HMC parameter-screen provenance, if results exist |
| failed queue attempts and merge repairs | scheduler provenance only; no raw scientific value |

Archive or delete candidates after compact packets exist:

- partial failed qsub roots with no job ids;
- duplicate chunk-level roots that were replaced by repair chunks;
- isolated worktrees whose only purpose was a completed or failed submission;
- old pre-F20F production-comparison outputs, unless they are explicitly cited
  as historical comparison.

## Worktree Cleanup Plan

Do this only after a cleanup dry-run manifest is prepared.

1. Freeze the dataset registry.
   - Update `codex/workspaces/nofb_diagnostics/state/F20F_DATASET_REGISTRY.tsv`.
   - Mark each dataset as `canonical_raw`, `compact_only`, `superseded`, or
     `delete_candidate`.
2. Write compact packets for every retained decision:
   - row counts;
   - aggregate tables;
   - protocol audit status;
   - source commit and config;
   - output/log root;
   - scheduler request id;
   - key metrics and interpretation boundary.
3. Generate a dry-run cleanup list.
   - Include path, size, owner line, replacement dataset, and reason.
   - Separate raw-output deletion candidates from worktree deletion candidates.
4. Confirm active-job safety.
   - `qstat -u cychou` must be empty or unrelated.
   - No held merge should depend on any deletion candidate.
5. Clean worktrees before raw data.
   - Remove stale isolated execution worktrees only after their commits,
     request rows, and output roots are registered.
   - Keep `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization` as the
     canonical remote execution/output root.
   - Do not touch the F23/stage2 worktree.
6. Delete or archive raw outputs only after explicit approval.
   - The first cleanup pass should be `dry_run`.
   - Prefer moving to an archive namespace over immediate deletion when the
     replacement relation is not trivial.

## Non-Goals Before Cleanup Approval

Do not do any of the following before the cleanup dry-run manifest is reviewed:

- rebuild the file library;
- delete or move remote output roots;
- prune isolated worktrees used by pending requests;
- rewrite dataset registry statuses as final.

## Immediate Post-Maintenance Action

After cluster maintenance:

1. Prepare the cleanup dry-run manifest.
2. Freeze the final F20F 1D toy summary packet.
3. Only after cleanup planning is settled, revisit the prepared
   `128seed x 200k` nofb-only `L=1,nstep=2` scale-up request.
