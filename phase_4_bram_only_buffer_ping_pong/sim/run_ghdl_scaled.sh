#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
work_dir="$script_dir/ghdl_work_bram_only_scaled"
sets_per_bank="${1:-600}"
stop_time="${2:-2ms}"
output_file="phase_4_ping_pong_buffer_output_${sets_per_bank}.csv"

mkdir -p "$work_dir"

ghdl -a --std=08 --workdir="$work_dir" "$project_dir/src/coeff_ping_pong_bram.vhd"
ghdl -a --std=08 --workdir="$work_dir" "$project_dir/src/coeff_ping_pong_buffer.vhd"
ghdl -a --std=08 --workdir="$work_dir" "$project_dir/tb/tb_coeff_ping_pong_buffer.vhd"
ghdl -e --std=08 --workdir="$work_dir" tb_coeff_ping_pong_buffer
ghdl -r --std=08 --workdir="$work_dir" tb_coeff_ping_pong_buffer \
    -gC_SETS_PER_BANK="$sets_per_bank" \
    -gC_OUTPUT_FILE="$output_file" \
    --stop-time="$stop_time"
