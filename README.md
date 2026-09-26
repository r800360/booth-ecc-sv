# Constant-weight code decoder on a Booth-multiplier datapath, in SystemVerilog

A sequential error-correcting decoder for a 12-bit constant-weight code. It reuses the structure of a Booth
multiplier: bit-pair recoding and an accumulator that adds or subtracts. The single-error correction and
triple-error detection are verified exhaustively, and the decoder is proven equal to a closed-form specification.

## The code

Ten 12-bit codewords encode the values −5…4:

| value | −5 | −4 | −3 | −2 | −1 | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|---|---|---|---|---|
| codeword | E07 | D0B | C93 | C63 | A65 | 59A | 39C | 36C | 2F4 | 1F8 |

Every codeword satisfies (bit indices 1…12, LSB = 1):
1. **Weight 6:** exactly six 1s.
2. **Balanced indices:** the indices of the 1s and of the 0s both sum to 39.
3. **Value embedding:** over bits 1…6, (Σ indices of 1s) − (Σ indices of 0s) = 2v + 1.
4. **Mirror symmetry:** bit i = bit 13 − i. **Complement:** inverting a codeword gives the codeword of −(v + 1).

The minimum distance is 4, so every single error can be corrected and every double or triple error detected.

## Decoding with a Booth datapath

Booth's algorithm scans the multiplier's bit pairs `(c_i, c_(i−1))` and adds or subtracts at the ends of runs of 1s.
This decoder does the same, with three changes:
* it adds or subtracts the **index i** instead of a multiplicand;
* it never shifts the accumulator;
* it runs three passes with different pair rules. A 0 is placed below bit 1 and above bit 12, so every run of 1s is
  closed.

| Phase | Start | Steps | Rule | Result |
|---|---|---|---|---|
| 1: weight | A = 0 | 13 | 01 → +i, 10 → −i | each run of 1s from s to e contributes (e + 1) − s = its length, so **A = number of 1s** (6 for a codeword) |
| 2: balance | A = 7 | 13 | 11 → +i, 00 → −i | **A = 2S + W − 84** (S = index sum of the 1s, W = weight): 0 for a codeword, **±(2j + 1)** for a single error in bit j |
| 3: value | A = 3 | 7 | as phase 2, on the low 6 bits of the corrected word | **A = 2 S6 + W6 − 25 = 2v**, so value = A / 2 |

The phase-2 formula follows from `c_i c_(i−1) − c_i' c_(i−1)' = c_i + c_(i−1) − 1`, which gives
`A2 = 7 + Σ_{i=1..13} i (c_i + c_(i−1) − 1) = 7 + S + (S + W) − 91`. A single flipped bit j changes S by ±j and W by
±1, so A2 = ±(2j + 1). **Correction** flips bit j = |A2| / 2. `err_weight = (A1 ≠ 6)` and `err_balance = (A2 ≠ 0)`.

The decoder is a single always-block datapath: a 13-bit accumulator, the scanned word, the previous bit, the index
counter and a phase register. `done` is high 34 cycles after the start edge (1 load + 13 + 13 + 7 steps).
Synthesized with Yosys (`make synth`) it is 65 flip-flops, 348 two-input gates and 4 inverters.

## Verification

### Simulation: `tb/tb_ecc12.sv` (Icarus and Verilator)

The reference model is the closed form above: phase 1 counts the 1s, phase 2 is `2S + W − 84`, and phase 3 is
`2 S6 + W6 − 25`. It is written from sums, not from the bit-serial algorithm. On top of it the testbench checks the
code's promises directly:

| Check | Result |
|---|---|
| The 10 codewords have properties 1–4 and pairwise distance ≥ 4 | pass |
| **All 4096 input words** decoded through the ports match the reference, with `done` exactly 34 edges after start | pass |
| Codewords: no error flag, word unchanged, value −5…4 | 10 / 10 |
| **Every single error**: both flags raised, corrected to the original codeword, value recovered | 120 / 120 |
| **Every double and triple error** flagged | 660 / 660 and 2 200 / 2 200 |
| Four-bit errors: undetected exactly when the received word satisfies both invariants | 190 of 4 950 |
| Start pulses and a changing input while busy are ignored; reset mid-decode | pass |

The 190 undetected four-bit patterns break down into two groups. **40** turn one codeword into another: 20 codeword
pairs are at distance 4, and each pair counts in both directions. The other **150** produce one of the 48 twelve-bit
words that have weight 6 and balanced indices without being codewords. The decoder tests only the two invariants,
so it accepts those words unchanged. There are 58 such balanced words and only 10 codewords.

### Formal: `make formal` (Yosys + ABC)

`formal/ecc12_formal.sv` states the specification with the same closed forms: exact latency, both flags, the
corrected word and the value.

* **Complete check of a transaction.** A bounded model check covers one transaction (reset, start, 34 cycles) for
  every one of the 4096 words: **no failure in 40 cycles**. An accepted start reloads every register the result
  depends on, and every output is rewritten before `done`, so this covers every transaction in any start/reset
  pattern.
* **Negative controls.** Two broken decoders, a wrong phase-3 seed and correction disabled for bit 12, both produce
  counterexamples.
* **Unbounded (optional).** `UNBOUNDED=1 make formal` runs the same property unbounded with PDR. It did not finish
  within 500 s here.

## Repository layout

```
rtl/ecc12_decoder.sv       the decoder
tb/tb_ecc12.sv             self-checking testbench (+ tb_common.svh)
formal/ecc12_formal.sv     specification; bmc.sh, pdr.sh, run_formal.sh
scripts/                   run_sim.sh, synth.sh
```

## Running

```bash
make                 # lint, Icarus and Verilator simulation
make formal          # bounded proof of every word, negative controls
make synth           # gate count
```

Requirements: Verilator 5, Icarus Verilog 12, Yosys ≥ 0.30 with yosys-abc. Tested with Verilator 5.032, Icarus 12.0
and Yosys 0.52.

## Background

This design started as a university digital-design lab assignment, built as a schematic around a provided Booth
multiplier controller. This repository is a from-scratch re-implementation in SystemVerilog with its own synchronous
controller. It adds exhaustive and formal verification of the code's correction and detection guarantees.
