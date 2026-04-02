#!/bin/bash
#PBS -N hrldas_run
#PBS -l select=1:ncpus=1:ompthreads=1
#PBS -l walltime=04:00:00
#PBS -q casper
#PBS -A UMIC0071
#PBS -o run_DP_fix.out
#PBS -e run_DP_fix.err

cd /glade/u/home/wukoutian/regression_test/phs_v5x_7yr
cp /glade/u/home/wukoutian/hrldas-phs-dev/hrldas/run/hrldas.exe .
cp /glade/u/home/wukoutian/hrldas-phs-dev/noahmp/parameters/NoahmpTable.TBL .
rm -f *.LDASOUT_DOMAIN1
./hrldas.exe > run_DP_fix.log 2>&1
