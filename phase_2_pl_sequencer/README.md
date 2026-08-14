# Phase 2 - PL Coefficient Reload Sequencer

This folder starts Phase 2 of the supervisor proposal: building the PL sequencer that automatically sends FIR Compiler `S_AXIS_RELOAD` and `S_AXIS_CONFIG` transactions.

## Current Scope

The first sequencer version is standalone. It does not include DMA or ping-pong buffering yet.

The RTL and standalone testbench avoid VHDL `variable` declarations to match the preferred project coding style. The sequencer FSM uses the project-style two-process structure: one clocked process for registered actions and one combinational process for `next_state` selection.

It proves:

- run when `enable` is asserted
- generate the Fu update tick internally from `fu_period_cycles`
- check `next_set_available` before starting each coefficient reload
- send one complete 32-tap real/imag reload set
- assert reload `tlast` only on tap 31
- send CONFIG only after the full reload set is accepted
- repeat for three coefficient sets
- tolerate reload/config `tready` backpressure
- pulse `reload_set_done` after each reload+CONFIG commit
- assert `reload_block_done` after the configured block is consumed
- raise `missed_refill` if a Fu tick arrives when no coefficient set is available
- raise `reload_timing_error` if the programmed Fu period is too short for reload+CONFIG

The status names are intentionally explicit for later AXI-Lite mapping:

- `reload_active` means the sequencer is currently performing reload/config work.
- `reload_set_done` is a one-clock pulse after one Fu update is committed.
- `reload_block_done` is a sticky block-complete status until disabled or cleared.
- `missed_refill` is a sticky underrun/refill-miss status.

## Files

- `src/coeff_reload_sequencer.vhd`
  - RTL sequencer module.
- `tb/tb_coeff_reload_sequencer.vhd`
  - Standalone testbench with pseudo-random reload/config backpressure.
- `sim/run_ghdl.sh`
  - Local GHDL simulation script.

## Run

```bash
cd phase_2_pl_sequencer
bash sim/run_ghdl.sh
```

## Next Integration Step

After standalone sequencer simulation passes, connect the sequencer outputs to the Phase 1 `complex_channel_emulator` reload/config ports and replace the manual testbench reload driver.
