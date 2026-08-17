# Phase 4 - Block-Ahead Ping-Pong Coefficient Buffer

This folder starts Phase 4 of the supervisor proposal: a PL-side ping-pong buffer that separates bursty coefficient writes from regular `Fu`-paced sequencer reads.

## Current Scope

The first proof is standalone. It does not connect to DMA or the FIR path yet.

The buffer uses two protected banks:

- one active bank read by the sequencer side
- one inactive bank filled by the future DMA/write side

Default RTL sizing now follows the proposal's high-bandwidth block-ahead target:

- tap count: 128
- maximum coefficient sets per bank: 600
- coefficient word: 32 bits total, with 16 bits real and 16 bits imaginary
- PL clock target: 300 MHz

The physical RAM is sized for 600 sets per bank. The active block length is selected with `cfg_sets_per_bank`, so the same RTL can be tested at 300 or 600 sets without changing the RAM structure.

The standalone testbench still uses 8 sets by default so simulation remains short and easy to inspect.

## Files

- `src/coeff_ping_pong_buffer.vhd`
  - RTL ping-pong coefficient buffer controller.
- `src/coeff_ping_pong_bram.vhd`
  - Simple-dual-port BRAM template used by the controller.
- `src/coeff_ping_pong_uram.vhd`
  - XPM simple-dual-port UltraRAM wrapper used when `G_RAM_STYLE => "ultra"`.
- `tb/tb_coeff_ping_pong_buffer.vhd`
  - Standalone testbench for bank fill, swap, write backpressure and underrun.
- `tb/tb_coeff_ping_pong_bram.vhd`
  - Standalone testbench for the inferred BRAM memory wrapper.
- `tb/tb_coeff_ping_pong_uram.vhd`
  - Standalone testbench for the XPM UltraRAM memory wrapper.
- `sim/run_ghdl.sh`
  - Local GHDL simulation script.
- `sim/run_ghdl_scaled.sh`
  - Local GHDL simulation script for larger proposal-style bank depths.
- `constraints/phase_4_timing.xdc`
  - Vivado timing constraint for the 300 MHz `aclk` target.

## Proven By Testbench

- initial bank fill becomes the active readable bank
- early `wr_last` rejects the partial write block
- missing final `wr_last` rejects the malformed write block
- clearing a write-format error restarts the write position
- inactive bank can be filled while active bank remains readable
- ready inactive bank blocks writes without falsely treating held `wr_valid` as an error
- active bank swaps atomically after all sets are consumed
- underrun asserts when active bank is exhausted and the next bank is not ready
- exhausted active-bank coefficients are not exposed on the read output after underrun
- after underrun, the buffer recovers and swaps when the next bank becomes ready
- `wr_ready` is blocked during `clear_errors` so no coefficient beat is falsely accepted
- `wr_ready` is registered and cleared during reset so a write handshake cannot be accepted while reset is active
- `consume_set_ready` is blocked during `clear_errors` so no consume handshake is falsely accepted
- `active_set_available` and `consume_set_ready` are registered status outputs
- `rd_en`/`rd_valid` prove the registered memory read path used by the sequencer side

## Interface Notes

- The public interface only exposes integration signals needed by the writer and reload sequencer.
- `cfg_sets_per_bank` selects the active bank length, for example 300 or 600 sets.
- The RTL latches `cfg_sets_per_bank` on reset, and may update it again only while both banks are empty.
- The write side uses `wr_valid`, `wr_ready`, packed `wr_data` and `wr_last`.
- The read side uses `rd_en`, `rd_tap_index`, `rd_data` and `rd_valid`.
- Packing is `data(G_COEFF_WIDTH - 1 downto 0) = real` and `data((2 * G_COEFF_WIDTH) - 1 downto G_COEFF_WIDTH) = imaginary`.
- `wr_ready` is driven from an internal register that is cleared in the reset and `clear_errors` branches.
- `wr_last` marks the end of one full buffer bank, not the FIR reload packet `tlast`.
- `rd_data` is registered from the selected synchronous memory, so it is valid only when `rd_valid = '1'`.
- The inferred BRAM wrapper currently has one-clock read latency; the XPM UltraRAM wrapper registers the read request before the XPM and uses three XPM read-latency stages.
- The sequencer side should use `rd_data` only when `rd_valid = '1'`.
- `active_set_available` means the active bank currently contains an unread coefficient set.
- A single registered availability flag drives both `active_set_available` and `consume_set_ready`.
- The availability flag is cleared inside the reset and `clear_errors` branches of the clocked process.
- The buffer internally selects the current coefficient set, so there is no public `rd_set_index` port.
- Read outputs are only driven with coefficient data while `active_set_available = '1'`. After all sets are consumed, the outputs return zero until a swap/recovery happens.
- `consume_set_ready` follows `active_set_available` when `clear_errors = '0'`.
- One coefficient set is consumed only when `consume_set_valid = '1'` and `consume_set_ready = '1'`.
- `consume_set_valid = '1'` while `consume_set_ready = '0'` is treated as a waiting valid-ready transaction, not an underrun by itself.
- `consume_set_valid` may be held while waiting, but the planned reload sequencer should still generate a clean one-clock accepted consume after one complete coefficient set has been transferred.
- Initial empty state is not treated as an underrun. `underrun` means the active bank was exhausted and no replacement bank is ready yet.
- `underrun` and `write_error` are the only public error/status outputs kept in the reduced interface.

## Memory Sizing

The RTL has a `G_RAM_STYLE` generic. When `G_RAM_STYLE => "ultra"`, the controller instantiates the XPM UltraRAM wrapper. For other values such as `"block"`, the controller instantiates the inferred simple-dual-port RAM wrapper.

The memory is one physical RAM with two logical address regions:

- bank 0: set/tap words from the current or next coefficient block
- bank 1: set/tap words from the alternate coefficient block

For packed 32-bit complex coefficients:

- `32 taps x 300 sets x 4 bytes = 38.4 KB` per bank
- `32 taps x 600 sets x 4 bytes = 76.8 KB` per bank
- ping-pong total for 32 taps and 600 sets is about `153.6 KB`
- `128 taps x 300 sets x 4 bytes = 153.6 KB` per bank
- `128 taps x 600 sets x 4 bytes = 307.2 KB` per bank
- ping-pong total for 128 taps and 600 sets is about `614.4 KB`

The preferred first implementation target is BRAM for smaller profiles. URAM is now available for larger 128-tap / 600-set builds by setting `G_RAM_STYLE => "ultra"`. This path uses `xpm_memory_sdpram` with `MEMORY_PRIMITIVE => "ultra"` so synthesis has a direct UltraRAM implementation target instead of relying only on a `ram_style` inference hint.

For the 128-tap / 600-set URAM build, routed timing at 300 MHz showed setup violations inside the XPM UltraRAM paths. The first issue was the cascade output path from `URAM288` read/cascade outputs into the XPM read data pipe registers. After that was reduced, the remaining small violation was the active set counter feeding the XPM URAM address input in the same cycle. The URAM wrapper therefore registers the read request/address before XPM, and the top-level buffer exposes `G_URAM_READ_LATENCY`, defaulted to 3 cycles, plus `G_URAM_CASCADE_HEIGHT`, defaulted to 4. Downstream logic must continue to use `rd_valid` to know when `rd_data` is usable.

## Run

```bash
cd phase_4_block_ahead_buffer
bash sim/run_ghdl.sh
```

The default simulation uses 8 coefficient sets per bank so it finishes quickly. To check the same logic at a larger block-ahead depth, pass the set count to the scaled script:

```bash
bash sim/run_ghdl_scaled.sh 300 2ms
bash sim/run_ghdl_scaled.sh 600 3ms
```

The testbench writes a CSV log here:

```text
phase_4_ping_pong_buffer_output.csv
```

The scaled script writes `phase_4_ping_pong_buffer_output_<set_count>.csv`.

The log records simulation time, event name, bank/set/tap indices, real/imaginary coefficient values and key handshakes/status signals. Use `read_check` rows to follow what the sequencer side reads from the active bank, `write_accept` rows to follow buffer fills, and `consume_set_accept` rows to see when one 32-tap coefficient set is consumed.

The testbench clock period is `3.333 ns`, matching the 300 MHz PL timing target used by the XDC constraint.

## Vivado Source Tracking

The copied Vivado project references the editable source files directly:

- `../src/coeff_ping_pong_bram.vhd`
- `../src/coeff_ping_pong_uram.vhd`
- `../src/coeff_ping_pong_buffer.vhd`
- `../tb/tb_coeff_ping_pong_buffer.vhd`
- `../constraints/phase_4_timing.xdc`

In this working project Vivado may still show imported copies under `work_proj/work_proj.srcs/.../imports/...`. If Vivado does not show a VS Code change, sync or re-add the file as a reference instead of importing a copied source.

## Next Integration Step

Connect packed `rd_data` to the next reload wrapper/sequencer stage, split it into real and imaginary FIR reload words there, and use the sequencer accepted-set pulse as `consume_set_valid`.
