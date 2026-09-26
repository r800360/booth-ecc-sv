#!/bin/bash
# synth.sh - Yosys synthesis to a generic gate library (synth -flatten; abc -g gates): flip-flops, two-input gates,
# inverters. Full statistics in build/synth_stat.txt.
cd "$(dirname "$0")/.."
mkdir -p build
yosys -q -p "read_verilog -sv rtl/ecc12_decoder.sv; synth -top ecc12_decoder -flatten; abc -g gates; opt_clean; \
  tee -q -o build/synth_stat.txt stat" > build/synth.log 2>&1 || { echo "yosys failed (build/synth.log)"; exit 1; }
awk '/^ +\$_/ { c=$1; v=$2; if (c ~ /DFF/) ff+=v; else if (c=="$_NOT_") inv+=v; else g+=v }
  END { printf "ecc12_decoder: %d flip-flops, %d two-input gates, %d inverters (%d cells)\n", ff, g, inv, ff+g+inv }' \
  build/synth_stat.txt
