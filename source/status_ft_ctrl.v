`timescale 1ns / 1ps

module status_ft_ctrl #(
	parameter DATA_LEN = 32
)(
	input                    clk,
	input                    rst_n,
	input                    soft_clear_i,
	input                    service_hold_i,
	input                    ft_idle_i,
	input                    status_req_i,
	input                    status_pop_i,
	input                    status_send_i,
	input                    loopback_mode_i,
	input                    tx_error_i,
	input                    rx_error_i,
	input                    tx_fifo_empty_i,
	input                    tx_fifo_full_i,
	input                    loopback_fifo_empty_i,
	input                    loopback_fifo_full_i,
	output                   source_sel_o,
	output                   source_empty_o,
	output [DATA_LEN-1:0]    status_word_o,
	output                   source_change_o
);
	localparam STATUS_BITS_LEN = 7;
	localparam [DATA_LEN-1:0] STATUS_MAGIC = 32'h5AA55AA5;

	reg queued_ff;
	reg active_ff;
	reg tx_started_ff;
	reg word_is_header_ff;
	reg source_sel_p1_ff;
	reg [1:0] pending_words_ff;
	reg [STATUS_BITS_LEN-1:0] status_bits_ff;

	wire source_sel;
	wire [DATA_LEN-1:0] status_word_mux;

	assign source_sel = active_ff;
	assign status_word_mux = word_is_header_ff ? STATUS_MAGIC :
	                         {{(DATA_LEN-STATUS_BITS_LEN){1'b0}}, status_bits_ff};

	// Delay the current source selection by one cycle for source_change detection.
	always @(posedge clk) begin
		if (!rst_n) begin
			source_sel_p1_ff <= 1'b0;
		end
		else if (soft_clear_i) begin
			source_sel_p1_ff <= 1'b0;
		end
		else
			source_sel_p1_ff <= source_sel;
	end

	// Capture a snapshot of status bits and queue a response request.
	always @(posedge clk) begin
		if (!rst_n) begin
			queued_ff <= 1'b0;
			status_bits_ff <= {STATUS_BITS_LEN{1'b0}};
		end
		else if (soft_clear_i) begin
			queued_ff <= 1'b0;
			status_bits_ff <= {STATUS_BITS_LEN{1'b0}};
		end
		else begin
			if (status_req_i && !queued_ff && !active_ff) begin
				queued_ff <= 1'b1;
				status_bits_ff <= {
				                   loopback_fifo_full_i,
				                   loopback_fifo_empty_i,
				                   tx_fifo_full_i,
				                   tx_fifo_empty_i,
				                   rx_error_i,
				                   tx_error_i,
				                   loopback_mode_i
				                  };
			end
			else if (queued_ff && ft_idle_i && !service_hold_i) begin
				queued_ff <= 1'b0;
			end
		end
	end

	// Drive the two-word status frame once the TX side reaches a safe issue window.
	always @(posedge clk) begin
		if (!rst_n) begin
			active_ff <= 1'b0;
			tx_started_ff <= 1'b0;
			word_is_header_ff <= 1'b0;
			pending_words_ff <= 2'b00;
		end
		else if (soft_clear_i) begin
			active_ff <= 1'b0;
			tx_started_ff <= 1'b0;
			word_is_header_ff <= 1'b0;
			pending_words_ff <= 2'b00;
		end
		else begin
			if (queued_ff && ft_idle_i && !service_hold_i) begin
				active_ff <= 1'b1;
				word_is_header_ff <= 1'b0;
				pending_words_ff <= 2'd2;
				tx_started_ff <= 1'b0;
			end

			if (active_ff && status_pop_i && (pending_words_ff != 2'd0)) begin
				pending_words_ff <= pending_words_ff - 1'b1;
				word_is_header_ff <= (pending_words_ff == 2'd2);
			end

			if (active_ff && (status_send_i || !ft_idle_i))
				tx_started_ff <= 1'b1;

			if (active_ff && tx_started_ff && ft_idle_i && (pending_words_ff == 2'd0)) begin
				active_ff <= 1'b0;
				tx_started_ff <= 1'b0;
				word_is_header_ff <= 1'b0;
				pending_words_ff <= 2'b00;
			end
		end
	end

	assign source_sel_o = source_sel;
	assign source_empty_o = (pending_words_ff == 2'd0);
	assign status_word_o = status_word_mux;
	assign source_change_o = source_sel ^ source_sel_p1_ff;

endmodule
