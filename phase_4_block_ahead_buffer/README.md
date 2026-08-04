# Phase 4 - Block-Ahead Ping-Pong Coefficient Buffer

This folder starts Phase 4 of the supervisor proposal: a PL-side ping-pong buffer that separates bursty coefficient writes from regular `Fu`-paced sequencer reads.

## Current Scope

The first proof is standalone. It does not connect to DMA or the FIR path yet.

The buffer uses two protected banks:

- one active bank read by the sequencer side
- one inactive bank filled by the future DMA/write side

For the first proof:

- tap count: 32
- coefficient sets per bank: 8
- coefficient word: 32 bits total, with 16 bits real and 16 bits imaginary

## Files

- `src/coeff_ping_pong_buffer.vhd`
  - RTL ping-pong coefficient buffer.
- `tb/tb_coeff_ping_pong_buffer.vhd`
  - Standalone testbench for bank fill, swap, write backpressure and underrun.
- `sim/run_ghdl.sh`
  - Local GHDL simulation script.

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

## Interface Notes

- The public interface only exposes integration signals needed by the writer and reload sequencer.
- The write side uses `wr_valid`, `wr_ready`, packed `wr_data` and `wr_last`.
- The read side outputs packed `rd_data`.
- Packing is `data(G_COEFF_WIDTH - 1 downto 0) = real` and `data((2 * G_COEFF_WIDTH) - 1 downto G_COEFF_WIDTH) = imaginary`.
- `wr_ready` is driven from an internal register that is cleared in the reset and `clear_errors` branches.
- `wr_last` marks the end of one full buffer bank, not the FIR reload packet `tlast`.
- The read side uses `rd_tap_index`, `rd_data`, `active_set_available`, `consume_set_valid` and `consume_set_ready`.
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

## Run

```bash
cd phase_4_block_ahead_buffer
bash sim/run_ghdl.sh
```

The testbench writes a CSV log here:

```text
phase_4_ping_pong_buffer_output.csv
```

The log records simulation time, event name, bank/set/tap indices, real/imaginary coefficient values and key handshakes/status signals. Use `read_check` rows to follow what the sequencer side reads from the active bank, `write_accept` rows to follow buffer fills, and `consume_set_accept` rows to see when one 32-tap coefficient set is consumed.

## Vivado Source Tracking

The copied Vivado project references the editable source files directly:

- `../src/coeff_ping_pong_buffer.vhd`
- `../tb/tb_coeff_ping_pong_buffer.vhd`

So changes made in VS Code should be visible in Vivado after reloading the file or relaunching simulation.

## Next Integration Step

Connect packed `rd_data` to the next reload wrapper/sequencer stage, split it into real and imaginary FIR reload words there, and use the sequencer accepted-set pulse as `consume_set_valid`.
