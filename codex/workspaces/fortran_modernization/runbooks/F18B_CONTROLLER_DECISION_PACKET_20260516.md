# F18b Controller Decision Packet

Date: 2026-05-16 JST
Scope: handwritten endpoint ODEX controller surfaces in
`src/physics/odex_backend.f90`.
Status: recommended F18b.2 policy packet; no production ODEX behavior change.

## Decision Summary

F18b.2 keeps the handwritten ODEX backend as TLTM-owned endpoint code, freezes
the current controller behavior as the modernization baseline, and does not
patch the controller toward full Hairer ODEX in this slice.

The accepted claim is deliberately narrow:

```text
TLTM uses an endpoint-only ODEX/GBS-family extrapolation backend with Hairer
IWORK(3)=3 step numbers, deterministic TLTM controller policy, and explicit
failure-as-no-endpoint behavior for downstream rejection/reverse-gate handling.
```

The blocked claim remains:

```text
The controller is a complete paper-exact Hairer ODEX implementation.
```

Rationale:

- F18 CVODE comparison did not produce a better canonical route.
- F18b.1 now freezes current controller behavior with deterministic observation
  tests.
- No immediate current-route source bug was found in the all-handwritten audit.
- Changing `h0`, h-min, order predicates, growth/shrink bounds, or stability
  defaults would change the proposal/failure surface and therefore needs a
  separate F8/M4/affected-baseline patch.

## Decisions By Surface

| Surface | F18b.2 decision | Paper-correctness status | Future patch policy |
| --- | --- | --- | --- |
| Endpoint-only scope | Accept as TLTM product boundary. | Product-scope decision, not full ODEX. | Reopen only if dense output or general ODE solving becomes product scope. |
| `IWORK(3)=3` sequence | Accept as TLTM endpoint policy. | Matched to selected Hairer sequence. | Any change requires F8, focused tests, M4, and affected baseline. |
| `calculate_ak` / positive `calculate_wk` | Accept as TLTM endpoint policy paired with signed intervals. | Paper-aware work estimate; positive `abs(h)` handling is TLTM robustness for signed endpoints. | Reopen only if sequence or work model changes. |
| Signed interval handling | Accept current signed `h` propagation with positive work estimate. | Numerically sound for endpoint forward/backward use; not a full controller proof. | Behavior-changing sign/work patch requires forward/backward and affected-baseline gates. |
| `h0 = t * initial_step_fraction` | Accept as current TLTM endpoint policy for modernization closure. | TLTM-specific, not paper-exact Hairer initial-step logic. | Hairer-inspired estimator is a separate behavior-changing candidate only if selected. |
| h-min floor and h-min status | Accept current TLTM failure-floor policy. | TLTM-specific failure policy. | Min-step replacement needs F8, failure-surface tests, and affected baseline. |
| Missing explicit `WORK(4)`/`WORK(5)` bounds | Defer; do not add bounds now. | Not full Hairer controller. | Candidate behavior-changing patch if performance/stability evidence demands it. |
| Order promotion/demotion predicates | Preserve current predicates for modernization closure. | TLTM-specific; not paper-signed. | Any alignment patch needs branch tests plus affected baseline. |
| Rejected-step behavior | Accept current reject-and-retry/failure classification as TLTM policy. | MCMC legality comes from no-endpoint rejection, not from ODEX paper exactness. | No best-candidate rescue without explicit MCMC/proposal-surface packet. |
| Large-error threshold `(k*k + 1)**2` | Preserve current threshold. | TLTM-specific controller heuristic. | Patch only as part of an order-controller alignment family. |
| Error floor `1.0e-14` | Preserve current floor under strict double baseline. | TLTM-specific numeric guard. | Revisit in F20 precision/tolerance profiles, not here. |
| Default stability control | Keep default `none`. | Product policy; current baseline does not use conservative stability rejection. | Enabling by default is behavior-changing and needs affected baseline. |
| Optional conservative stability branch | Keep as explicit opt-in diagnostic/control surface. | Not canonical paper claim. | Reopen only with explicit product-policy decision. |
| CVODE backend | Keep disabled-by-default comparison only. | Mature-package comparison evidence, not canonical route. | Reopen only if a new package route is selected. |

## F8 Classification

No behavior-changing source patch is authorized by this packet.

If a later patch changes a controller surface, classify it as follows:

| Patch family | F8 class | Minimum evidence before scale-up |
| --- | --- | --- |
| Initial-step estimator | behavior-changing solver-controller patch | focused controller tests, M4, 1k paired screen before any 10k run |
| h-min/min-step replacement | behavior-changing failure-surface patch | h-min failure tests, M4, affected baseline on both `no_fb` and `fb_norefine` |
| explicit growth/shrink bounds | behavior-changing proposal-surface patch | branch tests, M4, small paired screen |
| order threshold alignment | behavior-changing proposal-surface patch | branch tests that hit demote/keep/promote/reject paths, M4, small paired screen |
| default stability enablement | behavior-changing failure-surface patch | conservative-stability tests, M4, small paired screen |
| error-floor/tolerance change | behavior-changing tolerance/precision patch | F20 precision profile packet plus paired baseline |

## Immediate Consequence

F18b controller policy is closed for source modernization at the current
behavioral baseline, but universal paper-correctness remains blocked.

Next source-facing work should not be an ODEX controller behavior patch unless
the user explicitly selects one of the candidate patch families above.  The
lower-risk next modernization slice is F18b.3: ODEX/flow state productization
for counters, traces, and last-failure snapshots, preserving the current
solver kernel and output contracts.

The F18b.3 decision packet is
`F18B3_ODEX_FLOW_STATE_AND_BEHAVIOR_CORRECTION_DECISION_20260516.md`.  Its
behavior-correction rule is: state migration is allowed only if it preserves
current public counters/status/output; any discovered counter/schema/status
semantic fix must stop and become a separate F4/F7/F8 behavior-correction
packet; any endpoint/final-flow/reverse-gate/proposal change remains a separate
numerical behavior change.
