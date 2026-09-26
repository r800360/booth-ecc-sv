# 12-bit constant-weight code decoder on a Booth-style datapath: lint, simulation, formal proof, synthesis.
# Tools: Verilator >= 5, Icarus Verilog >= 12, Yosys >= 0.30 (with yosys-abc).

RTL := rtl/ecc12_decoder.sv
TB  := tb/tb_ecc12.sv
RUN := bash scripts/run_sim.sh

.PHONY: all lint sim sim-icarus sim-verilator formal synth clean

all: lint sim

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
