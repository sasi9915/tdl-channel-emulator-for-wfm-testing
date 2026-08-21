library ieee;
use ieee.std_logic_1164.all;

Library xpm;
use xpm.vcomponents.all;

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

architecture arc_xpm_fifo_sync_wrap of xpm_fifo_sync_wrap is

    signal w_reset : std_logic;
    signal w_empty : std_logic;
    signal r_q_val : std_logic;
    signal w_usedw : std_logic_vector(17 downto 0) := (others => '0');

    function f_mod_sel(x : boolean) return string is
    begin
        if (x) then
            return "fwft";
        else
            return "std";
        end if;
    end f_mod_sel;

    function f_read_latency_sel(x : boolean) return integer is
    begin
        if (x) then
            return 0;
        else
            return 1;
        end if;
    end f_read_latency_sel;

    function f_log2_size(A : natural) return natural is
    begin
        for I in 1 to 64 loop           -- Works for up to 64 bits
            if (2 ** I >= A) then
                return (I);
            end if;
        end loop;
        return (63);
    end function f_log2_size;

begin

    w_reset <= not (i_resetn);

    xpm_fifo_sync_inst : xpm_fifo_sync
        generic map(
            SIM_ASSERT_CHK      => 0,   -- DECIMAL; 0=disable simulation messages, 1=enable simulation messages
            FIFO_MEMORY_TYPE    => g_TYPE, --string; "auto", "block", "distributed", or "ultra" ;
            ECC_MODE            => "no_ecc", --string; "no_ecc" or "en_ecc";
            FIFO_WRITE_DEPTH    => g_DEPTH, --positive integer
            WRITE_DATA_WIDTH    => g_DATA_WIDTH, --positive integer
            WR_DATA_COUNT_WIDTH => f_log2_size(g_DEPTH) + 1, --positive integer
            PROG_FULL_THRESH    => g_ALMOST_FULL_THRESHOLD, --positive integer
            FULL_RESET_VALUE    => 0,   --positive integer; 0 or 1;
            USE_ADV_FEATURES    => "1F0F", --string; "0000" to "1F1F";
            READ_MODE           => f_mod_sel(g_FWFT_MODE_ENA), --string; "std" or "fwft";
            FIFO_READ_LATENCY   => f_read_latency_sel(g_FWFT_MODE_ENA), --positive integer;
            READ_DATA_WIDTH     => g_DATA_WIDTH, --positive integer
            RD_DATA_COUNT_WIDTH => f_log2_size(g_DEPTH) + 1, --positive integer
            PROG_EMPTY_THRESH   => g_ALMOST_EMPTY_THRESHOLD, --positive integer
            DOUT_RESET_VALUE    => "0", --string
            WAKEUP_TIME         => 0    --positive integer; 0 or 2;
        )
        port map(
            rst           => w_reset,
            wr_clk        => i_clk,
            wr_en         => i_wrreq,
            din           => i_data,
            full          => o_full,
            overflow      => open,
            wr_rst_busy   => open,
            prog_full     => o_almost_full,
            wr_data_count => w_usedw(f_log2_size(g_DEPTH) downto 0),
            almost_full   => open,
            wr_ack        => open,
            rd_en         => i_rdreq,
            dout          => o_q,
            empty         => w_empty,
            underflow     => open,
            rd_rst_busy   => open,
            prog_empty    => o_almost_empty,
            rd_data_count => open,
            almost_empty  => open,
            data_valid    => open,
            sleep         => '0',
            injectsbiterr => '0',
            injectdbiterr => '0',
            sbiterr       => open,
            dbiterr       => open
        );

    process(i_resetn, i_clk) is
    begin
        if i_resetn = '0' then
            r_q_val <= '0';
        elsif i_clk'event and i_clk = '1' then
            r_q_val <= i_rdreq and not (w_empty);
        end if;
    end process;

    o_q_val <= i_rdreq and not (w_empty) when (g_FWFT_MODE_ENA) else r_q_val;
    o_usedw <= w_usedw(15 downto 0);
    o_empty <= w_empty;

end arc_xpm_fifo_sync_wrap;
