library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

entity coeff_ping_pong_uram is
    generic(
        G_TAP_COUNT         : positive := 32;
        G_MAX_SETS_PER_BANK : positive := 600;
        G_DATA_WIDTH        : positive := 32;
        G_READ_LATENCY      : positive := 3;
        G_CASCADE_HEIGHT    : natural  := 4
    );
    port(
        clk : in std_logic;

        wr_en        : in std_logic;
        wr_bank      : in std_logic;
        wr_set_index : in integer range 0 to G_MAX_SETS_PER_BANK - 1;
        wr_tap_index : in integer range 0 to G_TAP_COUNT - 1;
        wr_data      : in std_logic_vector(G_DATA_WIDTH - 1 downto 0);

        rd_en        : in  std_logic;
        rd_bank      : in  std_logic;
        rd_set_index : in  integer range 0 to G_MAX_SETS_PER_BANK - 1;
        rd_tap_index : in  integer range 0 to G_TAP_COUNT - 1;
        rd_data      : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        rd_valid     : out std_logic
    );
end entity;

architecture rtl of coeff_ping_pong_uram is

    function clog2(value : positive) return natural is
        variable temp   : natural := value - 1;
        variable result : natural := 0;
    begin
        while temp > 0 loop
            temp   := temp / 2;
            result := result + 1;
        end loop;

        return result;
    end function;

    constant C_WORDS_PER_BANK : positive := G_MAX_SETS_PER_BANK * G_TAP_COUNT;
    constant C_TOTAL_DEPTH    : positive := 2 * C_WORDS_PER_BANK;
    constant C_ADDR_WIDTH     : positive := clog2(C_TOTAL_DEPTH);
    constant C_MEMORY_SIZE    : positive := C_TOTAL_DEPTH * G_DATA_WIDTH;

    signal w_write_bank_base : integer range 0 to C_WORDS_PER_BANK;
    signal w_read_bank_base  : integer range 0 to C_WORDS_PER_BANK;
    signal w_write_address   : integer range 0 to C_TOTAL_DEPTH - 1;
    signal w_read_address    : integer range 0 to C_TOTAL_DEPTH - 1;
    signal w_write_address_v : std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
    signal w_read_address_v  : std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
    signal w_write_enable    : std_logic_vector(0 downto 0);

    signal r_read_enable    : std_logic := '0';
    signal r_read_address_v : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal r_read_valid_pipe : std_logic_vector(G_READ_LATENCY - 1 downto 0) := (others => '0');

begin

    w_write_bank_base <= 0 when wr_bank = '0' else C_WORDS_PER_BANK;
    w_read_bank_base  <= 0 when rd_bank = '0' else C_WORDS_PER_BANK;

    w_write_address <= w_write_bank_base + (wr_set_index * G_TAP_COUNT) + wr_tap_index;
    w_read_address  <= w_read_bank_base + (rd_set_index * G_TAP_COUNT) + rd_tap_index;

    w_write_address_v <= std_logic_vector(to_unsigned(w_write_address, C_ADDR_WIDTH));
    w_read_address_v  <= std_logic_vector(to_unsigned(w_read_address, C_ADDR_WIDTH));
    w_write_enable(0) <= wr_en;

    read_valid_process : process(clk)
    begin
        if rising_edge(clk) then
            r_read_enable    <= rd_en;
            r_read_address_v <= w_read_address_v;

            r_read_valid_pipe(0) <= r_read_enable;

            for i in 1 to G_READ_LATENCY - 1 loop
                r_read_valid_pipe(i) <= r_read_valid_pipe(i - 1);
            end loop;
        end if;
    end process;

    xpm_uram_inst : xpm_memory_sdpram
        generic map(
            MEMORY_SIZE             => C_MEMORY_SIZE,
            MEMORY_PRIMITIVE        => "ultra",
            CLOCKING_MODE           => "common_clock",
            ECC_MODE                => "no_ecc",
            ECC_TYPE                => "none",
            MEMORY_INIT_FILE        => "none",
            MEMORY_INIT_PARAM       => "",
            USE_MEM_INIT            => 0,
            USE_MEM_INIT_MMI        => 0,
            WAKEUP_TIME             => "disable_sleep",
            AUTO_SLEEP_TIME         => 0,
            MESSAGE_CONTROL         => 0,
            USE_EMBEDDED_CONSTRAINT => 0,
            MEMORY_OPTIMIZATION     => "true",
            CASCADE_HEIGHT          => G_CASCADE_HEIGHT,
            SIM_ASSERT_CHK          => 0,
            WRITE_PROTECT           => 1,
            WRITE_DATA_WIDTH_A      => G_DATA_WIDTH,
            BYTE_WRITE_WIDTH_A      => G_DATA_WIDTH,
            ADDR_WIDTH_A            => C_ADDR_WIDTH,
            RST_MODE_A              => "SYNC",
            READ_DATA_WIDTH_B       => G_DATA_WIDTH,
            ADDR_WIDTH_B            => C_ADDR_WIDTH,
            READ_RESET_VALUE_B      => "0",
            READ_LATENCY_B          => G_READ_LATENCY,
            WRITE_MODE_B            => "read_first",
            RST_MODE_B              => "SYNC"
        )
        port map(
            sleep          => '0',
            clka           => clk,
            ena            => wr_en,
            wea            => w_write_enable,
            addra          => w_write_address_v,
            dina           => wr_data,
            injectsbiterra => '0',
            injectdbiterra => '0',
            clkb           => clk,
            rstb           => '0',
            enb            => r_read_enable,
            regceb         => '1',
            addrb          => r_read_address_v,
            doutb          => rd_data,
            sbiterrb       => open,
            dbiterrb       => open
        );

    rd_valid <= r_read_valid_pipe(G_READ_LATENCY - 1);

end architecture;
