`timescale 1ns / 1ps
`include "tb_pkg.sv"
`include "tb_axis_if.sv"
`include "tb_ft601_if.sv"
`include "axis_tx_arbiter.v"
`include "bit_sync.v"
`include "async_fifo.v"
`include "ft601_rx_adapter.v"
`include "ft601_tx_adapter.v"
`include "ft601_fsm.v"
`include "loopback_fifo.v"
`include "ft601_wrapper.v"
`include "gpio_wrapper.v"
`include "cmd_decoder.v"
`include "rx_stream_router.v"
`include "packer8to32.v"
`include "rst_sync.v"
`include "sram_dualport.v"
`include "status_source.v"
`include "service_status_policy.v"
`include "axis_fifo_read_adapter.v"
`include "axis_fifo_write_adapter.v"
`include "top.v"

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNUSEDPARAM */
module IBUFG #(parameter IOSTANDARD="LVCMOS33") (
   output wire O,
   input  wire I
);
   assign O = I;
endmodule
module IBUF #(parameter IOSTANDARD="LVCMOS33") (
   output wire O,
   input  wire I
);
   assign O = I;
endmodule

module OBUF #(parameter DRIVE=12, parameter IOSTANDARD="LVCMOS33", parameter SLEW="SLOW") (
   input  wire I,
   output wire O
);
   assign O = I;
endmodule

module IOBUF #(parameter DRIVE=12, parameter IOSTANDARD="LVCMOS33", parameter SLEW="SLOW") (
   input  wire I,
   output wire O,
   inout  wire IO,
   input  wire T
);
   assign IO = T ? 1'bz : I;
   assign O  = IO;
endmodule
/* verilator lint_on UNUSEDPARAM */
/* verilator lint_on DECLFILENAME */

module testbench;
   import tb_pkg::*;
   localparam int TB_POSEDGE_SAMPLE_DELAY = tb_pkg::TB_POSEDGE_SAMPLE_DELAY;

   // External clocks and top-level pins controlled directly by the testbench.
   logic                gpio_clk;
   logic                ft_clk;
   logic                gpio_strob;
   logic                fpga_reset;
   logic                ft_reset_n;
   logic [GPIO_LEN-1:0] gpio_data;
   logic                ft_txe_n;
   logic                ft_rxf_n;

   // Host-side FT601 bus model used while the DUT reads from RXF_N/DATA/BE.
   logic                host_drive_en;
   logic [DATA_LEN-1:0] host_data_drv;
   logic [BE_LEN-1:0]   host_be_drv;

   // FT601 pins and shared bus observed on the DUT side.
   logic                ft_oe_n;
   logic                ft_wr_n;
   logic                ft_rd_n;
   wire [DATA_LEN-1:0]  ft_data_bus;
   wire [BE_LEN-1:0]    ft_be_bus;
   logic                status_tx_hold;

   // Byte-level stimulus loaded by the GPIO driver.
   logic [7:0] byte_seq_p [0:TOTAL_WORDS-1];

   tb_ft601_if #(
      .DATA_LEN(DATA_LEN),
      .BE_LEN(BE_LEN)
   ) ft601_mon();

   tb_axis_if #(
      .DATA_LEN(DATA_LEN),
      .BE_LEN(BE_LEN)
   ) ft_rx_axis_mon();

   tb_axis_if #(
      .DATA_LEN(DATA_LEN),
      .BE_LEN(BE_LEN)
   ) normal_axis_mon();

   tb_axis_if #(
      .DATA_LEN(DATA_LEN),
      .BE_LEN(BE_LEN)
   ) loopback_payload_axis_mon();

   tb_axis_if #(
      .DATA_LEN(DATA_LEN),
      .BE_LEN(BE_LEN)
   ) loopback_axis_mon();

   tb_axis_if #(
      .DATA_LEN(DATA_LEN),
      .BE_LEN(BE_LEN)
   ) status_axis_mon();

   tb_axis_if #(
      .DATA_LEN(DATA_LEN),
      .BE_LEN(BE_LEN)
   ) tx_axis_mon();

   `include "tb_scoreboard.svh"
   `include "tb_runtime.svh"
   `include "tb_coverage.svh"
   `include "tb_monitors.svh"

   // The host may drive the shared FT bus only while the DUT has granted FT601 read direction.
   assign ft_data_bus = (host_drive_en && !ft_oe_n) ? host_data_drv : {DATA_LEN{1'bz}};
   assign ft_be_bus   = (host_drive_en && !ft_oe_n) ? host_be_drv   : {BE_LEN{1'bz}};

   always #10  gpio_clk = ~gpio_clk;   // 50 MHz GPIO clock
   always #5   ft_clk   = ~ft_clk;     // 100 MHz FT601 clock

   top #(
      .GPIO_LEN(GPIO_LEN),
      .DATA_LEN(DATA_LEN),
      .BE_LEN(BE_LEN),
      .FIFO_DEPTH(FIFO_DEPTH)
   ) dut (
      .GPIO_CLK(gpio_clk),
      .GPIO_DATA(gpio_data),
      .GPIO_STROB(gpio_strob),
      .FPGA_RESET(fpga_reset),
      .CLK(ft_clk),
      .RESET_N(ft_reset_n),
      .TXE_N(ft_txe_n),
      .RXF_N(ft_rxf_n),
      .OE_N(ft_oe_n),
      .WR_N(ft_wr_n),
      .RD_N(ft_rd_n),
      .BE(ft_be_bus),
      .DATA(ft_data_bus)
   );

   assign ft601_mon.clk     = ft_clk;
   assign ft601_mon.reset_n = ft_reset_n;
   assign ft601_mon.txe_n   = ft_txe_n;
   assign ft601_mon.rxf_n   = ft_rxf_n;
   assign ft601_mon.oe_n    = ft_oe_n;
   assign ft601_mon.wr_n    = ft_wr_n;
   assign ft601_mon.rd_n    = ft_rd_n;
   assign ft601_mon.data    = ft_data_bus;
   assign ft601_mon.be      = ft_be_bus;
   assign ft601_mon.data_t  = dut.ft601_wrapper.data_t_o_ff;
   assign ft601_mon.be_t    = dut.ft601_wrapper.be_t_o_ff;

   assign ft_rx_axis_mon.clk   = ft_clk;
   assign ft_rx_axis_mon.rst_n = ft_reset_n;
   assign ft_rx_axis_mon.valid = dut.ft_rx_axis_tvalid;
   assign ft_rx_axis_mon.ready = dut.ft_rx_axis_tready;
   assign ft_rx_axis_mon.data  = dut.ft_rx_axis_tdata;
   assign ft_rx_axis_mon.keep  = dut.ft_rx_axis_tkeep;

   assign normal_axis_mon.clk   = ft_clk;
   assign normal_axis_mon.rst_n = ft_reset_n;
   assign normal_axis_mon.valid = dut.normal_axis_tvalid;
   assign normal_axis_mon.ready = dut.normal_axis_tready;
   assign normal_axis_mon.data  = dut.normal_axis_tdata;
   assign normal_axis_mon.keep  = dut.normal_axis_tkeep;

   assign loopback_payload_axis_mon.clk   = ft_clk;
   assign loopback_payload_axis_mon.rst_n = ft_reset_n;
   assign loopback_payload_axis_mon.valid = dut.loopback_payload_tvalid;
   assign loopback_payload_axis_mon.ready = dut.loopback_payload_tready;
   assign loopback_payload_axis_mon.data  = dut.loopback_payload_tdata;
   assign loopback_payload_axis_mon.keep  = dut.loopback_payload_tkeep;

   assign loopback_axis_mon.clk   = ft_clk;
   assign loopback_axis_mon.rst_n = ft_reset_n;
   assign loopback_axis_mon.valid = dut.loopback_axis_tvalid;
   assign loopback_axis_mon.ready = dut.loopback_axis_tready;
   assign loopback_axis_mon.data  = dut.loopback_axis_tdata;
   assign loopback_axis_mon.keep  = dut.loopback_axis_tkeep;

   assign status_axis_mon.clk   = ft_clk;
   assign status_axis_mon.rst_n = ft_reset_n;
   assign status_axis_mon.valid = dut.status_axis_tvalid;
   assign status_axis_mon.ready = dut.status_axis_tready;
   assign status_axis_mon.data  = dut.status_axis_tdata;
   assign status_axis_mon.keep  = dut.status_axis_tkeep;

   assign tx_axis_mon.clk   = ft_clk;
   assign tx_axis_mon.rst_n = ft_reset_n;
   assign tx_axis_mon.valid = dut.tx_axis_tvalid;
   assign tx_axis_mon.ready = dut.tx_axis_tready;
   assign tx_axis_mon.data  = dut.tx_axis_tdata;
   assign tx_axis_mon.keep  = dut.tx_axis_tkeep;

   assign status_tx_hold = dut.status_frame_active ||
                           dut.service_status_policy.status_payload_hold_ff;

   // Deterministic testbench power-up state for all drivers, counters, and capture arrays.
   initial begin
      gpio_clk      = 1'b0;
      ft_clk        = 1'b0;
      gpio_strob    = 1'b0;
      fpga_reset    = 1'b1;
      gpio_data     = {GPIO_LEN{1'b0}};
      ft_txe_n      = 1'b1;
      ft_rxf_n      = 1'b1;
      host_drive_en = 1'b0;
      host_data_drv = {DATA_LEN{1'b0}};
      host_be_drv   = {BE_LEN{1'b0}};
      runtime_powerup_init();
      coverage_powerup_init();
      scoreboard_powerup_init();
      monitor_powerup_init();
   end

   // Applies FPGA_RESET, checks synchronized release in both domains, and verifies FT pins stay idle.
   task tb_reset;
      integer n;
      integer gpio_release_cycles;
      integer ft_release_cycles;
      begin
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Applying reset requests");
         rx_payload_check_en = 1'b0;
         tx_stream_only_mode = 1'b1;
         @(negedge gpio_clk);
         gpio_strob    = 1'b0;
         gpio_data     = {GPIO_LEN{1'b0}};
         ft_txe_n      = 1'b1;
         ft_rxf_n      = 1'b1;
         host_drive_en = 1'b0;
         host_data_drv = {DATA_LEN{1'b0}};
         host_be_drv   = {BE_LEN{1'b0}};
         fpga_reset    = 1'b1;
         tb_cov_set_normal_mode();

         #1;
         if (ft_reset_n !== 1'b1)
            fail("RESET_N output must remain high during FPGA_RESET; FT601 reset is command-driven");
         if (dut.gpio_rst_n_i !== 1'b0)
            fail("gpio_rst_n_i must assert low immediately after FPGA_RESET");
         if (dut.ft_rst_n_i !== 1'b0)
            fail("ft_rst_n_i must assert low immediately after FPGA_RESET");

         for (n = 0; n < 4; n = n + 1)
            @(posedge gpio_clk);
         for (n = 0; n < 4; n = n + 1)
            @(posedge ft_clk);

         if (ft_wr_n !== 1'b1)
            fail("WR_N must stay inactive during reset");
         if (ft_rd_n !== 1'b1)
            fail("RD_N must stay inactive during reset");
         if (ft_oe_n !== 1'b1)
            fail("OE_N must stay inactive during reset");
         if (dut.drive_tx !== 1'b0)
            fail("drive_tx must stay low during reset");

         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Releasing reset requests");
         fpga_reset = 1'b0;

         #1;
         if (ft_reset_n !== 1'b1)
            fail("RESET_N output must stay high after FPGA_RESET is inactive");
         if (dut.gpio_rst_n_i !== 1'b0)
            fail("gpio_rst_n_i must remain low until synchronized release");
         if (dut.ft_rst_n_i !== 1'b0)
            fail("ft_rst_n_i must remain low until synchronized release");

         gpio_release_cycles = 0;
         while ((dut.gpio_rst_n_i !== 1'b1) && (gpio_release_cycles < 4)) begin
            @(posedge gpio_clk);
            #1;
            gpio_release_cycles = gpio_release_cycles + 1;
         end
         if (dut.gpio_rst_n_i !== 1'b1)
            fail("gpio_rst_n_i did not release within four gpio clocks");

         ft_release_cycles = 0;
         while ((dut.ft_rst_n_i !== 1'b1) && (ft_release_cycles < 4)) begin
            @(posedge ft_clk);
            #1;
            ft_release_cycles = ft_release_cycles + 1;
         end
         if (dut.ft_rst_n_i !== 1'b1)
            fail("ft_rst_n_i did not release within four FT clocks");

         for (n = 0; n < 2; n = n + 1)
            @(posedge gpio_clk);
         for (n = 0; n < 2; n = n + 1)
            @(posedge ft_clk);

         #1;
         if (ft_wr_n !== 1'b1)
            fail("WR_N must stay inactive after reset release");
         if (ft_rd_n !== 1'b1)
            fail("RD_N must stay inactive after reset release");
         if (ft_oe_n !== 1'b1)
            fail("OE_N must stay inactive after reset release");
         if (dut.loopback_mode_ft !== 1'b0)
            fail("loopback_mode_ft must release from FPGA_RESET in normal mode");
         tb_cov_mark_reset_normal_mode();

         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Reset release observed after %0d gpio clocks and %0d FT clocks", gpio_release_cycles, ft_release_cycles);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Reset sequence passed");
      end
   endtask

   `include "tb_gpio_driver.svh"
   `include "tb_ft601_driver.svh"

   `include "tb_service_helpers.svh"

   // FT601 reset is command-driven and must be verified separately from FPGA_RESET.
   task expect_ft601_reset_pulse_2clks;
      integer timeout;
      integer low_cycles;
      begin
         timeout = 0;
         low_cycles = 0;

         while ((ft_reset_n !== 1'b0) && (timeout < 64)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;
            timeout = timeout + 1;
         end
         if (ft_reset_n !== 1'b0)
            fail("CMD_FT601_RESET did not assert RESET_N low");

         while (ft_reset_n === 1'b0) begin
            low_cycles = low_cycles + 1;
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;
            if (low_cycles > 4)
               fail("CMD_FT601_RESET held RESET_N low for too long");
         end

         if (low_cycles !== 2)
            fail("CMD_FT601_RESET must assert RESET_N low for exactly two FT clocks");
      end
   endtask

   `include "scenarios/main.svh"
   `include "scenarios/requirements_ft601.svh"
   `include "scenarios/requirements_payload.svh"
   `include "scenarios/requirements_control.svh"

   task run_directed_requirement_scenarios;
      begin
         run_ft601_turnaround_rx_priority();
         run_ft601_rxf_boundary();
         run_long_gapped_loopback_payload();
         run_status_window_with_payload();
         run_mode_switch_waits_idle();
         run_router_demux_backpressure();
         run_arbiter_priority();
      end
   endtask

   // Select the full regression unless a category entrypoint overrides it.
`ifndef TB_REGRESSION_FULL
`ifndef TB_REGRESSION_MAIN
`ifndef TB_REGRESSION_REQUIREMENTS
`define TB_REGRESSION_FULL
`endif
`endif
`endif

   // Regression order: public behavior first. Directed requirement scenarios are added separately.
   initial begin
      if (TB_VERBOSE_SCENARIO)
         $display("INFO: Testbench start. Universal bitstream mode");
      load_vectors();
      build_expected_words();

`ifdef TB_REGRESSION_MAIN
      run_reset_boot_normal();
      run_normal_path();
      run_loopback_path();
      run_service_control();
`elsif TB_REGRESSION_REQUIREMENTS
      run_reset_boot_normal();
      run_normal_path();
      run_loopback_path();
      run_service_control();
      run_directed_requirement_scenarios();
`else
      run_reset_boot_normal();
      run_normal_path();
      run_loopback_path();
      run_service_control();
      run_directed_requirement_scenarios();
`endif

      tb_cov_check_requirements();
      tb_finish_regression();
   end
   // Optional waveform dump for post-mortem inspection.
   initial begin
      $dumpfile("testbench.vcd");
      $dumpvars(0, testbench);
   end
endmodule
