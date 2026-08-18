library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity channel_emulator_prefetch_top is
    generic(
        G_RELOAD_WORD_COUNT : integer := 133;
        G_SET_COUNT         : integer := 3;
        G_COEFF_WIDTH       : integer := 16;
        G_CONFIG_WIDTH      : integer := 8;
        G_FIFO_DEPTH        : integer := 512
    );
    port(
        aclk     : in std_logic;
        aresetn  : in std_logic;

        enable           : in  std_logic;
        clear_status     : in  std_logic;
        fu_period_cycles : in  unsigned(31 downto 0);

        coeff_set_tvalid : in  std_logic;
        coeff_set_tready : out std_logic;
        coeff_set_tdata  : in  std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);

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
        dbg_imag_config_tdata  : out std_logic_vector(G_CONFIG_WIDTH - 1 downto 0)
    );
end entity;

architecture rtl of channel_emulator_prefetch_top is

    signal real_reload_tvalid : std_logic;
    signal real_reload_tready : std_logic;
    signal real_reload_tdata  : std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
    signal real_reload_tlast  : std_logic;

    signal imag_reload_tvalid : std_logic;
    signal imag_reload_tready : std_logic;
    signal imag_reload_tdata  : std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
    signal imag_reload_tlast  : std_logic;

    signal real_config_tvalid : std_logic;
    signal real_config_tready : std_logic;
    signal real_config_tdata  : std_logic_vector(G_CONFIG_WIDTH - 1 downto 0);

    signal imag_config_tvalid : std_logic;
    signal imag_config_tready : std_logic;
    signal imag_config_tdata  : std_logic_vector(G_CONFIG_WIDTH - 1 downto 0);

begin

    sequencer_inst : entity work.coeff_reload_sequencer
        generic map(
            G_RELOAD_WORD_COUNT => G_RELOAD_WORD_COUNT,
            G_SET_COUNT         => G_SET_COUNT,
            G_COEFF_WIDTH       => G_COEFF_WIDTH,
            G_CONFIG_WIDTH      => G_CONFIG_WIDTH,
            G_FIFO_DEPTH        => G_FIFO_DEPTH
        )
        port map(
            aclk                => aclk,
            aresetn             => aresetn,
            enable              => enable,
            clear_status        => clear_status,
            fu_period_cycles    => fu_period_cycles,
            coeff_set_tvalid    => coeff_set_tvalid,
            coeff_set_tready    => coeff_set_tready,
            coeff_set_tdata     => coeff_set_tdata,
            real_reload_tvalid  => real_reload_tvalid,
            real_reload_tready  => real_reload_tready,
            real_reload_tdata   => real_reload_tdata,
            real_reload_tlast   => real_reload_tlast,
            imag_reload_tvalid  => imag_reload_tvalid,
            imag_reload_tready  => imag_reload_tready,
            imag_reload_tdata   => imag_reload_tdata,
            imag_reload_tlast   => imag_reload_tlast,
            real_config_tvalid  => real_config_tvalid,
            real_config_tready  => real_config_tready,
            real_config_tdata   => real_config_tdata,
            imag_config_tvalid  => imag_config_tvalid,
            imag_config_tready  => imag_config_tready,
            imag_config_tdata   => imag_config_tdata,
            reload_active       => reload_active,
            reload_set_done     => reload_set_done,
            reload_block_done   => reload_block_done,
            missed_refill       => missed_refill,
            reload_timing_error => reload_timing_error,
            state_debug         => state_debug
        );

    channel_inst : entity work.complex_channel_emulator
        port map(
            aclk                         => aclk,
            aresetn                      => aresetn,
            s_axis_tvalid                => s_axis_tvalid,
            s_axis_tready                => s_axis_tready,
            s_axis_tdata                 => s_axis_tdata,
            s_axis_tlast                 => s_axis_tlast,
            s_axis_config_real_tvalid    => real_config_tvalid,
            s_axis_config_real_tready    => real_config_tready,
            s_axis_config_real_tdata     => real_config_tdata,
            s_axis_reload_real_tvalid    => real_reload_tvalid,
            s_axis_reload_real_tready    => real_reload_tready,
            s_axis_reload_real_tdata     => real_reload_tdata,
            s_axis_reload_real_tlast     => real_reload_tlast,
            s_axis_config_imag_tvalid    => imag_config_tvalid,
            s_axis_config_imag_tready    => imag_config_tready,
            s_axis_config_imag_tdata     => imag_config_tdata,
            s_axis_reload_imag_tvalid    => imag_reload_tvalid,
            s_axis_reload_imag_tready    => imag_reload_tready,
            s_axis_reload_imag_tdata     => imag_reload_tdata,
            s_axis_reload_imag_tlast     => imag_reload_tlast,
            m_axis_tvalid                => m_axis_tvalid,
            m_axis_tready                => m_axis_tready,
            m_axis_tdata                 => m_axis_tdata,
            m_axis_tlast                 => m_axis_tlast
        );

    dbg_real_reload_tvalid <= real_reload_tvalid;
    dbg_real_reload_tready <= real_reload_tready;
    dbg_real_reload_tdata  <= real_reload_tdata;
    dbg_real_reload_tlast  <= real_reload_tlast;
    dbg_imag_reload_tvalid <= imag_reload_tvalid;
    dbg_imag_reload_tready <= imag_reload_tready;
    dbg_imag_reload_tdata  <= imag_reload_tdata;
    dbg_imag_reload_tlast  <= imag_reload_tlast;
    dbg_real_config_tvalid <= real_config_tvalid;
    dbg_real_config_tready <= real_config_tready;
    dbg_real_config_tdata  <= real_config_tdata;
    dbg_imag_config_tvalid <= imag_config_tvalid;
    dbg_imag_config_tready <= imag_config_tready;
    dbg_imag_config_tdata  <= imag_config_tdata;

end architecture;
