# HWM-MET-001 Metropolis Reject Output Contract

Date: 2026-05-17 JST
Status: implemented and M4-passed

## Decision

HWM-MET-001 is the selected API-contract fix from
`HANDWRITTEN_MISMATCH_RESOLUTION_TABLE_20260516.md`:

`accepted=.false.` means the public `metropolis_step` output buffers
`x_new/z_new/j_new` represent the current stay-put state, not a discarded finite
proposal.

This does not change the live Markov-chain rule for current Stage1/Stage2
callers, which already commit the proposal only when `accepted=.true.`.  It
does make the direct API contract match the rejection-as-stay-put semantics used
for proposal construction failures and reverse-gate rejection.

## Source Patch

- `src/sampler/markovchain_metropolis.f90`
  - Finite ordinary Metropolis rejection now assigns:
    - `x_new = x`
    - `z_new = z`
    - `j_new = j`
    - `transition_status = metropolis_status_rejected`
- Existing proposal-failure, Hamiltonian-invalid, Delta-H-invalid, and
  reverse-gate-rejected paths already reset these buffers after the output-shape
  guard.
- Output-size mismatch remains the only exception because the caller-provided
  buffers have the wrong shape and cannot safely receive the current state.

## Focused Red-Green Evidence

Before the source patch, the new retained-core subtest found an ordinary finite
Metropolis rejection with `transition_status=metropolis_status_rejected`,
`proposal_failed=.false.`, and nonzero discarded-output drift:

- `dx = 8.7005E-06`
- `dz = 8.0468E-06`
- `dj = 6.3389E-07`

After the patch, the same focused target passed with the ordinary finite
rejection output reset:

```bash
TLTM_OFFICIAL_DFOLS_PYTHONPATH=<.venv-dfols site-packages> \
PYTHON=$PWD/.venv-dfols/bin/python \
make -C build FC=gfortran LDFLAGS= test_retained_core_rg_reject_identity
```

Relevant passing check:

```text
[CHECK] finite_metropolis_reject_output_reset ok=T found_reject=T status=1 ... dx=0 dz=0 dj=0
```

The same target still verifies the older reverse-gate rejection stay-put
contract and local transition accounting.

## F8 Statement

This is behavior/API relevant for direct `metropolis_step` callers, but it is
not expected to change current live-chain Stage1/Stage2 trajectories because
those callers already commit `x_new/z_new/j_new` only on accepted proposals.

The affected baseline for this patch is therefore the retained-core Metropolis
API harness plus full M4 guardrails.  A remote simulation screen is not required
for this source slice unless a later caller is found to have been using rejected
output buffers as proposal diagnostics or state.

Full M4 passed after the patch:

```bash
TLTM_OFFICIAL_DFOLS_PYTHONPATH=<.venv-dfols site-packages> \
PYTHON=$PWD/.venv-dfols/bin/python \
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

## Claim Boundary

This closes only the HWM-MET-001 output-buffer API caveat.  It does not prove
universal paper-correctness for all Metropolis/HMC/RATTLE behavior, and it does
not close the remaining RATTLE rejection-as-stay-put proof/test packet.
