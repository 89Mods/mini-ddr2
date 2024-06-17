//Constants for the particular RAM chip I used
//Timing parameters based on CPLD @ 80MHz
//This has the DDR2 clocked at 40MHz

//Defines for MR settings
`define MR_BURST_LEN_4 'b010
`define MR_BURST_LEN_8 'b011
`define MR_BURST_SEQUENTIAL 0
`define MR_BURST_INTERLEAVED (1 << 3)
`define MR_CAS_LATENCY(x) (x << 4)
`define MR_MODE_TEST (1 << 7)
`define MR_MODE_NORMAL 0
`define MR_DLL_RESET (1 << 8)
`define MR_WRITE_RECOVERY(x) ((x - 1) << 9)
`define MR_PD_FAST 0
`define MR_PD_SLOW (1 << 12)

`define CAS_LATENCY 3 //What goes into the MR
//Actual delays the controller takes
`define WRITE_LATENCY (`CAS_LATENCY-1)
`define READ_LATENCY (`CAS_LATENCY)

`define READ_RECOVERY 0 //How long the controller will delay after a read
`define WRITE_RECOVERY_SETTING 2 //This is what goes in the MR
`define WRITE_RECOVERY 2 //This is how much delay the controller will actually take after a write

`define MR_SETTING (`MR_BURST_LEN_4 | `MR_BURST_SEQUENTIAL | `MR_CAS_LATENCY(`CAS_LATENCY) | `MR_MODE_NORMAL | `MR_WRITE_RECOVERY(`WRITE_RECOVERY_SETTING) | `MR_PD_FAST)

//Defines for EMR settings
`define EMR_DLL_NORMAL 0
`define EMR_DLL_TEST 1
`define EMR_FULL_STRENGTH 0
`define EMR_REDUCED_STRENGTH (1 << 1)
`define EMR_R_DISABLED 0
`define EMR_R_75 (1 << 2)
`define EMR_R_150 (1 << 6)
`define EMR_R_50 ((1 << 2) | (1 << 6))
`define EMR_AL(x) (x << 3)
`define EMR_OCD_EXIT 0
`define EMR_OCD_DEFAULTS (7 << 7)
`define EMR_NDQS_ON 0
`define EMR_NDQS_OFF (1 << 10)
`define EMR_RDQS_OFF 0
`define EMR_RDQS_ON (1 << 11)
`define EMR_OUTS_ON 0
`define EMR_OUTS_OFF (1 << 12)

`define EMR_SETTING (`EMR_DLL_NORMAL | `EMR_R_150 | `EMR_FULL_STRENGTH | `EMR_AL(0) | `EMR_NDQS_OFF | `EMR_RDQS_OFF)

//How many clock cycles correspond to one tRFC
`define REFRESH_WAIT 4

//How many clock cycles correspond to one tRP
`define PRECHARGE_WAIT 1

//How many clock cycles correspond to one tRCD (activate command)
//Minimum value of 1
//(I found real hardware glitches out when this is 0)
`define TRCD_CYCLES 1

`undef WITH_HEARTBEAT
`define EARLY_READY

//Change if you need DQS_b. Also requires it be enabled in the EMR setting above
`undef WITH_DQSB

module dram_controller(
	input clk,
	output reg ddr_clk = 0,
	output ddr_clk_c,
	inout [3:0] Q,
	output reg CS_b = 1,
	output reg ODT = 0,
	output reg RAS_b = 1,
	output reg CAS_b,
	output reg WE_b = 1,
	output reg [1:0] BA = 0,
	output [13:0] A,
	inout DQS,
	output DM,
	output reg CKE = 0,

	/*
	 * Flat memory interface
	 */
	input CEb_in,
	inout [7:0] Q_f,
	input WEb_f,
	input [22:0] A_f,
	input rst_b,
	inout DQS_b,
	output ready,
	output bdir, //Bus direction for level shifter
	output dbg
);
wire [25:0] full_addr = {3'b00, A_f[22:0]};

wire reset = !rst_b;

assign Q = writing ? (rw_step >= 2 ? Q_f[3:0] : Q_f[7:4]) : 4'hz;
assign DQS = writing ? DQS_ll : 1'bz;
`ifdef WITH_DQSB
assign DQS_b = writing ? !DQS_ll : 1'bz; //optional DQS_b
`else
assign DQS_b = !init_done;
`endif
assign DM = !writing || rw_step == 0 || !counter_expired;

/*
 * Define address bus value
 * During init sequence, taken from below table
 * During normal operation, row address during ACTIVATE, column address otherwise
 * Note that A10 in the column address is always low
 */
reg [13:0] init_A;
always @(*) begin
	casez(init_step)
		default: init_A = 0;
		7'b?000101: init_A = 1<<10;
		7'b?010001: init_A = `MR_DLL_RESET;
		7'b?010100: init_A = 1<<10;
		7'b?011110: init_A = `MR_SETTING;
		7'b?100001: init_A = `EMR_SETTING | `EMR_OCD_DEFAULTS;
		7'b?100100: init_A = `EMR_SETTING;
	endcase
end

/*
 * Bank address during init sequence, combines with above table
 */
reg [1:0] BA_init;
always @(*) begin
	casez(init_step)
		default: BA_init = 2'bxx; //Don’t care
		7'b?000111: BA_init = 2'b10;
		7'b?001010: BA_init = 2'b11;
		7'b?001101: BA_init = 2'b01;
		7'b?010000: BA_init = 2'b00;
		7'b?011101: BA_init = 2'b00;
		7'b?100000: BA_init = 2'b01;
		7'b?100011: BA_init = 2'b01;
	endcase
end

wire [13:0] ready_A = state == 1 ? row_address : {3'b000, column_address[10], 1'b0, column_address[9:0]};
assign A = init_done ? ready_A : init_A;

assign ddr_clk_c = !ddr_clk;
reg init_done;
reg [2:0] state;
reg [7:0] counter = 255;
reg [1:0] rw_step;
reg [8:0] command_timeout = 0;
reg writing;
reg DQS_l;
reg DQS_ll;
reg last_DQS;
reg ready_l;
reg needs_precharge;
reg [13:0] row_address_l;
reg latch_command = 0;
reg [6:0] init_step;
reg CE_edge = 1;
reg CE_edge_edge = 1;
reg [7:0] dbuff;

wire [7:0] counter_dec = counter - 1;
wire counter_expired = counter == 0;

assign bdir = WEb_f && !CEb_in;
assign Q_f = bdir ? dbuff : 8'hzz;
assign ready = ready_l && !latch_command;

wire [10:0] column_address = {full_addr[9:0], 1'b0};
wire [13:0] row_address = full_addr[23:10];

`ifdef WITH_HEARTBEAT
//Just an LED blinker
reg [23:0] test = 0;
assign dbg = test[23];
`else
assign dbg = dbuff[7];
`endif

always @(negedge clk) DQS_ll <= DQS_l;

always @(posedge clk) begin
	if(reset) begin
		CKE <= 0;
		CS_b <= 1;
		CAS_b <= 1;
		ready_l <= 0;
		init_done <= 0;
		state <= 0;
		DQS_l <= 0;
		writing <= 0;
		rw_step <= 0;
		init_step <= 64;
		needs_precharge <= 0;
		ODT <= 0;
	end else begin
		ddr_clk <= !ddr_clk;
		if(command_timeout) command_timeout <= command_timeout - 1;
`ifdef WITH_HEARTBEAT
		test <= test + 1;
`endif
		/*
		 * Normal operation
		 */
		last_DQS <= DQS;
		//Commented out DQS edge check when reading
		//Would love to have this, but does not fit
		if(counter_expired && state[1]/* && (writing || last_DQS != DQS || !rw_step[1])*/) begin
			rw_step <= rw_step - 1;
			if(rw_step == 0) begin
				state <= 0;
`ifdef EARLY_READY
				ready_l <= 1;
`endif
				//TODO: Write recovery can be 0 if we know the next cycle isn’t going to be a PRECHARGE right away
				counter <= writing ? `WRITE_RECOVERY : `READ_RECOVERY;
			end
			DQS_l <= !DQS_l;
			//Differing behavior between testbench and real-life. Why? No Idea! (Probably propagation delays, though)
`ifdef BENCH
			if(!writing && rw_step[1]) dbuff <= {Q, dbuff[7:4]};
`else
			if(!writing && (rw_step == 1 || rw_step == 2)) dbuff <= {Q, dbuff[7:4]};
`endif
		end else if(init_done && ddr_clk) begin
			CS_b <= 1;
			RAS_b <= 1;
			CAS_b <= 1;
			WE_b <= 1;
			
			if(ready) begin
				CE_edge_edge <= CE_edge;
				CE_edge <= CEb_in;
				latch_command <= (CE_edge && !CEb_in) || (CE_edge_edge && !CE_edge) || (CE_edge_edge && !CEb_in); //Work already!
			end

			//re-use this reg for general-purpose delay
			if(!counter_expired) begin
				counter <= counter_dec;
			end else if(state == 4) begin
				activate();
			end else if(state == 5) begin
				refresh();
				state <= 0;
`ifdef EARLY_READY
				ready_l <= 1;
`endif
			end else if(state) begin
				if(WEb_f) begin
					begin_read();
				end else begin
					begin_write();
				end
			end else begin
				writing <= 0;
`ifndef EARLY_READY
				ready_l <= 1;
`endif
				if(!command_timeout && needs_precharge) begin
					needs_precharge <= 0;
					precharge();
					state <= 5;
				end else begin
					if(latch_command) begin
						ready_l <= 0;
						latch_command <= 0;
						CE_edge_edge <= CEb_in;
						CE_edge <= CEb_in;
						if(command_timeout) begin
							if(row_address == row_address_l && full_addr[25:24] == BA) begin
								if(WEb_f) begin
									begin_read();
								end else begin
									begin_write();
								end
							end else begin
								precharge();
								state <= 4;
							end
						end else begin
							activate();
							command_timeout <= 511;
							needs_precharge <= 1;
						end
					end else if(!command_timeout) begin
						refresh();
					end
				end
			end
		end
		if(CEb_in) dbuff <= 8'hAA;
		
		/*
		 * Initialization
		 */
		if(ddr_clk && !init_done) begin
			if(init_step == 1) begin
				//Startup
				CKE <= 1;
			end
			if(init_step == 2) begin
				//Startup delay
				counter <= 255;
			end
			if(init_step == 4 || init_step == 19) begin
				//PRECHARGE (ALL), start of command
				CS_b <= 0;
				RAS_b <= 0;
				WE_b <= 0;
			end
			if(init_step == 5 || init_step == 20) begin
				//PRECHARGE (ALL), end of command
				CS_b <= 1;
				RAS_b <= 1;
				WE_b <= 1;
				counter <= 255;
			end
			if(init_step == 7 || init_step == 10 || init_step == 13
			|| init_step == 16 || init_step == 29 || init_step == 32
			|| init_step == 35) begin
				//All instances of LOAD MODE (start of command)
				BA <= BA_init;
				CS_b <= 0;
				RAS_b <= 0;
				CAS_b <= 0;
				WE_b <= 0;
			end
			if(init_step == 8 || init_step == 11 || init_step == 14
			|| init_step == 17 || init_step == 30 || init_step == 33
			|| init_step == 36) begin
				//All instances of LOAD MODE (end of command)
				CS_b <= 1;
				RAS_b <= 1;
				CAS_b <= 1;
				WE_b <= 1;
				counter <= 255;
			end
			if(init_step == 22 || init_step == 25) begin
				//REFRESH, start of command
				CS_b <= 0;
				RAS_b <= 0;
				CAS_b <= 0;
				counter <= 255;
			end
			if(init_step == 23 || init_step == 26) begin
				//REFRESH, end of command
				CS_b <= 1;
				RAS_b <= 1;
				CAS_b <= 1;
			end
			if(init_step == 38) begin
				init_done <= 1;
				ODT <= 1;
`ifdef EARLY_READY
				ready_l <= 1;
`endif
			end
			if(init_step[6]) counter <= 255;
			
			if(counter_expired) begin
				init_step <= init_step + 1;
`ifdef BENCH
				if(init_step <= 38) $display("Init step %d", init_step);
`endif
			end else counter <= counter_dec;
		end
	end
end

task begin_read();
	begin
		CS_b <= 0;
		CAS_b <= 0;
		counter <= `READ_LATENCY;
		rw_step <= 3;
		state <= 2;
		last_DQS <= 0;
		dbuff <= 0;
	end
endtask

task begin_write();
	begin
		writing <= 1;
		DQS_l <= 0;
		CS_b <= 0;
		CAS_b <= 0;
		WE_b <= 0;
		counter <= `WRITE_LATENCY;
		rw_step <= 3;
		state <= 3;
		//dbuff <= Q_f;
	end
endtask

task activate();
	begin
		CS_b <= 0;
		RAS_b <= 0;
		BA <= full_addr[25:24];
		state <= 1;
		counter <= `TRCD_CYCLES;
		row_address_l <= row_address;
	end
endtask

task precharge();
	begin
		CS_b <= 0;
		RAS_b <= 0;
		WE_b <= 0;
		counter <= `PRECHARGE_WAIT;
	end
endtask

task refresh();
	begin
		CS_b <= 0;
		RAS_b <= 0;
		CAS_b <= 0;
		counter <= `REFRESH_WAIT;
	end
endtask

endmodule
