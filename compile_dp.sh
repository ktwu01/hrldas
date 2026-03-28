#!/bin/bash
cd /glade/u/home/wukoutian/hrldas-phs-dev/hrldas-dp-dev/hrldas
make clean || true
cp user_build_options.compiler user_build_options

# The specific compiler paths used on CASPER
export COMPILERF90=$(which mpif90)
export COMPILERF77=$(which mpif90)
export PNETCDF_DIR=/glade/u/apps/casper/24.12/spack/opt/spack/netcdf/4.9.2/oneapi/2024.2.1/hkzu

ed user_build_options <<EOF
,s/^COMPILERF90.*/COMPILERF90 = ${COMPILERF90//\//\\/}/g
,s/^COMPILERF77.*/COMPILERF77 = ${COMPILERF77//\//\\/}/g
,s|^NETCDFDIR.*|NETCDFDIR = $PNETCDF_DIR|g
w
EOF

echo "CPPFLAGS += -DDOUBLE_PREC" >> user_build_options
make -j 4
