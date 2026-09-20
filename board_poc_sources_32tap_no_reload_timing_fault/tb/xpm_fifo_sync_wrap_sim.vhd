library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity xpm_fifo_sync_wrap is
    generic(
        g_TYPE                   : string  := "block";
        g_DATA_WIDTH             : natural := 10;
        g_DEPTH                  : natural := 1024;
        g_FWFT_MODE_ENA          : boolean := true;
        g_ALMOST_FULL_THRESHOLD  : integer := 128 - 8;
        g_ALMOST_EMPTY_THRESHOLD : integer := 8
    );
    port(
        i_resetn       : in  std_logic;
        i_clk          : in  std_logic;
        i_wrreq        : in  std_logic;
        i_data         : in  std_logic_vector(g_DATA_WIDTH - 1 downto 0);
        i_rdreq        : in  std_logic;
        o_q_val        : out std_logic                                   := '0';
        o_q            : out std_logic_vector(g_DATA_WIDTH - 1 downto 0) := (others => '0');
        o_usedw        : out std_logic_vector(15 downto 0)               := (others => '0');
        o_full         : out std_logic                                   := '0';
        o_empty        : out std_logic                                   := '0';
        o_almost_full  : out std_logic                                   := '0';
        o_almost_empty : out std_logic                                   := '0'
    );
end entity;

architecture sim of xpm_fifo_sync_wrap is

    type t_fifo_mem is array (0 to g_DEPTH - 1) of std_logic_vector(g_DATA_WIDTH - 1 downto 0);

    signal r_mem    : t_fifo_mem := (others => (others => '0'));
    signal r_wr_ptr : integer range 0 to g_DEPTH - 1 := 0;
    signal r_rd_ptr : integer range 0 to g_DEPTH - 1 := 0;
    signal r_count  : integer range 0 to g_DEPTH     := 0;

begin

    process(i_resetn, i_clk)
        variable v_count  : integer range 0 to g_DEPTH;
        variable v_wr_ptr : integer range 0 to g_DEPTH - 1;
        variable v_rd_ptr : integer range 0 to g_DEPTH - 1;
    begin
        if i_resetn = '0' then
            r_wr_ptr <= 0;
            r_rd_ptr <= 0;
            r_count  <= 0;
        elsif rising_edge(i_clk) then
            v_count  := r_count;
            v_wr_ptr := r_wr_ptr;
            v_rd_ptr := r_rd_ptr;

            if i_wrreq = '1' and v_count < g_DEPTH then
                r_mem(v_wr_ptr) <= i_data;

                if v_wr_ptr = g_DEPTH - 1 then
                    v_wr_ptr := 0;
                else
                    v_wr_ptr := v_wr_ptr + 1;
                end if;

                v_count := v_count + 1;
            end if;

            if i_rdreq = '1' and v_count > 0 then
                if v_rd_ptr = g_DEPTH - 1 then
                    v_rd_ptr := 0;
                else
                    v_rd_ptr := v_rd_ptr + 1;
                end if;

                v_count := v_count - 1;
            end if;

            r_wr_ptr <= v_wr_ptr;
            r_rd_ptr <= v_rd_ptr;
            r_count  <= v_count;
        end if;
    end process;

    o_q            <= r_mem(r_rd_ptr) when r_count > 0 else (others => '0');
    o_q_val        <= i_rdreq and not o_empty;
    o_usedw        <= std_logic_vector(to_unsigned(r_count, o_usedw'length));
    o_full         <= '1' when r_count = g_DEPTH else '0';
    o_empty        <= '1' when r_count = 0 else '0';
    o_almost_full  <= '1' when r_count >= g_ALMOST_FULL_THRESHOLD else '0';
    o_almost_empty <= '1' when r_count <= g_ALMOST_EMPTY_THRESHOLD else '0';

end architecture;
