# Phase 2 - PL Coefficient Reload Sequencer

This folder starts Phase 2 of the supervisor proposal: building the PL sequencer that automatically sends FIR Compiler `S_AXIS_RELOAD` and `S_AXIS_CONFIG` transactions.

## Current Scope

The sequencer is standalone, but its coefficient input side now matches the planned block-ahead-buffer boundary. The large ping-pong buffer is still outside this module. This module only contains a small single-set XPM FIFO used to stage one complete reload set before each Fu update.

The RTL and standalone testbench avoid VHDL `variable` declarations to match the preferred project coding style. The sequencer FSM uses the project-style two-process structure: one clocked process for registered actions and one combinational process for `next_state` selection.

It proves:

- run when `enable` is asserted
- generate the Fu update tick internally from `fu_period_cycles`
- accept one full coefficient set into the internal XPM FIFO through `coeff_set_tvalid/tready/tdata`
- treat the staged FIFO set as ready only after `G_RELOAD_WORD_COUNT` words are accepted
- stream the staged set to the real and imaginary FIR reload ports at the Fu tick
- assert reload `tlast` only on the final reload word
- send CONFIG only after the full reload set is accepted
- repeat for three coefficient sets
- tolerate reload/config `tready` backpressure
- pulse `reload_set_done` after each reload+CONFIG commit
- assert `reload_block_done` after the configured block is consumed
- raise `missed_refill` if a Fu tick arrives when no complete FIFO-staged coefficient set is ready
- raise `reload_timing_error` if the programmed Fu period is too short for reload+CONFIG

The standalone testbench uses the proposal-level 300 MHz PL timing approximation:

- `C_CLK_PERIOD = 3333 ps`
- `C_RELOAD_WORD_COUNT = 133` for the current 128-tap FIR generated reload requirement
- `C_FIFO_DEPTH = 256` to hold one complete staged reload set
- `C_FU_PERIOD_CYCLES = 50000` for the 6 kHz Fu worst-case interval
- `C_REFILL_TEST_PERIOD_CYCLES = 50000` for missed-refill checking at the same Fu interval
- `C_FIFO_RESET_WAIT_TIME = 2000 ns` after reset release before FIFO traffic, matching the local XPM FIFO wrapper usage requirement

At 300 MHz, the 3 kHz Fu interval would use `fu_period_cycles = 100000`.

The status names are intentionally explicit for later AXI-Lite mapping:

- `reload_active` means the sequencer is currently performing reload/config work.
- `reload_set_done` is a one-clock pulse after one Fu update is committed.
- `reload_block_done` is a sticky block-complete status until disabled or cleared.
- `missed_refill` is a sticky underrun/refill-miss status. In this FIFO-based version, it means the FIR reload deadline arrived before one complete set was staged in the FIFO.

## Coefficient Set FIFO Boundary

The expected final connection is:

```text
block-ahead ping-pong buffer -> set prefetcher -> single XPM set FIFO -> PL sequencer -> FIR reload/config
```

The ping-pong buffer still decides which large block/bank is active. The sequencer does not need to know whether the data came from buffer 0 or buffer 1. It only sees whether a complete coefficient set has already been staged in the local FIFO by the prefetch side.

The packed FIFO input format is:

```text
coeff_set_tdata(31 downto 16) = real coefficient word
coeff_set_tdata(15 downto 0)  = imaginary coefficient word
```

For wider coefficients, the same packing rule is used with `G_COEFF_WIDTH`.

## Files

- `src/coeff_reload_sequencer.vhd`
  - RTL sequencer module with a single XPM set FIFO.
- `tb/tb_coeff_reload_sequencer.vhd`
  - Standalone testbench with FIFO-set loading and pseudo-random reload/config backpressure.
- `tb/xpm_fifo_sync_wrap_sim.vhd`
  - GHDL-only behavioral model of the project XPM FIFO wrapper.
- `sim/run_ghdl.sh`
  - Local GHDL simulation script.

## Run

```bash
cd phase_2_pl_sequencer
bash sim/run_ghdl.sh
```

## Next Integration Step

After standalone sequencer simulation passes, connect the sequencer outputs to the Phase 1 `complex_channel_emulator` reload/config ports and replace the manual testbench reload driver.
