library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity tb_complex_channel_emulator is
end entity;

architecture rtl of tb_complex_channel_emulator is

    constant C_CLK_PERIOD : time := 3.333 ns;

    constant C_TAP_COUNT : integer := 128;
    constant C_FIR_SAMPLE_PERIOD : integer := 7;
    constant C_RELOAD_WORD_COUNT : integer := 133;
    constant C_VERIFY_RESPONSE_OFFSET : integer := 0;
    constant C_RELOAD_SET_COUNT : integer := 3;
    constant C_RELOAD_START_SAMPLE : integer := 4;
    constant C_FU_PERIOD_CYCLES : integer := 50000;
    constant C_ACTIVE_PACKET_LENGTH : integer :=
        (((C_RELOAD_SET_COUNT - 1) * C_FU_PERIOD_CYCLES) +
        (C_RELOAD_START_SAMPLE * C_FIR_SAMPLE_PERIOD) +
        C_RELOAD_WORD_COUNT + 2048) / C_FIR_SAMPLE_PERIOD;
    constant C_VERIFY_PACKET_LENGTH : integer := C_TAP_COUNT;
    constant C_BOUNDARY_PACKET_LENGTH : integer := 512;
    constant C_BOUNDARY_RELOAD_START_CYCLE : integer := 1000;
    constant C_TIMEOUT : integer := (C_RELOAD_SET_COUNT * C_FU_PERIOD_CYCLES) + 50000;

    type t_coefficient_array is array (0 to C_TAP_COUNT - 1) of integer;
    type t_reload_order_array is array (0 to C_RELOAD_WORD_COUNT - 1) of integer range 0 to C_RELOAD_WORD_COUNT - 1;

    function generated_reload_order return t_reload_order_array is
        variable reload_order : t_reload_order_array;
    begin
        for index in 0 to C_RELOAD_WORD_COUNT - 1 loop
            reload_order(index) :=
                (C_RELOAD_WORD_COUNT - C_FIR_SAMPLE_PERIOD) -
                ((index / C_FIR_SAMPLE_PERIOD) * C_FIR_SAMPLE_PERIOD) +
                (index mod C_FIR_SAMPLE_PERIOD);
        end loop;

        return reload_order;
    end function;

    -- Matches fir_compiler_invest_*_reload_order.txt for the generated
    -- 128-tap, sample-period-7 FIR configuration.
    constant C_RELOAD_ORDER : t_reload_order_array := generated_reload_order;

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

    function reload_real_sum (
        set_index : integer
    ) return integer is
        variable coefficient_sum : integer := 0;
    begin
        for coefficient_index in 0 to C_TAP_COUNT - 1 loop
            coefficient_sum := coefficient_sum +
                reload_real_coefficient(set_index, coefficient_index);
        end loop;

        return coefficient_sum;
    end function;

    function reload_imag_sum (
        set_index : integer
    ) return integer is
        variable coefficient_sum : integer := 0;
    begin
        for coefficient_index in 0 to C_TAP_COUNT - 1 loop
            coefficient_sum := coefficient_sum +
                reload_imag_coefficient(set_index, coefficient_index);
        end loop;

        return coefficient_sum;
    end function;

    constant C_BOUNDARY_EXPECTED_I : integer := reload_real_sum(0);
    constant C_BOUNDARY_EXPECTED_Q : integer := reload_imag_sum(0);
    constant C_BOUNDARY_SETTLE_LIMIT : integer := 32;
    constant C_BOUNDARY_STABLE_SAMPLE_COUNT : integer := 8;

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
    signal dbg_reload_slot         : integer range 0 to C_RELOAD_WORD_COUNT - 1 := 0;
    signal dbg_reload_real_word    : std_logic_vector(15 downto 0) := (others => '0');
    signal dbg_reload_imag_word    : std_logic_vector(15 downto 0) := (others => '0');
    signal dbg_config_accept       : std_logic := '0';
    signal dbg_config_set_index    : integer range 0 to C_RELOAD_SET_COUNT - 1 := 0;
    signal dbg_input_accept        : std_logic := '0';
    signal dbg_real_config_accept  : std_logic := '0';
    signal dbg_imag_config_accept  : std_logic := '0';
    signal dbg_config_during_input_accept : std_logic := '0';

    signal verification_packet_active : std_logic := '0';
    signal boundary_packet_active : std_logic := '0';
    signal boundary_config_committed : std_logic := '0';
    signal current_packet_length : integer := C_ACTIVE_PACKET_LENGTH;

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

        procedure send_reload_set (
            constant set_index : integer
        ) is
            variable coefficient_index : integer := 0;
            variable current_real_word : integer := 0;
            variable current_imag_word : integer := 0;
            variable timeout_counter : integer := 0;
        begin
            for reload_slot in 0 to C_RELOAD_WORD_COUNT - 1 loop
                coefficient_index := C_RELOAD_ORDER(reload_slot);
                current_real_word := reload_real_coefficient(set_index, coefficient_index);
                current_imag_word := reload_imag_coefficient(set_index, coefficient_index);

                real_reload_tdata <= std_logic_vector(to_signed(current_real_word, 16));
                imag_reload_tdata <= std_logic_vector(to_signed(current_imag_word, 16));
                real_reload_tvalid <= '1';
                imag_reload_tvalid <= '1';

                if reload_slot = C_RELOAD_WORD_COUNT - 1 then
                    real_reload_tlast <= '1';
                    imag_reload_tlast <= '1';
                else
                    real_reload_tlast <= '0';
                    imag_reload_tlast <= '0';
                end if;

                loop
                    wait until rising_edge(aclk);

                    exit when real_reload_tready = '1' and imag_reload_tready = '1';

                    timeout_counter := timeout_counter + 1;

                    assert timeout_counter < C_TIMEOUT
                    report "Timeout waiting for reload TREADY in boundary test"
                        severity failure;
                end loop;

                dbg_reload_accept <= '1';
                dbg_reload_set_index <= set_index;
                dbg_reload_slot <= reload_slot;
                dbg_reload_real_word <= std_logic_vector(to_signed(current_real_word, 16));
                dbg_reload_imag_word <= std_logic_vector(to_signed(current_imag_word, 16));

                wait until rising_edge(aclk);
                dbg_reload_accept <= '0';
                real_reload_tvalid <= '0';
                imag_reload_tvalid <= '0';
                real_reload_tlast <= '0';
                imag_reload_tlast <= '0';
                real_reload_tdata <= (others => '0');
                imag_reload_tdata <= (others => '0');
            end loop;
        end procedure;

        procedure send_synchronized_config is
            variable timeout_counter : integer := 0;
        begin
            real_config_tdata <= (others => '0');
            imag_config_tdata <= (others => '0');
            real_config_tvalid <= '1';
            imag_config_tvalid <= '1';

            loop
                wait until rising_edge(aclk);

                assert real_config_tready = imag_config_tready
                report "CONFIG TREADY mismatch in boundary test"
                    severity error;

                exit when real_config_tready = '1' and imag_config_tready = '1';

                timeout_counter := timeout_counter + 1;

                assert timeout_counter < C_TIMEOUT
                report "Timeout waiting for CONFIG TREADY in boundary test"
                    severity failure;
            end loop;

            dbg_config_accept <= '1';
            dbg_config_set_index <= 0;
            dbg_real_config_accept <= '1';
            dbg_imag_config_accept <= '1';
            boundary_config_committed <= '1';

            wait until rising_edge(aclk);
            dbg_config_accept <= '0';
            dbg_real_config_accept <= '0';
            dbg_imag_config_accept <= '0';
            real_config_tvalid <= '0';
            imag_config_tvalid <= '0';
            real_config_tdata <= (others => '0');
            imag_config_tdata <= (others => '0');
        end procedure;

        -- Keeps input samples active while reload and CONFIG occur so the
        -- FIR pipeline boundary around the coefficient switch can be observed.
        procedure run_config_boundary_test is
            variable sample_index : integer := 0;
            variable reload_slot : integer := 0;
            variable coefficient_index : integer := 0;
            variable clock_cycle_count : integer := 0;
            variable data_active : boolean := false;
            variable data_done : boolean := false;
            variable real_reload_active : boolean := false;
            variable imag_reload_active : boolean := false;
            variable reload_beat_pending : boolean := false;
            variable reload_set_loaded : boolean := false;
            variable real_config_active : boolean := false;
            variable imag_config_active : boolean := false;
            variable config_started : boolean := false;
            variable config_done : boolean := false;
            variable timeout_counter : integer := 0;
            variable current_real_word : integer := 0;
            variable current_imag_word : integer := 0;
            variable input_accepted : boolean := false;
            variable real_config_accepted : boolean := false;
            variable imag_config_accepted : boolean := false;
            variable reload_start_time : time := 0 ns;
            variable reload_last_time : time := 0 ns;
            variable config_start_time : time := 0 ns;
            variable config_accept_time : time := 0 ns;
            variable reload_time : time := 0 ns;
            variable config_time : time := 0 ns;
            variable reload_plus_config_time : time := 0 ns;
            variable reload_cycle_count : integer := 0;
            variable config_cycle_count : integer := 0;
            variable reload_plus_config_cycle_count : integer := 0;
        begin
            loop
                if not data_active and not data_done then
                    s_axis_tdata <= std_logic_vector(to_signed(0, 16)) &
                        std_logic_vector(to_signed(1, 16));

                    if sample_index = C_BOUNDARY_PACKET_LENGTH - 1 then
                        s_axis_tlast <= '1';
                    else
                        s_axis_tlast <= '0';
                    end if;

                    s_axis_tvalid <= '1';
                    data_active := true;
                end if;

                if clock_cycle_count >= C_BOUNDARY_RELOAD_START_CYCLE and
                    not config_started and
                    not reload_set_loaded and
                    not reload_beat_pending then

                    coefficient_index := C_RELOAD_ORDER(reload_slot);
                    current_real_word :=
                        reload_real_coefficient(0, coefficient_index);
                    current_imag_word :=
                        reload_imag_coefficient(0, coefficient_index);

                    real_reload_tdata <= std_logic_vector(
                        to_signed(current_real_word, real_reload_tdata'LENGTH)
                        );
                    imag_reload_tdata <= std_logic_vector(
                        to_signed(current_imag_word, imag_reload_tdata'LENGTH)
                        );

                    if reload_slot = C_RELOAD_WORD_COUNT - 1 then
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

                if reload_set_loaded and not config_started and not config_done then
                    real_config_tdata <= (others => '0');
                    imag_config_tdata <= (others => '0');
                    real_config_tvalid <= '1';
                    imag_config_tvalid <= '1';
                    real_config_active := true;
                    imag_config_active := true;
                    config_started := true;
                    config_start_time := now;
                end if;

                wait until rising_edge(aclk);
                clock_cycle_count := clock_cycle_count + 1;
                dbg_input_accept <= '0';
                dbg_reload_accept <= '0';
                dbg_config_accept <= '0';
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

                    if sample_index = C_BOUNDARY_PACKET_LENGTH - 1 then
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

                if reload_beat_pending and not real_reload_active and
                    not imag_reload_active then

                    if reload_slot = 0 then
                        reload_start_time := now;
                    end if;

                    if reload_slot = C_RELOAD_WORD_COUNT - 1 then
                        reload_last_time := now;
                    end if;

                    dbg_reload_accept <= '1';
                    dbg_reload_set_index <= 0;
                    dbg_reload_slot <= reload_slot;
                    dbg_reload_real_word <= std_logic_vector(
                        to_signed(current_real_word, 16)
                        );
                    dbg_reload_imag_word <= std_logic_vector(
                        to_signed(current_imag_word, 16)
                        );

                    if reload_slot /= C_RELOAD_WORD_COUNT - 1 then
                        reload_slot := reload_slot + 1;
                    else
                        reload_set_loaded := true;
                    end if;

                    reload_beat_pending := false;
                end if;

                if real_config_active or imag_config_active then
                    assert real_config_tready = imag_config_tready
                    report "CONFIG TREADY mismatch during boundary test"
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

                if config_started and not real_config_active and
                    not imag_config_active and not config_done then

                    assert not data_done
                    report "Boundary CONFIG was accepted only after the input packet ended"
                        severity error;

                    dbg_config_accept <= '1';
                    dbg_config_set_index <= 0;
                    if input_accepted and real_config_accepted and
                        imag_config_accepted then

                        dbg_config_during_input_accept <= '1';
                    end if;

                    boundary_config_committed <= '1';
                    config_done := true;
                    config_accept_time := now;
                    reload_time := reload_last_time - reload_start_time;
                    config_time := config_accept_time - config_start_time;
                    reload_plus_config_time := config_accept_time - reload_start_time;
                    reload_cycle_count := reload_time / C_CLK_PERIOD;
                    config_cycle_count := config_time / C_CLK_PERIOD;
                    reload_plus_config_cycle_count :=
                        reload_plus_config_time / C_CLK_PERIOD;

                    report "Boundary reload timing: reload=" &
                        time'image(reload_time) &
                        " (" &
                        integer'image(reload_cycle_count) &
                        " cycles), config_after_reload=" &
                        time'image(config_time) &
                        " (" &
                        integer'image(config_cycle_count) &
                        " cycles), reload_plus_config=" &
                        time'image(reload_plus_config_time) &
                        " (" &
                        integer'image(reload_plus_config_cycle_count) &
                        " cycles)"
                        severity note;
                end if;

                exit when data_done and config_done;

                timeout_counter := timeout_counter + 1;

                if timeout_counter >= C_TIMEOUT then
                    report "Timeout during the CONFIG boundary test: slot=" &
                        integer'image(reload_slot) &
                        ", sample_index=" &
                        integer'image(sample_index) &
                        ", clock_cycle_count=" &
                        integer'image(clock_cycle_count) &
                        ", data_done=" &
                        boolean'image(data_done) &
                        ", reload_set_loaded=" &
                        boolean'image(reload_set_loaded) &
                        ", reload_beat_pending=" &
                        boolean'image(reload_beat_pending) &
                        ", real_reload_active=" &
                        boolean'image(real_reload_active) &
                        ", imag_reload_active=" &
                        boolean'image(imag_reload_active) &
                        ", config_started=" &
                        boolean'image(config_started) &
                        ", config_done=" &
                        boolean'image(config_done)
                        severity failure;
                end if;
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
            variable clock_cycle_count : integer := 0;
            variable next_reload_start_cycle : integer :=
                C_RELOAD_START_SAMPLE * C_FIR_SAMPLE_PERIOD;
            variable reload_start_time : time := 0 ns;
            variable reload_last_time : time := 0 ns;
            variable config_start_time : time := 0 ns;
            variable config_accept_time : time := 0 ns;
            variable reload_time : time := 0 ns;
            variable config_time : time := 0 ns;
            variable reload_plus_config_time : time := 0 ns;
            variable reload_cycle_count : integer := 0;
            variable config_cycle_count : integer := 0;
            variable reload_plus_config_cycle_count : integer := 0;
        begin
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

                if clock_cycle_count >= next_reload_start_cycle and
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

                    if reload_slot = C_RELOAD_WORD_COUNT - 1 then
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
                    config_start_time := now;

                end if;

                wait until rising_edge(aclk);
                clock_cycle_count := clock_cycle_count + 1;

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

                    if reload_slot = 0 then
                        reload_start_time := now;
                    end if;

                    if reload_slot = C_RELOAD_WORD_COUNT - 1 then
                        reload_last_time := now;
                    end if;

                    dbg_reload_accept <= '1';
                    dbg_reload_set_index <= reload_set_index;
                    dbg_reload_slot <= reload_slot;
                    dbg_reload_real_word <= std_logic_vector(
                        to_signed(current_real_word, 16)
                        );
                    dbg_reload_imag_word <= std_logic_vector(
                        to_signed(current_imag_word, 16)
                        );

                    if reload_slot /= C_RELOAD_WORD_COUNT - 1 then
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
                    config_accept_time := now;
                    reload_time := reload_last_time - reload_start_time;
                    config_time := config_accept_time - config_start_time;
                    reload_plus_config_time := config_accept_time - reload_start_time;
                    reload_cycle_count := reload_time / C_CLK_PERIOD;
                    config_cycle_count := config_time / C_CLK_PERIOD;
                    reload_plus_config_cycle_count := reload_plus_config_time / C_CLK_PERIOD;

                    report "Reload timing for set " &
                        integer'image(reload_set_index) &
                        ": reload=" &
                        time'image(reload_time) &
                        " (" &
                        integer'image(reload_cycle_count) &
                        " cycles), config_after_reload=" &
                        time'image(config_time) &
                        " (" &
                        integer'image(config_cycle_count) &
                        " cycles), reload_plus_config=" &
                        time'image(reload_plus_config_time) &
                        " (" &
                        integer'image(reload_plus_config_cycle_count) &
                        " cycles)"
                        severity note;

                    if reload_set_index = C_RELOAD_SET_COUNT - 1 then
                        all_reload_sets_done := true;
                    else
                        reload_set_index := reload_set_index + 1;
                        reload_slot := 0;
                        reload_set_loaded := false;
                        config_started := false;
                        config_done := false;
                        next_reload_start_cycle :=
                            next_reload_start_cycle + C_FU_PERIOD_CYCLES;
                    end if;
                end if;

                exit when data_done and all_reload_sets_done;

                timeout_counter := timeout_counter + 1;

                if timeout_counter >= C_TIMEOUT then
                    report "Timeout during the active-traffic reload test: set=" &
                        integer'image(reload_set_index) &
                        ", slot=" &
                        integer'image(reload_slot) &
                        ", sample_index=" &
                        integer'image(sample_index) &
                        ", clock_cycle_count=" &
                        integer'image(clock_cycle_count) &
                        ", next_reload_start_cycle=" &
                        integer'image(next_reload_start_cycle) &
                        ", data_done=" &
                        boolean'image(data_done) &
                        ", reload_set_loaded=" &
                        boolean'image(reload_set_loaded) &
                        ", reload_beat_pending=" &
                        boolean'image(reload_beat_pending) &
                        ", real_reload_active=" &
                        boolean'image(real_reload_active) &
                        ", imag_reload_active=" &
                        boolean'image(imag_reload_active) &
                        ", config_started=" &
                        boolean'image(config_started) &
                        ", config_done=" &
                        boolean'image(config_done)
                        severity failure;
                end if;
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
        boundary_packet_active <= '0';
        boundary_config_committed <= '0';
        current_packet_length <= C_BOUNDARY_PACKET_LENGTH;

        wait_clock_cycles(10);
        aresetn <= '1';
        wait_clock_cycles(2);

        -- Original Phase-1 regression kept here for later re-enable.
        -- verification_packet_active <= '0';
        -- current_packet_length <= C_ACTIVE_PACKET_LENGTH;
        -- send_active_packet_with_reload;
        -- wait_for_output_packet;
        -- wait_clock_cycles(5);
        --
        -- verification_packet_active <= '0';
        -- current_packet_length <= C_TAP_COUNT;
        -- send_zero_flush_packet;
        -- wait_for_output_packet;
        -- wait_clock_cycles(5);
        --
        -- verification_packet_active <= '1';
        -- current_packet_length <= C_VERIFY_PACKET_LENGTH;
        -- send_verification_impulse;
        -- wait_for_output_packet;
        -- wait_clock_cycles(10);

        -- Active scenario for the supervisor question:
        -- observe the output around CONFIG without zero-flushing the FIR.
        boundary_packet_active <= '1';
        current_packet_length <= C_BOUNDARY_PACKET_LENGTH;
        run_config_boundary_test;
        wait_for_output_packet;
        wait_clock_cycles(10);

        boundary_packet_active <= '0';

        report "CONFIG-boundary coefficient reload test completed"
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
        variable verification_coefficient_index : integer;
        variable output_line : line;
        variable header_written : boolean := false;
        variable boundary_config_seen : boolean := false;
        variable boundary_config_output_index : integer := 0;
        variable boundary_new_response_seen : boolean := false;
        variable boundary_stable_count : integer := 0;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                output_index := 0;
                boundary_config_seen := false;
                boundary_config_output_index := 0;
                boundary_new_response_seen := false;
                boundary_stable_count := 0;
            elsif m_axis_tvalid = '1' and m_axis_tready = '1' then

                if not header_written then
                    write(output_line, string'("is_verification_packet,is_boundary_packet,config_committed,sample_index,output_i,output_q,expected_i,expected_q,tlast"));
                    writeline(output_file, output_line);
                    header_written := true;
                end if;

                output_i := to_integer(signed(m_axis_tdata(39 downto 0)));
                output_q := to_integer(signed(m_axis_tdata(79 downto 40)));
                expected_i := 0;
                expected_q := 0;

                if verification_packet_active = '1' then
                    verification_coefficient_index := output_index - C_VERIFY_RESPONSE_OFFSET;

                    if verification_coefficient_index >= 0 and
                        verification_coefficient_index < C_TAP_COUNT then

                        expected_i := reload_real_coefficient(
                            C_RELOAD_SET_COUNT - 1,
                            verification_coefficient_index
                            );
                        expected_q := reload_imag_coefficient(
                            C_RELOAD_SET_COUNT - 1,
                            verification_coefficient_index
                            );
                    end if;
                end if;

                if verification_packet_active = '1' then
                    write(output_line, string'("1"));
                else
                    write(output_line, string'("0"));
                end if;

                write(output_line, string'(","));

                if boundary_packet_active = '1' then
                    write(output_line, string'("1"));
                else
                    write(output_line, string'("0"));
                end if;

                write(output_line, string'(","));

                if boundary_config_committed = '1' then
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

                if verification_packet_active = '1' then
                    assert output_i = expected_i and output_q = expected_q
                    report "Verification impulse output does not match the expected 128-tap response"
                        severity error;
                end if;

                if boundary_packet_active = '1' then
                    if boundary_config_committed = '1' and
                        not boundary_config_seen then

                        boundary_config_seen := true;
                        boundary_config_output_index := output_index;
                    end if;

                    if boundary_config_seen then
                        if output_i = C_BOUNDARY_EXPECTED_I and
                            output_q = C_BOUNDARY_EXPECTED_Q then

                            if not boundary_new_response_seen then
                                report "Boundary test: new coefficient response observed at output sample " &
                                    integer'image(output_index) &
                                    " after CONFIG sample " &
                                    integer'image(boundary_config_output_index)
                                    severity note;
                            end if;

                            boundary_new_response_seen := true;
                            boundary_stable_count := boundary_stable_count + 1;
                        elsif boundary_new_response_seen then
                            assert false
                            report "Boundary test: output changed after new coefficient response became stable"
                                severity error;
                        end if;

                        assert output_index - boundary_config_output_index <=
                            C_BOUNDARY_SETTLE_LIMIT or boundary_new_response_seen
                        report "Boundary test: new coefficient response was not observed within the settle limit"
                            severity error;
                    end if;
                end if;

                if m_axis_tlast = '1' then
                    expected_last_index := current_packet_length - 1;

                    assert output_index = expected_last_index
                    report "TLAST received at the wrong output index"
                        severity error;

                    if boundary_packet_active = '1' then
                        assert boundary_new_response_seen
                        report "Boundary test: new coefficient response was never observed"
                            severity error;

                        assert boundary_stable_count >= C_BOUNDARY_STABLE_SAMPLE_COUNT
                        report "Boundary test: new coefficient response was not stable for enough samples"
                            severity error;
                    end if;

                    output_index := 0;
                else
                    output_index := output_index + 1;
                end if;
            end if;
        end if;
    end process;

end architecture;
