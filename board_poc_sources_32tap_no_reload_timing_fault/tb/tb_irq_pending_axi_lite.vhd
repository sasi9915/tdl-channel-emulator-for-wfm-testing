library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.env.all;

entity tb_irq_pending_axi_lite is
end entity;

architecture sim of tb_irq_pending_axi_lite is

    constant C_CLK_PERIOD      : time := 3333 ps;
    constant C_AXI_DATA_WIDTH  : integer := 32;
    constant C_AXI_ADDR_WIDTH  : integer := 32;

    constant C_IRQ_ENABLE_ADDR  : std_logic_vector(C_AXI_ADDR_WIDTH - 1 downto 0) := x"0000000C";
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

    signal seq_enable                 : std_logic;
    signal seq_fu_period_cycles       : std_logic_vector(31 downto 0);
    signal cfg_bank_sets_per_bank     : std_logic_vector(31 downto 0);
    signal cfg_refill_threshold_sets  : std_logic_vector(31 downto 0);
    signal irq_enable                 : std_logic_vector(6 downto 0);
    signal irq_pending                : std_logic_vector(6 downto 0);
    signal seq_clear_status           : std_logic;

    signal seq_reload_active          : std_logic := '0';
    signal seq_reload_block_done      : std_logic := '0';
    signal seq_missed_refill          : std_logic := '0';
    signal refill_request             : std_logic := '0';
    signal refill_request_pulse       : std_logic := '0';
    signal seq_reload_timing_error    : std_logic := '0';
    signal active_set_available       : std_logic := '0';
    signal coeff_bank_underrun        : std_logic := '0';
    signal coeff_bank_write_error     : std_logic := '0';
    signal fir_reload_error           : std_logic := '0';
    signal coeff_bank_active_bank     : std_logic := '0';
    signal coeff_bank0_ready          : std_logic := '0';
    signal coeff_bank1_ready          : std_logic := '0';
    signal seq_state_debug            : std_logic_vector(2 downto 0) := (others => '0');
    signal irq                        : std_logic;

begin

    aclk <= not aclk after C_CLK_PERIOD / 2;
    irq <= '1' when (irq_pending and irq_enable) /= "0000000" else '0';

    dut : entity work.pl_sequencer_axi_lite
        generic map(
            C_S00_AXI_DATA_WIDTH => C_AXI_DATA_WIDTH,
            C_S00_AXI_ADDR_WIDTH => C_AXI_ADDR_WIDTH
        )
        port map(
            seq_enable                      => seq_enable,
            seq_fu_period_cycles            => seq_fu_period_cycles,
            cfg_bank_sets_per_bank          => cfg_bank_sets_per_bank,
            cfg_refill_threshold_sets       => cfg_refill_threshold_sets,
            irq_enable                      => irq_enable,
            irq_pending                     => irq_pending,
            seq_clear_status                => seq_clear_status,
            seq_reload_active               => seq_reload_active,
            seq_reload_block_done           => seq_reload_block_done,
            seq_missed_refill               => seq_missed_refill,
            refill_request                  => refill_request,
            refill_request_pulse            => refill_request_pulse,
            seq_reload_timing_error         => seq_reload_timing_error,
            coeff_bank_active_set_available => active_set_available,
            coeff_bank_underrun             => coeff_bank_underrun,
            coeff_bank_write_error          => coeff_bank_write_error,
            fir_reload_error                => fir_reload_error,
            coeff_bank_active_bank          => coeff_bank_active_bank,
            coeff_bank0_ready               => coeff_bank0_ready,
            coeff_bank1_ready               => coeff_bank1_ready,
            seq_state_debug                 => seq_state_debug,
            s00_axi_aclk                    => aclk,
            s00_axi_aresetn                 => aresetn,
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
            s00_axi_rready                  => s00_axi_rready
        );

    stimulus : process
        variable read_word : std_logic_vector(31 downto 0);

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
                wait for 0 ns;
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
                wait for 0 ns;
                exit when s00_axi_rvalid = '1';
            end loop;

            data := s00_axi_rdata;
            wait until rising_edge(aclk);
            s00_axi_rready <= '0';
        end procedure;

        procedure pulse_refill is
        begin
            refill_request_pulse <= '1';
            wait until rising_edge(aclk);
            wait for 0 ns;
            refill_request_pulse <= '0';
            wait until rising_edge(aclk);
            wait for 0 ns;
        end procedure;

        procedure pulse_underrun_rise is
        begin
            coeff_bank_underrun <= '1';
            wait until rising_edge(aclk);
            wait for 0 ns;
            wait until rising_edge(aclk);
            wait for 0 ns;
        end procedure;

        procedure expect_pending(
            constant expected : std_logic_vector(6 downto 0);
            constant label_text : string
        ) is
        begin
            axi_read(C_IRQ_PENDING_ADDR, read_word);

            assert read_word(6 downto 0) = expected
            report label_text & ": expected IRQ_PENDING=" &
                   integer'image(to_integer(unsigned(expected))) &
                   ", actual=" &
                   integer'image(to_integer(unsigned(read_word(6 downto 0))))
            severity failure;

            assert irq_pending = expected
            report label_text & ": irq_pending output mismatch"
            severity failure;
        end procedure;

        procedure expect_irq(
            constant expected : std_logic;
            constant label_text : string
        ) is
        begin
            wait for 0 ns;

            assert irq = expected
            report label_text & ": expected irq=" & std_logic'image(expected) &
                   ", actual=" & std_logic'image(irq)
            severity failure;
        end procedure;

        procedure clear_irq(
            constant mask : std_logic_vector(6 downto 0)
        ) is
            variable data : std_logic_vector(31 downto 0);
        begin
            data := (others => '0');
            data(6 downto 0) := mask;
            axi_write(C_IRQ_CLEAR_ADDR, data);
            wait until rising_edge(aclk);
            wait for 0 ns;
        end procedure;

        procedure clear_irq_with_same_cycle_refill(
            constant mask : std_logic_vector(6 downto 0)
        ) is
            variable data : std_logic_vector(31 downto 0);
        begin
            data := (others => '0');
            data(6 downto 0) := mask;

            s00_axi_awaddr  <= C_IRQ_CLEAR_ADDR;
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

            -- The AXI slave commits the write on the clock after AW/W capture.
            -- Drive a fresh refill pulse on that same commit clock.
            refill_request_pulse <= '1';
            wait until rising_edge(aclk);
            wait for 0 ns;
            refill_request_pulse <= '0';

            if s00_axi_bvalid = '0' then
                loop
                    wait until rising_edge(aclk);
                    wait for 0 ns;
                    exit when s00_axi_bvalid = '1';
                end loop;
            end if;

            wait until rising_edge(aclk);
            s00_axi_bready <= '0';
            wait for 0 ns;
        end procedure;

    begin
        aresetn <= '0';
        wait_clocks(8);
        aresetn <= '1';
        wait_clocks(4);

        axi_write(C_IRQ_ENABLE_ADDR, x"0000007F");
        expect_pending("0000000", "after reset");
        expect_irq('0', "after reset");

        report "TEST 1 - REFILL ONLY" severity note;
        pulse_refill;
        expect_pending("1000000", "TEST 1 after refill pulse");
        expect_irq('1', "TEST 1 IRQ high");
        clear_irq("1000000");
        expect_pending("0000000", "TEST 1 after IRQ_CLEAR[6]");
        expect_irq('0', "TEST 1 IRQ low");

        report "TEST 2 - UNDERRUN ONLY" severity note;
        pulse_underrun_rise;
        expect_pending("0001000", "TEST 2 after underrun rise");
        expect_irq('1', "TEST 2 IRQ high");
        clear_irq("0001000");
        expect_pending("0000000", "TEST 2 after IRQ_CLEAR[3]");
        expect_irq('0', "TEST 2 IRQ low");
        coeff_bank_underrun <= '0';
        wait_clocks(2);

        report "TEST 3 - SIMULTANEOUS REFILL + UNDERRUN" severity note;
        refill_request_pulse <= '1';
        coeff_bank_underrun  <= '1';
        wait until rising_edge(aclk);
        wait for 0 ns;
        refill_request_pulse <= '0';
        wait until rising_edge(aclk);
        wait for 0 ns;
        expect_pending("1001000", "TEST 3 simultaneous pending");
        expect_irq('1', "TEST 3 IRQ high");
        clear_irq("1000000");
        expect_pending("0001000", "TEST 3 after clearing refill only");
        expect_irq('1', "TEST 3 IRQ remains high");
        clear_irq("0001000");
        expect_pending("0000000", "TEST 3 after clearing underrun");
        expect_irq('0', "TEST 3 IRQ low");
        coeff_bank_underrun <= '0';
        wait_clocks(2);

        report "TEST 4 - CLEAR + NEW REFILL EVENT SAME CYCLE" severity note;
        pulse_refill;
        expect_pending("1000000", "TEST 4 setup pending refill");
        expect_irq('1', "TEST 4 setup IRQ high");
        clear_irq_with_same_cycle_refill("1000000");
        expect_pending("1000000", "TEST 4 clear plus new event keeps refill pending");
        expect_irq('1', "TEST 4 IRQ remains high");
        clear_irq("1000000");
        expect_pending("0000000", "TEST 4 final clear");
        expect_irq('0', "TEST 4 final IRQ low");

        report "PASS: IRQ_PENDING/IRQ_CLEAR passed refill, underrun, simultaneous, and clear-plus-new-event tests"
        severity note;

        stop;
    end process;

end architecture;
