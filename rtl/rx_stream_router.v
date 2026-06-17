`timescale 1ns / 1ps

// Demuxes FT601 RX stream words into service commands or loopback payload.
// A word is consumed by exactly one path; service frames are never echoed.
module rx_stream_router #(
	parameter DATA_LEN = 32,
	parameter BE_LEN   = 4,
	parameter FIFO_RX_LEN = DATA_LEN + BE_LEN
)(
	input                     clk,
	input                     rst_n,
	input                     block_i,
	input                     loopback_mode_i,

	input                     s_axis_tvalid_i,
	output                    s_axis_tready_o,
	input  [DATA_LEN-1:0]     s_axis_tdata_i,
	input  [BE_LEN-1:0]       s_axis_tkeep_i,

	output                    cmd_event_valid_o,
	output [DATA_LEN-1:0]     cmd_event_opcode_o,
	output                    service_frame_error_o,

	output                    m_payload_axis_tvalid_o,
	input                     m_payload_axis_tready_i,
	output [DATA_LEN-1:0]     m_payload_axis_tdata_o,
	output [BE_LEN-1:0]       m_payload_axis_tkeep_o
);

	localparam [DATA_LEN-1:0] CMD_MAGIC = 32'hA55A5AA5;

	reg cmd_wait_opcode_ff;
	reg cmd_valid_ff;
	reg [DATA_LEN-1:0] cmd_opcode_ff;
	reg service_frame_error_ff;
	reg payload_valid_ff;
	reg [DATA_LEN-1:0] payload_data_ff;
	reg [BE_LEN-1:0] payload_keep_ff;

	wire s_axis_full_keep;
	wire s_axis_has_keep;
	wire cmd_magic_match;
	wire payload_route_selected;
	wire payload_buf_ready;
	wire payload_word_accept;
	wire s_axis_hs;

	assign s_axis_full_keep = (s_axis_tkeep_i == {BE_LEN{1'b1}});
	assign s_axis_has_keep = |s_axis_tkeep_i;
	assign cmd_magic_match = s_axis_full_keep && (s_axis_tdata_i == CMD_MAGIC);
	assign payload_route_selected = !cmd_wait_opcode_ff && loopback_mode_i &&
	                                !cmd_magic_match && s_axis_has_keep;
	assign payload_buf_ready = !payload_valid_ff || m_payload_axis_tready_i;
	assign payload_word_accept = payload_route_selected;

	assign s_axis_tready_o = !block_i && (!payload_route_selected || payload_buf_ready);
	assign s_axis_hs = s_axis_tvalid_i && s_axis_tready_o;

	// Service parser consumes CMD_MAGIC and the next beat as opcode.
	// Non-full opcode beats are drained and reported as malformed frames.
	always @(negedge clk) begin
		if (!rst_n) begin
			cmd_wait_opcode_ff <= 1'b0;
			cmd_valid_ff <= 1'b0;
			cmd_opcode_ff <= {DATA_LEN{1'b0}};
			service_frame_error_ff <= 1'b0;
		end
		else begin
			cmd_valid_ff <= 1'b0;
			service_frame_error_ff <= 1'b0;

			if (s_axis_hs && cmd_wait_opcode_ff && s_axis_full_keep) begin
				cmd_wait_opcode_ff <= 1'b0;
				cmd_valid_ff <= 1'b1;
				cmd_opcode_ff <= s_axis_tdata_i;
			end
			else if (s_axis_hs && cmd_wait_opcode_ff) begin
				cmd_wait_opcode_ff <= 1'b0;
				service_frame_error_ff <= 1'b1;
			end
			else if (s_axis_hs && cmd_magic_match) begin
				cmd_wait_opcode_ff <= 1'b1;
			end
		end
	end

	// One-word payload buffer decouples RX sampling from loopback FIFO backpressure.
	always @(negedge clk) begin
		if (!rst_n) begin
			payload_valid_ff <= 1'b0;
			payload_data_ff <= {DATA_LEN{1'b0}};
			payload_keep_ff <= {BE_LEN{1'b0}};
		end
		else begin
			if (payload_valid_ff && m_payload_axis_tready_i)
				payload_valid_ff <= 1'b0;

			if (s_axis_hs && payload_word_accept) begin
				payload_valid_ff <= 1'b1;
				payload_data_ff <= s_axis_tdata_i;
				payload_keep_ff <= s_axis_tkeep_i;
			end
		end
	end

	assign cmd_event_valid_o = cmd_valid_ff;
	assign cmd_event_opcode_o = cmd_opcode_ff;
	assign service_frame_error_o = service_frame_error_ff;
	assign m_payload_axis_tvalid_o = payload_valid_ff;
	assign m_payload_axis_tdata_o = payload_data_ff;
	assign m_payload_axis_tkeep_o = payload_keep_ff;

endmodule
