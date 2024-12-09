// This module implements 2D covolution between a 3x3 filter and a 512-pixel-wide image of any height.
// It is assumed that the input image is padded with zeros such that the input and output images have
// the same size. The filter coefficients are symmetric in the x-direction (i.e. f[0][0] = f[0][2], 
// f[1][0] = f[1][2], f[2][0] = f[2][2] for any filter f) and their values are limited to integers
// (but can still be positive of negative). The input image is grayscale with 8-bit pixel values ranging
// from 0 (black) to 255 (white).
module lab2 (
	input  clk,			// Operating clock
	input  reset,			// Active-high reset signal (reset when set to 1)
	input  [71:0] i_f,		// Nine 8-bit signed convolution filter coefficients in row-major format (i.e. i_f[7:0] is f[0][0], i_f[15:8] is f[0][1], etc.)
	input  i_valid,			// Set to 1 if input pixel is valid
	input  i_ready,			// Set to 1 if consumer block is ready to receive a new pixel
	input  [7:0] i_x,		// Input pixel value (8-bit unsigned value between 0 and 255)
	output o_valid,			// Set to 1 if output pixel is valid
	output o_ready,			// Set to 1 if this block is ready to receive a new pixel
	output [7:0] o_y		// Output pixel value (8-bit unsigned value between 0 and 255)
);

localparam FILTER_SIZE = 3;	// Convolution filter dimension (i.e. 3x3)
localparam PIXEL_DATAW = 8;	// Bit width of image pixels and filter coefficients (i.e. 8 bits)

// The following code is intended to show you an example of how to use paramaters and
// for loops in SytemVerilog. It also arrages the input filter coefficients for you
// into a nicely-arranged and easy-to-use 2D array of registers. However, you can ignore
// this code and not use it if you wish to.

logic signed [PIXEL_DATAW-1:0] r_f [FILTER_SIZE-1:0][FILTER_SIZE-1:0]; // 2D array of registers for filter coefficients
integer col, row; // variables to use in the for loop
always_ff @ (posedge clk) begin
	// If reset signal is high, set all the filter coefficient registers to zeros
	// We're using a synchronous reset, which is recommended style for recent FPGA architectures
	if(reset)begin
		for(row = 0; row < FILTER_SIZE; row = row + 1) begin
			for(col = 0; col < FILTER_SIZE; col = col + 1) begin
				r_f[row][col] <= 0;
			end
		end
	// Otherwise, register the input filter coefficients into the 2D array signal
	end else begin
		for(row = 0; row < FILTER_SIZE; row = row + 1) begin
			for(col = 0; col < FILTER_SIZE; col = col + 1) begin
				// Rearrange the 72-bit input into a 3x3 array of 8-bit filter coefficients.
				// signal[a +: b] is equivalent to signal[a+b-1 : a]. You can try to plug in
				// values for col and row from 0 to 2, to understand how it operates.
				// For example at row=0 and col=0: r_f[0][0] = i_f[0+:8] = i_f[7:0]
				//	       at row=0 and col=1: r_f[0][1] = i_f[8+:8] = i_f[15:8]
				r_f[row][col] <= i_f[(row * FILTER_SIZE * PIXEL_DATAW)+(col * PIXEL_DATAW) +: PIXEL_DATAW];
			end
		end
	end
end

// Start of your code
// --------------- define parameters-------------------------
localparam WIDTH = 512; // Input image width without padding
localparam WIDTH_PAD = 514; // Input image width with padding
localparam WIDTH_DATAW = 10; // 512 + padding, need 10 bits to store
localparam PIPELINE_STAGES = 10; // number of pipeline stages

integer i;

// ----------------initialize memory_3row module------------------
// buffer the enough pixels to generate the first output
logic write_enable [2:0];
logic [WIDTH_DATAW-1:0] write_address [2:0];
logic [PIXEL_DATAW-1:0] data_in [2:0];
logic [WIDTH_DATAW-1:0] read_address;
logic [PIXEL_DATAW-1:0] data_out [2:0];

logic enable;
always_comb begin
	// signal for enable
	enable = i_ready;
end

memory_3row Memory3row (.CLK(clk), .ENA(enable), .write_ENA(write_enable), .write_address(write_address), .data_in(data_in), .read_address(read_address), .data_out(data_out));

// --------create logics to save pixel data into memory-----------------
// row_counter and col_counter indicate the current location in the memory
// data should be read from col_read
// idx is used to overwrite an old row with a new row
logic unsigned [1:0]row_counter;
logic unsigned [WIDTH_DATAW-1:0] col_counter;
logic unsigned [WIDTH_DATAW-1:0] col_read;
logic unsigned [2:0][1:0] idx;

always_ff @(posedge clk or posedge reset) begin
	if (reset) begin
		for(i=0; i<3; i=i+1) begin
			write_enable[i] <= 0;
			write_address[i] <= 0;
			data_in[i] <= 0;
			idx[i] <= i;
		end
		row_counter <= 0;
		col_counter <= 0;
		col_read <= 0;
	end else if(enable) begin
		if(i_valid) begin
			if(col_counter != WIDTH_PAD) begin
				write_enable[idx[2]] <= 1;
				write_address[idx[2]] <= col_counter;
				data_in[idx[2]] <= i_x;

				col_read <= col_counter;
				col_counter <= col_counter + 1;
			end else begin
				write_enable[idx[0]] <= 1;
				write_address[idx[0]] <= 0;
				data_in[idx[0]] <= i_x;

				idx <= {idx[0], idx[2:1]};
				col_read <= 0;
				col_counter <= 1;

				// when row counter = 2 indicates three rows are filled
				if(row_counter < 2) begin
					row_counter <= row_counter + 1;
				end
			end
		end
	end
end

// read from saved data
always_comb begin
	read_address = col_read;
end

// ------------pipeline the control signals---------------
// need to match the memory and the dsp cycles, 10 pipeline stages are used here
logic unsigned [PIPELINE_STAGES-1:0][1:0] row_counter_p; // row counter pipelined
logic unsigned [PIPELINE_STAGES-1:0][WIDTH_DATAW-1:0] col_counter_p; // column counter pipelined
logic unsigned [2:0][2:0] [1:0] idx_p; // this parameter only needs to be pipelined to prepare data section

// pipelined the signals
always_ff @(posedge clk) begin
	if (enable) begin
		row_counter_p <= {row_counter_p[PIPELINE_STAGES-2:0], row_counter};
		col_counter_p <= {col_counter_p[PIPELINE_STAGES-2:0], col_counter};
		idx_p <= {idx_p[1:0], idx};
	end
end

//--------------prepare data-------------------------
// read data from memory each cycle
// each cycle fill MAC_input_row012[0], next cycle MAC_input_row012[1] ...
logic signed [2:0][PIXEL_DATAW:0] MAC_input_row0;
logic signed [2:0][PIXEL_DATAW:0] MAC_input_row1;
logic signed [2:0][PIXEL_DATAW:0] MAC_input_row2;
logic [PIXEL_DATAW:0] data_from_memory [2:0];

always_ff @(posedge clk) begin
	if (enable) begin
		data_from_memory[0] <= {1'b0, data_out[0]};
		data_from_memory[1] <= {1'b0, data_out[1]};
		data_from_memory[2] <= {1'b0, data_out[2]};

		MAC_input_row0 <= {data_from_memory[idx_p[2][0]], MAC_input_row0[2:1]};
		MAC_input_row1 <= {data_from_memory[idx_p[2][1]], MAC_input_row1[2:1]};
		MAC_input_row2 <= {data_from_memory[idx_p[2][2]], MAC_input_row2[2:1]};
	end
end

//--------------perform multiply and add operations-------------------
// each DSP corresponds to the convolution of size 3 in a row. Three rows in total
// p0*c0 + p1*c1 + p2*c2 are reduced to (p0+p2)*c0 + p1*c1 due to symmtric filter
logic signed [15:0] sum_row0;
logic signed [15:0] sum_row1;
logic signed [15:0] sum_row2;

// row 0, first DSP
DSP_sum2 DSP_A (.CLK(clk), .ENA(enable), .pixel0(MAC_input_row0[0]), .pixel1(MAC_input_row0[1]), .pixel2(MAC_input_row0[2]),
			 .coeff0(r_f[0][0]), .coeff1(r_f[0][1]), .result(sum_row0));

// row 1, second DSP
DSP_sum2 DSP_B (.CLK(clk), .ENA(enable), .pixel0(MAC_input_row1[0]), .pixel1(MAC_input_row1[1]), .pixel2(MAC_input_row1[2]),
			 .coeff0(r_f[1][0]), .coeff1(r_f[1][1]), .result(sum_row1));

// row 2, third DSP
DSP_sum2 DSP_C (.CLK(clk), .ENA(enable), .pixel0(MAC_input_row2[0]), .pixel1(MAC_input_row2[1]), .pixel2(MAC_input_row2[2]),
			 .coeff0(r_f[2][0]), .coeff1(r_f[2][1]), .result(sum_row2));

//--------------sum three row sums-----------------------
// sum the partial sums of three rows to get the final result
// this summation is done by LEs, not DSPs 
logic signed [16:0] sum_row0_p0;
logic signed [16:0] sum_row1_p0;
logic signed [16:0] sum_row2_p0;

logic signed [16:0] sum_row01_p1;
logic signed [16:0] sum_row2_p1;

logic signed [16:0] sum_row012_p2;

logic signed [16:0] total_sum;
logic unsigned [PIXEL_DATAW-1:0] final_sum;

always_ff @ (posedge clk) begin
	if(enable) begin
		sum_row0_p0 <= sum_row0;
		sum_row1_p0 <= sum_row1;
		sum_row2_p0 <= sum_row2;

		total_sum <= sum_row012_p2;
	end
end

always_comb begin
	sum_row01_p1 <= sum_row0_p0 + sum_row1_p0 + sum_row2_p0;
end

// since the output type should be 8 bit unsigned,
// take care of the overflow and underflow 
always_comb begin
	sum_row012_p2 <= sum_row01_p1;

	if(total_sum < 0) begin
		final_sum = 0;
	end else if(total_sum > 255) begin
		final_sum = 255;
	end else begin 
		final_sum = total_sum[PIXEL_DATAW-1:0];
	end 
end

// ----------------assign outputs------------------
logic unsigned [PIXEL_DATAW-1:0] y_Q;
logic y_valid;

always_ff @(posedge clk or posedge reset) begin
	if (reset) begin
		y_Q <= 0;
		y_valid <= 0;
		// prev_col_counter <= 0;
	end else if(enable) begin
		// results are valid when more than than 3 columns 
		// and 3 rows are saved in the memory 
		if(col_counter_p[PIPELINE_STAGES-1] >= 3 &&
		row_counter_p[PIPELINE_STAGES-1] == 2) begin
			y_Q <= final_sum;
			y_valid <= 1;
		end else begin
			y_Q <= 0;
			y_valid <= 0;
		end
	end
end

assign o_y = y_Q;
assign o_ready = i_ready;
assign o_valid = y_valid & i_ready;

endmodule

//-----------------------------------------------------
// RAM that saves three rows of input pixels, 514 * 3 total pixels
// Re-usebility is achieved by index manipulation - <idx> parameter
// each cycle three pixels in the same column is read out
module memory_3row(
	input CLK,
	input ENA,
	input write_ENA[2:0],
    input [9:0] write_address [2:0],
    input unsigned [7:0] data_in [2:0],
    input [9:0] read_address,
    output logic unsigned [7:0] data_out [2:0]
);

logic unsigned [7:0] memory_row0 [513:0];
logic unsigned [7:0] memory_row1 [513:0];
logic unsigned [7:0] memory_row2 [513:0];
logic [9:0] read_address_reg;

integer i;

always_ff @(posedge CLK) begin
	if(ENA) begin
		read_address_reg <= read_address;

		if(write_ENA[0]) begin
			memory_row0[write_address[0]] <= data_in[0];
		end
		if(write_ENA[1]) begin
			memory_row1[write_address[1]] <= data_in[1];
		end
		if(write_ENA[2]) begin
			memory_row2[write_address[2]] <= data_in[2];
		end

		data_out[0] <= memory_row0[read_address_reg];
		data_out[1] <= memory_row1[read_address_reg];
		data_out[2] <= memory_row2[read_address_reg];
	end
end
endmodule

//--------------------------------------------------------------------------
// multiply and accumulate 3 pixels with 3 filter coefficients (row-wise)
// since filter is symmetric in the x-direction,
// we can omit the third coefficient to skip a multiplication
// This allows the one-row computation implemented with one DSP block 
// pixel0*coeff0 + pixel1*coeff1 + pixel2*coeff2 = (pixel0+pixel2)*coeff0 + pixel1*coeff1
// registers are added to match DSP structure
// Quartus will map this module to DSP 18x18 sum of 2 mode automatically
// each module consumes two 18x19 DSP block or one 27x27 DSP block
module DSP_sum2 (
    input CLK,
    input ENA,
    input signed [8:0] pixel0,
    input signed [8:0] pixel1,
    input signed [8:0] pixel2,
    input signed [7:0] coeff0,
    input signed [7:0] coeff1,
    output logic signed [15:0] result
) /* synthesis multstyle = "dsp" */;

logic signed [8:0] pixel0_p0, pixel1_p0, pixel2_p0;
// NOTE: use 10 bit here, in case overflow in addition!!!
logic signed [9:0] pixel02_p1, pixel02_p2;
logic signed [8:0] pixel1_p1, pixel1_p2;
logic signed [7:0] coeff0_p0, coeff1_p0;
logic signed [7:0] coeff0_p1, coeff1_p1;
logic signed [7:0] coeff0_p2, coeff1_p2;

always_ff @(posedge CLK) begin
    if(ENA) begin
        pixel0_p0 <= pixel0;
        pixel1_p0 <= pixel1;
        pixel2_p0 <= pixel2;
        coeff0_p0 <= coeff0;
        coeff1_p0 <= coeff1;

        pixel02_p1 <= pixel0_p0 + pixel2_p0;
        pixel1_p1 <= pixel1_p0;
        coeff0_p1 <= coeff0_p0;
        coeff1_p1 <= coeff1_p0;

        pixel02_p2 <= pixel02_p1;
        pixel1_p2 <= pixel1_p1;
        coeff0_p2 <= coeff0_p1;
        coeff1_p2 <= coeff1_p1;

        result <= pixel02_p2*coeff0_p2 + pixel1_p2*coeff1_p2;
    end
end
endmodule
//-----------------------------------------------------------