#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build_phase3_nldas_conus.sh extract-range START END EXTRACTED_DIR
  build_phase3_nldas_conus.sh build-ldasin START END EXTRACTED_DIR LDASIN_DIR [FULL_IC_FRQ]
  build_phase3_nldas_conus.sh validate-2012-day

Arguments:
  START, END    UTC timestamps in YYYY-MM-DD_HH format.

Commands:
  extract-range   Extract TMP, SPFH, PRES, UGRD, VGRD, DLWRF, DSWRF, APCP
                  from raw NLDAS FORA GRIB1 files into the HRLDAS extracted layout.
  build-ldasin    Run create_forcing.exe against an extracted directory.
                  FULL_IC_FRQ defaults to -1 for FORA-only forcing generation.
  validate-2012-day
                  Convenience command that builds a short CONUS 2012 validation
                  window for 2012-01-01_00 to 2012-01-02_00 under /glade/work.
EOF
}

ROOT="/glade/work/wukoutian/AFM24_experiments/phase3_2d"
RAW_NLDAS="/glade/campaign/work/twan/NLDAS"
REPO="/glade/u/home/wukoutian/hrldas-phs-dev"
CREATE_FORCING_EXE="${REPO}/hrldas/HRLDAS_forcing/create_forcing.exe"
GEO_EM="/glade/u/home/wukoutian/Ori_RPM/hrldas/hrldas/HRLDAS_forcing/run/examples/NLDAS/geo_em.d01_NLDAS0125.nc"
NLDAS_ELEVATION="/glade/u/home/wukoutian/Ori_RPM/hrldas/hrldas/HRLDAS_forcing/run/examples/NLDAS/NLDAS_ELEVATION.grb"
NLDAS_NAMELIST_EXAMPLE="${REPO}/hrldas/HRLDAS_forcing/run/examples/NLDAS/namelist.input.NLDAS"

VARS=(
  "TMP"
  "SPFH"
  "PRES"
  "UGRD"
  "VGRD"
  "DLWRF"
  "DSWRF"
  "APCP"
)

load_extract_tools() {
  module purge >/dev/null 2>&1 || true
  module load ncarenv/25.10 >/dev/null 2>&1
  module load grib-util/1.5.0 >/dev/null 2>&1
}

load_forcing_tools() {
  module purge >/dev/null 2>&1 || true
  module load ncarenv/25.10 >/dev/null 2>&1
  module load intel/2025.2.1 >/dev/null 2>&1
  module load ncarcompilers/1.1.0 >/dev/null 2>&1
  module load openmpi/5.0.8 >/dev/null 2>&1
  module load hdf5/1.14.6 >/dev/null 2>&1
  module load netcdf/4.9.3 >/dev/null 2>&1
}

to_compact_date() {
  date -u -d "${1/_/ }:00" +"%Y%m%d%H"
}

to_raw_stamp() {
  date -u -d "${1/_/ }:00" +"%Y%m%d.%H00"
}

next_hour() {
  local epoch
  epoch=$(date -u -d "${1/_/ }:00" +%s)
  date -u -d "@$((epoch + 3600))" +"%Y-%m-%d_%H"
}

ensure_extracted_dirs() {
  local extracted_dir=$1
  local var
  mkdir -p "${extracted_dir}"
  for var in "${VARS[@]}"; do
    mkdir -p "${extracted_dir}/${var}"
  done
  mkdir -p "${extracted_dir}/INIT"
}

extract_one_hour() {
  local timestamp=$1
  local extracted_dir=$2
  local raw_stamp compact_date raw_file

  raw_stamp=$(to_raw_stamp "${timestamp}")
  compact_date=$(to_compact_date "${timestamp}")
  raw_file="${RAW_NLDAS}/NLDAS_FORA0125_H.A${raw_stamp}.002.grb"

  if [[ ! -f "${raw_file}" ]]; then
    echo "Missing raw NLDAS file: ${raw_file}" >&2
    exit 1
  fi

  wgrib -s "${raw_file}" | grep ':TMP:'   | wgrib -i -grib "${raw_file}" -o "${extracted_dir}/TMP/NLDAS_TMP.${compact_date}.grb" >/dev/null
  wgrib -s "${raw_file}" | grep ':SPFH:'  | wgrib -i -grib "${raw_file}" -o "${extracted_dir}/SPFH/NLDAS_SPFH.${compact_date}.grb" >/dev/null
  wgrib -s "${raw_file}" | grep ':PRES:'  | wgrib -i -grib "${raw_file}" -o "${extracted_dir}/PRES/NLDAS_PRES.${compact_date}.grb" >/dev/null
  wgrib -s "${raw_file}" | grep ':UGRD:'  | wgrib -i -grib "${raw_file}" -o "${extracted_dir}/UGRD/NLDAS_UGRD.${compact_date}.grb" >/dev/null
  wgrib -s "${raw_file}" | grep ':VGRD:'  | wgrib -i -grib "${raw_file}" -o "${extracted_dir}/VGRD/NLDAS_VGRD.${compact_date}.grb" >/dev/null
  wgrib -s "${raw_file}" | grep ':DLWRF:' | wgrib -i -grib "${raw_file}" -o "${extracted_dir}/DLWRF/NLDAS_DLWRF.${compact_date}.grb" >/dev/null
  wgrib -s "${raw_file}" | grep ':DSWRF:' | wgrib -i -grib "${raw_file}" -o "${extracted_dir}/DSWRF/NLDAS_DSWRF.${compact_date}.grb" >/dev/null
  wgrib -s "${raw_file}" | grep ':APCP:'  | wgrib -i -grib "${raw_file}" -o "${extracted_dir}/APCP/NLDAS_APCP.${compact_date}.grb" >/dev/null
}

extract_range() {
  local start=$1
  local end=$2
  local extracted_dir=$3
  local current

  load_extract_tools
  ensure_extracted_dirs "${extracted_dir}"

  current="${start}"
  while :; do
    echo "Extracting ${current}"
    extract_one_hour "${current}" "${extracted_dir}"
    [[ "${current}" == "${end}" ]] && break
    current=$(next_hour "${current}")
  done
}

write_namelist() {
  local start=$1
  local end=$2
  local extracted_dir=$3
  local ldasin_dir=$4
  local full_ic_frq=$5
  local target=$6

  cat > "${target}" <<EOF
&files
 STARTDATE          = "${start}"
 ENDDATE            = "${end}"
 DataDir            = "${extracted_dir}"
 OutputDir          = "${ldasin_dir}/"
 FORCING_TYPE       = "NLDAS"
 FULL_IC_FRQ        = ${full_ic_frq}
 RAINFALL_INTERP    = 0
 RESCALE_SHORTWAVE  = .FALSE.
 UPDATE_SNOW        = .FALSE.
 FORCING_HEIGHT_2D  = .FALSE.
 TRUNCATE_SW        = .FALSE.
 EXPAND_LOOP        = 1
 INIT_LAI           = .TRUE.
 VARY_LAI           = .TRUE.
 MASK_WATER         = .TRUE.

 geo_em_flnm        = "${GEO_EM}"
 Zfile_template     = "${NLDAS_ELEVATION}"

 Tfile_template     = "<DataDir>/TMP/NLDAS_TMP.<date>.grb"
 Ufile_template     = "<DataDir>/UGRD/NLDAS_UGRD.<date>.grb",
 Vfile_template     = "<DataDir>/VGRD/NLDAS_VGRD.<date>.grb",
 Pfile_template     = "<DataDir>/PRES/NLDAS_PRES.<date>.grb",
 Qfile_template     = "<DataDir>/SPFH/NLDAS_SPFH.<date>.grb",
 LWfile_template    = "<DataDir>/DLWRF/NLDAS_DLWRF.<date>.grb",
 SWfile_primary     = "<DataDir>/DSWRF/NLDAS_DSWRF.<date>.grb",
 SWfile_secondary   = "<DataDir>/DSWRF/NLDAS_DSWRF.<date>.grb",
 PCPfile_primary    = "<DataDir>/APCP/NLDAS_APCP.<date>.grb"
 PCPfile_secondary  = "<DataDir>/APCP/NLDAS_APCP.<date>.grb",

 WEASDfile_template = "<DataDir>/INIT/NLDAS_WEASD.<date>.grb",
 CANWTfile_template = "<DataDir>/INIT/NLDAS_CNWAT.<date>.grb",
 SKINTfile_template = "<DataDir>/INIT/NLDAS_AVSFT.<date>.grb",

 STfile_template    = "<DataDir>/INIT/NLDAS_TSOIL_000-010.<date>.grb",
                      "<DataDir>/INIT/NLDAS_TSOIL_010-040.<date>.grb",
                      "<DataDir>/INIT/NLDAS_TSOIL_040-100.<date>.grb",
                      "<DataDir>/INIT/NLDAS_TSOIL_100-200.<date>.grb",

 SMfile_template    = "<DataDir>/INIT/NLDAS_SOILM_000-010.<date>.grb",
                      "<DataDir>/INIT/NLDAS_SOILM_010-040.<date>.grb",
                      "<DataDir>/INIT/NLDAS_SOILM_040-100.<date>.grb",
                      "<DataDir>/INIT/NLDAS_SOILM_100-200.<date>.grb",
/
EOF

  sed -n '/<VTABLE>/,$p' "${NLDAS_NAMELIST_EXAMPLE}" >> "${target}"
}

build_ldasin() {
  local start=$1
  local end=$2
  local extracted_dir=$3
  local ldasin_dir=$4
  local full_ic_frq=${5:--1}
  local namelist="${ldasin_dir}/namelist.input.NLDAS"

  load_forcing_tools
  mkdir -p "${ldasin_dir}"
  write_namelist "${start}" "${end}" "${extracted_dir}" "${ldasin_dir}" "${full_ic_frq}" "${namelist}"

  (
    cd "${REPO}/hrldas/HRLDAS_forcing"
    "${CREATE_FORCING_EXE}" "${namelist}"
  )

  if ! find "${ldasin_dir}" -maxdepth 1 -type f -name '*.LDASIN_DOMAIN1' | grep -q .; then
    echo "create_forcing.exe did not produce any LDASIN files in ${ldasin_dir}" >&2
    exit 1
  fi
}

validate_2012_day() {
  local base="${ROOT}/forcing/conus_2012"
  local extracted_dir="${base}/extracted_20120101_20120102"
  local ldasin_dir="${base}/LDASIN_20120101_20120102"
  local start="2012-01-01_00"
  local end="2012-01-02_00"

  extract_range "${start}" "${end}" "${extracted_dir}"
  build_ldasin "${start}" "${end}" "${extracted_dir}" "${ldasin_dir}" -1

  echo "Validated short CONUS 2012 forcing build"
  echo "  extracted: ${extracted_dir}"
  echo "  ldasin:    ${ldasin_dir}"
}

main() {
  local cmd=${1:-}

  case "${cmd}" in
    extract-range)
      [[ $# -eq 4 ]] || { usage >&2; exit 2; }
      extract_range "$2" "$3" "$4"
      ;;
    build-ldasin)
      [[ $# -ge 5 && $# -le 6 ]] || { usage >&2; exit 2; }
      build_ldasin "$2" "$3" "$4" "$5" "${6:--1}"
      ;;
    validate-2012-day)
      validate_2012_day
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
