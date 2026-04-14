`timescale 1ns / 1ps

module fifo_rx_ctrl #(
	parameter DATA_LEN = 32,
	parameter BE_LEN = 4,
	parameter FIFO_RX_LEN = DATA_LEN + BE_LEN
)(
	input 						clk,
	input 						rst_n,
	input 						rx_word_valid_i,
	input [FIFO_RX_LEN-1:0] rx_word_i,
	input 						tx_fifo_underflow_i,
	input 						rx_fifo_overflow_i,
	input 						rx_fifo_underflow_i,
	output 						tx_fifo_error_o,
	output 						rx_fifo_error_o,
	output 						clr_tx_error_tgl_o,
	output 						loopback_mode_o
    );

	localparam [DATA_LEN-1:0] CMD_CLR_TX_ERROR = 32'h00000001;
	localparam [DATA_LEN-1:0] CMD_CLR_RX_ERROR = 32'h00000002;
	localparam [DATA_LEN-1:0] CMD_CLR_ALL_ERROR = 32'h00000003;
	localparam [DATA_LEN-1:0] CMD_SET_LOOPBACK = 32'hA5A50004;

	reg tx_fifo_error_ff;
	reg rx_fifo_error_ff;
	reg clr_tx_error_tgl_ff;
	reg loopback_mode_ff;

	wire be_all_ones_w;
	wire cmd_valid_w;
	wire set_loopback_cmd_w;

	assign be_all_ones_w = (rx_word_i[FIFO_RX_LEN-1:DATA_LEN] == {BE_LEN{1'b1}});
	assign cmd_valid_w = rx_word_valid_i && !loopback_mode_ff && be_all_ones_w;
	assign set_loopback_cmd_w = cmd_valid_w && (rx_word_i[DATA_LEN-1:0] == CMD_SET_LOOPBACK);
	assign tx_fifo_error_o = tx_fifo_error_ff;
	assign rx_fifo_error_o = rx_fifo_error_ff;
	// Toggle is synchronized into gpio_clk domain and converted there to a clear pulse.
	assign clr_tx_error_tgl_o = clr_tx_error_tgl_ff;
	assign loopback_mode_o = loopback_mode_ff;

	always @(posedge clk) begin
		if (!rst_n) begin
			tx_fifo_error_ff <= 1'b0;
			rx_fifo_error_ff <= 1'b0;
			clr_tx_error_tgl_ff <= 1'b0;
			loopback_mode_ff <= 1'b0;
		end
		else begin
			if (tx_fifo_underflow_i)
				tx_fifo_error_ff <= 1'b1;
			if (rx_fifo_overflow_i || rx_fifo_underflow_i)
				rx_fifo_error_ff <= 1'b1;
			if (set_loopback_cmd_w)
				loopback_mode_ff <= 1'b1;
			if (cmd_valid_w) begin
				case (rx_word_i[DATA_LEN-1:0])
					CMD_CLR_TX_ERROR: begin
						tx_fifo_error_ff <= 1'b0;
						clr_tx_error_tgl_ff <= ~clr_tx_error_tgl_ff;
					end
					CMD_CLR_RX_ERROR: rx_fifo_error_ff <= 1'b0;
					CMD_CLR_ALL_ERROR: begin
						tx_fifo_error_ff <= 1'b0;
						rx_fifo_error_ff <= 1'b0;
						clr_tx_error_tgl_ff <= ~clr_tx_error_tgl_ff;
					end
					CMD_SET_LOOPBACK: ;
				endcase
			end
		end
	end

endmodule
