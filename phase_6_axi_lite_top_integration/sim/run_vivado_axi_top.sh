#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/sync_vivado_imports.sh"
vivado -mode batch -source "${SCRIPT_DIR}/run_vivado_axi_top.tcl"
