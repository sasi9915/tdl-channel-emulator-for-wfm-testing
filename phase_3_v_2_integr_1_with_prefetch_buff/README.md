# Phase 3 v2 - Prefetch Sequencer Integration

This folder connects the FIFO-prefetch version of `coeff_reload_sequencer` to the existing complex channel emulator path.

## What Changed

- `src/complex_channel_emulator.vhd` is copied from the working Phase 3 channel path.
- `src/coeff_reload_sequencer.vhd` is copied from the Phase 2 prefetch-FIFO sequencer.
- `src/channel_emulator_prefetch_top.vhd` instantiates both modules and owns the one-to-one reload/config wiring.
- `src/xpm_fifo_sync_wrap.vhd` is included for Vivado/XPM simulation.
- `tb/xpm_fifo_sync_wrap_sim.vhd` is included as the GHDL-only FIFO wrapper model.
- `tb/tb_complex_channel_emulator.vhd` instantiates only the top wrapper as the DUT.
- `tb/tb_complex_channel_emulator.vhd` now drives packed coefficient words through `coeff_set_tvalid/tready/tdata`.
- The testbench no longer manually drives FIR reload/config AXIS signals.
- The top wrapper connects the sequencer's real/imaginary reload and config ports into the channel emulator.
- The testbench does not drive an external `fu_tick`; the sequencer generates Fu internally from `fu_period_cycles`.

## Test Intent

The Phase 3 v2 test proves that:

- active input traffic continues while the prefetch sequencer reloads coefficients
- coefficient sets are streamed into the sequencer input FIFO through AXI-Stream style valid/ready handshaking
- the sequencer accepts multiple sets ahead when FIFO space is available
- reload starts only when a complete coefficient set is staged
- real and imaginary reload words match the expected coefficient stream
- reload `TLAST` is asserted only on the final word of each set
- CONFIG is sent by the sequencer after each complete reload set
- the final impulse verification packet observes the final coefficient set
- `missed_refill` and `reload_timing_error` stay low during the normal integration run

## Timing Constants

The testbench derives its timing from the proposal-style update rate:

- AXIS test clock: 100 MHz (`C_CLK_PERIOD = 10 ns`)
- coefficient update rate: 6 kHz
- Fu period register value: 16667 clock cycles

Timeout values are derived from those constants. The active packet is kept open while the sequencer performs all three Fu updates, then the testbench sends TLAST after `reload_block_done`.

## Vivado

Open:

```bash
phase_3_v_2_integr_1_with_prefetch_buff/work_proj/work_proj.xpr
```

Then reload sources if Vivado asks, make sure the new `src/xpm_fifo_sync_wrap.vhd` is included in the project, and run behavioral simulation.

The output CSV is written to:

```bash
phase_3_v_2_integr_1_with_prefetch_buff/misc/phase_3_prefetch_complex_channel_output.csv
```
