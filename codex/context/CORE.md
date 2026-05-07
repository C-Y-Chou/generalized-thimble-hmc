# CORE (Token-Saving Context)

- Repo: /home/cychou/TLTM
- Working hub: /home/cychou/TLTM/codex
- Mandatory pre-read: /home/cychou/TLTM/docs/AGENT_GUIDE.md
- Build env: `module load compiler/2025.3.0 mpi/2021.17 mkl/2025.3`
- Required flow policy: `nofb/withfb -> RG -> Metropolis`
- Live board (single source): `/home/cychou/TLTM/codex/runbooks/LIVE_BOARD.md`
- Refresh command: `bash /home/cychou/TLTM/codex/tasks/refresh_live_board.sh`
- Source audit bootstrap: `/home/cychou/TLTM/codex/runbooks/SOURCE_AUDIT_BOOTSTRAP.md`
- Source scan manifest: `/home/cychou/TLTM/codex/knowledge/CODEBASE_SCAN_MANIFEST.md`
- Full-program risk map: `/home/cychou/TLTM/codex/knowledge/FULL_PROGRAM_MAP_CHECK.md`
- Kernel audit status: `/home/cychou/TLTM/codex/workspaces/kernel_correctness_audit/runbooks/STATUS.md`
- Latest pre-production hardening: RG replay stats suppression, RG `jac` check, explicit `proposal_ok`, Stage3 warmup fail-fast, per-seed `run_manifest.json`.
- Active ops workspaces:
  - `/home/cychou/TLTM/codex/workspaces/stage3_4`
  - `/home/cychou/TLTM/codex/workspaces/stage3_3_rg_redo`
  - `/home/cychou/TLTM/codex/workspaces/ngport_rg_single_replica_t03_nstep_grid`
- Registry: `/home/cychou/TLTM/codex/runbooks/task_registry.tsv`
