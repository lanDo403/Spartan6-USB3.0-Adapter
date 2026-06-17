`timescale 1ns / 1ps

// Packs GPIO bytes into 32-bit stream words.
// GPIO_STROB becomes the per-byte keep mask; gaps become zero bytes with keep=0.
module packer8to32 #(
	parameter DATA_LEN = 32,
	parameter GPIO_LEN = 8,
	parameter BE_LEN = DATA_LEN / GPIO_LEN
)
(
	input 						clk,
	input 						rst_n,
	input 						valid_i,
	input  [GPIO_LEN-1:0] 	data_i,
	output 						valid_o,
	output [DATA_LEN-1:0] 	data_o,
	output [BE_LEN-1:0]    keep_o
    );

	localparam SHIFT_DATA_LEN = DATA_LEN - GPIO_LEN;
	localparam SHIFT_KEEP_LEN = BE_LEN - 1;

	reg [1:0] byte_counter;
	reg [SHIFT_DATA_LEN-1:0] data_shift_ff;
	reg [SHIFT_KEEP_LEN-1:0] keep_shift_ff;
	reg [DATA_LEN-1:0] data_ff;
	reg [BE_LEN-1:0] keep_ff;
	reg valid_ff;

	wire [GPIO_LEN-1:0] byte_w;
	wire [DATA_LEN-1:0] data_next_w;
	wire [BE_LEN-1:0] keep_next_w;
	wire [SHIFT_DATA_LEN-1:0] data_shift_next_w;
	wire [SHIFT_KEEP_LEN-1:0] keep_shift_next_w;

	assign byte_w = valid_i ? data_i : {GPIO_LEN{1'b0}};
	assign data_next_w = {byte_w, data_shift_ff};
	assign keep_next_w = {valid_i, keep_shift_ff};
	assign data_shift_next_w = data_next_w[DATA_LEN-1:GPIO_LEN];
	assign keep_shift_next_w = keep_next_w[BE_LEN-1:1];
	
	// After the first valid byte, collect a fixed four-cycle GPIO window.
	always @(negedge clk) begin
		if (!rst_n) begin
			byte_counter <= 2'd0;
			data_shift_ff <= {SHIFT_DATA_LEN{1'b0}};
			keep_shift_ff <= {SHIFT_KEEP_LEN{1'b0}};
			data_ff <= {DATA_LEN{1'b0}};
			keep_ff <= {BE_LEN{1'b0}};
			valid_ff <= 1'b0;
		end
		else begin
			valid_ff <= 1'b0;

			if (byte_counter == 2'd0) begin
				if (valid_i) begin
					data_shift_ff <= {data_i, {(SHIFT_DATA_LEN-GPIO_LEN){1'b0}}};
					keep_shift_ff <= {1'b1, {(SHIFT_KEEP_LEN-1){1'b0}}};
					byte_counter <= 2'd1;
				end
			end
			else if (byte_counter == 2'd3) begin
				data_ff <= data_next_w;
				keep_ff <= keep_next_w;
				valid_ff <= |keep_next_w;
				byte_counter <= 2'd0;
				data_shift_ff <= {SHIFT_DATA_LEN{1'b0}};
				keep_shift_ff <= {SHIFT_KEEP_LEN{1'b0}};
			end
			else begin
				data_shift_ff <= data_shift_next_w;
				keep_shift_ff <= keep_shift_next_w;
				byte_counter <= byte_counter + 1'b1;
			end
		end
	end

	assign valid_o = valid_ff;
	assign data_o 	= data_ff;
	assign keep_o = keep_ff;
endmodule
