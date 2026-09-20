library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pl_sequencer_axi_lite_slave_lite_v1_0_S00_AXI is
	generic(
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line

		-- Width of S_AXI data bus
		C_S_AXI_DATA_WIDTH : integer := 32;
		-- Width of S_AXI address bus
		C_S_AXI_ADDR_WIDTH : integer := 5
	);
	port(
		-- Users to add ports here
		seq_enable              : out std_logic;
			seq_fu_period_cycles    : out std_logic_vector(31 downto 0);
			cfg_bank_sets_per_bank  : out std_logic_vector(31 downto 0);
			irq_enable              : out std_logic_vector(5 downto 0);
			seq_clear_status        : out std_logic;
			seq_reload_active       : in  std_logic;
			seq_reload_block_done   : in  std_logic;
			seq_missed_refill       : in  std_logic;
			seq_reload_timing_error : in  std_logic;
			coeff_bank_active_set_available : in std_logic;
			coeff_bank_underrun             : in std_logic;
			coeff_bank_write_error          : in std_logic;
			fir_reload_error        : in  std_logic;
			coeff_bank_active_bank  : in  std_logic;
			coeff_bank0_ready       : in  std_logic;
			coeff_bank1_ready       : in  std_logic;
			seq_state_debug         : in  std_logic_vector(2 downto 0);
		-- User ports ends
		-- Do not modify the ports beyond this line

		-- Global Clock Signal
		S_AXI_ACLK              : in  std_logic;
		-- Global Reset Signal. This Signal is Active LOW
		S_AXI_ARESETN           : in  std_logic;
		-- Write address (issued by master, acceped by Slave)
		S_AXI_AWADDR            : in  std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
		-- Write channel Protection type. This signal indicates the
		-- privilege and security level of the transaction, and whether
		-- the transaction is a data access or an instruction access.
		S_AXI_AWPROT            : in  std_logic_vector(2 downto 0);
		-- Write address valid. This signal indicates that the master signaling
		-- valid write address and control information.
		S_AXI_AWVALID           : in  std_logic;
		-- Write address ready. This signal indicates that the slave is ready
		-- to accept an address and associated control signals.
		S_AXI_AWREADY           : out std_logic;
		-- Write data (issued by master, acceped by Slave)
		S_AXI_WDATA             : in  std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
		-- Write strobes. This signal indicates which byte lanes hold
		-- valid data. There is one write strobe bit for each eight
		-- bits of the write data bus.
		S_AXI_WSTRB             : in  std_logic_vector((C_S_AXI_DATA_WIDTH / 8) - 1 downto 0);
		-- Write valid. This signal indicates that valid write
		-- data and strobes are available.
		S_AXI_WVALID            : in  std_logic;
		-- Write ready. This signal indicates that the slave
		-- can accept the write data.
		S_AXI_WREADY            : out std_logic;
		-- Write response. This signal indicates the status
		-- of the write transaction.
		S_AXI_BRESP             : out std_logic_vector(1 downto 0);
		-- Write response valid. This signal indicates that the channel
		-- is signaling a valid write response.
		S_AXI_BVALID            : out std_logic;
		-- Response ready. This signal indicates that the master
		-- can accept a write response.
		S_AXI_BREADY            : in  std_logic;
		-- Read address (issued by master, acceped by Slave)
		S_AXI_ARADDR            : in  std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
		-- Protection type. This signal indicates the privilege
		-- and security level of the transaction, and whether the
		-- transaction is a data access or an instruction access.
		S_AXI_ARPROT            : in  std_logic_vector(2 downto 0);
		-- Read address valid. This signal indicates that the channel
		-- is signaling valid read address and control information.
		S_AXI_ARVALID           : in  std_logic;
		-- Read address ready. This signal indicates that the slave is
		-- ready to accept an address and associated control signals.
		S_AXI_ARREADY           : out std_logic;
		-- Read data (issued by slave)
		S_AXI_RDATA             : out std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
		-- Read response. This signal indicates the status of the
		-- read transfer.
		S_AXI_RRESP             : out std_logic_vector(1 downto 0);
		-- Read valid. This signal indicates that the channel is
		-- signaling the required read data.
		S_AXI_RVALID            : out std_logic;
		-- Read ready. This signal indicates that the master can
		-- accept the read data and response information.
		S_AXI_RREADY            : in  std_logic
	);
end pl_sequencer_axi_lite_slave_lite_v1_0_S00_AXI;

architecture arch_imp of pl_sequencer_axi_lite_slave_lite_v1_0_S00_AXI is

	-- AXI4LITE signals
	signal axi_awaddr  : std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
	signal axi_awready : std_logic;
	signal axi_wready  : std_logic;
	signal axi_bresp   : std_logic_vector(1 downto 0);
	signal axi_bvalid  : std_logic;
	signal axi_araddr  : std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
	signal axi_arready : std_logic;
	signal axi_rdata   : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
	signal axi_rresp   : std_logic_vector(1 downto 0);
	signal axi_rvalid  : std_logic;

	-- Example-specific design signals
	-- local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	-- ADDR_LSB is used for addressing 32/64 bit registers/memories
	-- ADDR_LSB = 2 for 32 bits (n downto 2)
	-- ADDR_LSB = 3 for 64 bits (n downto 3)
	constant ADDR_LSB          : integer := (C_S_AXI_DATA_WIDTH / 32) + 1;
	constant OPT_MEM_ADDR_BITS : integer := 2;
	------------------------------------------------
	---- Signals for user logic register space example
	--------------------------------------------------
	---- Number of Slave Registers 4 plus read-only status/debug/capability
	signal   slv_reg0          : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
	signal   slv_reg1          : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
	signal   slv_reg2          : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
	signal   slv_reg3          : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
	signal   r_clear_status    : std_logic;
	signal   w_control_reg     : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
	signal   w_status_reg      : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
	signal   w_debug_reg       : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
	signal   w_capability_reg  : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);

	signal mem_logic      : std_logic_vector(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
	signal r_aw_pending   : std_logic := '0';
	signal r_w_pending    : std_logic := '0';
	signal r_wdata        : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0) := (others => '0');
	signal r_wstrb        : std_logic_vector((C_S_AXI_DATA_WIDTH / 8) - 1 downto 0) := (others => '0');
	signal w_write_commit : std_logic;

	--State machine local parameters
	constant Idle        : std_logic_vector(1 downto 0) := "00";
	constant Raddr       : std_logic_vector(1 downto 0) := "10";
	constant Rdata       : std_logic_vector(1 downto 0) := "11";
	--State machine variables
	signal   state_read  : std_logic_vector(1 downto 0);
begin
	-- I/O Connections assignments

	S_AXI_AWREADY                                 <= axi_awready;
	S_AXI_WREADY                                  <= axi_wready;
	S_AXI_BRESP                                   <= axi_bresp;
	S_AXI_BVALID                                  <= axi_bvalid;
	S_AXI_ARREADY                                 <= axi_arready;
	S_AXI_RDATA                                   <= axi_rdata;
	S_AXI_RRESP                                   <= axi_rresp;
	S_AXI_RVALID                                  <= axi_rvalid;
		seq_enable                                    <= slv_reg0(0);
		seq_fu_period_cycles                          <= slv_reg1;
		cfg_bank_sets_per_bank                        <= slv_reg2;
		irq_enable                                    <= slv_reg3(5 downto 0);
		seq_clear_status                              <= r_clear_status;
		w_control_reg                                 <= slv_reg0 and std_logic_vector(to_unsigned(1, C_S_AXI_DATA_WIDTH));
		w_status_reg(C_S_AXI_DATA_WIDTH - 1 downto 8) <= (others => '0');
		w_status_reg(7)                               <= fir_reload_error;
		w_status_reg(6)                               <= coeff_bank_write_error;
	w_status_reg(5)                               <= coeff_bank_underrun;
	w_status_reg(4)                               <= coeff_bank_active_set_available;
	w_status_reg(3)                               <= seq_reload_timing_error;
	w_status_reg(2)                               <= seq_missed_refill;
	w_status_reg(1)                               <= seq_reload_block_done;
	w_status_reg(0)                               <= seq_reload_active;
		w_debug_reg(C_S_AXI_DATA_WIDTH - 1 downto 6)  <= (others => '0');
		w_debug_reg(5)                                <= coeff_bank1_ready;
		w_debug_reg(4)                                <= coeff_bank0_ready;
		w_debug_reg(3)                                <= coeff_bank_active_bank;
		w_debug_reg(2 downto 0)                       <= seq_state_debug;
	w_capability_reg                              <= x"00060001";
	mem_logic                                     <= axi_awaddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
	axi_awready                                  <= '1' when S_AXI_ARESETN = '1' and r_aw_pending = '0' and axi_bvalid = '0' else '0';
	axi_wready                                   <= '1' when S_AXI_ARESETN = '1' and r_w_pending = '0' and axi_bvalid = '0' else '0';
	w_write_commit                               <= r_aw_pending and r_w_pending and not axi_bvalid;

	-- Capture AXI4-Lite AW and W independently. One write transaction may be
	-- outstanding while its B response is pending.
	process(S_AXI_ACLK)
	begin
		if rising_edge(S_AXI_ACLK) then
			if S_AXI_ARESETN = '0' then
				axi_awaddr   <= (others => '0');
				axi_bvalid   <= '0';
				axi_bresp    <= (others => '0');
				r_aw_pending <= '0';
				r_w_pending  <= '0';
				r_wdata      <= (others => '0');
				r_wstrb      <= (others => '0');
			else
				if S_AXI_AWVALID = '1' and axi_awready = '1' then
					axi_awaddr   <= S_AXI_AWADDR;
					r_aw_pending <= '1';
				end if;

				if S_AXI_WVALID = '1' and axi_wready = '1' then
					r_wdata     <= S_AXI_WDATA;
					r_wstrb     <= S_AXI_WSTRB;
					r_w_pending <= '1';
				end if;

				if w_write_commit = '1' then
					r_aw_pending <= '0';
					r_w_pending  <= '0';
					axi_bvalid   <= '1';
				elsif axi_bvalid = '1' and S_AXI_BREADY = '1' then
					axi_bvalid <= '0';
				end if;
			end if;
		end if;
	end process;
	-- Implement memory mapped register select and write logic generation
	-- The write data is accepted and written to memory mapped registers when
	-- axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
	-- select byte enables of slave registers while writing.
	-- These registers are cleared when reset (active low) is applied.
	-- Slave register write enable is asserted when valid address and data are available
	-- and the slave is ready to accept the write address and write data.

	process(S_AXI_ACLK)
	begin
		if rising_edge(S_AXI_ACLK) then
			if S_AXI_ARESETN = '0' then
				slv_reg0       <= (others => '0');
				slv_reg1       <= (others => '0');
				slv_reg2       <= (others => '0');
				slv_reg3       <= (others => '0');
				r_clear_status <= '0';
			else
				r_clear_status <= '0';
				if w_write_commit = '1' then
					case (mem_logic) is
						when b"000" =>
							for byte_index in 0 to (C_S_AXI_DATA_WIDTH / 8 - 1) loop
								if (r_wstrb(byte_index) = '1') then
									-- Respective byte enables are asserted as per write strobes
									-- slave registor 0
									slv_reg0(byte_index * 8 + 7 downto byte_index * 8) <= r_wdata(byte_index * 8 + 7 downto byte_index * 8);
								end if;
							end loop;
							if r_wstrb(0) = '1' then
								r_clear_status <= r_wdata(1);
								slv_reg0(1) <= '0';
							end if;
						when b"001" =>
							for byte_index in 0 to (C_S_AXI_DATA_WIDTH / 8 - 1) loop
								if (r_wstrb(byte_index) = '1') then
									-- Respective byte enables are asserted as per write strobes
									-- slave registor 1
									slv_reg1(byte_index * 8 + 7 downto byte_index * 8) <= r_wdata(byte_index * 8 + 7 downto byte_index * 8);
								end if;
							end loop;
						when b"010" =>
							for byte_index in 0 to (C_S_AXI_DATA_WIDTH / 8 - 1) loop
								if (r_wstrb(byte_index) = '1') then
									-- Respective byte enables are asserted as per write strobes
									-- slave registor 2
									slv_reg2(byte_index * 8 + 7 downto byte_index * 8) <= r_wdata(byte_index * 8 + 7 downto byte_index * 8);
								end if;
							end loop;
						when b"011" =>
							for byte_index in 0 to (C_S_AXI_DATA_WIDTH / 8 - 1) loop
								if (r_wstrb(byte_index) = '1') then
									-- Respective byte enables are asserted as per write strobes
									-- slave registor 3
									slv_reg3(byte_index * 8 + 7 downto byte_index * 8) <= r_wdata(byte_index * 8 + 7 downto byte_index * 8);
								end if;
							end loop;
						when b"100" =>
							null;
						when b"101" =>
							null;
						when b"110" =>
							null;
						when others =>
							slv_reg0 <= slv_reg0;
							slv_reg1 <= slv_reg1;
							slv_reg2 <= slv_reg2;
							slv_reg3 <= slv_reg3;
					end case;
				end if;
			end if;
		end if;
	end process;

	-- Implement read state machine
	process(S_AXI_ACLK)
	begin
		if rising_edge(S_AXI_ACLK) then
			if S_AXI_ARESETN = '0' then
				--asserting initial values to all 0's during reset
				axi_arready <= '0';
				axi_rdata   <= (others => '0');
				axi_rvalid  <= '0';
				axi_rresp   <= (others => '0');
				state_read  <= Idle;
			else
				case (state_read) is
					when Idle =>        --Initial state inidicating reset is done and ready to receive read/write transactions
						if (S_AXI_ARESETN = '1') then
							axi_arready <= '1';
							state_read  <= Raddr;
						else
							state_read <= state_read;
						end if;
					when Raddr =>       --At this state, slave is ready to receive address along with corresponding control signals
						if (S_AXI_ARVALID = '1' and axi_arready = '1') then
							state_read  <= Rdata;
							axi_rvalid  <= '1';
							axi_arready <= '0';
							axi_araddr  <= S_AXI_ARADDR;

							case S_AXI_ARADDR(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB) is
								when b"000" =>
									axi_rdata <= w_control_reg;
								when b"001" =>
									axi_rdata <= slv_reg1;
								when b"010" =>
									axi_rdata <= slv_reg2;
								when b"011" =>
									axi_rdata <= slv_reg3;
								when b"100" =>
									axi_rdata <= w_status_reg;
								when b"101" =>
									axi_rdata <= w_debug_reg;
								when b"110" =>
									axi_rdata <= w_capability_reg;
								when others =>
									axi_rdata <= (others => '0');
							end case;
						else
							state_read <= state_read;
						end if;
					when Rdata =>       --At this state, slave is ready to send the data packets until the number of transfers is equal to burst length
						if (axi_rvalid = '1' and S_AXI_RREADY = '1') then
							axi_rvalid  <= '0';
							axi_arready <= '1';
							state_read  <= Raddr;
						else
							state_read <= state_read;
						end if;
					when others =>      --reserved
						axi_arready <= '0';
						axi_rvalid  <= '0';
				end case;
			end if;
		end if;
	end process;

	-- Add user logic here

	-- User logic ends

end arch_imp;
