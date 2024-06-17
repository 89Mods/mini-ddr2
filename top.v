//Constants for the particular RAM chip I used
//Timing parameters based on CPLD @ 80MHz
//This has the DDR2 clocked at 40MHz

`define MR_BURST_LEN_4 'b010
`define MR_BURST_LEN_8 'b011
`define MR_BURST_SEQUENTIAL (1 << 3)
`define MR_BURST_INTERLEAVED 0
`define MR_CAS_LATENCY(x) (x << 4)
`define MR_MODE_TEST (1 << 7)
`define MR_MODE_NORMAL 0
`define MR_DLL_RESET (1 << 8)
`define MR_WRITE_RECOVERY(x) ((x - 1) << 9)
`define MR_PD_FAST 0
`define MR_PD_SLOW (1 << 12)

`define CAS_LATENCY 3
`define WRITE_LATENCY (`CAS_LATENCY-1)
`define READ_LATENCY (`CAS_LATENCY)
`define TRCD_CYCLES 1
`define AUTOPRECHARGE_CYCLES 1
`define AUTOPRECHARGE_CYCLES_WRITE 3

`define MR_SETTING (`MR_BURST_LEN_4 | `MR_BURST_SEQUENTIAL | `MR_CAS_LATENCY(`CAS_LATENCY) | `MR_MODE_NORMAL | `MR_WRITE_RECOVERY(3) | `MR_PD_FAST)

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

`define WITH_HEARTBEAT

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

	inout dbg0,
	output ready,
	output bdir,

	/*
	 * Flat memory interface
	 */
	input CEb_in,
	inout [7:0] Q_f,
	input WEb_f,
	input [22:0] A_f,
	input rst_b,
	
	output dbg
);
wire [25:0] full_addr = {3'b00, A_f[22:0]};

wire reset = !rst_b;

assign Q = writing ? (rw_step >= 2 ? dbuff[3:0] : dbuff[7:4]) : 4'hz;
assign DQS = writing ? DQS_ll : 1'bz;
`ifdef WITH_DQSB
assign dbg0 = writing ? !DQS_ll : 1'bz; //optional DQS_b
`else
assign dbg0 = !init_done;
`endif
assign DM = !writing || rw_step == 0 || !counter_expired;

wire [13:0] ready_A = !state[1] ? row_address : {3'b000, column_address[10], 1'b1, column_address[9:0]};
wire [13:0] init_A = init_step == 13+1 ? 0 : (init_step == 16+1 ? `MR_DLL_RESET : (init_step == 29+1 ? `MR_SETTING : (init_step == 32+1 ? (`EMR_SETTING | `EMR_OCD_DEFAULTS) : (init_step == 35+1 ? `EMR_SETTING : (init_step == 4+1 || init_step == 19+1 ? 1024 : 0)))));
assign A = init_done ? ready_A : init_A;

assign ddr_clk_c = !ddr_clk;
reg init_done;
reg [1:0] state;
reg [7:0] counter;
reg [1:0] rw_step;
reg writing;
reg DQS_l;
reg DQS_ll;
reg last_DQS;
reg ready_l;
wire [7:0] counter_dec = counter - 1;
wire counter_expired = counter == 0;
wire latch_command = CE_edge && !CEb_in;

reg [6:0] init_step;
reg CE_edge;
reg [7:0] dbuff;
assign bdir = WEb_f && !CEb_in;

assign Q_f = bdir ? dbuff : 8'hzz;

assign ready = ready_l & !latch_command;

reg [1:0] BA_init;
always @(*) begin
	casex(init_step)
		default: BA_init <= 2'bxx;
		7: BA_init <= 2'b10;
		10: BA_init <= 2'b11;
		13: BA_init <= 2'b01;
		16: BA_init <= 2'b00;
		29: BA_init <= 2'b00;
		32: BA_init <= 2'b01;
		35: BA_init <= 2'b01;
	endcase
end

wire [10:0] column_address = {full_addr[9:0], 1'b0};
wire [13:0] row_address = full_addr[23:10];

`ifdef WITH_HEARTBEAT
reg [23:0] test = 0;
assign dbg = test[23];
`else
assign dbg = 0;
`endif

always @(negedge clk) DQS_ll <= DQS_l;

always @(posedge clk) begin
	if(reset) begin
		CKE <= 0;
		CS_b <= 1;
		RAS_b <= 1;
		CAS_b <= 1;
		WE_b <= 1;
		ready_l <= 0;
		BA <= 0;
		ddr_clk <= 0;
		init_done <= 0;
		CE_edge <= 1;
		dbuff <= 0;
		state <= 0;
		DQS_l <= 0;
		writing <= 0;
		rw_step <= 0;
		init_step <= 39;
		counter <= 255;
		ODT <= 0;
	end else begin
		ddr_clk <= !ddr_clk;
`ifdef WITH_HEARTBEAT
		test <= test + 1;
`endif
		/*
		 * Normal operation
		 */
		last_DQS <= DQS;
		//Commented out DQS edge check when reading
		//Makes it lock up. But works fine if the check is disabled? Weird.
		if(counter_expired && state[1]/* && (writing || last_DQS != DQS || !rw_step[1])*/) begin
			rw_step <= rw_step - 1;
			if(rw_step == 0) begin
				state <= 0;
				counter <= writing ? `AUTOPRECHARGE_CYCLES_WRITE : `AUTOPRECHARGE_CYCLES;
			end
			DQS_l <= !DQS_l;
			if(!writing && rw_step[1]) dbuff <= {Q, dbuff[7:4]};
		end else if(init_done && ddr_clk) begin
			CS_b <= 1;
			RAS_b <= 1;
			CAS_b <= 1;
			WE_b <= 1;
			//re-use this reg for general-purpose delay
			if(!counter_expired) begin
				counter <= counter_dec;
			end else if(state) begin
				if(WEb_f) begin
					//Read
					CS_b <= 0;
					CAS_b <= 0;
					counter <= `READ_LATENCY;
					rw_step <= 3;
					state <= 2;
					last_DQS <= 0;
				end else begin
					//Write
					writing <= 1;
					DQS_l <= 0;
					CS_b <= 0;
					CAS_b <= 0;
					WE_b <= 0;
					counter <= `WRITE_LATENCY;
					rw_step <= 3;
					state <= 3;
					dbuff <= Q_f;
				end
			end else begin
				writing <= 0;
				CE_edge <= CEb_in;
				ready_l <= 1;
				if(latch_command) begin
					ready_l <= 0;
					//Activate
					CS_b <= 0;
					RAS_b <= 0;
					BA <= full_addr[25:24];
					state <= 1;
					counter <= `TRCD_CYCLES;
				end else begin
					CS_b <= 0;
					RAS_b <= 0;
					CAS_b <= 0;
					counter <= `REFRESH_WAIT;
				end
			end
		end
		
		/*
		 * Initialization
		 */
		if(ddr_clk && !init_done) begin
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
				CS_b <= 0;
				RAS_b <= 0;
				CAS_b <= 0;
				counter <= 255;
			end
			if(init_step == 23 || init_step == 26) begin
				CS_b <= 1;
				RAS_b <= 1;
				CAS_b <= 1;
			end
			if(init_step == 1) begin
				CKE <= 1;
			end
			if(init_step == 2) begin
				counter <= 255;
			end
			if(init_step == 38) begin
				init_done <= 1;
				ODT <= 1;
			end
			if(init_step > 38) counter <= 255;
			
			if(counter_expired) begin
				init_step <= init_step + 1;
`ifdef BENCH
				if(init_step <= 38) $display("Init step %d", init_step);
`endif
			end else counter <= counter_dec;
		end
	end
end

endmodule
