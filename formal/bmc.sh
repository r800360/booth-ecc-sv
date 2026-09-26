#!/bin/bash
# bmc.sh TAG TOP "FILES" "CHPARAM" DEPTH - bounded model check of every assertion with ABC's bmc3 for DEPTH cycles
# from the initial state. Prints "TAG: NO FAILURE in DEPTH cycles ..." or "TAG: FAILED ...".
TAG=$1; TOP=$2; FILES=$3; PARAMS=${4:-}; DEPTH=${5:-40}
cd "$(dirname "$0")/.."
OUTD=build/formal; mkdir -p $OUTD
CH=""; [ -n "$PARAMS" ] && CH="chparam $PARAMS $TOP;"
yosys -q -l $OUTD/$TAG.yosys.log -p "read_verilog -sv -formal -DFORMAL $FILES; $CH \
  prep -top $TOP; flatten; async2sync; chformal -lower; chformal -assume -early; chformal -cover -remove; \
  opt_clean; setundef -anyseq; opt -keepdc -fast; techmap; opt -fast; dffunmap; abc -g AND -fast; opt_clean; \
  write_aiger -I -B -zinit -map $OUTD/$TAG.aim $OUTD/$TAG.aig" > /dev/null 2>&1 || { echo "$TAG: ERROR (yosys)"; exit 2; }
nb=$(head -1 $OUTD/$TAG.aig | awk '{print $7}')
[ "${nb:-0}" -gt 0 ] || { echo "$TAG: ERROR (no assertions in the model)"; exit 2; }
start=$(date +%s)
timeout ${TO:-1800} yosys-abc -c "read_aiger $OUTD/$TAG.aig; fold; strash; bmc3 -F $DEPTH" > $OUTD/$TAG.bmc.log 2>&1
t=$(( $(date +%s) - start ))
if grep -qE "was asserted|Counter-example|asserted in frame" $OUTD/$TAG.bmc.log; then
  echo "$TAG: FAILED (counterexample, frame $(grep -oE 'frame [0-9]+' $OUTD/$TAG.bmc.log | head -1 | cut -d' ' -f2)) in ${t}s"
elif grep -qE "No output asserted in [0-9]+ frames|Reached limit on the number of timeframes" $OUTD/$TAG.bmc.log; then
  echo "$TAG: NO FAILURE in $DEPTH cycles ($nb assertions) in ${t}s"
else
  echo "$TAG: ERROR: $(tail -2 $OUTD/$TAG.bmc.log | tr '\n' ' ')"
fi
