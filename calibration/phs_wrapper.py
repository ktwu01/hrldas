"""HRLDAS single-point PHS calibration wrapper — US-Syv site.

Modifies 5 PHS parameters for IPHTYP=1 (table index 0):
  TLP    [mm]      leaf turgor loss potential  → NoahmpTable.TBL PHS_LEAF_TLP[0]
  KSAT   [mm/s]    xylem sat. conductivity     → NoahmpTable.TBL PHS_XYLEM_KSAT[0]
  P50    [mm]      stem P50 potential          → NoahmpTable.TBL PHS_XYLEM_P50[0]
  SPWAI  [m2/m2]   sapwood area index          → wrfinput SPWAI field
  SPWVI  [m3/m2]   sapwood volume index        → wrfinput SPWVI field

Objective: KGE(LH) + KGE(PSN) at monthly scale, following Sun et al. (2024).

Usage:
    from phs_wrapper import run_phs
    score = run_phs(tlp=-1.07e5, ksat=2.07e-2, p50=-3.22e5, spwai=0.0015, spwvi=0.0435)
"""

import glob
import os
import re
import shutil
import subprocess
import tempfile
from collections import defaultdict
from datetime import datetime
from pathlib import Path

import netCDF4 as nc
import numpy as np

# ---------------------------------------------------------------------------
# Paths — mutable run artifacts come from the current workspace, not ~/regression_test
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parents[1]
LDASIN_DIR   = os.path.expanduser("~/regression_test/US-Syv")
OBS_FILE     = os.path.expanduser(
    "~/Ori_RPM/AFM24-data/flux_utc/US-Syv_2002010106_2009010105_hur_Flux.nc"
)
SCRATCH_BASE = "/glade/derecho/scratch/wukoutian/tmp/phs_cal"
WRFINPUT     = "0.2_wrfinput_phs_1P_plot.nc"
RESTART_INIT = "RESTART.2002010106_DOMAIN1"


def _resolve_override(env_name):
    value = os.environ.get(env_name)
    return Path(value).expanduser().resolve() if value else None


def _find_first_existing(candidates, description):
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    tried = "\n".join(f"  - {path}" for path in candidates)
    raise FileNotFoundError(f"Could not find {description}. Tried:\n{tried}")


def _resolve_template_dir():
    override = _resolve_override("PHS_CAL_TEMPLATE_DIR")
    if override is not None:
        required = [override / "namelist.hrldas", override / WRFINPUT, override / RESTART_INIT]
        missing = [str(path) for path in required if not path.exists()]
        if missing:
            missing_text = "\n".join(f"  - {path}" for path in missing)
            raise FileNotFoundError(
                "PHS_CAL_TEMPLATE_DIR is missing required files:\n" + missing_text
            )
        return override

    candidates = [
        REPO_ROOT / "run_globalDP",
        REPO_ROOT / "run_hybrid",
    ]
    return _find_first_existing(
        [path for path in candidates if (path / "namelist.hrldas").exists()
         and (path / WRFINPUT).exists()
         and (path / RESTART_INIT).exists()],
        "a workspace run template directory with namelist.hrldas, wrfinput, and restart",
    )


def _resolve_workspace_artifacts():
    template_dir = _resolve_template_dir()

    binary = _resolve_override("PHS_CAL_HRLDAS_EXE")
    if binary is None:
        binary = _find_first_existing(
            [
                REPO_ROOT / "hrldas" / "run" / "hrldas.exe",
                template_dir / "hrldas.exe",
            ],
            "a workspace hrldas.exe",
        )

    table_path = _resolve_override("PHS_CAL_NOAHMPTABLE")
    if table_path is None:
        table_path = _find_first_existing(
            [REPO_ROOT / "noahmp" / "parameters" / "NoahmpTable.TBL"],
            "workspace NoahmpTable.TBL",
        )

    namelist_path = _resolve_override("PHS_CAL_NAMELIST")
    if namelist_path is None:
        namelist_path = template_dir / "namelist.hrldas"

    wrfinput_path = _resolve_override("PHS_CAL_WRFINPUT")
    if wrfinput_path is None:
        wrfinput_path = template_dir / WRFINPUT

    restart_path = _resolve_override("PHS_CAL_RESTART")
    if restart_path is None:
        restart_path = template_dir / RESTART_INIT

    return {
        "template_dir": template_dir,
        "binary": binary,
        "table": table_path.resolve(),
        "namelist": namelist_path.resolve(),
        "wrfinput": wrfinput_path.resolve(),
        "restart": restart_path.resolve(),
    }


# ---------------------------------------------------------------------------
# KGE metric (Gupta et al. 2009)
# ---------------------------------------------------------------------------
def kge(sim, obs):
    mask = np.isfinite(obs) & np.isfinite(sim) & (obs > 0)
    if mask.sum() < 6:
        return -9.0
    r     = np.corrcoef(sim[mask], obs[mask])[0, 1]
    alpha = np.std(sim[mask]) / np.std(obs[mask])
    beta  = np.mean(sim[mask]) / np.mean(obs[mask])
    return 1.0 - np.sqrt((r - 1) ** 2 + (alpha - 1) ** 2 + (beta - 1) ** 2)


# ---------------------------------------------------------------------------
# NoahmpTable.TBL patcher: replace first comma-separated value of a param
# ---------------------------------------------------------------------------
def _patch_tbl_param(text, param, value):
    """Replace the first (IPHTYP=1, index 0) value of a PHS_* parameter line."""
    pat  = rf"(\s+{re.escape(param)}\s*=\s*)([+-]?[\d.]+[Ee][+-]?\d+)"
    repl = rf"\g<1>{value:.3E}"
    result, n = re.subn(pat, repl, text, count=1)
    if n != 1:
        raise ValueError(f"Parameter '{param}' not found in NoahmpTable.TBL")
    return result


# ---------------------------------------------------------------------------
# wrfinput patcher: write SPWAI and SPWVI fields
# ---------------------------------------------------------------------------
def _patch_wrfinput(path, spwai, spwvi):
    with nc.Dataset(path, "r+") as ds:
        ds.variables["SPWAI"][:] = spwai
        ds.variables["SPWVI"][:] = spwvi


# ---------------------------------------------------------------------------
# Time parser: LDASOUT Times is a char array 'YYYY-MM-DD_HH:MM:SS'
# ---------------------------------------------------------------------------
def _parse_ldasout_times(times_arr):
    result = []
    for row in times_arr:
        s = b"".join(row).decode("ascii")  # e.g. '2002-01-01_07:00:00'
        result.append(datetime.strptime(s, "%Y-%m-%d_%H:%M:%S"))
    return result


# ---------------------------------------------------------------------------
# Observation loader — returns monthly mean LH [W/m2] and PSN [umol/m2/s]
# ---------------------------------------------------------------------------
_obs_cache = None  # load once per process

def _load_obs_monthly():
    global _obs_cache
    if _obs_cache is not None:
        return _obs_cache

    with nc.Dataset(OBS_FILE) as ds:
        # time is stored as YYYYMMDDHH integers (no units attribute)
        time_raw = ds["time"][:].astype(np.int64)
        times    = [datetime.strptime(str(int(t)), "%Y%m%d%H") for t in time_raw]
        lh_raw   = ds["Qle_cor"][:].astype(np.float64)   # W/m2
        gpp_raw  = ds["GPP_DT"][:].astype(np.float64)    # umol CO2/m2/s

    lh_mon  = defaultdict(list)
    gpp_mon = defaultdict(list)
    for t, lh, gpp in zip(times, lh_raw, gpp_raw):
        key = (t.year, t.month)
        if np.isfinite(lh):
            lh_mon[key].append(float(lh))
        if np.isfinite(gpp):
            gpp_mon[key].append(float(gpp))

    keys    = sorted(set(lh_mon) | set(gpp_mon))
    lh_arr  = np.array([np.mean(lh_mon[k])  if lh_mon[k]  else np.nan for k in keys])
    gpp_arr = np.array([np.mean(gpp_mon[k]) if gpp_mon[k] else np.nan for k in keys])
    _obs_cache = {"months": keys, "LH": lh_arr, "PSN": gpp_arr}
    return _obs_cache


# ---------------------------------------------------------------------------
# Model output loader — reads single LDASOUT, returns monthly means
# ---------------------------------------------------------------------------
def _load_model_monthly(ldasout_path):
    with nc.Dataset(ldasout_path) as ds:
        times   = _parse_ldasout_times(ds["Times"][:])
        lh_mod  = ds["LH"][:, 0, 0].astype(np.float64)
        psn_mod = ds["PSN"][:, 0, 0].astype(np.float64)

    lh_mon  = defaultdict(list)
    psn_mon = defaultdict(list)
    for t, lh, psn in zip(times, lh_mod, psn_mod):
        key = (t.year, t.month)
        lh_mon[key].append(float(lh))
        psn_mon[key].append(float(psn))

    keys    = sorted(set(lh_mon) | set(psn_mon))
    lh_arr  = np.array([np.mean(lh_mon[k])  for k in keys])
    psn_arr = np.array([np.mean(psn_mon[k]) for k in keys])
    return {"months": keys, "LH": lh_arr, "PSN": psn_arr}


# ---------------------------------------------------------------------------
# Main wrapper: run HRLDAS and return KGE_LH + KGE_PSN
# ---------------------------------------------------------------------------
def run_phs(tlp, ksat, p50, spwai, spwvi, keep_dir=False):
    """Run HRLDAS-PHS with the given 5 parameters and return KGE_LH + KGE_PSN.

    Parameters (all for IPHTYP=1):
        tlp   : leaf turgor loss potential [mm], e.g. -1.07e5
        ksat  : xylem saturated conductivity [mm/s], e.g. 2.07e-2
        p50   : stem P50 potential [mm], e.g. -3.22e5
        spwai : sapwood area index [m2/m2], e.g. 0.0015
        spwvi : sapwood volume index [m3/m2], e.g. 0.0435
        keep_dir : if True, do not delete the temp workdir after the run

    Returns:
        float: KGE(LH) + KGE(PSN), range (-inf, 2.0]; or -9999 on failure.
    """
    artifacts = _resolve_workspace_artifacts()
    os.makedirs(SCRATCH_BASE, exist_ok=True)
    workdir = tempfile.mkdtemp(dir=SCRATCH_BASE, prefix="run_")

    try:
        # --- 1. Populate workdir ---
        shutil.copy(artifacts["binary"], Path(workdir) / "hrldas.exe")
        shutil.copy(artifacts["namelist"], Path(workdir) / "namelist.hrldas")
        shutil.copy(artifacts["wrfinput"], Path(workdir) / WRFINPUT)
        shutil.copy(artifacts["table"], Path(workdir) / "NoahmpTable.TBL")
        shutil.copy(artifacts["restart"], Path(workdir) / RESTART_INIT)
        os.symlink(LDASIN_DIR, os.path.join(workdir, "US-Syv"))

        # --- 2. Fix namelist paths to absolute ---
        nl_path = os.path.join(workdir, "namelist.hrldas")
        with open(nl_path) as f:
            nl = f.read()
        nl = re.sub(r'INDIR\s*=\s*"[^"]*"',  f'INDIR  = "{workdir}/US-Syv/"', nl)
        nl = re.sub(r'OUTDIR\s*=\s*"[^"]*"', f'OUTDIR = "{workdir}/"',         nl)
        with open(nl_path, "w") as f:
            f.write(nl)

        # --- 3. Patch NoahmpTable.TBL ---
        tbl_path = os.path.join(workdir, "NoahmpTable.TBL")
        with open(tbl_path) as f:
            tbl = f.read()
        tbl = _patch_tbl_param(tbl, "PHS_LEAF_TLP",  tlp)
        tbl = _patch_tbl_param(tbl, "PHS_XYLEM_KSAT", ksat)
        tbl = _patch_tbl_param(tbl, "PHS_XYLEM_P50",  p50)
        with open(tbl_path, "w") as f:
            f.write(tbl)

        # --- 4. Patch wrfinput SPWAI / SPWVI ---
        _patch_wrfinput(os.path.join(workdir, WRFINPUT), spwai, spwvi)

        # --- 5. Run HRLDAS ---
        logfile = os.path.join(workdir, "run.log")
        with open(logfile, "w") as log:
            ret = subprocess.run(
                ["./hrldas.exe"],
                cwd=workdir,
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=7200,
            )
        if ret.returncode != 0:
            print(f"[run_phs] HRLDAS failed (rc={ret.returncode}), log: {logfile}")
            return -9999.0

        # --- 6. Find LDASOUT ---
        ldasout_files = sorted(glob.glob(os.path.join(workdir, "*.LDASOUT_DOMAIN1")))
        if not ldasout_files:
            print("[run_phs] No LDASOUT file found")
            return -9999.0

        # --- 7. Compute KGE ---
        obs = _load_obs_monthly()
        mod = _load_model_monthly(ldasout_files[0])

        obs_set = set(obs["months"])
        mod_set = set(mod["months"])
        common  = sorted(obs_set & mod_set)
        if len(common) < 12:
            print(f"[run_phs] Only {len(common)} common months, skipping")
            return -9999.0

        obs_idx = {m: i for i, m in enumerate(obs["months"])}
        mod_idx = {m: i for i, m in enumerate(mod["months"])}

        obs_lh  = np.array([obs["LH"] [obs_idx[m]] for m in common])
        obs_psn = np.array([obs["PSN"][obs_idx[m]] for m in common])
        mod_lh  = np.array([mod["LH"] [mod_idx[m]] for m in common])
        mod_psn = np.array([mod["PSN"][mod_idx[m]] for m in common])

        kge_lh  = kge(mod_lh,  obs_lh)
        kge_psn = kge(mod_psn, obs_psn)
        total   = kge_lh + kge_psn

        print(
            f"[run_phs] TLP={tlp:.2E} KSAT={ksat:.2E} P50={p50:.2E} "
            f"SPWAI={spwai:.4f} SPWVI={spwvi:.4f} "
            f"→ KGE_LH={kge_lh:.3f}  KGE_PSN={kge_psn:.3f}  SUM={total:.3f}"
        )
        return total

    except Exception as exc:
        print(f"[run_phs] Exception: {exc}")
        return -9999.0

    finally:
        if not keep_dir:
            shutil.rmtree(workdir, ignore_errors=True)
