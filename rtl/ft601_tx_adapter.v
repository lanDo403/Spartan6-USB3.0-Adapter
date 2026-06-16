`timescale 1ns / 1ps

module ft601_tx_adapter #(
	parameter DATA_LEN = 32,
	parameter BE_LEN   = 4
)(
	input                    clk_i,
	input                    rst_n_i,
	input                    txe_n_i,
	input                    arb_phase_i,
	input                    prefetch_phase_i,
	input                    burst_phase_i,
	input                    bus_wr_hs_i,
	input                    s_axis_tvalid_i,
	input  [DATA_LEN-1:0]    s_axis_tdata_i,
	input  [BE_LEN-1:0]      s_axis_tkeep_i,
	output                   s_axis_tready_o,
	output                   bus_valid_o,
	output                   idle_o,
	output [DATA_LEN-1:0]    bus_data_o,
	output [BE_LEN-1:0]      bus_keep_o,
	output                   wr_n_o,
	output                   bus_drive_o
);

	reg [DATA_LEN-1:0] out_data_ff;
	reg [DATA_LEN-1:0] buf_data_ff;
	reg [BE_LEN-1:0]   out_keep_ff;
	reg [BE_LEN-1:0]   buf_keep_ff;
	reg out_valid_ff;
	reg buf_valid_ff;
	reg tx_accept_en_ff;
	reg bus_drive_ff;

	reg [DATA_LEN-1:0] out_data_next;
	reg [DATA_LEN-1:0] buf_data_next;
	reg [BE_LEN-1:0]   out_keep_next;
	reg [BE_LEN-1:0]   buf_keep_next;
	reg out_valid_next;
	reg buf_valid_next;

	wire bus_wr_hs;
	wire bus_wr_req;
	wire tx_accept_en;
	wire buf_ready;
	wire s_axis_hs;
	wire [1:0] buf_used;

	assign bus_wr_hs = bus_wr_hs_i && out_valid_ff;
	assign bus_wr_req = !txe_n_i && out_valid_ff;
	assign tx_accept_en = !txe_n_i;
	assign buf_used = {1'b0, out_valid_ff} +
	                       {1'b0, buf_valid_ff};
	assign buf_ready = (buf_used < 2'd2);
	assign s_axis_hs = s_axis_tvalid_i && s_axis_tready_o;

	// One output word plus one buffered word are enough for continuous FT601 TX bursts.
	always @(*) begin
		out_data_next = out_data_ff;
		out_keep_next = out_keep_ff;
		buf_data_next = buf_data_ff;
		buf_keep_next = buf_keep_ff;
		out_valid_next = out_valid_ff;
		buf_valid_next = buf_valid_ff;

		if (bus_wr_hs) begin
			if (buf_valid_ff) begin
				out_data_next = buf_data_ff;
				out_keep_next = buf_keep_ff;
				out_valid_next = 1'b1;
				buf_valid_next = 1'b0;
			end
			else begin
				out_valid_next = 1'b0;
			end
		end

		if (s_axis_hs) begin
			if (!out_valid_next) begin
				out_data_next = s_axis_tdata_i;
				out_keep_next = s_axis_tkeep_i;
				out_valid_next = 1'b1;
			end
			else if (!buf_valid_next) begin
				buf_data_next = s_axis_tdata_i;
				buf_keep_next = s_axis_tkeep_i;
				buf_valid_next = 1'b1;
			end
		end
	end

	always @(negedge clk_i) begin
		if (!rst_n_i) begin
			out_data_ff <= {DATA_LEN{1'b0}};
			buf_data_ff <= {DATA_LEN{1'b0}};
			out_keep_ff <= {BE_LEN{1'b0}};
			buf_keep_ff <= {BE_LEN{1'b0}};
			out_valid_ff <= 1'b0;
			buf_valid_ff <= 1'b0;
			tx_accept_en_ff <= 1'b0;
		end
		else begin
			out_data_ff <= out_data_next;
			buf_data_ff <= buf_data_next;
			out_keep_ff <= out_keep_next;
			buf_keep_ff <= buf_keep_next;
			out_valid_ff <= out_valid_next;
			buf_valid_ff <= buf_valid_next;
			tx_accept_en_ff <= tx_accept_en;
		end
	end

	always @(negedge clk_i) begin
		if (!rst_n_i)
			bus_drive_ff <= 1'b0;
		else begin
			bus_drive_ff <= 1'b0;
			if (arb_phase_i) begin
				if (bus_wr_req)
					bus_drive_ff <= 1'b1;
			end
			else if (prefetch_phase_i || burst_phase_i) begin
				if (out_valid_ff)
					bus_drive_ff <= 1'b1;
			end
		end
	end

	assign s_axis_tready_o = tx_accept_en_ff && buf_ready;
	assign bus_valid_o = out_valid_ff;
	assign idle_o = !out_valid_ff && !buf_valid_ff;
	assign bus_data_o = out_data_ff;
	assign bus_keep_o = out_keep_ff;
	assign wr_n_o = !bus_wr_hs;
	assign bus_drive_o = bus_drive_ff;

endmodule
