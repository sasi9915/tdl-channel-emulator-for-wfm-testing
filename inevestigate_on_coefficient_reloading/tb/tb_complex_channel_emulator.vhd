LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY std;
USE std.textio.ALL;

ENTITY tb_complex_channel_emulator IS
END ENTITY;

ARCHITECTURE sim OF tb_complex_channel_emulator IS

    CONSTANT C_CLK_PERIOD : TIME := 10 ns;

    CONSTANT C_TAP_COUNT : INTEGER := 21;
    CONSTANT C_PACKET_LENGTH : INTEGER := 25;
    CONSTANT C_ACTIVE_PACKET_LENGTH : INTEGER := 80;
    CONSTANT C_RELOAD_START_SAMPLE : INTEGER := 4;
    CONSTANT C_TIMEOUT : INTEGER := 10000;

    TYPE t_coefficient_array IS ARRAY (0 TO C_TAP_COUNT - 1) OF INTEGER;

    TYPE t_reload_order_array IS ARRAY (0 TO C_TAP_COUNT - 1) OF INTEGER RANGE 0 TO C_TAP_COUNT - 1;

    -- New real coefficients:
    -- hR = [2, 0, 0, ..., 0]
    CONSTANT C_REAL_COEFFICIENTS : t_coefficient_array := (0 => 2, OTHERS => 0);

    -- New imaginary coefficients:
    -- hI = [0, 0, -1, 0, ..., 0]
    CONSTANT C_IMAG_COEFFICIENTS : t_coefficient_array := (2 => - 1, OTHERS => 0);

    -- Active-traffic reload coefficients. These are intentionally non-zero
    -- across several early taps so the reload words are easy to see in waves.
    CONSTANT C_ACTIVE_REAL_COEFFICIENTS : t_coefficient_array := (
        0 => 3,
        1 => 4,
        2 => 5,
        OTHERS => 0
    );

    CONSTANT C_ACTIVE_IMAG_COEFFICIENTS : t_coefficient_array := (
        1 => - 2,
        2 => - 3,
        OTHERS => 0
    );

    -- Replace this with the actual reload order displayed
    -- by the FIR Compiler coefficient reload tab.
    CONSTANT C_RELOAD_ORDER : t_reload_order_array := (
        0, 1, 2, 3, 4,
        5, 6, 7, 8, 9,
        10, 11, 12, 13, 14,
        15, 16, 17, 18, 19,
        20
    );

    SIGNAL aclk : STD_LOGIC := '0';
    SIGNAL aresetn : STD_LOGIC := '0';

    SIGNAL s_axis_tvalid : STD_LOGIC := '0';
    SIGNAL s_axis_tready : STD_LOGIC;
    SIGNAL s_axis_tdata : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL s_axis_tlast : STD_LOGIC := '0';

    SIGNAL m_axis_tvalid : STD_LOGIC;
    SIGNAL m_axis_tready : STD_LOGIC := '1';
    SIGNAL m_axis_tdata : STD_LOGIC_VECTOR(79 DOWNTO 0);
    SIGNAL m_axis_tlast : STD_LOGIC;

    SIGNAL real_reload_tvalid : STD_LOGIC := '0';
    SIGNAL real_reload_tready : STD_LOGIC;
    SIGNAL real_reload_tdata : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL real_reload_tlast : STD_LOGIC := '0';

    SIGNAL real_config_tvalid : STD_LOGIC := '0';
    SIGNAL real_config_tready : STD_LOGIC;
    SIGNAL real_config_tdata : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');

    SIGNAL imag_reload_tvalid : STD_LOGIC := '0';
    SIGNAL imag_reload_tready : STD_LOGIC;
    SIGNAL imag_reload_tdata : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL imag_reload_tlast : STD_LOGIC := '0';

    SIGNAL imag_config_tvalid : STD_LOGIC := '0';
    SIGNAL imag_config_tready : STD_LOGIC;
    SIGNAL imag_config_tdata : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');

    SIGNAL dbg_active_reload_accept : STD_LOGIC := '0';
    SIGNAL dbg_active_reload_slot : INTEGER RANGE 0 TO C_TAP_COUNT - 1 := 0;
    SIGNAL dbg_active_reload_real_word : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL dbg_active_reload_imag_word : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');

    -- 0 = no test
    -- 1 = original coefficients
    -- 2 = reloaded coefficients
    -- 3 = reload/config while a sample packet is active
    -- 4 = active-traffic reloaded coefficients
    SIGNAL test_number : INTEGER RANGE 0 TO 4 := 0;

    FILE output_file : text OPEN write_mode IS
    "/home/sasindu/work/TDL_chnannel_emulator_project/inevestigate_on_coefficient_reloading/misc/complex_channel_output.csv";

BEGIN

    aclk <= NOT aclk AFTER C_CLK_PERIOD / 2;

    dut : ENTITY work.complex_channel_emulator
        PORT MAP(
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

    stimulus : PROCESS

        PROCEDURE wait_clock_cycles (
            CONSTANT number_of_cycles : INTEGER
        ) IS
        BEGIN
            FOR index IN 1 TO number_of_cycles LOOP
                WAIT UNTIL rising_edge(aclk);
            END LOOP;
        END PROCEDURE;

        PROCEDURE send_complex_sample (
            CONSTANT i_value : INTEGER;
            CONSTANT q_value : INTEGER;
            CONSTANT last_value : STD_LOGIC
        ) IS
            VARIABLE timeout_counter : INTEGER := 0;
        BEGIN
            s_axis_tdata <= STD_LOGIC_VECTOR(to_signed(q_value, 16)) & STD_LOGIC_VECTOR(to_signed(i_value, 16));
            s_axis_tlast <= last_value;
            s_axis_tvalid <= '1';

            LOOP
                WAIT UNTIL rising_edge(aclk);

                EXIT WHEN s_axis_tready = '1';

                timeout_counter := timeout_counter + 1;

                ASSERT timeout_counter < C_TIMEOUT
                REPORT "Timeout waiting for input TREADY"
                    SEVERITY failure;
            END LOOP;

            s_axis_tvalid <= '0';
            s_axis_tlast <= '0';
            s_axis_tdata <= (OTHERS => '0');
        END PROCEDURE;

        PROCEDURE send_impulse_packet IS
        BEGIN
            -- x[0] = 1 + j0
            send_complex_sample(1, 0, '0');

            FOR index IN 1 TO C_PACKET_LENGTH - 1 LOOP
                IF index = C_PACKET_LENGTH - 1 THEN
                    send_complex_sample(0, 0, '1');
                ELSE
                    send_complex_sample(0, 0, '0');
                END IF;
            END LOOP;
        END PROCEDURE;

        PROCEDURE send_real_reload_packet IS
            VARIABLE coefficient_index : INTEGER;
            VARIABLE timeout_counter   : INTEGER;
        BEGIN
            REPORT "Starting real coefficient reload"
                SEVERITY note;

            FOR reload_slot IN 0 TO C_TAP_COUNT - 1 LOOP

                coefficient_index := C_RELOAD_ORDER(reload_slot);

                real_reload_tdata <= STD_LOGIC_VECTOR( to_signed( C_REAL_COEFFICIENTS(coefficient_index), real_reload_tdata'LENGTH));

                IF reload_slot = C_TAP_COUNT - 1 THEN
                    real_reload_tlast <= '1';
                ELSE
                    real_reload_tlast <= '0';
                END IF;

                real_reload_tvalid <= '1';
                timeout_counter := 0;

                LOOP
                    WAIT UNTIL rising_edge(aclk);

                    EXIT WHEN real_reload_tready = '1';

                    timeout_counter := timeout_counter + 1;

                    ASSERT timeout_counter < C_TIMEOUT
                    REPORT "Timeout waiting for real reload TREADY"
                        SEVERITY failure;
                END LOOP;

                REPORT "Real reload slot " &
                    INTEGER'image(reload_slot) &
                    ", coefficient index " &
                    INTEGER'image(coefficient_index) &
                    ", value " &
                    INTEGER'image(
                    C_REAL_COEFFICIENTS(coefficient_index)
                    )
                    SEVERITY note;

                real_reload_tvalid <= '0';
                real_reload_tlast <= '0';
                real_reload_tdata <= (OTHERS => '0');
            END LOOP;

            REPORT "Real coefficient reload packet completed"
                SEVERITY note;
        END PROCEDURE;

        PROCEDURE send_imag_reload_packet IS
            VARIABLE coefficient_index : INTEGER;
            VARIABLE timeout_counter : INTEGER;
        BEGIN
            REPORT "Starting imaginary coefficient reload"
                SEVERITY note;

            FOR reload_slot IN 0 TO C_TAP_COUNT - 1 LOOP

                coefficient_index := C_RELOAD_ORDER(reload_slot);

                imag_reload_tdata <= STD_LOGIC_VECTOR(
                    to_signed(
                    C_IMAG_COEFFICIENTS(coefficient_index),
                    imag_reload_tdata'LENGTH
                    )
                    );

                IF reload_slot = C_TAP_COUNT - 1 THEN
                    imag_reload_tlast <= '1';
                ELSE
                    imag_reload_tlast <= '0';
                END IF;

                imag_reload_tvalid <= '1';
                timeout_counter := 0;

                LOOP
                    WAIT UNTIL rising_edge(aclk);

                    EXIT WHEN imag_reload_tready = '1';

                    timeout_counter := timeout_counter + 1;

                    ASSERT timeout_counter < C_TIMEOUT
                    REPORT "Timeout waiting for imaginary reload TREADY"
                        SEVERITY failure;
                END LOOP;

                REPORT "Imag reload slot " &
                    INTEGER'image(reload_slot) &
                    ", coefficient index " &
                    INTEGER'image(coefficient_index) &
                    ", value " &
                    INTEGER'image(
                    C_IMAG_COEFFICIENTS(coefficient_index)
                    )
                    SEVERITY note;

                imag_reload_tvalid <= '0';
                imag_reload_tlast <= '0';
                imag_reload_tdata <= (OTHERS => '0');
            END LOOP;

            REPORT "Imaginary coefficient reload packet completed"
                SEVERITY note;
        END PROCEDURE;

        PROCEDURE send_real_configuration IS
            VARIABLE timeout_counter : INTEGER := 0;
        BEGIN
            -- Select coefficient set 0.
            real_config_tdata <= (OTHERS => '0');
            real_config_tvalid <= '1';

            LOOP
                WAIT UNTIL rising_edge(aclk);

                EXIT WHEN real_config_tready = '1';

                timeout_counter := timeout_counter + 1;

                ASSERT timeout_counter < C_TIMEOUT
                REPORT "Timeout waiting for real config TREADY"
                    SEVERITY failure;
            END LOOP;

            real_config_tvalid <= '0';
            real_config_tdata <= (OTHERS => '0');

            REPORT "Real configuration transaction completed"
                SEVERITY note;
        END PROCEDURE;

        PROCEDURE send_imag_configuration IS
            VARIABLE timeout_counter : INTEGER := 0;
        BEGIN
            -- Select coefficient set 0.
            imag_config_tdata <= (OTHERS => '0');
            imag_config_tvalid <= '1';

            LOOP
                WAIT UNTIL rising_edge(aclk);

                EXIT WHEN imag_config_tready = '1';

                timeout_counter := timeout_counter + 1;

                ASSERT timeout_counter < C_TIMEOUT
                REPORT "Timeout waiting for imaginary config TREADY"
                    SEVERITY failure;
            END LOOP;

            imag_config_tvalid <= '0';
            imag_config_tdata <= (OTHERS => '0');

            REPORT "Imaginary configuration transaction completed"
                SEVERITY note;
        END PROCEDURE;

        PROCEDURE send_parallel_reload_packets IS
            VARIABLE real_coefficient_index : INTEGER;
            VARIABLE imag_coefficient_index : INTEGER;
            VARIABLE real_accepted : BOOLEAN;
            VARIABLE imag_accepted : BOOLEAN;
            VARIABLE timeout_counter : INTEGER;
        BEGIN
            REPORT "Starting parallel coefficient reload"
                SEVERITY note;

            FOR reload_slot IN 0 TO C_TAP_COUNT - 1 LOOP

                real_coefficient_index := C_RELOAD_ORDER(reload_slot);
                imag_coefficient_index := C_RELOAD_ORDER(reload_slot);

                real_reload_tdata <= STD_LOGIC_VECTOR(
                    to_signed(
                    C_REAL_COEFFICIENTS(real_coefficient_index),
                    real_reload_tdata'LENGTH
                    )
                    );

                imag_reload_tdata <= STD_LOGIC_VECTOR(
                    to_signed(
                    C_IMAG_COEFFICIENTS(imag_coefficient_index),
                    imag_reload_tdata'LENGTH
                    )
                    );

                IF reload_slot = C_TAP_COUNT - 1 THEN
                    real_reload_tlast <= '1';
                    imag_reload_tlast <= '1';
                ELSE
                    real_reload_tlast <= '0';
                    imag_reload_tlast <= '0';
                END IF;

                real_reload_tvalid <= '1';
                imag_reload_tvalid <= '1';

                real_accepted := false;
                imag_accepted := false;
                timeout_counter := 0;

                LOOP
                    WAIT UNTIL rising_edge(aclk);

                    IF NOT real_accepted AND real_reload_tready = '1' THEN
                        real_accepted := true;
                        real_reload_tvalid <= '0';
                        real_reload_tlast <= '0';
                        real_reload_tdata <= (OTHERS => '0');
                    END IF;

                    IF NOT imag_accepted AND imag_reload_tready = '1' THEN
                        imag_accepted := true;
                        imag_reload_tvalid <= '0';
                        imag_reload_tlast <= '0';
                        imag_reload_tdata <= (OTHERS => '0');
                    END IF;

                    EXIT WHEN real_accepted AND imag_accepted;

                    timeout_counter := timeout_counter + 1;

                    ASSERT timeout_counter < C_TIMEOUT
                    REPORT "Timeout waiting for parallel reload TREADY"
                        SEVERITY failure;
                END LOOP;

                REPORT "Parallel reload slot " &
                    INTEGER'image(reload_slot) &
                    ", real coefficient index " &
                    INTEGER'image(real_coefficient_index) &
                    ", real value " &
                    INTEGER'image(
                    C_REAL_COEFFICIENTS(real_coefficient_index)
                    ) &
                    ", imag coefficient index " &
                    INTEGER'image(imag_coefficient_index) &
                    ", imag value " &
                    INTEGER'image(
                    C_IMAG_COEFFICIENTS(imag_coefficient_index)
                    )
                    SEVERITY note;
            END LOOP;

            REPORT "Parallel coefficient reload packets completed"
                SEVERITY note;
        END PROCEDURE;

        PROCEDURE send_synchronized_configuration IS
            VARIABLE timeout_counter : INTEGER := 0;
        BEGIN
            REPORT "Starting synchronized configuration commit"
                SEVERITY note;

            real_config_tdata <= (OTHERS => '0');
            imag_config_tdata <= (OTHERS => '0');
            real_config_tvalid <= '1';
            imag_config_tvalid <= '1';

            LOOP
                WAIT UNTIL rising_edge(aclk);

                ASSERT real_config_tready = imag_config_tready
                REPORT "Config TREADY mismatch; configuration would not commit on the same cycle"
                    SEVERITY error;

                EXIT WHEN real_config_tready = '1' AND imag_config_tready = '1';

                timeout_counter := timeout_counter + 1;

                ASSERT timeout_counter < C_TIMEOUT
                REPORT "Timeout waiting for synchronized config TREADY"
                    SEVERITY failure;
            END LOOP;

            real_config_tvalid <= '0';
            imag_config_tvalid <= '0';
            real_config_tdata <= (OTHERS => '0');
            imag_config_tdata <= (OTHERS => '0');

            REPORT "Synchronized configuration commit completed"
                SEVERITY note;
        END PROCEDURE;

        PROCEDURE send_packet_with_reload_during_traffic IS
            VARIABLE sample_index : INTEGER := 0;
            VARIABLE reload_slot : INTEGER := 0;
            VARIABLE coefficient_index : INTEGER := 0;
            VARIABLE timeout_counter : INTEGER := 0;
            VARIABLE data_active : BOOLEAN := false;
            VARIABLE real_reload_active : BOOLEAN := false;
            VARIABLE imag_reload_active : BOOLEAN := false;
            VARIABLE real_config_active : BOOLEAN := false;
            VARIABLE imag_config_active : BOOLEAN := false;
            VARIABLE data_done : BOOLEAN := false;
            VARIABLE reload_done : BOOLEAN := false;
            VARIABLE reload_beat_pending : BOOLEAN := false;
            VARIABLE config_started : BOOLEAN := false;
            VARIABLE config_done : BOOLEAN := false;
            VARIABLE current_real_word : INTEGER := 0;
            VARIABLE current_imag_word : INTEGER := 0;
        BEGIN
            REPORT "Starting sample packet with active coefficient reload"
                SEVERITY note;

            LOOP
                IF NOT data_active AND NOT data_done THEN
                    -- Constant non-zero samples keep the FIR datapath visibly active
                    -- while the reload and config channels are also handshaking.
                    s_axis_tdata <=
                        STD_LOGIC_VECTOR(to_signed(0, 16)) &
                        STD_LOGIC_VECTOR(to_signed(1, 16));

                    IF sample_index = C_ACTIVE_PACKET_LENGTH - 1 THEN
                        s_axis_tlast <= '1';
                    ELSE
                        s_axis_tlast <= '0';
                    END IF;

                    s_axis_tvalid <= '1';
                    data_active := true;
                END IF;

                IF sample_index >= C_RELOAD_START_SAMPLE AND
                    NOT reload_done AND
                    NOT reload_beat_pending THEN

                    IF NOT real_reload_active THEN
                        coefficient_index := C_RELOAD_ORDER(reload_slot);
                        current_real_word :=
                            C_ACTIVE_REAL_COEFFICIENTS(coefficient_index);

                        real_reload_tdata <= STD_LOGIC_VECTOR(
                            to_signed(
                            current_real_word,
                            real_reload_tdata'LENGTH
                            )
                            );

                        IF reload_slot = C_TAP_COUNT - 1 THEN
                            real_reload_tlast <= '1';
                        ELSE
                            real_reload_tlast <= '0';
                        END IF;

                        real_reload_tvalid <= '1';
                        real_reload_active := true;
                    END IF;

                    IF NOT imag_reload_active THEN
                        coefficient_index := C_RELOAD_ORDER(reload_slot);
                        current_imag_word :=
                            C_ACTIVE_IMAG_COEFFICIENTS(coefficient_index);

                        imag_reload_tdata <= STD_LOGIC_VECTOR(
                            to_signed(
                            current_imag_word,
                            imag_reload_tdata'LENGTH
                            )
                            );

                        IF reload_slot = C_TAP_COUNT - 1 THEN
                            imag_reload_tlast <= '1';
                        ELSE
                            imag_reload_tlast <= '0';
                        END IF;

                        imag_reload_tvalid <= '1';
                        imag_reload_active := true;
                    END IF;

                    reload_beat_pending := true;
                END IF;

                IF reload_done AND NOT config_started THEN
                    real_config_tdata <= (OTHERS => '0');
                    imag_config_tdata <= (OTHERS => '0');
                    real_config_tvalid <= '1';
                    imag_config_tvalid <= '1';
                    real_config_active := true;
                    imag_config_active := true;
                    config_started := true;

                    REPORT "Starting config while sample packet remains active"
                        SEVERITY note;
                END IF;

                WAIT UNTIL rising_edge(aclk);

                dbg_active_reload_accept <= '0';

                IF data_active AND s_axis_tready = '1' THEN
                    s_axis_tvalid <= '0';
                    s_axis_tlast <= '0';
                    s_axis_tdata <= (OTHERS => '0');
                    data_active := false;

                    IF sample_index = C_ACTIVE_PACKET_LENGTH - 1 THEN
                        data_done := true;
                    ELSE
                        sample_index := sample_index + 1;
                    END IF;
                END IF;

                IF real_reload_active AND real_reload_tready = '1' THEN
                    real_reload_tvalid <= '0';
                    real_reload_tlast <= '0';
                    real_reload_tdata <= (OTHERS => '0');
                    real_reload_active := false;
                END IF;

                IF imag_reload_active AND imag_reload_tready = '1' THEN
                    imag_reload_tvalid <= '0';
                    imag_reload_tlast <= '0';
                    imag_reload_tdata <= (OTHERS => '0');
                    imag_reload_active := false;
                END IF;

                IF sample_index >= C_RELOAD_START_SAMPLE AND
                    NOT reload_done AND
                    reload_beat_pending AND
                    NOT real_reload_active AND
                    NOT imag_reload_active THEN

                    REPORT "Active reload slot " &
                        INTEGER'image(reload_slot) &
                        " accepted while data packet is active"
                        SEVERITY note;

                    dbg_active_reload_accept <= '1';
                    dbg_active_reload_slot <= reload_slot;
                    dbg_active_reload_real_word <= STD_LOGIC_VECTOR(
                        to_signed(current_real_word, 16)
                        );
                    dbg_active_reload_imag_word <= STD_LOGIC_VECTOR(
                        to_signed(current_imag_word, 16)
                        );

                    IF reload_slot = C_TAP_COUNT - 1 THEN
                        reload_done := true;
                    ELSE
                        reload_slot := reload_slot + 1;
                    END IF;

                    reload_beat_pending := false;
                END IF;

                IF real_config_active AND real_config_tready = '1' THEN
                    real_config_tvalid <= '0';
                    real_config_tdata <= (OTHERS => '0');
                    real_config_active := false;
                END IF;

                IF imag_config_active AND imag_config_tready = '1' THEN
                    imag_config_tvalid <= '0';
                    imag_config_tdata <= (OTHERS => '0');
                    imag_config_active := false;
                END IF;

                IF config_started AND
                    NOT real_config_active AND
                    NOT imag_config_active AND
                    NOT config_done THEN

                    ASSERT NOT data_done
                    REPORT "Config was accepted only after the active data packet ended"
                        SEVERITY error;

                    config_done := true;
                    REPORT "Active-traffic config accepted"
                        SEVERITY note;
                END IF;

                EXIT WHEN data_done AND reload_done AND config_done;

                timeout_counter := timeout_counter + 1;

                ASSERT timeout_counter < C_TIMEOUT
                REPORT "Timeout during active-traffic reload test"
                    SEVERITY failure;
            END LOOP;

            s_axis_tvalid <= '0';
            s_axis_tlast <= '0';
            s_axis_tdata <= (OTHERS => '0');
            real_reload_tvalid <= '0';
            real_reload_tlast <= '0';
            real_reload_tdata <= (OTHERS => '0');
            imag_reload_tvalid <= '0';
            imag_reload_tlast <= '0';
            imag_reload_tdata <= (OTHERS => '0');
            real_config_tvalid <= '0';
            real_config_tdata <= (OTHERS => '0');
            imag_config_tvalid <= '0';
            imag_config_tdata <= (OTHERS => '0');

            REPORT "Sample packet with active coefficient reload completed"
                SEVERITY note;
        END PROCEDURE;

        PROCEDURE wait_for_output_packet IS
            VARIABLE timeout_counter : INTEGER := 0;
        BEGIN
            LOOP
                WAIT UNTIL rising_edge(aclk);

                EXIT WHEN
                m_axis_tvalid = '1' AND
                m_axis_tready = '1' AND
                m_axis_tlast = '1';

                timeout_counter := timeout_counter + 1;

                ASSERT timeout_counter < C_TIMEOUT
                REPORT "Timeout waiting for output packet"
                    SEVERITY failure;
            END LOOP;
        END PROCEDURE;

    BEGIN

        aresetn <= '0';

        s_axis_tvalid <= '0';
        s_axis_tlast <= '0';
        s_axis_tdata <= (OTHERS => '0');

        real_reload_tvalid <= '0';
        real_reload_tlast <= '0';
        real_reload_tdata <= (OTHERS => '0');
        real_config_tvalid <= '0';
        real_config_tdata <= (OTHERS => '0');

        imag_reload_tvalid <= '0';
        imag_reload_tlast <= '0';
        imag_reload_tdata <= (OTHERS => '0');
        imag_config_tvalid <= '0';
        imag_config_tdata <= (OTHERS => '0');

        test_number <= 0;

        wait_clock_cycles(10);

        aresetn <= '1';

        wait_clock_cycles(2);

        -- Test 1:
        -- Initial h = [1+j0, 0+j0, 0+j1]
        test_number <= 1;

        REPORT "Starting test 1 with initial coefficients"
            SEVERITY note;

        send_impulse_packet;

        wait_for_output_packet;

        wait_clock_cycles(5);

        -- Load both FIR coefficient memories in parallel, then activate both
        -- pending coefficient sets with a shared configuration commit.
        send_parallel_reload_packets;
        send_synchronized_configuration;

        wait_clock_cycles(2);

        -- Test 2:
        -- Reloaded h = [2+j0, 0+j0, 0-j1]
        test_number <= 2;

        REPORT "Starting test 2 with reloaded coefficients"
            SEVERITY note;

        send_impulse_packet;

        wait_for_output_packet;

        wait_clock_cycles(5);

        -- Test 3:
        -- Keep sample traffic active while both FIR coefficient memories are
        -- reloaded and the shared configuration commit is accepted.
        test_number <= 3;

        REPORT "Starting test 3: reload while data packet is active"
            SEVERITY note;

        send_packet_with_reload_during_traffic;

        wait_for_output_packet;

        wait_clock_cycles(5);

        -- Test 4:
        -- Coefficients loaded during active traffic:
        -- h = [3+j0, 4-j2, 5-j3, 0+j0, ...]
        test_number <= 4;

        REPORT "Starting test 4 with active-traffic reloaded coefficients"
            SEVERITY note;

        send_impulse_packet;

        wait_for_output_packet;

        wait_clock_cycles(10);

        REPORT "Complex FIR coefficient reload test completed"
            SEVERITY note;

        WAIT;
    END PROCESS;

    output_monitor : PROCESS (aclk)
        VARIABLE output_index : INTEGER := 0;
        VARIABLE output_i : INTEGER;
        VARIABLE output_q : INTEGER;
        VARIABLE output_line : line;
        VARIABLE header_written : BOOLEAN := false;
        VARIABLE expected_last_index : INTEGER;
    BEGIN
        IF rising_edge(aclk) THEN
            IF aresetn = '0' THEN
                output_index := 0;

            ELSIF m_axis_tvalid = '1' AND m_axis_tready = '1' THEN

                IF NOT header_written THEN
                    write(
                    output_line,
                    STRING'(
                    "test_number,sample_index,output_i,output_q,tlast"
                    )
                    );

                    writeline(output_file, output_line);
                    header_written := true;
                END IF;

                output_i := to_integer(
                    signed(m_axis_tdata(39 DOWNTO 0))
                    );

                output_q := to_integer(
                    signed(m_axis_tdata(79 DOWNTO 40))
                    );

                REPORT "Test " &
                    INTEGER'image(test_number) &
                    ", output " &
                    INTEGER'image(output_index) &
                    ": I=" &
                    INTEGER'image(output_i) &
                    ", Q=" &
                    INTEGER'image(output_q) &
                    ", TLAST=" &
                    STD_LOGIC'image(m_axis_tlast);

                write(output_line, test_number);
                write(output_line, STRING'(","));
                write(output_line, output_index);
                write(output_line, STRING'(","));
                write(output_line, output_i);
                write(output_line, STRING'(","));
                write(output_line, output_q);
                write(output_line, STRING'(","));

                IF m_axis_tlast = '1' THEN
                    write(output_line, STRING'("1"));
                ELSE
                    write(output_line, STRING'("0"));
                END IF;

                writeline(output_file, output_line);

                CASE test_number IS

                    WHEN 1 =>
                        -- Initial:
                        -- h = [1+j0, 0+j0, 0+j1]

                        CASE output_index IS
                            WHEN 0 =>
                                ASSERT output_i = 1 AND output_q = 0
                                REPORT
                                    "Test 1 incorrect output at tap 0"
                                    SEVERITY error;

                            WHEN 2 =>
                                ASSERT output_i = 0 AND output_q = 1
                                REPORT
                                    "Test 1 incorrect output at tap 2"
                                    SEVERITY error;

                            WHEN OTHERS =>
                                ASSERT output_i = 0 AND output_q = 0
                                REPORT
                                    "Test 1 unexpected non-zero output at index " &
                                    INTEGER'image(output_index)
                                    SEVERITY error;
                        END CASE;

                    WHEN 2 =>
                        -- Reloaded:
                        -- h = [2+j0, 0+j0, 0-j1]

                        CASE output_index IS
                            WHEN 0 =>
                                ASSERT output_i = 2 AND output_q = 0
                                REPORT
                                    "Test 2 incorrect output at tap 0"
                                    SEVERITY error;

                            WHEN 2 =>
                                ASSERT output_i = 0 AND output_q =- 1
                                REPORT
                                    "Test 2 incorrect output at tap 2"
                                    SEVERITY error;

                            WHEN OTHERS =>
                                ASSERT output_i = 0 AND output_q = 0
                                REPORT
                                    "Test 2 unexpected non-zero output at index " &
                                    INTEGER'image(output_index)
                                    SEVERITY error;
                        END CASE;

                    WHEN 4 =>
                        -- Active-traffic reloaded:
                        -- h = [3+j0, 4-j2, 5-j3, 0+j0, ...]

                        CASE output_index IS
                            WHEN 0 =>
                                ASSERT output_i = 3 AND output_q = 0
                                REPORT
                                    "Test 4 incorrect output at tap 0"
                                    SEVERITY error;

                            WHEN 1 =>
                                ASSERT output_i = 4 AND output_q =- 2
                                REPORT
                                    "Test 4 incorrect output at tap 1"
                                    SEVERITY error;

                            WHEN 2 =>
                                ASSERT output_i = 5 AND output_q =- 3
                                REPORT
                                    "Test 4 incorrect output at tap 2"
                                    SEVERITY error;

                            WHEN OTHERS =>
                                ASSERT output_i = 0 AND output_q = 0
                                REPORT
                                    "Test 4 unexpected non-zero output at index " &
                                    INTEGER'image(output_index)
                                    SEVERITY error;
                        END CASE;

                    WHEN OTHERS =>
                        NULL;
                END CASE;

                IF m_axis_tlast = '1' THEN
                    IF test_number = 3 THEN
                        expected_last_index := C_ACTIVE_PACKET_LENGTH - 1;
                    ELSE
                        expected_last_index := C_PACKET_LENGTH - 1;
                    END IF;

                    ASSERT output_index = expected_last_index
                    REPORT "TLAST received at the wrong output index"
                        SEVERITY error;

                    output_index := 0;
                ELSE
                    output_index := output_index + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;
