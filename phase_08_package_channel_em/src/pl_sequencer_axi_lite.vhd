library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pl_sequencer_axi_lite is
	generic(
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line

		-- Parameters of Axi Slave Bus Interface S00_AXI
		C_S00_AXI_DATA_WIDTH : integer := 32;
		C_S00_AXI_ADDR_WIDTH : integer := 5
	);
	port(
		-- Users to add ports here
		seq_enable              : out std_logic;
		seq_fu_period_cycles    : out std_logic_vector(31 downto 0);
		cfg_bank_sets_per_bank  : out std_logic_vector(31 downto 0);
		irq_enable              : out std_logic_vector(5 downto 0);
		seq_clear_status        : out std_logic;
		seq_reload_active       : in  std_logic;
		seq_reload_block_done   : in  std_logic;
		seq_missed_refill       : in  std_logic;
		seq_reload_timing_error : in  std_logic;
		coeff_bank_active_set_available : in std_logic;
		coeff_bank_underrun             : in std_logic;
		coeff_bank_write_error          : in std_logic;
		fir_reload_error        : in  std_logic;
		coeff_bank_active_bank  : in  std_logic;
		coeff_bank0_ready       : in  std_logic;
		coeff_bank1_ready       : in  std_logic;
		seq_state_debug         : in  std_logic_vector(2 downto 0);
		-- User ports ends
		-- Do not modify the ports beyond this line

		-- Ports of Axi Slave Bus Interface S00_AXI
		s00_axi_aclk            : in  std_logic;
		s00_axi_aresetn         : in  std_logic;
		s00_axi_awaddr          : in  std_logic_vector(C_S00_AXI_ADDR_WIDTH - 1 downto 0);
		s00_axi_awprot          : in  std_logic_vector(2 downto 0);
		s00_axi_awvalid         : in  std_logic;
		s00_axi_awready         : out std_logic;
		s00_axi_wdata           : in  std_logic_vector(C_S00_AXI_DATA_WIDTH - 1 downto 0);
		s00_axi_wstrb           : in  std_logic_vector((C_S00_AXI_DATA_WIDTH / 8) - 1 downto 0);
		s00_axi_wvalid          : in  std_logic;
		s00_axi_wready          : out std_logic;
		s00_axi_bresp           : out std_logic_vector(1 downto 0);
		s00_axi_bvalid          : out std_logic;
		s00_axi_bready          : in  std_logic;
		s00_axi_araddr          : in  std_logic_vector(C_S00_AXI_ADDR_WIDTH - 1 downto 0);
		s00_axi_arprot          : in  std_logic_vector(2 downto 0);
		s00_axi_arvalid         : in  std_logic;
		s00_axi_arready         : out std_logic;
		s00_axi_rdata           : out std_logic_vector(C_S00_AXI_DATA_WIDTH - 1 downto 0);
		s00_axi_rresp           : out std_logic_vector(1 downto 0);
		s00_axi_rvalid          : out std_logic;
		s00_axi_rready          : in  std_logic
	);
end pl_sequencer_axi_lite;

architecture arch_imp of pl_sequencer_axi_lite is

	-- component declaration
	component pl_sequencer_axi_lite_slave_lite_v1_0_S00_AXI is
		generic(
			C_S_AXI_DATA_WIDTH : integer := 32;
			C_S_AXI_ADDR_WIDTH : integer := 5
		);
		port(
			seq_enable              : out std_logic;
			seq_fu_period_cycles    : out std_logic_vector(31 downto 0);
			cfg_bank_sets_per_bank  : out std_logic_vector(31 downto 0);
			irq_enable              : out std_logic_vector(5 downto 0);
			seq_clear_status        : out std_logic;
			seq_reload_active       : in  std_logic;
			seq_reload_block_done   : in  std_logic;
			seq_missed_refill       : in  std_logic;
			seq_reload_timing_error : in  std_logic;
			coeff_bank_active_set_available : in std_logic;
			coeff_bank_underrun             : in std_logic;
			coeff_bank_write_error          : in std_logic;
			fir_reload_error        : in  std_logic;
			coeff_bank_active_bank  : in  std_logic;
			coeff_bank0_ready       : in  std_logic;
			coeff_bank1_ready       : in  std_logic;
			seq_state_debug         : in  std_logic_vector(2 downto 0);
			S_AXI_ACLK              : in  std_logic;
			S_AXI_ARESETN           : in  std_logic;
			S_AXI_AWADDR            : in  std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
			S_AXI_AWPROT            : in  std_logic_vector(2 downto 0);
			S_AXI_AWVALID           : in  std_logic;
			S_AXI_AWREADY           : out std_logic;
			S_AXI_WDATA             : in  std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
			S_AXI_WSTRB             : in  std_logic_vector((C_S_AXI_DATA_WIDTH / 8) - 1 downto 0);
			S_AXI_WVALID            : in  std_logic;
			S_AXI_WREADY            : out std_logic;
			S_AXI_BRESP             : out std_logic_vector(1 downto 0);
			S_AXI_BVALID            : out std_logic;
			S_AXI_BREADY            : in  std_logic;
			S_AXI_ARADDR            : in  std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
			S_AXI_ARPROT            : in  std_logic_vector(2 downto 0);
			S_AXI_ARVALID           : in  std_logic;
			S_AXI_ARREADY           : out std_logic;
			S_AXI_RDATA             : out std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
			S_AXI_RRESP             : out std_logic_vector(1 downto 0);
			S_AXI_RVALID            : out std_logic;
			S_AXI_RREADY            : in  std_logic
		);
	end component pl_sequencer_axi_lite_slave_lite_v1_0_S00_AXI;

begin

	-- Instantiation of Axi Bus Interface S00_AXI
	pl_sequencer_axi_lite_slave_lite_v1_0_S00_AXI_inst : pl_sequencer_axi_lite_slave_lite_v1_0_S00_AXI
		generic map(
			C_S_AXI_DATA_WIDTH => C_S00_AXI_DATA_WIDTH,
			C_S_AXI_ADDR_WIDTH => C_S00_AXI_ADDR_WIDTH
		)
		port map(
			seq_enable              => seq_enable,
			seq_fu_period_cycles    => seq_fu_period_cycles,
			cfg_bank_sets_per_bank  => cfg_bank_sets_per_bank,
			irq_enable              => irq_enable,
			seq_clear_status        => seq_clear_status,
			seq_reload_active       => seq_reload_active,
			seq_reload_block_done   => seq_reload_block_done,
			seq_missed_refill       => seq_missed_refill,
			seq_reload_timing_error => seq_reload_timing_error,
			coeff_bank_active_set_available => coeff_bank_active_set_available,
			coeff_bank_underrun             => coeff_bank_underrun,
			coeff_bank_write_error          => coeff_bank_write_error,
			fir_reload_error        => fir_reload_error,
			coeff_bank_active_bank  => coeff_bank_active_bank,
			coeff_bank0_ready       => coeff_bank0_ready,
			coeff_bank1_ready       => coeff_bank1_ready,
			seq_state_debug         => seq_state_debug,
			S_AXI_ACLK              => s00_axi_aclk,
			S_AXI_ARESETN           => s00_axi_aresetn,
			S_AXI_AWADDR            => s00_axi_awaddr,
			S_AXI_AWPROT            => s00_axi_awprot,
			S_AXI_AWVALID           => s00_axi_awvalid,
			S_AXI_AWREADY           => s00_axi_awready,
			S_AXI_WDATA             => s00_axi_wdata,
			S_AXI_WSTRB             => s00_axi_wstrb,
			S_AXI_WVALID            => s00_axi_wvalid,
			S_AXI_WREADY            => s00_axi_wready,
			S_AXI_BRESP             => s00_axi_bresp,
			S_AXI_BVALID            => s00_axi_bvalid,
			S_AXI_BREADY            => s00_axi_bready,
			S_AXI_ARADDR            => s00_axi_araddr,
			S_AXI_ARPROT            => s00_axi_arprot,
			S_AXI_ARVALID           => s00_axi_arvalid,
			S_AXI_ARREADY           => s00_axi_arready,
			S_AXI_RDATA             => s00_axi_rdata,
			S_AXI_RRESP             => s00_axi_rresp,
			S_AXI_RVALID            => s00_axi_rvalid,
			S_AXI_RREADY            => s00_axi_rready
		);

	-- Add user logic here

	-- User logic ends

end arch_imp;
