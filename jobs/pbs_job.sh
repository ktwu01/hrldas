#!/bin/bash
#PBS -N noahmp_ml
#PBS -A UTAA0012
#PBS -q derecho
#PBS -l select=1:ncpus=16:ngpus=1:mem=64GB
#PBS -l walltime=02:00:00
set -euo pipefail
module load conda || true
source activate noahmp-ml || conda activate noahmp-ml || true

EXP=$(date +%Y%m%d_%H%M%S)
SCR=/glade/derecho/scratch/$USER/ml/experiments/$EXP
WRK=/glade/work/$USER/ml
mkdir -p "$SCR" "$WRK/checkpoints"
rsync -a "$WRK/datasets/" "$SCR/datasets/"
cd "$SCR"

# Example training
python -m train --data ./datasets --out ./outputs
rsync -av "$SCR/outputs/best.ckpt" "$WRK/checkpoints/$EXP.ckpt"
