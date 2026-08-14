# Phase 2 - PL Coefficient Reload Sequencer

This folder starts Phase 2 of the supervisor proposal: building the PL sequencer that automatically sends FIR Compiler `S_AXIS_RELOAD` and `S_AXIS_CONFIG` transactions.

## Current Scope

The first sequencer version is standalone. It does not include DMA or ping-pong buffering yet.

The RTL and standalone testbench avoid VHDL `variable` declarations to match the preferred project coding style. The sequencer FSM uses the project-style two-process structure: one clocked process for registered actions and one combinational process for `next_state` selection.

It proves:

- wait for `start`
- wait for one `fu_tick` per coefficient update
- send one complete 32-tap real/imag reload set
- assert reload `tlast` only on tap 31
- send CONFIG only after the full reload set is accepted
- repeat for three coefficient sets
- drive `fu_tick` at a fixed FU period instead of waiting for `done`
- tolerate reload/config `tready` backpressure
- raise `timing_error` if a new `fu_tick` arrives while reload/config is still busy
- intentionally sends an early `fu_tick` in a second scenario and checks that `timing_error` asserts

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
