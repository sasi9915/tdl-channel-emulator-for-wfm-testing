TDL board PoC source bundle

Purpose:
- 32 FIR reload words per coefficient set.
- 5 sets per bank should therefore be 160 coefficient stream words.
- Sequencer reload_timing_error protection is disabled as a stop condition.
- Debug ports are kept for ILA/VIO visibility.

Important status bits:
- STATUS[3] = seq_reload_timing_error. This should stay 0 in this bundle.
- STATUS[7] = fir_reload_error from FIR Compiler reload TLAST events.
- STATUS[8] = refill_request. This sticky bit means the PL-timed set counter
  reached the configured refill threshold, so software should refill the
  inactive coefficient bank.

Notes:
- dbg_timing_fault_o is observe-only. It reports the old timing-fault candidate condition, but it does not latch status and does not stop the reload sequencer.
- G_RELOAD_WORD_COUNT defaults to 32 in channel_emulator_axi_top, channel_emulator_prefetch_top, and coeff_reload_sequencer.
- The complex_channel_emulator file uses FIR component names with the _0 suffix, matching the pasted board files.
- AXI offset 0x1C writes REFILL_THRESHOLD_SETS. A value of 0 disables the
  refill request. IRQ_ENABLE[6] enables a one-clock refill irq pulse.

Focused simulation:
- tb/tb_seq_fifo_usedw_reload_flow.vhd directly instantiates coeff_reload_sequencer.
- It loads 5 x 32 words into the sequencer FIFO.
- It holds modeled FIR reload/config ready low first, proving usedw only drops by one internally staged word.
- It then enables modeled IQ stream by releasing config ready and toggling reload ready.
- For each coefficient set, it forces reload ready low while reload valid is held and asserts usedw does not change.
- It asserts usedw drops 128, 96, 64, 32, 0 after each completed coefficient set.
- It sets REFILL_THRESHOLD_SETS to 2 and asserts refill_request when two sets
  remain in the 5-set bank.
- It asserts reload_timing_error remains 0.

Run with GHDL, if available:
  ./sim/run_seq_fifo_usedw_reload_flow_ghdl.sh

Run with Vivado/XSim, if available:
  ./sim/run_seq_fifo_usedw_reload_flow_xsim.sh

Full AXI/FIR-path simulation:
- tb/tb_full_axi_fir_reload_usedw.vhd instantiates channel_emulator_axi_top.
- This includes the real complex_channel_emulator and FIR Compiler components in Vivado simulation.
- It enables IQ before the coefficient reload flow and keeps IQ running while reload happens.
- It drives AXI-Lite, streams the initial 5-set Bank 0 block, enables TDL,
  checks irq is low before the configured refill threshold, then checks
  refill_request/irq assert when two sets remain.
- After the refill IRQ pulse, it models the PS response by streaming the next
  5-set block into inactive Bank 1, verifies STATUS[8] stays sticky until
  clear_status, and checks the ping-pong source changes to Bank 1 without bank
  underrun.
- It reports how many PL clocks the modeled PS/DMA refill takes after the IRQ
  and asserts the refill finishes inside the configured threshold window.
- It reports Fu ticks, reload accepts, config accepts, reload_set_done pulses, and dbg_seq_fifo_usedw_o values.
- It asserts refill_request/irq at the configured threshold and checks
  clear_status clears refill_request.
- It asserts reload_timing_error and fir_reload_error stay 0.
- AXI offset 0x08 writes BANK_SETS = 5. AXI offset 0x04 writes FU_PERIOD_CYCLES.
- AXI offset 0x1C writes REFILL_THRESHOLD_SETS = 2 in the testbench.
- The full TB defaults to 6 kHz at 300 MHz: FU_PERIOD_CYCLES = 50000.
- To run the same flow at 4 kHz, set C_FU_PERIOD_CYCLES to C_FU_PERIOD_4KHZ_CYCLES in tb_full_axi_fir_reload_usedw.vhd.

Run with Vivado/XSim:
  ./sim/run_full_axi_fir_reload_usedw_xsim.sh

FIR IP requirement for the full simulation:
- Put the FIR .xci directories under ip/, or set TDL_FIR_IP_DIR to the directory that contains them.
- The complex_channel_emulator in this bundle expects fir_compiler_invest_real_comp_0 and fir_compiler_invest_imag_comp_0.
