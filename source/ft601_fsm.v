`timescale 1ns / 1ps

module ft601_fsm #(
	parameter DATA_LEN = 32,
	parameter BE_LEN   = 4
)(
	input                    rst_n,
	input                    clk,
	input                    txe_n,
	input                    rxf_n,

	input                    s_axis_tvalid_i,
	output                   s_axis_tready_o,
	input  [DATA_LEN-1:0]    s_axis_tdata_i,
	input  [BE_LEN-1:0]      s_axis_tkeep_i,

	output                   m_axis_tvalid_o,
	input                    m_axis_tready_i,
	output [DATA_LEN-1:0]    m_axis_tdata_o,
	output [BE_LEN-1:0]      m_axis_tkeep_o,
	input  [DATA_LEN-1:0]    rx_data_i,
	input  [BE_LEN-1:0]      rx_keep_i,

	input                    mode_switch_busy_i,
	input                    tx_prefetch_en_i,
	input                    tx_status_sel_i,

	output [DATA_LEN-1:0]    tx_data_o,
	output [BE_LEN-1:0]      tx_keep_o,
	output                   wr_n,
	output                   rd_n,
	output                   oe_n,
	output                   drive_tx,
	output                   idle_o
);

	localparam ARB         = 6'b000001;
	localparam TX_PREFETCH = 6'b000010;
	localparam TX_BURST    = 6'b000100;
	localparam RX_START    = 6'b001000;
	localparam RX_BURST    = 6'b010000;
	localparam TURNAROUND  = 6'b100000;

	reg [5:0] next_state;
	reg [5:0] state;

	wire rx_start_req;
	wire rx_burst_req;
	wire rx_idle;
	wire rx_rd_n;
	wire rx_oe_n;
	wire tx_bus_valid;
	wire tx_idle;
	wire tx_wr_n;
	wire tx_drive;
	wire tx_wr_req;
	wire tx_burst_req;
	wire tx_bus_wr_hs;
	wire rx_takeover_req;
	wire turnaround_phase;

	assign rx_start_req = !rxf_n && m_axis_tready_i;
	assign rx_burst_req = !rxf_n && m_axis_tready_i;
	assign rx_takeover_req = !mode_switch_busy_i && rx_start_req;
	assign tx_wr_req = !txe_n && tx_bus_valid;
	assign tx_burst_req = tx_wr_req;
	assign tx_bus_wr_hs = ((state == TX_PREFETCH) || (state == TX_BURST)) &&
	                           tx_wr_req;
	assign turnaround_phase = (state == TURNAROUND);

	always @(negedge clk) begin
		if (!rst_n)
			state <= ARB;
		else
			state <= next_state;
	end

	always @(*) begin
		next_state = state;
		case (state)
			ARB:         next_state = (!mode_switch_busy_i && rx_start_req) ? RX_START :
			                         tx_wr_req ? TX_PREFETCH : ARB;
			TX_PREFETCH: next_state = rx_takeover_req ? TURNAROUND :
			                         tx_burst_req ? TX_BURST : TX_PREFETCH;
			TX_BURST:    next_state = rx_takeover_req ? TURNAROUND :
			                         tx_burst_req ? TX_BURST : TURNAROUND;
			RX_START:    next_state = RX_BURST;
			RX_BURST:    next_state = rx_burst_req ? RX_BURST : TURNAROUND;
			TURNAROUND:  next_state = ARB;
			default:     next_state = ARB;
		endcase
	end

	ft601_rx_adapter #(
		.DATA_LEN(DATA_LEN),
		.BE_LEN(BE_LEN)
	) rx_adapter (
		.clk_i(clk),
		.rst_n_i(rst_n),
		.start_i(state == RX_START),
		.burst_i(state == RX_BURST),
		.rxf_n_i(rxf_n),
		.m_axis_tready_i(m_axis_tready_i),
		.bus_data_i(rx_data_i),
		.bus_keep_i(rx_keep_i),
		.m_axis_tdata_o(m_axis_tdata_o),
		.m_axis_tkeep_o(m_axis_tkeep_o),
		.m_axis_tvalid_o(m_axis_tvalid_o),
		.rd_n_o(rx_rd_n),
		.oe_n_o(rx_oe_n),
		.idle_o(rx_idle)
	);

	ft601_tx_adapter #(
		.DATA_LEN(DATA_LEN),
		.BE_LEN(BE_LEN)
	) tx_adapter (
		.clk_i(clk),
		.rst_n_i(rst_n),
		.txe_n_i(txe_n),
		.arb_phase_i(state == ARB),
		.prefetch_phase_i(state == TX_PREFETCH),
		.burst_phase_i(state == TX_BURST),
		.bus_wr_hs_i(tx_bus_wr_hs),
		.block_i(mode_switch_busy_i),
		.prefetch_en_i(tx_prefetch_en_i),
		.status_sel_i(tx_status_sel_i),
		.s_axis_tvalid_i(s_axis_tvalid_i),
		.s_axis_tdata_i(s_axis_tdata_i),
		.s_axis_tkeep_i(s_axis_tkeep_i),
		.s_axis_tready_o(s_axis_tready_o),
		.bus_valid_o(tx_bus_valid),
		.idle_o(tx_idle),
		.bus_data_o(tx_data_o),
		.bus_keep_o(tx_keep_o),
		.wr_n_o(tx_wr_n),
		.bus_drive_o(tx_drive)
	);

	assign wr_n = turnaround_phase ? 1'b1 : tx_wr_n;
	assign rd_n = turnaround_phase ? 1'b1 : rx_rd_n;
	assign oe_n = turnaround_phase ? 1'b1 : rx_oe_n;
	assign drive_tx = turnaround_phase ? 1'b0 : tx_drive;
	assign idle_o = (state == ARB) && tx_idle && rx_idle && wr_n && rd_n && oe_n && !drive_tx;

endmodule
