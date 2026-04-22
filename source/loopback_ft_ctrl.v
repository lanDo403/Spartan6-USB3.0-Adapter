`timescale 1ns / 1ps

module loopback_ft_ctrl #(
	parameter FIFO_RX_LEN = 36,
	parameter BE_LEN = 4
)(
	input                     clk,
	input                     rst_n,
	input                     soft_clear_i,
	input                     service_hold_i,
	input                     loopback_mode_i,
	input                     ft_rxf_n_i,
	input                     fifo_append_i,
	input  [FIFO_RX_LEN-1:0]  rx_word_i,
	output                    ft_rx_word_valid_o,
	output [FIFO_RX_LEN-1:0]  ft_rx_word_o,
	output                    loopback_fifo_wen_o,
	output [FIFO_RX_LEN-1:0]  loopback_fifo_word_o,
	output                    tx_prefetch_en_o,
	output                    tx_source_change_o
);

	reg loopback_mode_p1_ff;
	reg loopback_payload_en_ff;
	reg service_wait_opcode_ff;
	reg ft_rx_word_valid_ff;
	reg [FIFO_RX_LEN-1:0] ft_rx_word_ff;

	wire full_word;
	wire cmd_magic;
	wire service_frame_word;
	wire loopback_rx_busy;

	localparam [FIFO_RX_LEN-BE_LEN-1:0] CMD_MAGIC = 32'hA55A5AA5;

	assign full_word = (ft_rx_word_ff[FIFO_RX_LEN-1:FIFO_RX_LEN-BE_LEN] == {BE_LEN{1'b1}});
	assign cmd_magic = full_word && (ft_rx_word_ff[FIFO_RX_LEN-BE_LEN-1:0] == CMD_MAGIC);
	assign service_frame_word = ft_rx_word_valid_ff && (
	                           (!service_wait_opcode_ff && cmd_magic) ||
	                           ( service_wait_opcode_ff && full_word)
	                          );

	// Keep the previous loopback mode to detect the first RX phase after entering loopback.
	always @(posedge clk) begin
		if (!rst_n) begin
			loopback_mode_p1_ff <= 1'b0;
		end
		else if (soft_clear_i) begin
			loopback_mode_p1_ff <= loopback_mode_i;
		end
		else
			loopback_mode_p1_ff <= loopback_mode_i;
	end

	// Capture RX words after FIFO append so command decode and loopback buffering use the same registered sample.
	always @(posedge clk) begin
		if (!rst_n) begin
			ft_rx_word_valid_ff <= 1'b0;
			ft_rx_word_ff <= {FIFO_RX_LEN{1'b0}};
		end
		else if (soft_clear_i) begin
			ft_rx_word_valid_ff <= 1'b0;
			ft_rx_word_ff <= {FIFO_RX_LEN{1'b0}};
		end
		else begin
			ft_rx_word_valid_ff <= fifo_append_i && !service_hold_i;

			if (service_hold_i)
				ft_rx_word_ff <= {FIFO_RX_LEN{1'b0}};
			else if (fifo_append_i)
				ft_rx_word_ff <= rx_word_i;

		end
	end

	// Enable loopback payload storage only after the initial command frame has been consumed.
	always @(posedge clk) begin
		if (!rst_n) begin
			loopback_payload_en_ff <= 1'b0;
		end
		else if (soft_clear_i) begin
			loopback_payload_en_ff <= 1'b0;
		end
		else begin
			if (service_hold_i || !loopback_mode_i)
				loopback_payload_en_ff <= 1'b0;
			else if (loopback_mode_p1_ff && !ft_rxf_n_i)
				loopback_payload_en_ff <= 1'b1;
		end
	end

	// Service-frame parser consumes CMD_MAGIC first and the opcode on the next full RX word.
	always @(posedge clk) begin
		if (!rst_n) begin
			service_wait_opcode_ff <= 1'b0;
		end
		else if (soft_clear_i) begin
			service_wait_opcode_ff <= 1'b0;
		end
		else begin
			if (service_hold_i || !loopback_mode_i)
				service_wait_opcode_ff <= 1'b0;
			else if (ft_rx_word_valid_ff) begin
				if (service_wait_opcode_ff) begin
					if (full_word)
						service_wait_opcode_ff <= 1'b0;
				end
				else if (cmd_magic)
					service_wait_opcode_ff <= 1'b1;
			end
		end
	end

	assign ft_rx_word_valid_o   = ft_rx_word_valid_ff;
	assign ft_rx_word_o         = ft_rx_word_ff;
	assign loopback_fifo_wen_o  = ft_rx_word_valid_ff && loopback_payload_en_ff && !service_frame_word && !service_hold_i;
	assign loopback_fifo_word_o = ft_rx_word_ff;
	assign loopback_rx_busy     = !ft_rxf_n_i || fifo_append_i || ft_rx_word_valid_ff;
	assign tx_prefetch_en_o     = !service_hold_i && (!loopback_mode_i || !loopback_rx_busy);
	assign tx_source_change_o   = !service_hold_i && ((loopback_mode_i ^ loopback_mode_p1_ff) ||
	                             (loopback_mode_i && loopback_rx_busy));

endmodule
