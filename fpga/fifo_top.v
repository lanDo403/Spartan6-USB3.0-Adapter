`timescale 1ns / 1ps
`include "LVDS.v"
`include "packer8to32.v"
`include "fifo_dualport.v"
`include "sram_dp.v"
`include "fifo_fsm.v"
`include "fifo_rx_ctrl.v"
`include "fifo_tx_ctrl.v"

// This project is divided by two frequency domains. Write domain works on LVDS_CLK from input gpio pin (frequency is changeable). 
// Write domain includes modules such as LVDS, packer8to32, fifo_dualport(write side) and sram_dp(write side).
// Read domain works on CLK from FT601 (100MHZ). Read domain includes modules such as fifo_dualport(read side), sram_dp(read side), loopback and fifo_fsm.

module fifo_top #(
	parameter LVDS_LEN = 8,
	parameter DATA_LEN = 32,
	parameter BE_LEN = 4,
	parameter FIFO_DEPTH = 1024,
	parameter ADDR_LEN = $clog2(FIFO_DEPTH),
	parameter FIFO_RX_LEN = DATA_LEN + BE_LEN
)(
	// LVDS signals from FPGA logic
	input   						LVDS_CLK,
	input  [LVDS_LEN-1:0]	LVDS_DATA,
	input   						LVDS_STROB,	
	input 						FPGA_RESET,
   input 						CLK,		// Clock signal from FT601
   input 						RESET_N,	// Reset signal from FT601	
   input 						TXE_N,	// Trancieve empty signal from FT601
   input 						RXF_N,	//	Receive full signal from FT601
   output 						OE_N,		// Output enable signal to FT601
   output 						WR_N,		// Write enable signal to FT601
   output 						RD_N,		// Read enable signal to FT601
	inout [BE_LEN-1:0] 		BE,		// In and out byte enable bus connected to FT601
   inout [DATA_LEN-1:0] 	DATA		// In and out data bus connected to FT601
	 );

	//-------------------------------------------------------------
	// Wires
	//-------------------------------------------------------------
	
	//-----lvds-----
	wire [LVDS_LEN-1:0] lvds_data; 	// from LVDS module to packer8to32 module
	wire lvds_strob;	// LVDS strobe (valid signal)	
	wire lvds_clk;	// LVDS clock signal in write  
	
	//-----packer-----
	wire packer_valid_o;
	wire [DATA_LEN-1:0]	packer_data_o;
	
	//-----fifo-----
	wire [DATA_LEN-1:0]	fifo_data_i;
	wire [DATA_LEN-1:0]	fifo_data_o;
	wire [ADDR_LEN-1:0] fifo_addr_wr, fifo_addr_rd;
	wire [DATA_LEN-1:0] sram_in, sram_out; // Data to/from SRAM
	wire full_fifo;
	wire empty_fifo;
	wire fifo_wen_o, fifo_ren_o;
	wire tx_fifo_overflow;
	wire tx_fifo_underflow;
	wire packer_wen_i;
	wire tx_fifo_error_i; // Sticky TX-side error collected in CLK domain and synchronized into lvds_clk.
	wire [FIFO_RX_LEN-1:0] fifo_rx_data_i;
	wire [FIFO_RX_LEN-1:0] fifo_rx_data_o;
	wire [ADDR_LEN-1:0] fifo_rx_addr_wr, fifo_rx_addr_rd;
	wire [FIFO_RX_LEN-1:0] sram_rx_in, sram_rx_out; // Data to/from RX SRAM
	wire full_fifo_rx;
	wire empty_fifo_rx;
	wire fifo_rx_wen_o, fifo_rx_ren_o;
	wire rx_fifo_overflow;
	wire rx_fifo_underflow;
	wire fifo_rx_pop; // Internal read request that drains RX FIFO into the command decoder.
	wire rx_fifo_error_i; // Sticky RX-side error reported by the command decoder block.
	wire rx_fifo_rst_a;
	wire rx_fifo_rst_n;
	wire clr_tx_error_tgl; // Toggle-based clear request crossing from CLK domain into lvds_clk domain.
	 
	//-----sram-----
	// ***wire wr_en_sram, rd_en_sram_n;
	// ***wire [ADDR_LEN-1:0] wr_addr_sram, rd_addr_sram;

	//-----fsm-----
	// tx sends data from FPGA to FT601
	// rx recieves data from FT601 to FPGA
	wire [DATA_LEN-1:0] rx_data;
	wire [DATA_LEN-1:0] tx_data;
	wire [BE_LEN-1:0] rx_be;
	wire [BE_LEN-1:0]	tx_be;
	wire oe_n;
	wire wr_n;
	wire rd_n;
	wire drive_tx; // when is active - drives data on DATA bus to FT601
	wire [DATA_LEN-1:0] fsm_data_o; // data from ft601
	wire [BE_LEN-1:0] fsm_be_o; // byte enable from ft601
	wire fifo_pop;	// when is active - fsm is ready to get data from fifo
	wire fifo_append; // when is active - data from ft601 drives to fifo
	
	
	//-------------------------------------------------------------
	// Assignings
	//-------------------------------------------------------------
	assign fifo_data_i = packer_data_o;
	// RX FIFO stores the full FT601 receive word as {BE, DATA}.
	assign fifo_rx_data_i = {fsm_be_o, fsm_data_o};
	assign rx_fifo_rst_n = RESET_N & ~FPGA_RESET;
	assign rx_fifo_rst_a = ~rx_fifo_rst_n;
	assign DATA 	= drive_tx ? tx_data : 32'hzzzzzzzz; // sends data to FT601
	assign rx_data = DATA; // reads DATA from FT601
	assign BE 		= drive_tx ? tx_be : 4'hz; // sends BE to FT601
	assign rx_be 	= BE; // reads BE from FT601
	assign OE_N 	= oe_n;
	assign WR_N 	= wr_n;
	assign RD_N 	= rd_n;
	
	//-------------------------------------------------------------
	// Connection to LVDS module
	//------------------------------------------------------------- 
	LVDS lvds(
		.clk_i(LVDS_CLK),
		.strob_i(LVDS_STROB),
		.data_i(LVDS_DATA),
		.data_o(lvds_data),
		.strob_o(lvds_strob),
		.clk_o(lvds_clk)
	);
	
	//-------------------------------------------------------------
	// Connection to packer8to32 module
	//-------------------------------------------------------------
	packer8to32 packer(
		.clk(lvds_clk),
		.rst_a(FPGA_RESET),
		.valid_i(lvds_strob),
		.data_i(lvds_data),
		.valid_o(packer_valid_o),
		.data_o(packer_data_o)
	);
	
	//-------------------------------------------------------------
	// Connection to FIFO
	//-------------------------------------------------------------
	fifo_dualport #(
		.DATA_LEN(DATA_LEN),
		.DEPTH(FIFO_DEPTH)
	) fifo(
		.clk_wr(lvds_clk),
		.clk_rd(CLK),
		.rst_a(FPGA_RESET),
		.rst_n(RESET_N),
		.wen_i(packer_wen_i),
		.ren_i(fifo_pop), 
		.sram_data_r(sram_out),
		.data_i(fifo_data_i),
		.data_o(fifo_data_o),
		.sram_data_w(sram_in),
		.wen_o(fifo_wen_o),
		.ren_o(fifo_ren_o),
		.wr_addr_o(fifo_addr_wr),
		.rd_addr_o(fifo_addr_rd),
		.full(full_fifo),
		.empty(empty_fifo),
		.overflow(tx_fifo_overflow),
		.underflow(tx_fifo_underflow)
	);
	
	//-------------------------------------------------------------
	// Connection to SRAM
	//-------------------------------------------------------------
	sram_dp #(
		.DATA_LEN(DATA_LEN),
		.DEPTH(FIFO_DEPTH)
	) mem(
		.wr_clk(lvds_clk),
		.rd_clk(CLK),
		.wen(fifo_wen_o),
		.ren(fifo_ren_o),
		.wr_addr(fifo_addr_wr),
		.rd_addr(fifo_addr_rd),
		.data_i(sram_in),
		.data_o(sram_out)
	);

	//-------------------------------------------------------------
	// Connection to RX FIFO
	//-------------------------------------------------------------
	fifo_dualport #(
		.DATA_LEN(FIFO_RX_LEN),
		.DEPTH(FIFO_DEPTH),
		.USE_UNDERFLOW(0)
	) fifo_rx(
		.clk_wr(CLK),
		.clk_rd(CLK),
		.rst_a(rx_fifo_rst_a),
		.rst_n(rx_fifo_rst_n),
		.wen_i(fifo_append),
		.ren_i(fifo_rx_pop), 
		.sram_data_r(sram_rx_out),
		.data_i(fifo_rx_data_i),
		.data_o(fifo_rx_data_o),
		.sram_data_w(sram_rx_in),
		.wen_o(fifo_rx_wen_o),
		.ren_o(fifo_rx_ren_o),
		.wr_addr_o(fifo_rx_addr_wr),
		.rd_addr_o(fifo_rx_addr_rd),
		.full(full_fifo_rx),
		.empty(empty_fifo_rx),
		.overflow(rx_fifo_overflow),
		.underflow(rx_fifo_underflow)
	);

	//-------------------------------------------------------------
	// Connection to RX control
	//-------------------------------------------------------------
	fifo_rx_ctrl #(
		.DATA_LEN(DATA_LEN),
		.BE_LEN(BE_LEN),
		.FIFO_RX_LEN(FIFO_RX_LEN)
	) rx_ctrl(
		.clk(CLK),
		.rst_n(rx_fifo_rst_n),
		.fifo_rx_empty_i(empty_fifo_rx),
		.fifo_rx_ren_i(fifo_rx_ren_o),
		.fifo_rx_data_i(fifo_rx_data_o),
		.tx_fifo_underflow_i(tx_fifo_underflow),
		.rx_fifo_overflow_i(rx_fifo_overflow),
		.rx_fifo_underflow_i(rx_fifo_underflow),
		.fifo_rx_pop_o(fifo_rx_pop),
		.tx_fifo_error_o(tx_fifo_error_i),
		.rx_fifo_error_o(rx_fifo_error_i),
		.clr_tx_error_tgl_o(clr_tx_error_tgl)
	);

	//-------------------------------------------------------------
	// Connection to TX control
	//-------------------------------------------------------------
	fifo_tx_ctrl tx_ctrl(
		.clk(lvds_clk),
		.rst_a(FPGA_RESET),
		.packer_valid_i(packer_valid_o),
		.full_fifo_i(full_fifo),
		.tx_fifo_overflow_i(tx_fifo_overflow),
		.clr_tx_error_tgl_i(clr_tx_error_tgl),
		.tx_fifo_error_i(tx_fifo_error_i),
		.rx_fifo_error_i(rx_fifo_error_i),
		.packer_wen_o(packer_wen_i)
	);

	//-------------------------------------------------------------
	// Connection to RX SRAM
	//-------------------------------------------------------------
	sram_dp #(
		.DATA_LEN(FIFO_RX_LEN),
		.DEPTH(FIFO_DEPTH)
	) mem_rx(
		.wr_clk(CLK),
		.rd_clk(CLK),
		.wen(fifo_rx_wen_o),
		.ren(fifo_rx_ren_o),
		.wr_addr(fifo_rx_addr_wr),
		.rd_addr(fifo_rx_addr_rd),
		.data_i(sram_rx_in),
		.data_o(sram_rx_out)
	);
	
	//-------------------------------------------------------------
	// Connection to FSM 
	//-------------------------------------------------------------
	fifo_fsm fsm(
		.rst_n(RESET_N),
		.clk(CLK),
		.txe_n(TXE_N),
		.rxf_n(RXF_N),
		.data_i(fifo_data_o),
		.rx_data(rx_data),
		.be_i(rx_be),
		.full_fifo(full_fifo_rx),
		.empty_fifo(empty_fifo),
		.data_o(fsm_data_o),
		.tx_data(tx_data),
		.be_o(tx_be),
		.fifo_be(fsm_be_o),
		.wr_n(wr_n),
		.rd_n(rd_n),
		.oe_n(oe_n),
		.drive_tx(drive_tx),
		.fifo_pop(fifo_pop),
		.fifo_append(fifo_append)
	);
	
endmodule
