library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity channel_emulator_axi_top is
    generic(
        G_RELOAD_WORD_COUNT  : integer := 133;
        G_SET_COUNT          : integer := 6;
        G_BANK_SET_COUNT     : integer := 3;
        G_MAX_SETS_PER_BANK  : integer := 600;
        G_COEFF_WIDTH        : integer := 16;
        G_CONFIG_WIDTH       : integer := 8;
        G_FIFO_DEPTH         : integer := 512;
        C_S00_AXI_DATA_WIDTH : integer := 32;
        C_S00_AXI_ADDR_WIDTH : integer := 5
    );
    port(
        aclk    : in std_logic;
        aresetn : in std_logic;

        s00_axi_awaddr  : in  std_logic_vector(C_S00_AXI_ADDR_WIDTH - 1 downto 0);
        s00_axi_awprot  : in  std_logic_vector(2 downto 0);
        s00_axi_awvalid : in  std_logic;
        s00_axi_awready : out std_logic;
        s00_axi_wdata   : in  std_logic_vector(C_S00_AXI_DATA_WIDTH - 1 downto 0);
        s00_axi_wstrb   : in  std_logic_vector((C_S00_AXI_DATA_WIDTH / 8) - 1 downto 0);
        s00_axi_wvalid  : in  std_logic;
        s00_axi_wready  : out std_logic;
        s00_axi_bresp   : out std_logic_vector(1 downto 0);
        s00_axi_bvalid  : out std_logic;
        s00_axi_bready  : in  std_logic;
        s00_axi_araddr  : in  std_logic_vector(C_S00_AXI_ADDR_WIDTH - 1 downto 0);
        s00_axi_arprot  : in  std_logic_vector(2 downto 0);
        s00_axi_arvalid : in  std_logic;
        s00_axi_arready : out std_logic;
        s00_axi_rdata   : out std_logic_vector(C_S00_AXI_DATA_WIDTH - 1 downto 0);
        s00_axi_rresp   : out std_logic_vector(1 downto 0);
        s00_axi_rvalid  : out std_logic;
        s00_axi_rready  : in  std_logic;

        coeff_set_tvalid : in  std_logic;
        coeff_set_tready : out std_logic;
        coeff_set_tdata  : in  std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
        coeff_set_tlast  : in  std_logic;

        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;
        s_axis_tdata  : in  std_logic_vector(31 downto 0);
        s_axis_tlast  : in  std_logic;

        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic;
        m_axis_tdata  : out std_logic_vector(79 downto 0);
        m_axis_tlast  : out std_logic;

        reload_active       : out std_logic;
        reload_set_done     : out std_logic;
        reload_block_done   : out std_logic;
        missed_refill       : out std_logic;
        reload_timing_error : out std_logic;
        coeff_bank_active_set_available : out std_logic;
        coeff_bank_underrun             : out std_logic;
        coeff_bank_write_error          : out std_logic;
        state_debug         : out std_logic_vector(2 downto 0);

        dbg_real_reload_tvalid : out std_logic;
        dbg_real_reload_tready : out std_logic;
        dbg_real_reload_tdata  : out std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
        dbg_real_reload_tlast  : out std_logic;
        dbg_imag_reload_tvalid : out std_logic;
        dbg_imag_reload_tready : out std_logic;
        dbg_imag_reload_tdata  : out std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
        dbg_imag_reload_tlast  : out std_logic;
        dbg_real_config_tvalid : out std_logic;
        dbg_real_config_tready : out std_logic;
        dbg_real_config_tdata  : out std_logic_vector(G_CONFIG_WIDTH - 1 downto 0);
        dbg_imag_config_tvalid : out std_logic;
        dbg_imag_config_tready : out std_logic;
        dbg_imag_config_tdata  : out std_logic_vector(G_CONFIG_WIDTH - 1 downto 0);
        dbg_real_m_tvalid      : out std_logic;
        dbg_real_m_tready      : out std_logic;
        dbg_real_m_tlast       : out std_logic;
        dbg_imag_m_tvalid      : out std_logic;
        dbg_imag_m_tready      : out std_logic;
        dbg_imag_m_tlast       : out std_logic
    );
end entity;

architecture rtl of channel_emulator_axi_top is
    signal seq_enable           : std_logic;
    signal seq_clear_status     : std_logic;
    signal seq_fu_period_cycles : std_logic_vector(31 downto 0);
    signal cfg_bank_sets_per_bank : std_logic_vector(31 downto 0);

    signal w_reload_active       : std_logic;
    signal w_reload_set_done     : std_logic;
    signal w_reload_block_done   : std_logic;
    signal w_missed_refill       : std_logic;
    signal w_reload_timing_error : std_logic;
    signal w_coeff_bank_active_set_available : std_logic;
    signal w_coeff_bank_underrun             : std_logic;
    signal w_coeff_bank_write_error          : std_logic;
    signal w_state_debug         : std_logic_vector(2 downto 0);
begin

    axi_regs_inst : entity work.pl_sequencer_axi_lite
        generic map(
            C_S00_AXI_DATA_WIDTH => C_S00_AXI_DATA_WIDTH,
            C_S00_AXI_ADDR_WIDTH => C_S00_AXI_ADDR_WIDTH
        )
        port map(
            seq_enable              => seq_enable,
            seq_fu_period_cycles    => seq_fu_period_cycles,
            cfg_bank_sets_per_bank  => cfg_bank_sets_per_bank,
            seq_clear_status        => seq_clear_status,
            seq_reload_active       => w_reload_active,
            seq_reload_block_done   => w_reload_block_done,
            seq_missed_refill       => w_missed_refill,
            seq_reload_timing_error => w_reload_timing_error,
            coeff_bank_active_set_available => w_coeff_bank_active_set_available,
            coeff_bank_underrun             => w_coeff_bank_underrun,
            coeff_bank_write_error          => w_coeff_bank_write_error,
            seq_state_debug         => w_state_debug,
            s00_axi_aclk            => aclk,
            s00_axi_aresetn         => aresetn,
            s00_axi_awaddr          => s00_axi_awaddr,
            s00_axi_awprot          => s00_axi_awprot,
            s00_axi_awvalid         => s00_axi_awvalid,
            s00_axi_awready         => s00_axi_awready,
            s00_axi_wdata           => s00_axi_wdata,
            s00_axi_wstrb           => s00_axi_wstrb,
            s00_axi_wvalid          => s00_axi_wvalid,
            s00_axi_wready          => s00_axi_wready,
            s00_axi_bresp           => s00_axi_bresp,
            s00_axi_bvalid          => s00_axi_bvalid,
            s00_axi_bready          => s00_axi_bready,
            s00_axi_araddr          => s00_axi_araddr,
            s00_axi_arprot          => s00_axi_arprot,
            s00_axi_arvalid         => s00_axi_arvalid,
            s00_axi_arready         => s00_axi_arready,
            s00_axi_rdata           => s00_axi_rdata,
            s00_axi_rresp           => s00_axi_rresp,
            s00_axi_rvalid          => s00_axi_rvalid,
            s00_axi_rready          => s00_axi_rready
        );

    datapath_inst : entity work.channel_emulator_prefetch_top
        generic map(
            G_RELOAD_WORD_COUNT => G_RELOAD_WORD_COUNT,
            G_SET_COUNT         => G_SET_COUNT,
            G_BANK_SET_COUNT    => G_BANK_SET_COUNT,
            G_MAX_SETS_PER_BANK => G_MAX_SETS_PER_BANK,
            G_COEFF_WIDTH       => G_COEFF_WIDTH,
            G_CONFIG_WIDTH      => G_CONFIG_WIDTH,
            G_FIFO_DEPTH        => G_FIFO_DEPTH
        )
        port map(
            aclk     => aclk,
            aresetn  => aresetn,
            enable           => seq_enable,
            clear_status     => seq_clear_status,
            fu_period_cycles => unsigned(seq_fu_period_cycles),
            cfg_bank_sets_per_bank => unsigned(cfg_bank_sets_per_bank),
            coeff_set_tvalid => coeff_set_tvalid,
            coeff_set_tready => coeff_set_tready,
            coeff_set_tdata  => coeff_set_tdata,
            coeff_set_tlast  => coeff_set_tlast,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,
            s_axis_tdata  => s_axis_tdata,
            s_axis_tlast  => s_axis_tlast,
            m_axis_tvalid => m_axis_tvalid,
            m_axis_tready => m_axis_tready,
            m_axis_tdata  => m_axis_tdata,
            m_axis_tlast  => m_axis_tlast,
            reload_active       => w_reload_active,
            reload_set_done     => w_reload_set_done,
            reload_block_done   => w_reload_block_done,
            missed_refill       => w_missed_refill,
            reload_timing_error => w_reload_timing_error,
            coeff_bank_active_set_available => w_coeff_bank_active_set_available,
            coeff_bank_underrun             => w_coeff_bank_underrun,
            coeff_bank_write_error          => w_coeff_bank_write_error,
            state_debug         => w_state_debug,
            dbg_real_reload_tvalid => dbg_real_reload_tvalid,
            dbg_real_reload_tready => dbg_real_reload_tready,
            dbg_real_reload_tdata  => dbg_real_reload_tdata,
            dbg_real_reload_tlast  => dbg_real_reload_tlast,
            dbg_imag_reload_tvalid => dbg_imag_reload_tvalid,
            dbg_imag_reload_tready => dbg_imag_reload_tready,
            dbg_imag_reload_tdata  => dbg_imag_reload_tdata,
            dbg_imag_reload_tlast  => dbg_imag_reload_tlast,
            dbg_real_config_tvalid => dbg_real_config_tvalid,
            dbg_real_config_tready => dbg_real_config_tready,
            dbg_real_config_tdata  => dbg_real_config_tdata,
            dbg_imag_config_tvalid => dbg_imag_config_tvalid,
            dbg_imag_config_tready => dbg_imag_config_tready,
            dbg_imag_config_tdata  => dbg_imag_config_tdata,
            dbg_real_m_tvalid      => dbg_real_m_tvalid,
            dbg_real_m_tready      => dbg_real_m_tready,
            dbg_real_m_tlast       => dbg_real_m_tlast,
            dbg_imag_m_tvalid      => dbg_imag_m_tvalid,
            dbg_imag_m_tready      => dbg_imag_m_tready,
            dbg_imag_m_tlast       => dbg_imag_m_tlast
        );

    reload_active       <= w_reload_active;
    reload_set_done     <= w_reload_set_done;
    reload_block_done   <= w_reload_block_done;
    missed_refill       <= w_missed_refill;
    reload_timing_error <= w_reload_timing_error;
    coeff_bank_active_set_available <= w_coeff_bank_active_set_available;
    coeff_bank_underrun             <= w_coeff_bank_underrun;
    coeff_bank_write_error          <= w_coeff_bank_write_error;
    state_debug         <= w_state_debug;

end architecture;
