#!/bin/bash
# run_formal.sh - formal checks of rtl/ecc12_decoder.sv against the closed-form specification (formal/ecc12_formal.sv):
#   1. a complete transaction for every one of the 4096 words: bounded model check over its 36 cycles (SINGLE = 1);
#      complete for every transaction because start reloads all the state a result depends on
#   2. negative controls: two broken decoders must fail
#   3. (UNBOUNDED=1) the same property for every start / reset pattern with PDR; this can take hours
# Summary: build/formal/summary.txt
cd "$(dirname "$0")/.."
OUTD=build/formal; mkdir -p $OUTD/mutants
OUT=$OUTD/summary.txt; : > $OUT
bad=0
expect() {  # expected-word result-line
  local got=${2#*: }; got=${got%% *}
  if [ "$got" = "$1" ]; then echo "  ok        $2" | tee -a $OUT
  else echo "  UNEXPECTED (expected $1) $2" | tee -a $OUT; bad=1; fi
}
bmc() { bash formal/bmc.sh "$1" ecc12_formal "$2 formal/ecc12_formal.sv" "-set SINGLE 1" 40; }
mutant() {  # name sed-expression
  sed "$2" rtl/ecc12_decoder.sv > $OUTD/mutants/$1.sv
  if cmp -s rtl/ecc12_decoder.sv $OUTD/mutants/$1.sv; then echo "  mutation $1 did not apply" | tee -a $OUT; bad=1; return 1; fi
}
echo "== every word: decoder = closed-form specification, exact latency (BMC over the whole transaction)" | tee -a $OUT
expect NO "$(bmc ecc12 rtl/ecc12_decoder.sv)"
echo "== negative controls: each must FAIL" | tee -a $OUT
mutant phase3_seed "s/a <= 13'd3;/a <= 13'd2;/" && expect FAILED "$(bmc mut_phase3_seed $OUTD/mutants/phase3_seed.sv)"
mutant no_correction_msb "s/if (j >= 4'd1 \&\& j <= 4'd12)/if (j >= 4'd1 \&\& j <= 4'd11)/" \
  && expect FAILED "$(bmc mut_no_correction_msb $OUTD/mutants/no_correction_msb.sv)"
if [ -n "${UNBOUNDED:-}" ]; then
  echo "== every start / reset pattern (PDR)" | tee -a $OUT
  expect PROVED "$(TO=${TO:-14400} bash formal/pdr.sh ecc12_pdr ecc12_formal "rtl/ecc12_decoder.sv formal/ecc12_formal.sv")"
fi
if [ $bad -eq 0 ]; then echo "ALL OUTCOMES AS EXPECTED" | tee -a $OUT; else echo "SOME OUTCOMES UNEXPECTED" | tee -a $OUT; fi
exit $bad
