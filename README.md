# tdl-channel-emulator-for-wfm-testing

## Implementation Notes

### FIR Reload Word Count

The number of FIR reload transfers must be taken from the Vivado-generated
`*_reload_order.txt` file for the exact FIR Compiler configuration. It should
not be assumed to always equal the logical FIR tap count.

For the 32-tap configuration used earlier, the generated reload sequence matched
the 32 logical coefficients. For the 128-tap, sample-period-7 configuration,
Vivado generated 133 reload words. The extra reload positions are part of the FIR
Compiler's internal reload ordering, so the reload stream must send all generated
reload words and assert `TLAST` only on the final generated word.

This means the PS/DMA coefficient block format and the PL sequencer must use a
configuration-specific `reload_word_count` and reload order. In the current
two-FIR architecture, the real and imaginary reload streams must use the same
generated order and the same `TLAST` position. If the PS sends only the logical
tap count when Vivado expects more reload words, the FIR can raise
`event_s_reload_tlast_missing` and the new coefficient set will not be committed
as intended.
