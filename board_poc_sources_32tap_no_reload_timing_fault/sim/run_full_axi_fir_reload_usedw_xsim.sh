#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
vivado -mode batch -source "${SCRIPT_DIR}/run_full_axi_fir_reload_usedw_xsim.tcl"
