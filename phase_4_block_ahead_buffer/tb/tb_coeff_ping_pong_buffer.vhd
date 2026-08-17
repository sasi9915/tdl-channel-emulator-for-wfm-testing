library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.env.all;
use std.textio.all;

entity tb_coeff_ping_pong_buffer is
    generic(
        C_TAP_COUNT         : positive := 128;
        C_MAX_SETS_PER_BANK : positive := 600;
        C_SETS_PER_BANK     : positive := 8;
        C_COEFF_WIDTH       : positive := 16;
        C_RAM_STYLE         : string   := "ultra";
        C_OUTPUT_FILE       : string   := "phase_4_ping_pong_buffer_output.csv"
    );
end entity;

architecture sim of tb_coeff_ping_pong_buffer is

    constant C_CLK_PERIOD : time := 3.333 ns;
    signal aclk         : std_logic := '0';
    signal aresetn      : std_logic := '0';
    signal clear_errors : std_logic := '0';

    signal wr_valid : std_logic                                          := '0';
    signal wr_ready : std_logic;
    signal wr_data  : std_logic_vector((2 * C_COEFF_WIDTH) - 1 downto 0) := (others => '0');
    signal wr_last  : std_logic                                          := '0';

    signal rd_en             : std_logic := '0';
    signal rd_tap_index      : integer range 0 to C_TAP_COUNT - 1 := 0;
    signal rd_data           : std_logic_vector((2 * C_COEFF_WIDTH) - 1 downto 0);
    signal rd_valid          : std_logic;
    signal consume_set_valid : std_logic := '0';
    signal consume_set_ready : std_logic;

    signal active_set_available : std_logic;
    signal underrun             : std_logic;
    signal write_error          : std_logic;

    function coeff_real(
        bank_index : integer;
        set_index  : integer;
        tap_index  : integer
    ) return integer is
    begin
        return (bank_index * 1024) + ((set_index mod 16) * C_TAP_COUNT) + tap_index;
    end function;

    function coeff_imag(
        bank_index : integer;
        set_index  : integer;
        tap_index  : integer
    ) return integer is
    begin
        return -coeff_real(bank_index, set_index, tap_index);
    end function;

    function packed_coeff(
        bank_index : integer;
        set_index  : integer;
        tap_index  : integer
    ) return std_logic_vector is
    begin
        return std_logic_vector(to_signed(coeff_imag(bank_index, set_index, tap_index), C_COEFF_WIDTH)) & std_logic_vector(to_signed(coeff_real(bank_index, set_index, tap_index), C_COEFF_WIDTH));
    end function;

begin

    clk_process : process
    begin
        aclk <= '0';
        wait for C_CLK_PERIOD / 2;
        aclk <= '1';
        wait for C_CLK_PERIOD / 2;
    end process;

    dut : entity work.coeff_ping_pong_buffer
        generic map(
            G_TAP_COUNT         => C_TAP_COUNT,
            G_MAX_SETS_PER_BANK => C_MAX_SETS_PER_BANK,
            G_COEFF_WIDTH       => C_COEFF_WIDTH,
            G_RAM_STYLE         => C_RAM_STYLE
        )
        port map(
            aclk                 => aclk,
            aresetn              => aresetn,
            clear_errors         => clear_errors,
            cfg_sets_per_bank    => C_SETS_PER_BANK,
            wr_valid             => wr_valid,
            wr_ready             => wr_ready,
            wr_data              => wr_data,
            wr_last              => wr_last,
            rd_en                => rd_en,
            rd_tap_index         => rd_tap_index,
            rd_data              => rd_data,
            rd_valid             => rd_valid,
            consume_set_valid    => consume_set_valid,
            consume_set_ready    => consume_set_ready,
            active_set_available => active_set_available,
            underrun             => underrun,
            write_error          => write_error
        );

    stimulus : process
        file output_log : text open write_mode is C_OUTPUT_FILE;

        -- wait for a specified number of clock cycles
        procedure wait_clock_cycles(
            constant number_of_cycles : integer
        ) is
        begin
            for index in 1 to number_of_cycles loop
                wait until rising_edge(aclk);
            end loop;
        end procedure;

        procedure log_header is
            variable log_line : line;
        begin
            write(log_line, string'("time_ns,event,bank,set,tap,real,imag,wr_valid,wr_ready,wr_last,rd_en,rd_valid,active_set_available,consume_set_ready,underrun,write_error"));
            writeline(output_log, log_line);
        end procedure;

        function sl_to_character(
            constant sl_value : std_logic
        ) return character is
        begin
            if sl_value = '1' then
                return '1';
            elsif sl_value = '0' then
                return '0';
            else
                return 'X';
            end if;
        end function;

        procedure log_event(
            constant event_name : string;
            constant bank_index : integer;
            constant set_index  : integer;
            constant tap_index  : integer;
            constant real_value : integer;
            constant imag_value : integer
        ) is
            variable log_line : line;
        begin
            write(log_line, now / 1 ns);
            write(log_line, string'(","));
            write(log_line, event_name);
            write(log_line, string'(","));
            write(log_line, bank_index);
            write(log_line, string'(","));
            write(log_line, set_index);
            write(log_line, string'(","));
            write(log_line, tap_index);
            write(log_line, string'(","));
            write(log_line, real_value);
            write(log_line, string'(","));
            write(log_line, imag_value);
            write(log_line, string'(","));
            write(log_line, sl_to_character(wr_valid));
            write(log_line, string'(","));
            write(log_line, sl_to_character(wr_ready));
            write(log_line, string'(","));
            write(log_line, sl_to_character(wr_last));
            write(log_line, string'(","));
            write(log_line, sl_to_character(rd_en));
            write(log_line, string'(","));
            write(log_line, sl_to_character(rd_valid));
            write(log_line, string'(","));
            write(log_line, sl_to_character(active_set_available));
            write(log_line, string'(","));
            write(log_line, sl_to_character(consume_set_ready));
            write(log_line, string'(","));
            write(log_line, sl_to_character(underrun));
            write(log_line, string'(","));
            write(log_line, sl_to_character(write_error));
            writeline(output_log, log_line);
        end procedure;


        -- assert clear_errors for one clock cycle to clear any error flags
        procedure clear_error_flags is
        begin
            clear_errors <= '1';
            wait until rising_edge(aclk);
            log_event("clear_errors_asserted", -1, -1, -1, 0, 0);
            wait until rising_edge(aclk);
            clear_errors <= '0';
            wait until rising_edge(aclk);
            log_event("clear_errors_released", -1, -1, -1, 0, 0);
        end procedure;


        -- write a full bank of coefficients to the ping-pong buffer, asserting TLAST on the final beat
        procedure write_bank_block(
            constant bank_index : integer
        ) is
        begin
            for set_index in 0 to C_SETS_PER_BANK - 1 loop
                for tap_index in 0 to C_TAP_COUNT - 1 loop
                    wr_data <= packed_coeff(bank_index, set_index, tap_index);

                    if set_index = C_SETS_PER_BANK - 1 and tap_index = C_TAP_COUNT - 1 then
                        wr_last <= '1';
                    else
                        wr_last <= '0';
                    end if;

                    wr_valid <= '1';
                    wait until rising_edge(aclk);

                    assert wr_ready = '1'
                    report "Coefficient writer was not ready during a normal bank fill"
                    severity failure;

                    log_event("write_accept", bank_index, set_index, tap_index, coeff_real(bank_index, set_index, tap_index), coeff_imag(bank_index, set_index, tap_index));
                end loop;
            end loop;

            wr_valid <= '0';
            wr_last  <= '0';
            wr_data  <= (others => '0');
            wait until rising_edge(aclk);
        end procedure;

        -- write a full bank of coefficients to the ping-pong buffer, but do not assert TLAST on the final beat
        procedure write_bank_block_missing_final_last(
            constant bank_index : integer
        ) is
        begin
            for set_index in 0 to C_SETS_PER_BANK - 1 loop
                for tap_index in 0 to C_TAP_COUNT - 1 loop
                    wr_data  <= packed_coeff(bank_index, set_index, tap_index);
                    wr_last  <= '0';
                    wr_valid <= '1';
                    wait until rising_edge(aclk);

                    assert wr_ready = '1'
                    report "Coefficient writer was not ready during missing-final-TLAST test"
                    severity failure;

                    log_event("write_accept_missing_final_tlast", bank_index, set_index, tap_index, coeff_real(bank_index, set_index, tap_index), coeff_imag(bank_index, set_index, tap_index));
                end loop;
            end loop;

            wr_valid <= '0';
            wr_last  <= '0';
            wr_data  <= (others => '0');
            wait until rising_edge(aclk);
        end procedure;

        -- write a single coefficient to the ping-pong buffer, asserting TLAST on the first beat of a new bank
        procedure write_one_early_last_beat is
        begin
            wr_data  <= std_logic_vector(to_signed(-77, C_COEFF_WIDTH)) & std_logic_vector(to_signed(77, C_COEFF_WIDTH));
            wr_last  <= '1';
            wr_valid <= '1';
            wait until rising_edge(aclk);
            log_event("write_accept_early_tlast", -1, -1, -1, 77, -77);
            wr_valid <= '0';
            wr_last  <= '0';
            wait until rising_edge(aclk);
        end procedure;


        -- read a coefficient from the ping-pong buffer and check that it matches the expected value
        procedure check_coefficient(
            constant bank_index : integer;
            constant set_index  : integer;
            constant tap_index  : integer
        ) is
        begin
            rd_tap_index <= tap_index;
            rd_en        <= '1';
            wait until rising_edge(aclk);
            rd_en <= '0';

            for timeout_count in 0 to 8 loop
                wait for 1 ns;

                if rd_valid = '1' then
                    exit;
                end if;

                wait until rising_edge(aclk);
            end loop;

            assert rd_valid = '1'
            report "Coefficient memory read did not become valid"
            severity failure;

            assert rd_data = packed_coeff(bank_index, set_index, tap_index)
            report "Unexpected packed coefficient read from active bank"
            severity failure;

            log_event("read_check", bank_index, set_index, tap_index, coeff_real(bank_index, set_index, tap_index), coeff_imag(bank_index, set_index, tap_index));
        end procedure;

        -- consume a single set from the ping-pong buffer, asserting consume_set_valid for one clock cycle
        procedure consume_one_set(
            constant set_index : integer
        ) is
        begin
            assert consume_set_ready = '1'
            report "Testbench attempted to consume when no active set was available"
            severity failure;

            consume_set_valid <= '1';
            wait until rising_edge(aclk);
            log_event("consume_set_accept", -1, set_index, -1, 0, 0);
            consume_set_valid <= '0';
            wait until rising_edge(aclk);
        end procedure;

    begin
        log_header;
        wait for 0 ns;
        log_event("test_start", -1, -1, -1, 0, 0);
        report "Ping-pong buffer TB configuration: taps="
               & integer'image(C_TAP_COUNT)
               & ", max_sets_per_bank="
               & integer'image(C_MAX_SETS_PER_BANK)
               & ", active_test_sets="
               & integer'image(C_SETS_PER_BANK)
               & ", ram_style="
               & C_RAM_STYLE
        severity note;

        aresetn <= '0';

        -- reset must block the writer; no coefficient beat is accepted while reset is active
        report "Checking write ready is blocked during reset"
        severity note;

        wr_valid <= '1';
        wr_data  <= std_logic_vector(to_signed(-11, C_COEFF_WIDTH)) & std_logic_vector(to_signed(11, C_COEFF_WIDTH));
        wait for 1 ns;

        assert wr_ready = '0'
        report "wr_ready was high while reset was asserted"
        severity failure;

        log_event("reset_write_blocked", -1, -1, -1, 11, -11);

        wait_clock_cycles(10);
        wr_valid <= '0';
        wr_data  <= (others => '0');
        aresetn  <= '1';
        wait_clock_cycles(2);

        -- initial empty state is not an underrun; the buffer simply keeps consume_set_ready low
        report "Checking held consume valid while initially not ready"
        severity note;

        consume_set_valid <= '1';
        wait until rising_edge(aclk);
        wait until rising_edge(aclk);

        assert underrun = '0' and consume_set_ready = '0'
        report "Held consume valid while initially not ready caused a false underrun"
        severity failure;

        log_event("initial_empty_consume_blocked", -1, -1, -1, 0, 0);

        consume_set_valid <= '0';
        wait until rising_edge(aclk);

        -- wr_last before a full bank is complete must reject the partial write block
        report "Checking early TLAST write-format rejection"
        severity note;

        write_one_early_last_beat;

        assert write_error = '1' and active_set_available = '0'
        report "Early TLAST did not reject the partial coefficient block"
        severity failure;

        log_event("early_tlast_rejected", -1, -1, -1, 0, 0);

        clear_error_flags;

        assert write_error = '0'
        report "Early TLAST recovery did not clear the write error"
        severity failure;

        -- clear_errors must block writes so the writer cannot see a false valid-ready handshake
        report "Checking write ready is blocked during clear_errors"
        severity note;

        wr_valid     <= '1';
        wr_data      <= std_logic_vector(to_signed(-55, C_COEFF_WIDTH)) & std_logic_vector(to_signed(55, C_COEFF_WIDTH));
        clear_errors <= '1';
        wait for 1 ns;

        assert wr_ready = '0'
        report "wr_ready was high while clear_errors was asserted"
        severity failure;

        log_event("clear_errors_write_blocked", -1, -1, -1, 55, -55);

        wait until rising_edge(aclk);
        wr_valid     <= '0';
        clear_errors <= '0';
        wait until rising_edge(aclk);

        assert write_error = '0'
        report "Write clear recovery left an unexpected error"
        severity failure;

        -- a full bank without final wr_last is malformed and must not become readable
        report "Checking missing final TLAST write-format rejection"
        severity note;

        write_bank_block_missing_final_last(0);

        assert write_error = '1' and active_set_available = '0'
        report "Missing final TLAST incorrectly allowed a bank to become ready"
        severity failure;

        log_event("missing_final_tlast_rejected", -1, -1, -1, 0, 0);

        clear_error_flags;

        assert write_error = '0'
        report "Missing final TLAST recovery did not clear the write error"
        severity failure;

        -- first complete bank becomes the active readable bank for the sequencer side
        report "Filling initial active bank"
        severity note;

        write_bank_block(0);

        assert active_set_available = '1' and consume_set_ready = '1'
        report "Initial bank did not become the active readable bank"
        severity failure;

        log_event("initial_bank_ready", 0, 0, -1, 0, 0);

        check_coefficient(0, 0, 0);
        check_coefficient(0, 0, 7);
        check_coefficient(0, 0, 31);

        -- clear_errors must also block the consume handshake while leaving the loaded bank protected
        report "Checking consume ready is blocked during clear_errors"
        severity note;

        clear_errors <= '1';
        wait for 1 ns;

        assert consume_set_ready = '0'
        report "consume_set_ready was high while clear_errors was asserted"
        severity failure;

        log_event("clear_errors_consume_blocked", -1, -1, -1, 0, 0);

        wait until rising_edge(aclk);
        clear_errors <= '0';
        wait until rising_edge(aclk);

        -- second complete bank is written in the background while bank 0 remains the active read bank
        report "Filling inactive bank while active bank remains readable"
        severity note;

        write_bank_block(1);

        assert active_set_available = '1' and consume_set_ready = '1'
        report "Inactive bank was not filled while active bank remained protected"
        severity failure;

        log_event("inactive_bank_filled", 1, 0, -1, 0, 0);

        check_coefficient(0, 0, 5);

        -- when both banks are full, extra writes must be backpressured without setting write_error
        report "Checking ready-bank write blocking without false protocol error"
        severity note;

        wr_valid <= '1';
        wr_data  <= std_logic_vector(to_signed(-1234, C_COEFF_WIDTH)) & std_logic_vector(to_signed(1234, C_COEFF_WIDTH));
        wr_last  <= '0';
        wait until rising_edge(aclk);
        wait until rising_edge(aclk);
        wr_valid <= '0';
        wait until rising_edge(aclk);

        assert wr_ready = '0' and write_error = '0'
        report "Ready-bank write blocking caused an unexpected protocol error"
        severity failure;

        log_event("ready_bank_write_blocked", -1, -1, -1, 1234, -1234);

        check_coefficient(0, 0, 5);

        -- after all sets from bank 0 are consumed, the buffer must swap atomically to ready bank 1
        report "Consuming active bank and checking atomic swap"
        severity note;

        for set_index in 0 to C_SETS_PER_BANK - 1 loop
            check_coefficient(0, set_index, 0);
            check_coefficient(0, set_index, 31);
            consume_one_set(set_index);
        end loop;

        assert active_set_available = '1' and consume_set_ready = '1'
        report "Active bank did not swap after all active sets were consumed"
        severity failure;

        log_event("bank_swapped_to_next_ready_bank", 1, 0, -1, 0, 0);

        check_coefficient(1, 0, 0);
        check_coefficient(1, 0, 11);
        check_coefficient(1, 0, 31);

        -- if the active bank is exhausted and no replacement bank is ready, underrun must assert
        report "Checking underrun when next inactive bank is not ready"
        severity note;

        for set_index in 0 to C_SETS_PER_BANK - 1 loop
            check_coefficient(1, set_index, 0);
            check_coefficient(1, set_index, 31);
            consume_one_set(set_index);
        end loop;

        assert underrun = '1' and active_set_available = '0' and consume_set_ready = '0'
        report "Underrun did not assert when active bank was exhausted without a ready next bank"
        severity failure;

        log_event("underrun_asserted", -1, -1, -1, 0, 0);

        assert rd_data = std_logic_vector(to_unsigned(0, 2 * C_COEFF_WIDTH))
        report "Exhausted active bank remained readable after underrun"
        severity failure;

        log_event("exhausted_read_zeroed", -1, -1, -1, 0, 0);

        clear_errors <= '1';
        wait until rising_edge(aclk);
        clear_errors <= '0';
        wait until rising_edge(aclk);

        -- consume valid may wait while not ready; the buffer should keep the current underrun state
        consume_set_valid <= '1';
        wait until rising_edge(aclk);
        wait until rising_edge(aclk);

        assert underrun = '1' and consume_set_ready = '0'
        report "Held consume valid while exhausted changed the current underrun state incorrectly"
        severity failure;

        log_event("exhausted_consume_waiting", -1, -1, -1, 0, 0);

        consume_set_valid <= '0';
        wait until rising_edge(aclk);

        -- once a new bank is filled after underrun, the buffer recovers automatically and becomes readable
        report "Checking recovery after inactive bank becomes ready after underrun"
        severity note;

        write_bank_block(2);
        wait until rising_edge(aclk);

        assert underrun = '0' and active_set_available = '1' and consume_set_ready = '1'
        report "Buffer did not automatically recover and swap after underrun when the next bank became ready"
        severity failure;

        log_event("underrun_recovered", 2, 0, -1, 0, 0);

        check_coefficient(2, 0, 0);
        check_coefficient(2, 0, 31);

        -- all standalone ping-pong buffer checks completed
        report "Coefficient ping-pong buffer test completed"
        severity note;

        log_event("test_completed", -1, -1, -1, 0, 0);

        wait_clock_cycles(100);
        stop;
        wait;
    end process;

end architecture;
