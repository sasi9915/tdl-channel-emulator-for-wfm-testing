library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity tb_complex_channel_emulator is
end entity;

architecture rtl of tb_complex_channel_emulator is

    constant C_TAP_COUNT : integer := 32;
    constant C_RELOAD_SET_COUNT : integer := 3;
    constant C_AXIS_CLK_HZ : integer := 100_000_000;
    constant C_FU_HZ : integer := 6_000;
    constant C_CLK_PERIOD : time := 10 ns;
    constant C_PHASE3_FU_PERIOD_CYCLES : integer := (C_AXIS_CLK_HZ + C_FU_HZ / 2) / C_FU_HZ;
    constant C_RELOAD_START_SAMPLE : integer := 4;
    constant C_ACTIVE_PACKET_LENGTH : integer :=
        C_RELOAD_START_SAMPLE +
        (C_RELOAD_SET_COUNT - 1) * C_PHASE3_FU_PERIOD_CYCLES +
        C_TAP_COUNT +
        256;
    constant C_VERIFY_PACKET_LENGTH : integer := 25;
    constant C_INPUT_READY_TIMEOUT_CYCLES : integer := 1024;
    constant C_ACTIVE_TEST_TIMEOUT_CYCLES : integer :=
        C_ACTIVE_PACKET_LENGTH +
        C_RELOAD_SET_COUNT * C_PHASE3_FU_PERIOD_CYCLES +
        4096;
    constant C_OUTPUT_PACKET_TIMEOUT_CYCLES : integer :=
        C_ACTIVE_PACKET_LENGTH * 8 +
        4096;
    constant C_BACKPRESSURE_SEED : std_logic_vector(15 downto 0) := x"ACE1";

    type t_coefficient_array is array (0 to C_TAP_COUNT - 1) of integer;
    type t_reload_order_array is array (0 to C_TAP_COUNT - 1) of integer range 0 to C_TAP_COUNT - 1;

    -- Replace this with the actual reload order displayed by the FIR Compiler
    -- coefficient reload tab if Vivado reports a different order.
    constant C_RELOAD_ORDER : t_reload_order_array := (
        0, 1, 2, 3, 4, 5, 6, 7,
        8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23,
        24, 25, 26, 27, 28, 29, 30, 31
    );

    function reload_real_coefficient (
        set_index : integer;
        coefficient_index : integer
    ) return integer is
    begin
        case set_index is
            when 0 =>
                case coefficient_index is
                    when 0 => return 3;
                    when 1 => return 4;
                    when 2 => return 5;
                    when others => return 0;
                end case;

            when 1 =>
                case coefficient_index is
                    when 0 => return 1;
                    when 1 => return 2;
                    when 2 => return 3;
                    when others => return 0;
                end case;

            when 2 =>
                case coefficient_index is
                    when 0 => return 5;
                    when 1 => return 1;
                    when 2 => return -2;
                    when others => return 0;
                end case;

            when others =>
                return 0;
        end case;
    end function;

    function reload_imag_coefficient (
        set_index : integer;
        coefficient_index : integer
    ) return integer is
    begin
        case set_index is
            when 0 =>
                case coefficient_index is
                    when 1 => return -2;
                    when 2 => return -3;
                    when others => return 0;
                end case;

            when 1 =>
                case coefficient_index is
                    when 0 => return 1;
                    when 2 => return -1;
                    when others => return 0;
                end case;

            when 2 =>
                case coefficient_index is
                    when 1 => return 2;
                    when 2 => return -2;
                    when others => return 0;
                end case;

            when others =>
                return 0;
        end case;
    end function;

    signal aclk                    : std_logic := '0';
    signal aresetn                 : std_logic := '0';

    signal s_axis_tvalid           : std_logic := '0';
    signal s_axis_tready           : std_logic ;
    signal s_axis_tdata            : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axis_tlast            : std_logic := '0';

    signal m_axis_tvalid           : std_logic;
    signal m_axis_tready           : std_logic := '1';
    signal m_axis_tdata            : std_logic_vector(79 downto 0);
    signal m_axis_tlast            : std_logic;

    signal real_reload_tvalid      : std_logic := '0';
    signal real_reload_tready      : std_logic;
    signal real_reload_tdata       : std_logic_vector(15 downto 0) := (others => '0');
    signal real_reload_tlast       : std_logic := '0';

    signal real_config_tvalid      : std_logic := '0';
    signal real_config_tready      : std_logic;
    signal real_config_tdata       : std_logic_vector(7 downto 0) := (others => '0');

    signal imag_reload_tvalid      : std_logic := '0';
    signal imag_reload_tready      : std_logic;
    signal imag_reload_tdata       : std_logic_vector(15 downto 0) := (others => '0');
    signal imag_reload_tlast       : std_logic := '0';

    signal imag_config_tvalid      : std_logic := '0';
    signal imag_config_tready      : std_logic;
    signal imag_config_tdata       : std_logic_vector(7 downto 0) := (others => '0');

    signal sequencer_start         : std_logic := '0';
    signal sequencer_fu_tick       : std_logic := '0';
    signal sequencer_coeff_real    : std_logic_vector(15 downto 0);
    signal sequencer_coeff_imag    : std_logic_vector(15 downto 0);
    signal sequencer_set_index     : integer range 0 to C_RELOAD_SET_COUNT - 1;
    signal sequencer_tap_index     : integer range 0 to C_TAP_COUNT - 1;
    signal sequencer_busy          : std_logic;
    signal sequencer_done          : std_logic;
    signal sequencer_block_done    : std_logic;
    signal sequencer_timing_error  : std_logic;
    signal sequencer_state_debug   : std_logic_vector(2 downto 0);

    signal reload_handshake        : std_logic;
    signal config_handshake        : std_logic;

    signal dbg_reload_accept       : std_logic := '0';
    signal dbg_reload_set_index    : integer range 0 to C_RELOAD_SET_COUNT - 1 := 0;
    signal dbg_reload_slot         : integer range 0 to C_TAP_COUNT - 1 := 0;
    signal dbg_reload_real_word    : std_logic_vector(15 downto 0) := (others => '0');
    signal dbg_reload_imag_word    : std_logic_vector(15 downto 0) := (others => '0');
    signal dbg_config_accept       : std_logic := '0';
    signal dbg_config_set_index    : integer range 0 to C_RELOAD_SET_COUNT - 1 := 0;
    signal dbg_input_accept        : std_logic := '0';
    signal dbg_real_config_accept  : std_logic := '0';
    signal dbg_imag_config_accept  : std_logic := '0';
    signal dbg_config_during_input_accept : std_logic := '0';
    signal dbg_output_backpressure : std_logic := '0';

    signal verification_packet_active : std_logic := '0';
    signal current_packet_length : integer := C_ACTIVE_PACKET_LENGTH;
    signal output_backpressure_enable : std_logic := '0';

    file output_file : text open write_mode is
    "/home/sasindu/work/TDL_chnannel_emulator_project/tdl-channel-emulator-for-wfm-testing/phase_3_adding_sequencer_2_path_1/misc/phase_3_complex_channel_output.csv";

begin

    aclk <= not aclk after C_CLK_PERIOD / 2;

    sequencer_coeff_real <= std_logic_vector(
        to_signed(
            reload_real_coefficient(
                sequencer_set_index,
                C_RELOAD_ORDER(sequencer_tap_index)
            ),
            sequencer_coeff_real'length
        )
    );

    sequencer_coeff_imag <= std_logic_vector(
        to_signed(
            reload_imag_coefficient(
                sequencer_set_index,
                C_RELOAD_ORDER(sequencer_tap_index)
            ),
            sequencer_coeff_imag'length
        )
    );

    reload_handshake <= real_reload_tvalid and imag_reload_tvalid and real_reload_tready and imag_reload_tready;

    config_handshake <= real_config_tvalid and imag_config_tvalid and real_config_tready and imag_config_tready;

    dut : entity work.complex_channel_emulator
        port map(
            aclk => aclk,
            aresetn => aresetn,

            s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,
            s_axis_tdata => s_axis_tdata,
            s_axis_tlast => s_axis_tlast,

            s_axis_config_real_tvalid => real_config_tvalid,
            s_axis_config_real_tready => real_config_tready,
            s_axis_config_real_tdata => real_config_tdata,

            s_axis_reload_real_tvalid => real_reload_tvalid,
            s_axis_reload_real_tready => real_reload_tready,
            s_axis_reload_real_tdata => real_reload_tdata,
            s_axis_reload_real_tlast => real_reload_tlast,

            s_axis_config_imag_tvalid => imag_config_tvalid,
            s_axis_config_imag_tready => imag_config_tready,
            s_axis_config_imag_tdata => imag_config_tdata,

            s_axis_reload_imag_tvalid => imag_reload_tvalid,
            s_axis_reload_imag_tready => imag_reload_tready,
            s_axis_reload_imag_tdata => imag_reload_tdata,
            s_axis_reload_imag_tlast => imag_reload_tlast,

            m_axis_tvalid => m_axis_tvalid,
            m_axis_tready => m_axis_tready,
            m_axis_tdata => m_axis_tdata,
            m_axis_tlast => m_axis_tlast
        );

    u_coeff_reload_sequencer : entity work.coeff_reload_sequencer
        generic map(
            G_TAP_COUNT => C_TAP_COUNT,
            G_SET_COUNT => C_RELOAD_SET_COUNT,
            G_COEFF_WIDTH => 16,
            G_CONFIG_WIDTH => 8
        )
        port map(
            aclk => aclk,
            aresetn => aresetn,
            start => sequencer_start,
            fu_tick => sequencer_fu_tick,
            coeff_real_value => sequencer_coeff_real,
            coeff_imag_value => sequencer_coeff_imag,
            coeff_set_index => sequencer_set_index,
            coeff_tap_index => sequencer_tap_index,
            real_reload_tvalid => real_reload_tvalid,
            real_reload_tready => real_reload_tready,
            real_reload_tdata => real_reload_tdata,
            real_reload_tlast => real_reload_tlast,
            imag_reload_tvalid => imag_reload_tvalid,
            imag_reload_tready => imag_reload_tready,
            imag_reload_tdata => imag_reload_tdata,
            imag_reload_tlast => imag_reload_tlast,
            real_config_tvalid => real_config_tvalid,
            real_config_tready => real_config_tready,
            real_config_tdata => real_config_tdata,
            imag_config_tvalid => imag_config_tvalid,
            imag_config_tready => imag_config_tready,
            imag_config_tdata => imag_config_tdata,
            busy => sequencer_busy,
            done => sequencer_done,
            block_done => sequencer_block_done,
            timing_error => sequencer_timing_error,
            state_debug => sequencer_state_debug
        );

    output_backpressure_driver : process (aclk)
        variable lfsr : std_logic_vector(15 downto 0) := C_BACKPRESSURE_SEED;
        variable feedback_bit : std_logic;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                m_axis_tready <= '1';
                dbg_output_backpressure <= '0';
                lfsr := C_BACKPRESSURE_SEED;
            elsif output_backpressure_enable = '1' then
                feedback_bit := lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10);
                lfsr := lfsr(14 downto 0) & feedback_bit;

                if lfsr(3 downto 0) = "0000" or
                    lfsr(3 downto 0) = "0111" or
                    lfsr(3 downto 0) = "1011" then
                    m_axis_tready <= '0';
                    dbg_output_backpressure <= '1';
                else
                    m_axis_tready <= '1';
                    dbg_output_backpressure <= '0';
                end if;
            else
                m_axis_tready <= '1';
                dbg_output_backpressure <= '0';
                lfsr := C_BACKPRESSURE_SEED;
            end if;
        end if;
    end process;

    stimulus : process

        procedure wait_clock_cycles (
            constant number_of_cycles : integer
        ) is
        begin
            for index in 1 to number_of_cycles loop
                wait until rising_edge(aclk);
            end loop;
        end procedure;

        procedure send_complex_sample (
            constant i_value : integer;
            constant q_value : integer;
            constant last_value : std_logic
        ) is
            variable timeout_counter : integer := 0;
        begin
            s_axis_tdata <=
                std_logic_vector(to_signed(q_value, 16)) &
                std_logic_vector(to_signed(i_value, 16));
            s_axis_tlast <= last_value;
            s_axis_tvalid <= '1';

            loop
                wait until rising_edge(aclk);

                exit when s_axis_tready = '1';

                timeout_counter := timeout_counter + 1;

                assert timeout_counter < C_INPUT_READY_TIMEOUT_CYCLES
                report "Timeout waiting for input TREADY"
                    severity failure;
            end loop;

            s_axis_tvalid <= '0';
            s_axis_tlast <= '0';
            s_axis_tdata <= (others => '0');
        end procedure;

        procedure send_verification_impulse is
        begin
            send_complex_sample(1, 0, '0');

            for index in 1 to C_VERIFY_PACKET_LENGTH - 1 loop
                if index = C_VERIFY_PACKET_LENGTH - 1 then
                    send_complex_sample(0, 0, '1');
                else
                    send_complex_sample(0, 0, '0');
                end if;
            end loop;
        end procedure;

        procedure send_zero_flush_packet is
        begin
            for index in 0 to C_TAP_COUNT - 1 loop
                if index = C_TAP_COUNT - 1 then
                    send_complex_sample(0, 0, '1');
                else
                    send_complex_sample(0, 0, '0');
                end if;
            end loop;
        end procedure;

        procedure send_active_packet_with_sequencer is
            variable sample_index : integer := 0;
            variable timeout_counter : integer := 0;
            variable data_active : boolean := false;
            variable data_done : boolean := false;
            variable sequencer_started : boolean := false;
            variable fu_tick_count : integer := 0;
            variable fu_wait_count : integer := 0;
        begin
            report "Starting the Phase-3 active-traffic test with sequencer-driven reload"
                severity note;

            loop
                sequencer_fu_tick <= '0';
                dbg_reload_accept <= '0';
                dbg_config_accept <= '0';
                dbg_input_accept <= '0';
                dbg_real_config_accept <= '0';
                dbg_imag_config_accept <= '0';
                dbg_config_during_input_accept <= '0';

                if not data_active and not data_done then
                    s_axis_tdata <= std_logic_vector(to_signed(0, 16)) & std_logic_vector(to_signed(1, 16));

                    if sequencer_block_done = '1' and sequencer_started then
                        s_axis_tlast <= '1';
                    else
                        s_axis_tlast <= '0';
                    end if;

                    s_axis_tvalid <= '1';
                    data_active := true;
                end if;

                if sample_index >= C_RELOAD_START_SAMPLE and not sequencer_started then
                    sequencer_fu_tick <= '1';
                    sequencer_started := true;
                    fu_tick_count := 1;
                    fu_wait_count := 0;

                    report "Starting sequencer reload during active input traffic"
                        severity note;
                elsif sequencer_started and fu_tick_count < C_RELOAD_SET_COUNT then
                    if fu_wait_count = C_PHASE3_FU_PERIOD_CYCLES - 1 then
                        sequencer_fu_tick <= '1';
                        fu_tick_count := fu_tick_count + 1;
                        fu_wait_count := 0;
                    else
                        fu_wait_count := fu_wait_count + 1;
                    end if;
                end if;

                wait until rising_edge(aclk);

                assert sequencer_timing_error = '0'
                report "Sequencer reported a timing error during the Phase-3 active packet"
                    severity failure;

                if data_active and s_axis_tready = '1' then
                    dbg_input_accept <= '1';
                    s_axis_tvalid <= '0';
                    s_axis_tlast <= '0';
                    s_axis_tdata <= (others => '0');
                    data_active := false;

                    if s_axis_tlast = '1' then
                        data_done := true;
                        current_packet_length <= sample_index + 1;
                    else
                        sample_index := sample_index + 1;
                    end if;
                end if;

                if reload_handshake = '1' then
                    dbg_reload_accept <= '1';
                    dbg_reload_set_index <= sequencer_set_index;
                    dbg_reload_slot <= sequencer_tap_index;
                    dbg_reload_real_word <= real_reload_tdata;
                    dbg_reload_imag_word <= imag_reload_tdata;

                    report "Reload set " &
                        integer'image(sequencer_set_index) &
                        ", slot " &
                        integer'image(sequencer_tap_index) &
                        " accepted from the sequencer"
                        severity note;
                end if;

                if real_config_tvalid = '1' and real_config_tready = '1' then
                    dbg_real_config_accept <= '1';
                end if;

                if imag_config_tvalid = '1' and imag_config_tready = '1' then
                    dbg_imag_config_accept <= '1';
                end if;

                if config_handshake = '1' then
                    assert real_config_tready = imag_config_tready
                    report "CONFIG TREADY mismatch; real and imaginary FIRs would not commit together"
                        severity error;

                    dbg_config_accept <= '1';
                    dbg_config_set_index <= sequencer_set_index;

                    if data_active and s_axis_tready = '1' then
                        dbg_config_during_input_accept <= '1';
                    end if;

                    report "CONFIG for reload set " &
                        integer'image(sequencer_set_index) &
                        " accepted from the sequencer"
                        severity note;
                end if;

                exit when data_done and sequencer_block_done = '1';

                timeout_counter := timeout_counter + 1;

                assert timeout_counter < C_ACTIVE_TEST_TIMEOUT_CYCLES
                report "Timeout during the Phase-3 active-traffic sequencer test"
                    severity failure;
            end loop;

            assert sequencer_block_done = '1'
            report "Sequencer did not finish all coefficient sets during the active packet"
                severity failure;

            s_axis_tvalid <= '0';
            s_axis_tlast <= '0';
            s_axis_tdata <= (others => '0');

            report "Phase-3 active-traffic sequencer packet completed"
                severity note;
        end procedure;

        procedure wait_for_output_packet is
            variable timeout_counter : integer := 0;
        begin
            loop
                wait until rising_edge(aclk);

                exit when
                m_axis_tvalid = '1' and
                m_axis_tready = '1' and
                m_axis_tlast = '1';

                timeout_counter := timeout_counter + 1;

                assert timeout_counter < C_OUTPUT_PACKET_TIMEOUT_CYCLES
                report "Timeout waiting for output packet"
                    severity failure;
            end loop;
        end procedure;

    begin
        aresetn <= '0';
        s_axis_tvalid <= '0';
        s_axis_tlast <= '0';
        s_axis_tdata <= (others => '0');
        sequencer_start <= '0';
        sequencer_fu_tick <= '0';
        verification_packet_active <= '0';
        current_packet_length <= C_ACTIVE_PACKET_LENGTH;
        output_backpressure_enable <= '0';

        wait_clock_cycles(10);
        aresetn <= '1';
        wait_clock_cycles(2);
        sequencer_start <= '1';
        wait_clock_cycles(2);

        verification_packet_active <= '0';
        current_packet_length <= C_ACTIVE_PACKET_LENGTH;
        output_backpressure_enable <= '1';
        send_active_packet_with_sequencer;
        wait_for_output_packet;
        output_backpressure_enable <= '0';
        wait_clock_cycles(5);

        -- Flush the FIR delay line so the following impulse measures only the
        -- committed coefficient set, not leftover samples from the active packet.
        verification_packet_active <= '0';
        current_packet_length <= C_TAP_COUNT;
        send_zero_flush_packet;
        wait_for_output_packet;
        wait_clock_cycles(5);

        verification_packet_active <= '1';
        current_packet_length <= C_VERIFY_PACKET_LENGTH;
        send_verification_impulse;
        wait_for_output_packet;
        wait_clock_cycles(10);

        report "Phase-3 sequencer-to-channel-path test completed"
            severity note;

        sequencer_start <= '0';
        wait_clock_cycles(5);

        wait;
    end process;

    output_monitor : process (aclk)
        variable output_index : integer := 0;
        variable output_i : integer;
        variable output_q : integer;
        variable expected_last_index : integer;
        variable expected_i : integer;
        variable expected_q : integer;
        variable output_line : line;
        variable header_written : boolean := false;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                output_index := 0;
            elsif m_axis_tvalid = '1' and m_axis_tready = '1' then

                if not header_written then
                    write(output_line, string'("is_verification_packet,sample_index,output_i,output_q,expected_i,expected_q,tlast"));
                    writeline(output_file, output_line);
                    header_written := true;
                end if;

                output_i := to_integer(signed(m_axis_tdata(39 downto 0)));
                output_q := to_integer(signed(m_axis_tdata(79 downto 40)));
                expected_i := 0;
                expected_q := 0;

                if verification_packet_active = '1' then
                    case output_index is
                        when 0 =>
                            expected_i := 5;
                            expected_q := 0;

                        when 1 =>
                            expected_i := 1;
                            expected_q := 2;

                        when 2 =>
                            expected_i := -2;
                            expected_q := -2;

                        when others =>
                            expected_i := 0;
                            expected_q := 0;
                    end case;
                end if;

                if verification_packet_active = '1' then
                    write(output_line, string'("1"));
                else
                    write(output_line, string'("0"));
                end if;

                write(output_line, string'(","));
                write(output_line, output_index);
                write(output_line, string'(","));
                write(output_line, output_i);
                write(output_line, string'(","));
                write(output_line, output_q);
                write(output_line, string'(","));
                write(output_line, expected_i);
                write(output_line, string'(","));
                write(output_line, expected_q);
                write(output_line, string'(","));

                if m_axis_tlast = '1' then
                    write(output_line, string'("1"));
                else
                    write(output_line, string'("0"));
                end if;

                writeline(output_file, output_line);

                if verification_packet_active = '1' or output_index < 8 or m_axis_tlast = '1' then
                    report "Phase-3 channel output " &
                        integer'image(output_index) &
                        ": I=" &
                        integer'image(output_i) &
                        ", Q=" &
                        integer'image(output_q) &
                        ", TLAST=" &
                        std_logic'image(m_axis_tlast);
                end if;

                if verification_packet_active = '1' then
                    case output_index is
                        when 0 =>
                            assert output_i = 5 and output_q = 0
                            report "Verification impulse mismatch at tap 0"
                                severity error;

                        when 1 =>
                            assert output_i = 1 and output_q = 2
                            report "Verification impulse mismatch at tap 1"
                                severity error;

                        when 2 =>
                            assert output_i = -2 and output_q = -2
                            report "Verification impulse mismatch at tap 2"
                                severity error;

                        when others =>
                            assert output_i = 0 and output_q = 0
                            report "Verification impulse has unexpected non-zero output"
                                severity error;
                    end case;
                end if;

                if m_axis_tlast = '1' then
                    expected_last_index := current_packet_length - 1;

                    assert output_index = expected_last_index
                    report "TLAST received at the wrong output index"
                        severity error;

                    output_index := 0;
                else
                    output_index := output_index + 1;
                end if;
            end if;
        end if;
    end process;

end architecture;
