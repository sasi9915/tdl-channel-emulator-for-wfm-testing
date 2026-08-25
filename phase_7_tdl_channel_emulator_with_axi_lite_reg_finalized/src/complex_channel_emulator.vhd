library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity complex_channel_emulator is
    port(
        aclk                      : in  std_logic;
        aresetn                   : in  std_logic;
        -- Complex input:
        -- TDATA[15:0]  = I
        -- TDATA[31:16] = Q
        s_axis_tvalid             : in  std_logic;
        s_axis_tready             : out std_logic;
        s_axis_tdata              : in  std_logic_vector(31 downto 0);
        s_axis_tlast              : in  std_logic;
        ---adding the ports related to CONFIG and RELOAD interfaces for FIR_REAL and FIR_IMAG
        -- real component 
        s_axis_config_real_tvalid : in  std_logic;
        s_axis_config_real_tready : out std_logic;
        s_axis_config_real_tdata  : in  std_logic_vector(7 downto 0);
        s_axis_reload_real_tvalid : in  std_logic;
        s_axis_reload_real_tready : out std_logic;
        s_axis_reload_real_tdata  : in  std_logic_vector(15 downto 0);
        s_axis_reload_real_tlast  : in  std_logic;
        -- imaginary componnet
        s_axis_config_imag_tvalid : in  std_logic;
        s_axis_config_imag_tready : out std_logic;
        s_axis_config_imag_tdata  : in  std_logic_vector(7 downto 0);
        s_axis_reload_imag_tvalid : in  std_logic;
        s_axis_reload_imag_tready : out std_logic;
        s_axis_reload_imag_tdata  : in  std_logic_vector(15 downto 0);
        s_axis_reload_imag_tlast  : in  std_logic;
        -- Complex output:
        -- TDATA[39:0]  = output I, signed 40-bit field
        -- TDATA[79:40] = output Q, signed 40-bit field
        m_axis_tvalid             : out std_logic;
        m_axis_tready             : in  std_logic;
        m_axis_tdata              : out std_logic_vector(79 downto 0);
        m_axis_tlast              : out std_logic;
        fir_reload_error          : out std_logic
    );
end entity;

architecture rtl of complex_channel_emulator is

    component fir_compiler_invest_real_comp is
        port(
            aclk                            : in  std_logic;
            aresetn                         : in  std_logic;
            s_axis_config_tvalid            : in  std_logic;
            s_axis_config_tready            : out std_logic;
            s_axis_config_tdata             : in  std_logic_vector(7 downto 0);
            s_axis_reload_tvalid            : in  std_logic;
            s_axis_reload_tready            : out std_logic;
            s_axis_reload_tdata             : in  std_logic_vector(15 downto 0);
            s_axis_reload_tlast             : in  std_logic;
            s_axis_data_tvalid              : in  std_logic;
            s_axis_data_tready              : out std_logic;
            s_axis_data_tdata               : in  std_logic_vector(31 downto 0);
            s_axis_data_tlast               : in  std_logic;
            m_axis_data_tvalid              : out std_logic;
            m_axis_data_tready              : in  std_logic;
            m_axis_data_tdata               : out std_logic_vector(79 downto 0);
            m_axis_data_tlast               : out std_logic;
            event_s_reload_tlast_missing    : out std_logic;
            event_s_reload_tlast_unexpected : out std_logic
        );
    end component;

    component fir_compiler_invest_imag_comp is
        port(
            aclk                            : in  std_logic;
            aresetn                         : in  std_logic;
            s_axis_config_tvalid            : in  std_logic;
            s_axis_config_tready            : out std_logic;
            s_axis_config_tdata             : in  std_logic_vector(7 downto 0);
            s_axis_reload_tvalid            : in  std_logic;
            s_axis_reload_tready            : out std_logic;
            s_axis_reload_tdata             : in  std_logic_vector(15 downto 0);
            s_axis_reload_tlast             : in  std_logic;
            s_axis_data_tvalid              : in  std_logic;
            s_axis_data_tready              : out std_logic;
            s_axis_data_tdata               : in  std_logic_vector(31 downto 0);
            s_axis_data_tlast               : in  std_logic;
            m_axis_data_tvalid              : out std_logic;
            m_axis_data_tready              : in  std_logic;
            m_axis_data_tdata               : out std_logic_vector(79 downto 0);
            m_axis_data_tlast               : out std_logic;
            event_s_reload_tlast_missing    : out std_logic;
            event_s_reload_tlast_unexpected : out std_logic
        );
    end component;

    -- Input distribution buffer
    signal r_input_data         : std_logic_vector(31 downto 0) := (others => '0');
    signal r_input_last         : std_logic                     := '0';
    signal r_real_input_pending : std_logic                     := '0';
    signal r_imag_input_pending : std_logic                     := '0';
    signal w_input_ready        : std_logic;

    -- FIR real input interface
    signal w_real_s_tvalid : std_logic;
    signal w_real_s_tready : std_logic;

    -- FIR imaginary input interface
    signal w_imag_s_tvalid : std_logic;
    signal w_imag_s_tready : std_logic;

    -- FIR real output interface
    signal w_real_m_tvalid : std_logic;
    signal w_real_m_tready : std_logic;
    signal w_real_m_tdata  : std_logic_vector(79 downto 0);
    signal w_real_m_tlast  : std_logic;

    -- FIR imaginary output interface
    signal w_imag_m_tvalid                : std_logic;
    signal w_imag_m_tready                : std_logic;
    signal w_imag_m_tdata                 : std_logic_vector(79 downto 0);
    signal w_imag_m_tlast                 : std_logic;
    signal w_output_valid                 : std_logic;
    signal w_real_reload_tlast_missing    : std_logic;
    signal w_real_reload_tlast_unexpected : std_logic;
    signal w_imag_reload_tlast_missing    : std_logic;
    signal w_imag_reload_tlast_unexpected : std_logic;

    -- FIR output paths
    signal w_i_hr : signed(36 downto 0);
    signal w_q_hr : signed(36 downto 0);
    signal w_i_hi : signed(36 downto 0);
    signal w_q_hi : signed(36 downto 0);

    -- Complex result, one extra bit for addition/subtraction
    signal w_output_i : signed(37 downto 0);
    signal w_output_q : signed(37 downto 0);

begin

    -- Store one input transaction and independently deliver in to both FIR instances.
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                r_input_data         <= (others => '0');
                r_input_last         <= '0';
                r_real_input_pending <= '0';
                r_imag_input_pending <= '0';
            else
                -- Clear each pending flag when that FIR accepts the sample.
                if r_real_input_pending = '1' and w_real_s_tready = '1' then
                    r_real_input_pending <= '0';
                end if;

                if r_imag_input_pending = '1' and w_imag_s_tready = '1' then
                    r_imag_input_pending <= '0';
                end if;

                -- Capture a new packed I/Q input.
                if s_axis_tvalid = '1' and w_input_ready = '1' then
                    r_input_data         <= s_axis_tdata;
                    r_input_last         <= s_axis_tlast;
                    r_real_input_pending <= '1';
                    r_imag_input_pending <= '1';
                end if;
            end if;
        end if;
    end process;

    -- Check that the two identical FIR configurations remain aligned.
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '1' then
                if w_real_m_tvalid = '1' and w_imag_m_tvalid = '1' then
                    assert w_real_m_tlast = w_imag_m_tlast
                    report "FIR_REAL and FIR_IMAG TLAST mismatch"
                    severity error;
                end if;
            end if;
        end if;
    end process;

    w_real_s_tvalid <= r_real_input_pending;
    w_imag_s_tvalid <= r_imag_input_pending;

    -- Extract the four real convolutions
    -- FIR_REAL:  Path 0 = I*hR and  Path 1 = Q*hR
    w_i_hr <= signed(w_real_m_tdata(36 downto 0));
    w_q_hr <= signed(w_real_m_tdata(76 downto 40));
    -- FIR_IMAG: Path 0 = I*hI  and Path 1 = Q*hI
    w_i_hi <= signed(w_imag_m_tdata(36 downto 0));
    w_q_hi <= signed(w_imag_m_tdata(76 downto 40));

    -- output I = I*hR - Q*hI   / output Q = I*hI + Q*hR
    w_output_i      <= resize(w_i_hr, w_output_i'length) - resize(w_q_hi, w_output_i'length);
    w_output_q      <= resize(w_i_hi, w_output_q'length) + resize(w_q_hr, w_output_q'length);
    -- Consume both FIR outputs together.
    w_real_m_tready <= m_axis_tready and w_imag_m_tvalid;
    w_imag_m_tready <= m_axis_tready and w_real_m_tvalid;

    -- Accept a new TX sample only after both FIRs have accepte the previous sample.
    w_input_ready              <= not (r_real_input_pending or r_imag_input_pending);
    s_axis_tready              <= w_input_ready;
    -- Only present an output after both FIR results are available.
    w_output_valid             <= w_real_m_tvalid and w_imag_m_tvalid;
    m_axis_tvalid              <= w_output_valid;
    m_axis_tdata(39 downto 0)  <= std_logic_vector(resize(w_output_i, 40)); -- Place each 38-bit result in a sign-extended 40-bit field.
    m_axis_tdata(79 downto 40) <= std_logic_vector(resize(w_output_q, 40)); -- Place each 38-bit result in a sign-extended 40-bit field.
    m_axis_tlast               <= w_real_m_tlast and w_output_valid;
    fir_reload_error           <= w_real_reload_tlast_missing or w_real_reload_tlast_unexpected or w_imag_reload_tlast_missing or w_imag_reload_tlast_unexpected;

    -- FIR using the real channel coefficients hR
    u_fir_real : fir_compiler_invest_real_comp
        port map(
            aclk                            => aclk,
            aresetn                         => aresetn,
            s_axis_config_tvalid            => s_axis_config_real_tvalid,
            s_axis_config_tready            => s_axis_config_real_tready,
            s_axis_config_tdata             => s_axis_config_real_tdata,
            s_axis_reload_tvalid            => s_axis_reload_real_tvalid,
            s_axis_reload_tready            => s_axis_reload_real_tready,
            s_axis_reload_tdata             => s_axis_reload_real_tdata,
            s_axis_reload_tlast             => s_axis_reload_real_tlast,
            s_axis_data_tvalid              => w_real_s_tvalid,
            s_axis_data_tready              => w_real_s_tready,
            s_axis_data_tdata               => r_input_data,
            s_axis_data_tlast               => r_input_last,
            m_axis_data_tvalid              => w_real_m_tvalid,
            m_axis_data_tready              => w_real_m_tready,
            m_axis_data_tdata               => w_real_m_tdata,
            m_axis_data_tlast               => w_real_m_tlast,
            event_s_reload_tlast_missing    => w_real_reload_tlast_missing,
            event_s_reload_tlast_unexpected => w_real_reload_tlast_unexpected
        );

    -- FIR using the imaginary channel coefficients hI
    u_fir_imag : fir_compiler_invest_imag_comp
        port map(
            aclk                            => aclk,
            aresetn                         => aresetn,
            s_axis_config_tvalid            => s_axis_config_imag_tvalid,
            s_axis_config_tready            => s_axis_config_imag_tready,
            s_axis_config_tdata             => s_axis_config_imag_tdata,
            s_axis_reload_tvalid            => s_axis_reload_imag_tvalid,
            s_axis_reload_tready            => s_axis_reload_imag_tready,
            s_axis_reload_tdata             => s_axis_reload_imag_tdata,
            s_axis_reload_tlast             => s_axis_reload_imag_tlast,
            s_axis_data_tvalid              => w_imag_s_tvalid,
            s_axis_data_tready              => w_imag_s_tready,
            s_axis_data_tdata               => r_input_data,
            s_axis_data_tlast               => r_input_last,
            m_axis_data_tvalid              => w_imag_m_tvalid,
            m_axis_data_tready              => w_imag_m_tready,
            m_axis_data_tdata               => w_imag_m_tdata,
            m_axis_data_tlast               => w_imag_m_tlast,
            event_s_reload_tlast_missing    => w_imag_reload_tlast_missing,
            event_s_reload_tlast_unexpected => w_imag_reload_tlast_unexpected
        );

end architecture;
