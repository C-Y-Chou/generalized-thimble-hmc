# Coding Style Guide

This guide defines repository-level conventions for readability, maintainability, and numerical reproducibility.

## 1. Naming Conventions

- Use `snake_case` for files, procedures, and local variables.
- Use `_mod` suffix for primary module names (example: `quasi_newton_solver_mod`).
- Keep file/module alignment when practical:
  - `foo_bar_mod.f90` should define `module foo_bar_mod`.
- Compatibility wrappers may keep legacy names, but must be clearly marked as transitional.
- Prefer action-oriented names for public procedures (example: `solve_constraint_newton`).

Recommended local naming patterns:

- loop counters: `*_idx`
- sizes/lengths: `*_size`
- booleans: `is_*`, `has_*`, `*_failed`

## 2. Module Structure

Use a consistent internal layout:

1. `use` statements and `implicit none`
2. type/parameter declarations
3. public subroutines/functions
4. local helper subroutines/functions

Within each subroutine:

1. argument declarations
2. local declarations
3. input validation
4. setup/allocation
5. main algorithm
6. cleanup and return

## 3. Output and Logging

- Prefer formatted `write` over `print *` for stable output.
- Use standardized status tags:
  - `[INIT]`, `[CHAIN]`, `[WARMUP]`, `[PROGRESS]`, `[SUMMARY]`, `[DONE]`, `[WARN]`, `[ERROR]`.
- Keep progress reporting cadence predictable (for example every fixed sample interval).
- Keep one concern per line (for example progress vs acceptance vs tolerance).

## 4. Error Handling

- Validate dimensions and assumptions early.
- For unrecoverable configuration or shape errors, use explicit diagnostics followed by `error stop`.
- For recoverable numerical failures, propagate error flags and keep caller behavior explicit.
- Avoid silent fallbacks unless they are intentionally documented.

## 5. Performance and Memory

- Avoid repeated allocate/deallocate in hot paths.
- Prefer reusable work buffers/workspaces for iterative kernels.
- Keep data movement explicit when converting between real and complex representations.
- Document any algorithmic tradeoffs affecting stability or performance.

## 6. Comments and Documentation

- Write comments for intent, not for obvious syntax.
- Document numerical assumptions near the relevant implementation.
- Mark transitional compatibility code so it can be removed safely later.
- Keep docs synchronized with actual runtime behavior (especially input formats and defaults).

## 7. Test and File Naming

- Test files should describe the checked behavior, e.g.:
  - `test_hamiltonian_conservation.f90`
  - `test_action_derivatives.f90`
- New modules should be placed in the correct layer and avoid cross-layer shortcuts.
