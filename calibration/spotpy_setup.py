"""SPOTPY spot_setup class for SCE-UA calibration of PHS at US-Syv.

5 parameters calibrated (IPHTYP=1):
  TLP    — PHS_LEAF_TLP   [mm]      leaf turgor loss potential
  KSAT   — PHS_XYLEM_KSAT [mm/s]   xylem saturated hydraulic conductivity
  P50    — PHS_XYLEM_P50  [mm]      stem water potential at 50% conductivity loss
  SPWAI  — wrfinput SPWAI [m2/m2]  sapwood area index
  SPWVI  — wrfinput SPWVI [m3/m2]  sapwood volume index

Objective: maximize KGE(LH) + KGE(PSN) at monthly scale (Sun et al. 2024).
SPOTPY minimizes, so objectivefunction returns -(KGE_LH + KGE_PSN).

Parameter ranges informed by:
  - Current IPHTYP=1 table defaults (optguess)
  - Li et al. (2021) Table 2 ensemble range
  - Physical plausibility for temperate deciduous forest
"""

import spotpy

from phs_wrapper import run_phs


class PHS_SpotSetup:
    """SPOTPY setup for 5-parameter PHS calibration at US-Syv."""

    def __init__(self):
        # Uniform priors over physically plausible ranges.
        # optguess = current IPHTYP=1 default (verified against wrfinput).
        self.params = [
            # Leaf turgor loss point [mm]: more negative → drought tolerant
            # IPHTYP=1 default: -1.07e5 mm ≈ −1.07 MPa × 10^4 mm/MPa
            spotpy.parameter.Uniform(
                "TLP", low=-3.0e5, high=-0.5e5, optguess=-1.07e5
            ),
            # Xylem saturated conductivity [mm/s]
            # IPHTYP=1 default: 2.07e-2 mm/s
            spotpy.parameter.Uniform(
                "KSAT", low=1.0e-3, high=2.0e-1, optguess=2.07e-2
            ),
            # Stem P50 [mm]: potential at 50% conductivity loss
            # IPHTYP=1 default: -3.22e5 mm
            spotpy.parameter.Uniform(
                "P50", low=-6.0e5, high=-1.0e5, optguess=-3.22e5
            ),
            # Sapwood area index [m2/m2]: site-measured 0.0015
            # Table default was 0.10 (physically implausible — see MEMORY)
            spotpy.parameter.Uniform(
                "SPWAI", low=5.0e-4, high=5.0e-3, optguess=1.5e-3
            ),
            # Sapwood volume index [m3/m2]: site-measured 0.0435
            # Physical constraint: SPWVI ≈ SPWAI × canopy height (29 m)
            spotpy.parameter.Uniform(
                "SPWVI", low=1.0e-2, high=1.5e-1, optguess=4.35e-2
            ),
        ]

    def parameters(self):
        return spotpy.parameter.generate(self.params)

    def simulation(self, vector):
        tlp, ksat, p50, spwai, spwvi = vector
        score = run_phs(
            tlp=tlp, ksat=ksat, p50=p50, spwai=spwai, spwvi=spwvi
        )
        return [score]

    def evaluation(self):
        # Perfect KGE_LH + KGE_PSN = 2.0
        return [2.0]

    def objectivefunction(self, simulation, evaluation):
        # SPOTPY minimizes; negate KGE sum so that better model = smaller value
        return -(simulation[0])
