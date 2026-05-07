# ngport RG Single-Replica Grid Status

Updated: 2026-05-01 10:52 JST

## Active objective
- Run ngport-style matched-control sweep with RG enabled using a **single-layer chain design**.

## Scope
- Added checkpoints requested by user:
  - `tau=0.20, nstep=20, L=2`
  - `tau=0.35, nstep=20, L=2`
- Step-scan backbone at `tau=0.30`:
  - `nstep={10,15,20,30,40}`

## Condition matrix
Unique physics points: `7`
Methods (`no_fb`, `fb`) applied to each point: total `14` conditions.

## Single-layer sampling design
- Statistical unit: chain
- No external seed layer in experiment design
- Cluster settings:
  - `chains_per_job = 20`
  - `jobs_per_condition = 3`
  - `chains_total_per_condition = 60`
  - `samples_per_chain = 200000`

### Derived totals
- `total_samples_per_condition = 60 * 200000 = 12,000,000`
- `total_job_runs = 14 * 3 = 42`
- `total_chain_runs = 14 * 60 = 840`

## Wave plan
### Wave-1 (first step): 6 conditions
- `c01,c02` : `(tau=0.20, nstep=20)` no_fb/fb
- `c07,c08` : `(tau=0.30, nstep=20)` no_fb/fb
- `c13,c14` : `(tau=0.35, nstep=20)` no_fb/fb

Purpose: verify low/mid/high flow-time behavior first under the same `nstep=20` and RG-on policy.

### Wave-2: remaining 8 conditions
- `tau=0.30` step-scan complements:
  - `nstep=10,15,30,40` with both methods

## Current state
- Redesign completed and recorded.
- Submission scripts are not submitted yet.

## Next actions
1. Submit Wave-1 (6 conditions) first.
2. Check runtime and failure profile, then release Wave-2.
3. Refresh live board and append queue log.
