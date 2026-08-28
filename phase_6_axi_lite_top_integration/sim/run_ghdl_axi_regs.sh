#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK_DIR="/tmp/phase6_ghdl_axi_regs"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

ghdl -a --std=08 --workdir="${WORK_DIR}" \
    "${PHASE_DIR}/src/pl_sequencer_axi_lite_slave_lite_v1_0_S00_AXI.vhd" \
    "${PHASE_DIR}/src/pl_sequencer_axi_lite.vhd" \
    "${PHASE_DIR}/tb/tb_pl_sequencer_axi_lite.vhd"

ghdl -e --std=08 --workdir="${WORK_DIR}" tb_pl_sequencer_axi_lite
ghdl -r --std=08 --workdir="${WORK_DIR}" tb_pl_sequencer_axi_lite
