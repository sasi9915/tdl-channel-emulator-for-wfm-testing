library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.stop;

entity tb_coeff_ping_pong_bram_boundary is
end entity;

architecture sim of tb_coeff_ping_pong_bram_boundary is

    constant C_CLK_PERIOD        : time     := 10 ns;
    constant C_TAP_COUNT         : positive := 32;
    constant C_MAX_SETS_PER_BANK : positive := 600;
    constant C_DATA_WIDTH        : positive := 32;
    constant C_TEST_WORD_COUNT   : positive := 1064;
    constant C_PAGE_LAST_ADDR    : integer  := 1023;
    constant C_PAGE_FIRST_ADDR   : integer  := 1024;
    constant C_TOTAL_DEPTH       : positive := 2 * C_MAX_SETS_PER_BANK * C_TAP_COUNT;

    signal clk      : std_logic                                   := '0';
    signal wr_en    : std_logic                                   := '0';
    signal wr_addr  : integer range 0 to C_TOTAL_DEPTH - 1        := 0;
    signal wr_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');
    signal rd_en    : std_logic                                   := '0';
    signal rd_addr  : integer range 0 to C_TOTAL_DEPTH - 1        := 0;
    signal rd_data  : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    signal rd_valid : std_logic;

    function boundary_test_word(
        constant linear_index : integer
    ) return std_logic_vector is
        variable result_word : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    begin
        result_word(31 downto 16) := std_logic_vector(to_signed(linear_index + 1000, 16));
        result_word(15 downto 0)  := std_logic_vector(to_signed(-(linear_index + 1), 16));
        return result_word;
    end function;

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
            clk      => clk,
            wr_en    => wr_en,
            wr_addr  => wr_addr,
            wr_data  => wr_data,
            rd_en    => rd_en,
            rd_addr  => rd_addr,
            rd_data  => rd_data,
            rd_valid => rd_valid
        );

    stimulus : process
        variable expected_read_index : integer := 0;
    begin
        report "TEST: paged BRAM boundary 1023-to-1024 read-order verification"
        severity note;

        wait until rising_edge(clk);

        for write_index in 0 to C_TEST_WORD_COUNT - 1 loop
            wr_en   <= '1';
            wr_addr <= write_index;
            wr_data <= boundary_test_word(write_index);
            wait until rising_edge(clk);
        end loop;

        wr_en   <= '0';
        wr_addr <= 0;
        wr_data <= (others => '0');

        wait until rising_edge(clk);

        for read_cycle in 0 to C_TEST_WORD_COUNT + 3 loop
            if read_cycle < C_TEST_WORD_COUNT then
                rd_en   <= '1';
                rd_addr <= read_cycle;
            else
                rd_en   <= '0';
                rd_addr <= 0;
            end if;

            wait until rising_edge(clk);
            wait for 1 ps;

            if rd_valid = '1' then
                assert rd_data = boundary_test_word(expected_read_index)
                report "Paged BRAM read mismatch at linear address " & integer'image(expected_read_index)
                severity failure;

                if expected_read_index >= C_PAGE_LAST_ADDR - 1 and expected_read_index <= C_PAGE_FIRST_ADDR + 1 then
                    report "BRAM boundary read address " & integer'image(expected_read_index)
                    severity note;
                end if;

                expected_read_index := expected_read_index + 1;
            end if;
        end loop;

        assert expected_read_index = C_TEST_WORD_COUNT
        report "Paged BRAM returned " & integer'image(expected_read_index) & " words instead of " & integer'image(C_TEST_WORD_COUNT)
        severity failure;

        report "TEST passed: paged BRAM 1023-to-1024 transition verified"
        severity note;
        stop;
    end process;

end architecture;
