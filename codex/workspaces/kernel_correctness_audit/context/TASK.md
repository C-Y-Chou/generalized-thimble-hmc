# Kernel Correctness Audit

Updated: 2026-05-07 JST

## Purpose
Audit the minimal correctness conditions for the TLTM local proposal kernel without relying on compressed chat context.

## Current first target
Check whether the implemented proposal/replay path is deterministic and single-valued under fixed inputs and fixed solver/RG settings.

## Non-goals for first probe
- Do not claim volume preservation.
- Do not claim detailed balance.
- Do not claim reverse-gate correctness beyond the specific replay/full-run repeatability checks.

## Source of truth
- Remote repo: `/home/cychou/TLTM`
- Persistent audit root: `/home/cychou/TLTM/codex/workspaces/kernel_correctness_audit`
- Output root: `/home/cychou/TLTM/output/tests/kernel_correctness_audit`
- Log root: `/home/cychou/TLTM/output/logs/kernel_correctness_audit`

## Required records
- Record intent before each probe in `state/session_log.md`.
- Record job id and PBS script path after submit.
- Record result, output paths, and interpretation after completion.
