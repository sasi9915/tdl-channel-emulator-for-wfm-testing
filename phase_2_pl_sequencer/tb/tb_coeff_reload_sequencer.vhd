library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.env.all;

entity tb_coeff_reload_sequencer is
end entity;

architecture sim of tb_coeff_reload_sequencer is

    constant C_CLK_PERIOD : time    := 10 ns;
    constant C_TAP_COUNT  : integer := 32;
    constant C_SET_COUNT  : integer := 3;
    constant C_FU_PERIOD_CYCLES : integer := 100;
    constant C_FAULT_FU_PERIOD_CYCLES : integer := 10;
    constant C_TIMEOUT    : integer := 20000;

    signal aclk    : std_logic := '0';
    signal aresetn : std_logic := '0';
    signal start   : std_logic := '0';
    signal fu_tick : std_logic := '0';

    signal coeff_real_value : std_logic_vector(15 downto 0);
    signal coeff_imag_value : std_logic_vector(15 downto 0);
    signal coeff_set_index  : integer range 0 to C_SET_COUNT - 1;
    signal coeff_tap_index  : integer range 0 to C_TAP_COUNT - 1;

    signal real_reload_tvalid : std_logic;
    signal real_reload_tready : std_logic := '1';
    signal real_reload_tdata  : std_logic_vector(15 downto 0);
    signal real_reload_tlast  : std_logic;

    signal imag_reload_tvalid : std_logic;
    signal imag_reload_tready : std_logic := '1';
    signal imag_reload_tdata  : std_logic_vector(15 downto 0);
    signal imag_reload_tlast  : std_logic;

    signal real_config_tvalid : std_logic;
    signal real_config_tready : std_logic := '1';
    signal real_config_tdata  : std_logic_vector(7 downto 0);

    signal imag_config_tvalid : std_logic;
    signal imag_config_tready : std_logic := '1';
    signal imag_config_tdata  : std_logic_vector(7 downto 0);

    signal busy         : std_logic;
    signal done         : std_logic;
    signal block_done   : std_logic;
    signal timing_error : std_logic;
    signal state_debug  : std_logic_vector(2 downto 0);

    signal dbg_reload_accept      : std_logic                          := '0';
    signal dbg_config_accept      : std_logic                          := '0';
    signal dbg_accepted_set_index : integer range 0 to C_SET_COUNT - 1 := 0;
    signal dbg_accepted_tap_index : integer range 0 to C_TAP_COUNT - 1 := 0;

    signal lfsr_reg            : std_logic_vector(15 downto 0)                := x"BEEF";
    signal lfsr_feedback       : std_logic;
    signal reload_handshake    : std_logic;
    signal config_handshake    : std_logic;
    signal expected_tap_reg    : integer range 0 to C_TAP_COUNT - 1           := 0;
    signal expected_set_reg    : integer range 0 to C_SET_COUNT - 1           := 0;
    signal reload_count_reg    : integer range 0 to C_SET_COUNT * C_TAP_COUNT := 0;
    signal config_count_reg    : integer range 0 to C_SET_COUNT               := 0;
    signal done_count_reg      : integer range 0 to C_SET_COUNT               := 0;
    signal timeout_counter_reg : integer                                      := 0;

    function real_coeff(
        set_index : integer;
        tap_index : integer
    ) return integer is
    begin
        return (set_index + 1) * 100 + tap_index;
    end function;

    function imag_coeff(
        set_index : integer;
        tap_index : integer
    ) return integer is
    begin
        return -((set_index + 1) * 100 + tap_index);
    end function;

begin

    -- clock  process
    clk_process : process
    begin
        aclk <= '0';
        wait for C_CLK_PERIOD / 2;
        aclk <= '1';
        wait for C_CLK_PERIOD / 2;
    end process;

    coeff_real_value <= std_logic_vector(to_signed(real_coeff(coeff_set_index, coeff_tap_index), 16));
    coeff_imag_value <= std_logic_vector(to_signed(imag_coeff(coeff_set_index, coeff_tap_index), 16));

    lfsr_feedback <= lfsr_reg(15) xor lfsr_reg(13) xor lfsr_reg(12) xor lfsr_reg(10);

    reload_handshake <= real_reload_tvalid and imag_reload_tvalid and real_reload_tready and imag_reload_tready;

    config_handshake <= real_config_tvalid and imag_config_tvalid and real_config_tready and imag_config_tready;

    dut : entity work.coeff_reload_sequencer
        generic map(
            G_TAP_COUNT    => C_TAP_COUNT,
            G_SET_COUNT    => C_SET_COUNT,
            G_COEFF_WIDTH  => 16,
            G_CONFIG_WIDTH => 8
        )
        port map(
            aclk               => aclk,
            aresetn            => aresetn,
            start              => start,
            fu_tick            => fu_tick,
            coeff_real_value   => coeff_real_value,
            coeff_imag_value   => coeff_imag_value,
            coeff_set_index    => coeff_set_index,
            coeff_tap_index    => coeff_tap_index,
            real_reload_tvalid => real_reload_tvalid,
            real_reload_tready => real_reload_tready,
            real_reload_tdata  => real_reload_tdata,
            real_reload_tlast  => real_reload_tlast,
            imag_reload_tvalid => imag_reload_tvalid,
            imag_reload_tready => imag_reload_tready,
            imag_reload_tdata  => imag_reload_tdata,
            imag_reload_tlast  => imag_reload_tlast,
            real_config_tvalid => real_config_tvalid,
            real_config_tready => real_config_tready,
            real_config_tdata  => real_config_tdata,
            imag_config_tvalid => imag_config_tvalid,
            imag_config_tready => imag_config_tready,
            imag_config_tdata  => imag_config_tdata,
            busy               => busy,
            done               => done,
            block_done         => block_done,
            timing_error       => timing_error,
            state_debug        => state_debug
        );

    tready_driver : process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                real_reload_tready <= '1';
                imag_reload_tready <= '1';
                real_config_tready <= '1';
                imag_config_tready <= '1';
                lfsr_reg           <= x"BEEF";
            else
                lfsr_reg <= lfsr_reg(14 downto 0) & lfsr_feedback;

                if lfsr_reg(2 downto 0) = "000" then
                    real_reload_tready <= '0';
                    imag_reload_tready <= '0';
                else
                    real_reload_tready <= '1';
                    imag_reload_tready <= '1';
                end if;

                if lfsr_reg(5 downto 3) = "101" then
                    real_config_tready <= '0';
                    imag_config_tready <= '0';
                else
                    real_config_tready <= '1';
                    imag_config_tready <= '1';
                end if;
            end if;
        end if;
    end process;

    stimulus : process
        procedure wait_clock_cycles(
            constant number_of_cycles : integer
        ) is
        begin
            for index in 1 to number_of_cycles loop
                wait until rising_edge(aclk);
            end loop;
        end procedure;

        procedure send_fu_tick is
        begin
            fu_tick <= '1';
            wait until rising_edge(aclk);
            fu_tick <= '0';
        end procedure;
    begin
        aresetn <= '0';
        start   <= '0';
        fu_tick <= '0';
        wait_clock_cycles(10);

        aresetn <= '1';
        wait_clock_cycles(2);

        start <= '1';
        wait_clock_cycles(2);

        report "Starting normal fixed-FU-period reload test"
        severity note;

        for set_index in 0 to C_SET_COUNT - 1 loop
            send_fu_tick;
            wait_clock_cycles(C_FU_PERIOD_CYCLES - 1);

            assert timing_error = '0'
            report "Unexpected timing error before next FU tick"
            severity failure;
        end loop;

        if block_done /= '1' then
            wait until block_done = '1' or timing_error = '1';
        end if;

        wait_clock_cycles(5);

        assert timing_error = '0'
        report "Unexpected timing error after final FU tick"
        severity failure;

        assert block_done = '1'
        report "Block done was not asserted"
        severity failure;

        start <= '0';
        wait_clock_cycles(5);

        aresetn <= '0';
        fu_tick <= '0';
        wait_clock_cycles(5);

        aresetn <= '1';
        wait_clock_cycles(2);

        start <= '1';
        wait_clock_cycles(2);

        report "Starting early-FU timing-error test"
        severity note;

        send_fu_tick;
        wait_clock_cycles(C_FAULT_FU_PERIOD_CYCLES - 1);
        send_fu_tick;
        wait_clock_cycles(2);

        assert timing_error = '1'
        report "Timing error was not asserted when the next FU tick arrived too early"
        severity failure;

        assert block_done = '0'
        report "Block done asserted during timing-error test"
        severity failure;

        start <= '0';
        wait_clock_cycles(4);

        assert timing_error = '0'
        report "Timing error did not clear after returning to idle"
        severity failure;

        report "Coefficient reload sequencer tests completed"
        severity note;

        stop;
        wait;
    end process;

    checker : process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                expected_tap_reg    <= 0;
                expected_set_reg    <= 0;
                reload_count_reg    <= 0;
                config_count_reg    <= 0;
                done_count_reg      <= 0;
                timeout_counter_reg <= 0;
                dbg_reload_accept   <= '0';
                dbg_config_accept   <= '0';
            else
                dbg_reload_accept   <= '0';
                dbg_config_accept   <= '0';
                timeout_counter_reg <= timeout_counter_reg + 1;

                assert timeout_counter_reg < C_TIMEOUT
                report "Sequencer test timed out"
                severity failure;

                if reload_handshake = '1' then

                    assert to_integer(signed(real_reload_tdata)) = real_coeff(expected_set_reg, expected_tap_reg)
                    report "Unexpected real reload coefficient"
                    severity error;

                    assert to_integer(signed(imag_reload_tdata)) = imag_coeff(expected_set_reg, expected_tap_reg)
                    report "Unexpected imaginary reload coefficient"
                    severity error;

                    if expected_tap_reg = C_TAP_COUNT - 1 then
                        assert real_reload_tlast = '1' and imag_reload_tlast = '1'
                        report "Missing reload TLAST on final tap"
                        severity error;

                        report "Accepted final reload tap for set " & integer'image(expected_set_reg)
                        severity note;
                    else
                        assert real_reload_tlast = '0' and imag_reload_tlast = '0'
                        report "Unexpected reload TLAST before final tap"
                        severity error;
                    end if;

                    dbg_reload_accept      <= '1';
                    dbg_accepted_set_index <= expected_set_reg;
                    dbg_accepted_tap_index <= expected_tap_reg;
                    reload_count_reg       <= reload_count_reg + 1;

                    if expected_tap_reg = C_TAP_COUNT - 1 then
                        expected_tap_reg <= 0;
                    else
                        expected_tap_reg <= expected_tap_reg + 1;
                    end if;
                end if;

                if config_handshake = '1' then

                    assert expected_tap_reg = 0
                    report "CONFIG accepted before a complete reload set"
                    severity error;

                    assert real_config_tdata = x"00" and imag_config_tdata = x"00"
                    report "Unexpected CONFIG data"
                    severity error;

                    dbg_config_accept <= '1';
                    config_count_reg  <= config_count_reg + 1;

                    report "Accepted CONFIG number " & integer'image(config_count_reg + 1)
                    severity note;

                    if expected_set_reg /= C_SET_COUNT - 1 then
                        expected_set_reg <= expected_set_reg + 1;
                    end if;
                end if;

                if done = '1' then
                    done_count_reg <= done_count_reg + 1;
                end if;

                if block_done = '1' then
                    assert reload_count_reg = C_SET_COUNT * C_TAP_COUNT
                    report "Unexpected number of reload transfers"
                    severity error;

                    assert config_count_reg = C_SET_COUNT
                    report "Unexpected number of config transfers"
                    severity error;

                    assert done_count_reg = C_SET_COUNT or (done = '1' and done_count_reg = C_SET_COUNT - 1)
                    report "Unexpected number of done pulses"
                    severity error;
                end if;
            end if;
        end if;
    end process;

end architecture;
