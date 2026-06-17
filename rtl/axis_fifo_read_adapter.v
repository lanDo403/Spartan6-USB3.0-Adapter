`timescale 1ns / 1ps

// Converts a synchronous FIFO read port into a valid/ready stream.
// The two-entry lookahead hides read latency and keeps output data stable.
module axis_fifo_read_adapter #(
	parameter DATA_LEN = 32,
	parameter KEEP_LEN = 4,
	parameter FIFO_DATA_LEN = DATA_LEN + KEEP_LEN
)(
	input                     clk,
	input                     rst_n,

	input  [FIFO_DATA_LEN-1:0] fifo_data_i,
	input                     fifo_empty_i,
	output                    fifo_ren_o,

	output                    m_axis_tvalid_o,
	input                     m_axis_tready_i,
	output [DATA_LEN-1:0]     m_axis_tdata_o,
	output [KEEP_LEN-1:0]     m_axis_tkeep_o
);

	reg [FIFO_DATA_LEN-1:0] out_word_ff;
	reg [FIFO_DATA_LEN-1:0] buf_word_ff;
	reg [1:0]          buf_count_ff;
	reg                fifo_ren_pending_ff;

	reg [FIFO_DATA_LEN-1:0] out_word_next;
	reg [FIFO_DATA_LEN-1:0] buf_word_next;
	reg [1:0]          buf_count_next;

	wire m_axis_hs;
	wire [1:0] buf_used;
	wire fifo_ren;

	assign m_axis_tvalid_o = (buf_count_ff != 2'd0);
	assign m_axis_tdata_o = out_word_ff[FIFO_DATA_LEN-1:KEEP_LEN];
	assign m_axis_tkeep_o = out_word_ff[KEEP_LEN-1:0];
	assign m_axis_hs = m_axis_tvalid_o && m_axis_tready_i;
	assign buf_used = buf_count_ff + {1'b0, fifo_ren_pending_ff};
	assign fifo_ren = !fifo_empty_i && ((buf_used < 2'd2) || m_axis_hs);
	assign fifo_ren_o = fifo_ren;

	// Consume the current output word first, then place a completed FIFO read
	// into the output slot or the spare lookahead slot.
	always @(*) begin
		out_word_next = out_word_ff;
		buf_word_next = buf_word_ff;
		buf_count_next = buf_count_ff;

		if (m_axis_hs) begin
			if (buf_count_ff == 2'd2) begin
				out_word_next = buf_word_ff;
				buf_count_next = 2'd1;
			end
			else begin
				buf_count_next = 2'd0;
			end
		end

		if (fifo_ren_pending_ff) begin
			if (buf_count_next == 2'd0) begin
				out_word_next = fifo_data_i;
				buf_count_next = 2'd1;
			end
			else begin
				buf_word_next = fifo_data_i;
				buf_count_next = 2'd2;
			end
		end
	end

	always @(negedge clk) begin
		if (!rst_n) begin
			out_word_ff <= {FIFO_DATA_LEN{1'b0}};
			buf_word_ff <= {FIFO_DATA_LEN{1'b0}};
			buf_count_ff <= 2'd0;
			fifo_ren_pending_ff <= 1'b0;
		end
		else begin
			out_word_ff <= out_word_next;
			buf_word_ff <= buf_word_next;
			buf_count_ff <= buf_count_next;
			fifo_ren_pending_ff <= fifo_ren;
		end
	end

endmodule
