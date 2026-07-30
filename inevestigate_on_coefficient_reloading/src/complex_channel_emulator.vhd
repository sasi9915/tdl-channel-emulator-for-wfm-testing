LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY complex_channel_emulator IS
    PORT (
        aclk : IN STD_LOGIC;
        aresetn : IN STD_LOGIC;

        -- Complex input:
        -- TDATA[15:0]  = I
        -- TDATA[31:16] = Q
        s_axis_tvalid : IN STD_LOGIC;
        s_axis_tready : OUT STD_LOGIC;
        s_axis_tdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        s_axis_tlast : IN STD_LOGIC;

        ---adding the ports related to CONFIG and RELOAD interfaces for FIR_REAL and FIR_IMAG
        -- real component 
        s_axis_config_real_tvalid : IN STD_LOGIC;
        s_axis_config_real_tready : OUT STD_LOGIC;
        s_axis_config_real_tdata : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
        s_axis_reload_real_tvalid : IN STD_LOGIC;
        s_axis_reload_real_tready : OUT STD_LOGIC;
        s_axis_reload_real_tdata : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        s_axis_reload_real_tlast : IN STD_LOGIC;

        -- imaginary componnet
        s_axis_config_imag_tvalid : IN STD_LOGIC;
        s_axis_config_imag_tready : OUT STD_LOGIC;
        s_axis_config_imag_tdata : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
        s_axis_reload_imag_tvalid : IN STD_LOGIC;
        s_axis_reload_imag_tready : OUT STD_LOGIC;
        s_axis_reload_imag_tdata : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        s_axis_reload_imag_tlast : IN STD_LOGIC;

        -- Complex output:
        -- TDATA[39:0]  = output I, signed 40-bit field
        -- TDATA[79:40] = output Q, signed 40-bit field
        m_axis_tvalid : OUT STD_LOGIC;
        m_axis_tready : IN STD_LOGIC;
        m_axis_tdata : OUT STD_LOGIC_VECTOR(79 DOWNTO 0);
        m_axis_tlast : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE rtl OF complex_channel_emulator IS

    -- Input distribution buffer
    SIGNAL r_input_data : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL r_input_last : STD_LOGIC := '0';
    SIGNAL r_real_input_pending : STD_LOGIC := '0';
    SIGNAL r_imag_input_pending : STD_LOGIC := '0';
    SIGNAL w_input_ready : STD_LOGIC;

    -- FIR real input interface
    SIGNAL w_real_s_tvalid : STD_LOGIC;
    SIGNAL w_real_s_tready : STD_LOGIC;

    -- FIR imaginary input interface
    SIGNAL w_imag_s_tvalid : STD_LOGIC;
    SIGNAL w_imag_s_tready : STD_LOGIC;

    -- FIR real output interface
    SIGNAL w_real_m_tvalid : STD_LOGIC;
    SIGNAL w_real_m_tready : STD_LOGIC;
    SIGNAL w_real_m_tdata : STD_LOGIC_VECTOR(79 DOWNTO 0);
    SIGNAL w_real_m_tlast : STD_LOGIC;

    -- FIR imaginary output interface
    SIGNAL w_imag_m_tvalid : STD_LOGIC;
    SIGNAL w_imag_m_tready : STD_LOGIC;
    SIGNAL w_imag_m_tdata : STD_LOGIC_VECTOR(79 DOWNTO 0);
    SIGNAL w_imag_m_tlast : STD_LOGIC;
    SIGNAL w_output_valid : STD_LOGIC;

    -- FIR output paths
    SIGNAL w_i_hr : signed(36 DOWNTO 0);
    SIGNAL w_q_hr : signed(36 DOWNTO 0);
    SIGNAL w_i_hi : signed(36 DOWNTO 0);
    SIGNAL w_q_hi : signed(36 DOWNTO 0);

    -- Complex result, one extra bit for addition/subtraction
    SIGNAL w_output_i : signed(37 DOWNTO 0);
    SIGNAL w_output_q : signed(37 DOWNTO 0);

BEGIN

    

    -- Store one input transaction and independently deliver in to both FIR instances.
    PROCESS (aclk)
    BEGIN
        IF rising_edge(aclk) THEN
            IF aresetn = '0' THEN
                r_input_data <= (OTHERS => '0');
                r_input_last <= '0';
                r_real_input_pending <= '0';
                r_imag_input_pending <= '0';
            ELSE
                -- Clear each pending flag when that FIR accepts the sample.
                IF r_real_input_pending = '1' AND w_real_s_tready = '1' THEN
                    r_real_input_pending <= '0';
                END IF;

                IF r_imag_input_pending = '1' AND w_imag_s_tready = '1' THEN
                    r_imag_input_pending <= '0';
                END IF;

                -- Capture a new packed I/Q input.
                IF s_axis_tvalid = '1' AND w_input_ready = '1' THEN
                    r_input_data <= s_axis_tdata;
                    r_input_last <= s_axis_tlast;
                    r_real_input_pending <= '1';
                    r_imag_input_pending <= '1';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    

    -- Check that the two identical FIR configurations remain aligned.
    PROCESS (aclk)
    BEGIN
        IF rising_edge(aclk) THEN
            IF aresetn = '1' THEN
                IF w_real_m_tvalid = '1' AND w_imag_m_tvalid = '1' THEN
                    ASSERT w_real_m_tlast = w_imag_m_tlast
                    REPORT "FIR_REAL and FIR_IMAG TLAST mismatch"
                        SEVERITY error;
                END IF;
            END IF;
        END IF;
    END PROCESS;


    w_real_s_tvalid <= r_real_input_pending;
    w_imag_s_tvalid <= r_imag_input_pending;

    -- Extract the four real convolutions
    -- FIR_REAL:  Path 0 = I*hR and  Path 1 = Q*hR
    w_i_hr <= signed(w_real_m_tdata(36 DOWNTO 0));
    w_q_hr <= signed(w_real_m_tdata(76 DOWNTO 40));
    -- FIR_IMAG: Path 0 = I*hI  and Path 1 = Q*hI
    w_i_hi <= signed(w_imag_m_tdata(36 DOWNTO 0));
    w_q_hi <= signed(w_imag_m_tdata(76 DOWNTO 40));

    -- output I = I*hR - Q*hI   / output Q = I*hI + Q*hR
    w_output_i <= resize(w_i_hr, w_output_i'length) - resize(w_q_hi, w_output_i'length);
    w_output_q <= resize(w_i_hi, w_output_q'length) + resize(w_q_hr, w_output_q'length);
    -- Consume both FIR outputs together.
    w_real_m_tready <= m_axis_tready AND w_imag_m_tvalid;
    w_imag_m_tready <= m_axis_tready AND w_real_m_tvalid;
    

    -- Accept a new TX sample only after both FIRs have accepte the previous sample.
    w_input_ready <= NOT (r_real_input_pending OR r_imag_input_pending);
    s_axis_tready <= w_input_ready;
    -- Only present an output after both FIR results are available.
    w_output_valid <= w_real_m_tvalid AND w_imag_m_tvalid;
    m_axis_tvalid <= w_output_valid;
    m_axis_tdata(39 DOWNTO 0) <= STD_LOGIC_VECTOR(resize(w_output_i, 40));  -- Place each 38-bit result in a sign-extended 40-bit field.
    m_axis_tdata(79 DOWNTO 40) <= STD_LOGIC_VECTOR(resize(w_output_q, 40)); -- Place each 38-bit result in a sign-extended 40-bit field.
    m_axis_tlast <= w_real_m_tlast AND w_output_valid;


    -- FIR using the real channel coefficients hR
    u_fir_real : ENTITY work.fir_compiler_invest_real_comp
        PORT MAP(
            aclk => aclk,
            aresetn => aresetn,

            s_axis_config_tvalid => s_axis_config_real_tvalid,
            s_axis_config_tready => s_axis_config_real_tready,
            s_axis_config_tdata  => s_axis_config_real_tdata,

            s_axis_reload_tvalid => s_axis_reload_real_tvalid,
            s_axis_reload_tready => s_axis_reload_real_tready,
            s_axis_reload_tdata  => s_axis_reload_real_tdata,
            s_axis_reload_tlast  => s_axis_reload_real_tlast,

            s_axis_data_tvalid => w_real_s_tvalid,
            s_axis_data_tready => w_real_s_tready,
            s_axis_data_tdata  => r_input_data,
            s_axis_data_tlast  => r_input_last,

            m_axis_data_tvalid => w_real_m_tvalid,
            m_axis_data_tready => w_real_m_tready,
            m_axis_data_tdata  => w_real_m_tdata,
            m_axis_data_tlast  => w_real_m_tlast,

            event_s_reload_tlast_missing    => OPEN,
            event_s_reload_tlast_unexpected => OPEN
        );

    -- FIR using the imaginary channel coefficients hI
    u_fir_imag : ENTITY work.fir_compiler_invest_imag_comp
        PORT MAP(
            aclk => aclk,
            aresetn => aresetn,

            s_axis_config_tvalid => s_axis_config_imag_tvalid,
            s_axis_config_tready => s_axis_config_imag_tready,
            s_axis_config_tdata  => s_axis_config_imag_tdata,

            s_axis_reload_tvalid => s_axis_reload_imag_tvalid,
            s_axis_reload_tready => s_axis_reload_imag_tready,
            s_axis_reload_tdata  =>  s_axis_reload_imag_tdata,
            s_axis_reload_tlast  => s_axis_reload_imag_tlast,

            s_axis_data_tvalid => w_imag_s_tvalid,
            s_axis_data_tready => w_imag_s_tready,
            s_axis_data_tdata  => r_input_data,
            s_axis_data_tlast  => r_input_last,

            m_axis_data_tvalid => w_imag_m_tvalid,
            m_axis_data_tready => w_imag_m_tready,
            m_axis_data_tdata  => w_imag_m_tdata,
            m_axis_data_tlast  => w_imag_m_tlast,

            event_s_reload_tlast_missing    => OPEN,
            event_s_reload_tlast_unexpected => OPEN
        );

END ARCHITECTURE;
