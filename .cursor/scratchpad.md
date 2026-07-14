### Project Intro

> Rock variant rationale (deep vadose zone / rock moisture, Experiment 2): see `scratchpad-rock.md`.

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

Use HRLDAS as the superproject with a single `noahmp/` submodule. Use **simple 1:1 branch naming** between repos.

**Branch Mapping (1:1 paired naming):**
```
ktwu01/hrldas          ktwu01/noahmp
─────────────          ─────────────
main            ────── main           (baseline)
phs             ────── phs            (Plant Hydraulics)
wood            ────── wood           (Wood variant)
rock            ────── rock           (Rock variant)
ai              ────── ai             (AI variant)
```

**Worktree Layout:**
```
/glade/u/home/wukoutian/
├── hrldas/                        # Main worktree (branch: main)
│   ├── env/                       # Environment configs (versioned)
│   │   └── modules.sh             # Module loads for Derecho/Casper
│   └── noahmp/                    # Submodule pinned to fork/main
├── hrldas-wood/                   # Wood variant (branch: wood)
│   └── noahmp/                    # Submodule pinned to fork/wood
├── hrldas-rock/                   # Rock variant (branch: rock)
│   └── noahmp/                    # Submodule pinned to fork/rock
├── hrldas-ai/                     # AI variant (branch: ai)
│   └── noahmp/                    # Submodule pinned to fork/ai
└── hrldas-phs/                    # PHS variant (branch: phs)
    └── noahmp/                    # Submodule pinned to fork/phs
```

**Remotes:**
- `origin` = your fork (ktwu01/hrldas or ktwu01/noahmp)
- `fork` = alias for noahmp fork (ktwu01/noahmp) in hrldas repo
- NCAR upstream = reference only, don't sync unless needed

**Rules:**
- Always use simple branch names (no `feature/` prefix)
- hrldas branch X → noahmp branch X (1:1 mapping)
- Push only to your fork, never to NCAR upstream
- Put build/output under Scratch per branch

**Legacy branches (archived with `-legacy` suffix):**
- hrldas: `master-legacy`, `rock-legacy`, `ai-legacy`, `test-noah-agent-rock-legacy`
- noahmp: `master-legacy`

### Useful Git Commands

- **List worktrees:** `git worktree list`
- **Add a worktree:** `git worktree add <path> <branch>`
- **Remove a worktree:** `git worktree remove <path>`
- **Prune worktree metadata:** `git worktree prune`

### Submodule管理注意事项 - "打地鼠"现象

**现象描述：**
在一个worktree中更新NoahMP submodule后，其他worktree会显示"submodule有新提交可用"的提示，就像打地鼠一样此起彼伏。

**原因分析：**
1. **共享.git目录**: 所有worktree共享同一个`.git`目录，包括submodule的引用信息
2. **Git检测机制**: Git会检测到fork上有新提交，并提示"可更新"
3. **正常现象**: 这是git worktree + submodule组合的预期行为，不是bug

**最佳实践指南：**

**✅ 正确的做法：**
- 忽略其他worktree中的"new commits available"提示
- 只在当前工作的worktree中进行submodule更新
- 使用`git submodule status`确认当前worktree的pinning状态
- 每个worktree保持其独立的submodule版本

**❌ 避免的操作：**
- 不要在所有worktree中都运行`git submodule update`
- 不要试图"同步"所有worktree的submodule到同一版本
- 不要因为看到提示就强制更新不相关的worktree

**诊断命令：**
```bash
# 检查当前worktree的submodule状态（无前缀 = 正常）
git submodule status

# 检查submodule的当前分支
cd noahmp && git branch --show-current

# 确认pinning是否正确
cd .. && git ls-tree HEAD noahmp
```

**处理原则：**
每个worktree的submodule版本应该独立管理，"new commits"提示可以安全忽略，只要当前worktree的功能开发正常进行即可。