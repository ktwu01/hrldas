### Project Intro

HRLDAS + Noah‑MP (Fortran) for simulations and Python ML for analysis/training on Derecho/Casper. Keep code safe in Home, run I/O in Scratch, retain results in Work, and promote long‑lived assets to Campaign.

### Storage Layout (Best Practice)

- Home (`/glade/u/home/wukoutian`)
  - `hrldas/` — driver repo (with git branches)
  - `hrldas/noahmp/` — model repo
  -  `../Ori_RPM/hrldas_phs/` - phs hrldas repo
- Work (`/glade/work/wukoutian`)
  - `noahmp/inputs/` — simulation inputs (authoritative copy)
  - `noahmp/results/` — retained outputs by run_id
  - `ml/datasets/` — curated training/validation/test shards
  - `ml/checkpoints/` — active model checkpoints
- Scratch (`/glade/derecho/scratch/wukoutian`)
  - `noahmp/runs/<run_id>/` — per-simulation working dirs
  - `ml/experiments/<exp_id>/` — per-training run workspaces
- Campaign (`/glade/campaign/univ/utaa0012/`)
  - `datasets/{raw,curated}/`, `models/releases/`, `manifests/`, `results/<YYYY>/<run_id>/`

Guideline: Stage inputs to Scratch for each run; write intermediates to Scratch; copy minimal results to Work; promote stable datasets/models to Campaign. Do not train directly from Campaign.

### HRLDAS + Noah‑MP Workflow

- Repos in Home; builds and runs in Scratch; inputs from Work; archive results to Work.
- If Noah‑MP is separate from HRLDAS, pin versions via Git submodule.

### Git/worktree plan

Use HRLDAS as the superproject with a single `noahmp/` submodule; create and develop Noah‑MP feature branches on your fork (`feature/wood`, `feature/rock`, `feature/ai`) for model changes; create thin HRLDAS branches (`main`, `wood`, `rock`, `ai`) and worktrees at `/glade/u/home/$USER/hrldas-{main,wood,rock,ai}` to pin each variant to a specific `noahmp` commit; in each worktree `git submodule update --init`, check out the target `noahmp` feature commit in detached HEAD, commit the submodule pointer, then build/run there; never create `noahmp_*` directories—always use `noahmp/`; push only to your fork; put build/output under Scratch per branch.

/glade/u/home/wukoutian/
├── hrldas/                        # Main worktree
│   ├── env/                       # Environment configs (versioned)
│   │   └── modules.sh             # Module loads for Derecho/Casper
│   └── noahmp/
├── hrldas-wood/                   # Wood variant worktree
│   └── noahmp/
├── hrldas-rock/                   # Rock variant worktree
│   └── noahmp/
└── hrldas-ai/                     # AI variant worktree
    └── noahmp/

- HRLDAS (superproject → submodule mapping)
  - HRLDAS branch `main` pins submodule `noahmp` to `fork/main` (baseline from upstream `master`)
  - HRLDAS branch `wood` pins submodule `noahmp` to `fork/feature/wood`
  - HRLDAS branch `rock` pins submodule `noahmp` to `fork/feature/rock`
  - HRLDAS branch `ai`   pins submodule `noahmp` to `fork/feature/ai`
- Worktrees
  - `/glade/u/home/$USER/hrldas` (branch `main`)
  - `/glade/u/home/$USER/hrldas-wood` (branch `wood`)
  - `/glade/u/home/$USER/hrldas-rock` (branch `rock`)
  - `/glade/u/home/$USER/hrldas-ai`   (branch `ai`)
- Environment config
  - `hrldas/env/modules.sh` (module loads for Derecho/Casper)
- **Important:** Do not delete `origin/master` branch - it contains important NCAR/upstream code that may be needed. (confirmed by KW 20250915)

### Useful Git Commands

- **List worktrees:** `git worktree list`
- **Add a worktree:** `git worktree add <path> <branch>`
- **Remove a worktree:** `git worktree remove <path>`
- **Prune worktree metadata:** `git worktree prune`

### Project Status Board

- **HRLDAS Superproject Setup**
  - [x] Create `wood`, `rock`, `ai` branches. (Completed on 2025-09-15)
  - [x] Create worktrees at `/glade/u/home/wukoutian/hrldas-{wood,rock,ai}`. (Completed on 2025-09-15)

- **Noah-MP Submodule Setup**
  - [x] **Task 1: Create `noahmp` feature branches.** (Completed on 2025-09-15)
    - **Description:** For each variant (`wood`, `rock`, `ai`), navigate into the corresponding worktree's `noahmp/` directory, create a new feature branch (e.g., `feature/wood`), and push it to the personal fork.
    - **Success Criteria:** The `feature/wood`, `feature/rock`, and `feature/ai` branches exist on the `noahmp` submodule's remote fork.

- **Submodule Pinning**
  - [x] **Task 2: Pin HRLDAS branches to submodule commits.** (Completed on 2025-09-15)
    - **Description:** In each HRLDAS worktree (e.g., `hrldas-wood`), update the submodule pointer to track the corresponding `noahmp` feature branch (e.g., `feature/wood`) and commit this change.
    - **Success Criteria:** Running `git submodule status` in each HRLDAS worktree shows the `noahmp` submodule pointing to the correct feature branch commit.

- **Branch Verification and Alignment**
  - [x] **Task 3: Verify `noahmp` branches across worktrees.** (Completed on 2025-09-15)
    - **Description:** In each worktree (`hrldas-{wood,rock,ai}`), run `git fetch --all` inside `noahmp/` and confirm `feature/{wood,rock,ai}` exists and is checked out; confirm remotes (`origin`→NCAR, `fork`→ktwu01) are correct.
    - **Success Criteria:** `git branch -vv` shows the expected `feature/*` branch tracking `fork/feature/*` in each worktree.
  - [x] **Task 4: Create `main` branch in fork (alias to upstream master).** (Completed on 2025-09-15)
    - **Description:** In `ktwu01/noahmp` fork, create `main` that points to `NCAR/noahmp:master` (keep `master` to match upstream); optionally set HRLDAS `main` submodule to track `fork/main` to reduce naming confusion.
    - **Success Criteria:** `main` exists on `ktwu01/noahmp`; if opted, `hrldas` `main` submodule points to a commit reachable from `fork/main`.
  - [ ] **Task 5: Publish HRLDAS `wood` branch.**
    - **Description:** Ensure `hrldas-wood` worktree is clean and push branch `wood` to remote (no submodule changes beyond pinned pointer).
    - **Success Criteria:** `git status` clean in `/glade/u/home/wukoutian/hrldas-wood`; `git push -u origin wood` succeeds.
  - [ ] **Task 6: Diagnose `feature/rock` git status issue.**
    - **Description:** In `/glade/u/home/wukoutian/hrldas-rock`, run `git status`, `git submodule status`, and resolve any staged/unstaged changes or detached pointers; ensure submodule tracks `fork/feature/rock` and commit if needed.
    - **Success Criteria:** `git status` clean; submodule pointer correct; branch tracks remote; ready to push.