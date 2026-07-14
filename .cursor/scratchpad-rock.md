# Why the `rock` branch exists (Noah-MP + HRLDAS)

> Companion to `.cursor/scratchpad.md` (workflow/branching). This doc records the
> *scientific and engineering rationale* for the `rock` variant so the branch's
> purpose survives context loss. Last updated: 2026-07-14.

## One-line answer

The `rock` branch will extend Noah-MP's fixed 2-m, 4-layer soil column down
through the weathered bedrock (saprolite + fractured rock) to the unweathered
bedrock contact — up to ~50 m — so the model can store and release **rock
moisture**, the water in the deep vadose zone that real ecosystems draw on
during droughts and that the stock model cannot represent at all.

## Scientific motivation (Experiment 2: Deep Vadose Zone & Rock Moisture)

Stock Noah-MP truncates the subsurface at 2 m. Everything below is either an
abstract lumped aquifer (SIMGM/MMF) or simply absent. But field evidence
(Critical Zone Observatories; Rempe & Dietrich-style rock-moisture studies)
shows that in much of CONUS the weathered bedrock zone:

1. **Stores plant-available water** — trees transpire through multi-month dry
   seasons on water held in saprolite/fractured rock, long after the 2-m soil
   column has dried out.
2. **Routes recharge** — infiltration pulses move through fractures quickly
   (bypass flow) while the rock matrix absorbs and retains water slowly. A
   single-porosity 2-m column gets both the timing and the partitioning wrong.
3. **Carries hydrologic memory** — deep vadose deficits built up in one drought
   persist for years (severe multi-year deficits observed at the White Family
   Outdoor Learning Center), which a 2-m column cannot hold.

Consequences of the missing store in the stock model: dry-downs are too fast,
latent heat collapses too early in droughts, terrestrial water storage
anomalies (GRACE-scale) are under-amplified, and drought stress onset is
mistimed. The `rock` branch exists to fix the *right-answers-for-right-reasons*
problem: matching fluxes by adding the physically real reservoir, not by
tuning soil parameters to compensate.

## Design (what the branch will implement)

- **Dynamic column extension**: soil column extended from 2 m down to the
  unweathered bedrock contact per grid cell (up to ~50 m). Regolith thickness
  prescribed spatially across CONUS from **Pelletier et al. (2016)**.
- **Dual-porosity weathered zone**:
  - *Matrix porosity* → high-retention storage (sustains ET, slow release).
  - *Fracture porosity* → rapid percolation and groundwater recharge.
- **Depth-decaying hydraulics**: baseline `Ksat`, `θsat` from surface
  lithology, attenuated with exponential decay controlled by an e-folding
  depth parameter `f`.
- **Aquifer coupling**: bottom of the deep vadose zone couples directly to
  Noah-MP's unconfined aquifer scheme (SIMGM or MMF) — capillary rise and
  dynamic water table both permitted.

## Calibration & spin-up plan

- **Spin-up**: 30–90 yr of cycled historical forcing to reach dynamic
  equilibrium — deep reservoirs have massive memory, so short spin-ups leave
  the store drifting and contaminate every metric.
- **Calibration**: parameter regionalization — lithology-informed priors,
  constrained to physically plausible bounds, to fight equifinality (fracture
  porosity and `f` are weakly observable and would otherwise trade off freely).

## Validation & success criteria (two timescales, by design)

| Scale | Test | Data | Success criterion |
|---|---|---|---|
| Event → sub-seasonal | Are infiltration pulses routed correctly (fracture bypass vs matrix absorption)? | AmeriFlux towers, CZO boreholes | Lower RMSE / higher KGE for latent heat and dry-down timescales |
| Seasonal → interannual | Does rock moisture delay hydraulic stress and sustain dry-season transpiration? | GRACE/GRACE-FO TWSA at major-basin scale (~300 km) | Improved TWSA amplitude & phase, esp. 2011 Texas and 2011–2016 California droughts; match observed dry-season transpiration persistence and multi-year vadose deficits at the White Family Outdoor Learning Center |

The two-scale split is deliberate: a model can nail seasonal storage with
wrong fast physics (or vice versa); requiring both closes the
compensating-error loophole.

## Code touchpoints in Noah-MP v5.1.1 (where the work lands)

Current `rock` tip = `67d75ab` = clean v5.1.1 + docs (identical to `shs`);
**no rock physics implemented yet**. Expected surfaces:

- **Column geometry**: `NSOIL` / `soil_thick_input` in the HRLDAS namelist
  (currently 4 layers: 0.10/0.30/0.60/1.00 m). Needs per-cell layer counts or
  a generous fixed deep discretization with per-cell bedrock-contact masking.
- **Richards solver**: `SoilWaterMainMod.F90`,
  `SoilWaterDiffusionRichardsMod.F90`, `SoilMoistureSolverMod.F90` — where
  dual-porosity (matrix + fracture) has to enter.
- **Aquifer schemes**: `GroundWaterTopModelMod.F90` (SIMGM),
  `GroundWaterMmfMod.F90` (MMF), plus the `RunoffSubSurface*Mod.F90` family —
  bottom-boundary coupling. NB: MMF already does its own below-2-m water-table
  bookkeeping; overlap must be reconciled, not duplicated.
- **Root uptake / ET**: `SoilWaterTranspirationMod.F90` — roots (or at least
  hydraulic access) must reach the rock-moisture store or the whole point is
  lost.
- **Thermal column**: `GroundThermalPropertyMod.F90` and the deep-soil
  temperature boundary (`TBOT`) — a 50-m water column with a 2-m heat column
  is inconsistent.
- **Static inputs**: new 2-D regolith-thickness field (Pelletier 2016) and
  lithology-derived parameter maps through the HRLDAS setup/preprocessing
  path.
- **I/O & restarts**: soil-layer dimension is baked into HRLDAS restart and
  output files; deep columns change file shapes → old restarts incompatible.

Encouraging precedent already upstream: v5.1.1 commit `4adebf3` ("change
hard-coded soil depth to generic in ZWT init") — evidence that hard-coded
2-m/4-layer assumptions exist, are scattered, and that upstream accepts
generalizing them.

## Why a dedicated branch (not a flag on `main`/`shs`)

1. **Invasive**: changing the soil-column dimension touches memory layout,
   init, solver loops, restart/output shapes — far beyond an option switch.
2. **Long-lived**: multi-decadal spin-ups and CONUS calibration mean this
   variant runs for months; it needs a stable, independently pinned code line
   (hrldas `rock` ↔ noahmp `rock`, per the 1:1 pairing scheme).
3. **Isolation from other variants**: `phs` (plant hydraulics), `wood`, `ai`
   must stay comparable against an unmodified baseline; deep-column changes
   would contaminate those comparisons.
4. **History**: the original rock branch was corrupted and archived
   (`rock-legacy`, recovery attempt in `rock-legacy-orphan-recovery`); current
   `rock` is a clean restart rebased onto `shs`/v5.1.1.

## Known risks / open design questions

- **Dual-porosity in a single-continuum solver**: options range from a simple
  fracture bypass-flow term (cheap, defensible) to full dual-permeability with
  a matrix–fracture exchange term (expensive, more parameters). Decide early —
  it dictates the solver refactor.
- **Numerics**: thin surface layers + 50-m depth → strong layer-thickness
  stretching; watch tridiagonal conditioning and mass balance at the
  soil/saprolite interface.
- **Spin-up cost** dominates the compute budget; consider equilibrium
  water-table initialization or accelerated spin-up before brute-forcing
  90-yr cycles CONUS-wide.
- **Scale mismatch in validation**: GRACE (~300 km) vs point-scale CZO/flux
  towers — aggregation strategy needs defining up front.
- **Equifinality** remains the central calibration threat even with
  regionalization: fracture porosity, `f`, and regolith depth all modulate
  storage amplitude.
