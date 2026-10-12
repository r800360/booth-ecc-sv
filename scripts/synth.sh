#!/bin/bash
# synth.sh - Yosys synthesis to a generic gate library (synth -flatten; abc -g gates). Writes build/synth/stat.txt
# (full statistics), ecc12_decoder.v (netlist) and summary.txt.
cd "$(dirname "$0")/.."
B=build/synth; mkdir -p $B
yosys -q -p "read_verilog -sv rtl/ecc12_decoder.sv; synth -top ecc12_decoder -flatten; abc -g gates; opt_clean; \
  tee -q -o $B/stat.txt stat; write_verilog -noattr $B/ecc12_decoder.v" > $B/yosys.log 2>&1 < /dev/null \
  || { echo "yosys failed (see $B/yosys.log)"; exit 1; }
awk '/^ +\$_/ { c=$1; v=$2; if (c ~ /DFF/) ff+=v; else if (c=="$_NOT_") inv+=v; else g+=v }
  END { printf "ecc12_decoder: %d flip-flops, %d two-input gates, %d inverters (%d cells)\n", ff, g, inv, ff+g+inv }' \
  $B/stat.txt | tee $B/summary.txt
