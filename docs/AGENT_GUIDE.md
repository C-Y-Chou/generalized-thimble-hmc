# AGENT GUIDE — HPC PROJECT EXECUTION RULES (CLUSTER02)

Verification note:
- Last checked on 2026-04-22 from ithems_fe02.intra.riken.jp
- Queue values below were checked with qstat -Q and qstat -Qf
- Module values below were checked with module avail and module load
- Quota values below were checked with lfs quota
- Re-check queue, module, and quota values before large production work

==================================================
A. SYSTEM CONSTRAINTS
==================================================

- Target system: iTHEMS cluster02
- Frontend / login host: ithems_fe02.intra.riken.jp
- NEVER run MPI programs on frontend (ithems_fe02)
- Direct login to compute nodes is forbidden on cluster02
- ALL execution MUST occur on compute nodes obtained through PBS jobs
- ALWAYS use PBS tools for execution and monitoring:
    - qsub
    - qstat
    - qdel
- ALWAYS load modules before build or run:

    module purge
    module load compiler/2025.3.0
    module load mpi/2021.17
    module load mkl/2025.3

- Authentication is SSH public-key only
- Password authentication is disabled
- If outside the RIKEN network, assume VPN is required first
- Storage quotas:
    - $HOME resolves to /lustre1/home/<username>
    - /data/<username> resolves to /lustre1/data/<username>
    - Current observed Lustre user quota: 20T soft / 21T hard on /lustre1
    - Before large output, verify current quota with:

        lfs quota -h -u $USER /lustre1

- No automatic backup is provided by the system
- Python environment note:
    - Do NOT assume only Python 3.6.8 is available
    - Cluster02 provides system Python plus Miniconda environments
    - Current Miniconda module:

        module load miniconda3

    - Current shared conda environments observed:
        - base
        - pytorch_py3.12
        - tensorflow_py3.12
    - If the project requires a specific Python version, detect it from the codebase and activate the correct environment explicitly

==================================================
B. PROJECT DISCOVERY RULE
==================================================

- Scan the full directory tree before acting
- Identify at minimum:
    - Makefile / makefiles
    - main programs
    - scripts/
    - tests/
    - README / documentation
    - job scripts
    - Python environments / requirements files
- Do NOT assume structure
- Derive actual execution flow from the repository contents

==================================================
C. BUILD RULES
==================================================

- Common initial build, only after confirming the target and OMP variable exist:

    make fast OMP=0

- If the project does not provide that target, use the smallest documented build target from the repository
- Preferred compiler for MPI Fortran builds:

    mpiifx

- But do NOT hard-code this blindly
- First inspect Makefile, compiler variables, and existing project conventions
- If the project already specifies a working compiler, preserve it unless there is a clear failure
- Avoid in the initial stabilization stage:
    - -ipo
    - aggressive optimization changes
    - OpenMP changes
    - large build-system rewrites

==================================================
D. EXECUTION RULES
==================================================

TESTING:

- Use an interactive PBS job for short validation runs:

    qsub -I -q debug -l select=1:ncpus=4:mpiprocs=4 -l walltime=00:15:00

- After allocation:

    cd $PBS_O_WORKDIR

- Run only the smallest meaningful test first

PRODUCTION:

- Use PBS batch scripts
- Always include:
    - queue selection
    - select=...
    - walltime
    - module initialization / load section
    - cd $PBS_O_WORKDIR
    - redirected stdout/stderr when output may be large

- Example execution pattern:

    mpirun -np <N> ./a.out > output.log 2>&1

- Never run heavy production calculations interactively unless explicitly needed for debugging

==================================================
E. QUEUE SELECTION RULES
==================================================

- Choose the smallest queue and shortest walltime that fit the job
- Prefer debug for compile/run sanity checks only
- Prefer standard queues for ordinary production runs
- Use LONG queues only when runtime realistically exceeds the normal queue limit
- LONG queues share resources with the corresponding base queues, so they are more constrained and should not be used casually
- Queue policies can change; before production submission, run:

    qstat -Q
    qstat -Qf <queue>

Current standard queue snapshot for cluster02:

- debug
    - max resource across all users: 2 nodes
    - max queued jobs per person: 2
    - max running jobs per person: 1
    - max running nodes per person: 2 nodes
    - default memory per node: 185gb
    - time limit: 15 minutes

- C8
    - max resource across all users: 8 nodes
    - default memory per node: 185gb
    - time limit: 12 hours

- C12
    - max resource across all users: 12 nodes
    - default memory per node: 370gb
    - time limit: 12 hours

- C17
    - max resource across all users: 17 nodes
    - default memory per node: 370gb
    - time limit: 12 hours

- C16
    - max resource across all users: 16 nodes
    - default memory per node: 185gb
    - time limit: 12 hours

- C24
    - min resource: 17 nodes
    - max resource across all users: 24 nodes
    - default memory per node: 185gb
    - time limit: 12 hours

- C36
    - min resource: 25 nodes
    - max resource across all users: 36 nodes
    - default memory per node: 185gb
    - time limit: 12 hours

- G
    - max resource across all users: 4 nodes
    - default memory per node: 185gb
    - default GPUs per node: 2
    - time limit: 12 hours

- G-A100
    - max resource across all users: 1 node
    - default memory per node: 370gb
    - default GPUs per node: 2
    - time limit: 12 hours

- F
    - max resource across all users: 1 node
    - default memory per node: 3020gb
    - time limit: 12 hours

- Queues observed but not suitable as default choices:
    - V: disabled / stopped
    - C: disabled / stopped
    - C5: disabled / stopped
    - C12-LONG2: enabled but stopped

Current LONG queue policy for cluster02:

- C17-LONG
    - resource is shared with C17
    - max resource across all users: 8 nodes
    - max number of jobs per person: no limit
    - max running nodes per person: 4 nodes
    - time limit: 72 hours

- C8-LONG
    - resource is shared with C8
    - max resource across all users: 8 nodes
    - max number of jobs per person: no limit
    - max running nodes per person: 4 nodes
    - time limit: 48 hours

- C12-LONG
    - resource is shared with C12
    - max resource across all users: 12 nodes
    - max number of jobs per person: no limit
    - max running nodes per person: 6 nodes
    - time limit: 72 hours

- G-LONG
    - resource is shared with G
    - max resource across all users: 1 node
    - max number of jobs per person: no limit
    - max running nodes per person: 1 node
    - time limit: 72 hours

Operational implications:

- For long CPU jobs on the 48-core class, consider C17-LONG when the job truly needs more than 12 hours and fits within the per-user 4-node running limit
- For long jobs on older 40-core nodes, use C8-LONG only when 48 hours is sufficient
- For long jobs on 48-core / 384GB nodes, use C12-LONG when 72 hours is required and up to 6 running nodes are enough
- For GPU long jobs, G-LONG is highly constrained because the total shared resource is only 1 node
- Before generating a production script, verify queue choice against required node count, runtime, GPU need, and per-user running-node limits

==================================================
F. ERROR HANDLING PROTOCOL
==================================================

On any failure:

1. STOP immediately
2. Identify the FIRST real error only
3. Classify it as one of:
    - build
    - module
    - MPI
    - Python
    - PBS / queue
    - path
    - filesystem / quota
4. Apply the MINIMAL fix only
5. Re-run the smallest validation step

==================================================
G. ITERATIVE WORKFLOW
==================================================

1. Scan project
2. Identify build entry point
3. Attempt minimal build
4. Fix first error
5. Rebuild
6. Validate with the smallest runnable test
7. Prepare PBS script only after local project logic is understood
8. Expand scope gradually

==================================================
H. STRICT PROHIBITIONS
==================================================

- DO NOT run MPI on frontend
- DO NOT bypass PBS for compute execution
- DO NOT attempt direct login to cluster02 compute nodes
- DO NOT rewrite the entire codebase
- DO NOT change architecture without evidence
- DO NOT guess dependencies without checking files or module availability
- DO NOT submit oversized jobs before a small validation run succeeds
- DO NOT write large outputs to $HOME when /data is more appropriate
- DO NOT assume an unlimited LONG queue allocation

==================================================
I. DEFAULT PBS TEMPLATE
==================================================

Use this as a conservative starting template and modify only as required:

#!/bin/bash
#PBS -q debug
#PBS -l select=1:ncpus=4:mpiprocs=4
#PBS -l walltime=00:15:00
#PBS -N test_job

cd $PBS_O_WORKDIR
module purge
module load compiler/2025.3.0
module load mpi/2021.17
module load mkl/2025.3

mpirun -np 4 ./a.out > output.log 2>&1

For production, replace:
- queue name
- select=...
- walltime
- executable name
- module set if the project requires something else
