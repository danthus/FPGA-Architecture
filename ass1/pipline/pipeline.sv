module lab1 #
(
	parameter WIDTHIN = 16,		// Input format is Q2.14 (2 integer bits + 14 fractional bits = 16 bits)
	parameter WIDTHOUT = 32,	// Intermediate/Output format is Q7.25 (7 integer bits + 25 fractional bits = 32 bits)
	// Taylor coefficients for the first five terms in Q2.14 format
	parameter [WIDTHIN-1:0] A0 = 16'b01_00000000000000, // a0 = 1
	parameter [WIDTHIN-1:0] A1 = 16'b01_00000000000000, // a1 = 1
	parameter [WIDTHIN-1:0] A2 = 16'b00_10000000000000, // a2 = 1/2
	parameter [WIDTHIN-1:0] A3 = 16'b00_00101010101010, // a3 = 1/6
	parameter [WIDTHIN-1:0] A4 = 16'b00_00001010101010, // a4 = 1/24
	parameter [WIDTHIN-1:0] A5 = 16'b00_00000010001000  // a5 = 1/120
)
(
	input clk,
	input reset,	
	
	input i_valid,
	input i_ready,
	output o_valid,
	output o_ready,
	
	input [WIDTHIN-1:0] i_x,
	output [WIDTHOUT-1:0] o_y
);
//Output value could overflow (32-bit output, and 16-bit inputs multiplied
//together repeatedly).  Don't worry about that -- assume that only the bottom
//32 bits are of interest, and keep them.
logic [WIDTHIN-1:0] x;	// Register to hold input X
logic [WIDTHOUT-1:0] y_Q;	// Register to hold output Y
logic valid_Q1;		// Output of register x is valid
logic valid_Q2;		// Output of register y is valid

// pipeline the i_valid siganl
// Since pipeline takes 9 stages, i_valid should be the same.
logic valid_p1;
logic valid_p2;
logic valid_p3;
logic valid_p4;
logic valid_p5;
logic valid_p6;
logic valid_p7;
logic valid_p8;
logic valid_p9;

// signal for enabling sequential circuit elements
logic enable;

// Signals for computing the y output
logic [WIDTHOUT-1:0] m0_out; // A5 * x
logic [WIDTHOUT-1:0] a0_out; // A5 * x + A4
logic [WIDTHOUT-1:0] m1_out; // (A5 * x + A4) * x
logic [WIDTHOUT-1:0] a1_out; // (A5 * x + A4) * x + A3
logic [WIDTHOUT-1:0] m2_out; // ((A5 * x + A4) * x + A3) * x
logic [WIDTHOUT-1:0] a2_out; // ((A5 * x + A4) * x + A3) * x + A2
logic [WIDTHOUT-1:0] m3_out; // (((A5 * x + A4) * x + A3) * x + A2) * x
logic [WIDTHOUT-1:0] a3_out; // (((A5 * x + A4) * x + A3) * x + A2) * x + A1
logic [WIDTHOUT-1:0] m4_out; // ((((A5 * x + A4) * x + A3) * x + A2) * x + A1) * x
logic [WIDTHOUT-1:0] a4_out; // ((((A5 * x + A4) * x + A3) * x + A2) * x + A1) * x + A0
logic [WIDTHOUT-1:0] y_D;

//signals for pipelined registers between each mult and add block
logic [WIDTHOUT-1:0] m0_reg;
logic [WIDTHOUT-1:0] a0_reg; 
logic [WIDTHOUT-1:0] m1_reg;
logic [WIDTHOUT-1:0] a1_reg;
logic [WIDTHOUT-1:0] m2_reg;
logic [WIDTHOUT-1:0] a2_reg;
logic [WIDTHOUT-1:0] m3_reg;
logic [WIDTHOUT-1:0] a3_reg;
logic [WIDTHOUT-1:0] m4_reg;

// i_x needs to be pipelined as well
// So every stage can have a consistent X value
logic [WIDTHOUT-1:0] x_0;
logic [WIDTHOUT-1:0] x_1;
logic [WIDTHOUT-1:0] x_2;
logic [WIDTHOUT-1:0] x_3;
logic [WIDTHOUT-1:0] x_4;
logic [WIDTHOUT-1:0] x_5;
logic [WIDTHOUT-1:0] x_6;
logic [WIDTHOUT-1:0] x_7;
logic [WIDTHOUT-1:0] x_8;
logic [WIDTHOUT-1:0] x_9;

// compute y value, registers are inserted between each mult and add 
mult16x16 Mult0 (.i_dataa(A5), 		.i_datab(x), 	.o_res(m0_out));
reg32 reg0 (.reset(reset), .CLK(clk), .ena(i_ready), .D1(m0_out), .Q1(m0_reg), .D2(x), .Q2(x_0));
addr32p16 Addr0 (.i_dataa(m0_reg), 	.i_datab(A4), 	.o_res(a0_out));

reg32 reg1 (.reset(reset), .CLK(clk), .ena(i_ready), .D1(a0_out), .Q1(a0_reg), .D2(x_0), .Q2(x_1));

mult32x16 Mult1 (.i_dataa(a0_reg), 	.i_datab(x_1), 	.o_res(m1_out));
reg32 reg2 (.reset(reset), .CLK(clk), .ena(i_ready), .D1(m1_out), .Q1(m1_reg), .D2(x_1), .Q2(x_2));
addr32p16 Addr1 (.i_dataa(m1_reg), 	.i_datab(A3), 	.o_res(a1_out));

reg32 reg3 (.reset(reset), .CLK(clk), .ena(i_ready), .D1(a1_out), .Q1(a1_reg), .D2(x_2), .Q2(x_3));

mult32x16 Mult2 (.i_dataa(a1_reg), 	.i_datab(x_3), 	.o_res(m2_out));
reg32 reg4 (.reset(reset), .CLK(clk), .ena(i_ready), .D1(m2_out), .Q1(m2_reg), .D2(x_3), .Q2(x_4));
addr32p16 Addr2 (.i_dataa(m2_reg), 	.i_datab(A2), 	.o_res(a2_out));

reg32 reg5 (.reset(reset), .CLK(clk), .ena(i_ready), .D1(a2_out), .Q1(a2_reg), .D2(x_4), .Q2(x_5));

mult32x16 Mult3 (.i_dataa(a2_reg), 	.i_datab(x_5), 	.o_res(m3_out));
reg32 reg6 (.reset(reset), .CLK(clk), .ena(i_ready), .D1(m3_out), .Q1(m3_reg), .D2(x_5), .Q2(x_6));
addr32p16 Addr3 (.i_dataa(m3_reg), 	.i_datab(A1), 	.o_res(a3_out));

reg32 reg7 (.reset(reset), .CLK(clk), .ena(i_ready), .D1(a3_out), .Q1(a3_reg), .D2(x_6), .Q2(x_7));

mult32x16 Mult4 (.i_dataa(a3_reg), 	.i_datab(x_7), 	.o_res(m4_out));
reg32 reg8 (.reset(reset), .CLK(clk), .ena(i_ready), .D1(m4_out), .Q1(m4_reg));
addr32p16 Addr4 (.i_dataa(m4_reg), 	.i_datab(A0), 	.o_res(a4_out));

assign y_D = a4_out;

// Combinational logic
always_comb begin
	// signal for enable
	enable = i_ready;
end

always_ff @(posedge clk or posedge reset) begin
	if (reset) begin
		x <= 0;
	end else if (enable) begin	
		// read in new x value
		x <= i_x;
	end
end

// pipeline the i_valid
always_ff @(posedge clk or posedge reset) begin
	if (reset) begin
		valid_p1 <= 1'b0;
		valid_p2 <= 1'b0;
		valid_p3 <= 1'b0; 
		valid_p4 <= 1'b0;
		valid_p5 <= 1'b0;
		valid_p6 <= 1'b0;
		valid_p7 <= 1'b0;
		valid_p8 <= 1'b0;
		valid_p9 <= 1'b0;
		
	end else if(enable) begin
		valid_p1 <= i_valid;
		valid_p2 <= valid_p1;
		valid_p3 <= valid_p2; 
		valid_p4 <= valid_p3;
		valid_p5 <= valid_p4;
		valid_p6 <= valid_p5;
		valid_p7 <= valid_p6;
		valid_p8 <= valid_p7;
		valid_p9 <= valid_p8;
	end
end

// Infer the registers
always_ff @(posedge clk or posedge reset) begin
	if (reset) begin
		valid_Q1 <= 1'b0;
		valid_Q2 <= 1'b0;
		
		y_Q <= 0;
	end else if (enable) begin
		// propagate the valid value
		valid_Q1 <= valid_p9;
		valid_Q2 <= valid_Q1;
		
		// output computed y value
		y_Q <= y_D;
	end
end

// assign outputs
assign o_y = y_Q;
// ready for inputs as long as receiver is ready for outputs */
assign o_ready = i_ready;   		
// the output is valid as long as the corresponding input was valid and 
//	the receiver is ready. If the receiver isn't ready, the computed output
//	will still remain on the register outputs and the circuit will resume
//  normal operation when the receiver is ready again (i_ready is high)
assign o_valid = valid_Q2 & i_ready;	

endmodule

/************************************************************/

// Multiplier module for the first 16x16 multiplication
module mult16x16 (
	input  [15:0] i_dataa,
	input  [15:0] i_datab,
	output [31:0] o_res
);

logic [31:0] result;

always_comb begin
	result = i_dataa * i_datab;
end

// The result of Q2.14 x Q2.14 is in the Q4.28 format. Therefore we need to change it
// to the Q7.25 format specified in the assignment by shifting right and padding with zeros.
assign o_res = {3'b000, result[31:3]};

endmodule

/***********************************************************/

// Multiplier module for all the remaining 32x16 multiplications
module mult32x16 (
	input  [31:0] i_dataa,
	input  [15:0] i_datab,
	output [31:0] o_res
);

logic [47:0] result;

always_comb begin
	result = i_dataa * i_datab;
end

// The result of Q7.25 x Q2.14 is in the Q9.39 format. Therefore we need to change it
// to the Q7.25 format specified in the assignment by selecting the appropriate bits
// (i.e. dropping the most-significant 2 bits and least-significant 14 bits).
assign o_res = result[45:14];

endmodule

/***********************************************************/

// Adder module for all the 32b+16b addition operations 
module addr32p16 (
	input [31:0] i_dataa,
	input [15:0] i_datab,
	output [31:0] o_res
);

// The 16-bit Q2.14 input needs to be aligned with the 32-bit Q7.25 input by zero padding
assign o_res = i_dataa + {5'b00000, i_datab, 11'b00000000000};

endmodule

// custom register module
// Q1 is 32-bit, used for pipeline the intermedia computed values
// Q2 is 16-bit, used for passing consistent X values
// ena, enable, allowes the register to stall
module reg32(
	input reset,
	input CLK,
	input ena,

	input [31:0] D1,
	output logic [31:0] Q1,
	
	input [15:0] D2,
	output logic [15:0] Q2
);

	always_ff @(posedge CLK or posedge reset) begin
		if(reset) begin
			Q1 <= 0; 
			Q2 <= 0; 
		end else if(ena) begin
			Q1 <= D1;
			Q2 <= D2;
		end
			
	end
endmodule

/*******************************************************************/
