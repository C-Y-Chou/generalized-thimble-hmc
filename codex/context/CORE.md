# CORE (Token-Saving Context)

- Repo: /home/cychou/TLTM
- Working hub: /home/cychou/TLTM/codex
- Mandatory pre-read: /home/cychou/TLTM/docs/AGENT_GUIDE.md
- Build env: `module load compiler/2025.3.0 mpi/2021.17 mkl/2025.3`
- Required flow policy: `nofb/withfb -> RG -> Metropolis`
- Compact boot state: `/home/cychou/TLTM/codex/context/L0_BOOT.md`
- Routing index: `/home/cychou/TLTM/codex/indexes/L1_INDEX.tsv`
- Remote refresh: `bash /home/cychou/TLTM/codex/tasks/refresh_remote_state.sh`
- L0 render: `bash /home/cychou/TLTM/codex/tasks/render_l0_boot.sh`
- Control-plane validation: `bash /home/cychou/TLTM/codex/tasks/validate_control_plane.sh`
- Source audit docs are triggered reads, not always-read files.
- Cluster02 scheduling agent: `/home/cychou/TLTM/codex/agents/cluster02_scheduler/README.md`
- Latest pre-production hardening: RG replay stats suppression, RG `jac` check, explicit `proposal_ok`, Stage3 warmup fail-fast, per-seed `run_manifest.json`.
- Active ops workspaces:
  - `/home/cychou/TLTM/codex/workspaces/tltm_production_comparison`
  - `/home/cychou/TLTM/codex/workspaces/stage3_3_rg_redo`
  - `/home/cychou/TLTM/codex/workspaces/ngport_rg_single_replica_t03_nstep_grid`
- Registry: `/home/cychou/TLTM/codex/runbooks/task_registry.tsv`
