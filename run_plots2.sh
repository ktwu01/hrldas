#!/bin/bash
cd /glade/u/home/wukoutian/LSMs-dev-Review/tests_scripts
source /glade/u/apps/opt/miniconda3/bin/activate
export PYTHONPATH="/glade/u/home/wukoutian/LSMs-dev-Review/tests_scripts"

# Run the 2x2 residuals plot
python3 plot_2x2_residuals.py
python3 plot_delta_comparison.py
python3 plot_monthly_comparison.py

