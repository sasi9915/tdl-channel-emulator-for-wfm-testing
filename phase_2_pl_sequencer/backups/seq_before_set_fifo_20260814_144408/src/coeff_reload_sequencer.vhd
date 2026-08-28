library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity coeff_reload_sequencer is
    generic(
        G_TAP_COUNT    : integer := 32;
        G_SET_COUNT    : integer := 3;
        G_COEFF_WIDTH  : integer := 16;
        G_CONFIG_WIDTH : integer := 8
    );
    port(
        aclk                : in  std_logic;
        aresetn             : in  std_logic;

        enable              : in  std_logic;
        clear_status        : in  std_logic;
        fu_period_cycles    : in  unsigned(31 downto 0);

        next_set_available  : in  std_logic;
        
        coeff_real_value    : in  std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
        coeff_imag_value    : in  std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
        coeff_set_index     : out integer range 0 to G_SET_COUNT - 1;
        coeff_tap_index     : out integer range 0 to G_TAP_COUNT - 1;

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
end entity;

architecture rtl of coeff_reload_sequencer is

    type t_state is (s_idle, s_wait_fu, s_reload, s_config, s_advance, s_done, s_fault_hold);

    signal state      : t_state := s_idle;
    signal next_state : t_state := s_idle;

    signal r_fu_counter : unsigned(31 downto 0) := (others => '0');
    signal w_fu_tick    : std_logic;

    signal r_set_index : integer range 0 to G_SET_COUNT - 1 := 0;
    signal r_tap_index : integer range 0 to G_TAP_COUNT - 1 := 0;

    signal r_real_reload_valid : std_logic                                    := '0';
    signal r_imag_reload_valid : std_logic                                    := '0';
    signal r_real_reload_data  : std_logic_vector(G_COEFF_WIDTH - 1 downto 0) := (others => '0');
    signal r_imag_reload_data  : std_logic_vector(G_COEFF_WIDTH - 1 downto 0) := (others => '0');
    signal r_reload_last       : std_logic                                    := '0';

    signal r_real_config_valid : std_logic := '0';
    signal r_imag_config_valid : std_logic := '0';

    signal r_reload_set_done     : std_logic := '0';
    signal r_reload_block_done   : std_logic := '0';
    signal r_missed_refill       : std_logic := '0';
    signal r_reload_timing_error : std_logic := '0';

    signal w_reload_accepted : std_logic;
    signal w_config_accepted : std_logic;

begin

    with state select state_debug <=
        "000" when s_idle,
        "001" when s_wait_fu,
        "010" when s_reload,
        "011" when s_config,
        "100" when s_advance,
        "101" when s_done,
        "111" when others;

    w_fu_tick <= '1' when enable = '1' and fu_period_cycles /= to_unsigned(0, fu_period_cycles'length) and r_fu_counter = fu_period_cycles - 1 else '0';

    w_reload_accepted <= r_real_reload_valid and r_imag_reload_valid and real_reload_tready and imag_reload_tready;

    w_config_accepted <= r_real_config_valid and r_imag_config_valid and real_config_tready and imag_config_tready;

    process(aclk, aresetn)
    begin
        if aresetn = '0' then
            r_fu_counter <= (others => '0');
        elsif rising_edge(aclk) then
            if enable = '0' or fu_period_cycles = to_unsigned(0, fu_period_cycles'length) then

                r_fu_counter <= (others => '0');
            elsif w_fu_tick = '1' then
                r_fu_counter <= (others => '0');
            else
                r_fu_counter <= r_fu_counter + 1;
            end if;
        end if;
    end process;

    process(aclk, aresetn)
    begin
        if aresetn = '0' then
            state                 <= s_idle;
            r_set_index           <= 0;
            r_tap_index           <= 0;
            r_real_reload_valid   <= '0';
            r_imag_reload_valid   <= '0';
            r_real_reload_data    <= (others => '0');
            r_imag_reload_data    <= (others => '0');
            r_reload_last         <= '0';
            r_real_config_valid   <= '0';
            r_imag_config_valid   <= '0';
            r_reload_set_done     <= '0';
            r_reload_block_done   <= '0';
            r_missed_refill       <= '0';
            r_reload_timing_error <= '0';
        elsif rising_edge(aclk) then
            r_reload_set_done <= '0';

            if clear_status = '1' then
                r_reload_block_done   <= '0';
                r_missed_refill       <= '0';
                r_reload_timing_error <= '0';
            end if;

            if enable = '0' then
                r_real_reload_valid   <= '0';
                r_imag_reload_valid   <= '0';
                r_reload_last         <= '0';
                r_real_config_valid   <= '0';
                r_imag_config_valid   <= '0';
                r_set_index           <= 0;
                r_tap_index           <= 0;
                r_reload_block_done   <= '0';
                r_missed_refill       <= '0';
                r_reload_timing_error <= '0';
            elsif w_fu_tick = '1' and (state = s_reload or state = s_config or state = s_advance) then

                r_reload_timing_error <= '1';
                r_real_reload_valid   <= '0';
                r_imag_reload_valid   <= '0';
                r_reload_last         <= '0';
                r_real_config_valid   <= '0';
                r_imag_config_valid   <= '0';
            else
                case state is
                    when s_idle =>
                        r_real_reload_valid <= '0';
                        r_imag_reload_valid <= '0';
                        r_reload_last       <= '0';
                        r_real_config_valid <= '0';
                        r_imag_config_valid <= '0';
                        r_set_index         <= 0;
                        r_tap_index         <= 0;

                    when s_wait_fu =>
                        if w_fu_tick = '1' then
                            r_tap_index <= 0;

                            if next_set_available = '0' then
                                r_missed_refill <= '1';
                            end if;
                        end if;

                    when s_reload =>
                        if r_real_reload_valid = '0' and r_imag_reload_valid = '0' then
                            r_real_reload_data  <= coeff_real_value;
                            r_imag_reload_data  <= coeff_imag_value;
                            r_real_reload_valid <= '1';
                            r_imag_reload_valid <= '1';

                            if r_tap_index = G_TAP_COUNT - 1 then
                                r_reload_last <= '1';
                            else
                                r_reload_last <= '0';
                            end if;
                        elsif w_reload_accepted = '1' then
                            r_real_reload_valid <= '0';
                            r_imag_reload_valid <= '0';
                            r_reload_last       <= '0';

                            if r_tap_index = G_TAP_COUNT - 1 then
                                r_real_config_valid <= '1';
                                r_imag_config_valid <= '1';
                            else
                                r_tap_index <= r_tap_index + 1;
                            end if;
                        end if;

                    when s_config =>
                        if w_config_accepted = '1' then
                            r_real_config_valid <= '0';
                            r_imag_config_valid <= '0';
                        end if;

                    when s_advance =>
                        r_reload_set_done <= '1';

                        if r_set_index = G_SET_COUNT - 1 then
                            r_reload_block_done <= '1';
                        else
                            r_set_index <= r_set_index + 1;
                            r_tap_index <= 0;
                        end if;

                    when s_done =>
                        null;

                    when s_fault_hold =>
                        null;
                end case;
            end if;

            state <= next_state;
        end if;
    end process;

    process(state, enable, w_fu_tick, next_set_available, r_set_index, r_tap_index, w_reload_accepted, w_config_accepted)
    begin
        next_state <= state;

        if enable = '0' then
            next_state <= s_idle;
        elsif w_fu_tick = '1' and (state = s_reload or state = s_config or state = s_advance) then

            next_state <= s_fault_hold;
        else
            case state is
                when s_idle =>
                    next_state <= s_wait_fu;

                when s_wait_fu =>
                    if w_fu_tick = '1' and next_set_available = '1' then
                        next_state <= s_reload;
                    end if;

                when s_reload =>
                    if w_reload_accepted = '1' then
                        if r_tap_index = G_TAP_COUNT - 1 then
                            next_state <= s_config;
                        end if;
                    end if;

                when s_config =>
                    if w_config_accepted = '1' then
                        next_state <= s_advance;
                    end if;

                when s_advance =>
                    if r_set_index = G_SET_COUNT - 1 then
                        next_state <= s_done;
                    else
                        next_state <= s_wait_fu;
                    end if;

                when s_done =>
                    null;

                when s_fault_hold =>
                    null;
            end case;
        end if;
    end process;

    coeff_set_index <= r_set_index;
    coeff_tap_index <= r_tap_index;

    real_reload_tvalid <= r_real_reload_valid;
    imag_reload_tvalid <= r_imag_reload_valid;
    real_reload_tdata  <= r_real_reload_data;
    imag_reload_tdata  <= r_imag_reload_data;
    real_reload_tlast  <= r_reload_last;
    imag_reload_tlast  <= r_reload_last;

    real_config_tvalid <= r_real_config_valid;
    imag_config_tvalid <= r_imag_config_valid;
    real_config_tdata  <= (others => '0');
    imag_config_tdata  <= (others => '0');

    reload_active       <= '1' when state = s_reload or state = s_config or state = s_advance else '0';
    reload_set_done     <= r_reload_set_done;
    reload_block_done   <= r_reload_block_done;
    missed_refill       <= r_missed_refill;
    reload_timing_error <= r_reload_timing_error;

end architecture;
