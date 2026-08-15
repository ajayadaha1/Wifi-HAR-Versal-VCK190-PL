#!/usr/bin/env bash
# Build + run the composed FIR->stats AIE graph in the x86 functional simulator.
# Requires Vitis 2025.2 + g++. On Ubuntu 20 use run_host.sh (see fir_bandpass note).
set -euo pipefail
cd "$(dirname "$0")"

export CPATH="/usr/include/x86_64-linux-gnu${CPATH:+:$CPATH}"
PY=/tmp/venv/bin/python
command -v aiecompiler >/dev/null || { echo "aiecompiler not on PATH — source Vitis settings64.sh"; exit 1; }
command -v g++ >/dev/null || { echo "g++ missing — use run_host.sh for math validation"; exit 1; }

"$PY" gen_golden.py
rm -rf Work x86simulator_output data/output.txt
aiecompiler --target=x86sim --part=xcvc1902-vsva2197-2MP-e-S --include=./src ./src/graph.cpp --workdir=./Work
x86simulator --pkg-dir=./Work

OUT=data/output.txt
[ -f "$OUT" ] || OUT="$(find . -name output.txt | head -1)"
echo "output: $OUT"
"$PY" compare.py "$OUT" data/golden.txt 1e-4
