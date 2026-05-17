# HWA-STAGE2/RNG Protocol Line Audit

Date: 2026-05-17 JST

Status: implemented for the current Stage2 swap/RNG protocol scope. Focused
tests passed; the combined HWA batch later passed full M4.

## Scope

This packet covers:

- Stage2 local-update, swap, measurement, label-trace, and history ordering in
  `src/sampler/tltm_stage2_driver.f90`;
- counter-based Stage2 RNG v2 primitives in `src/core/tltm_rng.f90`;
- explicit MT95 stream-state compatibility in `src/core/mt95.f90` and
  `src/core/mtdefs.f90`;
- public effective-energy and phase gates used by Stage2 swap/history paths;
- focused tests in `tests/test_tltm_swap_kernel_contract.f90`,
  `tests/test_tltm_rng_contract.f90`, and `tests/test_mt95_state_contract.f90`.

This packet does not claim final production-output regeneration. It is a
source-level protocol and unit/guardrail packet.

## Protocol Readback

The active Stage2 cycle order is:

```text
local updates -> adjacent swap sweep -> refresh label positions ->
round-trip bookkeeping -> measure every slot -> optional histories ->
label trace
```

Cycle zero is initialized separately: slots are initialized, measured once, label
positions are refreshed, round-trip bookkeeping is initialized, and label trace
cycle zero is written.

The adjacent-swap kernel:

1. computes current effective energies for `slot_a` and `slot_b`;
2. rejects immediately if either current energy is invalid;
3. proposes cross-flow states by copying the other slot's seed state and setting
   the target flow time;
4. reflows both proposed states with strict `flow(...)`;
5. computes proposed effective energies;
6. rejects immediately if either proposed energy is invalid;
7. computes `delta = (E_ap + E_bp) - (E_a + E_b)`;
8. sets `acc_prob = 1` for `delta <= 0`, otherwise `exp(-delta)`;
9. draws one swap random number only after all current and proposed energies are
   finite;
10. on accept, swaps the live `x/z/jac` payloads and mobile `label_id`;
11. on reject, leaves both live slots and labels unchanged.

The current Stage2 RNG contracts are:

- `stage2_kernel_rng_v2`: counter-based Philox4x32-10 domains. Local momentum
  uses `stage2_local_momentum`, local Metropolis accept uses
  `stage2_local_accept`, and swap accept uses `stage2_swap_accept`.
- `per_replica_rng_v1`: explicit MT95 state per slot plus one swap stream.
- `legacy_global_v0`: compatibility shared serial MT95 stream.

The active default remains `stage2_kernel_rng_v2`; older modes are compatibility
or anchor/audit paths.

## Findings And Handling

### HWA-STAGE2-001: Effective-energy gate was too permissive

Finding: `compute_effective_energy(z, jac, energy, ok)` rejected singular or
non-square Jacobians through `log_determinant`, but did not require `size(jac)`
to match `size(z)`. It also did not reject nonfinite action/logdet-derived
energies, allowing an invalid value to reach the swap-probability surface.

Handling: implemented source hardening in `src/sampler/tltm_stage2_driver.f90`.

- `jac` must be square with dimension equal to `size(z)`.
- nonfinite real energy or nonfinite action/logdet imaginary components return
  `ok=.false.` and `energy=0`.
- invalid current/proposed energies therefore follow the existing reject path:
  proposal counted, accept probability set to zero, live slots and labels
  unchanged.

### HWA-RNG-001: RNG domain separation and replay proof

Finding: Stage2 RNG v2 is intentionally counter-based and should not depend on
interleaving or task scheduling. The relevant proof surface is domain separation
and deterministic replay for the same key tuple.

Handling: no source change required in this packet. Existing focused tests
already check Philox known-answer vectors, deterministic normal replay,
update-index sensitivity, and local momentum vs local accept domain separation.

### HWA-RNG-002: MT95 compatibility state must include Gaussian spare state

Finding: the compatibility MT95 stream path remains relevant for anchors and
legacy audits. Its explicit state must include Box-Muller spare state, otherwise
Gaussian momentum replay can drift after stream save/restore.

Handling: no source change required in this packet. Existing focused tests check
that `mt95_state_t` captures Gaussian spare state, supports interleaved stream
replay, and `sgrnd` resets the spare state.

## Proof Tests

Passed locally:

```bash
make -C build test_tltm_swap_kernel_contract
make -C build test_tltm_rng_contract
make -C build test_mt95_state_contract
```

Key checks:

- valid adjacent swap computes the replica-exchange probability from TLTM
  effective-energy deltas;
- accepted swap moves labels and reflowed payloads together;
- rejected swap keeps labels and live payloads unchanged;
- invalid current energy rejects with zero acceptance probability;
- `compute_effective_energy` rejects `z/J` dimension mismatch and nonfinite
  action/logdet-derived energy;
- phase factor rejects `z/J` mismatch with neutral-error output;
- Philox4x32-10 known-answer vectors pass;
- counter-based RNG draws are deterministic and domain separated;
- explicit MT95 state preserves Gaussian spare state and interleaved streams.

## F8 Statement

This packet is behavior/API relevant only for invalid Stage2 energy inputs. The
valid swap/RNG protocol is intended to be unchanged. No local TLTM Stage2/Stage3
simulation screen was run; only focused local guardrail tests were run. Full M4
and any affected-baseline decision remain required before using this batch for
production-comparison synchronization or regeneration.

## Current Scope Closure

HWA-STAGE2 and HWA-RNG are closed for the current Stage2 protocol/RNG unit
scope: cycle ordering, swap kernel state transitions, Stage2 RNG v2 domain
separation, MT95 compatibility replay, and invalid energy fail-closed handling.

Reopen if the Stage2 cycle order, measurement boundary, label/slot semantics,
RNG stream contract, swap acceptance draw boundary, output schema, history
sampling policy, precision/tolerance profile, or production-redo contract
changes.
