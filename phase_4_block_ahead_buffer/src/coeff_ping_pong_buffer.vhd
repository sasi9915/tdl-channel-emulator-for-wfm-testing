library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity coeff_ping_pong_buffer is
    generic(
        G_TAP_COUNT         : positive := 128;
        G_MAX_SETS_PER_BANK : positive := 600;
        G_COEFF_WIDTH       : positive := 16;
        G_RAM_STYLE           : string   := "ultra";
        G_URAM_READ_LATENCY   : positive := 3;
        G_URAM_CASCADE_HEIGHT : natural := 4
    );
    port(
        aclk                 : in  std_logic;
        aresetn              : in  std_logic;
        clear_errors         : in  std_logic;
        cfg_sets_per_bank    : in  integer range 1 to G_MAX_SETS_PER_BANK;
        wr_valid             : in  std_logic;
        wr_ready             : out std_logic;
        wr_data              : in  std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
        wr_last              : in  std_logic;
        rd_en                : in  std_logic;
        rd_tap_index         : in  integer range 0 to G_TAP_COUNT - 1;
        rd_data              : out std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
        rd_valid             : out std_logic;
        consume_set_valid    : in  std_logic;
        consume_set_ready    : out std_logic;
        active_set_available : out std_logic;
        underrun             : out std_logic;
        write_error          : out std_logic
    );
end entity;

architecture rtl of coeff_ping_pong_buffer is

    -- component instantiation

    component coeff_ping_pong_bram is
        generic(
            G_TAP_COUNT         : positive := 128;
            G_MAX_SETS_PER_BANK : positive := 600;
            G_DATA_WIDTH        : positive := 32;
            G_RAM_STYLE         : string   := "block"
        );
        port(
            clk          : in  std_logic;
            wr_en        : in  std_logic;
            wr_bank      : in  std_logic;
            wr_set_index : in  integer range 0 to G_MAX_SETS_PER_BANK - 1;
            wr_tap_index : in  integer range 0 to G_TAP_COUNT - 1;
            wr_data      : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
            rd_en        : in  std_logic;
            rd_bank      : in  std_logic;
            rd_set_index : in  integer range 0 to G_MAX_SETS_PER_BANK - 1;
            rd_tap_index : in  integer range 0 to G_TAP_COUNT - 1;
            rd_data      : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
            rd_valid     : out std_logic
        );
    end component;

    component coeff_ping_pong_uram is
        generic(
            G_TAP_COUNT         : positive := 128;
            G_MAX_SETS_PER_BANK : positive := 600;
            G_DATA_WIDTH        : positive := 32;
            G_READ_LATENCY      : positive := 3;
            G_CASCADE_HEIGHT    : natural  := 4
        );
        port(
            clk          : in  std_logic;
            wr_en        : in  std_logic;
            wr_bank      : in  std_logic;
            wr_set_index : in  integer range 0 to G_MAX_SETS_PER_BANK - 1;
            wr_tap_index : in  integer range 0 to G_TAP_COUNT - 1;
            wr_data      : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
            rd_en        : in  std_logic;
            rd_bank      : in  std_logic;
            rd_set_index : in  integer range 0 to G_MAX_SETS_PER_BANK - 1;
            rd_tap_index : in  integer range 0 to G_TAP_COUNT - 1;
            rd_data      : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
            rd_valid     : out std_logic
        );
    end component;

    subtype t_coeff_word is std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);

    signal r_active_bank       : std_logic := '0';
    signal r_active_bank_valid : std_logic := '0';
    signal r_bank0_ready       : std_logic := '0';
    signal r_bank1_ready       : std_logic := '0';

    signal r_sets_per_bank   : integer range 1 to G_MAX_SETS_PER_BANK := G_MAX_SETS_PER_BANK;
    signal r_write_set_count : integer range 0 to G_MAX_SETS_PER_BANK := 0;
    signal r_write_tap_count : integer range 0 to G_TAP_COUNT         := 0;
    signal r_read_set_count  : integer range 0 to G_MAX_SETS_PER_BANK := 0;

    signal r_active_set_available : std_logic := '0';
    signal r_write_ready          : std_logic := '0';
    signal r_underrun             : std_logic := '0';
    signal r_write_error          : std_logic := '0';

    signal w_write_bank                : std_logic;
    signal w_write_ready               : std_logic;
    signal w_next_write_ready          : std_logic;
    signal w_write_accept              : std_logic;
    signal w_final_write_position      : std_logic;
    signal w_write_block_complete      : std_logic;
    signal w_bank0_ready_for_swap      : std_logic;
    signal w_bank1_ready_for_swap      : std_logic;
    signal w_active_set_available      : std_logic;
    signal w_replacement_bank_ready    : std_logic;
    signal w_next_active_set_available : std_logic;
    signal w_consume_set_accept        : std_logic;
    signal w_both_banks_empty          : std_logic;

    signal w_safe_write_set_index : integer range 0 to G_MAX_SETS_PER_BANK - 1;
    signal w_safe_write_tap_index : integer range 0 to G_TAP_COUNT - 1;
    signal w_safe_read_set_index  : integer range 0 to G_MAX_SETS_PER_BANK - 1;

    signal w_ram_read_enable : std_logic;
    signal w_ram_read_data   : t_coeff_word;
    signal w_ram_read_valid  : std_logic;

begin

    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                r_active_bank          <= '0';
                r_active_bank_valid    <= '0';
                r_bank0_ready          <= '0';
                r_bank1_ready          <= '0';
                r_sets_per_bank        <= cfg_sets_per_bank;
                r_write_set_count      <= 0;
                r_write_tap_count      <= 0;
                r_read_set_count       <= 0;
                r_active_set_available <= '0';
                r_write_ready          <= '0';
                r_underrun             <= '0';
                r_write_error          <= '0';
            else
                if clear_errors = '1' then
                    r_active_set_available <= '0';
                    r_write_ready          <= '0';
                    r_underrun             <= '0';
                    r_write_error          <= '0';

                    if r_write_error = '1' then
                        r_write_set_count <= 0;
                        r_write_tap_count <= 0;
                    end if;
                else
                    if w_both_banks_empty = '1' and r_write_set_count = 0 and r_write_tap_count = 0 then
                        r_sets_per_bank <= cfg_sets_per_bank;
                    end if;

                    r_active_set_available <= w_next_active_set_available;
                    r_write_ready          <= w_next_write_ready;

                    if w_write_accept = '1' then
                        if w_final_write_position = '1' then
                            if wr_last = '1' then
                                if w_write_bank = '0' then
                                    r_bank0_ready <= '1';
                                else
                                    r_bank1_ready <= '1';
                                end if;

                                if r_active_bank_valid = '0' then
                                    r_active_bank <= w_write_bank;
                                end if;

                                r_active_bank_valid <= '1';
                            else
                                r_write_error <= '1';
                            end if;

                            r_write_set_count <= 0;
                            r_write_tap_count <= 0;
                        elsif wr_last = '1' then
                            r_write_error     <= '1';
                            r_write_set_count <= 0;
                            r_write_tap_count <= 0;
                        elsif r_write_tap_count = G_TAP_COUNT - 1 then
                            r_write_tap_count <= 0;
                            r_write_set_count <= r_write_set_count + 1;
                        else
                            r_write_tap_count <= r_write_tap_count + 1;
                        end if;
                    end if;

                    if r_active_bank_valid = '1' and r_read_set_count = r_sets_per_bank then
                        if r_active_bank = '0' and w_bank1_ready_for_swap = '1' then
                            r_active_bank    <= '1';
                            r_bank0_ready    <= '0';
                            r_read_set_count <= 0;
                            r_underrun       <= '0';
                        elsif r_active_bank = '1' and w_bank0_ready_for_swap = '1' then
                            r_active_bank    <= '0';
                            r_bank1_ready    <= '0';
                            r_read_set_count <= 0;
                            r_underrun       <= '0';
                        else
                            r_underrun <= '1';
                        end if;
                    end if;

                    if w_consume_set_accept = '1' then
                        if r_read_set_count = r_sets_per_bank - 1 then
                            if r_active_bank = '0' and w_bank1_ready_for_swap = '1' then
                                r_active_bank    <= '1';
                                r_bank0_ready    <= '0';
                                r_read_set_count <= 0;
                            elsif r_active_bank = '1' and w_bank0_ready_for_swap = '1' then
                                r_active_bank    <= '0';
                                r_bank1_ready    <= '0';
                                r_read_set_count <= 0;
                            else
                                r_read_set_count <= r_sets_per_bank;
                                r_underrun       <= '1';
                            end if;
                        else
                            r_read_set_count <= r_read_set_count + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    gen_uram_memory : if G_RAM_STYLE = "ultra" generate
        coeff_memory_inst : coeff_ping_pong_uram
            generic map(
                G_TAP_COUNT         => G_TAP_COUNT,
                G_MAX_SETS_PER_BANK => G_MAX_SETS_PER_BANK,
                G_DATA_WIDTH        => 2 * G_COEFF_WIDTH,
                G_READ_LATENCY      => G_URAM_READ_LATENCY,
                G_CASCADE_HEIGHT    => G_URAM_CASCADE_HEIGHT
            )
            port map(
                clk          => aclk,
                wr_en        => w_write_accept,
                wr_bank      => w_write_bank,
                wr_set_index => w_safe_write_set_index,
                wr_tap_index => w_safe_write_tap_index,
                wr_data      => wr_data,
                rd_en        => w_ram_read_enable,
                rd_bank      => r_active_bank,
                rd_set_index => w_safe_read_set_index,
                rd_tap_index => rd_tap_index,
                rd_data      => w_ram_read_data,
                rd_valid     => w_ram_read_valid
            );
    end generate;

    gen_inferred_memory : if G_RAM_STYLE /= "ultra" generate
        coeff_memory_inst : coeff_ping_pong_bram
            generic map(
                G_TAP_COUNT         => G_TAP_COUNT,
                G_MAX_SETS_PER_BANK => G_MAX_SETS_PER_BANK,
                G_DATA_WIDTH        => 2 * G_COEFF_WIDTH,
                G_RAM_STYLE         => G_RAM_STYLE
            )
            port map(
                clk          => aclk,
                wr_en        => w_write_accept,
                wr_bank      => w_write_bank,
                wr_set_index => w_safe_write_set_index,
                wr_tap_index => w_safe_write_tap_index,
                wr_data      => wr_data,
                rd_en        => w_ram_read_enable,
                rd_bank      => r_active_bank,
                rd_set_index => w_safe_read_set_index,
                rd_tap_index => rd_tap_index,
                rd_data      => w_ram_read_data,
                rd_valid     => w_ram_read_valid
            );
    end generate;

    w_write_bank                <= r_active_bank when r_active_bank_valid = '0' else not r_active_bank;
    w_write_ready               <= not r_bank0_ready when w_write_bank = '0' else not r_bank1_ready;
    w_next_write_ready          <= '0' when r_write_error = '1' else
                                   '0' when w_write_accept = '1' and (w_final_write_position = '1' or wr_last = '1') else
                                   w_write_ready;
    wr_ready                    <= r_write_ready and not clear_errors;
    w_write_accept              <= wr_valid and r_write_ready and not clear_errors;
    w_final_write_position      <= '1' when r_write_set_count = r_sets_per_bank - 1 and r_write_tap_count = G_TAP_COUNT - 1 else '0';
    w_write_block_complete      <= w_write_accept and w_final_write_position and wr_last;
    w_bank0_ready_for_swap      <= r_bank0_ready or (w_write_block_complete and not w_write_bank);
    w_bank1_ready_for_swap      <= r_bank1_ready or (w_write_block_complete and w_write_bank);
    w_active_set_available      <= '1' when r_active_bank_valid = '1' and r_read_set_count < r_sets_per_bank else '0';
    w_replacement_bank_ready    <= w_bank1_ready_for_swap when r_active_bank = '0' else w_bank0_ready_for_swap;
    w_consume_set_accept        <= consume_set_valid and r_active_set_available and not clear_errors;
    w_both_banks_empty          <= '1' when r_active_bank_valid = '0' and r_bank0_ready = '0' and r_bank1_ready = '0' else '0';
    w_safe_write_set_index      <= r_write_set_count when r_write_set_count < G_MAX_SETS_PER_BANK else 0;
    w_safe_write_tap_index      <= r_write_tap_count when r_write_tap_count < G_TAP_COUNT else 0;
    w_safe_read_set_index       <= r_read_set_count when r_read_set_count < r_sets_per_bank else 0;
    w_ram_read_enable           <= rd_en and r_active_set_available and not clear_errors;
    w_next_active_set_available <= '0' when clear_errors = '1' else
                                   '1' when w_write_block_complete = '1' and r_active_bank_valid = '0' else
                                   '1' when r_active_bank_valid = '1' and r_read_set_count = r_sets_per_bank and w_replacement_bank_ready = '1' else
                                   '1' when w_consume_set_accept = '1' and r_read_set_count < r_sets_per_bank - 1 else
                                   '1' when w_consume_set_accept = '1' and r_read_set_count = r_sets_per_bank - 1 and w_replacement_bank_ready = '1' else
                                   '0' when w_consume_set_accept = '1' and r_read_set_count = r_sets_per_bank - 1 else
                                   '1' when w_active_set_available = '1' else
                                   '0';

    rd_data <= w_ram_read_data when w_ram_read_valid = '1' else (others => '0');

    rd_valid             <= w_ram_read_valid;
    active_set_available <= r_active_set_available;
    consume_set_ready    <= r_active_set_available and not clear_errors;
    underrun             <= r_underrun;
    write_error          <= r_write_error;

end architecture;
