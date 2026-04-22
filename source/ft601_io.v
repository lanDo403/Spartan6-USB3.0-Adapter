`timescale 1ns / 1ps

module ft601_io #(
	parameter DATA_LEN = 32,
	parameter BE_LEN   = 4
)(
	// FT601 physical pins
	input                     CLK,
	input                     RESET_N, // Active-low reset input from FT601
	input                     TXE_N,
	input                     RXF_N,
	output                    OE_N,
	output                    WR_N,
	output                    RD_N,
	inout  [BE_LEN-1:0]       BE,
	inout  [DATA_LEN-1:0]     DATA,

	// Internal core-side signals
	output                    clk_o,
	output                    reset_n_o, // Buffered active-low FT601 reset
	output                    txe_n_o,
	output                    rxf_n_o,
	output [BE_LEN-1:0]       rx_be_o,
	output [DATA_LEN-1:0]     rx_data_o,

	input                     oe_n_i,
	input                     wr_n_i,
	input                     rd_n_i,
	input                     drive_tx_i,
	input  [BE_LEN-1:0]       tx_be_i,
	input  [DATA_LEN-1:0]     tx_data_i
);

	wire txe_n_ibuf;
	wire rxf_n_ibuf;
	(* IOB = "TRUE" *) reg txe_n_ff;
	(* IOB = "TRUE" *) reg rxf_n_ff;

	// Buffered inputs from FT601
	IBUFG #(
		.IOSTANDARD("LVCMOS33")
	) ibufg_clk (
		.I(CLK),
		.O(clk_o)
	);

	IBUF #(
		.IOSTANDARD("LVCMOS33")
	) ibuf_reset_n (
		.I(RESET_N),
		.O(reset_n_o)
	);

	IBUF #(
		.IOSTANDARD("LVCMOS33")
	) ibuf_txe_n (
		.I(TXE_N),
		.O(txe_n_ibuf)
	);

	IBUF #(
		.IOSTANDARD("LVCMOS33")
	) ibuf_rxf_n (
		.I(RXF_N),
		.O(rxf_n_ibuf)
	);

	always @(posedge clk_o or negedge reset_n_o) begin
		if (!reset_n_o) begin
			txe_n_ff <= 1'b1;
			rxf_n_ff <= 1'b1;
		end
		else begin
			txe_n_ff <= txe_n_ibuf;
			rxf_n_ff <= rxf_n_ibuf;
		end
	end

	assign txe_n_o = txe_n_ff;
	assign rxf_n_o = rxf_n_ff;

	// Buffered FT601 control outputs
	OBUF #(
		.IOSTANDARD("LVCMOS33"),
		.DRIVE(8),
		.SLEW("FAST")
	) obuf_oe_n (
		.I(oe_n_i),
		.O(OE_N)
	);

	OBUF #(
		.IOSTANDARD("LVCMOS33"),
		.DRIVE(8),
		.SLEW("FAST")
	) obuf_wr_n (
		.I(wr_n_i),
		.O(WR_N)
	);

	OBUF #(
		.IOSTANDARD("LVCMOS33"),
		.DRIVE(8),
		.SLEW("FAST")
	) obuf_rd_n (
		.I(rd_n_i),
		.O(RD_N)
	);

	// Bidirectional FT601 buses
	genvar i;
	generate
		for (i = 0; i < DATA_LEN; i = i + 1) begin : gen_data_iobuf
			IOBUF #(
				.IOSTANDARD("LVCMOS33"),
				.DRIVE(8),
				.SLEW("FAST")
			) iobuf_data (
				.I(tx_data_i[i]),
				.O(rx_data_o[i]),
				.IO(DATA[i]),
				.T(~drive_tx_i)
			);
		end
	endgenerate

	genvar j;
	generate
		for (j = 0; j < BE_LEN; j = j + 1) begin : gen_be_iobuf
			IOBUF #(
				.IOSTANDARD("LVCMOS33"),
				.DRIVE(8),
				.SLEW("FAST")
			) iobuf_be (
				.I(tx_be_i[j]),
				.O(rx_be_o[j]),
				.IO(BE[j]),
				.T(~drive_tx_i)
			);
		end
	endgenerate

endmodule
