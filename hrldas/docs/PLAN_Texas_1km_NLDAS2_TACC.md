# Plan: Offline Noah-MP Simulation over Texas at 1 km, NLDAS-2 Forced, on TACC

Status: draft for student review
Date: 2026-05-26
Model: Noah-MP v5.2.0 (this repo) + HRLDAS offline driver (external)

## 1. Objective

Produce Noah-MP land-surface output for **Texas** with these deliverables:

| Field | Noah-MP field (internal) | LDASOUT string (verify) | Units |
|-------|--------------------------|-------------------------|-------|
| Soil moisture | `SMOIS` total / `SH2O` liquid | `SOIL_M` / `SOIL_W` | m3 m-3 |
| Soil temperature | `TSLB` | `SOIL_T` | K |
| Latent heat flux | `LH` | `LH` | W m-2 |

Internal names confirmed in `drivers/hrldas/NoahmpIOVarType.F90`. The LDASOUT
*output* variable strings are defined in the HRLDAS driver and have varied
across versions, so confirm the exact names once with `ncdump -h
<YYYYMMDDHH>.LDASOUT_DOMAIN1` in the smoke test (Section 5b) before using them in
the deliverable.

- Output cadence: **3-hourly or 6-hourly** (`OUTPUT_TIMESTEP = 10800` or `21600`).
- Model grid: **1 km**.
- Forcing: **NLDAS-2** (~0.125 deg, ~12.5 km), confirmed acceptable by the requester.
- Compute: **TACC**.
- Time period: one full year (see Section 5 for picking it).

## 2. Important caveat the student must understand first

**The forcing is ~12.5 km; the requested output grid is 1 km.** Noah-MP can run on a 1 km grid using NLDAS-2 forcing interpolated to that grid, and this is a legitimate, common setup. But be honest about what it means:

- Land-surface **static fields** (land use, soil texture, terrain, vegetation) will be at true 1 km resolution, so soil moisture/temperature and LH **will** show 1 km spatial structure driven by surface heterogeneity.
- The **atmospheric forcing** (rain, radiation, temperature, wind) carries only ~12.5 km information, smoothly interpolated onto the 1 km grid. There is no sub-12.5 km meteorological detail.

Net effect: you get a 1 km product whose fine-scale variability comes from the land surface, not the atmosphere. That is scientifically fine for many soil-moisture/flux studies. If true 1 km meteorology is required, NLDAS-2 is the wrong forcing (AORC at ~800 m would be needed). **The requester accepted NLDAS-2, so this plan proceeds on the 1 km-grid / 12.5 km-forcing basis, and the limitation should be stated in any writeup of the results.**

**One correction to the "no sub-12.5 km detail" framing:** interpolation should NOT be a naive smooth interpolation. Elevation varies strongly at 1 km across Texas (Guadalupe Mountains, Edwards Plateau, High Plains escarpment), and the 12.5 km cell-mean elevation differs from the 1 km true elevation. Temperature, surface pressure, and downward longwave radiation **must be elevation-corrected** to the 1 km terrain during forcing prep, which `create_forcing.exe` does automatically using `NLDAS_ELEVATION.grb` (Section 6, Phase C). Done correctly, the 1 km forcing therefore *does* carry real high-resolution structure in T/PSFC/LWDOWN driven by terrain, even though the underlying weather systems remain ~12.5 km. The caveat to document is narrower than "no 1 km detail": it is that **sub-12.5 km precipitation, wind, and cloud/radiation weather structure is absent**, while terrain-driven thermodynamic structure is present.

## 3. Architecture: what this repo is, and what else is needed

This repository (`/Users/kw35262/Documents/dev/noahmp`) contains the **Noah-MP physics library AND the HRLDAS offline driver interface** under `drivers/hrldas/` (e.g., `NoahmpDriverMainMod.F90`, `NoahmpReadNamelistMod.F90`). What it does **not** contain is the build-options file, the top-level offline program glue, and the forcing/grid preprocessing tools: the driver `Makefile` explicitly includes `../../../hrldas/user_build_options`, and `README.md` directs offline users to the **HRLDAS** repo (https://github.com/NCAR/hrldas) for the runnable system and its preprocessing utilities.

Practical reading of this: the offline build root is **HRLDAS**, which embeds this `noahmp` repo as a git submodule. Clone with `git clone --recurse-submodules https://github.com/NCAR/hrldas`; that pulls a matching `noahmp` into `hrldas/noahmp/`. `./configure` writes `user_build_options`, `make` produces `hrldas.exe` and `create_forcing.exe`. Do not assume an arbitrary HRLDAS commit pairs cleanly with this v5.2.0 `noahmp`; use the submodule-pinned pairing to avoid an interface-version conflict.

The offline workflow therefore has three external pieces beyond the physics/driver in this repo:

1. **HRLDAS build options + forcing/setup tools** (external, version-matched): `user_build_options` for TACC, plus utilities to prepare forcing and the setup file.
2. **WPS/geogrid** (or HRLDAS setup tool): creates the 1 km static grid file (`HRLDAS_SETUP_FILE`).
3. **NLDAS-2 data**: downloaded from NASA GES DISC, then regridded/downscaled to the 1 km grid in HRLDAS-readable NetCDF.

Driver/namelist files this plan relies on (verified in repo):

| Component | Path |
|-----------|------|
| Offline driver main | `drivers/hrldas/NoahmpDriverMainMod.F90` |
| Namelist reader (authoritative var list) | `drivers/hrldas/NoahmpReadNamelistMod.F90` |
| Noah-MP source Makefile | `src/Makefile` |
| HRLDAS driver Makefile (expects `../../../hrldas/user_build_options`) | `drivers/hrldas/Makefile` |
| Parameter table | `parameters/NoahmpTable.TBL` |
| Tech note | `docs/NoahMP_v5_technote.pdf` |

## 4. Domain and grid sizing

Texas bounding box (full state, generous margin):
- Latitude: ~25.8 N to ~36.5 N
- Longitude: ~106.7 W to ~93.5 W

At 1 km (Lambert Conformal recommended, two true latitudes ~30/35 N):
- East-west extent ~1200 km, north-south ~1180 km.
- Grid: roughly **1200 x 1180 ≈ 1.42 million cells** (the exact `e_we`/`e_sn` come out of geogrid; budget ~1.4-1.6M cells).

This is the single most important number for cost. Confirm the exact bounding box with the student before running geogrid; a tighter box (Texas land only, trimming Gulf and Mexico) reduces cost.

The model can be run over the full geogrid domain, or subset at runtime with `xstart/xend/ystart/yend` in the namelist (verified present in `NoahmpReadNamelistMod.F90`).

## 5. Choosing the year and spin-up (this matters for the requested variables)

Soil moisture and soil temperature are **slow-memory** variables. A cold start contaminates them for months to years. The two requested state variables are exactly the ones spin-up protects. Plan:

- **Pick one analysis year**, e.g. **2018** (NLDAS-2 covers 1979-present, so any recent full year works; 2018 is a reasonable non-extreme year over Texas). Final choice is the student's.
- **Spin-up**: run the year (or a multi-year lead-in) repeatedly until soil states stabilize. Two mechanisms:
  - `SPINUP_LOOPS = N` repeats the simulation window N times before the production run (verified as a native namelist variable in `NoahmpReadNamelistMod.F90` for v5.2.0; cheapest if using a single year), or
  - an **external restart loop**: run one year, rename the output `RESTART` file, point `RESTART_FILENAME_REQUESTED` at it, and repeat via a shell script. Use this if `SPINUP_LOOPS` behaves unexpectedly in the HRLDAS build, or to chain multiple distinct forcing years.
  - **How long**: 2 years is NOT enough. West Texas is semi-arid to arid (Chihuahuan Desert, High Plains), and the deep soil layers (down to 2.0 m) take many years to equilibrate from a cold start. Target **5-10 equivalent years** of spin-up, and verify convergence (Section 6, Phase F) rather than assuming a fixed count. Use one mechanism, not both: a non-zero `SPINUP_LOOPS` with a restart file re-loops an already-equilibrated state. State the choice in the writeup.
- Production output is written only for the analysis year.

## 5b. Budget estimate and mandatory smoke test

Do not submit the full ~1.4M-cell, multi-year job blind. Estimate the budget, then **measure** it with a smoke test and scale up.

**Compute (a priori):**
```
total_model_steps = (KHOUR x 3600 / NOAH_TIMESTEP) x (1 + SPINUP_LOOPS)
                  = (8760 x 3600 / 1800) x (1 + 8) = 17520 x 9 = 157,680 steps
core_seconds     ~= cells x total_model_steps x per_cell_step_cost
```
`per_cell_step_cost` is machine/compiler specific; get it from the smoke test rather than guessing. Note the ~9x spin-up multiplier dominates the cost.

**Storage (often the real bottleneck on TACC `$SCRATCH`):** estimate a priori, then pin it with the smoke test.

A priori bound:
```
bytes ~= cells x n_output_vars x (sim_seconds / OUTPUT_TIMESTEP) x 4
       ~= 1.4e6 x 40 x 2920 x 4 ~= 6.5e11 ~= ~650 GB uncompressed  (production year)
```
This ignores headers, per-file overhead, and compression, so it is easily 2x off. Pin it with the smoke test:
```
bytes_per_cell_per_outstep = (one smoke LDASOUT file size) / (cells in smoke subdomain)
prod_bytes = bytes_per_cell_per_outstep x cells_full_domain x (production_seconds / OUTPUT_TIMESTEP)
```
`prod_bytes` is the number checked against quota. Hundreds of GB to low TB. Mitigations: confirm `$SCRATCH`/`$WORK` quota first; enable netCDF deflate compression; and **subset the output to just soil moisture / soil temp / LH** (via the HRLDAS output variable list), which cuts the ~40-field volume by roughly an order of magnitude. Discard spin-up output.

**Smoke test (run BEFORE the production job, Phase D):**
1. Build, then run the provided single-point case and a tiny 3-day CONUS slice to confirm the executable + forcing pipeline.
2. Run a 3-7 day window on a small `xstart/xend/ystart/yend` subset of the real Texas domain, on the target TACC node type with production flags (`-O3`).
3. Measure and scale each to production:
   - compute: wall time, cells, steps -> `per_cell_step_cost` -> x full cells x full steps x (1 + `SPINUP_LOOPS`);
   - storage: one LDASOUT file size / slab cells -> `bytes_per_cell_per_outstep` -> x full cells x production outsteps (formula above);
   - memory: peak RAM per MPI rank, to size ranks-per-node for the full domain.
4. Only then size the production SLURM request (nodes, walltime) and confirm scaled storage fits quota. If the estimate is surprising, revisit bounding box, cadence, or output variable subset before committing node-hours.

## 6. Step-by-step execution plan

### Phase A — Build on TACC
1. Choose TACC system (Frontera / Stampede3 / Lonestar6) and load the matching toolchain (Intel `ifort`/`ifx` + Intel-MPI + NetCDF/HDF5 + Jasper modules). Record exact module versions.
2. Clone the offline system with submodules: `git clone --recurse-submodules https://github.com/NCAR/hrldas` (embeds the `noahmp` submodule). Run `./configure` (TACC -> an Intel MPI option) and edit `user_build_options` for the NetCDF/Jasper paths (`nc-config`), `-O3`. See the skill's `getting-started.md`.
3. `make clean && make`; confirm `run/hrldas.exe` and `HRLDAS_forcing/create_forcing.exe` both build.
4. Build smoke test: run the shipped single-point (Bondville) case to confirm the executable works before scaling up. (Domain/budget smoke test is Phase D.)

### Phase B — Static grid (HRLDAS_SETUP_FILE) at 1 km
5. Run WPS geogrid (or HRLDAS setup tool) for the Texas LCC 1 km domain to produce `geo_em.d01.nc`.
6. Choose static datasets: MODIS land use (USGS categories work with default `NoahmpTable.TBL`), default soil texture (STATSGO; SSURGO is higher-res but optional and heavier). Confirm `SOIL_DATA_OPTION` matches the soil dataset.
7. Convert geogrid output into the HRLDAS setup file with the required fields: `XLAT, XLONG, HGT, MAPFAC_*, SHDMAX, SHDMIN, XLAND, IVGTYP, ISLTYP, DZS, ZS, TMN, SEAICE` (LAI optional).

### Phase C — Forcing (NLDAS-2 -> 1 km LDASIN via `create_forcing.exe`)

Use the HRLDAS forcing preprocessor (`create_forcing.exe`), which handles regridding onto the target `geo_em` grid and the elevation height-adjustment of temperature and pressure automatically. Do NOT hand-code interpolation; the tool exists for exactly this. See HRLDAS `README.NLDAS` and the skill's `running-2d-domain.md`.

8. Download NLDAS-2 hourly forcing (NLDAS_FORA0125_H, GRIB) from NASA GES DISC for the analysis year plus spin-up years. Requires a free Earthdata login. NLDAS-2 covers CONUS (25-53 N, 125-67 W), which fully contains Texas; coverage 1979-present (with a days-to-weeks lag, so use a closed past year).
9. Extract per-variable GRIB fields with `extract_nldas.perl` (creates `TMP, SPFH, UGRD, VGRD, PRES, DLWRF, DSWRF, APCP` subdirs). Uncompress `NLDAS_ELEVATION.grb.gz` and set `Zfile_template = "NLDAS_ELEVATION.grb"` in `namelist.input.NLDAS` so the tool height-adjusts T and PSFC onto the 1 km terrain.
10. Run `create_forcing.exe namelist.input.NLDAS` pointed at the Texas 1 km `geo_em` to produce hourly `LDASIN_DOMAIN1.YYYYMMDDHH.nc` plus the `HRLDAS_setup_YYYYMMDDHH_d1` initial-state file. This writes the forcing variable names Noah-MP expects (`T2D, Q2D, U2D, V2D, PSFC, LWDOWN, SWDOWN, RAINRATE`).
11. Resolution caveat (Section 2): `create_forcing.exe` gives real 1 km terrain-driven structure in T/PSFC, but precip/wind/cloud weather remains ~12.5 km. Confirm precipitation and winds look physically reasonable on the 1 km grid in the smoke test.
12. Timesteps: `FORCING_TIMESTEP = 3600` (NLDAS-2 hourly). Set the **internal model step shorter than the forcing step** for stability at 1 km: `NOAH_TIMESTEP = 1800` (drop to `900` if instability appears at sunrise/sunset or during intense convective precip). Do not leave it at 3600.

### Phase D — Smoke test and budget scaling (BEFORE production)
13. Run the smoke test from Section 5b: a 3-7 day window on a small `xstart/xend/ystart/yend` subset, on the target TACC node type with production flags. Measure wall time, cells, steps, output bytes.
14. Scale to the full domain x full period x (1 + `SPINUP_LOOPS`); confirm the compute fits the allocation and storage fits `$SCRATCH` quota. Adjust bounding box / cadence / output-variable subset if the scaled estimate is too large before committing.

### Phase E — Production run
15. Configure `namelist.hrldas` (template in Section 7).
16. Submit via SLURM with MPI domain decomposition across nodes, sized from the Phase D scaling. The spin-up (~9x the year) dominates cost. Use `RESTART_FREQUENCY_HOURS` to checkpoint so jobs are resumable.
17. Run order: spin-up (output discarded) then the production year with `OUTPUT_TIMESTEP` set to 3 h or 6 h. Subset the output variable list to `SOIL_M`/`SOIL_T`/`LH` to control storage if the full default set is not needed.

### Phase F — Verify and deliver
18. Confirm output files contain the soil-moisture/soil-temp/LH fields at the requested cadence; verify the exact LDASOUT variable strings with `ncdump -h` (Section 1) and use those names downstream. **Verify spin-up convergence**: compare deep-layer soil-moisture annual-mean fields between successive spin-up cycles and confirm the year-to-year change is below a small tolerance, especially over West Texas. If still drifting, add cycles.
19. Sanity-check against an independent reference (e.g., NLDAS-2 NOAH soil moisture climatology, or SMAP/ESA-CCI surface soil moisture pattern) for gross errors.
20. Package output + a short README describing domain, period, forcing, the `create_forcing.exe` elevation adjustment, spin-up length and convergence evidence, physics options, output variable names, and the precip/wind sub-12.5 km caveat from Section 2.

## 7. Namelist template (`namelist.hrldas`, NOAHLSM_OFFLINE block)

Variable names verified against `drivers/hrldas/NoahmpReadNamelistMod.F90` (v5.2.0).

```fortran
&NOAHLSM_OFFLINE
  HRLDAS_SETUP_FILE  = "./setup/geo_em_texas_1km.nc"
  INDIR              = "./forcing"        ! 1km NLDAS-2-derived hourly NetCDF
  OUTDIR             = "./output"

  START_YEAR  = 2018
  START_MONTH = 1
  START_DAY   = 1
  START_HOUR  = 0
  START_MIN   = 0
  KHOUR       = 8760                       ! 365-day production year (8784 if leap)

  NSOIL            = 4
  soil_thick_input = 0.10, 0.30, 0.60, 1.00

  FORCING_TIMESTEP = 3600                  ! NLDAS-2 hourly
  NOAH_TIMESTEP    = 1800                   ! < forcing step for 1km stability (drop to 900 if needed)
  OUTPUT_TIMESTEP  = 10800                 ! 3-hourly (use 21600 for 6-hourly)

  NOAHMP_OUTPUT           = 0              ! standard output set (includes SOIL_M, SOIL_T, LH)
  SKIP_FIRST_OUTPUT       = .false.
  RESTART_FREQUENCY_HOURS = 24
  ! Spin-up: use ONE mechanism. Native loops -> SPINUP_LOOPS>0 and restart blank.
  ! External restart -> SPINUP_LOOPS=0 and START_* must match the restart timestamp.
  RESTART_FILENAME_REQUESTED = " "         ! blank when SPINUP_LOOPS > 0
  SPINUP_LOOPS = 8                         ! ~5-10 equiv years (Phase F convergence check); 0 if using a restart

  ! grid subset (optional; defaults run full geogrid domain)
  ! XSTART = 1
  ! XEND   = 0
  ! YSTART = 1
  ! YEND   = 0
/

&NOAHMP_OFFLINE_PHYSICS
  ! Standard recommended physics; adjust only with reason.
  DYNAMIC_VEG_OPTION                = 4
  CANOPY_STOMATAL_RESISTANCE_OPTION = 1
  BTR_OPTION                        = 1
  SURFACE_RUNOFF_OPTION             = 3
  SUBSURFACE_RUNOFF_OPTION          = 3
  SURFACE_DRAG_OPTION               = 1
  SUPERCOOLED_WATER_OPTION          = 1
  FROZEN_SOIL_OPTION                = 1
  RADIATIVE_TRANSFER_OPTION         = 3
  SNOW_ALBEDO_OPTION                = 1
  PCP_PARTITION_OPTION              = 1
  TBOT_OPTION                       = 2
  TEMP_TIME_SCHEME_OPTION           = 1
  GLACIER_OPTION                    = 1
  SURFACE_RESISTANCE_OPTION         = 1
  SOIL_DATA_OPTION                  = 1
  PEDOTRANSFER_OPTION               = 1
  CROP_OPTION                       = 0
  IRRIGATION_OPTION                 = 0
/
```

Notes:
- The exact physics-block name/contents should be reconciled against the HRLDAS-provided example `namelist.hrldas`; option *names* above match the v5.2.0 reader, but HRLDAS owns the final namelist file layout.
- Soil moisture, soil temperature, and LH are part of the standard output set (`NOAHMP_OUTPUT = 0`); no special flag needed. Confirm the exact LDASOUT variable strings with `ncdump -h` (Section 1).

## 8. Open items needing the student's confirmation

1. **Exact Texas bounding box** (full state with Gulf/Mexico margin, or land-only tight box). Drives cost.
2. **Analysis year** (default suggestion 2018) and **spin-up length** (`SPINUP_LOOPS` ~8, i.e. 5-10 equivalent years, vs a multi-year lead-in).
3. **Output cadence**: 3-hourly or 6-hourly (template defaults to 3-hourly).
4. **TACC system + allocation** (Frontera / Stampede3 / Lonestar6) and whether the build is in scope here.
5. **Soil/land-use datasets** at 1 km (defaults: MODIS/USGS land use, STATSGO soil) unless the student needs SSURGO.

## 9. Risks

- **Forcing prep correctness**: `create_forcing.exe` handles the regridding and T/PSFC elevation adjustment, so this is less hand-coding than it first appears, but it is still where silent errors hide. Verify in the smoke test that precipitation is non-zero and spatially sensible (a common failure is a missing `APCP` extraction) and that winds are physical on the 1 km grid.
- **HRLDAS version pairing**: the offline system is built from a version-matched HRLDAS checkout that embeds the `noahmp` submodule (`git clone --recurse-submodules https://github.com/NCAR/hrldas`). A mismatched submodule commit can fail to build or wire the v5.2.0 interface incorrectly. Confirm the intended pairing; the build smoke test de-risks this early.
- **Forcing/grid mismatch** (Section 2): document the narrow caveat correctly — sub-12.5 km precip/wind/cloud structure is absent, terrain-driven thermodynamic structure is present. Do not present the output as full 1 km meteorology.
- **Spin-up neglect**: skipping or under-running it makes the headline variables (soil moisture/temperature) unreliable, especially deep layers over West Texas. Target 5-10 equivalent years and verify convergence; do not assume a fixed loop count is enough.
- **Compute + storage budget overrun**: ~1.4M cells x ~9x spin-up for compute; ~hundreds of GB to low TB of LDASOUT. Do the Phase D smoke test and confirm allocation + `$SCRATCH` quota before the production submit; subset output variables to control storage.
```
