# Stephanov HMC Protocol Tuning Policy - 2026-05-22

## Scope

This records the active tuning policy for Stephanov `n=6` nofb development.
It supersedes ad hoc scans that used `L` as the primary scan variable or tried
to reduce nofb proposal failures during protocol selection.

## Policy

Tune HMC protocol in the standard HMC order:

1. Decide the integrator step size
   `epsilon = trajectory_length / integration_steps`.
2. With `epsilon` fixed, decide trajectory length through `nstep`
   (`L = epsilon * nstep`).
3. Only after the HMC protocol is fixed, run nofb flow-time physics/sign-problem
   tests.

Do not use nofb proposal failure minimization as a separate tuning objective.
Proposal failures still count as local-update attempts: the primary acceptance
reported for protocol scans is
`accepted / (accepted + metropolis_reject + proposal_failure)`.  A secondary
conditional Metropolis acceptance may be reported for diagnostics, but it must
not replace attempt acceptance when choosing `epsilon`, `nstep`, or `L`.

In nofb, proposal failures are also diagnostic output for the selected protocol
and flow time.  Reducing them by shrinking `epsilon` or `L` can hide the
geometry/flow difficulty that nofb is supposed to expose.

## Epsilon Selection

The epsilon scan should test bounded short runs and reject only protocols that
are not operational:

- catastrophic timeout or no samples produced,
- clear invalid-Hamiltonian / invalid-delta-H behavior,
- runtime per proposal so large that the protocol cannot support development,
- attempt acceptance clearly too low for useful HMC.

Attempt acceptance is a guide for step-size scale, not the final objective.
High acceptance by itself is not evidence of a good protocol; it can mean the
step size or trajectory is too conservative.  A Stan-like target around `0.8`
is a reasonable reference scale for choosing `epsilon`, but the final decision
must also consider whether the selected protocol gives useful movement and
stable finite samples.

## Trajectory-Length Selection

After choosing `epsilon`, scan small `nstep` values first (`nstep < 10` for the
current local development phase).  Compare movement/decorrelation proxies per
wall time, not acceptance alone.  This is the stage where `L` is selected.

## nofb Flow Tests

For nofb flow-time tests, report proposal failures as part of the result
alongside phase coherence, observable error bars, attempt acceptance, and
runtime.
Do not retune the HMC protocol just to make nofb failure rates smaller unless
the selected protocol cannot produce usable samples at all.
