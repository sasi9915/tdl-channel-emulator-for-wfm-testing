library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity coeff_ping_pong_bram_page is
    generic(
        G_PAGE_DEPTH : positive := 1024;
        G_DATA_WIDTH : positive := 32;
        G_RAM_STYLE  : string   := "block"
    );
    port(
        clk : in std_logic;

        wr_en   : in std_logic;
        wr_addr : in integer range 0 to G_PAGE_DEPTH - 1;
        wr_data : in std_logic_vector(G_DATA_WIDTH - 1 downto 0);

        rd_en    : in  std_logic;
        rd_addr  : in  integer range 0 to G_PAGE_DEPTH - 1;
        rd_data  : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        rd_valid : out std_logic
    );
end entity;

architecture rtl of coeff_ping_pong_bram_page is

    type t_ram is array (0 to G_PAGE_DEPTH - 1) of std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    signal r_ram        : t_ram;
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
    constant C_PAGE_DEPTH     : positive := 1024;
    constant C_PAGE_COUNT     : positive := (C_TOTAL_DEPTH + C_PAGE_DEPTH - 1) / C_PAGE_DEPTH;

    subtype t_page_index is integer range 0 to C_PAGE_COUNT - 1;
    subtype t_page_addr is integer range 0 to C_PAGE_DEPTH - 1;

    type t_page_data_array is array (0 to C_PAGE_COUNT - 1) of std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    signal w_write_page      : t_page_index;
    signal w_write_page_addr : t_page_addr;
    signal w_read_page       : t_page_index;
    signal w_read_page_addr  : t_page_addr;
    signal w_page_read_data  : t_page_data_array;
    signal w_page_read_valid : std_logic_vector(0 to C_PAGE_COUNT - 1);
    signal r_read_data       : std_logic_vector(G_DATA_WIDTH - 1 downto 0) := (others => '0');
    signal r_read_valid      : std_logic := '0';

    function f_page_index(address : integer) return t_page_index is
    begin
        return address / C_PAGE_DEPTH;
    end function;

    function f_page_addr(address : integer) return t_page_addr is
    begin
        return address mod C_PAGE_DEPTH;
    end function;

begin

    w_write_page      <= f_page_index(wr_addr);
    w_write_page_addr <= f_page_addr(wr_addr);
    w_read_page       <= f_page_index(rd_addr);
    w_read_page_addr  <= f_page_addr(rd_addr);

    page_gen : for page_index in 0 to C_PAGE_COUNT - 1 generate
        signal page_wr_en : std_logic;
        signal page_rd_en : std_logic;
    begin
        page_wr_en <= wr_en when w_write_page = page_index else '0';
        page_rd_en <= rd_en when w_read_page = page_index else '0';

        page_inst : entity work.coeff_ping_pong_bram_page
            generic map(
                G_PAGE_DEPTH => C_PAGE_DEPTH,
                G_DATA_WIDTH => G_DATA_WIDTH,
                G_RAM_STYLE  => G_RAM_STYLE
            )
            port map(
                clk      => clk,
                wr_en    => page_wr_en,
                wr_addr  => w_write_page_addr,
                wr_data  => wr_data,
                rd_en    => page_rd_en,
                rd_addr  => w_read_page_addr,
                rd_data  => w_page_read_data(page_index),
                rd_valid => w_page_read_valid(page_index)
            );
    end generate;

    read_output_select_process : process(clk)
        variable v_read_data  : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        variable v_read_valid : std_logic;
    begin
        if rising_edge(clk) then
            v_read_data  := (others => '0');
            v_read_valid := '0';

            for page_index in 0 to C_PAGE_COUNT - 1 loop
                if w_page_read_valid(page_index) = '1' then
                    v_read_data  := v_read_data or w_page_read_data(page_index);
                    v_read_valid := '1';
                end if;
            end loop;

            r_read_data  <= v_read_data;
            r_read_valid <= v_read_valid;
        end if;
    end process;

    rd_data  <= r_read_data;
    rd_valid <= r_read_valid;

end architecture;

 