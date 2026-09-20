library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.env.all;

entity tb_seq_fifo_usedw_reload_flow is
end entity;

architecture sim of tb_seq_fifo_usedw_reload_flow is

    constant C_CLK_PERIOD        : time    := 3333 ps;
    constant C_RELOAD_WORD_COUNT : integer := 32;
    constant C_SET_COUNT         : integer := 5;
    constant C_REFILL_THRESHOLD_SETS : integer := 2;
    constant C_TOTAL_WORDS       : integer := C_RELOAD_WORD_COUNT * C_SET_COUNT;
    constant C_FIFO_DEPTH        : integer := 256;
    constant C_FU_PERIOD_CYCLES  : integer := 20;
    constant C_TIMEOUT_CYCLES    : integer := 5000;

    signal aclk             : std_logic := '0';
    signal aresetn          : std_logic := '0';
    signal enable           : std_logic := '0';
    signal clear_status     : std_logic := '0';
    signal fu_period_cycles : unsigned(31 downto 0) := (others => '0');

    signal coeff_set_tvalid : std_logic := '0';
    signal coeff_set_tready : std_logic;
    signal coeff_set_tdata  : std_logic_vector(31 downto 0) := (others => '0');

    signal real_reload_tvalid : std_logic;
    signal real_reload_tready : std_logic := '0';
    signal real_reload_tdata  : std_logic_vector(15 downto 0);
    signal real_reload_tlast  : std_logic;
    signal imag_reload_tvalid : std_logic;
    signal imag_reload_tready : std_logic := '0';
    signal imag_reload_tdata  : std_logic_vector(15 downto 0);
    signal imag_reload_tlast  : std_logic;

    signal real_config_tvalid : std_logic;
    signal real_config_tready : std_logic := '0';
    signal real_config_tdata  : std_logic_vector(7 downto 0);
    signal imag_config_tvalid : std_logic;
    signal imag_config_tready : std_logic := '0';
    signal imag_config_tdata  : std_logic_vector(7 downto 0);

    signal reload_active       : std_logic;
    signal reload_set_done     : std_logic;
    signal reload_block_done   : std_logic;
    signal missed_refill       : std_logic;
    signal refill_request      : std_logic;
    signal refill_request_pulse : std_logic;
    signal reload_timing_error : std_logic;
    signal state_debug         : std_logic_vector(2 downto 0);

    signal dbg_fu_tick           : std_logic;
    signal dbg_next_state        : std_logic_vector(2 downto 0);
    signal dbg_reload_accept     : std_logic;
    signal dbg_config_accept     : std_logic;
    signal dbg_timing_fault      : std_logic;
    signal dbg_reload_word_index : std_logic_vector(15 downto 0);
    signal dbg_reload_set_index  : std_logic_vector(15 downto 0);
    signal dbg_seq_fifo_usedw    : std_logic_vector(15 downto 0);
    signal dbg_seq_fifo_has_set  : std_logic;
    signal dbg_seq_input_ready   : std_logic;

    impure function usedw return integer is
    begin
        return to_integer(unsigned(dbg_seq_fifo_usedw));
    end function;

    function pack_word(
        constant set_index  : integer;
        constant word_index : integer
    ) return std_logic_vector is
        variable packed : std_logic_vector(31 downto 0);
    begin
        packed(31 downto 16) := std_logic_vector(to_signed((set_index * 100) + word_index, 16));
        packed(15 downto 0)  := std_logic_vector(to_signed(-((set_index * 100) + word_index), 16));
        return packed;
    end function;

begin

    aclk <= not aclk after C_CLK_PERIOD / 2;

    dut : entity work.coeff_reload_sequencer
        generic map(
            G_RELOAD_WORD_COUNT => C_RELOAD_WORD_COUNT,
            G_MAX_SET_COUNT     => 600,
            G_COEFF_WIDTH       => 16,
            G_CONFIG_WIDTH      => 8,
            G_FIFO_DEPTH        => C_FIFO_DEPTH
        )
        port map(
            aclk                    => aclk,
            aresetn                 => aresetn,
            enable                  => enable,
            clear_status            => clear_status,
            fu_period_cycles        => fu_period_cycles,
            block_set_count         => C_SET_COUNT,
            refill_threshold_sets   => C_REFILL_THRESHOLD_SETS,
            coeff_set_tvalid        => coeff_set_tvalid,
            coeff_set_tready        => coeff_set_tready,
            coeff_set_tdata         => coeff_set_tdata,
            real_reload_tvalid      => real_reload_tvalid,
            real_reload_tready      => real_reload_tready,
            real_reload_tdata       => real_reload_tdata,
            real_reload_tlast       => real_reload_tlast,
            imag_reload_tvalid      => imag_reload_tvalid,
            imag_reload_tready      => imag_reload_tready,
            imag_reload_tdata       => imag_reload_tdata,
            imag_reload_tlast       => imag_reload_tlast,
            real_config_tvalid      => real_config_tvalid,
            real_config_tready      => real_config_tready,
            real_config_tdata       => real_config_tdata,
            imag_config_tvalid      => imag_config_tvalid,
            imag_config_tready      => imag_config_tready,
            imag_config_tdata       => imag_config_tdata,
            reload_active           => reload_active,
            reload_set_done         => reload_set_done,
            reload_block_done       => reload_block_done,
            missed_refill           => missed_refill,
            refill_request          => refill_request,
            refill_request_pulse    => refill_request_pulse,
            reload_timing_error     => reload_timing_error,
            dbg_fu_tick_o           => dbg_fu_tick,
            dbg_next_state_o        => dbg_next_state,
            dbg_reload_accept_o     => dbg_reload_accept,
            dbg_config_accept_o     => dbg_config_accept,
            dbg_timing_fault_o      => dbg_timing_fault,
            dbg_reload_word_index_o => dbg_reload_word_index,
            dbg_reload_set_index_o  => dbg_reload_set_index,
            dbg_seq_fifo_usedw_o    => dbg_seq_fifo_usedw,
            dbg_seq_fifo_has_set_o  => dbg_seq_fifo_has_set,
            dbg_seq_input_ready_o   => dbg_seq_input_ready,
            state_debug             => state_debug
        );

    stimulus : process
        procedure wait_clocks(constant count : integer) is
        begin
            for index in 1 to count loop
                wait until rising_edge(aclk);
            end loop;
        end procedure;

        procedure push_word(
            constant set_index  : integer;
            constant word_index : integer
        ) is
        begin
            coeff_set_tdata  <= pack_word(set_index, word_index);
            coeff_set_tvalid <= '1';

            loop
                wait until rising_edge(aclk);
                exit when coeff_set_tready = '1';
            end loop;

            coeff_set_tvalid <= '0';
        end procedure;

        procedure wait_for_set_done(
            constant expected_usedw : integer;
            constant message_prefix : string
        ) is
            variable timeout : integer := 0;
        begin
            loop
                wait until rising_edge(aclk);
                exit when reload_set_done = '1';
                timeout := timeout + 1;

                assert timeout < C_TIMEOUT_CYCLES
                report message_prefix & ": timeout waiting for reload_set_done"
                severity failure;
            end loop;

            report message_prefix & ": usedw=" & integer'image(usedw) &
                   ", state=" & integer'image(to_integer(unsigned(state_debug))) &
                   ", word_index=" & integer'image(to_integer(unsigned(dbg_reload_word_index))) &
                   ", set_index=" & integer'image(to_integer(unsigned(dbg_reload_set_index)))
            severity note;

            assert usedw = expected_usedw
            report message_prefix & ": expected usedw=" & integer'image(expected_usedw) &
                   ", actual usedw=" & integer'image(usedw)
            severity failure;

            if expected_usedw = 0 then
                assert reload_block_done = '1'
                report "Fifth set did not pulse reload_block_done"
                severity failure;
            end if;
        end procedure;

        procedure set_reload_ready(constant ready_value : std_logic) is
        begin
            real_reload_tready <= ready_value;
            imag_reload_tready <= ready_value;
        end procedure;

        procedure set_config_ready(constant ready_value : std_logic) is
        begin
            real_config_tready <= ready_value;
            imag_config_tready <= ready_value;
        end procedure;

        procedure check_reload_ready_low_holds_fifo(
            constant message_prefix : string
        ) is
            variable start_usedw : integer;
        begin
            set_reload_ready('0');

            loop
                wait until rising_edge(aclk);
                exit when real_reload_tvalid = '1' and imag_reload_tvalid = '1';
            end loop;

            wait until rising_edge(aclk);
            start_usedw := usedw;

            for cycle_index in 1 to 12 loop
                wait until rising_edge(aclk);

                assert dbg_reload_accept = '0'
                report message_prefix & ": reload accepted while reload ready was forced low"
                severity failure;

                assert usedw = start_usedw
                report message_prefix & ": FIFO usedw changed while reload ready was forced low. start=" &
                       integer'image(start_usedw) & ", actual=" & integer'image(usedw)
                severity failure;
            end loop;

            report message_prefix & ": ready-low pause held usedw at " & integer'image(start_usedw)
            severity note;
            set_reload_ready('1');
        end procedure;

    begin
        aresetn              <= '0';
        enable               <= '0';
        clear_status         <= '0';
        set_reload_ready('0');
        set_config_ready('0');
        fu_period_cycles     <= (others => '0');
        coeff_set_tvalid     <= '0';
        coeff_set_tdata      <= (others => '0');
        wait_clocks(20);

        aresetn <= '1';
        wait_clocks(5);

        enable <= '1';
        wait_clocks(2);

        report "Loading 5 x 32 coefficient words into sequencer FIFO while Fu tick is disabled"
        severity note;

        for set_index in 0 to C_SET_COUNT - 1 loop
            for word_index in 0 to C_RELOAD_WORD_COUNT - 1 loop
                push_word(set_index, word_index);
            end loop;
        end loop;

        wait_clocks(4);
        report "After load: usedw=" & integer'image(usedw)
        severity note;

        assert usedw = C_TOTAL_WORDS
        report "Expected 160 staged words before Fu ticks begin"
        severity failure;

        fu_period_cycles <= to_unsigned(C_FU_PERIOD_CYCLES, fu_period_cycles'length);

        report "Fu ticks enabled while FIR reload/config ready are held low"
        severity note;

        wait until rising_edge(aclk) and dbg_fu_tick = '1';
        wait_clocks(8);

        report "Ready low window: usedw=" & integer'image(usedw) &
               ", reload_valid=" & std_logic'image(real_reload_tvalid and imag_reload_tvalid) &
               ", reload_ready=" & std_logic'image(real_reload_tready and imag_reload_tready) &
               ", state=" & integer'image(to_integer(unsigned(state_debug)))
        severity note;

        assert usedw = C_TOTAL_WORDS - 1
        report "With reload ready low, FIFO should only drop by the one internally staged word"
        severity failure;

        wait_clocks(3 * C_FU_PERIOD_CYCLES);

        assert usedw = C_TOTAL_WORDS - 1
        report "FIFO usedw kept dropping even though downstream reload ready stayed low"
        severity failure;

        assert reload_timing_error = '0'
        report "reload_timing_error asserted even though timing-fault protection is disabled"
        severity failure;

        report "Enabling modeled IQ stream and toggling FIR reload ready during the reload flow"
        severity note;

        set_config_ready('1');
        set_reload_ready('1');

        check_reload_ready_low_holds_fifo("set0 backpressure check");

        wait_for_set_done(128, "set0 complete");
        assert refill_request = '0'
        report "refill_request asserted too early after set0"
        severity failure;

        check_reload_ready_low_holds_fifo("set1 backpressure check");
        wait_for_set_done(96, "set1 complete");
        assert refill_request = '0'
        report "refill_request asserted too early after set1"
        severity failure;

        check_reload_ready_low_holds_fifo("set2 backpressure check");
        wait_for_set_done(64, "set2 complete");
        wait for 0 ns;
        assert refill_request = '1'
        report "refill_request did not assert when two sets remained"
        severity failure;

        assert refill_request_pulse = '1'
        report "refill_request_pulse did not pulse when two sets remained"
        severity failure;

        wait_clocks(1);
        assert refill_request_pulse = '0'
        report "refill_request_pulse stayed high for more than one clock"
        severity failure;

        check_reload_ready_low_holds_fifo("set3 backpressure check");
        wait_for_set_done(32, "set3 complete");
        check_reload_ready_low_holds_fifo("set4 backpressure check");
        wait_for_set_done(0, "set4 complete");

        assert reload_timing_error = '0'
        report "reload_timing_error asserted during successful 5-set reload flow"
        severity failure;

        report "PASS: usedw only drains with downstream reload handshakes and drops by 32 words per set"
        severity note;

        stop;
    end process;

end architecture;
