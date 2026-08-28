#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_SRCS="${PHASE_DIR}/work_proj/work_proj.srcs"

mkdir -p \
    "${PROJECT_SRCS}/sources_1/imports/src" \
    "${PROJECT_SRCS}/sim_1/imports/tb" \
    "${PROJECT_SRCS}/constrs_1/imports/constraints"

cp "${PHASE_DIR}/src/"*.vhd "${PROJECT_SRCS}/sources_1/imports/src/"
cp "${PHASE_DIR}/tb/tb_channel_emulator_axi_top.vhd" "${PROJECT_SRCS}/sim_1/imports/tb/"
cp "${PHASE_DIR}/constraints/phase_6_timing.xdc" "${PROJECT_SRCS}/constrs_1/imports/constraints/"

echo "Synced Phase 6 RTL, testbench, and constraints into Vivado imported sources."
