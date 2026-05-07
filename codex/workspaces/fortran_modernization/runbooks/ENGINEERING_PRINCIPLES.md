# TLTM Engineering Principles

## 1. Physics preservation is mandatory
- The modernization effort is not allowed to change the underlying physical model, action definition, target distribution, or accepted scientific interpretation.
- Any proposed change that alters physics, algorithm semantics, or experimental policy must be treated as a separate scientific decision, not as a refactor.

## 2. Behavior preservation is the default
- Structure-only refactors must preserve outputs exactly for the same configuration and seed whenever practical.
- Changes that touch floating-point execution paths must preserve scientific behavior and remain within pre-agreed numerical tolerances, backed by before/after evidence.
- No silent shifts in solver policy, fallback routing, acceptance logic, or runtime defaults.

## 3. Separate mechanism from policy
- Numerical kernels, solver strategy, runtime policy, and diagnostics must not remain entangled.
- Research toggles and ablation controls must not obscure the core algorithm contract.

## 4. Prefer explicit contracts over hidden state
- Reduce dependence on global variables, module-level hidden state, and implicit coupling.
- Make data ownership, input/output expectations, and failure modes explicit.

## 5. Stabilize before optimizing
- Add tests, benchmarks, and observability around a behavior before refactoring it.
- Do not chase performance or cleanliness ahead of verification.

## 6. Design for scientific reproducibility
- Configuration, seeds, runtime knobs, and generated artifacts must remain traceable.
- Reproduction of key reference outputs is part of the product definition.

## 7. Product quality matters
- The end state is not just usable research code; it should be understandable, maintainable, reviewable, and publication-ready.
