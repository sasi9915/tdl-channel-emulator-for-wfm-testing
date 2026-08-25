library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity tb_channel_emulator_axi_top is
end entity;

architecture rtl of tb_channel_emulator_axi_top is

    constant C_TAP_COUNT                  : integer                                         := 128;
    constant C_RELOAD_WORD_COUNT          : integer                                         := 133;
    constant C_PREFETCH_FIFO_DEPTH        : integer                                         := 512;
    constant C_BANK_SET_COUNT             : integer                                         := 2;
    constant C_CONTINUOUS_RELOAD_SET_COUNT : integer                                        := 4;
    constant C_PREFETCH_SET_COUNT         : integer                                         := C_CONTINUOUS_RELOAD_SET_COUNT + C_BANK_SET_COUNT;
    constant C_AXIS_CLK_HZ                : integer                                         := 300_000_000;
    constant C_FU_HZ                      : integer                                         := 6_000;
    constant C_CLK_PERIOD                 : time                                            := 3333 ps;
    constant C_PHASE3_FU_PERIOD_CYCLES    : integer                                         := (C_AXIS_CLK_HZ + C_FU_HZ / 2) / C_FU_HZ;
    constant C_FIR_SAMPLE_PERIOD_CYCLES   : integer                                         := 7;
    constant C_FU_PERIOD_OUTPUT_SAMPLES   : integer                                         := (C_PHASE3_FU_PERIOD_CYCLES + C_FIR_SAMPLE_PERIOD_CYCLES - 1) / C_FIR_SAMPLE_PERIOD_CYCLES;
    constant C_ACTIVE_PACKET_LENGTH : integer := C_CONTINUOUS_RELOAD_SET_COUNT * C_FU_PERIOD_OUTPUT_SAMPLES + C_TAP_COUNT + 512;
    constant C_VERIFY_PACKET_LENGTH       : integer                                         := 25;
    constant C_INPUT_READY_TIMEOUT_CYCLES : integer                                         := 1024;
    constant C_ACTIVE_TEST_TIMEOUT_CYCLES : integer := C_ACTIVE_PACKET_LENGTH + C_CONTINUOUS_RELOAD_SET_COUNT * C_PHASE3_FU_PERIOD_CYCLES + 4096;
    constant C_OUTPUT_PACKET_TIMEOUT_CYCLES : integer := C_ACTIVE_PACKET_LENGTH * 8 + 4096;
    constant C_BACKPRESSURE_SEED          : std_logic_vector(15 downto 0)                   := x"ACE1";
    constant C_AXI_ADDR_WIDTH             : integer                                         := 5;
    constant C_AXI_DATA_WIDTH             : integer                                         := 32;
    constant C_CONTROL_ADDR               : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := "00000";
    constant C_FU_PERIOD_ADDR             : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := "00100";
    constant C_BANK_SETS_ADDR             : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := "01000";
    constant C_IRQ_ENABLE_ADDR            : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := "01100";
    constant C_STATUS_ADDR                : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := "10000";
    constant C_DEBUG_ADDR                 : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := "10100";

    type t_coefficient_array  is array (0 to C_TAP_COUNT - 1) of integer;
    type t_reload_order_array is array (0 to C_RELOAD_WORD_COUNT - 1) of integer range 0 to C_RELOAD_WORD_COUNT - 1;

    -- Replace this with the actual reload order displayed by the FIR Compiler
    -- coefficient reload tab if Vivado reports a different order.
    constant C_RELOAD_ORDER : t_reload_order_array := (
        126, 127, 128, 129, 130, 131, 132,
        119, 120, 121, 122, 123, 124, 125,
        112, 113, 114, 115, 116, 117, 118,
        105, 106, 107, 108, 109, 110, 111,
        98, 99, 100, 101, 102, 103, 104,
        91, 92, 93, 94, 95, 96, 97,
        84, 85, 86, 87, 88, 89, 90,
        77, 78, 79, 80, 81, 82, 83,
        70, 71, 72, 73, 74, 75, 76,
        63, 64, 65, 66, 67, 68, 69,
        56, 57, 58, 59, 60, 61, 62,
        49, 50, 51, 52, 53, 54, 55,
        42, 43, 44, 45, 46, 47, 48,
        35, 36, 37, 38, 39, 40, 41,
        28, 29, 30, 31, 32, 33, 34,
        21, 22, 23, 24, 25, 26, 27,
        14, 15, 16, 17, 18, 19, 20,
        7, 8, 9, 10, 11, 12, 13,
        0, 1, 2, 3, 4, 5, 6
    );

    function reload_real_coefficient(
        set_index         : integer;
        coefficient_index : integer
    ) return integer is
    begin
        case set_index is
            when 0 =>
                case coefficient_index is
                    when 0      => return 3;
                    when 1      => return 4;
                    when 2      => return 5;
                    when others => return 0;
                end case;

            when 1 =>
                case coefficient_index is
                    when 0      => return 1;
                    when 1      => return 2;
                    when 2      => return 3;
                    when others => return 0;
                end case;

            when 2 =>
                case coefficient_index is
                    when 0      => return 5;
                    when 1      => return 1;
                    when 2      => return -2;
                    when others => return 0;
                end case;

            when 3 =>
                case coefficient_index is
                    when 0      => return 7;
                    when 1      => return 8;
                    when 2      => return 9;
                    when others => return 0;
                end case;

            when 4 =>
                case coefficient_index is
                    when 0      => return 2;
                    when 1      => return 4;
                    when 2      => return 6;
                    when others => return 0;
                end case;

            when 5 =>
                case coefficient_index is
                    when 0      => return 9;
                    when 1      => return -4;
                    when 2      => return 2;
                    when others => return 0;
                end case;

            when 6 =>
                case coefficient_index is
                    when 0      => return 4;
                    when 1      => return -1;
                    when 2      => return 7;
                    when others => return 0;
                end case;

            when 7 =>
                case coefficient_index is
                    when 0      => return -3;
                    when 1      => return 5;
                    when 2      => return 1;
                    when others => return 0;
                end case;

            when 8 =>
                case coefficient_index is
                    when 0      => return 6;
                    when 1      => return -2;
                    when 2      => return 5;
                    when others => return 0;
                end case;

            when others =>
                return 0;
        end case;
    end function;

    function reload_imag_coefficient(
        set_index         : integer;
        coefficient_index : integer
    ) return integer is
    begin
        case set_index is
            when 0 =>
                case coefficient_index is
                    when 1      => return -2;
                    when 2      => return -3;
                    when others => return 0;
                end case;

            when 1 =>
                case coefficient_index is
                    when 0      => return 1;
                    when 2      => return -1;
                    when others => return 0;
                end case;

            when 2 =>
                case coefficient_index is
                    when 1      => return 2;
                    when 2      => return -2;
                    when others => return 0;
                end case;

            when 3 =>
                case coefficient_index is
                    when 0      => return -1;
                    when 1      => return -2;
                    when 2      => return -3;
                    when others => return 0;
                end case;

            when 4 =>
                case coefficient_index is
                    when 0      => return 3;
                    when 1      => return 1;
                    when 2      => return -3;
                    when others => return 0;
                end case;

            when 5 =>
                case coefficient_index is
                    when 0      => return 1;
                    when 1      => return -1;
                    when 2      => return 3;
                    when others => return 0;
                end case;

            when 6 =>
                case coefficient_index is
                    when 0      => return -2;
                    when 1      => return 2;
                    when others => return 0;
                end case;

            when 7 =>
                case coefficient_index is
                    when 0      => return 2;
                    when 1      => return -4;
                    when 2      => return 4;
                    when others => return 0;
                end case;

            when 8 =>
                case coefficient_index is
                    when 0      => return -1;
                    when 1      => return 3;
                    when 2      => return -5;
                    when others => return 0;
                end case;

            when others =>
                return 0;
        end case;
    end function;

    function pack_reload_word(
        set_index  : integer;
        word_index : integer
    ) return std_logic_vector is
        variable packed_word       : std_logic_vector(31 downto 0);
        variable coefficient_index : integer range 0 to C_RELOAD_WORD_COUNT - 1;
    begin
        coefficient_index         := C_RELOAD_ORDER(word_index);
        packed_word(31 downto 16) := std_logic_vector(to_signed(reload_real_coefficient(set_index, coefficient_index), 16));
        packed_word(15 downto 0)  := std_logic_vector(to_signed(reload_imag_coefficient(set_index, coefficient_index), 16));
        return packed_word;
    end function;

    signal aclk    : std_logic := '0';
    signal aresetn : std_logic := '0';

    signal s_axis_tvalid : std_logic                     := '0';
    signal s_axis_tready : std_logic;
    signal s_axis_tdata  : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axis_tlast  : std_logic                     := '0';

    signal m_axis_tvalid : std_logic;
    signal m_axis_tready : std_logic := '1';
    signal m_axis_tdata  : std_logic_vector(79 downto 0);
    signal m_axis_tlast  : std_logic;
    signal irq           : std_logic;
    signal block_done_irq_monitor_enable : std_logic := '0';
    signal block_done_irq_pulse_count    : integer   := 0;
    signal block_done_irq_previous       : std_logic := '0';

    signal s00_axi_awaddr  : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0)       := (others => '0');
    signal s00_axi_awprot  : std_logic_vector(2 downto 0)                          := (others => '0');
    signal s00_axi_awvalid : std_logic                                             := '0';
    signal s00_axi_awready : std_logic;
    signal s00_axi_wdata   : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0)       := (others => '0');
    signal s00_axi_wstrb   : std_logic_vector((C_AXI_DATA_WIDTH / 8) - 1 downto 0) := (others => '0');
    signal s00_axi_wvalid  : std_logic                                             := '0';
    signal s00_axi_wready  : std_logic;
    signal s00_axi_bresp   : std_logic_vector(1 downto 0);
    signal s00_axi_bvalid  : std_logic;
    signal s00_axi_bready  : std_logic                                             := '0';
    signal s00_axi_araddr  : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0)       := (others => '0');
    signal s00_axi_arprot  : std_logic_vector(2 downto 0)                          := (others => '0');
    signal s00_axi_arvalid : std_logic                                             := '0';
    signal s00_axi_arready : std_logic;
    signal s00_axi_rdata   : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0);
    signal s00_axi_rresp   : std_logic_vector(1 downto 0);
    signal s00_axi_rvalid  : std_logic;
    signal s00_axi_rready  : std_logic                                             := '0';

    signal coeff_set_tvalid                : std_logic                     := '0';
    signal coeff_set_tready                : std_logic;
    signal coeff_set_tdata                 : std_logic_vector(31 downto 0) := (others => '0');
    signal coeff_set_tlast                 : std_logic                     := '0';
    signal coeff_prefetch_enable           : std_logic                     := '0';
    signal coeff_prefetch_done             : std_logic                     := '0';
    signal coeff_recovery_enable           : std_logic                     := '0';
    signal coeff_recovery_done             : std_logic                     := '0';

    signal dbg_input_accept               : std_logic                                  := '0';
    signal dbg_output_backpressure        : std_logic                                  := '0';

    signal verification_packet_active : std_logic                                  := '0';
    signal current_packet_length      : integer                                    := C_ACTIVE_PACKET_LENGTH;
    signal output_backpressure_enable : std_logic                                  := '0';

    file output_file : text open write_mode is "/home/sasindu/work/TDL_chnannel_emulator_project/tdl-channel-emulator-for-wfm-testing/phase_7_tdl_channel_emulator_with_axi_lite_reg_finalized/misc/phase_7_axi_lite_finalized_complex_channel_output.csv";

begin

    aclk <= not aclk after C_CLK_PERIOD / 2;

    dut : entity work.channel_emulator_axi_top
        generic map(
            G_RELOAD_WORD_COUNT  => C_RELOAD_WORD_COUNT,
            G_BANK_SET_COUNT     => C_BANK_SET_COUNT,
            G_COEFF_WIDTH        => 16,
            G_CONFIG_WIDTH       => 8,
            G_FIFO_DEPTH         => C_PREFETCH_FIFO_DEPTH,
            C_S00_AXI_DATA_WIDTH => C_AXI_DATA_WIDTH,
            C_S00_AXI_ADDR_WIDTH => C_AXI_ADDR_WIDTH
        )
        port map(
            aclk                            => aclk,
            aresetn                         => aresetn,
            s00_axi_awaddr                  => s00_axi_awaddr,
            s00_axi_awprot                  => s00_axi_awprot,
            s00_axi_awvalid                 => s00_axi_awvalid,
            s00_axi_awready                 => s00_axi_awready,
            s00_axi_wdata                   => s00_axi_wdata,
            s00_axi_wstrb                   => s00_axi_wstrb,
            s00_axi_wvalid                  => s00_axi_wvalid,
            s00_axi_wready                  => s00_axi_wready,
            s00_axi_bresp                   => s00_axi_bresp,
            s00_axi_bvalid                  => s00_axi_bvalid,
            s00_axi_bready                  => s00_axi_bready,
            s00_axi_araddr                  => s00_axi_araddr,
            s00_axi_arprot                  => s00_axi_arprot,
            s00_axi_arvalid                 => s00_axi_arvalid,
            s00_axi_arready                 => s00_axi_arready,
            s00_axi_rdata                   => s00_axi_rdata,
            s00_axi_rresp                   => s00_axi_rresp,
            s00_axi_rvalid                  => s00_axi_rvalid,
            s00_axi_rready                  => s00_axi_rready,
            coeff_set_tvalid                => coeff_set_tvalid,
            coeff_set_tready                => coeff_set_tready,
            coeff_set_tdata                 => coeff_set_tdata,
            coeff_set_tlast                 => coeff_set_tlast,
            s_axis_tvalid                   => s_axis_tvalid,
            s_axis_tready                   => s_axis_tready,
            s_axis_tdata                    => s_axis_tdata,
            s_axis_tlast                    => s_axis_tlast,
            m_axis_tvalid                   => m_axis_tvalid,
            m_axis_tready                   => m_axis_tready,
            m_axis_tdata                    => m_axis_tdata,
            m_axis_tlast                    => m_axis_tlast,
            irq                             => irq
        );

    output_backpressure_driver : process(aclk)
        variable lfsr         : std_logic_vector(15 downto 0) := C_BACKPRESSURE_SEED;
        variable feedback_bit : std_logic;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                m_axis_tready           <= '1';
                dbg_output_backpressure <= '0';
                lfsr                    := C_BACKPRESSURE_SEED;
            elsif output_backpressure_enable = '1' then
                feedback_bit := lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10);
                lfsr         := lfsr(14 downto 0) & feedback_bit;

                if lfsr(3 downto 0) = "0000" or lfsr(3 downto 0) = "0111" or lfsr(3 downto 0) = "1011" then
                    m_axis_tready           <= '0';
                    dbg_output_backpressure <= '1';
                else
                    m_axis_tready           <= '1';
                    dbg_output_backpressure <= '0';
                end if;
            else
                m_axis_tready           <= '1';
                dbg_output_backpressure <= '0';
                lfsr                    := C_BACKPRESSURE_SEED;
            end if;
        end if;
    end process;

    block_done_irq_monitor : process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                block_done_irq_pulse_count <= 0;
                block_done_irq_previous    <= '0';
            elsif block_done_irq_monitor_enable = '1' then
                if irq = '1' then
                    block_done_irq_pulse_count <= block_done_irq_pulse_count + 1;

                    assert block_done_irq_previous = '0'
                    report "block_done IRQ stayed high for more than one clock"
                    severity failure;
                end if;

                block_done_irq_previous <= irq;
            else
                block_done_irq_previous <= '0';
            end if;
        end if;
    end process;

    coefficient_prefetch_driver : process
    begin
        coeff_set_tvalid    <= '0';
        coeff_set_tdata     <= (others => '0');
        coeff_set_tlast     <= '0';
        coeff_prefetch_done <= '0';
        coeff_recovery_done <= '0';

        wait until aresetn = '1';
        wait until coeff_prefetch_enable = '1';
        wait until rising_edge(aclk);

        for set_index in 0 to C_PREFETCH_SET_COUNT - 1 loop
            for word_index in 0 to C_RELOAD_WORD_COUNT - 1 loop
                coeff_set_tdata  <= pack_reload_word(set_index, word_index);
                -- TLAST marks a complete ping-pong bank, not every sequencer reload set.
                if (set_index mod C_BANK_SET_COUNT) = C_BANK_SET_COUNT - 1 and word_index = C_RELOAD_WORD_COUNT - 1 then
                    coeff_set_tlast <= '1';
                else
                    coeff_set_tlast <= '0';
                end if;
                coeff_set_tvalid <= '1';

                loop
                    wait until rising_edge(aclk);
                    exit when coeff_set_tready = '1';
                end loop;
            end loop;
        end loop;

        coeff_set_tvalid    <= '0';
        coeff_set_tdata     <= (others => '0');
        coeff_set_tlast     <= '0';
        coeff_prefetch_done <= '1';

        wait until coeff_recovery_enable = '1';
        wait until rising_edge(aclk);

        for set_index in C_PREFETCH_SET_COUNT to C_PREFETCH_SET_COUNT + C_BANK_SET_COUNT - 1 loop
            for word_index in 0 to C_RELOAD_WORD_COUNT - 1 loop
                coeff_set_tdata  <= pack_reload_word(set_index, word_index);

                if (set_index mod C_BANK_SET_COUNT) = C_BANK_SET_COUNT - 1 and word_index = C_RELOAD_WORD_COUNT - 1 then
                    coeff_set_tlast <= '1';
                else
                    coeff_set_tlast <= '0';
                end if;

                coeff_set_tvalid <= '1';

                loop
                    wait until rising_edge(aclk);
                    exit when coeff_set_tready = '1';
                end loop;
            end loop;
        end loop;

        coeff_set_tvalid    <= '0';
        coeff_set_tdata     <= (others => '0');
        coeff_set_tlast     <= '0';
        coeff_recovery_done <= '1';

        wait;
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

        procedure axi_write(
            constant addr : in std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0);
            constant data : in std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0)
        ) is
        begin
            s00_axi_awaddr  <= addr;
            s00_axi_awvalid <= '1';
            s00_axi_wdata   <= data;
            s00_axi_wstrb   <= (others => '1');
            s00_axi_wvalid  <= '1';
            s00_axi_bready  <= '1';

            wait until rising_edge(aclk) and s00_axi_awready = '1' and s00_axi_wready = '1';
            s00_axi_awvalid <= '0';
            s00_axi_wvalid  <= '0';
            s00_axi_wstrb   <= (others => '0');

            wait until rising_edge(aclk) and s00_axi_bvalid = '1';
            assert s00_axi_bresp = "00"
            report "AXI-Lite write response was not OKAY"
            severity failure;

            s00_axi_bready <= '0';
            wait until rising_edge(aclk);
        end procedure;

        procedure axi_write_aw_first(
            constant addr : in std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0);
            constant data : in std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0)
        ) is
        begin
            s00_axi_awaddr  <= addr;
            s00_axi_awvalid <= '1';
            s00_axi_bready  <= '1';

            wait until rising_edge(aclk) and s00_axi_awready = '1';
            s00_axi_awvalid <= '0';
            wait_clock_cycles(2);

            s00_axi_wdata  <= data;
            s00_axi_wstrb  <= (others => '1');
            s00_axi_wvalid <= '1';

            wait until rising_edge(aclk) and s00_axi_wready = '1';
            s00_axi_wvalid <= '0';
            s00_axi_wstrb  <= (others => '0');

            wait until rising_edge(aclk) and s00_axi_bvalid = '1';
            assert s00_axi_bresp = "00"
            report "AXI-Lite AW-first write response was not OKAY"
            severity failure;

            s00_axi_bready <= '0';
            wait until rising_edge(aclk);
        end procedure;

        procedure axi_write_w_first(
            constant addr : in std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0);
            constant data : in std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0)
        ) is
        begin
            s00_axi_wdata  <= data;
            s00_axi_wstrb  <= (others => '1');
            s00_axi_wvalid <= '1';
            s00_axi_bready <= '1';

            wait until rising_edge(aclk) and s00_axi_wready = '1';
            s00_axi_wvalid <= '0';
            s00_axi_wstrb  <= (others => '0');
            wait_clock_cycles(2);

            s00_axi_awaddr  <= addr;
            s00_axi_awvalid <= '1';

            wait until rising_edge(aclk) and s00_axi_awready = '1';
            s00_axi_awvalid <= '0';

            wait until rising_edge(aclk) and s00_axi_bvalid = '1';
            assert s00_axi_bresp = "00"
            report "AXI-Lite W-first write response was not OKAY"
            severity failure;

            s00_axi_bready <= '0';
            wait until rising_edge(aclk);
        end procedure;

        procedure axi_read(
            constant addr : in  std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0);
            variable data : out std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0)
        ) is
        begin
            s00_axi_araddr  <= addr;
            s00_axi_arvalid <= '1';
            s00_axi_rready  <= '1';

            wait until rising_edge(aclk) and s00_axi_arready = '1';
            s00_axi_arvalid <= '0';

            wait until rising_edge(aclk) and s00_axi_rvalid = '1';
            assert s00_axi_rresp = "00"
            report "AXI-Lite read response was not OKAY"
            severity failure;

            data := s00_axi_rdata;
            s00_axi_rready <= '0';
            wait until rising_edge(aclk);
        end procedure;

        procedure send_complex_sample(
            constant i_value    : integer;
            constant q_value    : integer;
            constant last_value : std_logic
        ) is
            variable timeout_counter : integer := 0;
        begin
            s_axis_tdata  <= std_logic_vector(to_signed(q_value, 16)) & std_logic_vector(to_signed(i_value, 16));
            s_axis_tlast  <= last_value;
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
            s_axis_tlast  <= '0';
            s_axis_tdata  <= (others => '0');
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
            variable sample_index    : integer := 0;
            variable timeout_counter : integer := 0;
            variable data_active     : boolean := false;
            variable data_done       : boolean := false;
            variable last_sample      : boolean := false;
            variable wait_pause_done  : boolean := false;
            variable reload_pause_done : boolean := false;
            variable pause_timeout_counter : integer := 0;
            variable pause_status_word : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0);
        begin
            report "Starting the Phase-7 AXI-Lite controlled active-traffic test"
            severity note;

            loop
                dbg_input_accept               <= '0';

                if not data_active and not wait_pause_done and sample_index >= C_FU_PERIOD_OUTPUT_SAMPLES / 4 then
                    report "Pausing AXI-Lite enable while the sequencer is waiting for the first Fu tick"
                    severity note;

                    axi_write(C_CONTROL_ADDR, x"00000000");
                    wait_clock_cycles(256);
                    axi_read(C_STATUS_ADDR, pause_status_word);
                    assert pause_status_word(0) = '0'
                    report "Sequencer became active while enable was paused before the first Fu tick"
                    severity failure;
                    assert pause_status_word(2) = '0' and pause_status_word(3) = '0' and pause_status_word(6) = '0' and pause_status_word(7) = '0'
                    report "Pause-before-Fu test raised reload/timing/write error bits"
                    severity failure;

                    axi_write(C_CONTROL_ADDR, x"00000001");
                    wait_pause_done := true;
                end if;

                if not data_active and not reload_pause_done and sample_index >= C_FU_PERIOD_OUTPUT_SAMPLES then
                    pause_timeout_counter := 0;

                    loop
                        axi_read(C_STATUS_ADDR, pause_status_word);
                        exit when pause_status_word(0) = '1';
                        wait_clock_cycles(1);
                        pause_timeout_counter := pause_timeout_counter + 1;

                        assert pause_timeout_counter < C_PHASE3_FU_PERIOD_CYCLES
                        report "Timeout waiting for reload activity before active-update pause test"
                        severity failure;
                    end loop;

                    report "Pausing AXI-Lite enable during an active reload/config update"
                    severity note;

                    axi_write(C_CONTROL_ADDR, x"00000000");
                    pause_timeout_counter := 0;

                    loop
                        axi_read(C_STATUS_ADDR, pause_status_word);
                        exit when pause_status_word(0) = '0';
                        wait_clock_cycles(1);
                        pause_timeout_counter := pause_timeout_counter + 1;

                        assert pause_timeout_counter < C_INPUT_READY_TIMEOUT_CYCLES
                        report "Reload/config update did not finish after enable was paused"
                        severity failure;
                    end loop;

                    wait_clock_cycles(256);
                    axi_read(C_STATUS_ADDR, pause_status_word);
                    assert pause_status_word(2) = '0' and pause_status_word(3) = '0' and pause_status_word(6) = '0' and pause_status_word(7) = '0'
                    report "Pause-during-update test raised reload/timing/write error bits"
                    severity failure;

                    axi_write(C_CONTROL_ADDR, x"00000001");
                    reload_pause_done := true;
                end if;

                if not data_active and not data_done then
                    s_axis_tdata <= std_logic_vector(to_signed(0, 16)) & std_logic_vector(to_signed(1, 16));

                    last_sample := sample_index = C_ACTIVE_PACKET_LENGTH - 1;

                    if last_sample then
                        s_axis_tlast <= '1';
                    else
                        s_axis_tlast <= '0';
                    end if;

                    s_axis_tvalid <= '1';
                    data_active   := true;
                end if;

                wait until rising_edge(aclk);

                if data_active and s_axis_tready = '1' then
                    dbg_input_accept <= '1';
                    s_axis_tvalid    <= '0';
                    s_axis_tlast     <= '0';
                    s_axis_tdata     <= (others => '0');
                    data_active      := false;

                    if last_sample then
                        data_done             := true;
                        current_packet_length <= sample_index + 1;
                    else
                        sample_index := sample_index + 1;
                    end if;
                end if;

                exit when data_done;

                timeout_counter := timeout_counter + 1;

                assert timeout_counter < C_ACTIVE_TEST_TIMEOUT_CYCLES
                report "Timeout during the Phase-7 active-traffic test"
                severity failure;
            end loop;

            s_axis_tvalid <= '0';
            s_axis_tlast  <= '0';
            s_axis_tdata  <= (others => '0');

            report "Phase-7 active-traffic packet completed"
            severity note;
        end procedure;

        procedure wait_for_output_packet is
            variable timeout_counter : integer := 0;
            variable valid_seen      : boolean := false;
            variable ready_low_seen  : boolean := false;
            variable tlast_seen      : boolean := false;
            variable handshake_count : integer := 0;
        begin
            loop
                wait until rising_edge(aclk);

                if m_axis_tvalid = '1' then
                    valid_seen := true;
                end if;

                if m_axis_tready = '0' then
                    ready_low_seen := true;
                end if;

                if m_axis_tlast = '1' then
                    tlast_seen := true;
                end if;

                if m_axis_tvalid = '1' and m_axis_tready = '1' then
                    handshake_count := handshake_count + 1;
                end if;

                exit when m_axis_tvalid = '1' and m_axis_tready = '1' and m_axis_tlast = '1';

                timeout_counter := timeout_counter + 1;

                if timeout_counter >= C_OUTPUT_PACKET_TIMEOUT_CYCLES then
                    report "Output timeout diagnostics: valid_seen=" & boolean'image(valid_seen) &
                           ", ready_low_seen=" & boolean'image(ready_low_seen) &
                           ", tlast_seen=" & boolean'image(tlast_seen) &
                           ", handshake_count=" & integer'image(handshake_count) &
                           ", s_axis_tready=" & std_logic'image(s_axis_tready) &
                           ", irq=" & std_logic'image(irq)
                    severity note;

                    assert false
                    report "Timeout waiting for output packet"
                    severity failure;
                end if;
            end loop;
        end procedure;

        variable status_word : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0);
        variable readback_word : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0);
        variable recovery_timeout_counter : integer := 0;

    begin
        aresetn                    <= '0';
        s_axis_tvalid              <= '0';
        s_axis_tlast               <= '0';
        s_axis_tdata               <= (others => '0');
        s00_axi_awaddr             <= (others => '0');
        s00_axi_awvalid            <= '0';
        s00_axi_wdata              <= (others => '0');
        s00_axi_wstrb              <= (others => '0');
        s00_axi_wvalid             <= '0';
        s00_axi_bready             <= '0';
        s00_axi_araddr             <= (others => '0');
        s00_axi_arvalid            <= '0';
        s00_axi_rready             <= '0';
        coeff_prefetch_enable      <= '0';
        block_done_irq_monitor_enable <= '0';
        verification_packet_active <= '0';
        current_packet_length      <= C_ACTIVE_PACKET_LENGTH;
        output_backpressure_enable <= '0';

        wait_clock_cycles(10);
        aresetn               <= '1';
        wait for 2000 ns;

        axi_write(C_FU_PERIOD_ADDR, x"0000006F");
        axi_read(C_FU_PERIOD_ADDR, readback_word);
        assert readback_word = x"0000006F"
        report "AXI-Lite together write/readback failed for FU_PERIOD"
        severity failure;

        axi_write_aw_first(C_BANK_SETS_ADDR, x"00000005");
        axi_read(C_BANK_SETS_ADDR, readback_word);
        assert readback_word = x"00000005"
        report "AXI-Lite AW-first write/readback failed for BANK_SETS"
        severity failure;

        axi_write_w_first(C_FU_PERIOD_ADDR, x"000000DE");
        axi_read(C_FU_PERIOD_ADDR, readback_word);
        assert readback_word = x"000000DE"
        report "AXI-Lite W-first write/readback failed for FU_PERIOD"
        severity failure;

        axi_read(C_BANK_SETS_ADDR, readback_word);
        assert readback_word = x"00000005"
        report "AXI-Lite W-first write corrupted the previous BANK_SETS address"
        severity failure;

        axi_write(C_IRQ_ENABLE_ADDR, x"0000003F");
        axi_read(C_IRQ_ENABLE_ADDR, readback_word);
        assert readback_word = x"0000003F"
        report "AXI-Lite write/readback failed for IRQ_ENABLE"
        severity failure;

        -- Configure setup-time parameters while the coefficient-update engine is paused.
        axi_write(C_CONTROL_ADDR, x"00000000");
        axi_write(C_IRQ_ENABLE_ADDR, x"00000000");
        axi_write(C_FU_PERIOD_ADDR, std_logic_vector(to_unsigned(C_PHASE3_FU_PERIOD_CYCLES, C_AXI_DATA_WIDTH)));
        axi_write(C_BANK_SETS_ADDR, std_logic_vector(to_unsigned(C_BANK_SET_COUNT, C_AXI_DATA_WIDTH)));
        coeff_prefetch_enable <= '1';

        recovery_timeout_counter := 0;
        loop
            axi_read(C_STATUS_ADDR, status_word);
            exit when status_word(4) = '1';
            wait_clock_cycles(1);
            recovery_timeout_counter := recovery_timeout_counter + 1;

            assert recovery_timeout_counter < C_INPUT_READY_TIMEOUT_CYCLES
            report "Timeout waiting for the first coefficient bank before enabling the sequencer"
            severity failure;
        end loop;

        axi_read(C_DEBUG_ADDR, readback_word);
        assert readback_word(4) = '1'
        report "DEBUG did not report bank0_ready after the first coefficient bank was filled"
        severity failure;
        assert readback_word(3) = '0'
        report "DEBUG active_bank did not report bank 0 after the first coefficient bank was filled"
        severity failure;

        axi_write(C_IRQ_ENABLE_ADDR, x"00000001");
        block_done_irq_monitor_enable <= '1';
        axi_write(C_CONTROL_ADDR, x"00000001");
        wait_clock_cycles(2);

        verification_packet_active <= '0';
        current_packet_length      <= C_ACTIVE_PACKET_LENGTH;
        output_backpressure_enable <= '1';
        send_active_packet_with_sequencer;
        block_done_irq_monitor_enable <= '0';
        axi_write(C_IRQ_ENABLE_ADDR, x"00000000");
        wait_clock_cycles(1);

        axi_read(C_STATUS_ADDR, status_word);
        report "AXI status after active packet: active=" & std_logic'image(status_word(0)) &
               ", block_done=" & std_logic'image(status_word(1)) &
               ", missed_refill=" & std_logic'image(status_word(2)) &
               ", reload_timing_error=" & std_logic'image(status_word(3)) &
               ", active_set_available=" & std_logic'image(status_word(4)) &
               ", bank_underrun=" & std_logic'image(status_word(5)) &
               ", bank_write_error=" & std_logic'image(status_word(6)) &
               ", fir_reload_error=" & std_logic'image(status_word(7))
        severity note;
        assert block_done_irq_pulse_count = C_CONTINUOUS_RELOAD_SET_COUNT / C_BANK_SET_COUNT
        report "block_done did not generate the expected number of one-clock IRQ pulses"
        severity failure;
        assert status_word(2) = '0' and status_word(3) = '0' and status_word(6) = '0' and status_word(7) = '0'
        report "AXI status reported reload/timing/write error bits after the continuous active packet"
        severity failure;
        assert irq = '0'
        report "IRQ asserted even though IRQ_ENABLE masked all sources"
        severity failure;

        assert coeff_prefetch_done = '1'
        report "Coefficient prefetch stream did not finish during the active packet"
        severity failure;

        axi_write(C_CONTROL_ADDR, x"00000000");
        wait_for_output_packet;
        output_backpressure_enable <= '0';
        wait_clock_cycles(5);

        if status_word(5) = '1' then
            report "Ping-pong bank underrun observed after finite coefficient input; sending a recovery bank"
            severity note;

            axi_write(C_IRQ_ENABLE_ADDR, x"0000003E");
            wait_clock_cycles(1);
            assert irq = '1'
            report "IRQ did not assert when bank_underrun was enabled in IRQ_ENABLE"
            severity failure;

            recovery_timeout_counter := 0;
            loop
                axi_read(C_STATUS_ADDR, status_word);
                exit when status_word(0) = '0';
                wait_clock_cycles(1);
                recovery_timeout_counter := recovery_timeout_counter + 1;

                assert recovery_timeout_counter < C_INPUT_READY_TIMEOUT_CYCLES
                report "Reload/config update did not finish before the underrun recovery test"
                severity failure;
            end loop;

            coeff_recovery_enable <= '1';

            recovery_timeout_counter := 0;
            loop
                wait until rising_edge(aclk);
                exit when coeff_recovery_done = '1';
                recovery_timeout_counter := recovery_timeout_counter + 1;

                assert recovery_timeout_counter < C_INPUT_READY_TIMEOUT_CYCLES
                report "Timeout waiting for the recovery coefficient bank to be accepted"
                severity failure;
            end loop;

            recovery_timeout_counter := 0;
            loop
                axi_read(C_STATUS_ADDR, status_word);
                exit when status_word(5) = '0';
                wait_clock_cycles(1);
                recovery_timeout_counter := recovery_timeout_counter + 1;

                assert recovery_timeout_counter < C_PHASE3_FU_PERIOD_CYCLES
                report "Ping-pong bank underrun did not clear after the recovery bank became ready"
                severity failure;
            end loop;

            wait_clock_cycles(1);
            assert irq = '0'
            report "IRQ stayed asserted after the enabled bank_underrun source cleared"
            severity failure;

            assert status_word(2) = '0' and status_word(3) = '0' and status_word(6) = '0' and status_word(7) = '0'
            report "Underrun recovery test raised reload/timing/write error bits"
            severity failure;

            report "Ping-pong bank underrun cleared after the recovery bank was written"
            severity note;
        end if;

        -- Flush the FIR delay line so the following impulse measures only the
        -- committed coefficient set, not leftover samples from the active packet.
        verification_packet_active <= '0';
        current_packet_length      <= C_TAP_COUNT;
        send_zero_flush_packet;
        wait_for_output_packet;
        wait_clock_cycles(5);

        verification_packet_active <= '1';
        current_packet_length      <= C_VERIFY_PACKET_LENGTH;
        send_verification_impulse;
        wait_for_output_packet;
        wait_clock_cycles(10);

        report "Phase-7 continuous AXI-Lite sequencer-to-channel-path test completed"
        severity note;

        axi_write(C_CONTROL_ADDR, x"00000000");
        wait_clock_cycles(5);

        wait;
    end process;

    output_monitor : process(aclk)
        variable output_index        : integer := 0;
        variable output_i            : integer;
        variable output_q            : integer;
        variable expected_last_index : integer;
        variable expected_i          : integer;
        variable expected_q          : integer;
        variable output_line         : line;
        variable header_written      : boolean := false;
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

                output_i   := to_integer(signed(m_axis_tdata(39 downto 0)));
                output_q   := to_integer(signed(m_axis_tdata(79 downto 40)));
                expected_i := 0;
                expected_q := 0;

                if verification_packet_active = '1' then
                    case output_index is
                        when 0 =>
                            expected_i := 7;
                            expected_q := -1;

                        when 1 =>
                            expected_i := 8;
                            expected_q := -2;

                        when 2 =>
                            expected_i := 9;
                            expected_q := -3;

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
                    report "Phase-7 channel output " & integer'image(output_index) & ": I=" & integer'image(output_i) & ", Q=" & integer'image(output_q) & ", TLAST=" & std_logic'image(m_axis_tlast);
                end if;

                if verification_packet_active = '1' then
                    case output_index is
                        when 0 =>
                            assert output_i = 7 and output_q = -1
                            report "Verification impulse mismatch at tap 0"
                            severity error;

                        when 1 =>
                            assert output_i = 8 and output_q = -2
                            report "Verification impulse mismatch at tap 1"
                            severity error;

                        when 2 =>
                            assert output_i = 9 and output_q = -3
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
