# Verification

`make ci` runs every check here in about a minute. Logs and reports go to `build/`, and `build/SUMMARY.md` collects
them.

## Simulation (`tb/tb_ecc12.sv`, Icarus and Verilator)

The reference model is the closed form from DESIGN.md, written from index sums rather than from the bit-serial
algorithm:
* pass 1 counts the 1s;
* pass 2 computes `2S + W − 84`;
* pass 3 computes `2 S6 + W6 − 25`.

On top of it, the testbench checks the code's guarantees directly:

| Check | Result |
|---|---|
| The 10 codewords have properties 1–4 and pairwise distance ≥ 4 | pass |
| **All 4096 words**, decoded through the ports, match the reference; `done` exactly 34 edges after start | pass |
| Codewords: no flag, word unchanged, value −5…4 | 10 / 10 |
| Every single error: both flags raised, corrected to the original codeword, value recovered | 120 / 120 |
| Every double and triple error flagged | 660 / 660 and 2 200 / 2 200 |
| Four-bit errors: undetected exactly when the received word passes both checks | 190 of 4 950 (40 onto codewords, 150 onto the other balanced words) |
| Start pulses and a changing input while busy are ignored; reset mid-decode | pass |

## Formal (`make formal`)

`formal/ecc12_formal.sv` states the specification with the same closed forms: the exact latency, both flags, the
corrected word and the value.

* **Complete check of a transaction.** A bounded model check (ABC `bmc3`) covers one transaction, from reset through
  start and 34 cycles, for every one of the 4096 words. It finds no failure in 40 cycles.

  This covers every transaction in any start/reset pattern, for two reasons. An accepted start reloads every register
  the result depends on, and every output is rewritten before `done`.
* **Negative controls.** Two broken decoders must each fail: a wrong pass-3 seed, and correction disabled for bit 12.
* **Unbounded (optional).** `UNBOUNDED=1 make formal` runs the same property with PDR for every start/reset pattern.
  It did not finish within 500 s on a laptop, which is why the argument above uses the bounded check.

## Tools and how they are run

| Tool (version) | Used for | Command |
|---|---|---|
| Icarus Verilog 12.0 | simulation | `iverilog -g2012 -I tb -o build/ecc12.vvp tb/tb_ecc12.sv rtl/ecc12_decoder.sv`, then `vvp -n` |
| Verilator 5.032 | lint, simulation | `verilator --lint-only -Wall --top-module ecc12_decoder ...`; `verilator --binary --timing -O2 ...` |
| Yosys 0.52 + ABC | proof model, BMC, PDR, synthesis | `formal/bmc.sh`: Yosys writes an AIGER model, then `yosys-abc -c "read_aiger m.aig; fold; strash; bmc3 -F 40"`; `formal/pdr.sh` uses `pdr` instead |

The model is built with `read_verilog -sv -formal; prep; flatten; async2sync; chformal -lower; chformal -assume
-early; …; write_aiger -I -B -zinit`. `chformal -lower` is essential: Yosys 0.52 turns `assert` into `$check` cells,
which would otherwise leave the model with no properties. Both scripts refuse a model with none.

## CI

The *CI* (`.github/workflows/ci.yml`) and *Full verification* (`full.yml`) workflows both run all of the above:
* CI runs on every push.
* Full verification runs on demand or for a `v*` tag, and a tag also publishes a release.

Both use the pinned `ubuntu:26.04` image and `scripts/install-tools.sh`, the same script as the `Dockerfile`, and
upload `build/` as an artifact.
