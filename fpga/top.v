`timescale 1ns / 1ps
`include "get_gpio.v"
`include "packer8to32.v"
`include "fifo_dualport.v"
`include "fifo_singleclock.v"
`include "sram_dualport.v"
`include "fifo_fsm.v"
`include "fifo_rx_ctrl.v"
`include "fifo_tx_ctrl.v"
`include "ft601_io.v"
`include "rst_sync.v"

// This project is divided by two frequency domains. Write domain works on GPIO_CLK from input gpio pin (frequency is changeable). 
// Write domain includes modules such as get_gpio, packer8to32, fifo_dualport(write side) and sram_dp(write side).
// Read domain works on CLK from FT601 (100MHZ). Read domain includes modules such as fifo_dualport(read side), sram_dp(read side), loopback and fifo_fsm.

module top #(
	parameter GPIO_LEN = 8,
	parameter DATA_LEN = 32,
	parameter BE_LEN = 4,
	parameter FIFO_DEPTH = 8192,
	parameter ADDR_LEN = $clog2(FIFO_DEPTH),
	parameter FIFO_RX_LEN = DATA_LEN + BE_LEN
)(
	// GPIO signals from FPGA logic
	input   						GPIO_CLK,
	input  [GPIO_LEN-1:0]	GPIO_DATA,
	input   						GPIO_STROB,	
	input 						FPGA_RESET,
   input 						CLK,		// Clock signal from FT601
   input 						RESET_N,	// Active-low reset signal from FT601	
   input 						TXE_N,		// Trancieve empty signal from FT601
   input 						RXF_N,		// Receive full signal from FT601
   output 						OE_N,		// Output enable signal to FT601
   output 						WR_N,		// Write enable signal to FT601
   output 						RD_N,		// Read enable signal to FT601
	inout [BE_LEN-1:0] 		BE,			// In and out byte enable bus connected to FT601
   inout [DATA_LEN-1:0] 	DATA		// In and out data bus connected to FT601
	 );

	localparam [DATA_LEN-1:0] CMD_SET_LOOPBACK = 32'hA5A50004;

	//-------------------------------------------------------------
	// Wires
	//-------------------------------------------------------------
	
	//-----gpio-----
	wire [GPIO_LEN-1:0] gpio_data; 	// from GPIO module to packer8to32 module
	wire gpio_strob;	// GPIO strobe (valid signal)	
	wire gpio_clk;	// GPIO clock signal in write  
	
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
	wire packer_wen_raw;
	wire tx_fifo_error_i; // Sticky TX-side error collected in CLK domain and synchronized into lvds_clk.
	wire [DATA_LEN-1:0] fsm_tx_fifo_data_i; // Selected TX source for FT601: normal TX FIFO or loopback FIFO.
	wire [BE_LEN-1:0]   fsm_tx_fifo_be_i; // Selected TX byte-enable source.
	wire                fsm_tx_fifo_empty_i; // Empty flag for the currently selected TX source.
	wire                fifo_tx_pop_i; // Pop command routed to normal TX FIFO.
	wire [FIFO_RX_LEN-1:0] loopback_fifo_data_i;
	wire [FIFO_RX_LEN-1:0] loopback_fifo_data_o;
	wire full_loopback_fifo;
	wire empty_loopback_fifo;
	wire rx_fifo_overflow;
	wire rx_fifo_underflow;
	wire rx_fifo_error_i; // Sticky RX-side error reported by the command decoder block.
	wire clr_tx_error_tgl; // Toggle-based clear request crossing from CLK domain into lvds_clk domain.
	wire loopback_mode_ft; // Runtime loopback mode latched in FT clock domain by command decoder.
	wire fsm_rx_full_i; // Selected receive-side backpressure source for the FSM.
	wire gpio_rst_n_i; // Active-low synchronous reset for the GPIO/write clock domain.
	wire ft_rst_n_i; // Active-low synchronous reset for the FT601/read clock domain.
	wire fpga_reset_i; // Buffered FPGA reset input.
	wire ft_reset_i; // Active-high reset request derived from FT601 RESET_N.
	wire ft_rst_req_w; // Combined asynchronous reset request that is synchronized into FT clock domain.
	reg  loopback_mode_gpio_meta_ff;
	reg  loopback_mode_gpio_ff;
	reg  loopback_mode_ft_p1_ff;
	reg  loopback_capture_armed_ff;
	reg  rx_stream_valid_ff;
	reg  [FIFO_RX_LEN-1:0] rx_stream_word_ff;
	wire loopback_fifo_wen_i;
	wire loopback_rx_busy_w;
	wire tx_prefetch_en_w;
	wire tx_src_change_w;
	 
	//-----sram-----
	// ***wire wr_en_sram, rd_en_sram_n;
	// ***wire [ADDR_LEN-1:0] wr_addr_sram, rd_addr_sram;

	//-----fsm-----
	// tx sends data from FPGA to FT601
	// rx recieves data from FT601 to FPGA
	wire ft_clk_i; // Buffered FT601 clock used by the full read domain.
	wire ft_reset_n_i; // Buffered active-low FT601 RESET_N.
	wire ft_txe_n_i; // Buffered FT601 TXE# sampled inside FPGA.
	wire ft_rxf_n_i; // Buffered FT601 RXF# sampled inside FPGA.
	wire [DATA_LEN-1:0] rx_data;
	wire [DATA_LEN-1:0] tx_data;
	wire [BE_LEN-1:0] rx_be;
	wire [BE_LEN-1:0]	tx_be;
	wire fsm_oe_o;
	wire fsm_wr_o;
	wire fsm_rd_o;
	wire drive_tx; // when is active - drives data on DATA bus to FT601
	wire [DATA_LEN-1:0] fsm_data_o; // data from ft601
	wire [BE_LEN-1:0] fsm_be_o; // byte enable from ft601
	wire fifo_pop;	// when is active - fsm is ready to get data from fifo
	wire fifo_append; // when is active - data from ft601 drives to fifo
	
	
	//-------------------------------------------------------------
	// Assignings
	//-------------------------------------------------------------
	assign fifo_data_i = packer_data_o;
	// TX source is selected at runtime:
	// normal mode uses the GPIO/TX FIFO, loopback mode reuses words captured into the FT-domain loopback FIFO.
	assign fsm_tx_fifo_data_i  = loopback_mode_ft ? loopback_fifo_data_o[DATA_LEN-1:0] : fifo_data_o;
	assign fsm_tx_fifo_be_i    = loopback_mode_ft ? loopback_fifo_data_o[FIFO_RX_LEN-1:DATA_LEN] : {BE_LEN{1'b1}};
	assign fsm_tx_fifo_empty_i = loopback_mode_ft ? empty_loopback_fifo : empty_fifo;
	assign fifo_tx_pop_i       = loopback_mode_ft ? 1'b0 : fifo_pop;
	assign packer_wen_i        = packer_wen_raw && !loopback_mode_gpio_ff;
	assign loopback_fifo_data_i = {fsm_be_o, fsm_data_o};
	assign fsm_rx_full_i = loopback_mode_ft ? full_loopback_fifo : 1'b0;
	assign loopback_fifo_wen_i =
		rx_stream_valid_ff &&
		loopback_capture_armed_ff;
	assign loopback_rx_busy_w = !ft_rxf_n_i || fifo_append || rx_stream_valid_ff;
	assign tx_prefetch_en_w = !loopback_mode_ft || !loopback_rx_busy_w;
	assign tx_src_change_w = (loopback_mode_ft ^ loopback_mode_ft_p1_ff) ||
	                        (loopback_mode_ft && loopback_rx_busy_w);
	assign ft_reset_i = ~ft_reset_n_i;
	assign ft_rst_req_w = fpga_reset_i | ft_reset_i;

	//-------------------------------------------------------------
	// Buffered FPGA reset input
	//-------------------------------------------------------------
	IBUF #(
		.IOSTANDARD("LVCMOS33")
	) ibuf_fpga_reset (
		.I(FPGA_RESET),
		.O(fpga_reset_i)
	);
	
	//-------------------------------------------------------------
	// FT601 physical I/O wrapper
	//-------------------------------------------------------------
	ft601_io #(
		.DATA_LEN(DATA_LEN),
		.BE_LEN(BE_LEN)
	) ft_io (
		.CLK(CLK),
		.RESET_N(RESET_N),
		.TXE_N(TXE_N),
		.RXF_N(RXF_N),
		.OE_N(OE_N),
		.WR_N(WR_N),
		.RD_N(RD_N),
		.BE(BE),
		.DATA(DATA),
		.clk_o(ft_clk_i),
		.reset_n_o(ft_reset_n_i),
		.txe_n_o(ft_txe_n_i),
		.rxf_n_o(ft_rxf_n_i),
		.rx_be_o(rx_be),
		.rx_data_o(rx_data),
		.oe_n_i(fsm_oe_o),
		.wr_n_i(fsm_wr_o),
		.rd_n_i(fsm_rd_o),
		.drive_tx_i(drive_tx),
		.tx_be_i(tx_be),
		.tx_data_i(tx_data)
	);

	//-------------------------------------------------------------
	// Reset synchronizers per clock domain
	//-------------------------------------------------------------
	rst_sync gpio_rst_sync (
		.clk(gpio_clk),
		.arst_i(fpga_reset_i),
		.rst_n_o(gpio_rst_n_i)
	);

	rst_sync ft_rst_sync (
		.clk(ft_clk_i),
		.arst_i(ft_rst_req_w),
		.rst_n_o(ft_rst_n_i)
	);

	always @(posedge gpio_clk) begin
		if (!gpio_rst_n_i) begin
			loopback_mode_gpio_meta_ff <= 1'b0;
			loopback_mode_gpio_ff <= 1'b0;
		end
		else begin
			loopback_mode_gpio_meta_ff <= loopback_mode_ft;
			loopback_mode_gpio_ff <= loopback_mode_gpio_meta_ff;
		end
	end

	always @(posedge ft_clk_i) begin
		if (!ft_rst_n_i) begin
			loopback_mode_ft_p1_ff <= 1'b0;
			loopback_capture_armed_ff <= 1'b0;
			rx_stream_valid_ff <= 1'b0;
			rx_stream_word_ff <= {FIFO_RX_LEN{1'b0}};
		end
		else begin
			loopback_mode_ft_p1_ff <= loopback_mode_ft;
			if (!loopback_mode_ft)
				loopback_capture_armed_ff <= 1'b0;
			else if (loopback_mode_ft_p1_ff && !ft_rxf_n_i)
				loopback_capture_armed_ff <= 1'b1;
			rx_stream_valid_ff <= fifo_append;
			if (fifo_append)
				rx_stream_word_ff <= loopback_fifo_data_i;
		end
	end

	//-------------------------------------------------------------
	// Connection to get_gpio module
	//------------------------------------------------------------- 
	get_gpio gpio(
		.clk_i(GPIO_CLK),
		.strob_i(GPIO_STROB),
		.data_i(GPIO_DATA),
		.data_o(gpio_data),
		.strob_o(gpio_strob),
		.clk_o(gpio_clk)
	);
	
	//-------------------------------------------------------------
	// Connection to packer8to32 
	//-------------------------------------------------------------
	packer8to32 packer(
		.clk(gpio_clk),
		.rst_n(gpio_rst_n_i),
		.valid_i(gpio_strob),
		.data_i(gpio_data),
		.valid_o(packer_valid_o),
		.data_o(packer_data_o)
	);
	
	//-------------------------------------------------------------
	// Connection to FIFO
	//-------------------------------------------------------------
	fifo_dualport #(
		.DATA_LEN(DATA_LEN),
		.DEPTH(FIFO_DEPTH)
	) fifo_tx(
		.clk_wr(gpio_clk),
		.clk_rd(ft_clk_i),
		.rst_wr_n(gpio_rst_n_i),
		.rst_rd_n(ft_rst_n_i),
		.wen_i(packer_wen_i),
		.ren_i(fifo_tx_pop_i), 
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
	) mem_tx(
		.wr_clk(gpio_clk),
		.rd_clk(ft_clk_i),
		.wen(fifo_wen_o),
		.ren(fifo_ren_o),
		.wr_addr(fifo_addr_wr),
		.rd_addr(fifo_addr_rd),
		.data_i(sram_in),
		.data_o(sram_out)
	);

	//-------------------------------------------------------------
	// FT-domain loopback FIFO
	//-------------------------------------------------------------
	fifo_singleclock #(
		.DATA_LEN(FIFO_RX_LEN),
		.DEPTH(FIFO_DEPTH)
	) loopback_fifo(
		.clk(ft_clk_i),
		.rst_n(ft_rst_n_i),
		.wen_i(loopback_fifo_wen_i),
		.ren_i(fifo_pop && loopback_mode_ft),
		.data_i(rx_stream_word_ff),
		.data_o(loopback_fifo_data_o),
		.full(full_loopback_fifo),
		.empty(empty_loopback_fifo),
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
		.clk(ft_clk_i),
		.rst_n(ft_rst_n_i),
		.rx_word_valid_i(rx_stream_valid_ff),
		.rx_word_i(rx_stream_word_ff),
		.tx_fifo_underflow_i(tx_fifo_underflow),
		.rx_fifo_overflow_i(rx_fifo_overflow),
		.rx_fifo_underflow_i(rx_fifo_underflow),
		.tx_fifo_error_o(tx_fifo_error_i),
		.rx_fifo_error_o(rx_fifo_error_i),
		.clr_tx_error_tgl_o(clr_tx_error_tgl),
		.loopback_mode_o(loopback_mode_ft)
	);

	//-------------------------------------------------------------
	// Connection to TX control
	//-------------------------------------------------------------
	fifo_tx_ctrl tx_ctrl(
		.clk(gpio_clk),
		.rst_n(gpio_rst_n_i),
		.packer_valid_i(packer_valid_o),
		.full_fifo_i(full_fifo),
		.tx_fifo_overflow_i(tx_fifo_overflow),
		.clr_tx_error_tgl_i(clr_tx_error_tgl),
		.tx_fifo_error_i(tx_fifo_error_i),
		.rx_fifo_error_i(rx_fifo_error_i),
		.packer_wen_o(packer_wen_raw)
	);

	//-------------------------------------------------------------
	// Connection to FSM 
	//-------------------------------------------------------------
	fifo_fsm fsm(
		.rst_n(ft_rst_n_i),
		.clk(ft_clk_i),
		.txe_n(ft_txe_n_i),
		.rxf_n(ft_rxf_n_i),
		.data_i(fsm_tx_fifo_data_i),
		.tx_be_i(fsm_tx_fifo_be_i),
		.rx_data(rx_data),
		.be_i(rx_be),
		.full_fifo(fsm_rx_full_i),
		.empty_fifo(fsm_tx_fifo_empty_i),
		.tx_clear_i(tx_src_change_w),
		.tx_prefetch_en_i(tx_prefetch_en_w),
		.data_o(fsm_data_o),
		.tx_data(tx_data),
		.be_o(tx_be),
		.fifo_be(fsm_be_o),
		.wr_n(fsm_wr_o),
		.rd_n(fsm_rd_o),
		.oe_n(fsm_oe_o),
		.drive_tx(drive_tx),
		.fifo_pop(fifo_pop),
		.fifo_append(fifo_append)
	);
	
endmodule
