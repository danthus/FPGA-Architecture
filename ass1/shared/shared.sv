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

logic [WIDTHOUT-1:0] y_Q;	// Register to hold output Y
logic [WIDTHOUT-1:0] y_D;

// signal for enabling sequential circuit elements
logic enable;
logic [2:0] select;

// output signal of 5to1 mux, contains A4 to A0 parameters
logic [WIDTHIN-1:0] mux_out;

// signal from register that keeps the inital x
logic [WIDTHIN-1:0] init_x;

//input signals for multiplier
logic [WIDTHIN-1:0] m1_in;
logic [WIDTHOUT-1:0] m2_in;
// output signal from multiplier
logic [WIDTHOUT-1:0] m_out;
// output signal from adder
logic [WIDTHOUT-1:0] a_out;

// ready signal generated by FSM
logic fsm_ready;

// signal for i_valid to wait 5 cycles
// since each valid output takes 5 cycles
logic valid_Q1;
logic valid_Q2;
logic valid_Q3;
logic valid_Q4;
logic valid_Q5;

// connect the FSM
fsm counter (.clk(clk), .reset(reset), .i_ready(i_ready), .sel2(enable), .sel5(select), .o_ready(fsm_ready));

// create the 5to1 mux
assign mux_out = (select == 3'b000) ? A4 :
                (select == 3'b001) ? A3 :
                (select == 3'b010) ? A2 :
                (select == 3'b011) ? A1 : A0;

// register holds the inital x value for next several cycles
always_ff @(posedge clk or posedge reset) begin
	if (reset) begin
		init_x <= 0;
	end else if (i_valid) begin	
		// read in new x value
		init_x <= i_x;
	end
end

// 2to1 mux, choose A5 in the first cycle
// choose init_x for the rest four cycles
assign m1_in = enable ? init_x : A5;

// 2to1 mux, choose i_x in the first cycle
// choose y_Q for the the rest four cycles
assign m2_in = enable ? y_Q : {5'b00000, i_x, 11'b00000000000};

// one mult and one adder for shared HW design
mult32x16 Mult1 (.i_dataa(m2_in), 	.i_datab(m1_in), 	.o_res(m_out));
addr32p16 Addr1 (.i_dataa(m_out), 	.i_datab(mux_out), 	.o_res(a_out));

//assign adder output to y register
assign y_D = a_out;


// Y register, holds final result when o_ready and o_valid are true
// holds intermediate value then o_ready and o_valid are false
always_ff @(posedge clk or posedge reset) begin
	if (reset) begin
		y_Q <= 0;
	end else if(i_ready) begin	
		y_Q <= y_D;
	end
end

// register to propagate i_valid
always_ff @(posedge clk or posedge reset) begin
	if (reset) begin
		valid_Q1 <= 0;
		valid_Q2 <= 0;
		valid_Q3 <= 0;
		valid_Q4 <= 0;
		valid_Q5 <= 0;
	
	end else if (i_ready) begin	
		valid_Q1 <= i_valid;
		valid_Q2 <= valid_Q1;
		valid_Q3 <= valid_Q2;
		valid_Q4 <= valid_Q3;
		valid_Q5 <= valid_Q4;
	end
end

// output is valid as long as the propagated i_valid and FSM generates
// the Y register contains the final result.
assign o_valid = valid_Q5 & fsm_ready;

// assign outputs
assign o_y = y_Q;
// ready for inputs as long as receiver is ready for outputs */
assign o_ready = fsm_ready;   	

endmodule

// FSM module contains 5 states. Each state generates control signals for mux
// and indicate final result is ready or not.
// FSM stalls when i_ready is false
module fsm (input clk, reset, i_ready, output logic sel2, output logic [2:0] sel5, output logic o_ready);
	enum logic [2:0] {S0=3'b000, S1=3'b001, S2=3'b010, S3=3'b011, S4=3'b100} state;	
	
	always_ff @(posedge clk or posedge reset) begin
		if (reset) begin
			state <= S0;
			sel2 <= 1;
			sel5 <= 3'b000;
			o_ready <= 1;
		end else if (i_ready) begin
			case (state)
			S0: begin
				state <= S1;
				sel2 <= 0;
				sel5 <= 3'b000;
				o_ready <= 1;
			end
			S1: begin
				state <= S2;
				sel2 <= 1;
				sel5 <= 3'b001;
				o_ready <= 0;
			end
			S2: begin
				state <= S3;
				sel2 <= 1;
				sel5 <= 3'b010;
				o_ready <= 0;
			end
			S3: begin
				state <= S4;
				sel2 <= 1;
				sel5 <= 3'b011;
				o_ready <= 0;
			end
			S4: begin
				state <= S0;
				sel2 <= 1;
				sel5 <= 3'b100;
				o_ready <= 0;
			end
			endcase
		end
	end
endmodule

/******************************************************************/

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

/*********************************************************************/

// Adder module for all the 32b+16b addition operations 
module addr32p16 (
	input [31:0] i_dataa,
	input [15:0] i_datab,
	output [31:0] o_res
);

// The 16-bit Q2.14 input needs to be aligned with the 32-bit Q7.25 input by zero padding
assign o_res = i_dataa + {5'b00000, i_datab, 11'b00000000000};

endmodule

/********************************************************************/
