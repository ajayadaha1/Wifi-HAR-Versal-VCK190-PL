#!/bin/sh
# D1 on-target: route csi_mux to mm2s (S01), then run the proven XRT host
# (mm2s -> csi_mux -> AIE -> s2mm) and compare to golden.
cd "$(dirname "$0")"
echo "=== D1: set csi_mux route (S01=mm2s) ==="
python3 mux_set.py 1 2>&1 | sed 's/^/  /'
echo "=== D1: run XRT host (DDR->mm2s->csi_mux->AIE->s2mm->DDR) ==="
./host inline_cogen_d1.xclbin input.txt golden.txt
