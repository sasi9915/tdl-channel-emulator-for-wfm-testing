library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.stop;

entity tb_pl_sequencer_axi_lite is
end tb_pl_sequencer_axi_lite;

architecture sim of tb_pl_sequencer_axi_lite is
    constant C_CLK_PERIOD : time := 10 ns;
    constant C_ADDR_WIDTH : integer := 5;
    constant C_DATA_WIDTH : integer := 32;

    constant C_CONTROL_ADDR      : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := "00000";
    constant C_FU_PERIOD_ADDR    : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := "00100";
    constant C_BANK_SETS_ADDR    : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := "01000";
    constant C_STATUS_ADDR       : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := "10000";
    constant C_DEBUG_ADDR        : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := "10100";
    constant C_CAPABILITY_ADDR   : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := "11000";

    signal aclk    : std_logic := '0';
    signal aresetn : std_logic := '0';

    signal s00_axi_awaddr  : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal s00_axi_awprot  : std_logic_vector(2 downto 0) := (others => '0');
    signal s00_axi_awvalid : std_logic := '0';
    signal s00_axi_awready : std_logic;
    signal s00_axi_wdata   : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
    signal s00_axi_wstrb   : std_logic_vector((C_DATA_WIDTH / 8) - 1 downto 0) := (others => '0');
    signal s00_axi_wvalid  : std_logic := '0';
    signal s00_axi_wready  : std_logic;
    signal s00_axi_bresp   : std_logic_vector(1 downto 0);
    signal s00_axi_bvalid  : std_logic;
    signal s00_axi_bready  : std_logic := '0';
    signal s00_axi_araddr  : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal s00_axi_arprot  : std_logic_vector(2 downto 0) := (others => '0');
    signal s00_axi_arvalid : std_logic := '0';
    signal s00_axi_arready : std_logic;
    signal s00_axi_rdata   : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    signal s00_axi_rresp   : std_logic_vector(1 downto 0);
    signal s00_axi_rvalid  : std_logic;
    signal s00_axi_rready  : std_logic := '0';

    signal seq_enable              : std_logic;
    signal seq_fu_period_cycles    : std_logic_vector(31 downto 0);
    signal cfg_bank_sets_per_bank  : std_logic_vector(31 downto 0);
    signal seq_clear_status        : std_logic;
    signal seq_reload_active       : std_logic := '0';
    signal seq_reload_block_done   : std_logic := '0';
    signal seq_missed_refill       : std_logic := '0';
    signal seq_reload_timing_error : std_logic := '0';
    signal coeff_bank_active_set_available : std_logic := '0';
    signal coeff_bank_underrun             : std_logic := '0';
    signal coeff_bank_write_error          : std_logic := '0';
    signal seq_state_debug         : std_logic_vector(2 downto 0) := (others => '0');

    signal clear_status_seen          : std_logic := '0';
    signal clear_status_capture_reset : std_logic := '0';
begin
    aclk <= not aclk after C_CLK_PERIOD / 2;

    dut : entity work.pl_sequencer_axi_lite
        generic map(
            C_S00_AXI_DATA_WIDTH => C_DATA_WIDTH,
            C_S00_AXI_ADDR_WIDTH => C_ADDR_WIDTH
        )
        port map(
            seq_enable              => seq_enable,
            seq_fu_period_cycles    => seq_fu_period_cycles,
            cfg_bank_sets_per_bank  => cfg_bank_sets_per_bank,
            seq_clear_status        => seq_clear_status,
            seq_reload_active       => seq_reload_active,
            seq_reload_block_done   => seq_reload_block_done,
            seq_missed_refill       => seq_missed_refill,
            seq_reload_timing_error => seq_reload_timing_error,
            coeff_bank_active_set_available => coeff_bank_active_set_available,
            coeff_bank_underrun             => coeff_bank_underrun,
            coeff_bank_write_error          => coeff_bank_write_error,
            seq_state_debug         => seq_state_debug,
            s00_axi_aclk            => aclk,
            s00_axi_aresetn         => aresetn,
            s00_axi_awaddr          => s00_axi_awaddr,
            s00_axi_awprot          => s00_axi_awprot,
            s00_axi_awvalid         => s00_axi_awvalid,
            s00_axi_awready         => s00_axi_awready,
            s00_axi_wdata           => s00_axi_wdata,
            s00_axi_wstrb           => s00_axi_wstrb,
            s00_axi_wvalid          => s00_axi_wvalid,
            s00_axi_wready          => s00_axi_wready,
            s00_axi_bresp           => s00_axi_bresp,
            s00_axi_bvalid          => s00_axi_bvalid,
            s00_axi_bready          => s00_axi_bready,
            s00_axi_araddr          => s00_axi_araddr,
            s00_axi_arprot          => s00_axi_arprot,
            s00_axi_arvalid         => s00_axi_arvalid,
            s00_axi_arready         => s00_axi_arready,
            s00_axi_rdata           => s00_axi_rdata,
            s00_axi_rresp           => s00_axi_rresp,
            s00_axi_rvalid          => s00_axi_rvalid,
            s00_axi_rready          => s00_axi_rready
        );

    clear_status_monitor : process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' or clear_status_capture_reset = '1' then
                clear_status_seen <= '0';
            elsif seq_clear_status = '1' then
                clear_status_seen <= '1';
            end if;
        end if;
    end process;

    stimulus : process
        procedure wait_clock_cycles(cycles : natural) is
        begin
            for i in 1 to cycles loop
                wait until rising_edge(aclk);
            end loop;
        end procedure;

        procedure axi_write(
            constant addr : in std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
            constant data : in std_logic_vector(C_DATA_WIDTH - 1 downto 0)
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

        procedure axi_read(
            constant addr : in std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
            variable data : out std_logic_vector(C_DATA_WIDTH - 1 downto 0)
        ) is
        begin
            s00_axi_araddr  <= addr;
            s00_axi_arvalid <= '1';
            s00_axi_rready  <= '1';

            wait until rising_edge(aclk) and s00_axi_arready = '1';
            s00_axi_arvalid <= '0';

            wait until rising_edge(aclk) and s00_axi_rvalid = '1';
            data := s00_axi_rdata;
            assert s00_axi_rresp = "00"
                report "AXI-Lite read response was not OKAY"
                severity failure;

            s00_axi_rready <= '0';
            wait until rising_edge(aclk);
        end procedure;

        variable read_data : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    begin
        -- Reset proves all control outputs start from a known inactive state.
        aresetn <= '0';
        wait_clock_cycles(5);
        aresetn <= '1';
        wait_clock_cycles(3);

        assert seq_enable = '0'
            report "seq_enable was not cleared by reset"
            severity failure;
        assert seq_fu_period_cycles = x"00000000"
            report "seq_fu_period_cycles was not cleared by reset"
            severity failure;
        assert cfg_bank_sets_per_bank = x"00000000"
            report "cfg_bank_sets_per_bank was not cleared by reset"
            severity failure;

        -- CONTROL register: PS writes enable bit and can create a clear-status pulse.
        axi_write(C_CONTROL_ADDR, x"00000001");
        wait_clock_cycles(1);
        assert seq_enable = '1'
            report "CONTROL bit 0 did not drive seq_enable"
            severity failure;
        axi_read(C_CONTROL_ADDR, read_data);
        assert read_data = x"00000001"
            report "CONTROL readback did not match written value"
            severity failure;

        clear_status_capture_reset <= '1';
        wait_clock_cycles(1);
        clear_status_capture_reset <= '0';
        axi_write(C_CONTROL_ADDR, x"00000003");
        wait_clock_cycles(2);
        assert seq_enable = '1'
            report "CONTROL bit 0 was not preserved during clear-status write"
            severity failure;
        assert clear_status_seen = '1'
            report "CONTROL bit 1 did not create seq_clear_status pulse"
            severity failure;
        assert seq_clear_status = '0'
            report "seq_clear_status stayed high instead of pulsing for one clock"
            severity failure;
        axi_read(C_CONTROL_ADDR, read_data);
        assert read_data = x"00000001"
            report "CONTROL bit 1 should read back as zero"
            severity failure;

        -- FU_PERIOD register: PS programs the Fu tick spacing used by the sequencer.
        axi_write(C_FU_PERIOD_ADDR, std_logic_vector(to_unsigned(50000, C_DATA_WIDTH)));
        wait_clock_cycles(1);
        assert seq_fu_period_cycles = std_logic_vector(to_unsigned(50000, C_DATA_WIDTH))
            report "FU_PERIOD did not drive seq_fu_period_cycles"
            severity failure;
        axi_read(C_FU_PERIOD_ADDR, read_data);
        assert read_data = std_logic_vector(to_unsigned(50000, C_DATA_WIDTH))
            report "FU_PERIOD readback did not match written value"
            severity failure;

        -- BANK_SETS_PER_BANK is a runtime configuration register.
        axi_write(C_BANK_SETS_ADDR, std_logic_vector(to_unsigned(300, C_DATA_WIDTH)));
        wait_clock_cycles(1);
        assert cfg_bank_sets_per_bank = std_logic_vector(to_unsigned(300, C_DATA_WIDTH))
            report "BANK_SETS_PER_BANK did not drive cfg_bank_sets_per_bank"
            severity failure;
        axi_read(C_BANK_SETS_ADDR, read_data);
        assert read_data = std_logic_vector(to_unsigned(300, C_DATA_WIDTH))
            report "BANK_SETS_PER_BANK readback did not match written value"
            severity failure;

        -- STATUS register: sequencer and coefficient-bank status inputs are packed for PS readback.
        seq_reload_active       <= '1';
        seq_reload_block_done   <= '1';
        seq_missed_refill       <= '1';
        seq_reload_timing_error <= '1';
        coeff_bank_active_set_available <= '1';
        coeff_bank_underrun             <= '1';
        coeff_bank_write_error          <= '1';
        wait_clock_cycles(1);
        axi_read(C_STATUS_ADDR, read_data);
        assert read_data = x"0000007F"
            report "STATUS register did not return expected Phase 6 status bits"
            severity failure;

        -- DEBUG register: state_debug is readable without changing sequencer behavior.
        seq_state_debug <= "101";
        wait_clock_cycles(1);
        axi_read(C_DEBUG_ADDR, read_data);
        assert read_data = x"00000005"
            report "DEBUG register did not return seq_state_debug"
            severity failure;

        axi_read(C_CAPABILITY_ADDR, read_data);
        assert read_data = x"00060001"
            report "CAPABILITY register did not return expected Phase 6 version"
            severity failure;

        report "PL sequencer AXI-Lite register test completed"
            severity note;
        stop;
    end process;
end sim;
