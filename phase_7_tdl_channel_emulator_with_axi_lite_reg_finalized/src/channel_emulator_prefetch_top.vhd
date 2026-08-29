library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity channel_emulator_prefetch_top is
    generic(
        G_RELOAD_WORD_COUNT : integer := 133;
        G_BANK_SET_COUNT    : integer := 3;
        G_MAX_SETS_PER_BANK : integer := 600;
        G_COEFF_WIDTH       : integer := 16;
        G_CONFIG_WIDTH      : integer := 8;
        G_FIFO_DEPTH        : integer := 512
    );
    port(
        aclk                            : in  std_logic;
        aresetn                         : in  std_logic;
        enable                          : in  std_logic;
        clear_status                    : in  std_logic;
        fu_period_cycles                : in  unsigned(31 downto 0);
        cfg_bank_sets_per_bank          : in  unsigned(31 downto 0);
        coeff_set_tvalid                : in  std_logic;
        coeff_set_tready                : out std_logic;
        coeff_set_tdata                 : in  std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
        coeff_set_tkeep                 : in  std_logic_vector(((2 * G_COEFF_WIDTH) / 8) - 1 downto 0);
        coeff_set_tlast                 : in  std_logic;
        s_axis_tvalid                   : in  std_logic;
        s_axis_tready                   : out std_logic;
        s_axis_tdata                    : in  std_logic_vector(31 downto 0);
        s_axis_tkeep                    : in  std_logic_vector(3 downto 0);
        s_axis_tlast                    : in  std_logic;
        m_axis_tvalid                   : out std_logic;
        m_axis_tready                   : in  std_logic;
        m_axis_tdata                    : out std_logic_vector(127 downto 0);
        m_axis_tkeep                    : out std_logic_vector(15 downto 0);
        m_axis_tlast                    : out std_logic;
        reload_active                   : out std_logic;
        reload_set_done                 : out std_logic;
        reload_block_done               : out std_logic;
        missed_refill                   : out std_logic;
        reload_timing_error             : out std_logic;
        coeff_bank_active_set_available : out std_logic;
        coeff_bank_underrun             : out std_logic;
        coeff_bank_write_error          : out std_logic;
        fir_reload_error                : out std_logic;
        coeff_bank_active_bank          : out std_logic;
        coeff_bank0_ready               : out std_logic;
        coeff_bank1_ready               : out std_logic;
        state_debug                     : out std_logic_vector(2 downto 0)
    );
end entity;

architecture rtl of channel_emulator_prefetch_top is

    component coeff_ping_pong_buffer is
        generic(
            G_TAP_COUNT         : positive := 32;
            G_MAX_SETS_PER_BANK : positive := 600;
            G_COEFF_WIDTH       : positive := 16;
            G_RAM_STYLE         : string   := "block"
        );
        port(
            aclk                 : in  std_logic;
            aresetn              : in  std_logic;
            clear_errors         : in  std_logic;
            cfg_sets_per_bank    : in  integer range 1 to G_MAX_SETS_PER_BANK;
            wr_valid             : in  std_logic;
            wr_ready             : out std_logic;
            wr_data              : in  std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
            wr_keep              : in  std_logic_vector(((2 * G_COEFF_WIDTH) / 8) - 1 downto 0);
            wr_last              : in  std_logic;
            rd_en                : in  std_logic;
            rd_tap_index         : in  integer range 0 to G_TAP_COUNT - 1;
            rd_data              : out std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
            rd_valid             : out std_logic;
            consume_set_valid    : in  std_logic;
            consume_set_ready    : out std_logic;
            active_set_available : out std_logic;
            underrun             : out std_logic;
            write_error          : out std_logic;
            debug_active_bank    : out std_logic;
            debug_bank0_ready    : out std_logic;
            debug_bank1_ready    : out std_logic
        );
    end component;

    component coeff_reload_sequencer is
        generic(
            G_RELOAD_WORD_COUNT : integer := 133;
            G_MAX_SET_COUNT     : positive := 600;
            G_COEFF_WIDTH       : integer := 16;
            G_CONFIG_WIDTH      : integer := 8;
            G_FIFO_DEPTH        : integer := 512
        );
        port(
            aclk                : in  std_logic;
            aresetn             : in  std_logic;
            enable              : in  std_logic;
            clear_status        : in  std_logic;
            fu_period_cycles    : in  unsigned(31 downto 0);
            block_set_count     : in  integer range 1 to G_MAX_SET_COUNT;
            coeff_set_tvalid    : in  std_logic;
            coeff_set_tready    : out std_logic;
            coeff_set_tdata     : in  std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
            real_reload_tvalid  : out std_logic;
            real_reload_tready  : in  std_logic;
            real_reload_tdata   : out std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
            real_reload_tlast   : out std_logic;
            imag_reload_tvalid  : out std_logic;
            imag_reload_tready  : in  std_logic;
            imag_reload_tdata   : out std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
            imag_reload_tlast   : out std_logic;
            real_config_tvalid  : out std_logic;
            real_config_tready  : in  std_logic;
            real_config_tdata   : out std_logic_vector(G_CONFIG_WIDTH - 1 downto 0);
            imag_config_tvalid  : out std_logic;
            imag_config_tready  : in  std_logic;
            imag_config_tdata   : out std_logic_vector(G_CONFIG_WIDTH - 1 downto 0);
            reload_active       : out std_logic;
            reload_set_done     : out std_logic;
            reload_block_done   : out std_logic;
            missed_refill       : out std_logic;
            reload_timing_error : out std_logic;
            state_debug         : out std_logic_vector(2 downto 0)
        );
    end component;

    component complex_channel_emulator is
        port(
            aclk                      : in  std_logic;
            aresetn                   : in  std_logic;
            s_axis_tvalid             : in  std_logic;
            s_axis_tready             : out std_logic;
            s_axis_tdata              : in  std_logic_vector(31 downto 0);
            s_axis_tlast              : in  std_logic;
            s_axis_config_real_tvalid : in  std_logic;
            s_axis_config_real_tready : out std_logic;
            s_axis_config_real_tdata  : in  std_logic_vector(7 downto 0);
            s_axis_reload_real_tvalid : in  std_logic;
            s_axis_reload_real_tready : out std_logic;
            s_axis_reload_real_tdata  : in  std_logic_vector(15 downto 0);
            s_axis_reload_real_tlast  : in  std_logic;
            s_axis_config_imag_tvalid : in  std_logic;
            s_axis_config_imag_tready : out std_logic;
            s_axis_config_imag_tdata  : in  std_logic_vector(7 downto 0);
            s_axis_reload_imag_tvalid : in  std_logic;
            s_axis_reload_imag_tready : out std_logic;
            s_axis_reload_imag_tdata  : in  std_logic_vector(15 downto 0);
            s_axis_reload_imag_tlast  : in  std_logic;
            m_axis_tvalid             : out std_logic;
            m_axis_tready             : in  std_logic;
            m_axis_tdata              : out std_logic_vector(79 downto 0);
            m_axis_tlast              : out std_logic;
            fir_reload_error          : out std_logic
        );
    end component;

    type t_bank_reader_state is (s_bank_idle, s_bank_wait_data, s_bank_send_word, s_bank_consume_set);

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

    signal bank_rd_en                : std_logic                                  := '0';
    signal bank_sets_per_bank        : integer range 1 to G_MAX_SETS_PER_BANK     := G_BANK_SET_COUNT;
    signal bank_rd_tap_index         : integer range 0 to G_RELOAD_WORD_COUNT - 1 := 0;
    signal bank_rd_data              : std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
    signal bank_rd_valid             : std_logic;
    signal bank_consume_set_valid    : std_logic                                  := '0';
    signal bank_consume_set_ready    : std_logic;
    signal bank_active_set_available : std_logic;
    signal bank_underrun             : std_logic;
    signal bank_write_error          : std_logic;
    signal channel_fir_reload_error  : std_logic;
    signal r_fir_reload_error        : std_logic := '0';
    signal bank_active_bank          : std_logic;
    signal bank0_ready               : std_logic;
    signal bank1_ready               : std_logic;
    signal sample_axis_tready        : std_logic;
    signal channel_m_axis_tdata      : std_logic_vector(79 downto 0);

    signal reader_state           : t_bank_reader_state                                := s_bank_idle;
    signal reader_word_index      : integer range 0 to G_RELOAD_WORD_COUNT - 1         := 0;
    signal sequencer_coeff_tvalid : std_logic                                          := '0';
    signal sequencer_coeff_tready : std_logic;
    signal sequencer_coeff_tdata  : std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0) := (others => '0');

begin

    -- SETS_PER_BANK is setup-time configuration from AXI-Lite. This combinational
    -- guard converts the register value once into the shared range used by both
    -- the ping-pong buffer bank boundary and the sequencer block-done boundary.
    sets_per_bank_config_process : process(cfg_bank_sets_per_bank)
    begin
        if is_x(std_logic_vector(cfg_bank_sets_per_bank)) then
            bank_sets_per_bank <= G_BANK_SET_COUNT;
        elsif cfg_bank_sets_per_bank = to_unsigned(0, cfg_bank_sets_per_bank'length) then
            bank_sets_per_bank <= G_BANK_SET_COUNT;
        elsif cfg_bank_sets_per_bank > to_unsigned(G_MAX_SETS_PER_BANK, cfg_bank_sets_per_bank'length) then
            bank_sets_per_bank <= G_MAX_SETS_PER_BANK;
        else
            bank_sets_per_bank <= to_integer(cfg_bank_sets_per_bank);
        end if;
    end process;

    coeff_bank_inst : coeff_ping_pong_buffer
        generic map(
            G_TAP_COUNT         => G_RELOAD_WORD_COUNT,
            G_MAX_SETS_PER_BANK => G_MAX_SETS_PER_BANK,
            G_COEFF_WIDTH       => G_COEFF_WIDTH,
            G_RAM_STYLE         => "block"
        )
        port map(
            aclk                 => aclk,
            aresetn              => aresetn,
            clear_errors         => clear_status,
            cfg_sets_per_bank    => bank_sets_per_bank,
            wr_valid             => coeff_set_tvalid,
            wr_ready             => coeff_set_tready,
            wr_data              => coeff_set_tdata,
            wr_keep              => coeff_set_tkeep,
            wr_last              => coeff_set_tlast,
            rd_en                => bank_rd_en,
            rd_tap_index         => bank_rd_tap_index,
            rd_data              => bank_rd_data,
            rd_valid             => bank_rd_valid,
            consume_set_valid    => bank_consume_set_valid,
            consume_set_ready    => bank_consume_set_ready,
            active_set_available => bank_active_set_available,
            underrun             => bank_underrun,
            write_error          => bank_write_error,
            debug_active_bank    => bank_active_bank,
            debug_bank0_ready    => bank0_ready,
            debug_bank1_ready    => bank1_ready
        );

    bank_reader_process : process(aclk, aresetn)
    begin
        if aresetn = '0' then
            reader_state           <= s_bank_idle;
            reader_word_index      <= 0;
            bank_rd_en             <= '0';
            bank_rd_tap_index      <= 0;
            bank_consume_set_valid <= '0';
            sequencer_coeff_tvalid <= '0';
            sequencer_coeff_tdata  <= (others => '0');
        elsif rising_edge(aclk) then
            bank_rd_en             <= '0';
            bank_consume_set_valid <= '0';

            case reader_state is
                when s_bank_idle =>
                    sequencer_coeff_tvalid <= '0';
                    reader_word_index      <= 0;

                    if enable = '1' and bank_active_set_available = '1' then
                        bank_rd_en        <= '1';
                        bank_rd_tap_index <= 0;
                        reader_state      <= s_bank_wait_data;
                    end if;

                when s_bank_wait_data =>
                    if bank_rd_valid = '1' then
                        sequencer_coeff_tdata  <= bank_rd_data;
                        sequencer_coeff_tvalid <= '1';
                        reader_state           <= s_bank_send_word;
                    end if;

                when s_bank_send_word =>
                    if sequencer_coeff_tvalid = '1' and sequencer_coeff_tready = '1' then
                        sequencer_coeff_tvalid <= '0';

                        if reader_word_index = G_RELOAD_WORD_COUNT - 1 then
                            bank_consume_set_valid <= '1';
                            reader_state           <= s_bank_consume_set;
                        else
                            reader_word_index <= reader_word_index + 1;
                            bank_rd_tap_index <= reader_word_index + 1;
                            bank_rd_en        <= '1';
                            reader_state      <= s_bank_wait_data;
                        end if;
                    end if;

                when s_bank_consume_set =>
                    bank_consume_set_valid <= '1';

                    if bank_consume_set_ready = '1' then
                        bank_consume_set_valid <= '0';
                        reader_word_index      <= 0;
                        reader_state           <= s_bank_idle;
                    end if;
            end case;
        end if;
    end process;

    fir_reload_error_status_process : process(aclk, aresetn)
    begin
        if aresetn = '0' then
            r_fir_reload_error <= '0';
        elsif rising_edge(aclk) then
            if clear_status = '1' then
                r_fir_reload_error <= '0';
            elsif channel_fir_reload_error = '1' then
                r_fir_reload_error <= '1';
            end if;
        end if;
    end process;

    sequencer_inst : coeff_reload_sequencer
        generic map(
            G_RELOAD_WORD_COUNT => G_RELOAD_WORD_COUNT,
            G_MAX_SET_COUNT     => G_MAX_SETS_PER_BANK,
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
            block_set_count     => bank_sets_per_bank,
            coeff_set_tvalid    => sequencer_coeff_tvalid,
            coeff_set_tready    => sequencer_coeff_tready,
            coeff_set_tdata     => sequencer_coeff_tdata,
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

    channel_inst : complex_channel_emulator
        port map(
            aclk                      => aclk,
            aresetn                   => aresetn,
            s_axis_tvalid             => s_axis_tvalid,
            s_axis_tready             => sample_axis_tready,
            s_axis_tdata              => s_axis_tdata,
            s_axis_tlast              => s_axis_tlast,
            s_axis_config_real_tvalid => real_config_tvalid,
            s_axis_config_real_tready => real_config_tready,
            s_axis_config_real_tdata  => real_config_tdata,
            s_axis_reload_real_tvalid => real_reload_tvalid,
            s_axis_reload_real_tready => real_reload_tready,
            s_axis_reload_real_tdata  => real_reload_tdata,
            s_axis_reload_real_tlast  => real_reload_tlast,
            s_axis_config_imag_tvalid => imag_config_tvalid,
            s_axis_config_imag_tready => imag_config_tready,
            s_axis_config_imag_tdata  => imag_config_tdata,
            s_axis_reload_imag_tvalid => imag_reload_tvalid,
            s_axis_reload_imag_tready => imag_reload_tready,
            s_axis_reload_imag_tdata  => imag_reload_tdata,
            s_axis_reload_imag_tlast  => imag_reload_tlast,
            m_axis_tvalid             => m_axis_tvalid,
            m_axis_tready             => m_axis_tready,
            m_axis_tdata              => channel_m_axis_tdata,
            m_axis_tlast              => m_axis_tlast,
            fir_reload_error          => channel_fir_reload_error
        );

    s_axis_tready <= sample_axis_tready;
    m_axis_tdata(79 downto 0) <= channel_m_axis_tdata;
    m_axis_tdata(127 downto 80) <= (others => '0');
    m_axis_tkeep <= (others => '1');

    -- synthesis translate_off
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '1' and s_axis_tvalid = '1' and sample_axis_tready = '1' then
                assert s_axis_tkeep = (s_axis_tkeep'range => '1')
                report "Sample AXIS TKEEP must mark all 32-bit IQ bytes valid"
                severity error;
            end if;
        end if;
    end process;
    -- synthesis translate_on

    coeff_bank_active_set_available <= bank_active_set_available;
    coeff_bank_underrun             <= bank_underrun;
    coeff_bank_write_error          <= bank_write_error;
    fir_reload_error                <= r_fir_reload_error;
    coeff_bank_active_bank          <= bank_active_bank;
    coeff_bank0_ready               <= bank0_ready;
    coeff_bank1_ready               <= bank1_ready;

end architecture;
