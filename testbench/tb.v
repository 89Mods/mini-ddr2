`default_nettype none
`timescale 1ps / 1ps

module tb(input clk, output init_done, input CEb, input WEb, input reset, input [22:0] addr, input [7:0] din, output [7:0] dout);

wire ddr_clk;
wire ddr_clk_c;
wire CKE;
wire CS_b;
wire RAS_b;
wire CAS_b;
wire WE_b;
wire DM;
wire [1:0] BA;
wire [13:0] A;
wire [3:0] Q;
wire DQS;
wire ODT;
wire [7:0] Q_f = WEb ? 8'hzz : din;
assign dout = Q_f;
dram_controller dram_controller(
    .clk(clk),
    .ddr_clk(ddr_clk),
    .ddr_clk_c(ddr_clk_c),
    .Q(Q),
    .CS_b(CS_b),
    .ODT(ODT),
    .RAS_b(RAS_b),
    .CAS_b(CAS_b),
    .WE_b(WE_b),
    .BA(BA),
    .A(A),
    .DQS(DQS),
    .DM(DM),
    .CKE(CKE),
    .ready(),
    
    .CEb_in(CEb),
    .Q_f(Q_f),
    .WEb_f(WEb),
    .A_f(addr),
    .rst_b(reset),
    
    .dbg0(init_done)
);

tri1 DQS_n;
ddr2_model ddr2_model(
    .ck(ddr_clk),
    .ck_n(ddr_clk_c),
    .cke(CKE),
    .cs_n(CS_b),
    .ras_n(RAS_b),
    .cas_n(CAS_b),
    .we_n(WE_b),
    .dm_rdqs(DM),
    .ba(BA),
    .addr(A),
    .dq(Q),
    .dqs(DQS),
    .dqs_n(DQS_n),
    .rdqs_n(),
    .odt(ODT)
);

initial begin
	$dumpfile("tb.vcd");
	$dumpvars();
end

endmodule
