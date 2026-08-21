# Phase 6 - AXI-Lite Controlled Top Integration

This phase starts from the Phase 5 ping-pong coefficient buffer integration and adds a clean PS-facing AXI4-Lite control layer.

## Goal

- Keep the Phase 5 datapath baseline intact.
- Add repo-owned AXI-Lite registers for runtime configuration and status.
- Expose one hardware top that can be dropped into the Vivado block design.
- Test the register block separately before testing full datapath integration.

## Starting Baseline

The `src/` folder currently contains a direct copy of the Phase 5 integration RTL:

- `channel_emulator_prefetch_top.vhd`
- `coeff_ping_pong_bram.vhd`
- `coeff_ping_pong_buffer.vhd`
- `coeff_reload_sequencer.vhd`
- `complex_channel_emulator.vhd`
- `xpm_fifo_sync_wrap.vhd`

The copied Phase 5 top still has direct control ports:

- `enable`
- `clear_status`
- `fu_period_cycles`

Phase 6 should replace those external control ports at the system boundary with AXI-Lite registers.

## Planned Register Map

| Offset | Register | Purpose |
| --- | --- | --- |
| `0x00` | `CONTROL` | bit 0 `enable`, bit 1 `clear_status` pulse |
| `0x04` | `FU_PERIOD_CYCLES` | runtime reload period in PL clock cycles |
| `0x08` | `BANK_SETS_PER_BANK` | active coefficient sets per ping-pong bank |
| `0x0C` | `RESERVED` | kept for future runtime run/IRQ control |
| `0x10` | `STATUS` | reload and coefficient-bank status bits |
| `0x14` | `DEBUG` | sequencer/reader debug state |
| `0x18` | `CAPABILITY` | optional read-only version/capability word |

## Parameter Ownership

- `G_RELOAD_WORD_COUNT`: compile-time reload words per coefficient set.
- `G_MAX_SETS_PER_BANK`: compile-time physical BRAM capacity per bank.
- `G_COEFF_WIDTH`: compile-time coefficient lane width.
- `fu_period_cycles`: runtime AXI-Lite register.
- `bank_sets_per_bank`: runtime AXI-Lite register, range `1` to `G_MAX_SETS_PER_BANK`.
- `enable`: runtime AXI-Lite control bit.
- `clear_status`: one-clock AXI-Lite generated pulse.

## Test Plan

1. Test the AXI-Lite register block alone.
2. Test the AXI top with the Phase 5 datapath connected.
3. Verify bank fill, reload sequencing, status readback, clear-status pulse, underrun, and write-error behavior.
4. Run Vivado synthesis/implementation at the `300 MHz` target from `constraints/phase_6_timing.xdc`.

## Local Simulation

Run the register-only AXI-Lite test:

```bash
bash phase_6_axi_lite_top_integration/sim/run_ghdl_axi_regs.sh
```

Run the full AXI-controlled top integration test in Vivado/xsim:

```bash
bash phase_6_axi_lite_top_integration/sim/run_vivado_axi_top.sh
```

If the Vivado GUI is already open and does not show recent RTL/testbench changes, run:

```bash
bash phase_6_axi_lite_top_integration/sim/sync_vivado_imports.sh
```

Then reload/reopen the project or refresh sources in Vivado.

The full top testbench uses the real FIR Compiler IP instances from `phase_6_axi_lite_top_integration/work_proj`.
