# Design

## The code

| value | −5 | −4 | −3 | −2 | −1 | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|---|---|---|---|---|
| codeword (hex) | E07 | D0B | C93 | C63 | A65 | 59A | 39C | 36C | 2F4 | 1F8 |

Bit indices run 1…12, with the LSB = 1. Every codeword has these properties:
1. **Weight 6:** exactly six 1s.
2. **Balanced indices:** the indices of the 1s and of the 0s each sum to 39.
3. **Value embedding:** over bits 1…6, (Σ indices of 1s) − (Σ indices of 0s) = 2v + 1.
4. **Mirror symmetry and complement:** bit i = bit 13 − i, and inverting a codeword gives the codeword of −(v + 1).

The minimum distance is 4. 20 codeword pairs are at distance 4, 20 at distance 8, and 5 at distance 12.

## Decoding with a Booth datapath (`rtl/ecc12_decoder.sv`)

Booth's algorithm scans the bit pairs `(c_i, c_(i−1))` of a word and adds or subtracts at the ends of runs of 1s. This
decoder differs in three ways:
* it adds or subtracts the **index i** instead of a multiplicand;
* it never shifts the accumulator;
* it runs three passes with different pair rules.

A 0 sits below bit 1 and above bit 12, so every run of 1s is closed.

| Pass | Start | Steps | Rule | Result |
|---|---|---|---|---|
| 1: weight | A = 0 | 13 | 01 → +i, 10 → −i | a run of 1s from s to e contributes (e + 1) − s, its length, so **A = W**, the number of 1s |
| 2: balance | A = 7 | 13 | 11 → +i, 00 → −i | **A = 2S + W − 84**: 0 for a codeword, ±(2j + 1) for a single error in bit j |
| 3: value | A = 3 | 7 | as pass 2, on the low 6 bits of the corrected word | **A = 2 S6 + W6 − 25 = 2v** |

**Where 2S + W − 84 comes from.** Here S is the index sum of the 1s. Use the identity
`c_i c_(i−1) − c_i' c_(i−1)' = c_i + c_(i−1) − 1`. Then
`A2 = 7 + Σ_{i=1..13} i (c_i + c_(i−1) − 1) = 7 + S + (S + W) − 91`.

A codeword has S = 39 and W = 6, so A2 = 0. A single flipped bit j changes S by ±j and W by ±1, so A2 = ±(2j + 1).
The decoder therefore:
* flips bit j = |A2| / 2;
* sets `err_weight = (A1 ≠ 6)` and `err_balance = (A2 ≠ 0)`;
* sets `value = A3 / 2`.

For a double or triple error, the "corrected" word is not a codeword, and the flags report the error.

**Implementation.** One always-block datapath holds a 13-bit accumulator, the word being scanned, the previous bit, an
index counter and a phase register. `done` is high 34 cycles after the start edge: 1 load + 13 + 13 + 7 steps.

**What the checks can and cannot see.** 58 twelve-bit words satisfy both checks (weight 6, balanced indices), and only
10 of them are codewords. A four-bit error that lands on one of the other 48 goes undetected, as does one that lands
on another codeword. That gives 150 + 40 = 190 undetectable four-bit patterns out of 4 950.

## Synthesis (`make synth`)

Yosys `synth -flatten; abc -g gates` gives 65 flip-flops, 348 two-input gates and 4 inverters. The netlist is
`build/synth/ecc12_decoder.v`.
