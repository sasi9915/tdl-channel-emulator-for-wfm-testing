#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
work_dir="$script_dir/ghdl_work_bram_only"

mkdir -p "$work_dir"

ghdl -a --std=08 --workdir="$work_dir" "$project_dir/src/coeff_ping_pong_bram.vhd"
ghdl -a --std=08 --workdir="$work_dir" "$project_dir/src/coeff_ping_pong_buffer.vhd"
ghdl -a --std=08 --workdir="$work_dir" "$project_dir/tb/tb_coeff_ping_pong_buffer.vhd"
ghdl -e --std=08 --workdir="$work_dir" tb_coeff_ping_pong_buffer
ghdl -r --std=08 --workdir="$work_dir" tb_coeff_ping_pong_buffer --stop-time=100us
