`timescale 1ns / 1ps

// This project is divided by two frequency domains. Write domain works on GPIO_CLK from input gpio pin (frequency is changeable). 
// Write domain includes modules such as gpio_wrapper, packer8to32, async_fifo(write side) and sram_dp(write side).
// Read domain works on CLK from FT601 (100MHZ). Read domain includes modules such as async_fifo(read side), sram_dp(read side), loopback and ft601_fsm.

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
	output 						RESET_N,	// Active-low reset signal driven to FT601
   input 						TXE_N,		// Trancieve empty signal from FT601
   input 						RXF_N,		// Receive full signal from FT601
   output 						OE_N,		// Output enable signal to FT601
   output 						WR_N,		// Write enable signal to FT601
   output 						RD_N,		// Read enable signal to FT601
	inout [BE_LEN-1:0] 		BE,			// In and out byte enable bus connected to FT601
	inout [DATA_LEN-1:0] 	DATA		// In and out data bus connected to FT601
	 );
	localparam [BE_LEN-1:0] FULL_BE = {BE_LEN{1'b1}};
	
	// Reset and clocks
	wire gpio_clk;
	wire ft_clk_i;
	wire fpga_reset_i;
	wire ft601_reset_n_i;
	wire ft601_reset_n_ft;
	wire gpio_rst_req;
	wire ft_rst_req;
	wire gpio_rst_n_i;
	wire ft_rst_n_i;

	// FT601 wrapper / FSM pins
	wire ft_txe_n_i;
	wire ft_rxf_n_i;
	wire [DATA_LEN-1:0] rx_data;
	wire [DATA_LEN-1:0] tx_data;
	wire [BE_LEN-1:0] rx_be;
	wire [BE_LEN-1:0] tx_be;
	wire fsm_oe_o;
	wire fsm_wr_o;
	wire fsm_rd_o;
	wire fsm_idle_o;
	wire drive_tx;

	// GPIO wrapper and packer
	wire [GPIO_LEN-1:0] gpio_data;
	wire gpio_strob;
	wire packer_valid_o;
	wire [DATA_LEN-1:0] packer_data_o;
	wire [BE_LEN-1:0] packer_keep_o;

	// Normal TX async FIFO and SRAM
	wire [FIFO_RX_LEN-1:0] normal_fifo_wdata;
	wire [FIFO_RX_LEN-1:0] normal_fifo_rdata;
	wire [ADDR_LEN-1:0] normal_fifo_waddr;
	wire [ADDR_LEN-1:0] normal_fifo_raddr;
	wire [FIFO_RX_LEN-1:0] sram_wdata;
	wire [FIFO_RX_LEN-1:0] sram_rdata;
	wire normal_fifo_full;
	wire normal_fifo_empty;
	wire normal_fifo_wen_req;
	wire normal_fifo_wen;
	wire normal_fifo_ren;
	wire tx_fifo_full_ft;

	// Loopback FIFO
	wire [FIFO_RX_LEN-1:0] loopback_fifo_wdata;
	wire [FIFO_RX_LEN-1:0] loopback_fifo_rdata;
	wire loopback_fifo_full;
	wire loopback_fifo_empty;
	wire loopback_fifo_wen;
	wire loopback_fifo_ren;

	// RX stream router
	wire ft_rx_axis_tvalid;
	wire ft_rx_axis_tready;
	wire [DATA_LEN-1:0] ft_rx_axis_tdata;
	wire [BE_LEN-1:0] ft_rx_axis_tkeep;
	wire cmd_event_valid;
	wire [DATA_LEN-1:0] cmd_event_opcode;
	wire service_frame_error_pulse;
	wire loopback_payload_tvalid;
	wire loopback_payload_tready;
	wire [DATA_LEN-1:0] loopback_payload_tdata;
	wire [BE_LEN-1:0] loopback_payload_tkeep;
	wire tx_prefetch_en;

	// Service command decoder and diagnostics
	wire service_frame_error;
	wire loopback_mode_ft;
	wire loopback_mode_gpio;
	wire mode_switch_busy_ft;
	wire mode_switch_busy_gpio;
	wire rx_router_block_ft;
	wire status_req;

	// Status source
	wire status_frame_active;
	wire status_start_ready;
	wire status_payload_block;
	wire normal_source_sel;
	wire loopback_source_sel;
	reg status_payload_hold_ff;
	reg status_txe_low_seen_ff;
	reg tx_payload_accept_ff;

	// Local stream contracts between payload/status sources, the TX arbiter and
	// FT601 adapters. This is a small valid/ready layer, not a full AXI fabric.
	wire normal_axis_tvalid;
	wire normal_axis_tready;
	wire [DATA_LEN-1:0] normal_axis_tdata;
	wire [BE_LEN-1:0] normal_axis_tkeep;
	wire loopback_axis_tvalid;
	wire loopback_axis_tready;
	wire [DATA_LEN-1:0] loopback_axis_tdata;
	wire [BE_LEN-1:0] loopback_axis_tkeep;
	wire status_axis_tvalid;
	wire status_axis_tready;
	wire [DATA_LEN-1:0] status_axis_tdata;
	wire [BE_LEN-1:0] status_axis_tkeep;
	wire tx_axis_tvalid;
	wire tx_axis_tready;
	wire [DATA_LEN-1:0] tx_axis_tdata;
	wire [BE_LEN-1:0] tx_axis_tkeep;

	// Assignings
	assign status_start_ready = fsm_idle_o;
	assign ft601_reset_n_i = ft601_reset_n_ft;
	assign gpio_rst_req = fpga_reset_i;
	assign ft_rst_req = fpga_reset_i;
	assign rx_router_block_ft = mode_switch_busy_ft && fsm_idle_o;
	assign status_payload_block = status_frame_active || status_req || status_payload_hold_ff;
	assign normal_source_sel = !status_payload_block && !loopback_mode_ft;
	assign loopback_source_sel = !status_payload_block && loopback_mode_ft;

	// A status read is a stop-and-wait service transaction on the same FT601 IN
	// endpoint as payload. Keep payload sources blocked until the host-side read
	// phase ends and FT601 deasserts TXE_N, otherwise payload can be appended
	// behind STATUS_MAGIC/status_word and later appear shifted or stale.
	always @(negedge ft_clk_i) begin
		if (!ft_rst_n_i) begin
			status_payload_hold_ff <= 1'b0;
			status_txe_low_seen_ff <= 1'b0;
			tx_payload_accept_ff <= 1'b0;
		end
		else begin
			tx_payload_accept_ff <= !ft_txe_n_i;

			if (status_req || status_frame_active)
				status_payload_hold_ff <= 1'b1;

			if (status_payload_hold_ff && !ft_txe_n_i)
				status_txe_low_seen_ff <= 1'b1;

			if (status_payload_hold_ff && status_txe_low_seen_ff &&
			    ft_txe_n_i && !status_frame_active) begin
				status_payload_hold_ff <= 1'b0;
				status_txe_low_seen_ff <= 1'b0;
			end
		end
	end

	IBUF #(
		.IOSTANDARD("LVCMOS33")
	) ibuf_fpga_reset (
		.I(FPGA_RESET),
		.O(fpga_reset_i)
	);
	
	// FT601 physical I/O wrapper
	ft601_wrapper #(
		.DATA_LEN(DATA_LEN),
		.BE_LEN(BE_LEN)
	) ft601_wrapper (
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
		.ft601_reset_n_i(ft601_reset_n_i),
		.core_rst_n_i(ft_rst_n_i),
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

	// Synchronizers per clock domain
	rst_sync gpio_rst_sync (
		.clk(gpio_clk),
		.arst_i(gpio_rst_req),
		.rst_n_o(gpio_rst_n_i)
	);

	rst_sync ft_rst_sync (
		.clk(ft_clk_i),
		.arst_i(ft_rst_req),
		.rst_n_o(ft_rst_n_i)
	);

	bit_sync #(
		.RESET_VALUE(1'b0)
	) loopback_mode_gpio_sync (
		.clk(gpio_clk),
		.rst_n(gpio_rst_n_i),
		.din(loopback_mode_ft),
		.dout(loopback_mode_gpio)
	);

	bit_sync #(
		.RESET_VALUE(1'b0)
	) mode_switch_busy_gpio_sync (
		.clk(gpio_clk),
		.rst_n(gpio_rst_n_i),
		.din(mode_switch_busy_ft),
		.dout(mode_switch_busy_gpio)
	);

	bit_sync #(
		.RESET_VALUE(1'b0)
	) tx_fifo_full_ft_sync (
		.clk(ft_clk_i),
		.rst_n(ft_rst_n_i),
		.din(normal_fifo_full),
		.dout(tx_fifo_full_ft)
	);

	axis_fifo_read_adapter #(
		.DATA_LEN(DATA_LEN),
		.KEEP_LEN(BE_LEN)
	) normal_fifo_read_adapter (
		.clk(ft_clk_i),
		.rst_n(ft_rst_n_i),
		.enable_i(normal_source_sel && tx_prefetch_en && tx_payload_accept_ff),
		.fifo_data_i(normal_fifo_rdata),
		.fifo_empty_i(normal_fifo_empty),
		.fifo_ren_o(normal_fifo_ren),
		.m_axis_tvalid_o(normal_axis_tvalid),
		.m_axis_tready_i(normal_axis_tready),
		.m_axis_tdata_o(normal_axis_tdata),
		.m_axis_tkeep_o(normal_axis_tkeep)
	);

	axis_fifo_read_adapter #(
		.DATA_LEN(DATA_LEN),
		.KEEP_LEN(BE_LEN)
	) loopback_fifo_read_adapter (
		.clk(ft_clk_i),
		.rst_n(ft_rst_n_i),
		.enable_i(loopback_source_sel && tx_prefetch_en && tx_payload_accept_ff),
		.fifo_data_i(loopback_fifo_rdata),
		.fifo_empty_i(loopback_fifo_empty),
		.fifo_ren_o(loopback_fifo_ren),
		.m_axis_tvalid_o(loopback_axis_tvalid),
		.m_axis_tready_i(loopback_axis_tready),
		.m_axis_tdata_o(loopback_axis_tdata),
		.m_axis_tkeep_o(loopback_axis_tkeep)
	);

	// Explicit TX stream priority: status response, then loopback, then normal payload.
	axis_tx_arbiter #(
		.DATA_LEN(DATA_LEN),
		.BE_LEN(BE_LEN)
	) axis_tx_arbiter (
		.clk(ft_clk_i),
		.rst_n(ft_rst_n_i),
		.status_frame_active_i(status_frame_active),
		.loopback_mode_i(loopback_mode_ft),
		.s_normal_axis_tvalid_i(normal_axis_tvalid),
		.s_normal_axis_tready_o(normal_axis_tready),
		.s_normal_axis_tdata_i(normal_axis_tdata),
		.s_normal_axis_tkeep_i(normal_axis_tkeep),
		.s_loopback_axis_tvalid_i(loopback_axis_tvalid),
		.s_loopback_axis_tready_o(loopback_axis_tready),
		.s_loopback_axis_tdata_i(loopback_axis_tdata),
		.s_loopback_axis_tkeep_i(loopback_axis_tkeep),
		.s_status_axis_tvalid_i(status_axis_tvalid),
		.s_status_axis_tready_o(status_axis_tready),
		.s_status_axis_tdata_i(status_axis_tdata),
		.s_status_axis_tkeep_i(status_axis_tkeep),
		.m_axis_tvalid_o(tx_axis_tvalid),
		.m_axis_tready_i(tx_axis_tready),
		.m_axis_tdata_o(tx_axis_tdata),
		.m_axis_tkeep_o(tx_axis_tkeep)
	);

	// Loopback control
	rx_stream_router #(
		.DATA_LEN(DATA_LEN),
		.BE_LEN(BE_LEN),
		.FIFO_RX_LEN(FIFO_RX_LEN)
	) rx_stream_router (
		.clk(ft_clk_i),
		.rst_n(ft_rst_n_i),
		.block_i(rx_router_block_ft),
		.loopback_mode_i(loopback_mode_ft),
		.rxf_n_i(ft_rxf_n_i),
		.s_axis_tvalid_i(ft_rx_axis_tvalid),
		.s_axis_tready_o(ft_rx_axis_tready),
		.s_axis_tdata_i(ft_rx_axis_tdata),
		.s_axis_tkeep_i(ft_rx_axis_tkeep),
		.cmd_event_valid_o(cmd_event_valid),
		.cmd_event_opcode_o(cmd_event_opcode),
		.service_frame_error_o(service_frame_error_pulse),
		.m_payload_axis_tvalid_o(loopback_payload_tvalid),
		.m_payload_axis_tready_i(loopback_payload_tready),
		.m_payload_axis_tdata_o(loopback_payload_tdata),
		.m_payload_axis_tkeep_o(loopback_payload_tkeep),
		.tx_prefetch_en_o(tx_prefetch_en)
	);

	// Status response control
	status_source #(
		.DATA_LEN(DATA_LEN),
		.BE_LEN(BE_LEN)
	) status_source (
		.clk(ft_clk_i),
		.rst_n(ft_rst_n_i),
		.block_i(mode_switch_busy_ft),
		.start_ready_i(status_start_ready),
		.req_i(status_req),
		.m_axis_tready_i(status_axis_tready),
		.loopback_mode_i(loopback_mode_ft),
		.service_frame_error_i(service_frame_error),
		.tx_fifo_empty_i(normal_fifo_empty),
		.tx_fifo_full_i(tx_fifo_full_ft),
		.loopback_fifo_empty_i(loopback_fifo_empty),
		.loopback_fifo_full_i(loopback_fifo_full),
		.frame_active_o(status_frame_active),
		.m_axis_tvalid_o(status_axis_tvalid),
		.m_axis_tdata_o(status_axis_tdata),
		.m_axis_tkeep_o(status_axis_tkeep)
	);

	// GPIO I/O wrapper
	gpio_wrapper gpio_wrapper(
		.clk_i(GPIO_CLK),
		.strob_i(GPIO_STROB),
		.data_i(GPIO_DATA),
		.data_o(gpio_data),
		.strob_o(gpio_strob),
		.clk_o(gpio_clk)
	);
	
	// Packer 8-bit bus to 32-bit bus
	packer8to32 packer(
		.clk(gpio_clk),
		.rst_n(gpio_rst_n_i),
		.valid_i(gpio_strob),
		.data_i(gpio_data),
		.valid_o(packer_valid_o),
		.data_o(packer_data_o),
		.keep_o(packer_keep_o)
	);
	
	// Normal mode asynchronous FIFO
	async_fifo #(
		.DATA_LEN(FIFO_RX_LEN),
		.DEPTH(FIFO_DEPTH)
	) async_fifo(
		.clk_wr(gpio_clk),
		.clk_rd(ft_clk_i),
		.rst_wr_n(gpio_rst_n_i),
		.rst_rd_n(ft_rst_n_i),
		.wen_i(normal_fifo_wen_req),
		.ren_i(normal_fifo_ren),
		.sram_rdata_i(sram_rdata),
		.data_i(normal_fifo_wdata),
		.data_o(normal_fifo_rdata),
		.sram_wdata_o(sram_wdata),
		.wen_o(normal_fifo_wen),
		.wr_addr_o(normal_fifo_waddr),
		.rd_addr_o(normal_fifo_raddr),
		.full(normal_fifo_full),
		.empty(normal_fifo_empty)
	);
	
	// Asynchronous FIFO SRAM
	sram_dp #(
		.DATA_LEN(FIFO_RX_LEN),
		.DEPTH(FIFO_DEPTH)
	) mem_tx(
		.wr_clk(gpio_clk),
		.rd_clk(ft_clk_i),
		.wen(normal_fifo_wen),
		.wr_addr(normal_fifo_waddr),
		.rd_addr(normal_fifo_raddr),
		.data_i(sram_wdata),
		.data_o(sram_rdata)
	);

	// Loopback mode FIFO
	loopback_fifo #(
		.DATA_LEN(FIFO_RX_LEN),
		.DEPTH(FIFO_DEPTH)
	) loopback_fifo(
		.clk(ft_clk_i),
		.rst_n(ft_rst_n_i),
		.wen_i(loopback_fifo_wen),
		.ren_i(loopback_fifo_ren),
		.data_i(loopback_fifo_wdata),
		.data_o(loopback_fifo_rdata),
		.full(loopback_fifo_full),
		.empty(loopback_fifo_empty)
	);

	// Loopback FIFO write-side AXIS adapter. RX router is ready-aware, so
	// payload valid during FIFO backpressure is normal and not an overflow.
	axis_fifo_write_adapter #(
		.DATA_LEN(DATA_LEN),
		.KEEP_LEN(BE_LEN)
	) loopback_fifo_write_adapter (
		.enable_i(loopback_mode_ft),
		.s_axis_tvalid_i(loopback_payload_tvalid),
		.s_axis_tready_o(loopback_payload_tready),
		.s_axis_tdata_i(loopback_payload_tdata),
		.s_axis_tkeep_i(loopback_payload_tkeep),
		.fifo_full_i(loopback_fifo_full),
		.fifo_wen_o(loopback_fifo_wen),
		.fifo_data_o(loopback_fifo_wdata)
	);

	// PC command decoder
	cmd_decoder #(
		.DATA_LEN(DATA_LEN),
		.BE_LEN(BE_LEN),
		.FIFO_RX_LEN(FIFO_RX_LEN)
	) cmd_decoder(
		.clk(ft_clk_i),
		.rst_n(ft_rst_n_i),
		.cmd_event_valid_i(cmd_event_valid),
		.cmd_event_opcode_i(cmd_event_opcode),
		.idle_i(fsm_idle_o),
		.service_frame_error_i(service_frame_error_pulse),
		.service_frame_error_o(service_frame_error),
		.ft601_reset_n_o(ft601_reset_n_ft),
		.status_req_o(status_req),
		.mode_switch_busy_o(mode_switch_busy_ft),
		.loopback_mode_o(loopback_mode_ft)
	);

	// Normal FIFO write-side AXIS adapter. GPIO ingress has no external ready,
	// so this boundary treats each packed word as a one-cycle valid event.
	axis_fifo_write_adapter #(
		.DATA_LEN(DATA_LEN),
		.KEEP_LEN(BE_LEN)
	) normal_fifo_write_adapter (
		.enable_i(!loopback_mode_gpio && !mode_switch_busy_gpio),
		.s_axis_tvalid_i(packer_valid_o),
		.s_axis_tready_o(),
		.s_axis_tdata_i(packer_data_o),
		.s_axis_tkeep_i(packer_keep_o),
		.fifo_full_i(normal_fifo_full),
		.fifo_wen_o(normal_fifo_wen_req),
		.fifo_data_o(normal_fifo_wdata)
	);

	// FT-domain FSM 
	ft601_fsm ft601_fsm(
		.rst_n(ft_rst_n_i),
		.clk(ft_clk_i),
		.txe_n(ft_txe_n_i),
		.rxf_n(ft_rxf_n_i),
		.s_axis_tvalid_i(tx_axis_tvalid),
		.s_axis_tready_o(tx_axis_tready),
		.s_axis_tdata_i(tx_axis_tdata),
		.s_axis_tkeep_i(tx_axis_tkeep),
		.m_axis_tvalid_o(ft_rx_axis_tvalid),
		.m_axis_tready_i(ft_rx_axis_tready),
		.m_axis_tdata_o(ft_rx_axis_tdata),
		.m_axis_tkeep_o(ft_rx_axis_tkeep),
		.rx_data_i(rx_data),
		.rx_keep_i(rx_be),
		.mode_switch_busy_i(mode_switch_busy_ft),
		.tx_prefetch_en_i(tx_prefetch_en),
		.tx_status_sel_i(status_frame_active),
		.tx_data_o(tx_data),
		.tx_keep_o(tx_be),
		.wr_n(fsm_wr_o),
		.rd_n(fsm_rd_o),
		.oe_n(fsm_oe_o),
		.drive_tx(drive_tx),
		.idle_o(fsm_idle_o)
	);
	
endmodule
