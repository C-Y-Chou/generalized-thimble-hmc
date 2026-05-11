#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(git -C "$CODEX_DIR" rev-parse --show-toplevel)"
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"

CANONICAL_LOCAL="/Users/ccy/Documents/TLTM_qn_error_handling"
LEGACY_LOCAL="/Users/ccy/Documents/New project/TLTM_repo"
CANONICAL_REMOTE="/lustre1/home/cychou/TLTM_worktrees/fortran_modernization"

echo "[route] root=$ROOT"
echo "[route] branch=$BRANCH"

if [ "$ROOT" = "$LEGACY_LOCAL" ] && [ "${TLTM_ALLOW_LEGACY_CONTROL_PLANE:-0}" != "1" ]; then
  cat >&2 <<EOF
[route][error] Refusing to continue from legacy local checkout:
  $LEGACY_LOCAL

Use the canonical TLTM repo instead:
  cd $CANONICAL_LOCAL

Set TLTM_ALLOW_LEGACY_CONTROL_PLANE=1 only for an explicit legacy/control-plane task.
EOF
  exit 2
fi

case "$BRANCH" in
  codex/fortran-modernization)
    ;;
  codex/*official-dfols)
    echo "[route][warn] This is an official-DFO-LS mirror, not necessarily the preferred local source of truth."
    echo "[route][warn] Preferred local repo: $CANONICAL_LOCAL"
    echo "[route][warn] Preferred remote execution target: $CANONICAL_REMOTE"
    ;;
  codex/control-plane)
    if [ "${TLTM_ALLOW_LEGACY_CONTROL_PLANE:-0}" != "1" ]; then
      cat >&2 <<EOF
[route][error] Refusing default workflow on legacy control-plane branch:
  $BRANCH

Current TLTM work defaults to official DFO-LS:
  $CANONICAL_LOCAL
  branch codex/fortran-modernization
EOF
      exit 2
    fi
    ;;
  *)
    echo "[route][warn] Unrecognized TLTM branch. Verify this is intentional before changing code or submitting jobs." >&2
    ;;
esac

if [ -f "$CODEX_DIR/context/HANDOFF_MIN.txt" ]; then
  if ! grep -q "$CANONICAL_LOCAL" "$CODEX_DIR/context/HANDOFF_MIN.txt"; then
    echo "[route][error] HANDOFF_MIN.txt does not name canonical local repo: $CANONICAL_LOCAL" >&2
    exit 2
  fi
  if ! grep -q "codex/fortran-modernization" "$CODEX_DIR/context/HANDOFF_MIN.txt"; then
    echo "[route][error] HANDOFF_MIN.txt does not name codex/fortran-modernization" >&2
    exit 2
  fi
fi

echo "[route] canonical route guard passed"
