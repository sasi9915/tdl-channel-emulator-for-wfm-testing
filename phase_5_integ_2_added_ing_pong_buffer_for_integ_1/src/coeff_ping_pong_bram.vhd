library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity coeff_ping_pong_bram is
    generic(
        G_TAP_COUNT         : positive := 32;
        G_MAX_SETS_PER_BANK : positive := 600;
        G_DATA_WIDTH        : positive := 32;
        G_RAM_STYLE         : string   := "block"
    );
    port(
        clk : in std_logic;

        wr_en   : in std_logic;
        wr_addr : in integer range 0 to (2 * G_MAX_SETS_PER_BANK * G_TAP_COUNT) - 1;
        wr_data : in std_logic_vector(G_DATA_WIDTH - 1 downto 0);

        rd_en    : in  std_logic;
        rd_addr  : in  integer range 0 to (2 * G_MAX_SETS_PER_BANK * G_TAP_COUNT) - 1;
        rd_data  : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        rd_valid : out std_logic
    );
end entity;

architecture rtl of coeff_ping_pong_bram is

    constant C_WORDS_PER_BANK : positive := G_MAX_SETS_PER_BANK * G_TAP_COUNT;
    constant C_TOTAL_DEPTH    : positive := 2 * C_WORDS_PER_BANK;

    type t_ram is array (0 to C_TOTAL_DEPTH - 1) of std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    signal r_ram : t_ram;

    signal r_read_data  : std_logic_vector(G_DATA_WIDTH - 1 downto 0) := (others => '0');
    signal r_read_valid : std_logic := '0';

    attribute ram_style : string;
    attribute ram_style of r_ram : signal is G_RAM_STYLE;

begin

    ram_process : process(clk)
    begin
        if rising_edge(clk) then
            if wr_en = '1' then
                r_ram(wr_addr) <= wr_data;
            end if;

            if rd_en = '1' then
                r_read_data <= r_ram(rd_addr);
            end if;

            r_read_valid <= rd_en;
        end if;
    end process;

    rd_data  <= r_read_data;
    rd_valid <= r_read_valid;

end architecture;
