`timescale 1ns / 1ps

// Emits the two-word status response frame on the shared TX stream.
// Status bits are snapshotted when a request is accepted.
module status_source #(
	parameter DATA_LEN = 32,
	parameter BE_LEN   = 4
)(
	input                    clk,
	input                    rst_n,
	input                    block_i,
	input                    start_ready_i,
	input                    req_i,
	input                    loopback_mode_i,
	input                    service_frame_error_i,
	input                    tx_fifo_empty_i,
	input                    tx_fifo_full_i,
	input                    loopback_fifo_empty_i,
	input                    loopback_fifo_full_i,
	output                   frame_active_o,
	input                    m_axis_tready_i,
	output                   m_axis_tvalid_o,
	output [DATA_LEN-1:0]    m_axis_tdata_o,
	output [BE_LEN-1:0]      m_axis_tkeep_o
);
	localparam STATUS_BITS_LEN = 6;
	localparam [DATA_LEN-1:0] STATUS_MAGIC = 32'h5AA55AA5;

	reg req_queued_ff;
	reg active_ff;
	reg frame_header_ff;
	reg [1:0] frame_words_left_ff;
	reg [STATUS_BITS_LEN-1:0] status_bits_ff;

	wire frame_valid;
	wire [DATA_LEN-1:0] frame_word;
	wire req_start_now;
	wire frame_start;

	assign frame_valid = active_ff && (frame_words_left_ff != 2'd0);
	assign frame_word = frame_header_ff ? STATUS_MAGIC :
	                         {{(DATA_LEN-STATUS_BITS_LEN){1'b0}}, status_bits_ff};
	assign req_start_now = req_i && !req_queued_ff && !active_ff && start_ready_i && !block_i;
	assign frame_start = req_start_now || (req_queued_ff && start_ready_i && !block_i);

	// Capture a snapshot of status bits and queue a response request.
	always @(negedge clk) begin
		if (!rst_n) begin
			req_queued_ff <= 1'b0;
			status_bits_ff <= {STATUS_BITS_LEN{1'b0}};
		end
		else begin
			if (req_i && !req_queued_ff && !active_ff) begin
				req_queued_ff <= !req_start_now;
				status_bits_ff <= {
				                   loopback_fifo_full_i,
				                   loopback_fifo_empty_i,
				                   tx_fifo_full_i,
				                   tx_fifo_empty_i,
				                   service_frame_error_i,
				                   loopback_mode_i
				                  };
			end
			else if (frame_start) begin
				req_queued_ff <= 1'b0;
			end
		end
	end

	// Drive the two-word status frame using only the AXI-Stream handshake.
	always @(negedge clk) begin
		if (!rst_n) begin
			active_ff <= 1'b0;
			frame_header_ff <= 1'b0;
			frame_words_left_ff <= 2'b00;
		end
		else begin
			if (frame_start) begin
				active_ff <= 1'b1;
				frame_header_ff <= 1'b1;
				frame_words_left_ff <= 2'd2;
			end

			if (frame_valid && m_axis_tready_i) begin
				if (frame_words_left_ff == 2'd1) begin
					active_ff <= 1'b0;
					frame_header_ff <= 1'b0;
					frame_words_left_ff <= 2'b00;
				end
				else begin
					frame_words_left_ff <= frame_words_left_ff - 1'b1;
					frame_header_ff <= 1'b0;
				end
			end
		end
	end

	assign frame_active_o = active_ff || req_queued_ff;
	assign m_axis_tvalid_o = frame_valid;
	assign m_axis_tdata_o = frame_word;
	assign m_axis_tkeep_o = {BE_LEN{1'b1}};

endmodule
