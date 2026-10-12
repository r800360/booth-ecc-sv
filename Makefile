# 12-bit constant-weight code decoder on a Booth-style datapath: lint, simulation, formal checks, synthesis.
# Toolchain: Icarus Verilog, Verilator, Yosys + yosys-abc (exact versions in scripts/install-tools.sh).

RTL := rtl/ecc12_decoder.sv
TB  := tb/tb_ecc12.sv
RUN := bash scripts/run_sim.sh

.PHONY: all ci full summary lint sim sim-icarus sim-verilator formal synth clean

all: lint sim

# CI entry points (.github/workflows): everything here runs in a few minutes, so both suites are the same
ci: lint sim formal synth summary
full: ci

summary:
	@bash scripts/summary.sh > /dev/null && echo "wrote build/SUMMARY.md"

lint:
	verilator --lint-only -Wall --top-module ecc12_decoder $(RTL)

sim: sim-icarus sim-verilator

sim-icarus:
	$(RUN) icarus ecc12 $(TB) "" $(RTL)

sim-verilator:
	$(RUN) verilator ecc12 $(TB) "" $(RTL)

formal:
	bash formal/run_formal.sh

synth:
	bash scripts/synth.sh

clean:
	rm -rf build obj_dir
