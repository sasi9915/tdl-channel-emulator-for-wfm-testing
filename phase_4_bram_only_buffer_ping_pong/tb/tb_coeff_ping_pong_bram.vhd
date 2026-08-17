library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.stop;

entity tb_coeff_ping_pong_bram is
end entity;

architecture sim of tb_coeff_ping_pong_bram is
    constant C_CLK_PERIOD        : time     := 10 ns;
    constant C_TAP_COUNT         : positive := 4;
    constant C_MAX_SETS_PER_BANK : positive := 3;
    constant C_DATA_WIDTH        : positive := 32;

    signal clk : std_logic := '0';

    signal wr_en        : std_logic := '0';
    signal wr_bank      : std_logic := '0';
    signal wr_set_index : integer range 0 to C_MAX_SETS_PER_BANK - 1 := 0;
    signal wr_tap_index : integer range 0 to C_TAP_COUNT - 1 := 0;
    signal wr_data      : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');

    signal rd_en        : std_logic := '0';
    signal rd_bank      : std_logic := '0';
    signal rd_set_index : integer range 0 to C_MAX_SETS_PER_BANK - 1 := 0;
    signal rd_tap_index : integer range 0 to C_TAP_COUNT - 1 := 0;
    signal rd_data      : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    signal rd_valid     : std_logic;
begin
    clk <= not clk after C_CLK_PERIOD / 2;

    dut : entity work.coeff_ping_pong_bram
        generic map(
            G_TAP_COUNT         => C_TAP_COUNT,
            G_MAX_SETS_PER_BANK => C_MAX_SETS_PER_BANK,
            G_DATA_WIDTH        => C_DATA_WIDTH,
            G_RAM_STYLE         => "block"
        )
        port map(
            clk          => clk,
            wr_en        => wr_en,
            wr_bank      => wr_bank,
            wr_set_index => wr_set_index,
            wr_tap_index => wr_tap_index,
            wr_data      => wr_data,
            rd_en        => rd_en,
            rd_bank      => rd_bank,
            rd_set_index => rd_set_index,
            rd_tap_index => rd_tap_index,
            rd_data      => rd_data,
            rd_valid     => rd_valid
        );

    stimulus : process
        procedure wait_clock_cycles(cycles : natural) is
        begin
            for i in 1 to cycles loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        procedure write_word(
            constant bank      : in std_logic;
            constant set_index : in integer;
            constant tap_index : in integer;
            constant data      : in std_logic_vector(C_DATA_WIDTH - 1 downto 0)
        ) is
        begin
            wr_bank      <= bank;
            wr_set_index <= set_index;
            wr_tap_index <= tap_index;
            wr_data      <= data;
            wr_en        <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            wr_en <= '0';
            wait_clock_cycles(1);
        end procedure;

        procedure check_read(
            constant bank      : in std_logic;
            constant set_index : in integer;
            constant tap_index : in integer;
            constant expected  : in std_logic_vector(C_DATA_WIDTH - 1 downto 0)
        ) is
        begin
            rd_bank      <= bank;
            rd_set_index <= set_index;
            rd_tap_index <= tap_index;
            rd_en        <= '1';

            -- Read request is sampled on this clock; output is registered from BRAM.
            wait until rising_edge(clk);
            wait for 1 ns;
            assert rd_valid = '1'
                report "rd_valid was not asserted with the registered read data"
                severity failure;
            assert rd_data = expected
                report "BRAM read data mismatch"
                severity failure;

            rd_en <= '0';
            wait until rising_edge(clk);
            wait for 1 ns;
            assert rd_valid = '0'
                report "rd_valid should deassert one clock after rd_en is removed"
                severity failure;
        end procedure;
    begin
        wait_clock_cycles(2);

        -- Write different taps and sets into bank 0.
        write_word('0', 0, 0, x"AAAA0001");
        write_word('0', 0, 1, x"AAAA0002");
        write_word('0', 1, 0, x"BBBB0001");

        -- Write the same set/tap location in bank 1 to prove bank separation.
        write_word('1', 0, 0, x"CCCC0001");

        -- Read back bank 0 values and check the one-clock registered output.
        check_read('0', 0, 0, x"AAAA0001");
        check_read('0', 0, 1, x"AAAA0002");
        check_read('0', 1, 0, x"BBBB0001");

        -- Read bank 1 and confirm it did not overwrite bank 0.
        check_read('1', 0, 0, x"CCCC0001");
        check_read('0', 0, 0, x"AAAA0001");

        report "Coefficient ping-pong BRAM standalone test completed"
            severity note;
        stop;
    end process;
end architecture;
