library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity channel_emulator_prefetch_top is
    generic(
        G_RELOAD_WORD_COUNT : integer := 32;
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
        cfg_refill_threshold_sets       : in  unsigned(31 downto 0);
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
        refill_request                  : out std_logic;
        refill_request_pulse            : out std_logic;
        reload_timing_error             : out std_logic;
        coeff_bank_active_set_available : out std_logic;
        coeff_bank_underrun             : out std_logic;
        coeff_bank_write_error          : out std_logic;
        fir_reload_error                : out std_logic;
        coeff_bank_active_bank          : out std_logic;
        coeff_bank0_ready               : out std_logic;
        coeff_bank1_ready               : out std_logic;
        dbg_reload_valid_o              : out std_logic;
        dbg_reload_combined_ready_o     : out std_logic;
        dbg_reload_real_ready_o         : out std_logic;
        dbg_reload_imag_ready_o         : out std_logic;
        dbg_reload_last_o               : out std_logic;
        dbg_reload_real_data_o          : out std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
        dbg_reload_imag_data_o          : out std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
        dbg_fir_real_reload_tlast_missing_o    : out std_logic;
        dbg_fir_real_reload_tlast_unexpected_o : out std_logic;
        dbg_fir_imag_reload_tlast_missing_o    : out std_logic;
        dbg_fir_imag_reload_tlast_unexpected_o : out std_logic;
        dbg_config_valid_o              : out std_logic;
        dbg_config_ready_o              : out std_logic;
        dbg_fu_tick_o                   : out std_logic;
        dbg_seq_enable_o                : out std_logic;
        dbg_next_state_o                : out std_logic_vector(2 downto 0);
        dbg_reload_accept_o             : out std_logic;
        dbg_config_accept_o             : out std_logic;
        dbg_timing_fault_o              : out std_logic;
        dbg_reload_word_index_o         : out std_logic_vector(15 downto 0);
        dbg_reload_set_index_o          : out std_logic_vector(15 downto 0);
        dbg_seq_fifo_usedw_o            : out std_logic_vector(15 downto 0);
        dbg_seq_fifo_has_set_o          : out std_logic;
        dbg_seq_input_ready_o           : out std_logic;
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
            G_RELOAD_WORD_COUNT : integer := 32;
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
            refill_threshold_sets : in integer range 0 to G_MAX_SET_COUNT;
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
            refill_request      : out std_logic;
            refill_request_pulse : out std_logic;
            reload_timing_error : out std_logic;
            dbg_fu_tick_o       : out std_logic;
            dbg_next_state_o    : out std_logic_vector(2 downto 0);
            dbg_reload_accept_o : out std_logic;
            dbg_config_accept_o : out std_logic;
            dbg_timing_fault_o  : out std_logic;
            dbg_reload_word_index_o : out std_logic_vector(15 downto 0);
            dbg_reload_set_index_o  : out std_logic_vector(15 downto 0);
            dbg_seq_fifo_usedw_o : out std_logic_vector(15 downto 0);
            dbg_seq_fifo_has_set_o : out std_logic;
            dbg_seq_input_ready_o : out std_logic;
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
            fir_reload_error          : out std_logic;
            fir_real_reload_tlast_missing    : out std_logic;
            fir_real_reload_tlast_unexpected : out std_logic;
            fir_imag_reload_tlast_missing    : out std_logic;
            fir_imag_reload_tlast_unexpected : out std_logic
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
    signal bank_sets_per_bank_next   : integer range 1 to G_MAX_SETS_PER_BANK     := G_BANK_SET_COUNT;
    signal refill_threshold_sets     : integer range 0 to G_MAX_SETS_PER_BANK     := 0;
    signal refill_threshold_sets_next : integer range 0 to G_MAX_SETS_PER_BANK    := 0;
    signal bank_rd_tap_index         : integer range 0 to G_RELOAD_WORD_COUNT - 1 := 0;
    signal bank_rd_data              : std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
    signal bank_rd_valid             : std_logic;
    signal bank_consume_set_valid    : std_logic                                  := '0';
    signal bank_consume_set_ready    : std_logic;
    signal bank_active_set_available : std_logic;
    signal bank_underrun             : std_logic;
    signal bank_write_error          : std_logic;
    signal channel_fir_reload_error  : std_logic;
    signal channel_real_reload_tlast_missing    : std_logic;
    signal channel_real_reload_tlast_unexpected : std_logic;
    signal channel_imag_reload_tlast_missing    : std_logic;
    signal channel_imag_reload_tlast_unexpected : std_logic;
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
    signal sequencer_fu_tick      : std_logic;
    signal sequencer_next_state   : std_logic_vector(2 downto 0);
    signal sequencer_reload_accept : std_logic;
    signal sequencer_config_accept : std_logic;
    signal sequencer_timing_fault : std_logic;
    signal sequencer_reload_word_index : std_logic_vector(15 downto 0);
    signal sequencer_reload_set_index  : std_logic_vector(15 downto 0);
    signal sequencer_fifo_usedw        : std_logic_vector(15 downto 0);
    signal sequencer_fifo_has_set      : std_logic;
    signal sequencer_input_ready       : std_logic;

begin

    -- SETS_PER_BANK and REFILL_THRESHOLD are setup-time AXI-Lite
    -- configuration. Register the sanitized values locally so wide AXI
    -- register decode/comparison logic is not on the 300 MHz reload path.
    bank_sets_per_bank_next <= G_BANK_SET_COUNT when is_x(std_logic_vector(cfg_bank_sets_per_bank)) else
                               G_BANK_SET_COUNT when cfg_bank_sets_per_bank = to_unsigned(0, cfg_bank_sets_per_bank'length) else
                               G_MAX_SETS_PER_BANK when cfg_bank_sets_per_bank > to_unsigned(G_MAX_SETS_PER_BANK, cfg_bank_sets_per_bank'length) else
                               to_integer(cfg_bank_sets_per_bank);

    refill_threshold_sets_next <= 0 when is_x(std_logic_vector(cfg_refill_threshold_sets)) else
                                  0 when cfg_refill_threshold_sets = to_unsigned(0, cfg_refill_threshold_sets'length) else
                                  bank_sets_per_bank_next - 1 when cfg_refill_threshold_sets >= to_unsigned(bank_sets_per_bank_next, cfg_refill_threshold_sets'length) else
                                  G_MAX_SETS_PER_BANK when cfg_refill_threshold_sets > to_unsigned(G_MAX_SETS_PER_BANK, cfg_refill_threshold_sets'length) else
                                  to_integer(cfg_refill_threshold_sets);

    config_register_process : process(aclk, aresetn)
    begin
        if aresetn = '0' then
            bank_sets_per_bank    <= G_BANK_SET_COUNT;
            refill_threshold_sets <= 0;
        elsif rising_edge(aclk) then
            bank_sets_per_bank    <= bank_sets_per_bank_next;
            refill_threshold_sets <= refill_threshold_sets_next;
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
            refill_threshold_sets => refill_threshold_sets,
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
            refill_request      => refill_request,
            refill_request_pulse => refill_request_pulse,
            reload_timing_error => reload_timing_error,
            dbg_fu_tick_o       => sequencer_fu_tick,
            dbg_next_state_o    => sequencer_next_state,
            dbg_reload_accept_o => sequencer_reload_accept,
            dbg_config_accept_o => sequencer_config_accept,
            dbg_timing_fault_o  => sequencer_timing_fault,
            dbg_reload_word_index_o => sequencer_reload_word_index,
            dbg_reload_set_index_o  => sequencer_reload_set_index,
            dbg_seq_fifo_usedw_o => sequencer_fifo_usedw,
            dbg_seq_fifo_has_set_o => sequencer_fifo_has_set,
            dbg_seq_input_ready_o => sequencer_input_ready,
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
            fir_reload_error          => channel_fir_reload_error,
            fir_real_reload_tlast_missing    => channel_real_reload_tlast_missing,
            fir_real_reload_tlast_unexpected => channel_real_reload_tlast_unexpected,
            fir_imag_reload_tlast_missing    => channel_imag_reload_tlast_missing,
            fir_imag_reload_tlast_unexpected => channel_imag_reload_tlast_unexpected
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
    dbg_reload_valid_o              <= real_reload_tvalid or imag_reload_tvalid;
    dbg_reload_combined_ready_o     <= real_reload_tready and imag_reload_tready;
    dbg_reload_real_ready_o         <= real_reload_tready;
    dbg_reload_imag_ready_o         <= imag_reload_tready;
    dbg_reload_last_o               <= real_reload_tlast or imag_reload_tlast;
    dbg_reload_real_data_o          <= real_reload_tdata;
    dbg_reload_imag_data_o          <= imag_reload_tdata;
    dbg_fir_real_reload_tlast_missing_o    <= channel_real_reload_tlast_missing;
    dbg_fir_real_reload_tlast_unexpected_o <= channel_real_reload_tlast_unexpected;
    dbg_fir_imag_reload_tlast_missing_o    <= channel_imag_reload_tlast_missing;
    dbg_fir_imag_reload_tlast_unexpected_o <= channel_imag_reload_tlast_unexpected;
    dbg_config_valid_o              <= real_config_tvalid or imag_config_tvalid;
    dbg_config_ready_o              <= real_config_tready and imag_config_tready;
    dbg_fu_tick_o                   <= sequencer_fu_tick;
    dbg_seq_enable_o                <= enable;
    dbg_next_state_o                <= sequencer_next_state;
    dbg_reload_accept_o             <= sequencer_reload_accept;
    dbg_config_accept_o             <= sequencer_config_accept;
    dbg_timing_fault_o              <= sequencer_timing_fault;
    dbg_reload_word_index_o         <= sequencer_reload_word_index;
    dbg_reload_set_index_o          <= sequencer_reload_set_index;
    dbg_seq_fifo_usedw_o            <= sequencer_fifo_usedw;
    dbg_seq_fifo_has_set_o          <= sequencer_fifo_has_set;
    dbg_seq_input_ready_o           <= sequencer_input_ready;

end architecture;

 
