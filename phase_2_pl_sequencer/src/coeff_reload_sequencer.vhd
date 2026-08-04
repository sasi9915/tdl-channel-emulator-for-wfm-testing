library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity coeff_reload_sequencer is
    generic(
        G_TAP_COUNT                  : integer := 32;
        G_SET_COUNT                  : integer := 3;
        G_COEFF_WIDTH                : integer := 16;
        G_CONFIG_WIDTH               : integer := 8
    );
    port(
        aclk                         : in  std_logic;
        aresetn                      : in  std_logic;
        start                        : in  std_logic;
        fu_tick                      : in  std_logic;
        coeff_real_value             : in  std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
        coeff_imag_value             : in  std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
        coeff_set_index              : out integer range 0 to G_SET_COUNT - 1;
        coeff_tap_index              : out integer range 0 to G_TAP_COUNT - 1;
        real_reload_tvalid           : out std_logic;
        real_reload_tready           : in  std_logic;
        real_reload_tdata            : out std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
        real_reload_tlast            : out std_logic;
        imag_reload_tvalid           : out std_logic;
        imag_reload_tready           : in  std_logic;
        imag_reload_tdata            : out std_logic_vector(G_COEFF_WIDTH - 1 downto 0);
        imag_reload_tlast            : out std_logic;
        real_config_tvalid           : out std_logic;
        real_config_tready           : in  std_logic;
        real_config_tdata            : out std_logic_vector(G_CONFIG_WIDTH - 1 downto 0);
        imag_config_tvalid           : out std_logic;
        imag_config_tready           : in  std_logic;
        imag_config_tdata            : out std_logic_vector(G_CONFIG_WIDTH - 1 downto 0);
        busy                         : out std_logic;
        done                         : out std_logic;
        block_done                   : out std_logic;
        timing_error                 : out std_logic;
        state_debug                  : out std_logic_vector(2 downto 0)
    );
end entity;

architecture rtl of coeff_reload_sequencer is

    type t_state is (s_idle, s_wait_fu, s_reload, s_config, s_advance, s_done, s_fault_hold);

    signal state      : t_state := s_idle;
    signal next_state : t_state := s_idle;

    signal r_set_index : integer range 0 to G_SET_COUNT - 1 := 0;
    signal r_tap_index : integer range 0 to G_TAP_COUNT - 1 := 0;

    signal r_real_reload_valid : std_logic                                    := '0';
    signal r_imag_reload_valid : std_logic                                    := '0';
    signal r_real_reload_data  : std_logic_vector(G_COEFF_WIDTH - 1 downto 0) := (others => '0');
    signal r_imag_reload_data  : std_logic_vector(G_COEFF_WIDTH - 1 downto 0) := (others => '0');
    signal r_reload_last       : std_logic                                    := '0';

    signal r_real_config_valid : std_logic := '0';
    signal r_imag_config_valid : std_logic := '0';

    signal r_done         : std_logic := '0';
    signal r_block_done   : std_logic := '0';
    signal r_timing_error : std_logic := '0';

    signal r_reload_accepted : std_logic;
    signal r_config_accepted : std_logic;

begin

    with state select state_debug <=
        "000" when s_idle,
        "001" when s_wait_fu,
        "010" when s_reload,
        "011" when s_config,
        "100" when s_advance,
        "101" when s_done,
        "111" when others;

    r_reload_accepted <= r_real_reload_valid and r_imag_reload_valid and real_reload_tready and imag_reload_tready;

    r_config_accepted <= r_real_config_valid and r_imag_config_valid and real_config_tready and imag_config_tready;

    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state               <= s_idle;
                r_set_index         <= 0;
                r_tap_index         <= 0;
                r_real_reload_valid <= '0';
                r_imag_reload_valid <= '0';
                r_real_reload_data  <= (others => '0');
                r_imag_reload_data  <= (others => '0');
                r_reload_last       <= '0';
                r_real_config_valid <= '0';
                r_imag_config_valid <= '0';
                r_done              <= '0';
                r_block_done        <= '0';
                r_timing_error      <= '0';
            else
                r_done <= '0';

                if fu_tick = '1' and (state = s_reload or state = s_config or state = s_advance) then
                    r_timing_error      <= '1';
                    r_real_reload_valid <= '0';
                    r_imag_reload_valid <= '0';
                    r_reload_last       <= '0';
                    r_real_config_valid <= '0';
                    r_imag_config_valid <= '0';
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
                            r_timing_error      <= '0';
                            r_block_done        <= '0';

                        when s_wait_fu =>
                            if fu_tick = '1' then
                                r_tap_index <= 0;
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
                            elsif r_reload_accepted = '1' then
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
                            if r_config_accepted = '1' then
                                r_real_config_valid <= '0';
                                r_imag_config_valid <= '0';
                            end if;

                        when s_advance =>
                            r_done <= '1';

                            if r_set_index = G_SET_COUNT - 1 then
                                r_block_done <= '1';
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
        end if;
    end process;

    process(state, start, fu_tick, r_set_index, r_tap_index, r_reload_accepted, r_config_accepted)
    begin
        next_state <= state;

        if fu_tick = '1' and (state = s_reload or state = s_config or state = s_advance) then
            next_state <= s_fault_hold;
        else
            case state is
                when s_idle =>
                    if start = '1' then
                        next_state <= s_wait_fu;
                    end if;

                when s_wait_fu =>
                    if start = '0' then
                        next_state <= s_idle;
                    elsif fu_tick = '1' then
                        next_state <= s_reload;
                    end if;

                when s_reload =>
                    if r_reload_accepted = '1' then
                        if r_tap_index = G_TAP_COUNT - 1 then
                            next_state <= s_config;
                        end if;
                    end if;

                when s_config =>
                    if r_config_accepted = '1' then
                        next_state <= s_advance;
                    end if;

                when s_advance =>
                    if r_set_index = G_SET_COUNT - 1 then
                        next_state <= s_done;
                    else
                        next_state <= s_wait_fu;
                    end if;

                when s_done =>
                    if start = '0' then
                        next_state <= s_idle;
                    end if;

                when s_fault_hold =>
                    if start = '0' then
                        next_state <= s_idle;
                    end if;
            end case;
        end if;
    end process;

    -- port assignments
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

    busy         <= '1' when state = s_reload or state = s_config or state = s_advance else '0';
    done         <= r_done;
    block_done   <= r_block_done;
    timing_error <= r_timing_error;

end architecture;
