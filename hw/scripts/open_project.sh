#!/usr/bin/env bash
# Open the copied VCK190 project in Vivado 2025.2.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
exec vivado "${HERE}/../ps_emio_basex_hw/ps_emio_basex.xpr" "$@"
