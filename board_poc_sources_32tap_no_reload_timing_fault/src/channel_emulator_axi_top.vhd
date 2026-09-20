library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity channel_emulator_axi_top is
    generic(
        G_RELOAD_WORD_COUNT  : integer := 32;
        G_BANK_SET_COUNT     : integer := 3;
        G_MAX_SETS_PER_BANK  : integer := 600;
        G_COEFF_WIDTH        : integer := 16;
        G_CONFIG_WIDTH       : integer := 8;
        G_FIFO_DEPTH         : integer := 512;
        C_S00_AXI_DATA_WIDTH : integer := 32;
        C_S00_AXI_ADDR_WIDTH : integer := 32
    );
    port(
        aclk                   : in  std_logic;
        aresetn                : in  std_logic;
        s00_axi_awaddr         : in  std_logic_vector(C_S00_AXI_ADDR_WIDTH - 1 downto 0);
        s00_axi_awprot         : in  std_logic_vector(2 downto 0);
        s00_axi_awvalid        : in  std_logic;
        s00_axi_awready        : out std_logic;
        s00_axi_wdata          : in  std_logic_vector(C_S00_AXI_DATA_WIDTH - 1 downto 0);
        s00_axi_wstrb          : in  std_logic_vector((C_S00_AXI_DATA_WIDTH / 8) - 1 downto 0);
        s00_axi_wvalid         : in  std_logic;
        s00_axi_wready         : out std_logic;
        s00_axi_bresp          : out std_logic_vector(1 downto 0);
        s00_axi_bvalid         : out std_logic;
        s00_axi_bready         : in  std_logic;
        s00_axi_araddr         : in  std_logic_vector(C_S00_AXI_ADDR_WIDTH - 1 downto 0);
        s00_axi_arprot         : in  std_logic_vector(2 downto 0);
        s00_axi_arvalid        : in  std_logic;
        s00_axi_arready        : out std_logic;
        s00_axi_rdata          : out std_logic_vector(C_S00_AXI_DATA_WIDTH - 1 downto 0);
        s00_axi_rresp          : out std_logic_vector(1 downto 0);
        s00_axi_rvalid         : out std_logic;
        s00_axi_rready         : in  std_logic;
        s_axis_coeff_tvalid    : in  std_logic;
        s_axis_coeff_tready    : out std_logic;
        s_axis_coeff_tdata     : in  std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
        s_axis_coeff_tkeep     : in  std_logic_vector(((2 * G_COEFF_WIDTH) / 8) - 1 downto 0);
        s_axis_coeff_tlast     : in  std_logic;
        s_axis_tvalid          : in  std_logic;
        s_axis_tready          : out std_logic;
        s_axis_tdata           : in  std_logic_vector(31 downto 0);
        s_axis_tkeep           : in  std_logic_vector(3 downto 0);
        s_axis_tlast           : in  std_logic;
        m_axis_tvalid          : out std_logic;
        m_axis_tready          : in  std_logic;
        m_axis_tdata           : out std_logic_vector(127 downto 0);
        m_axis_tkeep           : out std_logic_vector(15 downto 0);
        m_axis_tlast           : out std_logic;
        reload_busy_o          : out std_logic;
        reload_done_o          : out std_logic;
        dbg_reload_valid_o     : out std_logic;
        dbg_reload_combined_ready_o : out std_logic;
        dbg_reload_real_ready_o : out std_logic;
        dbg_reload_imag_ready_o : out std_logic;
        dbg_reload_last_o      : out std_logic;
        dbg_reload_real_data_o : out std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
        dbg_reload_imag_data_o : out std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
        dbg_fir_real_reload_tlast_missing_o    : out std_logic;
        dbg_fir_real_reload_tlast_unexpected_o : out std_logic;
        dbg_fir_imag_reload_tlast_missing_o    : out std_logic;
        dbg_fir_imag_reload_tlast_unexpected_o : out std_logic;
        dbg_config_valid_o     : out std_logic;
        dbg_config_ready_o     : out std_logic;
        dbg_fu_tick_o          : out std_logic;
        dbg_state_o            : out std_logic_vector(2 downto 0);
        dbg_seq_enable_o       : out std_logic;
        dbg_next_state_o       : out std_logic_vector(2 downto 0);
        dbg_reload_accept_o    : out std_logic;
        dbg_config_accept_o    : out std_logic;
        dbg_timing_fault_o     : out std_logic;
        dbg_reload_word_index_o : out std_logic_vector(15 downto 0);
        dbg_reload_set_index_o  : out std_logic_vector(15 downto 0);
        dbg_reload_timing_error_o : out std_logic;
        dbg_fir_reload_error_o : out std_logic;
        dbg_active_set_available_o : out std_logic;
        dbg_active_bank_o      : out std_logic;
        dbg_bank0_ready_o      : out std_logic;
        dbg_bank1_ready_o      : out std_logic;
        dbg_seq_fifo_usedw_o   : out std_logic_vector(15 downto 0);
        dbg_seq_fifo_has_set_o : out std_logic;
        dbg_seq_input_ready_o  : out std_logic;
        dbg_refill_request_pulse_o : out std_logic;
        irq                    : out std_logic
    );
end entity;

architecture rtl of channel_emulator_axi_top is
    signal seq_enable             : std_logic;
    signal seq_clear_status       : std_logic;
    signal seq_fu_period_cycles   : std_logic_vector(31 downto 0);
    signal cfg_bank_sets_per_bank : std_logic_vector(31 downto 0);
    signal cfg_refill_threshold_sets : std_logic_vector(31 downto 0);
    signal irq_enable             : std_logic_vector(6 downto 0);
    signal irq_pending            : std_logic_vector(6 downto 0);

    signal w_reload_active                   : std_logic;
    signal w_reload_set_done                 : std_logic;
    signal w_reload_block_done               : std_logic;
    signal w_missed_refill                   : std_logic;
    signal w_refill_request                  : std_logic;
    signal w_refill_request_pulse            : std_logic;
    signal w_reload_timing_error             : std_logic;
    signal w_coeff_bank_active_set_available : std_logic;
    signal w_coeff_bank_underrun             : std_logic;
    signal w_coeff_bank_write_error          : std_logic;
    signal w_fir_reload_error                : std_logic;
    signal w_coeff_bank_active_bank          : std_logic;
    signal w_coeff_bank0_ready               : std_logic;
    signal w_coeff_bank1_ready               : std_logic;
    signal w_state_debug                     : std_logic_vector(2 downto 0);
    signal w_reload_tvalid                   : std_logic;
    signal w_reload_combined_tready          : std_logic;
    signal w_reload_real_tready              : std_logic;
    signal w_reload_imag_tready              : std_logic;
    signal w_reload_tlast                    : std_logic;
    signal w_reload_real_data                : std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
    signal w_reload_imag_data                : std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
    signal w_real_reload_tlast_missing       : std_logic;
    signal w_real_reload_tlast_unexpected    : std_logic;
    signal w_imag_reload_tlast_missing       : std_logic;
    signal w_imag_reload_tlast_unexpected    : std_logic;
    signal w_config_tvalid                   : std_logic;
    signal w_config_tready                   : std_logic;
    signal w_fu_tick                         : std_logic;
    signal w_seq_enable_debug                : std_logic;
    signal w_next_state                      : std_logic_vector(2 downto 0);
    signal w_reload_accept                   : std_logic;
    signal w_config_accept                   : std_logic;
    signal w_timing_fault                    : std_logic;
    signal w_reload_word_index               : std_logic_vector(15 downto 0);
    signal w_reload_set_index                : std_logic_vector(15 downto 0);
    signal w_axis_coeff_tready               : std_logic;
    signal w_seq_fifo_usedw                  : std_logic_vector(15 downto 0);
    signal w_seq_fifo_has_set                : std_logic;
    signal w_seq_input_ready                 : std_logic;
begin

    axi_regs_inst : entity work.pl_sequencer_axi_lite
        generic map(
            C_S00_AXI_DATA_WIDTH => C_S00_AXI_DATA_WIDTH,
            C_S00_AXI_ADDR_WIDTH => C_S00_AXI_ADDR_WIDTH
        )
        port map(
            seq_enable                      => seq_enable,
            seq_fu_period_cycles            => seq_fu_period_cycles,
            cfg_bank_sets_per_bank          => cfg_bank_sets_per_bank,
            cfg_refill_threshold_sets       => cfg_refill_threshold_sets,
            irq_enable                      => irq_enable,
            irq_pending                     => irq_pending,
            seq_clear_status                => seq_clear_status,
            seq_reload_active               => w_reload_active,
            seq_reload_block_done           => w_reload_block_done,
            seq_missed_refill               => w_missed_refill,
            refill_request                  => w_refill_request,
            refill_request_pulse            => w_refill_request_pulse,
            seq_reload_timing_error         => w_reload_timing_error,
            coeff_bank_active_set_available => w_coeff_bank_active_set_available,
            coeff_bank_underrun             => w_coeff_bank_underrun,
            coeff_bank_write_error          => w_coeff_bank_write_error,
            fir_reload_error                => w_fir_reload_error,
            coeff_bank_active_bank          => w_coeff_bank_active_bank,
            coeff_bank0_ready               => w_coeff_bank0_ready,
            coeff_bank1_ready               => w_coeff_bank1_ready,
            seq_state_debug                 => w_state_debug,
            s00_axi_aclk                    => aclk,
            s00_axi_aresetn                 => aresetn,
            s00_axi_awaddr                  => s00_axi_awaddr,
            s00_axi_awprot                  => s00_axi_awprot,
            s00_axi_awvalid                 => s00_axi_awvalid,
            s00_axi_awready                 => s00_axi_awready,
            s00_axi_wdata                   => s00_axi_wdata,
            s00_axi_wstrb                   => s00_axi_wstrb,
            s00_axi_wvalid                  => s00_axi_wvalid,
            s00_axi_wready                  => s00_axi_wready,
            s00_axi_bresp                   => s00_axi_bresp,
            s00_axi_bvalid                  => s00_axi_bvalid,
            s00_axi_bready                  => s00_axi_bready,
            s00_axi_araddr                  => s00_axi_araddr,
            s00_axi_arprot                  => s00_axi_arprot,
            s00_axi_arvalid                 => s00_axi_arvalid,
            s00_axi_arready                 => s00_axi_arready,
            s00_axi_rdata                   => s00_axi_rdata,
            s00_axi_rresp                   => s00_axi_rresp,
            s00_axi_rvalid                  => s00_axi_rvalid,
            s00_axi_rready                  => s00_axi_rready
        );

    datapath_inst : entity work.channel_emulator_prefetch_top
        generic map(
            G_RELOAD_WORD_COUNT => G_RELOAD_WORD_COUNT,
            G_BANK_SET_COUNT    => G_BANK_SET_COUNT,
            G_MAX_SETS_PER_BANK => G_MAX_SETS_PER_BANK,
            G_COEFF_WIDTH       => G_COEFF_WIDTH,
            G_CONFIG_WIDTH      => G_CONFIG_WIDTH,
            G_FIFO_DEPTH        => G_FIFO_DEPTH
        )
        port map(
            aclk                            => aclk,
            aresetn                         => aresetn,
            enable                          => seq_enable,
            clear_status                    => seq_clear_status,
            fu_period_cycles                => unsigned(seq_fu_period_cycles),
            cfg_bank_sets_per_bank          => unsigned(cfg_bank_sets_per_bank),
            cfg_refill_threshold_sets       => unsigned(cfg_refill_threshold_sets),
            coeff_set_tvalid                => s_axis_coeff_tvalid,
            coeff_set_tready                => w_axis_coeff_tready,
            coeff_set_tdata                 => s_axis_coeff_tdata,
            coeff_set_tkeep                 => s_axis_coeff_tkeep,
            coeff_set_tlast                 => s_axis_coeff_tlast,
            s_axis_tvalid                   => s_axis_tvalid,
            s_axis_tready                   => s_axis_tready,
            s_axis_tdata                    => s_axis_tdata,
            s_axis_tkeep                    => s_axis_tkeep,
            s_axis_tlast                    => s_axis_tlast,
            m_axis_tvalid                   => m_axis_tvalid,
            m_axis_tready                   => m_axis_tready,
            m_axis_tdata                    => m_axis_tdata,
            m_axis_tkeep                    => m_axis_tkeep,
            m_axis_tlast                    => m_axis_tlast,
            reload_active                   => w_reload_active,
            reload_set_done                 => w_reload_set_done,
            reload_block_done               => w_reload_block_done,
            missed_refill                   => w_missed_refill,
            refill_request                  => w_refill_request,
            refill_request_pulse            => w_refill_request_pulse,
            reload_timing_error             => w_reload_timing_error,
            coeff_bank_active_set_available => w_coeff_bank_active_set_available,
            coeff_bank_underrun             => w_coeff_bank_underrun,
            coeff_bank_write_error          => w_coeff_bank_write_error,
            fir_reload_error                => w_fir_reload_error,
            coeff_bank_active_bank          => w_coeff_bank_active_bank,
            coeff_bank0_ready               => w_coeff_bank0_ready,
            coeff_bank1_ready               => w_coeff_bank1_ready,
            dbg_reload_valid_o              => w_reload_tvalid,
            dbg_reload_combined_ready_o     => w_reload_combined_tready,
            dbg_reload_real_ready_o         => w_reload_real_tready,
            dbg_reload_imag_ready_o         => w_reload_imag_tready,
            dbg_reload_last_o               => w_reload_tlast,
            dbg_reload_real_data_o          => w_reload_real_data,
            dbg_reload_imag_data_o          => w_reload_imag_data,
            dbg_fir_real_reload_tlast_missing_o    => w_real_reload_tlast_missing,
            dbg_fir_real_reload_tlast_unexpected_o => w_real_reload_tlast_unexpected,
            dbg_fir_imag_reload_tlast_missing_o    => w_imag_reload_tlast_missing,
            dbg_fir_imag_reload_tlast_unexpected_o => w_imag_reload_tlast_unexpected,
            dbg_config_valid_o              => w_config_tvalid,
            dbg_config_ready_o              => w_config_tready,
            dbg_fu_tick_o                   => w_fu_tick,
            dbg_seq_enable_o                => w_seq_enable_debug,
            dbg_next_state_o                => w_next_state,
            dbg_reload_accept_o             => w_reload_accept,
            dbg_config_accept_o             => w_config_accept,
            dbg_timing_fault_o              => w_timing_fault,
            dbg_reload_word_index_o         => w_reload_word_index,
            dbg_reload_set_index_o          => w_reload_set_index,
            dbg_seq_fifo_usedw_o            => w_seq_fifo_usedw,
            dbg_seq_fifo_has_set_o          => w_seq_fifo_has_set,
            dbg_seq_input_ready_o           => w_seq_input_ready,
            state_debug                     => w_state_debug
        );

    s_axis_coeff_tready <= w_axis_coeff_tready;

    reload_busy_o       <= w_reload_active;
    reload_done_o       <= w_reload_set_done;
    dbg_reload_valid_o  <= w_reload_tvalid;
    dbg_reload_combined_ready_o <= w_reload_combined_tready;
    dbg_reload_real_ready_o <= w_reload_real_tready;
    dbg_reload_imag_ready_o <= w_reload_imag_tready;
    dbg_reload_last_o   <= w_reload_tlast;
    dbg_reload_real_data_o <= w_reload_real_data;
    dbg_reload_imag_data_o <= w_reload_imag_data;
    dbg_fir_real_reload_tlast_missing_o <= w_real_reload_tlast_missing;
    dbg_fir_real_reload_tlast_unexpected_o <= w_real_reload_tlast_unexpected;
    dbg_fir_imag_reload_tlast_missing_o <= w_imag_reload_tlast_missing;
    dbg_fir_imag_reload_tlast_unexpected_o <= w_imag_reload_tlast_unexpected;
    dbg_config_valid_o  <= w_config_tvalid;
    dbg_config_ready_o  <= w_config_tready;
    dbg_fu_tick_o       <= w_fu_tick;
    dbg_state_o         <= w_state_debug;
    dbg_seq_enable_o    <= w_seq_enable_debug;
    dbg_next_state_o    <= w_next_state;
    dbg_reload_accept_o <= w_reload_accept;
    dbg_config_accept_o <= w_config_accept;
    dbg_timing_fault_o  <= w_timing_fault;
    dbg_reload_word_index_o <= w_reload_word_index;
    dbg_reload_set_index_o  <= w_reload_set_index;
    dbg_reload_timing_error_o <= w_reload_timing_error;
    dbg_fir_reload_error_o <= w_fir_reload_error;
    dbg_active_set_available_o <= w_coeff_bank_active_set_available;
    dbg_active_bank_o   <= w_coeff_bank_active_bank;
    dbg_bank0_ready_o   <= w_coeff_bank0_ready;
    dbg_bank1_ready_o   <= w_coeff_bank1_ready;
    dbg_seq_fifo_usedw_o <= w_seq_fifo_usedw;
    dbg_seq_fifo_has_set_o <= w_seq_fifo_has_set;
    dbg_seq_input_ready_o <= w_seq_input_ready;
    dbg_refill_request_pulse_o <= w_refill_request_pulse;

    irq <= '1' when (irq_pending and irq_enable) /= "0000000" else '0';

end architecture;

 
