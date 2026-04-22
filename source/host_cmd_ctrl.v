`timescale 1ns / 1ps

module host_cmd_ctrl #(
	parameter DATA_LEN = 32,
	parameter BE_LEN = 4,
	parameter FIFO_RX_LEN = DATA_LEN + BE_LEN
)(
	input 						clk,
	input 						rst_n,
	input 						rx_word_valid_i,
	input [FIFO_RX_LEN-1:0] rx_word_i,
	input                   ft_idle_i,
	input 						tx_fifo_underflow_i,
	input                   tx_fifo_error_i,
	input 						rx_fifo_overflow_i,
	input 						rx_fifo_underflow_i,
	output 						tx_fifo_error_o,
	output 						rx_fifo_error_o,
	output 						soft_clear_tx_o,
	output 						soft_clear_rx_o,
	output 						soft_clear_ft_state_o,
	output                  status_req_o,
	output                  service_hold_o,
	output 						loopback_mode_o
    );

	localparam [DATA_LEN-1:0] CMD_CLR_TX_ERROR = 32'h00000001;
	localparam [DATA_LEN-1:0] CMD_CLR_RX_ERROR = 32'h00000002;
	localparam [DATA_LEN-1:0] CMD_CLR_ALL_ERROR = 32'h00000003;
	localparam [DATA_LEN-1:0] CMD_SET_LOOPBACK = 32'hA5A50004;
	localparam [DATA_LEN-1:0] CMD_SET_NORMAL = 32'hA5A50005;
	localparam [DATA_LEN-1:0] CMD_GET_STATUS = 32'hA5A50006;
	localparam [DATA_LEN-1:0] CMD_MAGIC = 32'hA55A5AA5;
	localparam [1:0] MODE_IDLE = 2'b00;
	localparam [1:0] MODE_WAIT_IDLE = 2'b01;
	localparam [1:0] MODE_CLEAR = 2'b10;
	localparam [1:0] MODE_COMMIT = 2'b11;

	reg tx_fifo_error_ff;
	reg rx_fifo_error_ff;
	reg loopback_mode_ff;
	reg parser_wait_opcode_ff;
	reg tx_error_arm_ff;
	reg [1:0] tx_recover_pipe_ff;
	reg [1:0] rx_recover_pipe_ff;
	reg [1:0] mode_state_ff;
	reg mode_target_ff;

	wire full_word;
	wire cmd_magic;
	(* KEEP = "TRUE" *) wire cmd_valid;
	wire set_loopback_cmd;
	wire set_normal_cmd;
	wire get_status_cmd;
	wire opcode_word_valid;
	wire clear_all_cmd;
	wire mode_switch_cmd;
	wire clear_tx_cmd;
	wire clear_rx_cmd;
	wire tx_recover_active;
	wire rx_recover_active;
	wire mode_switch_active;
	wire tx_error_clear;
	wire rx_error_clear;
	wire mode_clear_start;

	assign full_word = (rx_word_i[FIFO_RX_LEN-1:DATA_LEN] == {BE_LEN{1'b1}});
	assign cmd_magic = rx_word_valid_i && full_word && (rx_word_i[DATA_LEN-1:0] == CMD_MAGIC);
	assign opcode_word_valid = rx_word_valid_i && full_word && parser_wait_opcode_ff;
	assign mode_switch_active = (mode_state_ff != MODE_IDLE);
	assign clear_all_cmd = opcode_word_valid && !mode_switch_active && (rx_word_i[DATA_LEN-1:0] == CMD_CLR_ALL_ERROR);
	assign cmd_valid = opcode_word_valid && !mode_switch_active && (
	                  (rx_word_i[DATA_LEN-1:0] == CMD_CLR_TX_ERROR) ||
	                  (rx_word_i[DATA_LEN-1:0] == CMD_CLR_RX_ERROR) ||
	                  (rx_word_i[DATA_LEN-1:0] == CMD_CLR_ALL_ERROR) ||
	                  (rx_word_i[DATA_LEN-1:0] == CMD_SET_LOOPBACK) ||
	                  (rx_word_i[DATA_LEN-1:0] == CMD_SET_NORMAL) ||
	                  (rx_word_i[DATA_LEN-1:0] == CMD_GET_STATUS)
	                 );
	assign set_loopback_cmd = opcode_word_valid && !mode_switch_active && (rx_word_i[DATA_LEN-1:0] == CMD_SET_LOOPBACK);
	assign set_normal_cmd = opcode_word_valid && !mode_switch_active && (rx_word_i[DATA_LEN-1:0] == CMD_SET_NORMAL);
	assign get_status_cmd = opcode_word_valid && !mode_switch_active && (rx_word_i[DATA_LEN-1:0] == CMD_GET_STATUS);
	assign mode_switch_cmd = (set_loopback_cmd && !loopback_mode_ff) ||
	                         (set_normal_cmd && loopback_mode_ff);
	assign clear_tx_cmd = (opcode_word_valid && !mode_switch_active && (rx_word_i[DATA_LEN-1:0] == CMD_CLR_TX_ERROR)) ||
	                      clear_all_cmd;
	assign clear_rx_cmd = (opcode_word_valid && !mode_switch_active && (rx_word_i[DATA_LEN-1:0] == CMD_CLR_RX_ERROR)) ||
	                      clear_all_cmd;
	assign tx_recover_active = |tx_recover_pipe_ff;
	assign rx_recover_active = |rx_recover_pipe_ff;
	assign tx_error_clear = tx_recover_active || clear_tx_cmd || mode_switch_active || mode_switch_cmd;
	assign rx_error_clear = rx_recover_active || clear_rx_cmd || mode_switch_active || mode_switch_cmd;
	assign mode_clear_start = (mode_state_ff == MODE_WAIT_IDLE) && ft_idle_i;
	assign tx_fifo_error_o = tx_fifo_error_ff;
	assign rx_fifo_error_o = rx_fifo_error_ff;
	assign soft_clear_tx_o = tx_recover_pipe_ff[1];
	assign soft_clear_rx_o = rx_recover_pipe_ff[1];
	assign soft_clear_ft_state_o = tx_recover_pipe_ff[1] || rx_recover_pipe_ff[1];
	assign status_req_o = get_status_cmd;
	assign service_hold_o = mode_switch_active;
	assign loopback_mode_o = loopback_mode_ff;

	// Parse FT601 service frames as two full words: CMD_MAGIC followed by opcode.
	always @(posedge clk) begin
		if (!rst_n) begin
			parser_wait_opcode_ff <= 1'b0;
		end
		else begin
			if (parser_wait_opcode_ff) begin
				if (rx_word_valid_i && full_word)
					parser_wait_opcode_ff <= 1'b0;
			end
			else if (cmd_magic)
				parser_wait_opcode_ff <= 1'b1;
		end
	end

	// Generate two-cycle recovery pulses for TX and RX/local FT-domain state.
	always @(posedge clk) begin
		if (!rst_n) begin
			tx_recover_pipe_ff <= 2'b00;
			rx_recover_pipe_ff <= 2'b00;
		end
		else begin
			if (mode_clear_start || clear_tx_cmd)
				tx_recover_pipe_ff <= 2'b11;
			else
				tx_recover_pipe_ff <= {1'b0, tx_recover_pipe_ff[1]};

			if (mode_clear_start || clear_rx_cmd)
				rx_recover_pipe_ff <= 2'b11;
			else
				rx_recover_pipe_ff <= {1'b0, rx_recover_pipe_ff[1]};
		end
	end

	// TX sticky error combines FT-domain underflow detection with the synchronized GPIO write-side fault.
	always @(posedge clk) begin
		if (!rst_n) begin
			tx_fifo_error_ff <= 1'b0;
			tx_error_arm_ff <= 1'b1;
		end
		else begin
			if (tx_error_clear) begin
				tx_fifo_error_ff <= 1'b0;
				tx_error_arm_ff <= 1'b0;
			end
			else begin
				if (!tx_fifo_error_i)
					tx_error_arm_ff <= 1'b1;
				if (tx_error_arm_ff && (tx_fifo_underflow_i || tx_fifo_error_i))
					tx_fifo_error_ff <= 1'b1;
			end
		end
	end

	// RX sticky error tracks loopback FIFO faults until explicit recovery.
	always @(posedge clk) begin
		if (!rst_n)
			rx_fifo_error_ff <= 1'b0;
		else begin
			if (rx_error_clear)
				rx_fifo_error_ff <= 1'b0;
			else if (rx_fifo_overflow_i || rx_fifo_underflow_i)
				rx_fifo_error_ff <= 1'b1;
		end
	end

	// Mode switch waits for FT idle, launches local recovery, then commits the new runtime mode.
	always @(posedge clk) begin
		if (!rst_n) begin
			loopback_mode_ff <= 1'b0;
			mode_state_ff <= MODE_IDLE;
			mode_target_ff <= 1'b0;
		end
		else begin
			case (mode_state_ff)
				MODE_IDLE: begin
					if (mode_switch_cmd) begin
						mode_target_ff <= set_loopback_cmd;
						mode_state_ff <= MODE_WAIT_IDLE;
					end
				end

				MODE_WAIT_IDLE: begin
					if (ft_idle_i)
						mode_state_ff <= MODE_CLEAR;
				end

				MODE_CLEAR: begin
					if (!tx_recover_active && !rx_recover_active) begin
						loopback_mode_ff <= mode_target_ff;
						mode_state_ff <= MODE_COMMIT;
					end
				end

				MODE_COMMIT:
					mode_state_ff <= MODE_IDLE;
			endcase
		end
	end

endmodule
