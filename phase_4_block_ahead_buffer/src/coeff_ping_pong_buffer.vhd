library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity coeff_ping_pong_buffer is
    generic(
        G_TAP_COUNT     : positive := 32;
        G_SETS_PER_BANK : positive := 8;
        G_COEFF_WIDTH   : positive := 16
    );
    port(
        aclk                 : in  std_logic;
        aresetn              : in  std_logic;
        clear_errors         : in  std_logic;
        wr_valid             : in  std_logic;
        wr_ready             : out std_logic;
        wr_data              : in  std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
        wr_last              : in  std_logic;
        rd_tap_index         : in  integer range 0 to G_TAP_COUNT - 1;
        rd_data              : out std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
        consume_set_valid    : in  std_logic;
        consume_set_ready    : out std_logic;
        active_set_available : out std_logic;
        underrun             : out std_logic;
        write_error          : out std_logic
    );
end entity;

architecture rtl of coeff_ping_pong_buffer is

    subtype t_coeff_word   is std_logic_vector((2 * G_COEFF_WIDTH) - 1 downto 0);
    type    t_coeff_memory is array (0 to G_SETS_PER_BANK - 1, 0 to G_TAP_COUNT - 1) of t_coeff_word;

    signal r_bank0_data : t_coeff_memory := (others => (others => (others => '0')));
    signal r_bank1_data : t_coeff_memory := (others => (others => (others => '0')));

    signal r_active_bank       : std_logic := '0';
    signal r_active_bank_valid : std_logic := '0';
    signal r_bank0_ready       : std_logic := '0';
    signal r_bank1_ready       : std_logic := '0';

    signal r_write_set_count : integer range 0 to G_SETS_PER_BANK := 0;
    signal r_write_tap_count : integer range 0 to G_TAP_COUNT     := 0;
    signal r_read_set_count  : integer range 0 to G_SETS_PER_BANK := 0;

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
    signal w_read_set_index            : integer range 0 to G_SETS_PER_BANK - 1;

begin

    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                r_active_bank          <= '0';
                r_active_bank_valid    <= '0';
                r_bank0_ready          <= '0';
                r_bank1_ready          <= '0';
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
                    r_active_set_available <= w_next_active_set_available;
                    r_write_ready          <= w_next_write_ready;

                    if w_write_accept = '1' then
                        if w_write_bank = '0' then
                            r_bank0_data(r_write_set_count, r_write_tap_count) <= wr_data;
                        else
                            r_bank1_data(r_write_set_count, r_write_tap_count) <= wr_data;
                        end if;

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

                    if r_active_bank_valid = '1' and r_read_set_count = G_SETS_PER_BANK then
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
                        if r_read_set_count = G_SETS_PER_BANK - 1 then
                            if r_active_bank = '0' and w_bank1_ready_for_swap = '1' then
                                r_active_bank    <= '1';
                                r_bank0_ready    <= '0';
                                r_read_set_count <= 0;
                            elsif r_active_bank = '1' and w_bank0_ready_for_swap = '1' then
                                r_active_bank    <= '0';
                                r_bank1_ready    <= '0';
                                r_read_set_count <= 0;
                            else
                                r_read_set_count <= G_SETS_PER_BANK;
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

    w_write_bank                <= r_active_bank when r_active_bank_valid = '0' else not r_active_bank;
    w_write_ready               <= not r_bank0_ready when w_write_bank = '0' else not r_bank1_ready;
    w_next_write_ready          <= '0' when r_write_error = '1' else
                                   '0' when w_write_accept = '1' and (w_final_write_position = '1' or wr_last = '1') else
                                   w_write_ready;
    wr_ready                    <= r_write_ready and not clear_errors;
    w_write_accept              <= wr_valid and r_write_ready and not clear_errors;
    w_final_write_position      <= '1' when r_write_set_count = G_SETS_PER_BANK - 1 and r_write_tap_count = G_TAP_COUNT - 1 else '0';
    w_write_block_complete      <= w_write_accept and w_final_write_position and wr_last;
    w_bank0_ready_for_swap      <= r_bank0_ready or (w_write_block_complete and not w_write_bank);
    w_bank1_ready_for_swap      <= r_bank1_ready or (w_write_block_complete and w_write_bank);
    w_active_set_available      <= '1' when r_active_bank_valid = '1' and r_read_set_count < G_SETS_PER_BANK else '0';
    w_replacement_bank_ready    <= w_bank1_ready_for_swap when r_active_bank = '0' else w_bank0_ready_for_swap;
    w_consume_set_accept        <= consume_set_valid and r_active_set_available and not clear_errors;
    w_read_set_index            <= r_read_set_count when r_read_set_count < G_SETS_PER_BANK else 0;
    w_next_active_set_available <= '0' when clear_errors = '1' else
                                    -- First bank has just completed
                                   '1' when w_write_block_complete = '1' and r_active_bank_valid = '0' else  
                                   -- Recovering from underrun
                                   '1' when r_active_bank_valid = '1' and r_read_set_count = G_SETS_PER_BANK and w_replacement_bank_ready = '1' else
                                   -- Moving to the next set in the same bank
                                   '1' when w_consume_set_accept = '1' and r_read_set_count < G_SETS_PER_BANK - 1 else
                                   -- Final set consumed and replacement bank ready
                                   '1' when w_consume_set_accept = '1' and r_read_set_count = G_SETS_PER_BANK - 1 and w_replacement_bank_ready = '1' else
                                   -- Final set consumed without replacement bank
                                   '0' when w_consume_set_accept = '1' and r_read_set_count = G_SETS_PER_BANK - 1 else
                                   -- Maintain current availability
                                   '1' when w_active_set_available = '1' else
                                   '0';

    rd_data <= r_bank0_data(w_read_set_index, rd_tap_index) when r_active_bank = '0' and r_active_set_available = '1' else
               r_bank1_data(w_read_set_index, rd_tap_index) when r_active_bank = '1' and r_active_set_available = '1' else
               (others => '0');

    active_set_available <= r_active_set_available;
    consume_set_ready    <= r_active_set_available and not clear_errors;
    underrun             <= r_underrun;
    write_error          <= r_write_error;

end architecture;
