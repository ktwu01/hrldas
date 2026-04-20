#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  stage_phase3_conus.sh smoke [phs|shs]
  stage_phase3_conus.sh phase3-layout

Commands:
  smoke         Stage a reproducible 1-day CONUS smoke-test run under
                /glade/work/wukoutian/AFM24_experiments/phase3_2d using the
                current workspace hrldas.exe and NoahmpTable.TBL, plus the
                known-good NLDAS smoke forcing/setup files from
                /glade/u/home/wukoutian/LSMs-dev-Review/CONUS_PHS_1day.
  phase3-layout Create the Phase 3 directory skeleton for the full 2011/2012
                CONUS/Texas campaign and raw-file manifests for CONUS 2012 and
                CONUS 2011 from the campaign NLDAS archive.
EOF
}

ROOT="/glade/work/wukoutian/AFM24_experiments/phase3_2d"
REPO="/glade/u/home/wukoutian/hrldas-phs-dev"
SRC_SMOKE="/glade/u/home/wukoutian/LSMs-dev-Review/CONUS_PHS_1day/forcing/LDASIN"
RAW_NLDAS="/glade/campaign/work/twan/NLDAS"

repair_smoke_setup() {
  local setup_file="${ROOT}/forcing/conus_smoke_20000101/LDASIN/HRLDAS_setup_2000010100_d1"

  python - "${setup_file}" <<'PY'
import sys

import numpy as np
from netCDF4 import Dataset

setup_file = sys.argv[1]

with Dataset(setup_file, "r+") as ds:
    xland = np.array(ds.variables["XLAND"][0])
    land = xland == 1

    tsk = np.ma.array(ds.variables["TSK"][0]).filled(np.nan)
    tslb = np.ma.array(ds.variables["TSLB"][0]).filled(np.nan)
    smois = np.ma.array(ds.variables["SMOIS"][0]).filled(np.nan)

    bad_land = land & (
        np.isnan(tsk)
        | np.any(np.isnan(tslb), axis=0)
        | np.any(np.isnan(smois), axis=0)
    )

    if not np.any(bad_land):
        print(f"Smoke setup already clean: {setup_file}")
        sys.exit(0)

    valid_land = land & (
        np.isfinite(tsk)
        & np.all(np.isfinite(tslb), axis=0)
        & np.all(np.isfinite(smois), axis=0)
    )

    donors = np.argwhere(valid_land)
    if donors.size == 0:
        raise SystemExit(f"No valid land donors found in {setup_file}")

    bad_points = np.argwhere(bad_land)
    for j, i in bad_points:
        dist2 = (donors[:, 0] - j) ** 2 + (donors[:, 1] - i) ** 2
        donor_j, donor_i = donors[np.argmin(dist2)]
        ds.variables["TSK"][0, j, i] = ds.variables["TSK"][0, donor_j, donor_i]
        ds.variables["TSLB"][0, :, j, i] = ds.variables["TSLB"][0, :, donor_j, donor_i]
        ds.variables["SMOIS"][0, :, j, i] = ds.variables["SMOIS"][0, :, donor_j, donor_i]
        print(
            "Repaired smoke setup land point "
            f"(i={i + 1}, j={j + 1}) from donor (i={donor_i + 1}, j={donor_j + 1})"
        )
PY
}

write_smoke_namelist() {
  local target=$1
  local run_name=$2
  local btr_option=$3

  cat > "${target}" <<EOF
&NOAHLSM_OFFLINE

 HRLDAS_SETUP_FILE = "${ROOT}/forcing/conus_smoke_20000101/LDASIN/HRLDAS_setup_2000010100_d1"
 INDIR             = "${ROOT}/forcing/conus_smoke_20000101/LDASIN/"
 OUTDIR            = "${ROOT}/runs/${run_name}/output/"

 START_YEAR  = 2000
 START_MONTH = 01
 START_DAY   = 01
 START_HOUR  = 00
 START_MIN   = 00

 KHOUR = 24

 FORCING_NAME_T  = "T2D"
 FORCING_NAME_Q  = "Q2D"
 FORCING_NAME_U  = "U2D"
 FORCING_NAME_V  = "V2D"
 FORCING_NAME_P  = "PSFC"
 FORCING_NAME_LW = "LWDOWN"
 FORCING_NAME_SW = "SWDOWN"
 FORCING_NAME_PR = "RAINRATE"

 DYNAMIC_VEG_OPTION                = 4
 CANOPY_STOMATAL_RESISTANCE_OPTION = 1
 BTR_OPTION                        = ${btr_option}
 SURFACE_RUNOFF_OPTION             = 3
 SUBSURFACE_RUNOFF_OPTION          = 2
 DVIC_INFILTRATION_OPTION          = 1
 SURFACE_DRAG_OPTION               = 1
 FROZEN_SOIL_OPTION                = 1
 SUPERCOOLED_WATER_OPTION          = 1
 RADIATIVE_TRANSFER_OPTION         = 3
 SNOW_ALBEDO_OPTION                = 1
 SNOW_COMPACTION_OPTION            = 2
 SNOW_COVER_OPTION                 = 1
 PCP_PARTITION_OPTION              = 1
 SNOW_THERMAL_CONDUCTIVITY         = 1
 TBOT_OPTION                       = 2
 TEMP_TIME_SCHEME_OPTION           = 3
 GLACIER_OPTION                    = 1
 SURFACE_RESISTANCE_OPTION         = 4
 SOIL_DATA_OPTION                  = 1
 PEDOTRANSFER_OPTION               = 1
 CROP_OPTION                       = 0
 IRRIGATION_OPTION                 = 0
 IRRIGATION_METHOD                 = 0
 TILE_DRAINAGE_OPTION              = 0
 WETLAND_OPTION                    = 0

 FORCING_TIMESTEP = 3600
 NOAH_TIMESTEP    = 1800
 OUTPUT_TIMESTEP  = 3600

 SPLIT_OUTPUT_COUNT       = 1
 SKIP_FIRST_OUTPUT        = .false.
 RESTART_FREQUENCY_HOURS  = 24

 NSOIL=4
 soil_thick_input(1) = 0.10
 soil_thick_input(2) = 0.30
 soil_thick_input(3) = 0.60
 soil_thick_input(4) = 1.00

 ZLVL = 10.0

 SF_URBAN_PHYSICS = 0
 USE_WUDAPT_LCZ   = 0

/
EOF
}

write_smoke_pbs() {
  local target=$1
  local run_name=$2
  local run_dir="${ROOT}/runs/${run_name}"

  cat > "${target}" <<EOF
#!/bin/bash
#PBS -N ${run_name}
#PBS -l select=2:ncpus=36:mpiprocs=36
#PBS -l walltime=01:00:00
#PBS -q casper
#PBS -A UTAA0012
#PBS -o ${run_dir}/logs/run.out
#PBS -e ${run_dir}/logs/run.err

set -euo pipefail

cd "${run_dir}"

module purge
module load ncarenv/25.10
module load intel/2025.2.1
module load ncarcompilers/1.1.0
module load openmpi/5.0.8
module load hdf5/1.14.6
module load netcdf/4.9.3

ulimit -s unlimited

NPROC=\$(wc -l < "\$PBS_NODEFILE")
echo "Starting ${run_name} at \$(date)"
echo "Rundir: ${run_dir}"
echo "Nproc: \${NPROC}"

mpiexec -n "\${NPROC}" ./hrldas.exe > logs/hrldas.log 2>&1
echo "Finished at \$(date) with exit code \$?" >> logs/hrldas.log
EOF
}

stage_smoke() {
  local physics=${1:-phs}
  local run_name
  local btr_option

  case "${physics}" in
    phs)
      run_name="CONUS-PHS-smoke-20000101"
      btr_option=4
      ;;
    shs)
      run_name="CONUS-SHS-smoke-20000101"
      btr_option=1
      ;;
    *)
      echo "Unsupported smoke physics: ${physics}" >&2
      exit 2
      ;;
  esac

  mkdir -p \
    "${ROOT}/forcing/conus_smoke_20000101/LDASIN" \
    "${ROOT}/runs/${run_name}/logs" \
    "${ROOT}/runs/${run_name}/output"

  rsync -a --delete "${SRC_SMOKE}/" "${ROOT}/forcing/conus_smoke_20000101/LDASIN/"
  repair_smoke_setup
  cp "${REPO}/hrldas/run/hrldas.exe" "${ROOT}/runs/${run_name}/hrldas.exe"
  cp "${REPO}/noahmp/parameters/NoahmpTable.TBL" "${ROOT}/runs/${run_name}/NoahmpTable.TBL"

  write_smoke_namelist "${ROOT}/runs/${run_name}/namelist.hrldas" "${run_name}" "${btr_option}"
  write_smoke_pbs "${ROOT}/runs/${run_name}/submit.pbs" "${run_name}"
  chmod +x "${ROOT}/runs/${run_name}/submit.pbs"

  cat <<EOF
Staged ${run_name}
  forcing: ${ROOT}/forcing/conus_smoke_20000101/LDASIN
  rundir:  ${ROOT}/runs/${run_name}
  submit:  qsub ${ROOT}/runs/${run_name}/submit.pbs
EOF
}

write_raw_manifest() {
  local year=$1
  local out=$2
  find "${RAW_NLDAS}" -maxdepth 1 -type f -name "NLDAS_FORA0125_H.A${year}*.002.grb" | sort > "${out}"
}

stage_phase3_layout() {
  local forcing_root="${ROOT}/forcing"
  local runs_root="${ROOT}/runs"
  local logs_root="${ROOT}/logs"
  local analysis_root="${ROOT}/analysis"

  mkdir -p \
    "${forcing_root}/conus_2011/raw" \
    "${forcing_root}/conus_2011/extracted" \
    "${forcing_root}/conus_2011/LDASIN" \
    "${forcing_root}/conus_2011/manifests" \
    "${forcing_root}/conus_2012/raw" \
    "${forcing_root}/conus_2012/extracted" \
    "${forcing_root}/conus_2012/LDASIN" \
    "${forcing_root}/conus_2012/manifests" \
    "${forcing_root}/texas_2011/raw" \
    "${forcing_root}/texas_2011/extracted" \
    "${forcing_root}/texas_2011/LDASIN" \
    "${forcing_root}/texas_2011/manifests" \
    "${runs_root}/CONUS-SHS-2012" \
    "${runs_root}/CONUS-PHS-2012" \
    "${runs_root}/TX-SHS-2011" \
    "${runs_root}/TX-PHS-2011" \
    "${logs_root}" \
    "${analysis_root}"

  write_raw_manifest 2011 "${forcing_root}/conus_2011/manifests/raw_2011_fora_paths.txt"
  write_raw_manifest 2012 "${forcing_root}/conus_2012/manifests/raw_2012_fora_paths.txt"

  cat > "${ROOT}/README.phase3_layout.txt" <<EOF
Phase 3 layout staged by $(basename "$0")

Notes:
- The CONUS smoke-test forcing is staged separately under:
    ${ROOT}/forcing/conus_smoke_20000101/LDASIN
- The full 2011/2012 experiment skeleton is present, but physically correct
  2011/2012 HRLDAS_setup initialization files still need to be generated or
  provided before production runs are submitted.
- Raw NLDAS forcing manifests are recorded in:
    ${forcing_root}/conus_2011/manifests/raw_2011_fora_paths.txt
    ${forcing_root}/conus_2012/manifests/raw_2012_fora_paths.txt
EOF

  cat <<EOF
Staged Phase 3 directory layout at ${ROOT}
Created raw-file manifests for CONUS 2011 and 2012.
EOF
}

main() {
  local cmd=${1:-}
  case "${cmd}" in
    smoke)
      shift
      stage_smoke "${1:-phs}"
      ;;
    phase3-layout)
      stage_phase3_layout
      ;;
    ""|-h|--help|help)
      usage
      ;;
    *)
      echo "Unknown command: ${cmd}" >&2
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
