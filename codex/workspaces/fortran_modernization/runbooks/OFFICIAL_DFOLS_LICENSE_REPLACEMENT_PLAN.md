# Official DFO-LS License and Production Replacement Plan

Updated: 2026-05-11 JST

## Purpose

This note records the license decision needed before replacing the TLTM in-house BTN/QN solver with the official DFO-LS implementation in production.

This is an engineering compliance plan, not legal advice. If TLTM will be distributed as a public or institutional product, the final license choice should be reviewed by the project owner and, if needed, counsel or the institution's software/IP office.

## Confirmed Facts

Local TLTM license state:

- Before the 2026-05-11 license cleanup, the repository only contained
  `docs/LICENSE`, and that file was the MIT License.
- The user explicitly decided that preserving MIT is not required.
- The repository now carries a repository-root `LICENSE` with GPL v3 text plus
  `LICENSE_POLICY.md` stating the project-level `GPL-3.0-or-later` grant, and
  the old `docs/LICENSE` MIT file has been removed to avoid ambiguous
  license-scanner results.

Official DFO-LS license state:

- Installed `DFO-LS==1.6.5` reports `License: GPL-3.0-or-later`.
- PyPI metadata also reports `GPL-3.0-or-later`.
- The PyPI project page says the algorithm is released under the GNU GPL and points users to contact NAG for alternative licensing.

Tapenade AD license/tooling state:

- TLTM also supports a Tapenade source-transformation AD route through
  `GEN_BACKEND=st_tapenade` and `scripts/st_backends/tapenade_codegen.py`.
- Tapenade is currently used as an external CLI/code-generation tool, not as a
  vendored runtime dependency.
- The official Tapenade distribution license checked on 2026-05-11 is MIT
  License, Copyright INRIA.
- Current checked-in `src/physics/model_generated.f90` is not Tapenade output
  unless its backend banner says `st-tapenade-experimental`.
- Tapenade therefore does not force the DFO-LS GPL decision. It still requires
  release provenance: exact Tapenade version, generation command, generated-file
  inspection, and retained notices if generated output includes Tapenade-owned
  helper text or runtime code.

Compatibility implication:

- MIT code can be combined with GPL code in a GPL-covered combined program.
- A distributed combined product that incorporates or links GPL-covered DFO-LS code must be GPL-compatible as a whole.
- Because the user decided not to preserve MIT, the mature-product route is now
  a clear repository-level GPL-3.0-or-later policy.

## Rejected Paths

Rejected: production Python subprocess bridge.

- Too slow and fragile for the HMC inner loop.
- Good for offline replay and validation only.

Rejected: copying or porting DFO-LS internals into TLTM while pretending the result remains MIT-only.

- DFO-LS is GPL-3.0-or-later.
- A port or derivative implementation based on the official source inherits the GPL constraints.

Rejected: hiding official DFO-LS as an undocumented dependency.

- This would make reproducibility and distribution ambiguous.
- It does not solve the combined-product license question.

## Viable Paths

### Path A: GPL Production Product

Recommended if the user wants official DFO-LS in production and accepts open-source copyleft distribution.

Actions:

1. Add repository-root `LICENSE` with GPL v3 text and `LICENSE_POLICY.md` with
   the GPL-3.0-or-later project grant.
2. Remove or replace ambiguous MIT-only license files.
3. Add `NOTICE` or `THIRD_PARTY_NOTICES.md` listing DFO-LS, its version, homepage, license, and dependency role.
4. Add source-file or module-level notices for new official-DFO-LS backend integration code.
5. Mark the full production distribution as GPL-3.0-or-later.
6. Implement production backend integration only after the license policy is committed.

Status on 2026-05-11 JST:

- Repository-root `LICENSE` added from the GNU GPL v3 text.
- Repository-root `LICENSE_POLICY.md` added to state the project-level
  `GPL-3.0-or-later` grant.
- Old `docs/LICENSE` MIT file removed.
- Repository-root `THIRD_PARTY_NOTICES.md` added with DFO-LS and Tapenade entries.

Pros:

- Legally straightforward for an open-source research codebase.
- Allows official DFO-LS production use without relying on vendor negotiation.
- Consistent with publishable reproducible science if GPL is acceptable.

Cons:

- Downstream users must comply with GPL when distributing modified/combined versions.
- Some collaborators or institutions may dislike GPL obligations.

### Path B: Alternative License from NAG

Recommended if TLTM must remain MIT/permissive or if institutional/product constraints cannot accept GPL.

Actions:

1. Contact NAG and request an alternative DFO-LS license for TLTM production use.
2. Keep official DFO-LS as offline validation only until license terms are settled.
3. If NAG grants compatible terms, record the license text and scope in `THIRD_PARTY_NOTICES.md`.
4. Then proceed with production replacement under those terms.

Pros:

- Could preserve MIT/permissive TLTM distribution.
- Avoids copyleft concerns.

Cons:

- Requires external negotiation.
- May have cost, usage limits, or publication restrictions.

### Path C: Keep In-House Production Solver

Recommended if neither GPL nor alternative licensing is acceptable.

Actions:

1. Keep official DFO-LS as validation/calibration oracle.
2. Continue improving in-house solver design using paper-backed audits.
3. Do not ship official DFO-LS in production.

Pros:

- Preserves current MIT-style project posture.
- Avoids dependency/license complexity.

Cons:

- Does not satisfy the user's current preference to replace the in-house solver with official DFO-LS.

## Recommended Decision

User clarification on 2026-05-11 JST:

- TLTM was written by the user.
- TLTM has not yet been published.
- Preserving MIT is not required.
- Tapenade AD is also part of the toolchain and must be considered.
- Therefore, assuming there are no external contributor, employer, funder, or institutional ownership restrictions, relicensing TLTM for GPL-compatible official-DFO-LS production use is not expected to be a blocker.

Given the user's explicit goal that production should use official DFO-LS, the recommended path is now:

1. Adopt Path A: make the production TLTM distribution GPL-3.0-or-later.
2. Do not preserve the old MIT file in the active repository license path.
3. Proceed with backend-interface work and official-DFO-LS production integration after the repository license files are updated.
4. Keep Tapenade as an external MIT-licensed code-generation tool with explicit
   generated-source provenance checks.

Operational recommendation for the next coding step:

- Implement backend-interface scaffolding that can host in-house and official backends, then make official DFO-LS the intended production target after behavior gates pass.
- Keep `THIRD_PARTY_NOTICES.md` current whenever DFO-LS, Tapenade, Enzyme, or
  generated-source provenance changes.

## Replacement Readiness After License Decision

Once the license path is selected:

1. Implement residual-only solver backend interface.
2. Add official DFO-LS production backend using the tuned preset:
   - `objfun_has_noise = true`
   - `npt = 4`
   - `rhobeg = 0.018`
   - `rhoend = 1e-16`
   - `model.abs_tol = 1e-30`
   - `model.rel_tol = 0`
   - `maxfun = 250`
   - success gate: `residual_norm <= cttol`
3. Run attempt-level replacement gate.
4. Run fixed-seed 10k chain gate.
5. Run 50k -> 100k behavior-preservation gates before making official DFO-LS the default.
