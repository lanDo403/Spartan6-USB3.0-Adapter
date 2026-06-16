`timescale 1ns / 1ps

module ft601_rx_adapter #(
	parameter DATA_LEN = 32,
	parameter BE_LEN   = 4
)(
	input                    clk_i,
	input                    rst_n_i,
	input                    start_i,
	input                    burst_i,
	input                    rxf_n_i,
	input                    m_axis_tready_i,
	input  [DATA_LEN-1:0]    bus_data_i,
	input  [BE_LEN-1:0]      bus_keep_i,
	output [DATA_LEN-1:0]    m_axis_tdata_o,
	output [BE_LEN-1:0]      m_axis_tkeep_o,
	output                   m_axis_tvalid_o,
	output                   rd_n_o,
	output                   oe_n_o,
	output                   idle_o
);

	localparam STREAM_WORD_LEN = DATA_LEN + BE_LEN;

	reg [STREAM_WORD_LEN-1:0] buf0_ff;
	reg [STREAM_WORD_LEN-1:0] buf1_ff;
	reg [STREAM_WORD_LEN-1:0] buf2_ff;
	reg [STREAM_WORD_LEN-1:0] buf3_ff;
	reg [2:0]          buf_count_ff;
	reg                bus_rd_hs_d1_ff;
	reg                bus_rd_hs_d2_ff;
	reg                bus_rd_valid_d2_ff;

	reg [STREAM_WORD_LEN-1:0] buf0_next;
	reg [STREAM_WORD_LEN-1:0] buf1_next;
	reg [STREAM_WORD_LEN-1:0] buf2_next;
	reg [STREAM_WORD_LEN-1:0] buf3_next;
	reg [2:0]          buf_count_next;

	wire bus_rd_hs;
	wire buf_has_space;
	wire m_axis_hs;
	wire buf_push;
	wire [2:0] buf_used;
	wire [STREAM_WORD_LEN-1:0] bus_word;

	assign bus_word = {bus_keep_i, bus_data_i};
	assign buf_used = buf_count_ff + {2'b00, bus_rd_hs_d1_ff} +
	                       {2'b00, bus_rd_hs_d2_ff};
	assign buf_has_space = (buf_used < 3'd4);
	assign bus_rd_hs = burst_i && !rxf_n_i && buf_has_space;
	assign m_axis_hs = (buf_count_ff != 3'd0) && m_axis_tready_i;
	assign buf_push = bus_rd_valid_d2_ff && !rxf_n_i;
	assign rd_n_o = !bus_rd_hs;
	assign oe_n_o = !((start_i && !rxf_n_i && buf_has_space) || bus_rd_hs);

	always @(*) begin
		buf0_next = buf0_ff;
		buf1_next = buf1_ff;
		buf2_next = buf2_ff;
		buf3_next = buf3_ff;
		buf_count_next = buf_count_ff;

		if (m_axis_hs) begin
			case (buf_count_ff)
				3'd1:
					buf_count_next = 3'd0;

				3'd2: begin
					buf0_next = buf1_ff;
					buf_count_next = 3'd1;
				end

				3'd3: begin
					buf0_next = buf1_ff;
					buf1_next = buf2_ff;
					buf_count_next = 3'd2;
				end

				default: begin
					buf0_next = buf1_ff;
					buf1_next = buf2_ff;
					buf2_next = buf3_ff;
					buf_count_next = 3'd3;
				end
			endcase
		end

		if (buf_push) begin
			case (buf_count_next)
				3'd0:
					buf0_next = bus_word;

				3'd1:
					buf1_next = bus_word;

				3'd2:
					buf2_next = bus_word;

				default:
					buf3_next = bus_word;
			endcase

			if (buf_count_next < 3'd4)
				buf_count_next = buf_count_next + 1'b1;
		end
	end

	always @(negedge clk_i) begin
		if (!rst_n_i) begin
			buf0_ff <= {STREAM_WORD_LEN{1'b0}};
			buf1_ff <= {STREAM_WORD_LEN{1'b0}};
			buf2_ff <= {STREAM_WORD_LEN{1'b0}};
			buf3_ff <= {STREAM_WORD_LEN{1'b0}};
			buf_count_ff <= 3'd0;
			bus_rd_hs_d1_ff <= 1'b0;
			bus_rd_hs_d2_ff <= 1'b0;
			bus_rd_valid_d2_ff <= 1'b0;
		end
		else begin
			buf0_ff <= buf0_next;
			buf1_ff <= buf1_next;
			buf2_ff <= buf2_next;
			buf3_ff <= buf3_next;
			buf_count_ff <= buf_count_next;
			bus_rd_valid_d2_ff <= bus_rd_hs_d1_ff && !rxf_n_i;
			bus_rd_hs_d2_ff <= bus_rd_hs_d1_ff;
			bus_rd_hs_d1_ff <= bus_rd_hs;
		end
	end

	assign m_axis_tdata_o = buf0_ff[DATA_LEN-1:0];
	assign m_axis_tkeep_o = buf0_ff[STREAM_WORD_LEN-1:DATA_LEN];
	assign m_axis_tvalid_o = (buf_count_ff != 3'd0);
	assign idle_o = (buf_count_ff == 3'd0) && !bus_rd_hs_d1_ff &&
	                !bus_rd_hs_d2_ff && !bus_rd_valid_d2_ff;

endmodule
