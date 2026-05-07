# Test and Benchmark Roadmap

## Verification pillars
- unit correctness
- solver-route correctness
- scientific invariants
- fixed-seed regression stability
- performance regression visibility

## Near-term additions
### Unit and kernel checks
- state-vector helper tests
- residual and real/complex mapping checks
- solver acceptance-rule micro tests

### Integration checks
- HMC proposal stability checks
- Metropolis acceptance-path checks
- representative Stage2/Stage3 workflow smoke runs

### Scientific invariants
- action/derivative consistency
- Hessian-vector consistency
- Hamiltonian conservation trend
- reversibility diagnostics

### Regression baselines
- fixed-seed reference runs for representative configs
- solver stats and route census snapshots
- summary metric comparison tables

### Benchmarking
- baseline runtime and allocation profile for flow, Newton, quasi-Newton, and chain driver hot paths
- before/after benchmark table for every major refactor wave
