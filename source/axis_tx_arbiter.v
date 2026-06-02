`timescale 1ns / 1ps

module axis_tx_arbiter #(
	parameter DATA_LEN = 32,
	parameter BE_LEN   = 4
)(
	input                    clk,
	input                    rst_n,
	input                    status_frame_active_i,
	input                    loopback_mode_i,

	input                    s_normal_axis_tvalid_i,
	output                   s_normal_axis_tready_o,
	input  [DATA_LEN-1:0]    s_normal_axis_tdata_i,
	input  [BE_LEN-1:0]      s_normal_axis_tkeep_i,

	input                    s_loopback_axis_tvalid_i,
	output                   s_loopback_axis_tready_o,
	input  [DATA_LEN-1:0]    s_loopback_axis_tdata_i,
	input  [BE_LEN-1:0]      s_loopback_axis_tkeep_i,

	input                    s_status_axis_tvalid_i,
	output                   s_status_axis_tready_o,
	input  [DATA_LEN-1:0]    s_status_axis_tdata_i,
	input  [BE_LEN-1:0]      s_status_axis_tkeep_i,

	output                   m_axis_tvalid_o,
	input                    m_axis_tready_i,
	output [DATA_LEN-1:0]    m_axis_tdata_o,
	output [BE_LEN-1:0]      m_axis_tkeep_o
);

	localparam [1:0] STATUS_FRAME_WORDS = 2'd2;

	reg status_frame_busy_ff;
	reg [1:0] status_words_left_ff;
	reg m_axis_tvalid_ff;
	reg [DATA_LEN-1:0] m_axis_tdata_ff;
	reg [BE_LEN-1:0] m_axis_tkeep_ff;
	reg m_axis_status_ff;
	reg status_sel_d_ff;

	wire status_sel;
	wire loopback_sel;
	wire normal_sel;
	wire m_axis_ready;
	wire status_start;
	wire status_axis_hs;
	wire sel_valid;
	wire [DATA_LEN-1:0] sel_data;
	wire [BE_LEN-1:0] sel_keep;

	assign status_sel = status_frame_busy_ff || status_frame_active_i;
	assign status_start = status_sel && !status_sel_d_ff;
	assign loopback_sel = !status_sel && loopback_mode_i;
	assign normal_sel = !status_sel && !loopback_mode_i;
	assign m_axis_ready = m_axis_tready_i;
	assign sel_valid = status_sel ? s_status_axis_tvalid_i :
	                          loopback_sel ? s_loopback_axis_tvalid_i :
	                          s_normal_axis_tvalid_i;
	assign sel_data = status_sel ? s_status_axis_tdata_i :
	                         loopback_sel ? s_loopback_axis_tdata_i :
	                         s_normal_axis_tdata_i;
	assign sel_keep = status_sel ? s_status_axis_tkeep_i :
	                         loopback_sel ? s_loopback_axis_tkeep_i :
	                         s_normal_axis_tkeep_i;
	assign status_axis_hs = m_axis_ready &&
	                              status_sel &&
	                              s_status_axis_tvalid_i;

	// Fixed two-word status frame lock: STATUS_MAGIC followed by status_word.
	always @(negedge clk) begin
		if (!rst_n) begin
			status_frame_busy_ff <= 1'b0;
			status_words_left_ff <= 2'b00;
			status_sel_d_ff <= 1'b0;
		end
		else begin
			status_sel_d_ff <= status_sel;

			if (!status_frame_busy_ff && status_frame_active_i) begin
				status_frame_busy_ff <= 1'b1;
				status_words_left_ff <= STATUS_FRAME_WORDS;
			end

			if (status_axis_hs) begin
				if (!status_frame_busy_ff) begin
					status_frame_busy_ff <= 1'b1;
					status_words_left_ff <= STATUS_FRAME_WORDS - 1'b1;
				end
				else if (status_words_left_ff <= 2'd1) begin
					status_frame_busy_ff <= 1'b0;
					status_words_left_ff <= 2'b00;
				end
				else begin
					status_words_left_ff <= status_words_left_ff - 1'b1;
				end
			end
		end
	end

	always @(negedge clk) begin
		if (!rst_n) begin
			m_axis_tvalid_ff <= 1'b0;
			m_axis_tdata_ff <= {DATA_LEN{1'b0}};
			m_axis_tkeep_ff <= {BE_LEN{1'b0}};
			m_axis_status_ff <= 1'b0;
		end
		else if (status_start && !m_axis_status_ff) begin
			m_axis_tvalid_ff <= 1'b0;
			m_axis_status_ff <= 1'b0;
		end
		else if (m_axis_ready) begin
			m_axis_tvalid_ff <= sel_valid;
			if (sel_valid) begin
				m_axis_tdata_ff <= sel_data;
				m_axis_tkeep_ff <= sel_keep;
				m_axis_status_ff <= status_sel;
			end
			else begin
				m_axis_status_ff <= 1'b0;
			end
		end
	end

	assign s_status_axis_tready_o = m_axis_ready && status_sel && !status_start;
	assign s_loopback_axis_tready_o = m_axis_ready && loopback_sel;
	assign s_normal_axis_tready_o = m_axis_ready && normal_sel;

	assign m_axis_tvalid_o = m_axis_tvalid_ff;
	assign m_axis_tdata_o = m_axis_tdata_ff;
	assign m_axis_tkeep_o = m_axis_tkeep_ff;

endmodule
