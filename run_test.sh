#!/bin/bash
cd /glade/u/home/wukoutian/regression_test/phs_v5x_7yr
cp /glade/u/home/wukoutian/hrldas-phs-dev/hrldas/run/hrldas.exe .
./hrldas.exe > run_DP_fix.log 2>&1
