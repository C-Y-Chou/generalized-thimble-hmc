# Outputs And Restart

## WV-HMC Outputs

A WV-HMC run writes:

- `summary.csv`: transition and measurement diagnostics;
- `observables.csv`: final ratio estimates;
- `product_run_manifest.json`: wrapper parameters, output paths, and source
  settings;
- `final_state.bin`: final flow-time and physical state;
- `observable_history.csv`: per-measurement observable history when `--history`
  is enabled;
- `x_history.dat` and `state_history.dat`: binary histories when `--history` is
  enabled;
- `snapshot_index.csv` and snapshot files when `--snapshot-interval` is set.

Example:

```bash
python3 scripts/run_tltm_product.py wv-hmc \
  --cycles 1000 \
  --history \
  --snapshot-interval 250 \
  --output-dir output/product/wv_hmc_example
```

## TLTM Outputs

TLTM runs through the product runner write:

- per-seed summary tables;
- aggregate summary tables;
- run-protocol metadata;
- observable estimates;
- run logs;
- `product_run_manifest.json`.

## Restart Policy

For WV-HMC, use snapshots or `final_state.bin` as restart material. A restart
protocol should record:

- source commit;
- parameter file;
- wrapper options;
- initial state file;
- cycle offset;
- measurement start cycle;
- output directory.

Restarted runs should keep their own output directory and manifest.
