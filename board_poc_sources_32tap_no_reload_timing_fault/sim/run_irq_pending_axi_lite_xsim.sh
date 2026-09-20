#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
xvhdl -version >/dev/null
vivado -mode batch -source "${SCRIPT_DIR}/run_irq_pending_axi_lite_xsim.tcl"
