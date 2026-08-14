# Phase 3 - Add Sequencer To Phase 1 Path

This folder connects the Phase 2 `coeff_reload_sequencer` to the Phase 1 complex channel emulator path.

## What Changed

- `src/complex_channel_emulator.vhd` is copied from the working Phase 1 design.
- `src/coeff_reload_sequencer.vhd` is copied from Phase 2.
- `tb/tb_complex_channel_emulator.vhd` now instantiates the sequencer.
- The testbench no longer manually drives FIR reload/config AXIS signals.
- The sequencer drives real/imaginary reload and config ports into the channel emulator.
- The testbench only drives active input samples, `sequencer_start`, and `sequencer_fu_tick`.

## Test Intent

The Phase 3 test proves that:

- active input traffic continues while the sequencer reloads coefficients
- three 32-tap coefficient sets are sent through the FIR reload path
- CONFIG is sent by the sequencer after each complete reload set
- the final impulse verification packet observes the final coefficient set
- `sequencer_timing_error` stays low

## Timing Constants

The testbench derives its timing from the proposal-style update rate:

- AXIS test clock: 100 MHz (`C_CLK_PERIOD = 10 ns`)
- coefficient update rate: 6 kHz
- FU period: 16667 clock cycles

Timeout values are derived from those constants. The active packet is kept open while the sequencer performs all three FU updates, then the testbench sends TLAST after `sequencer_block_done`.

## Vivado

Open:

```bash
phase_3_adding_sequencer_2_path_1/work_proj/work_proj.xpr
```

Then reload sources if Vivado asks, and run behavioral simulation.

The output CSV is written to:

```bash
phase_3_adding_sequencer_2_path_1/misc/phase_3_complex_channel_output.csv
```
