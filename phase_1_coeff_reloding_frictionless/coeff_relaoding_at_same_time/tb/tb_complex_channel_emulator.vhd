library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity tb_complex_channel_emulator is
end entity;

architecture rtl of tb_complex_channel_emulator is

    constant C_CLK_PERIOD : time := 10 ns;

    constant C_TAP_COUNT : integer := 32;
    constant C_RELOAD_SET_COUNT : integer := 3;
    constant C_ACTIVE_PACKET_LENGTH : integer := 180;
    constant C_VERIFY_PACKET_LENGTH : integer := 25;
    constant C_RELOAD_START_SAMPLE : integer := 4;
    constant C_TIMEOUT : integer := 10000;
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
    "/home/sasindu/work/TDL_chnannel_emulator_project/tdl-channel-emulator-for-wfm-testing/phase_1_coeff_reloding_frictionless/coeff_relaoding_at_same_time/misc/phase_1_complex_channel_output.csv";

begin

    aclk <= not aclk after C_CLK_PERIOD / 2;

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

                assert timeout_counter < C_TIMEOUT
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

        procedure send_active_packet_with_reload is
            variable sample_index : integer := 0;
            variable reload_set_index : integer range 0 to C_RELOAD_SET_COUNT - 1 := 0;
            variable reload_slot : integer := 0;
            variable coefficient_index : integer := 0;
            variable timeout_counter : integer := 0;
            variable data_active : boolean := false;
            variable real_reload_active : boolean := false;
            variable imag_reload_active : boolean := false;
            variable reload_beat_pending : boolean := false;
            variable reload_set_loaded : boolean := false;
            variable all_reload_sets_done : boolean := false;
            variable real_config_active : boolean := false;
            variable imag_config_active : boolean := false;
            variable config_started : boolean := false;
            variable config_done : boolean := false;
            variable data_done : boolean := false;
            variable current_real_word : integer := 0;
            variable current_imag_word : integer := 0;
            variable input_accepted : boolean := false;
            variable real_config_accepted : boolean := false;
            variable imag_config_accepted : boolean := false;
        begin
            report "Starting the single Phase-1 active-traffic repeated reload test"
                severity note;

            loop
                if not data_active and not data_done then
                    s_axis_tdata <= std_logic_vector(to_signed(0, 16)) & std_logic_vector(to_signed(1, 16));

                    if sample_index = C_ACTIVE_PACKET_LENGTH - 1 then
                        s_axis_tlast <= '1';
                    else
                        s_axis_tlast <= '0';
                    end if;

                    s_axis_tvalid <= '1';
                    data_active := true;
                end if;

                if sample_index >= C_RELOAD_START_SAMPLE and
                    not all_reload_sets_done and
                    not config_started and
                    not reload_set_loaded and
                    not reload_beat_pending then

                    coefficient_index := C_RELOAD_ORDER(reload_slot);
                    current_real_word :=
                        reload_real_coefficient(reload_set_index, coefficient_index);
                    current_imag_word :=
                        reload_imag_coefficient(reload_set_index, coefficient_index);

                    real_reload_tdata <= std_logic_vector(
                        to_signed(current_real_word, real_reload_tdata'LENGTH)
                        );
                    imag_reload_tdata <= std_logic_vector(
                        to_signed(current_imag_word, imag_reload_tdata'LENGTH)
                        );

                    if reload_slot = C_TAP_COUNT - 1 then
                        real_reload_tlast <= '1';
                        imag_reload_tlast <= '1';
                    else
                        real_reload_tlast <= '0';
                        imag_reload_tlast <= '0';
                    end if;

                    real_reload_tvalid <= '1';
                    imag_reload_tvalid <= '1';
                    real_reload_active := true;
                    imag_reload_active := true;
                    reload_beat_pending := true;
                end if;

                if reload_set_loaded and
                    not config_started and
                    not config_done and
                    not all_reload_sets_done then

                    real_config_tdata <= (others => '0');
                    imag_config_tdata <= (others => '0');
                    real_config_tvalid <= '1';
                    imag_config_tvalid <= '1';
                    real_config_active := true;
                    imag_config_active := true;
                    config_started := true;

                    report "Starting CONFIG for reload set " &
                        integer'image(reload_set_index) &
                        " while the input packet is still active"
                        severity note;
                end if;

                wait until rising_edge(aclk);

                dbg_reload_accept <= '0';
                dbg_config_accept <= '0';
                dbg_input_accept <= '0';
                dbg_real_config_accept <= '0';
                dbg_imag_config_accept <= '0';
                dbg_config_during_input_accept <= '0';
                input_accepted := false;
                real_config_accepted := false;
                imag_config_accepted := false;

                if data_active and s_axis_tready = '1' then
                    input_accepted := true;
                    dbg_input_accept <= '1';
                    s_axis_tvalid <= '0';
                    s_axis_tlast <= '0';
                    s_axis_tdata <= (others => '0');
                    data_active := false;

                    if sample_index = C_ACTIVE_PACKET_LENGTH - 1 then
                        data_done := true;
                    else
                        sample_index := sample_index + 1;
                    end if;
                end if;

                if real_reload_active and real_reload_tready = '1' then
                    real_reload_tvalid <= '0';
                    real_reload_tlast <= '0';
                    real_reload_tdata <= (others => '0');
                    real_reload_active := false;
                end if;

                if imag_reload_active and imag_reload_tready = '1' then
                    imag_reload_tvalid <= '0';
                    imag_reload_tlast <= '0';
                    imag_reload_tdata <= (others => '0');
                    imag_reload_active := false;
                end if;

                if reload_beat_pending and not real_reload_active and not imag_reload_active then

                    dbg_reload_accept <= '1';
                    dbg_reload_set_index <= reload_set_index;
                    dbg_reload_slot <= reload_slot;
                    dbg_reload_real_word <= std_logic_vector(
                        to_signed(current_real_word, 16)
                        );
                    dbg_reload_imag_word <= std_logic_vector(
                        to_signed(current_imag_word, 16)
                        );

                    report "Reload set " &
                        integer'image(reload_set_index) &
                        ", slot " &
                        integer'image(reload_slot) &
                        " accepted during active input traffic"
                        severity note;

                    if reload_slot /= C_TAP_COUNT - 1 then
                        reload_slot := reload_slot + 1;
                    else
                        reload_set_loaded := true;
                    end if;

                    reload_beat_pending := false;
                end if;

                if real_config_active or imag_config_active then
                    assert real_config_tready = imag_config_tready
                    report "CONFIG TREADY mismatch; real and imaginary FIRs would not commit together"
                        severity error;
                end if;

                if real_config_active and real_config_tready = '1' then
                    real_config_accepted := true;
                    dbg_real_config_accept <= '1';
                    real_config_tvalid <= '0';
                    real_config_tdata <= (others => '0');
                    real_config_active := false;
                end if;

                if imag_config_active and imag_config_tready = '1' then
                    imag_config_accepted := true;
                    dbg_imag_config_accept <= '1';
                    imag_config_tvalid <= '0';
                    imag_config_tdata <= (others => '0');
                    imag_config_active := false;
                end if;

                if config_started and not real_config_active and not imag_config_active and
                    not config_done then

                    assert not data_done
                    report "CONFIG was accepted only after the active input packet ended"
                        severity error;

                    dbg_config_accept <= '1';
                    dbg_config_set_index <= reload_set_index;
                    if input_accepted and real_config_accepted and imag_config_accepted then
                        dbg_config_during_input_accept <= '1';
                    end if;
                    config_done := true;

                    report "CONFIG for reload set " &
                        integer'image(reload_set_index) &
                        " accepted during active input traffic"
                        severity note;

                    if reload_set_index = C_RELOAD_SET_COUNT - 1 then
                        all_reload_sets_done := true;
                    else
                        reload_set_index := reload_set_index + 1;
                        reload_slot := 0;
                        reload_set_loaded := false;
                        config_started := false;
                        config_done := false;
                    end if;
                end if;

                exit when data_done and all_reload_sets_done;

                timeout_counter := timeout_counter + 1;

                assert timeout_counter < C_TIMEOUT
                report "Timeout during the active-traffic reload test"
                    severity failure;
            end loop;

            s_axis_tvalid <= '0';
            s_axis_tlast <= '0';
            s_axis_tdata <= (others => '0');
            real_reload_tvalid <= '0';
            real_reload_tlast <= '0';
            real_reload_tdata <= (others => '0');
            imag_reload_tvalid <= '0';
            imag_reload_tlast <= '0';
            imag_reload_tdata <= (others => '0');
            real_config_tvalid <= '0';
            real_config_tdata <= (others => '0');
            imag_config_tvalid <= '0';
            imag_config_tdata <= (others => '0');

            report "Active-traffic reload packet completed"
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

                assert timeout_counter < C_TIMEOUT
                report "Timeout waiting for output packet"
                    severity failure;
            end loop;
        end procedure;

    begin
        aresetn <= '0';
        s_axis_tvalid <= '0';
        s_axis_tlast <= '0';
        s_axis_tdata <= (others => '0');
        real_reload_tvalid <= '0';
        real_reload_tlast <= '0';
        real_reload_tdata <= (others => '0');
        real_config_tvalid <= '0';
        real_config_tdata <= (others => '0');
        imag_reload_tvalid <= '0';
        imag_reload_tlast <= '0';
        imag_reload_tdata <= (others => '0');
        imag_config_tvalid <= '0';
        imag_config_tdata <= (others => '0');
        verification_packet_active <= '0';
        current_packet_length <= C_ACTIVE_PACKET_LENGTH;
        output_backpressure_enable <= '0';

        wait_clock_cycles(10);
        aresetn <= '1';
        wait_clock_cycles(2);

        verification_packet_active <= '0';
        current_packet_length <= C_ACTIVE_PACKET_LENGTH;
        output_backpressure_enable <= '1';
        send_active_packet_with_reload;
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

        report "Single Phase-1 coefficient reload test completed"
            severity note;

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

                report "Phase-1 active reload output " &
                    integer'image(output_index) &
                    ": I=" &
                    integer'image(output_i) &
                    ", Q=" &
                    integer'image(output_q) &
                    ", TLAST=" &
                    std_logic'image(m_axis_tlast);

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
