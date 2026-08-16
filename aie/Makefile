# AIE feature graph -> VCK190 platform build (Vitis 2025.2).
# Compiles the ADF graph for the AI Engine array (chess), builds PL data-mover
# kernels (mm2s/s2mm), then links AIE + PL onto the xilinx_vck190_base platform
# with v++ and packages boot artifacts.
#
# Datapath: DDR -> mm2s -> AIE(FIR->stats) -> s2mm -> DDR (Arch A validation).

PART      := xcvc1902-vsva2197-2MP-e-S
PLATFORM  ?= /proj/rdi/xbuilds/2025.2_released/internal_platforms/xilinx_vck190_base_202520_1/xilinx_vck190_base_202520_1.xpfm
GRAPH     := ./src/graph.cpp
WORK      := Work_hw
LIBADF    := libadf.a
KERNELS   := mm2s s2mm
XOS       := $(addsuffix .xo,$(KERNELS))
XSA       := feature_graph.xsa
VXX_FLAGS := -t hw --platform $(PLATFORM)

.PHONY: aie kernels link package clean platforminfo

# Compile the ADF graph to AIE machine code -> libadf.a (emitted to cwd).
aie: $(LIBADF)
$(LIBADF): $(GRAPH) $(wildcard src/*.cpp) $(wildcard src/*.h)
	aiecompiler --target=hw --part=$(PART) --include=./src $(GRAPH) --workdir=$(WORK)

# Compile PL data movers to Xilinx objects (HLS via v++ -c).
kernels: $(XOS)
%.xo: pl/%.cpp
	v++ -c $(VXX_FLAGS) -k $* $< -o $@

platforminfo:
	@test -n "$(PLATFORM)" || { echo "set PLATFORM=<path to .xpfm>"; exit 1; }
	platforminfo $(PLATFORM) | sed -n '1,60p'

# Link the AIE graph + PL kernels onto the platform (connections in system.cfg).
link: $(XSA)
$(XSA): $(LIBADF) $(XOS) system.cfg
	@test -n "$(PLATFORM)" || { echo "set PLATFORM=<path to .xpfm>"; exit 1; }
	v++ -l $(VXX_FLAGS) --config system.cfg $(LIBADF) $(XOS) -o $(XSA)

package: $(XSA)
	v++ -p $(VXX_FLAGS) $(XSA) \
	  --package.out_dir ./package --package.boot_mode sd

clean:
	rm -rf $(WORK) $(XSA) $(XOS) package .Xil _x v++_* *.log *.jou *.xpe *.ltx
