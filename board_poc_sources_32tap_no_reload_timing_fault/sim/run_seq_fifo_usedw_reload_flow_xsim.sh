#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
xvhdl -version >/dev/null
vivado -mode batch -source "${SCRIPT_DIR}/run_seq_fifo_usedw_reload_flow_xsim.tcl"
