# TLTM Codex Workspace

This folder is the Codex control plane for the TLTM Fortran modernization
workspace.

## Active Entry Point

Read these first:

1. `codex/runbooks/MODERNIZATION_WORKFLOW.md`
2. `codex/runbooks/MODERNIZATION_STATUS.md`

Do not start by searching dated generated runbooks.  Generated runbooks are
evidence packets and should be opened only when the modernization status points
to them.

## Local Roots

Local checkout and remote runtime paths are user-specific.  Do not encode them
in public documentation or public milestone evidence.

## Cluster Rule

Production-scale validation should use an authorized scheduler workflow for the
target cluster.  The scheduler implementation, queue ledgers, source pins, and
repair records are local control-plane state; they are not part of the public
repository surface.

Any compact evidence derived from cluster jobs must be summarized through
`codex/runbooks/MODERNIZATION_STATUS.md` before it is used in a readback.

## Active Scientific Boundary

- TLTM production default: canonical `nofb`.
- fallback-assisted solver routes: legacy diagnostic, not an active product
  dependency.
- WV-HMC: dense explicit-J sibling sampler path under validation.
- Matrix-free/BiCGStab WV-HMC and deep reentrancy work: deferred until the
  current dense validation and product-readiness gate are closed.
