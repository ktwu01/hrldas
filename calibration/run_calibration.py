"""SCE-UA calibration of PHS at US-Syv using SPOTPY.

Following Sun et al. (2024): SCE-UA optimizer targeting KGE(ET) + KGE(GPP)
at monthly scale, 5 PHS hydraulic parameters for IPHTYP=1 (temperate deciduous).

Usage:
    # Dry run — test wrapper with current table defaults (one HRLDAS run)
    python run_calibration.py --test

    # Full calibration — 1000 SCE-UA evaluations
    python run_calibration.py --reps 1000

    # Lighter run for quick exploration
    python run_calibration.py --reps 200 --output quick_test

Results saved to CSV; best parameter set printed on completion.
Typical budget: ~600 core-hours for 1000 reps × 0.6 hr/run.

References:
  Li et al. (2021) J. Adv. Model. Earth Syst. — ensemble opt. of 5 PHS params
  Sun et al. (2024) — SCE-UA via SPOTPY targeting KGE(ET)+KGE(GPP)
"""

import argparse
import os
import sys

import spotpy
import numpy as np

# Make sure calibration/ is on the path when called from elsewhere
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spotpy_setup import PHS_SpotSetup
from phs_wrapper import run_phs

DEFAULT_REPS   = 1000
DEFAULT_OUTPUT = "calibration_results"


def test_wrapper():
    """Single run with current table defaults to verify infrastructure."""
    print("=== Dry run: testing wrapper with current IPHTYP=1 defaults ===")
    score = run_phs(
        tlp=-1.07e5,
        ksat=2.07e-2,
        p50=-3.22e5,
        spwai=0.0015,
        spwvi=0.0435,
        keep_dir=False,
    )
    if score > -9000:
        print(f"Wrapper OK — KGE_LH + KGE_PSN = {score:.3f}")
    else:
        print("Wrapper FAILED — check paths and template run directory")
    return score


def run_sceua(reps, output):
    print(f"=== SCE-UA calibration: {reps} evaluations → {output}.csv ===")
    setup   = PHS_SpotSetup()
    sampler = spotpy.algorithms.sceua(
        setup,
        dbname=output,
        dbformat="csv",
        random_state=42,
    )
    sampler.sample(reps)

    # Load results and report best
    results  = spotpy.analyser.load_csv_results(output)
    best_idx, best_obj = spotpy.analyser.get_minlikeindex(results)
    best               = results[best_idx]

    print("\n=== Best parameter set ===")
    param_names = ["TLP", "KSAT", "P50", "SPWAI", "SPWVI"]
    for name in param_names:
        val = best[f"par{name}"]
        print(f"  {name:6s} = {val:.4E}")
    obj = best_obj
    print(f"\n  Objective (−KGE sum) = {obj:.4f}")
    print(f"  → KGE_LH + KGE_PSN  ≈ {-obj:.4f}  (target: 2.0)")


def main():
    parser = argparse.ArgumentParser(
        description="SCE-UA calibration of PHS at US-Syv"
    )
    parser.add_argument(
        "--test", action="store_true",
        help="One-shot test: run wrapper with table defaults and exit"
    )
    parser.add_argument(
        "--reps", type=int, default=DEFAULT_REPS,
        help=f"Number of SCE-UA evaluations (default: {DEFAULT_REPS})"
    )
    parser.add_argument(
        "--output", type=str, default=DEFAULT_OUTPUT,
        help=f"Output CSV base name (default: {DEFAULT_OUTPUT})"
    )
    args = parser.parse_args()

    if args.test:
        test_wrapper()
    else:
        run_sceua(args.reps, args.output)


if __name__ == "__main__":
    main()
