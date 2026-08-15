#!/usr/bin/env bash
# Validate the composed FIR->stats chain math with the system gcc (no AIE tools).
set -euo pipefail
cd "$(dirname "$0")"
PY=/tmp/venv/bin/python
"$PY" gen_golden.py
gcc -O2 -I src test/test_host.c -o test_host
./test_host
"$PY" compare.py data/host_output.txt data/golden.txt 1e-4
