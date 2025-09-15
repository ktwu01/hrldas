#!/bin/bash
#SBATCH -J noahmp
#SBATCH -A UTAA0012
#SBATCH -N 1
#SBATCH -t 02:00:00
RUN_ID=$(date +%Y%m%d_%H%M%S)
SCR=/glade/derecho/scratch/$USER/noahmp/runs/$RUN_ID
WRK=/glade/work/$USER/noahmp
mkdir -p "$SCR" "$WRK/results"
cp -r "$WRK/inputs" "$SCR"
cd "$SCR"
# srun ./noahmp.exe ...
rsync -av output/ "$WRK/results/$RUN_ID/"
