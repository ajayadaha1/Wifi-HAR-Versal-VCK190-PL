#!/usr/bin/env bash
# Compile the composed AIE graph to hardware (libadf.a) via the chess flow.
# Ubuntu 20 (unsupported by 2025.2) lacks libdebuginfod.so.1 that binutils
# readelf needs at the ELF stage; supply the bundled toolchain copy.
set -uo pipefail   # not -e: keep going so a nonzero aiecompiler still reports
cd "$(dirname "$0")"
source /proj/gsd/vivado/2025.2/Vitis/settings64.sh >/dev/null 2>&1

mkdir -p /tmp/extralibs
# glibc-2.31 no-op stub: the toolchain readelf hard-links libdebuginfod.so.1,
# absent on Ubuntu 20 (bundled copy needs glibc 2.34+). Only remote debug fetch
# uses it; local elfgen does not.
gcc -shared -fPIC -Wl,-soname,libdebuginfod.so.1 "$(dirname "$0")/tools/debuginfod_stub.c" -o /tmp/extralibs/libdebuginfod.so.1
export LD_LIBRARY_PATH="/tmp/extralibs:${LD_LIBRARY_PATH:-}"
# Bundled aietools g++ (CDO generation) needs the multiarch asm/ headers.
export CPATH="/usr/include/x86_64-linux-gnu${CPATH:+:$CPATH}"

rm -rf Work_hw
# --Xpreproc injects the multiarch include into aiecompiler's own PS/CDO g++
# compile (it scrubs CPATH from its subprocess env, but honors this flag).
aiecompiler --target=hw --part=xcvc1902-vsva2197-2MP-e-S --include=./src --Xpreproc=-I/usr/include/x86_64-linux-gnu ./src/graph.cpp --workdir=./Work_hw
rc=$?
# aiecompiler emits libadf.a into the invocation dir (cwd), not the workdir.
echo "AIE_HW_DONE rc=$rc libadf_bytes=$(stat -c%s libadf.a 2>/dev/null || echo 0)"
