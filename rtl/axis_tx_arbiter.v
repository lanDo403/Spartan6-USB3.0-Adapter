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

	reg m_axis_tvalid_ff;
	reg [DATA_LEN-1:0] m_axis_tdata_ff;
	reg [BE_LEN-1:0] m_axis_tkeep_ff;

	wire status_sel;
	wire loopback_sel;
	wire normal_sel;
	wire can_load;
	wire sel_valid;
	wire [DATA_LEN-1:0] sel_data;
	wire [BE_LEN-1:0] sel_keep;

	assign status_sel = status_frame_active_i;
	assign loopback_sel = !status_sel && loopback_mode_i;
	assign normal_sel = !status_sel && !loopback_mode_i;
	assign can_load = !m_axis_tvalid_ff || m_axis_tready_i;
	assign sel_valid = status_sel ? s_status_axis_tvalid_i :
	                          loopback_sel ? s_loopback_axis_tvalid_i :
	                          s_normal_axis_tvalid_i;
	assign sel_data = status_sel ? s_status_axis_tdata_i :
	                         loopback_sel ? s_loopback_axis_tdata_i :
	                         s_normal_axis_tdata_i;
	assign sel_keep = status_sel ? s_status_axis_tkeep_i :
	                         loopback_sel ? s_loopback_axis_tkeep_i :
	                         s_normal_axis_tkeep_i;

	always @(negedge clk) begin
		if (!rst_n) begin
			m_axis_tvalid_ff <= 1'b0;
			m_axis_tdata_ff <= {DATA_LEN{1'b0}};
			m_axis_tkeep_ff <= {BE_LEN{1'b0}};
		end
		else if (can_load) begin
			m_axis_tvalid_ff <= sel_valid;
			if (sel_valid) begin
				m_axis_tdata_ff <= sel_data;
				m_axis_tkeep_ff <= sel_keep;
			end
		end
	end

	assign s_status_axis_tready_o = can_load && status_sel;
	assign s_loopback_axis_tready_o = can_load && loopback_sel;
	assign s_normal_axis_tready_o = can_load && normal_sel;

	assign m_axis_tvalid_o = m_axis_tvalid_ff;
	assign m_axis_tdata_o = m_axis_tdata_ff;
	assign m_axis_tkeep_o = m_axis_tkeep_ff;

endmodule
