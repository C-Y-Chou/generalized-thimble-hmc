# WV-HMC Fast Detection Plan 2026-06-02

Purpose: find the implementation layer that can bias WV-HMC observables without relying on long-chain tuning.

## Principle

Do not use lower failure rate, long validation z-score, or parameter tuning as the first diagnostic. First audit whether the transition kernel preserves the target distribution identities expected of the algorithm.

## Fast Gates

1. Math local identities
   - complex action directional derivative vs manual gradient;
   - tangent/normal flow RHS convention;
   - projection reconstruction and orthogonality;
   - nonzero `W'(t)` force finite difference.

2. Constraint/RATTLE identities
   - Newton residual decreases and reaches tolerance;
   - RATTLE constraint residual after each step;
   - forward/reverse one-step recovery;
   - forward/reverse Hamiltonian antisymmetry.

3. Integrator order
   - fixed trajectory length with halved step size must reduce `|Delta H|` with second-order-compatible scaling;
   - fail if the slope is clearly below a reversible second-order integrator expectation.

4. Boundary/reflection policy
   - current implementation self-consistency: boundary bounce is involutive and energy-preserving on tangent momentum;
   - simplified-paper policy gate: boundary exit maps `(z, pi)` to `(z, -pi)`;
   - a failure of the paper-policy gate with other identities passing localizes the issue to the current normal-reflection deviation.

5. Transition-level identities
   - reverse gate state/momentum errors;
   - Metropolis probability uses the same `Delta H` as the trajectory;
   - construction failures remain stay-put rejected proposals unless they are classified as boundary exits.

6. Minimal observable oracle
   - after gates 1-5 pass, use `n=2`, `T0=0`, small `T1`, no sign-problem regime;
   - if observables still fail, the remaining suspects are target density, measurement factor, or initialization/mixing.

## First Execution Batch

Add deterministic tests to the existing cluster-only WV-HMC test target:

- paper full-flip boundary rule gate;
- stronger fixed-length `Delta H` order gate;
- forward/reverse `Delta H` antisymmetry gate.

Run through `cluster02_qsub_gate.sh`; do not run local Fortran simulation.

## Interpretation

- If paper full-flip fails but normal-reflect self-consistency passes: boundary policy is a likely implementation deviation to test by changing the default policy.
- If energy order or forward/reverse `Delta H` antisymmetry fails: the bug is in RATTLE/Newton/force/Hamiltonian, not measurement.
- If all kernel gates pass but n=2 observables remain biased: focus on target density, measurement factor, and state-bank/mixing.
