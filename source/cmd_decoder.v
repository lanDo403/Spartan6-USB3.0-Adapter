`timescale 1ns / 1ps

module cmd_decoder #(
	parameter DATA_LEN = 32,
	parameter BE_LEN = 4,
	parameter FIFO_RX_LEN = DATA_LEN + BE_LEN
)(
	input 						clk,
	input 						rst_n,
	input 						cmd_event_valid_i,
	input [DATA_LEN-1:0]    cmd_event_opcode_i,
	input                   idle_i,
	input 						service_frame_error_i,
	output 						service_frame_error_o,
	output                  ft601_reset_n_o,
	output                  status_req_o,
	output                  mode_switch_busy_o,
	output 						loopback_mode_o
    );

	localparam [DATA_LEN-1:0] CMD_CLR_SERVICE_ERROR = 32'h00000001;
	localparam [DATA_LEN-1:0] CMD_SET_LOOPBACK = 32'hA5A50004;
	localparam [DATA_LEN-1:0] CMD_SET_NORMAL = 32'hA5A50005;
	localparam [DATA_LEN-1:0] CMD_GET_STATUS = 32'hA5A50006;
	localparam [DATA_LEN-1:0] CMD_FT601_RESET = 32'hA5A50007;
	localparam [1:0] MODE_IDLE = 2'b00;
	localparam [1:0] MODE_WAIT_IDLE = 2'b01;
	localparam [1:0] MODE_COMMIT = 2'b10;

	reg service_frame_error_ff;
	reg loopback_mode_ff;
	reg [1:0] ft601_reset_pipe_ff;
	reg [1:0] mode_state_ff;
	reg mode_target_ff;

	// Command-event endpoint: rx_stream_router has already consumed
	// CMD_MAGIC + opcode. This block is not an AXI-Stream sink; it only
	// filters known opcodes and applies control side effects.
	wire cmd_known;
	wire set_loopback_cmd;
	wire set_normal_cmd;
	wire get_status_cmd;
	wire ft601_reset_cmd;
	wire mode_switch_cmd;
	wire clr_service_cmd;
	wire mode_switch_busy;

	assign mode_switch_busy = (mode_state_ff != MODE_IDLE);
	assign cmd_known = cmd_event_valid_i && !mode_switch_busy && (
	                  (cmd_event_opcode_i == CMD_CLR_SERVICE_ERROR) ||
	                  (cmd_event_opcode_i == CMD_SET_LOOPBACK) ||
	                  (cmd_event_opcode_i == CMD_SET_NORMAL) ||
	                  (cmd_event_opcode_i == CMD_GET_STATUS) ||
	                  (cmd_event_opcode_i == CMD_FT601_RESET)
	                 );
	assign set_loopback_cmd = cmd_known && (cmd_event_opcode_i == CMD_SET_LOOPBACK);
	assign set_normal_cmd = cmd_known && (cmd_event_opcode_i == CMD_SET_NORMAL);
	assign get_status_cmd = cmd_known && (cmd_event_opcode_i == CMD_GET_STATUS);
	assign ft601_reset_cmd = cmd_known && (cmd_event_opcode_i == CMD_FT601_RESET);
	assign mode_switch_cmd = (set_loopback_cmd && !loopback_mode_ff) ||
	                         (set_normal_cmd && loopback_mode_ff);
	assign clr_service_cmd = cmd_known && (cmd_event_opcode_i == CMD_CLR_SERVICE_ERROR);

	// CMD_FT601_RESET only drives the external FT601 RESET_N pulse.
	always @(negedge clk) begin
		if (!rst_n) begin
			ft601_reset_pipe_ff <= 2'b00;
		end
		else begin
			if (ft601_reset_cmd)
				ft601_reset_pipe_ff <= 2'b11;
			else
				ft601_reset_pipe_ff <= {1'b0, ft601_reset_pipe_ff[1]};
		end
	end

	// Service sticky error tracks malformed service/control frames until explicit recovery.
	always @(negedge clk) begin
		if (!rst_n)
			service_frame_error_ff <= 1'b0;
		else begin
			if (clr_service_cmd)
				service_frame_error_ff <= 1'b0;
			else if (service_frame_error_i)
				service_frame_error_ff <= 1'b1;
		end
	end

	// Mode switch waits for the FT601 datapath to become idle, then commits the new runtime mode.
	always @(negedge clk) begin
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
					if (idle_i) begin
						loopback_mode_ff <= mode_target_ff;
						mode_state_ff <= MODE_COMMIT;
					end
				end

				MODE_COMMIT:
					mode_state_ff <= MODE_IDLE;

				default:
					mode_state_ff <= MODE_IDLE;
			endcase
		end
	end

	assign service_frame_error_o = service_frame_error_ff;
	assign ft601_reset_n_o = !(|ft601_reset_pipe_ff);
	assign status_req_o = get_status_cmd;
	assign mode_switch_busy_o = mode_switch_busy;
	assign loopback_mode_o = loopback_mode_ff;

endmodule
