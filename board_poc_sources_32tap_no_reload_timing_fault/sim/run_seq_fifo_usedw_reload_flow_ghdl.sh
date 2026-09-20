#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK_DIR="${ROOT_DIR}/sim/ghdl_work_seq_fifo"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

ghdl -a --std=08 --workdir="${WORK_DIR}" "${ROOT_DIR}/tb/xpm_fifo_sync_wrap_sim.vhd"
ghdl -a --std=08 --workdir="${WORK_DIR}" "${ROOT_DIR}/src/coeff_reload_sequencer.vhd"
ghdl -a --std=08 --workdir="${WORK_DIR}" "${ROOT_DIR}/tb/tb_seq_fifo_usedw_reload_flow.vhd"
ghdl -e --std=08 --workdir="${WORK_DIR}" tb_seq_fifo_usedw_reload_flow
ghdl -r --std=08 --workdir="${WORK_DIR}" tb_seq_fifo_usedw_reload_flow \
    --vcd="${ROOT_DIR}/sim/tb_seq_fifo_usedw_reload_flow.vcd"
