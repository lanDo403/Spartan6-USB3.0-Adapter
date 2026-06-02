`timescale 1ns / 1ps

module axis_fifo_write_adapter #(
	parameter DATA_LEN = 32,
	parameter KEEP_LEN = 4,
	parameter FIFO_DATA_LEN = DATA_LEN + KEEP_LEN
)(
	input                    enable_i,

	input                    s_axis_tvalid_i,
	output                   s_axis_tready_o,
	input  [DATA_LEN-1:0]    s_axis_tdata_i,
	input  [KEEP_LEN-1:0]    s_axis_tkeep_i,

	input                    fifo_full_i,
	output                   fifo_wen_o,
	output [FIFO_DATA_LEN-1:0] fifo_data_o
);

	wire keep_valid;

	assign keep_valid = |s_axis_tkeep_i;
	assign s_axis_tready_o = enable_i && !fifo_full_i && keep_valid;
	assign fifo_wen_o = s_axis_tvalid_i && s_axis_tready_o;
	assign fifo_data_o = {s_axis_tdata_i, s_axis_tkeep_i};

endmodule
