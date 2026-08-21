###############################################################################
# Phase 6 timing constraints
#
# Proposal target:
#   AXI-Lite controlled PL coefficient buffer and reload path clock = 300 MHz
#
# 300 MHz period = 3.333 ns.
###############################################################################

create_clock -name aclk_300mhz -period 3.333 [get_ports aclk]

# Reset is synchronously sampled inside the RTL. No reset false-path is applied
# here, so Vivado still checks reset fanout paths against the 300 MHz clock.
