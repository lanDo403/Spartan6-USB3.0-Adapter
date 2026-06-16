`timescale 1ns / 1ps

module service_status_policy (
	input  clk_i,
	input  rst_n_i,
	input  mode_switch_busy_i,
	input  status_req_i,
	input  status_frame_active_i,
	input  txe_n_i,
	input  fsm_idle_i,
	output payload_block_o,
	output status_source_block_o,
	output rx_router_block_o,
	output status_start_ready_o,
	output tx_payload_accept_o
);

	reg status_payload_hold_ff;
	reg status_txe_low_seen_ff;
	reg tx_payload_accept_ff;
	wire status_window_active;

	// Status read is a stop-and-wait service transaction on the shared FT601 IN
	// endpoint. Payload is blocked until the host opens a TX window for the
	// status frame and the shared TX path returns to idle.
	always @(negedge clk_i) begin
		if (!rst_n_i) begin
			status_payload_hold_ff <= 1'b0;
			status_txe_low_seen_ff <= 1'b0;
			tx_payload_accept_ff <= 1'b0;
		end
		else begin
			tx_payload_accept_ff <= !txe_n_i;

			if (status_req_i || status_frame_active_i)
				status_payload_hold_ff <= 1'b1;

			if (status_payload_hold_ff && !txe_n_i)
				status_txe_low_seen_ff <= 1'b1;

			if (status_payload_hold_ff && status_txe_low_seen_ff &&
			    !status_req_i && !status_frame_active_i && fsm_idle_i) begin
				status_payload_hold_ff <= 1'b0;
				status_txe_low_seen_ff <= 1'b0;
			end
		end
	end

	assign status_window_active = status_frame_active_i || status_payload_hold_ff;
	assign payload_block_o = mode_switch_busy_i || status_req_i || status_window_active;
	assign status_source_block_o = mode_switch_busy_i;
	assign rx_router_block_o = mode_switch_busy_i && fsm_idle_i;
	assign status_start_ready_o = fsm_idle_i;
	assign tx_payload_accept_o = tx_payload_accept_ff;

endmodule
