# Cross-compile the XRT host app for the VCK190 A72 (aarch64) target.
#
# Requires the PetaLinux platform SYSROOT (built with the Linux image for the
# VCK190 base platform); it provides the aarch64 XRT headers + libs that are NOT
# in the desktop Vitis install. Point SYSROOT at <plnx>/images/linux/sdk/sysroots/
# cortexa72-cortexa53-xilinx-linux (or the base platform sw/ sysroot).
#
#   make SYSROOT=/path/to/aarch64-xilinx-linux-sysroot
#
# Then copy `host` + the packaged feature_graph.xclbin + data/{input,golden}.txt
# to the SD card and run on target: ./host feature_graph.xclbin input.txt golden.txt

SYSROOT ?=
CXX     := aarch64-linux-gnu-g++

ifeq ($(SYSROOT),)
$(warning SYSROOT is not set — set it to the PetaLinux aarch64 sysroot to build)
endif

CXXFLAGS := -std=c++17 -O2 --sysroot=$(SYSROOT) \
            -I$(SYSROOT)/usr/include -I$(SYSROOT)/usr/include/xrt
LDFLAGS  := --sysroot=$(SYSROOT) -L$(SYSROOT)/usr/lib \
            -lxrt_coreutil -pthread

host: host.cpp
	$(CXX) $(CXXFLAGS) host.cpp -o host $(LDFLAGS)

clean:
	rm -f host
