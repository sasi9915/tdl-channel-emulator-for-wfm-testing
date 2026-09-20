library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.env.all;

entity tb_full_axi_fir_reload_usedw is
end entity;

architecture sim of tb_full_axi_fir_reload_usedw is

    constant C_CLK_PERIOD        : time    := 3333 ps;
    constant C_RELOAD_WORD_COUNT : integer := 32;
    constant C_SET_COUNT         : integer := 5;
    constant C_REFILL_THRESHOLD_SETS : integer := 2;
    constant C_FU_PERIOD_6KHZ_CYCLES : integer := 50000;
    constant C_FU_PERIOD_4KHZ_CYCLES : integer := 75000;
    constant C_FU_PERIOD_CYCLES      : integer := C_FU_PERIOD_6KHZ_CYCLES;
    constant C_TIMEOUT_CYCLES        : integer := (C_SET_COUNT + 2) * C_FU_PERIOD_CYCLES;
    constant C_IQ_STREAM_ALWAYS_ON   : boolean := true;

    constant C_AXI_DATA_WIDTH : integer := 32;
    constant C_AXI_ADDR_WIDTH : integer := 32;
    constant C_CONTROL_ADDR   : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := x"00000000";
    constant C_FU_PERIOD_ADDR : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := x"00000004";
    constant C_BANK_SETS_ADDR : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := x"00000008";
    constant C_IRQ_ENABLE_ADDR : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := x"0000000C";
    constant C_STATUS_ADDR    : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := x"00000010";
    constant C_REFILL_THRESHOLD_ADDR : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := x"0000001C";
    constant C_IRQ_PENDING_ADDR : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := x"00000020";
    constant C_IRQ_CLEAR_ADDR   : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := x"00000024";

    signal aclk    : std_logic := '0';
    signal aresetn : std_logic := '0';

    signal s00_axi_awaddr  : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal s00_axi_awprot  : std_logic_vector(2 downto 0) := (others => '0');
    signal s00_axi_awvalid : std_logic := '0';
    signal s00_axi_awready : std_logic;
    signal s00_axi_wdata   : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0) := (others => '0');
    signal s00_axi_wstrb   : std_logic_vector((C_AXI_DATA_WIDTH / 8) - 1 downto 0) := (others => '0');
    signal s00_axi_wvalid  : std_logic := '0';
    signal s00_axi_wready  : std_logic;
    signal s00_axi_bresp   : std_logic_vector(1 downto 0);
    signal s00_axi_bvalid  : std_logic;
    signal s00_axi_bready  : std_logic := '0';
    signal s00_axi_araddr  : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal s00_axi_arprot  : std_logic_vector(2 downto 0) := (others => '0');
    signal s00_axi_arvalid : std_logic := '0';
    signal s00_axi_arready : std_logic;
    signal s00_axi_rdata   : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0);
    signal s00_axi_rresp   : std_logic_vector(1 downto 0);
    signal s00_axi_rvalid  : std_logic;
    signal s00_axi_rready  : std_logic := '0';

    signal s_axis_coeff_tvalid : std_logic := '0';
    signal s_axis_coeff_tready : std_logic;
    signal s_axis_coeff_tdata  : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axis_coeff_tkeep  : std_logic_vector(3 downto 0) := (others => '0');
    signal s_axis_coeff_tlast  : std_logic := '0';

    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tready : std_logic;
    signal s_axis_tdata  : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axis_tkeep  : std_logic_vector(3 downto 0) := (others => '0');
    signal s_axis_tlast  : std_logic := '0';

    signal m_axis_tvalid : std_logic;
    signal m_axis_tready : std_logic := '1';
    signal m_axis_tdata  : std_logic_vector(127 downto 0);
    signal m_axis_tkeep  : std_logic_vector(15 downto 0);
    signal m_axis_tlast  : std_logic;
    signal irq           : std_logic;

    signal reload_busy          : std_logic;
    signal reload_done          : std_logic;
    signal dbg_reload_valid     : std_logic;
    signal dbg_reload_combined_ready : std_logic;
    signal dbg_reload_real_ready : std_logic;
    signal dbg_reload_imag_ready : std_logic;
    signal dbg_reload_last      : std_logic;
    signal dbg_reload_real_data : std_logic_vector(15 downto 0);
    signal dbg_reload_imag_data : std_logic_vector(15 downto 0);
    signal dbg_fir_real_reload_tlast_missing    : std_logic;
    signal dbg_fir_real_reload_tlast_unexpected : std_logic;
    signal dbg_fir_imag_reload_tlast_missing    : std_logic;
    signal dbg_fir_imag_reload_tlast_unexpected : std_logic;
    signal dbg_config_valid     : std_logic;
    signal dbg_config_ready     : std_logic;
    signal dbg_fu_tick          : std_logic;
    signal dbg_state            : std_logic_vector(2 downto 0);
    signal dbg_seq_enable       : std_logic;
    signal dbg_next_state       : std_logic_vector(2 downto 0);
    signal dbg_reload_accept    : std_logic;
    signal dbg_config_accept    : std_logic;
    signal dbg_timing_fault     : std_logic;
    signal dbg_reload_word_index : std_logic_vector(15 downto 0);
    signal dbg_reload_set_index  : std_logic_vector(15 downto 0);
    signal dbg_reload_timing_error : std_logic;
    signal dbg_fir_reload_error : std_logic;
    signal dbg_active_set_available : std_logic;
    signal dbg_active_bank      : std_logic;
    signal dbg_bank0_ready      : std_logic;
    signal dbg_bank1_ready      : std_logic;
    signal dbg_seq_fifo_usedw   : std_logic_vector(15 downto 0);
    signal dbg_seq_fifo_has_set : std_logic;
    signal dbg_seq_input_ready  : std_logic;
    signal dbg_refill_request_pulse : std_logic;

    signal iq_stream_enable : std_logic := '0';
    signal iq_sample_count  : unsigned(15 downto 0) := (others => '0');
    signal refill_request_pulse_count : integer := 0;
    signal external_irq_high_count : integer := 0;
    signal sim_cycle_count : integer := 0;

    impure function usedw return integer is
    begin
        return to_integer(unsigned(dbg_seq_fifo_usedw));
    end function;

    impure function state_id return integer is
    begin
        return to_integer(unsigned(dbg_state));
    end function;

    function pack_coeff(
        constant set_index  : integer;
        constant word_index : integer
    ) return std_logic_vector is
        variable packed : std_logic_vector(31 downto 0);
    begin
        packed(31 downto 16) := std_logic_vector(to_signed((set_index + 1) * 100 + word_index, 16));
        packed(15 downto 0)  := std_logic_vector(to_signed(-((set_index + 1) * 100 + word_index), 16));
        return packed;
    end function;

begin

    aclk <= not aclk after C_CLK_PERIOD / 2;

    dut : entity work.channel_emulator_axi_top
        generic map(
            G_RELOAD_WORD_COUNT  => C_RELOAD_WORD_COUNT,
            G_BANK_SET_COUNT     => C_SET_COUNT,
            G_MAX_SETS_PER_BANK  => 600,
            G_COEFF_WIDTH        => 16,
            G_CONFIG_WIDTH       => 8,
            G_FIFO_DEPTH         => 512,
            C_S00_AXI_DATA_WIDTH => C_AXI_DATA_WIDTH,
            C_S00_AXI_ADDR_WIDTH => C_AXI_ADDR_WIDTH
        )
        port map(
            aclk                                  => aclk,
            aresetn                               => aresetn,
            s00_axi_awaddr                        => s00_axi_awaddr,
            s00_axi_awprot                        => s00_axi_awprot,
            s00_axi_awvalid                       => s00_axi_awvalid,
            s00_axi_awready                       => s00_axi_awready,
            s00_axi_wdata                         => s00_axi_wdata,
            s00_axi_wstrb                         => s00_axi_wstrb,
            s00_axi_wvalid                        => s00_axi_wvalid,
            s00_axi_wready                        => s00_axi_wready,
            s00_axi_bresp                         => s00_axi_bresp,
            s00_axi_bvalid                        => s00_axi_bvalid,
            s00_axi_bready                        => s00_axi_bready,
            s00_axi_araddr                        => s00_axi_araddr,
            s00_axi_arprot                        => s00_axi_arprot,
            s00_axi_arvalid                       => s00_axi_arvalid,
            s00_axi_arready                       => s00_axi_arready,
            s00_axi_rdata                         => s00_axi_rdata,
            s00_axi_rresp                         => s00_axi_rresp,
            s00_axi_rvalid                        => s00_axi_rvalid,
            s00_axi_rready                        => s00_axi_rready,
            s_axis_coeff_tvalid                   => s_axis_coeff_tvalid,
            s_axis_coeff_tready                   => s_axis_coeff_tready,
            s_axis_coeff_tdata                    => s_axis_coeff_tdata,
            s_axis_coeff_tkeep                    => s_axis_coeff_tkeep,
            s_axis_coeff_tlast                    => s_axis_coeff_tlast,
            s_axis_tvalid                         => s_axis_tvalid,
            s_axis_tready                         => s_axis_tready,
            s_axis_tdata                          => s_axis_tdata,
            s_axis_tkeep                          => s_axis_tkeep,
            s_axis_tlast                          => s_axis_tlast,
            m_axis_tvalid                         => m_axis_tvalid,
            m_axis_tready                         => m_axis_tready,
            m_axis_tdata                          => m_axis_tdata,
            m_axis_tkeep                          => m_axis_tkeep,
            m_axis_tlast                          => m_axis_tlast,
            reload_busy_o                         => reload_busy,
            reload_done_o                         => reload_done,
            dbg_reload_valid_o                    => dbg_reload_valid,
            dbg_reload_combined_ready_o           => dbg_reload_combined_ready,
            dbg_reload_real_ready_o               => dbg_reload_real_ready,
            dbg_reload_imag_ready_o               => dbg_reload_imag_ready,
            dbg_reload_last_o                     => dbg_reload_last,
            dbg_reload_real_data_o                => dbg_reload_real_data,
            dbg_reload_imag_data_o                => dbg_reload_imag_data,
            dbg_fir_real_reload_tlast_missing_o   => dbg_fir_real_reload_tlast_missing,
            dbg_fir_real_reload_tlast_unexpected_o => dbg_fir_real_reload_tlast_unexpected,
            dbg_fir_imag_reload_tlast_missing_o   => dbg_fir_imag_reload_tlast_missing,
            dbg_fir_imag_reload_tlast_unexpected_o => dbg_fir_imag_reload_tlast_unexpected,
            dbg_config_valid_o                    => dbg_config_valid,
            dbg_config_ready_o                    => dbg_config_ready,
            dbg_fu_tick_o                         => dbg_fu_tick,
            dbg_state_o                           => dbg_state,
            dbg_seq_enable_o                      => dbg_seq_enable,
            dbg_next_state_o                      => dbg_next_state,
            dbg_reload_accept_o                   => dbg_reload_accept,
            dbg_config_accept_o                   => dbg_config_accept,
            dbg_timing_fault_o                    => dbg_timing_fault,
            dbg_reload_word_index_o               => dbg_reload_word_index,
            dbg_reload_set_index_o                => dbg_reload_set_index,
            dbg_reload_timing_error_o             => dbg_reload_timing_error,
            dbg_fir_reload_error_o                => dbg_fir_reload_error,
            dbg_active_set_available_o            => dbg_active_set_available,
            dbg_active_bank_o                     => dbg_active_bank,
            dbg_bank0_ready_o                     => dbg_bank0_ready,
            dbg_bank1_ready_o                     => dbg_bank1_ready,
            dbg_seq_fifo_usedw_o                  => dbg_seq_fifo_usedw,
            dbg_seq_fifo_has_set_o                => dbg_seq_fifo_has_set,
            dbg_seq_input_ready_o                 => dbg_seq_input_ready,
            dbg_refill_request_pulse_o            => dbg_refill_request_pulse,
            irq                                   => irq
        );

    iq_driver : process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                s_axis_tvalid <= '0';
                s_axis_tdata  <= (others => '0');
                s_axis_tkeep  <= (others => '0');
                s_axis_tlast  <= '0';
                iq_sample_count <= (others => '0');
            else
                s_axis_tkeep <= (others => '1');
                s_axis_tlast <= '0';

                if iq_stream_enable = '1' then
                    s_axis_tvalid <= '1';

                    if s_axis_tready = '1' then
                        iq_sample_count <= iq_sample_count + 1;
                        s_axis_tdata(15 downto 0)  <= std_logic_vector(iq_sample_count);
                        s_axis_tdata(31 downto 16) <= std_logic_vector(not iq_sample_count);
                    end if;
                else
                    s_axis_tvalid <= '0';
                end if;
            end if;
        end if;
    end process;

    monitor : process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                sim_cycle_count <= 0;
                refill_request_pulse_count <= 0;
                external_irq_high_count <= 0;
            else
                sim_cycle_count <= sim_cycle_count + 1;

                if dbg_refill_request_pulse = '1' then
                    refill_request_pulse_count <= refill_request_pulse_count + 1;
                end if;

                if irq = '1' then
                    external_irq_high_count <= external_irq_high_count + 1;
                end if;

                if dbg_fu_tick = '1' then
                    report "FU tick: usedw=" & integer'image(usedw) &
                           ", state=" & integer'image(state_id) &
                           ", next=" & integer'image(to_integer(unsigned(dbg_next_state))) &
                           ", reload_ready=" & std_logic'image(dbg_reload_combined_ready) &
                           ", config_ready=" & std_logic'image(dbg_config_ready)
                    severity note;
                end if;

                if dbg_reload_accept = '1' then
                    report "reload_accept: usedw=" & integer'image(usedw) &
                           ", word_index=" & integer'image(to_integer(unsigned(dbg_reload_word_index))) &
                           ", last=" & std_logic'image(dbg_reload_last)
                    severity note;
                end if;

                if dbg_config_accept = '1' then
                    report "config_accept: usedw=" & integer'image(usedw) &
                           ", set_index=" & integer'image(to_integer(unsigned(dbg_reload_set_index)))
                    severity note;
                end if;

                if reload_done = '1' then
                    report "reload_set_done: usedw=" & integer'image(usedw) &
                           ", set_index=" & integer'image(to_integer(unsigned(dbg_reload_set_index))) &
                           ", state=" & integer'image(state_id)
                    severity note;
                end if;
            end if;
        end if;
    end process;

    stimulus : process
        variable status_word : std_logic_vector(31 downto 0);
        variable pending_word : std_logic_vector(31 downto 0);
        variable timeout     : integer;
        variable set_done_count : integer;
        variable refill_start_cycle : integer;
        variable refill_done_cycle  : integer;
        variable refill_cycles      : integer;
        variable refill_deadline_cycles : integer;

        procedure wait_clocks(constant count : integer) is
        begin
            for index in 1 to count loop
                wait until rising_edge(aclk);
            end loop;
        end procedure;

        procedure axi_write(
            constant address : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0);
            constant data    : std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0)
        ) is
        begin
            s00_axi_awaddr  <= address;
            s00_axi_awvalid <= '1';
            s00_axi_wdata   <= data;
            s00_axi_wstrb   <= (others => '1');
            s00_axi_wvalid  <= '1';
            s00_axi_bready  <= '1';

            loop
                wait until rising_edge(aclk);
                exit when s00_axi_awready = '1' and s00_axi_wready = '1';
            end loop;

            s00_axi_awvalid <= '0';
            s00_axi_wvalid  <= '0';
            s00_axi_awaddr  <= (others => '0');
            s00_axi_wdata   <= (others => '0');
            s00_axi_wstrb   <= (others => '0');

            loop
                wait until rising_edge(aclk);
                exit when s00_axi_bvalid = '1';
            end loop;

            wait until rising_edge(aclk);
            s00_axi_bready <= '0';
        end procedure;

        procedure axi_read(
            constant address : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0);
            variable data    : out std_logic_vector(C_AXI_DATA_WIDTH - 1 downto 0)
        ) is
        begin
            s00_axi_araddr  <= address;
            s00_axi_arvalid <= '1';
            s00_axi_rready  <= '1';

            loop
                wait until rising_edge(aclk);
                exit when s00_axi_arready = '1';
            end loop;

            s00_axi_arvalid <= '0';
            s00_axi_araddr  <= (others => '0');

            loop
                wait until rising_edge(aclk);
                exit when s00_axi_rvalid = '1';
            end loop;

            data := s00_axi_rdata;
            wait until rising_edge(aclk);
            s00_axi_rready <= '0';
        end procedure;

        procedure push_coeff_word(
            constant set_index  : integer;
            constant word_index : integer;
            constant last_word  : boolean
        ) is
        begin
            s_axis_coeff_tdata  <= pack_coeff(set_index, word_index);
            s_axis_coeff_tkeep  <= (others => '1');
            if last_word then
                s_axis_coeff_tlast <= '1';
            else
                s_axis_coeff_tlast <= '0';
            end if;
            s_axis_coeff_tvalid <= '1';

            loop
                wait until rising_edge(aclk);
                exit when s_axis_coeff_tready = '1';
            end loop;

            s_axis_coeff_tvalid <= '0';
            s_axis_coeff_tdata  <= (others => '0');
            s_axis_coeff_tkeep  <= (others => '0');
            s_axis_coeff_tlast  <= '0';
        end procedure;

        procedure wait_for_bank_ready is
        begin
            timeout := 0;
            loop
                wait until rising_edge(aclk);
                exit when dbg_active_set_available = '1';
                timeout := timeout + 1;

                assert timeout < C_TIMEOUT_CYCLES
                report "Timeout waiting for coefficient bank to become available"
                severity failure;
            end loop;
        end procedure;

        procedure push_coeff_bank(
            constant base_set_index : integer
        ) is
        begin
            for set_index in 0 to C_SET_COUNT - 1 loop
                for word_index in 0 to C_RELOAD_WORD_COUNT - 1 loop
                    push_coeff_word(base_set_index + set_index,
                                    word_index,
                                    set_index = C_SET_COUNT - 1 and word_index = C_RELOAD_WORD_COUNT - 1);
                end loop;
            end loop;
        end procedure;

        procedure wait_for_active_bank(
            constant expected_bank : std_logic
        ) is
        begin
            timeout := 0;
            loop
                wait until rising_edge(aclk);
                wait for 0 ns;

                if reload_done = '1' then
                    set_done_count := set_done_count + 1;
                end if;

                exit when dbg_active_bank = expected_bank;
                timeout := timeout + 1;

                assert timeout < C_TIMEOUT_CYCLES
                report "Timeout waiting for active bank " & std_logic'image(expected_bank)
                severity failure;
            end loop;
        end procedure;

        procedure wait_for_bank_ready_flag(
            constant expected_bank : std_logic
        ) is
        begin
            timeout := 0;
            loop
                wait until rising_edge(aclk);
                exit when (expected_bank = '0' and dbg_bank0_ready = '1') or
                          (expected_bank = '1' and dbg_bank1_ready = '1');
                timeout := timeout + 1;

                assert timeout < C_TIMEOUT_CYCLES
                report "Timeout waiting for bank ready flag " & std_logic'image(expected_bank)
                severity failure;
            end loop;
        end procedure;

        procedure wait_for_set_done_count(
            constant target_count : integer;
            constant max_cycles   : integer
        ) is
        begin
            timeout := 0;
            loop
                wait until rising_edge(aclk);
                wait for 0 ns;

                if reload_done = '1' then
                    set_done_count := set_done_count + 1;
                end if;

                exit when set_done_count >= target_count;
                timeout := timeout + 1;

                assert timeout < max_cycles
                report "Timeout waiting for reload_set_done count " & integer'image(target_count)
                severity failure;
            end loop;
        end procedure;

        procedure wait_for_threshold_set_done(
            constant target_count : integer;
            constant max_cycles   : integer
        ) is
            variable refill_pulse_seen : boolean := false;
        begin
            timeout := 0;
            loop
                wait until rising_edge(aclk);
                wait for 0 ns;
                wait for 0 ns;

                if dbg_refill_request_pulse = '1' then
                    refill_pulse_seen := true;
                end if;

                if reload_done = '1' then
                    set_done_count := set_done_count + 1;
                end if;

                exit when set_done_count >= target_count;
                timeout := timeout + 1;

                assert timeout < max_cycles
                report "Timeout waiting for refill-threshold reload_set_done count " & integer'image(target_count)
                severity failure;
            end loop;

            assert refill_pulse_seen
            report "refill_request_pulse was not observed before/on the configured threshold set transition"
            severity failure;
        end procedure;

        procedure wait_for_irq_pending_refill(
            constant context_text : string
        ) is
        begin
            timeout := 0;
            loop
                axi_read(C_IRQ_PENDING_ADDR, pending_word);
                exit when pending_word(6) = '1';

                wait until rising_edge(aclk);
                wait for 0 ns;
                timeout := timeout + 1;

                assert timeout < 8
                report context_text & ": IRQ_PENDING[6] was not set after the refill event; pending[6:0] decimal=" &
                       integer'image(to_integer(unsigned(pending_word(6 downto 0)))) &
                       ", irq=" & std_logic'image(irq) &
                       ", dbg_refill_request_pulse=" & std_logic'image(dbg_refill_request_pulse)
                severity failure;
            end loop;
        end procedure;

    begin
        aresetn             <= '0';
        iq_stream_enable    <= '0';
        s_axis_coeff_tvalid <= '0';
        s_axis_coeff_tkeep  <= (others => '0');
        s_axis_coeff_tlast  <= '0';
        wait_clocks(30);

        aresetn <= '1';
        wait_clocks(20);

        if C_IQ_STREAM_ALWAYS_ON then
            iq_stream_enable <= '1';
            wait_clocks(4);

            report "IQ stream enabled before coefficient reload flow and kept running"
            severity note;
        end if;

        report "Configure AXI-Lite: 5 sets per bank, 2-set refill threshold, Fu period, clear status, sequencer disabled"
        severity note;

        axi_write(C_CONTROL_ADDR, x"00000000");
        axi_write(C_BANK_SETS_ADDR, std_logic_vector(to_unsigned(C_SET_COUNT, 32)));
        axi_write(C_REFILL_THRESHOLD_ADDR, std_logic_vector(to_unsigned(C_REFILL_THRESHOLD_SETS, 32)));
        axi_write(C_FU_PERIOD_ADDR, std_logic_vector(to_unsigned(C_FU_PERIOD_CYCLES, 32)));
        axi_write(C_IRQ_ENABLE_ADDR, x"00000040");
        axi_write(C_CONTROL_ADDR, x"00000002");
        wait_clocks(10);
        axi_write(C_CONTROL_ADDR, x"00000000");

        report "Stream initial Bank 0 coefficient block"
        severity note;

        push_coeff_bank(0);

        wait_for_bank_ready;
        assert dbg_active_bank = '0'
        report "Initial active coefficient bank was not Bank 0"
        severity failure;

        report "Bank 0 ready before enabling sequencer"
        severity note;

        axi_write(C_CONTROL_ADDR, x"00000001");

        set_done_count := 0;

        assert dbg_reload_timing_error = '0'
        report "Sequencer reload_timing_error asserted"
        severity failure;

        assert dbg_fir_reload_error = '0'
        report "FIR reload TLAST error asserted before main reload completion wait"
        severity failure;

        if not C_IQ_STREAM_ALWAYS_ON then
            report "Enable IQ stream and watch real FIR reload/config ready recover"
            severity note;

            iq_stream_enable <= '1';
        else
            report "IQ stream is already running; wait for reload to consume all coefficient sets"
            severity note;
        end if;

        if set_done_count = 0 then
            wait_for_set_done_count(1, C_TIMEOUT_CYCLES);
            report "After first completed set with IQ enabled: irq=" & std_logic'image(irq)
            severity note;

            axi_read(C_STATUS_ADDR, status_word);
            assert status_word(8) = '0'
            report "refill_request asserted before the configured threshold"
            severity failure;

            axi_read(C_IRQ_PENDING_ADDR, pending_word);
            assert pending_word(6) = '0'
            report "IRQ_PENDING[6] refill_request asserted before the configured threshold"
            severity failure;

            assert refill_request_pulse_count = 0
            report "refill_request_pulse occurred before the configured threshold"
            severity failure;

            assert external_irq_high_count = 0
            report "external IRQ asserted before the configured threshold"
            severity failure;
        else
            report "At least one set completed before IQ was enabled; continuing to 5 completed sets"
            severity note;
        end if;

        wait_for_threshold_set_done(C_SET_COUNT - C_REFILL_THRESHOLD_SETS, C_TIMEOUT_CYCLES);
        report "Refill threshold reached after " & integer'image(C_SET_COUNT - C_REFILL_THRESHOLD_SETS) &
               " completed sets; usedw=" & integer'image(usedw) &
               ", irq=" & std_logic'image(irq)
        severity note;

        axi_read(C_STATUS_ADDR, status_word);
        assert status_word(8) = '1'
        report "STATUS[8] refill_request was not set at the configured threshold"
        severity failure;

        wait_for_irq_pending_refill("First refill threshold");

        assert irq = '1'
        report "Refill IRQ was not held high by IRQ_PENDING[6]"
        severity failure;

        wait until rising_edge(aclk);
        wait for 0 ns;

        assert dbg_refill_request_pulse = '0'
        report "refill_request_pulse stayed high after the threshold clock"
        severity failure;

        assert irq = '1'
        report "Refill IRQ deasserted before PS cleared IRQ_PENDING[6]"
        severity failure;

        assert dbg_active_bank = '0'
        report "Ping-pong source bank changed before the PS refilled the inactive bank"
        severity failure;

        report "PS response model: stream next 5-set block into inactive Bank 1 after refill interrupt event"
        severity note;

        refill_start_cycle := sim_cycle_count;
        push_coeff_bank(C_SET_COUNT);
        wait_for_bank_ready_flag('1');
        refill_done_cycle := sim_cycle_count;
        refill_cycles := refill_done_cycle - refill_start_cycle;
        refill_deadline_cycles := C_REFILL_THRESHOLD_SETS * C_FU_PERIOD_CYCLES;

        report "Inactive-bank refill transfer completed in " &
               integer'image(refill_cycles) & " PL clocks (" &
               time'image(refill_cycles * C_CLK_PERIOD) &
               "); available threshold window is " &
               integer'image(refill_deadline_cycles) & " PL clocks"
        severity note;

        assert refill_cycles < refill_deadline_cycles
        report "Inactive-bank refill did not finish before the configured threshold window expired"
        severity failure;

        axi_read(C_STATUS_ADDR, status_word);
        assert status_word(8) = '1'
        report "refill_request status did not stay sticky while PS filled inactive bank"
        severity failure;

        axi_read(C_IRQ_PENDING_ADDR, pending_word);
        assert pending_word(6) = '1'
        report "IRQ_PENDING[6] did not stay pending while PS filled inactive bank"
        severity failure;

        axi_write(C_IRQ_CLEAR_ADDR, x"00000040");
        wait_clocks(4);
        axi_read(C_IRQ_PENDING_ADDR, pending_word);

        assert pending_word(6) = '0'
        report "IRQ_CLEAR[6] did not clear IRQ_PENDING[6]"
        severity failure;

        assert irq = '0'
        report "IRQ stayed high after PS cleared IRQ_PENDING[6]"
        severity failure;

        axi_write(C_CONTROL_ADDR, x"00000003");
        wait_clocks(4);
        axi_write(C_CONTROL_ADDR, x"00000001");
        wait_clocks(4);
        axi_read(C_STATUS_ADDR, status_word);

        assert status_word(8) = '0'
        report "clear_status did not clear refill_request"
        severity failure;

        assert irq = '0'
        report "IRQ was high after clear_status even though IRQ_PENDING[6] was already cleared"
        severity failure;

        wait_for_active_bank('1');
        report "Ping-pong RAM source swapped to Bank 1 after Bank 0 drained into the sequencer/FIFO path; FIR reload_done count=" &
               integer'image(set_done_count) & ", fifo_usedw=" & integer'image(usedw)
        severity note;

        assert dbg_bank0_ready = '0'
        report "Bank 0 stayed marked ready after the 0->1 swap, so the old active bank was not released for refill"
        severity failure;

        report "Bank 0 released for refill; Bank 1 is now the RAM source feeding the sequencer path"
        severity note;

        wait_for_threshold_set_done(C_SET_COUNT + (C_SET_COUNT - C_REFILL_THRESHOLD_SETS), C_TIMEOUT_CYCLES);
        report "Second refill threshold reached while Bank 1 is active; usedw=" & integer'image(usedw) &
               ", irq=" & std_logic'image(irq)
        severity note;

        axi_read(C_STATUS_ADDR, status_word);
        assert status_word(8) = '1'
        report "STATUS[8] refill_request was not set at the Bank 1 refill threshold"
        severity failure;

        wait_for_irq_pending_refill("Second refill threshold");

        assert irq = '1'
        report "Second refill IRQ was not held high by IRQ_PENDING[6]"
        severity failure;

        wait until rising_edge(aclk);
        wait for 0 ns;

        assert dbg_refill_request_pulse = '0'
        report "Second refill_request_pulse stayed high after the threshold clock"
        severity failure;

        assert irq = '1'
        report "Second refill IRQ deasserted before PS cleared IRQ_PENDING[6]"
        severity failure;

        assert dbg_active_bank = '1'
        report "Ping-pong source bank changed before PS refilled inactive Bank 0"
        severity failure;

        report "PS response model: stream third 5-set block into inactive Bank 0 after second refill interrupt event"
        severity note;

        refill_start_cycle := sim_cycle_count;
        push_coeff_bank(2 * C_SET_COUNT);
        wait_for_bank_ready_flag('0');
        refill_done_cycle := sim_cycle_count;
        refill_cycles := refill_done_cycle - refill_start_cycle;
        refill_deadline_cycles := C_REFILL_THRESHOLD_SETS * C_FU_PERIOD_CYCLES;

        report "Inactive Bank 0 refill transfer completed in " &
               integer'image(refill_cycles) & " PL clocks (" &
               time'image(refill_cycles * C_CLK_PERIOD) &
               "); available threshold window is " &
               integer'image(refill_deadline_cycles) & " PL clocks"
        severity note;

        assert refill_cycles < refill_deadline_cycles
        report "Inactive Bank 0 refill did not finish before the configured threshold window expired"
        severity failure;

        axi_read(C_STATUS_ADDR, status_word);
        assert status_word(8) = '1'
        report "Second refill_request status did not stay sticky while PS filled inactive Bank 0"
        severity failure;

        axi_read(C_IRQ_PENDING_ADDR, pending_word);
        assert pending_word(6) = '1'
        report "Second IRQ_PENDING[6] did not stay pending while PS filled inactive Bank 0"
        severity failure;

        axi_write(C_IRQ_CLEAR_ADDR, x"00000040");
        wait_clocks(4);
        axi_read(C_IRQ_PENDING_ADDR, pending_word);

        assert pending_word(6) = '0'
        report "Second IRQ_CLEAR[6] did not clear IRQ_PENDING[6]"
        severity failure;

        assert irq = '0'
        report "IRQ stayed high after PS cleared the second IRQ_PENDING[6]"
        severity failure;

        axi_write(C_CONTROL_ADDR, x"00000003");
        wait_clocks(4);
        axi_write(C_CONTROL_ADDR, x"00000001");
        wait_clocks(4);
        axi_read(C_STATUS_ADDR, status_word);

        assert status_word(8) = '0'
        report "clear_status did not clear the second refill_request"
        severity failure;

        assert irq = '0'
        report "IRQ was high after the second clear_status even though IRQ_PENDING[6] was already cleared"
        severity failure;

        wait_for_active_bank('0');
        report "Ping-pong RAM source swapped back to Bank 0 after Bank 1 drained into the sequencer/FIFO path; FIR reload_done count=" &
               integer'image(set_done_count) & ", fifo_usedw=" & integer'image(usedw)
        severity note;

        assert dbg_bank1_ready = '0'
        report "Bank 1 stayed marked ready after the 1->0 swap, so the old active bank was not released for refill"
        severity failure;

        axi_read(C_STATUS_ADDR, status_word);
        report "Final STATUS bits 8 downto 0 decimal=" &
               integer'image(to_integer(unsigned(status_word(8 downto 0)))) &
               " bits: active=" & std_logic'image(status_word(0)) &
               ", block_done=" & std_logic'image(status_word(1)) &
               ", missed_refill=" & std_logic'image(status_word(2)) &
               ", reload_timing_error=" & std_logic'image(status_word(3)) &
               ", active_set_available=" & std_logic'image(status_word(4)) &
               ", bank_underrun=" & std_logic'image(status_word(5)) &
               ", bank_write_error=" & std_logic'image(status_word(6)) &
               ", fir_reload_error=" & std_logic'image(status_word(7)) &
               ", refill_request=" & std_logic'image(status_word(8))
        severity note;

        assert dbg_reload_timing_error = '0'
        report "Sequencer reload_timing_error asserted during full FIR reload run"
        severity failure;

        assert dbg_fir_reload_error = '0'
        report "FIR reload error asserted during full FIR reload run"
        severity failure;

        assert status_word(5) = '0'
        report "Coefficient bank underrun asserted during refill/swap test"
        severity failure;

        report "PASS: refill event pulsed internally at both thresholds, IRQ_PENDING[6] held PS IRQ until W1C clear, and banks swapped 0->1->0"
        severity note;

        stop;
    end process;

end architecture;
 
