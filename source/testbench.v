`timescale 1ns / 1ps
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

   localparam integer TOTAL_WORDS = 3402;
   localparam integer PAUSE_LEN   = 16;

   localparam integer GPIO_LEN    = 8;
   localparam integer DATA_LEN    = 32;
   localparam integer BE_LEN      = 4;
   localparam integer FIFO_RX_LEN = DATA_LEN + BE_LEN;
   localparam integer FIFO_DEPTH  = 8192;
   localparam integer MAX_WORDS   = 1200;
   localparam [DATA_LEN-1:0] CMD_MAGIC = 32'hA55A5AA5;
   localparam [DATA_LEN-1:0] STATUS_MAGIC = 32'h5AA55AA5;
   localparam [DATA_LEN-1:0] CMD_CLR_SERVICE_ERROR = 32'h00000001;
   localparam [DATA_LEN-1:0] CMD_SET_LOOPBACK = 32'hA5A50004;
   localparam [DATA_LEN-1:0] CMD_SET_NORMAL = 32'hA5A50005;
   localparam [DATA_LEN-1:0] CMD_GET_STATUS = 32'hA5A50006;
   localparam [DATA_LEN-1:0] CMD_FT601_RESET = 32'hA5A50007;
   localparam [BE_LEN-1:0]   FULL_BE = {BE_LEN{1'b1}};
   localparam integer        TX_CAPTURE_WORDS_MAX = 16;
   localparam                TB_VERBOSE_STREAM = 1'b0;
   localparam                TB_VERBOSE_COMMAND = 1'b0;
   localparam                TB_VERBOSE_SCENARIO = 1'b0;
   localparam integer        TB_POSEDGE_SAMPLE_DELAY = 2;
   localparam [5:0]          FSM_ARB = 6'b000001;

   reg                  gpio_clk;
   reg                  ft_clk;
   reg                  gpio_strob;
   reg                  fpga_reset;
   wire                 ft_reset_n;
   reg  [GPIO_LEN-1:0]  gpio_data;
   reg                  ft_txe_n;
   reg                  ft_rxf_n;

   reg                  host_drive_en;
   reg  [DATA_LEN-1:0]  host_data_drv;
   reg  [BE_LEN-1:0]    host_be_drv;

   wire                 ft_oe_n;
   wire                 ft_wr_n;
   wire                 ft_rd_n;
   wire [DATA_LEN-1:0]  ft_data_bus;
   wire [BE_LEN-1:0]    ft_be_bus;
   wire                 status_tx_hold;

   reg [7:0]  byte_seq_p [0:TOTAL_WORDS-1];
   reg [31:0] exp_words  [0:MAX_WORDS-1];
   reg [BE_LEN-1:0] exp_be [0:MAX_WORDS-1];

   integer exp_words_n;
   integer tx_words_n;
   integer rx_words_n;
   integer rx_active_cycles_n;
   integer oe_active_cycles_n;
   reg     rx_burst_seen;
   reg     tx_burst_seen;
   reg     tx_payload_burst_seen;
   integer ft_rx_axis_hs_n;
   integer loopback_fifo_wen_n;
   integer loopback_fifo_ren_n;
   integer tx_axis_hs_n;
   reg     prev_ft_oe_n;
   reg     prev_ft_rd_n;
   reg     prev_ft_wr_n;
   reg     prev_ft_txe_n_neg;
   reg     prev_ft_rxf_n;
   reg     rx_expect_rd_after_oe;
   reg     rx_expect_release_after_rxf;
   integer cmd_valid_pulses_n;
   integer cmd_event_pulses_n;
   reg     rx_payload_check_en;
   reg     tx_stream_only_mode;
   integer tx_total_words_n;
   reg [DATA_LEN-1:0] tx_captured_words [0:TX_CAPTURE_WORDS_MAX-1];
   reg [BE_LEN-1:0]   tx_captured_be    [0:TX_CAPTURE_WORDS_MAX-1];
   reg                 loopback_fifo_wen_pre;
   reg [FIFO_RX_LEN-1:0] loopback_fifo_wdata_pre;
   reg                 prev_ft_rx_axis_stall;
   reg [DATA_LEN-1:0]  prev_ft_rx_axis_tdata;
   reg [BE_LEN-1:0]    prev_ft_rx_axis_tkeep;
   reg                 prev_loopback_payload_axis_stall;
   reg [DATA_LEN-1:0]  prev_loopback_payload_axis_tdata;
   reg [BE_LEN-1:0]    prev_loopback_payload_axis_tkeep;
   reg                 prev_normal_axis_stall;
   reg [DATA_LEN-1:0]  prev_normal_axis_tdata;
   reg [BE_LEN-1:0]    prev_normal_axis_tkeep;
   reg                 prev_loopback_axis_stall;
   reg [DATA_LEN-1:0]  prev_loopback_axis_tdata;
   reg [BE_LEN-1:0]    prev_loopback_axis_tkeep;
   reg                 prev_status_axis_stall;
   reg [DATA_LEN-1:0]  prev_status_axis_tdata;
   reg [BE_LEN-1:0]    prev_status_axis_tkeep;
   reg                 prev_tx_axis_stall;
   reg [DATA_LEN-1:0]  prev_tx_axis_tdata;
   reg [BE_LEN-1:0]    prev_tx_axis_tkeep;
   reg                 allow_status_preempt_drop;
   reg                 prev_status_tx_hold;

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

   assign status_tx_hold = dut.status_frame_active ||
                           dut.axis_tx_arbiter.status_frame_busy_ff;

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
      exp_words_n   = 0;
      tx_words_n    = 0;
      rx_words_n    = 0;
      rx_active_cycles_n = 0;
      oe_active_cycles_n = 0;
      rx_burst_seen = 1'b0;
      tx_burst_seen = 1'b0;
      tx_payload_burst_seen = 1'b0;
      prev_ft_oe_n  = 1'b1;
      prev_ft_rd_n  = 1'b1;
      prev_ft_wr_n  = 1'b1;
      prev_ft_txe_n_neg = 1'b1;
      prev_ft_rxf_n = 1'b1;
      rx_expect_rd_after_oe      = 1'b0;
      rx_expect_release_after_rxf = 1'b0;
      cmd_valid_pulses_n = 0;
      cmd_event_pulses_n = 0;
      rx_payload_check_en = 1'b0;
      tx_stream_only_mode = 1'b0;
      tx_total_words_n = 0;
      prev_loopback_payload_axis_stall = 1'b0;
      prev_loopback_payload_axis_tdata = {DATA_LEN{1'b0}};
      prev_loopback_payload_axis_tkeep = {BE_LEN{1'b0}};
      prev_normal_axis_stall = 1'b0;
      prev_normal_axis_tdata = {DATA_LEN{1'b0}};
      prev_normal_axis_tkeep = {BE_LEN{1'b0}};
      prev_loopback_axis_stall = 1'b0;
      prev_loopback_axis_tdata = {DATA_LEN{1'b0}};
      prev_loopback_axis_tkeep = {BE_LEN{1'b0}};
      prev_status_axis_stall = 1'b0;
      prev_status_axis_tdata = {DATA_LEN{1'b0}};
      prev_status_axis_tkeep = {BE_LEN{1'b0}};
      prev_tx_axis_stall = 1'b0;
      prev_tx_axis_tdata = {DATA_LEN{1'b0}};
      prev_tx_axis_tkeep = {BE_LEN{1'b0}};
      allow_status_preempt_drop = 1'b0;
      prev_status_tx_hold = 1'b0;
      for (integer cap_i = 0; cap_i < TX_CAPTURE_WORDS_MAX; cap_i = cap_i + 1) begin
         tx_captured_words[cap_i] = {DATA_LEN{1'b0}};
         tx_captured_be[cap_i] = {BE_LEN{1'b0}};
      end
   end

   task fail(input [1023:0] msg);
      begin
         $display("ERROR: %0s", msg);
         $finish;
      end
   endtask

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

         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Reset release observed after %0d gpio clocks and %0d FT clocks", gpio_release_cycles, ft_release_cycles);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Reset sequence passed");
      end
   endtask

   task load_vectors;
      integer fd_p;
      integer i;
      begin
         fd_p = $fopen("data_p", "r");
         if (fd_p == 0)
            fd_p = $fopen("source/data_p", "r");
         if (fd_p == 0)
            fail("cannot open data_p");
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Loading stimulus bytes from data_p");

         for (i = 0; i < TOTAL_WORDS; i = i + 1) begin
            if ($fscanf(fd_p, "%h\n", byte_seq_p[i]) != 1)
               fail("cannot read byte from data_p");
         end

         $fclose(fd_p);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Stimulus file loaded");
      end
   endtask

   task is_pause_template_at(
      input  integer idx,
      output reg     is_pause
   );
      integer t;
      reg [7:0] expected;
      begin
         is_pause = 1'b1;

         if (idx + PAUSE_LEN > TOTAL_WORDS)
            is_pause = 1'b0;
         else begin
            for (t = 0; t < PAUSE_LEN; t = t + 1) begin
               expected = 8'h00;
               if ((t % 4) == 0)
                  expected = 8'hFF;
               if (byte_seq_p[idx + t] !== expected)
                  is_pause = 1'b0;
            end
         end
      end
   endtask

   task append_expected_packer_cycle;
      input [GPIO_LEN-1:0] data_i;
      input                strobe_i;
      inout [1:0]          cnt;
      inout [DATA_LEN-1:0] data_shift;
      inout [BE_LEN-1:0]   keep_shift;

      reg [GPIO_LEN-1:0]   byte_w;
      reg [DATA_LEN-1:0]   data_next;
      reg [BE_LEN-1:0]     keep_next;
      begin
         byte_w = strobe_i ? data_i : {GPIO_LEN{1'b0}};
         data_next = {byte_w, data_shift[DATA_LEN-1:GPIO_LEN]};
         keep_next = {strobe_i, keep_shift[BE_LEN-1:1]};

         if (cnt == 2'd0) begin
            if (strobe_i) begin
               data_shift = {data_i, {(DATA_LEN-GPIO_LEN){1'b0}}};
               keep_shift = {1'b1, {(BE_LEN-1){1'b0}}};
               cnt = 2'd1;
            end
         end
         else if (cnt == 2'd3) begin
            if (|keep_next) begin
               exp_words[exp_words_n] = data_next;
               exp_be[exp_words_n] = keep_next;
               exp_words_n = exp_words_n + 1;
            end
            data_shift = {DATA_LEN{1'b0}};
            keep_shift = {BE_LEN{1'b0}};
            cnt = 2'd0;
         end
         else begin
            data_shift = data_next;
            keep_shift = keep_next;
            cnt = cnt + 1'b1;
         end
      end
   endtask

   task build_expected_words;
      integer i;
      integer t;
      reg [1:0]  cnt;
      reg        pause_here;
      reg [DATA_LEN-1:0] data_shift;
      reg [BE_LEN-1:0] keep_shift;
      begin
         cnt = 2'd0;
         data_shift = {DATA_LEN{1'b0}};
         keep_shift = {BE_LEN{1'b0}};
         exp_words_n = 0;

         i = 0;
         while (i < TOTAL_WORDS) begin
            is_pause_template_at(i, pause_here);

            if (pause_here) begin
               for (t = 0; t < PAUSE_LEN; t = t + 1) begin
                  append_expected_packer_cycle(byte_seq_p[i], 1'b0, cnt, data_shift, keep_shift);
                  i = i + 1;
               end
            end
            else begin
               append_expected_packer_cycle(byte_seq_p[i], 1'b1, cnt, data_shift, keep_shift);
               i = i + 1;
            end
         end

         for (t = 0; t < 3; t = t + 1)
            append_expected_packer_cycle({GPIO_LEN{1'b0}}, 1'b0, cnt, data_shift, keep_shift);

         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Built %0d expected 32-bit words", exp_words_n);
      end
   endtask

   task build_synthetic_expected_words(input integer word_count);
      integer i;
      begin
         if (word_count > MAX_WORDS)
            fail("synthetic expected word count exceeds MAX_WORDS");

         exp_words_n = word_count;
         for (i = 0; i < word_count; i = i + 1) begin
            exp_words[i] = 32'h80000000 | i[31:0];
            exp_be[i] = FULL_BE;
         end
      end
   endtask

   task build_counter_expected_words(input integer word_count);
      integer i;
      begin
         if (word_count > MAX_WORDS)
            fail("counter expected word count exceeds MAX_WORDS");

         exp_words_n = word_count;
         for (i = 0; i < word_count; i = i + 1) begin
            exp_words[i] = i + 1;
            exp_be[i] = FULL_BE;
         end
      end
   endtask

   task expect_loopback_stage_counts(input integer expected_count);
      begin
         if (ft_rx_axis_hs_n !== expected_count) begin
            $display("ERROR: ft_rx_axis_hs_n=%0d expected=%0d", ft_rx_axis_hs_n, expected_count);
            fail("loopback diagnostic: FT RX adapter count mismatch");
         end
         if (loopback_fifo_wen_n !== expected_count) begin
            $display("ERROR: loopback_fifo_wen_n=%0d expected=%0d", loopback_fifo_wen_n, expected_count);
            fail("loopback diagnostic: loopback FIFO write count mismatch");
         end
         if (loopback_fifo_ren_n !== expected_count) begin
            $display("ERROR: loopback_fifo_ren_n=%0d expected=%0d", loopback_fifo_ren_n, expected_count);
            fail("loopback diagnostic: loopback FIFO read count mismatch");
         end
         if (tx_axis_hs_n !== expected_count) begin
            $display("ERROR: tx_axis_hs_n=%0d expected=%0d", tx_axis_hs_n, expected_count);
            fail("loopback diagnostic: TX AXIS count mismatch");
         end
         if (tx_words_n !== expected_count) begin
            $display("ERROR: tx_words_n=%0d expected=%0d", tx_words_n, expected_count);
            fail("loopback diagnostic: FT601 TX word count mismatch");
         end
      end
   endtask

   task clear_monitors;
      integer cap_i;
      begin
         tx_words_n = 0;
         tx_total_words_n = 0;
         rx_words_n = 0;
         rx_active_cycles_n = 0;
         oe_active_cycles_n = 0;
         rx_burst_seen = 1'b0;
         tx_burst_seen = 1'b0;
         tx_payload_burst_seen = 1'b0;
         ft_rx_axis_hs_n = 0;
         loopback_fifo_wen_n = 0;
         loopback_fifo_ren_n = 0;
         tx_axis_hs_n = 0;
         prev_ft_oe_n = ft_oe_n;
         prev_ft_rd_n = ft_rd_n;
         prev_ft_wr_n = ft_wr_n;
         prev_ft_txe_n_neg = ft_txe_n;
         prev_ft_rxf_n = ft_rxf_n;
         rx_expect_rd_after_oe = 1'b0;
         rx_expect_release_after_rxf = 1'b0;
         cmd_valid_pulses_n = 0;
         cmd_event_pulses_n = 0;
         rx_payload_check_en = 1'b0;
         tx_stream_only_mode = 1'b0;
         prev_loopback_payload_axis_stall = 1'b0;
         prev_loopback_payload_axis_tdata = {DATA_LEN{1'b0}};
         prev_loopback_payload_axis_tkeep = {BE_LEN{1'b0}};
         prev_normal_axis_stall = 1'b0;
         prev_normal_axis_tdata = {DATA_LEN{1'b0}};
         prev_normal_axis_tkeep = {BE_LEN{1'b0}};
         prev_loopback_axis_stall = 1'b0;
         prev_loopback_axis_tdata = {DATA_LEN{1'b0}};
         prev_loopback_axis_tkeep = {BE_LEN{1'b0}};
         prev_status_axis_stall = 1'b0;
         prev_status_axis_tdata = {DATA_LEN{1'b0}};
         prev_status_axis_tkeep = {BE_LEN{1'b0}};
         prev_tx_axis_stall = 1'b0;
         prev_tx_axis_tdata = {DATA_LEN{1'b0}};
         prev_tx_axis_tkeep = {BE_LEN{1'b0}};
         prev_status_tx_hold = status_tx_hold;
         for (cap_i = 0; cap_i < TX_CAPTURE_WORDS_MAX; cap_i = cap_i + 1) begin
            tx_captured_words[cap_i] = {DATA_LEN{1'b0}};
            tx_captured_be[cap_i] = {BE_LEN{1'b0}};
         end
      end
   endtask

   task scenario_start(input [1023:0] name);
      begin
         $display("SCENARIO START [%0d ns] %0s", $time, name);
      end
   endtask

   task scenario_end(input [1023:0] name);
      begin
         $display("SCENARIO END   [%0d ns] %0s", $time, name);
      end
   endtask

   task send_one_gpio_byte(
      input [GPIO_LEN-1:0] data_i,
      input                strobe_i
   );
      begin
         @(posedge gpio_clk);
         #1;
         gpio_data  = data_i;
         gpio_strob = strobe_i;
      end
   endtask

   task send_gpio_idle_cycle;
      begin
         send_one_gpio_byte({GPIO_LEN{1'b0}}, 1'b0);
      end
   endtask

   task send_gpio_stream;
      integer idx;
      integer t;
      reg pause_here;
      begin
         idx = 0;
         while (idx < TOTAL_WORDS) begin
            is_pause_template_at(idx, pause_here);

            if (pause_here) begin
               for (t = 0; t < PAUSE_LEN; t = t + 1) begin
                  send_one_gpio_byte(byte_seq_p[idx], 1'b0);
                  idx = idx + 1;
               end
            end
            else begin
               send_one_gpio_byte(byte_seq_p[idx], 1'b1);
               idx = idx + 1;
            end
         end

         send_gpio_idle_cycle();
      end
   endtask

   task wait_ft_cycles(input integer cycles);
      integer i;
      begin
         for (i = 0; i < cycles; i = i + 1)
            @(negedge ft_clk);
      end
   endtask

   task ft_set_txe_now(input val);
      begin
         #1;
         ft_txe_n = val;
      end
   endtask

   task ft_drive_rx_now(
      input [DATA_LEN-1:0] data_i,
      input [BE_LEN-1:0]   be_i,
      input                drive_en_i,
      input                rxf_n_i
   );
      begin
         #1;
         host_drive_en = drive_en_i;
         host_be_drv   = be_i;
         host_data_drv = data_i;
         ft_rxf_n      = rxf_n_i;
      end
   endtask

   task wait_gpio_cycles(input integer cycles);
      integer i;
      begin
         for (i = 0; i < cycles; i = i + 1)
            @(posedge gpio_clk);
      end
   endtask

   task send_gpio_word(
      input [DATA_LEN-1:0] word_i
   );
      begin
         send_one_gpio_byte(word_i[7:0], 1'b1);
         send_one_gpio_byte(word_i[15:8], 1'b1);
         send_one_gpio_byte(word_i[23:16], 1'b1);
         send_one_gpio_byte(word_i[31:24], 1'b1);
         send_gpio_idle_cycle();
      end
   endtask

   task wait_for_ft_rx_idle;
      integer timeout;
      begin
         timeout = 0;
         while ((((ft_rd_n !== 1'b1) || (ft_oe_n !== 1'b1)) || (dut.ft601_fsm.state !== FSM_ARB)) && (timeout < 64)) begin
            @(posedge ft_clk);
            timeout = timeout + 1;
         end

         if ((ft_rd_n !== 1'b1) || (ft_oe_n !== 1'b1) || (dut.ft601_fsm.state !== FSM_ARB))
            fail("FT601 RX path did not return to ARB/idle");
      end
   endtask

   task wait_for_ft_tx_idle;
      integer timeout;
      begin
         timeout = 0;
         while (((ft_wr_n !== 1'b1) || (dut.ft601_fsm.state !== FSM_ARB)) && (timeout < 64)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;
            timeout = timeout + 1;
         end

         if ((ft_wr_n !== 1'b1) || (dut.ft601_fsm.state !== FSM_ARB))
            fail("FT601 TX path did not return to ARB/idle");
      end
   endtask

   task expect_tx_word(
      input integer        wi,
      input [DATA_LEN-1:0] got_data,
      input [BE_LEN-1:0]   got_be
   );
      begin
         if (wi >= exp_words_n)
            fail("unexpected FT601 TX word");
         if (got_data !== exp_words[wi]) begin
            $display("ERROR: TX word [%0d] got=%h expected=%h", wi, got_data, exp_words[wi]);
            $finish;
         end
         if (got_be !== exp_be[wi]) begin
            $display("ERROR: TX BE [%0d] got=%h expected=%h", wi, got_be, exp_be[wi]);
            $finish;
         end
      end
   endtask

   function [DATA_LEN-1:0] build_status_word;
      input loopback_mode_i;
      input service_frame_error_i;
      input tx_fifo_empty_i;
      input tx_fifo_full_i;
      input loopback_fifo_empty_i;
      input loopback_fifo_full_i;
      begin
         build_status_word = {DATA_LEN{1'b0}};
         build_status_word[0] = loopback_mode_i;
         build_status_word[1] = service_frame_error_i;
         build_status_word[2] = tx_fifo_empty_i;
         build_status_word[3] = tx_fifo_full_i;
         build_status_word[4] = loopback_fifo_empty_i;
         build_status_word[5] = loopback_fifo_full_i;
      end
   endfunction

   task expect_rx_word(
      input integer        wi,
      input [DATA_LEN-1:0] got_data,
      input [BE_LEN-1:0]   got_be
   );
      begin
         if (wi >= exp_words_n)
            fail("unexpected FT601 RX word");
         if (got_data !== exp_words[wi]) begin
            $display("ERROR: RX word [%0d] got=%h expected=%h", wi, got_data, exp_words[wi]);
            $finish;
         end
         if (got_be !== exp_be[wi]) begin
            $display("ERROR: RX BE [%0d] got=%h expected=%h", wi, got_be, exp_be[wi]);
            $finish;
         end
      end
   endtask

   task wait_for_tx_words(
      input integer expected_words,
      input integer timeout_cycles
   );
      integer i;
      begin
         for (i = 0; i < timeout_cycles; i = i + 1) begin
            if (tx_words_n == expected_words)
               i = timeout_cycles;
            else
               @(negedge ft_clk);
         end

         if (tx_words_n !== expected_words) begin
            $display("ERROR: TX timeout, got=%0d expected=%0d", tx_words_n, expected_words);
            $finish;
         end
      end
   endtask

   task wait_for_tx_total_words(
      input integer expected_words,
      input integer timeout_cycles
   );
      integer i;
      begin
         for (i = 0; i < timeout_cycles; i = i + 1) begin
            if (tx_total_words_n == expected_words)
               i = timeout_cycles;
            else
               @(negedge ft_clk);
         end

         if (tx_total_words_n !== expected_words) begin
            $display("ERROR: TX total-word timeout, got=%0d expected=%0d", tx_total_words_n, expected_words);
            $finish;
         end
      end
   endtask

   task expect_captured_tx_word(
      input integer        wi,
      input [DATA_LEN-1:0] expected_data,
      input [BE_LEN-1:0]   expected_be
   );
      begin
         if (wi >= tx_total_words_n)
            fail("captured TX stream is shorter than expected");
         if (wi >= TX_CAPTURE_WORDS_MAX)
            fail("captured TX stream index exceeds TX_CAPTURE_WORDS_MAX");
         if (tx_captured_words[wi] !== expected_data) begin
            $display("ERROR: TX captured word [%0d] got=%h expected=%h", wi, tx_captured_words[wi], expected_data);
            $finish;
         end
         if (tx_captured_be[wi] !== expected_be) begin
            $display("ERROR: TX captured BE [%0d] got=%h expected=%h", wi, tx_captured_be[wi], expected_be);
            $finish;
         end
      end
   endtask

   task expect_status_frame_at(
      input integer        first_word_index,
      input [DATA_LEN-1:0] expected_status_word
   );
      begin
         expect_captured_tx_word(first_word_index, STATUS_MAGIC, FULL_BE);
         expect_captured_tx_word(first_word_index + 1, expected_status_word, FULL_BE);
      end
   endtask

   task expect_no_tx_for_cycles(input integer cycles);
      integer start_words;
      begin
         start_words = tx_total_words_n;
         wait_ft_cycles(cycles);
         if (tx_total_words_n !== start_words)
            fail("FT601 transmitted data while TXE_N was inactive");
      end
   endtask

   task drive_ft_loopback_stream;
      integer i;
      integer timeout;
      begin
         if (exp_words_n <= 0)
            fail("loopback stimulus is empty");

         @(posedge ft_clk);
         ft_drive_rx_now(exp_words[0], exp_be[0], 1'b1, 1'b0);

         timeout = 0;
         while ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("FT601 RX burst did not start");
         end

         for (i = 0; i < exp_words_n; i = i + 1) begin
            @(posedge ft_clk);
            if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
               fail("RX burst has an unexpected gap");
            if (i + 1 < exp_words_n)
               ft_drive_rx_now(exp_words[i + 1], exp_be[i + 1], 1'b1, 1'b0);
            else
               ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);
         end
      end
   endtask

   task drive_first_expected_loopback_words(
      input integer count
   );
      integer i;
      integer timeout;
      begin
         if (count <= 0)
            fail("loopback burst helper requires a positive word count");
         if (count > exp_words_n)
            fail("loopback burst helper count exceeds expected stimulus size");

         @(posedge ft_clk);
         ft_drive_rx_now(exp_words[0], exp_be[0], 1'b1, 1'b0);

         timeout = 0;
         while ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("short FT601 RX burst did not start");
         end

         for (i = 0; i < count; i = i + 1) begin
            @(posedge ft_clk);
            if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
               fail("short RX burst has an unexpected gap");
            if (i + 1 < count)
               ft_drive_rx_now(exp_words[i + 1], exp_be[i + 1], 1'b1, 1'b0);
            else
               ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);
         end
      end
   endtask

   task drive_expected_loopback_words_with_rx_gaps(
      input integer count,
      input integer gap_interval,
      input integer gap_cycles
   );
      integer i;
      integer chunk_left;
      integer timeout;
      begin
         if (count <= 0)
            fail("gapped RX burst requires a positive word count");
         if (count > exp_words_n)
            fail("gapped RX burst count exceeds expected stimulus size");

         i = 0;
         while (i < count) begin
            chunk_left = gap_interval;
            if (chunk_left <= 0)
               chunk_left = count;
            if (chunk_left > (count - i))
               chunk_left = count - i;

            @(posedge ft_clk);
            ft_drive_rx_now(exp_words[i], exp_be[i], 1'b1, 1'b0);

            timeout = 0;
            while ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0)) begin
               @(negedge ft_clk);
               timeout = timeout + 1;
               if (timeout > 128)
                  fail("gapped FT601 RX burst did not start");
            end

            while (chunk_left > 0) begin
               @(posedge ft_clk);
               if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
                  fail("gapped RX burst has an unexpected gap before packet boundary");
               if ((chunk_left > 1) && (i + 1 < count))
                  ft_drive_rx_now(exp_words[i + 1], exp_be[i + 1], 1'b1, 1'b0);
               else
                  ft_drive_rx_now(exp_words[i], exp_be[i], 1'b1, 1'b1);
               i = i + 1;
               chunk_left = chunk_left - 1;
            end

            if (i < count)
               wait_ft_cycles(gap_cycles);
         end
      end
   endtask

   task send_ft_command_frame(
      input [DATA_LEN-1:0] cmd_word
   );
      integer timeout;
      begin
         if (TB_VERBOSE_COMMAND)
            $display("INFO: Sending FT601 command frame magic=%h opcode=%h", CMD_MAGIC, cmd_word);

         @(posedge ft_clk);
         ft_drive_rx_now(CMD_MAGIC, FULL_BE, 1'b1, 1'b0);

         timeout = 0;
         while ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("FT601 command frame RX transaction did not start");
         end

         @(posedge ft_clk);
         if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
            fail("command frame magic read has an unexpected gap");
         ft_drive_rx_now(cmd_word, FULL_BE, 1'b1, 1'b0);

         @(posedge ft_clk);
         if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
            fail("command frame opcode read has an unexpected gap");
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);

         timeout = 0;
         while ((ft_rd_n !== 1'b1) || (ft_oe_n !== 1'b1)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("FT601 command frame RX transaction did not complete");
         end

         @(posedge ft_clk);
         wait_for_ft_rx_idle();
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);
         wait_ft_cycles(3);
      end
   endtask

   task send_malformed_service_frame;
      integer timeout;
      begin
         @(posedge ft_clk);
         ft_drive_rx_now(CMD_MAGIC, FULL_BE, 1'b1, 1'b0);

         timeout = 0;
         while ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("malformed service frame RX transaction did not start");
         end

         @(posedge ft_clk);
         if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
            fail("malformed service frame magic read has an unexpected gap");
         ft_drive_rx_now(CMD_GET_STATUS, {BE_LEN{1'b0}}, 1'b1, 1'b0);

         @(posedge ft_clk);
         if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
            fail("malformed service frame opcode read has an unexpected gap");
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);

         timeout = 0;
         while ((ft_rd_n !== 1'b1) || (ft_oe_n !== 1'b1)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("malformed service frame RX transaction did not complete");
         end

         @(posedge ft_clk);
         wait_for_ft_rx_idle();
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);
         wait_ft_cycles(3);
      end
   endtask

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

   task pulse_fpga_reset_only;
      integer n;
      integer gpio_release_cycles;
      integer ft_release_cycles;
      begin
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Pulsing FPGA_RESET to exit loopback mode");
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

         #1;
         if (ft_reset_n !== 1'b1)
            fail("RESET_N output must remain high during FPGA_RESET pulse");

         for (n = 0; n < 4; n = n + 1)
            @(posedge gpio_clk);
         for (n = 0; n < 4; n = n + 1)
            @(posedge ft_clk);

         fpga_reset = 1'b0;

         #1;
         if (ft_reset_n !== 1'b1)
            fail("RESET_N output must stay high after FPGA_RESET pulse");

         gpio_release_cycles = 0;
         while ((dut.gpio_rst_n_i !== 1'b1) && (gpio_release_cycles < 4)) begin
            @(posedge gpio_clk);
            gpio_release_cycles = gpio_release_cycles + 1;
         end
         if (dut.gpio_rst_n_i !== 1'b1)
            fail("gpio_rst_n_i did not release after FPGA_RESET pulse");

         ft_release_cycles = 0;
         while ((dut.ft_rst_n_i !== 1'b1) && (ft_release_cycles < 4)) begin
            @(posedge ft_clk);
            ft_release_cycles = ft_release_cycles + 1;
         end
         if (dut.ft_rst_n_i !== 1'b1)
            fail("ft_rst_n_i did not release after FPGA_RESET pulse");

         wait_gpio_cycles(4);
         wait_ft_cycles(4);

         if (dut.loopback_mode_ft !== 1'b0)
            fail("loopback_mode_ft must return to 0 after FPGA_RESET");
         if (dut.loopback_mode_gpio !== 1'b0)
            fail("loopback mode must clear in GPIO domain after FPGA_RESET");

         if (TB_VERBOSE_SCENARIO)
            $display("INFO: FPGA_RESET returned the design to normal mode");
      end
   endtask
   task test_gpio_mode;
      begin
         if (dut.loopback_mode_ft !== 1'b0)
            fail("GPIO-mode test started while loopback mode is active");
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Starting GPIO to FT601 mode test");

         send_gpio_stream();
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: GPIO stimulus sent into packer/FIFO path");
         wait_gpio_cycles(8);

         expect_no_tx_for_cycles(8);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Confirmed TX path stays idle while TXE_N is inactive");
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: TXE_N asserted low, waiting for FT601 transmission");

         wait_for_tx_words(exp_words_n, 12000);

         if (rx_active_cycles_n != 0)
            fail("RD_N became active in GPIO TX-only mode");
         if (oe_active_cycles_n != 0)
            fail("OE_N became active in GPIO TX-only mode");
         if (dut.normal_fifo_empty !== 1'b1)
            fail("TX FIFO is not empty after GPIO-mode transmission");
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: GPIO mode test passed, transmitted %0d words", tx_words_n);
      end
   endtask
   task test_loopback_mode;
      begin
         if (dut.loopback_mode_ft !== 1'b1)
            fail("Loopback-mode test started while loopback mode is not active");
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Starting FT601 loopback mode test");

         ft_txe_n = 1'b1;
         rx_payload_check_en = 1'b1;
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: TXE_N held high during FT601 receive phase");

         send_ft_command_frame(CMD_CLR_SERVICE_ERROR);
         if (rx_words_n !== 0)
            fail("control frame must not increment loopback RX payload counter");
         if (cmd_event_pulses_n !== 1)
            fail("control frame must generate exactly one command event");
         if (cmd_valid_pulses_n !== 1)
            fail("control frame must generate exactly one known command pulse");
         if (dut.loopback_fifo_empty !== 1'b1)
            fail("control frame must not leave data inside loopback FIFO");
         wait_gpio_cycles(4);

         drive_ft_loopback_stream();
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: FT601 RX stimulus burst driven into DUT from data_p words");
         wait_for_ft_rx_idle();
         wait_ft_cycles(4);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: DUT accepted payload words into loopback path, counted=%0d", rx_words_n);

         expect_no_tx_for_cycles(8);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Confirmed TX path stays idle while TXE_N is inactive");
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: TXE_N asserted low, FT601 may accept loopback data");

         wait_for_tx_words(exp_words_n, 16000);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: DUT returned %0d words back to FT601", tx_words_n);

         if (rx_active_cycles_n == 0)
            fail("RD_N never became active in loopback mode");
         if (oe_active_cycles_n == 0)
            fail("OE_N never became active in loopback mode");
         if (dut.loopback_fifo_empty !== 1'b1)
            fail("Loopback FIFO is not empty after loopback transmission");
         rx_payload_check_en = 1'b0;
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Loopback mode test passed, looped back %0d words", tx_words_n);
      end
   endtask

   task test_loopback_counter64_diagnostic;
      integer word_count;
      begin
         if (dut.loopback_mode_ft !== 1'b1)
            fail("counter64 loopback diagnostic requires loopback mode");

         word_count = 64;
         build_counter_expected_words(word_count);
         clear_monitors();
         ft_txe_n = 1'b1;
         rx_payload_check_en = 1'b1;

         drive_first_expected_loopback_words(word_count);
         wait_for_ft_rx_idle();
         wait_ft_cycles(4);

         if (rx_words_n !== word_count) begin
            $display("ERROR: rx_words_n=%0d expected=%0d", rx_words_n, word_count);
            fail("loopback diagnostic: RX payload count mismatch before TX readout");
         end
         if (ft_rx_axis_hs_n !== word_count) begin
            $display("ERROR: ft_rx_axis_hs_n=%0d expected=%0d", ft_rx_axis_hs_n, word_count);
            fail("loopback diagnostic: FT RX adapter count mismatch before TX readout");
         end
         if (loopback_fifo_wen_n !== word_count) begin
            $display("ERROR: loopback_fifo_wen_n=%0d expected=%0d", loopback_fifo_wen_n, word_count);
            fail("loopback diagnostic: loopback FIFO write count mismatch before TX readout");
         end

         expect_no_tx_for_cycles(8);
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         wait_for_tx_words(word_count, 4000);
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         wait_ft_cycles(2);

         expect_loopback_stage_counts(word_count);
         if (dut.loopback_fifo_empty !== 1'b1)
            fail("loopback diagnostic: FIFO must be empty after 64-word readout");

         rx_payload_check_en = 1'b0;
      end
   endtask

   task check_status_after_loopback_write_diagnostic;
      integer word_count;
      begin
         if (dut.loopback_mode_ft !== 1'b1)
            fail("status-after-loopback diagnostic requires loopback mode");

         word_count = 64;
         build_counter_expected_words(word_count);
         clear_monitors();
         ft_txe_n = 1'b1;
         rx_payload_check_en = 1'b1;

         drive_first_expected_loopback_words(word_count);
         wait_for_ft_rx_idle();
         wait_ft_cycles(4);

         if (rx_words_n !== word_count) begin
            $display("ERROR: rx_words_n=%0d expected=%0d", rx_words_n, word_count);
            fail("status-after-loopback diagnostic: RX payload count mismatch");
         end
         if (loopback_fifo_wen_n !== word_count) begin
            $display("ERROR: loopback_fifo_wen_n=%0d expected=%0d", loopback_fifo_wen_n, word_count);
            fail("status-after-loopback diagnostic: loopback FIFO write count mismatch");
         end
         if (dut.loopback_fifo_empty !== 1'b0)
            fail("status-after-loopback diagnostic: loopback FIFO must contain payload before status request");
         if (dut.loopback_fifo_full !== 1'b0)
            fail("status-after-loopback diagnostic: loopback FIFO unexpectedly full after 64 words");

         rx_payload_check_en = 1'b0;
         expect_status_bits(1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);

         clear_monitors();
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         wait_for_tx_words(word_count, 4000);
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         if (loopback_fifo_ren_n !== word_count) begin
            $display("ERROR: loopback_fifo_ren_n=%0d expected=%0d", loopback_fifo_ren_n, word_count);
            fail("status-after-loopback diagnostic: loopback FIFO read count mismatch");
         end
         if (tx_axis_hs_n !== word_count) begin
            $display("ERROR: tx_axis_hs_n=%0d expected=%0d", tx_axis_hs_n, word_count);
            fail("status-after-loopback diagnostic: TX AXIS count mismatch");
         end
         if (tx_words_n !== word_count) begin
            $display("ERROR: tx_words_n=%0d expected=%0d", tx_words_n, word_count);
            fail("status-after-loopback diagnostic: FT601 TX word count mismatch");
         end
         if (dut.loopback_fifo_empty !== 1'b1)
            fail("status-after-loopback diagnostic: loopback FIFO must empty after payload readout");
      end
   endtask

   task check_repeated_status_after_normal_pending_diagnostic;
      integer i;
      integer timeout;
      begin
         clear_monitors();
         tx_stream_only_mode = 1'b1;
         ft_txe_n = 1'b1;

         for (i = 0; i < 16; i = i + 1)
            send_gpio_word(32'h73000000 | i[31:0]);
         wait_gpio_cycles(4);

         timeout = 0;
         while ((dut.normal_fifo_empty === 1'b1) && (timeout < 256)) begin
            @(posedge ft_clk);
            timeout = timeout + 1;
         end
         if (dut.normal_fifo_empty !== 1'b0)
            fail("repeated-status diagnostic: normal FIFO did not receive pending payload");
         if (dut.normal_fifo_full !== 1'b0)
            fail("repeated-status diagnostic: normal FIFO unexpectedly full");

         expect_status_bits(1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
         expect_status_bits(1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
      end
   endtask

   task expect_status_frame(
      input [DATA_LEN-1:0] expected_word
   );
      begin
         if (tx_total_words_n !== 2)
            fail("exactly two TX words are expected for a pure status response");
         expect_status_frame_at(0, expected_word);
      end
   endtask
   task expect_status_bits(
      input expected_loopback_mode,
      input expected_service_frame_error,
      input expected_tx_fifo_empty,
      input expected_tx_fifo_full,
      input expected_loopback_fifo_empty,
      input expected_loopback_fifo_full
   );
      reg [DATA_LEN-1:0] expected_status;
      begin
         expected_status = build_status_word(expected_loopback_mode,
                                             expected_service_frame_error,
                                             expected_tx_fifo_empty,
                                             expected_tx_fifo_full,
                                             expected_loopback_fifo_empty,
                                             expected_loopback_fifo_full);
         clear_monitors();
         tx_stream_only_mode = 1'b1;
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         cmd_valid_pulses_n = 0;
         cmd_event_pulses_n = 0;

         send_ft_command_frame(CMD_GET_STATUS);
         if (cmd_event_pulses_n !== 1)
            fail("CMD_GET_STATUS must generate exactly one command event");
         if (cmd_valid_pulses_n !== 1)
            fail("CMD_GET_STATUS must generate exactly one known command pulse");

         expect_no_tx_for_cycles(8);
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         wait_for_tx_total_words(2, 256);
         expect_status_frame(expected_status);
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         tx_stream_only_mode = 1'b0;
      end
   endtask

   task set_loopback_via_status;
      begin
         clear_monitors();
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         cmd_valid_pulses_n = 0;
         cmd_event_pulses_n = 0;
         send_ft_command_frame(CMD_SET_LOOPBACK);
         if (cmd_event_pulses_n !== 1)
            fail("CMD_SET_LOOPBACK must generate exactly one command event");
         if (cmd_valid_pulses_n !== 1)
            fail("CMD_SET_LOOPBACK must generate exactly one known command pulse");
         wait_ft_cycles(8);
         expect_status_bits(1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
      end
   endtask

   task set_normal_via_status;
      begin
         clear_monitors();
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         cmd_valid_pulses_n = 0;
         cmd_event_pulses_n = 0;
         send_ft_command_frame(CMD_SET_NORMAL);
         if (cmd_event_pulses_n !== 1)
            fail("CMD_SET_NORMAL must generate exactly one command event");
         if (cmd_valid_pulses_n !== 1)
            fail("CMD_SET_NORMAL must generate exactly one known command pulse");
         wait_ft_cycles(8);
         expect_status_bits(1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
      end
   endtask

   task short_loopback_payload_check(input integer word_count);
      begin
         if (dut.loopback_mode_ft !== 1'b1)
            fail("short loopback payload check requires loopback mode");

         clear_monitors();
         ft_txe_n = 1'b1;
         rx_payload_check_en = 1'b1;
         drive_first_expected_loopback_words(word_count);
         wait_for_ft_rx_idle();
         wait_ft_cycles(4);
         expect_no_tx_for_cycles(8);

         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         wait_for_tx_words(word_count, 2000);
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         rx_payload_check_en = 1'b0;
      end
   endtask

   task transmit_expected_words_with_txe_gaps(
      input integer expected_count,
      input integer gap_interval,
      input integer gap_cycles
   );
      integer timeout;
      integer last_count;
      begin
         timeout = 0;
         last_count = tx_words_n;
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);

         while ((tx_words_n < expected_count) && (timeout < 40000)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;

            if (tx_words_n != last_count) begin
               last_count = tx_words_n;
               timeout = 0;
               if ((tx_words_n < expected_count) &&
                   (gap_interval > 0) &&
                   ((tx_words_n % gap_interval) == 0)) begin
                  ft_set_txe_now(1'b1);
                  wait_ft_cycles(gap_cycles);
                  ft_set_txe_now(1'b0);
               end
            end
            else begin
               timeout = timeout + 1;
            end
         end

         if (tx_words_n !== expected_count)
            fail("gapped TX did not transmit the expected number of words");

         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
      end
   endtask

   task test_loopback_packet_boundary_integrity;
      integer word_count;
      begin
         if (dut.loopback_mode_ft !== 1'b1)
            fail("packet-boundary loopback check requires loopback mode");

         word_count = 1100;
         build_synthetic_expected_words(word_count);
         clear_monitors();
         ft_txe_n = 1'b1;
         rx_payload_check_en = 1'b1;

         drive_expected_loopback_words_with_rx_gaps(word_count, 128, 6);
         wait_for_ft_rx_idle();
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);
         wait_ft_cycles(8);

         if (rx_words_n !== word_count)
            fail("gapped loopback RX accepted word count mismatch");
         if (ft_rx_axis_hs_n !== word_count) begin
            $display("ERROR: ft_rx_axis_hs_n=%0d expected=%0d", ft_rx_axis_hs_n, word_count);
            fail("gapped loopback FT RX stream count mismatch");
         end
         if (loopback_fifo_wen_n !== word_count) begin
            $display("ERROR: loopback_fifo_wen_n=%0d expected=%0d", loopback_fifo_wen_n, word_count);
            fail("gapped loopback FIFO write count mismatch");
         end

         transmit_expected_words_with_txe_gaps(word_count, 128, 6);

         if (loopback_fifo_ren_n !== word_count) begin
            $display("ERROR: loopback_fifo_ren_n=%0d expected=%0d", loopback_fifo_ren_n, word_count);
            fail("gapped loopback FIFO read count mismatch");
         end
         if (tx_axis_hs_n !== word_count) begin
            $display("ERROR: tx_axis_hs_n=%0d expected=%0d", tx_axis_hs_n, word_count);
            fail("gapped loopback TX stream count mismatch");
         end
         if (dut.loopback_fifo_empty !== 1'b1)
            fail("Loopback FIFO is not empty after gapped loopback transmission");

         rx_payload_check_en = 1'b0;
      end
   endtask

   task check_chipscope_like_rx_takeover;
      integer timeout;
      begin
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Starting ChipScope-like RX takeover check");

         clear_monitors();
         tx_stream_only_mode = 1'b1;
         ft_txe_n = 1'b1;
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);

         send_gpio_word(32'h11223344);
         send_gpio_word(32'h55667788);
         wait_gpio_cycles(4);

         @(posedge ft_clk);
         ft_set_txe_now(1'b0);

         timeout = 0;
         while ((ft_wr_n !== 1'b0) && (timeout < 128)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;
            timeout = timeout + 1;
         end
         if (ft_wr_n !== 1'b0)
            fail("ChipScope-like check did not start TX before RX takeover");

         ft_drive_rx_now(32'h13579BDF, FULL_BE, 1'b1, 1'b0);

         timeout = 0;
         while (((ft_oe_n !== 1'b0) || (ft_rd_n !== 1'b0)) && (timeout < 128)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;
            timeout = timeout + 1;
         end
         if ((ft_oe_n !== 1'b0) || (ft_rd_n !== 1'b0))
            fail("ChipScope-like check did not grant RX while RXF_N was active");

         if (ft_wr_n !== 1'b1)
            fail("WR_N must be inactive when RX takeover reaches RD_N/OE_N active");

         @(posedge ft_clk);
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);
         wait_for_ft_rx_idle();

         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         tx_stream_only_mode = 1'b0;

         if (TB_VERBOSE_SCENARIO)
            $display("INFO: ChipScope-like RX takeover check passed");
      end
   endtask

   task run_reset_boot_normal;
      begin
         scenario_start("reset_boot_normal");
         tb_reset();
         clear_monitors();
         if (ft_reset_n !== 1'b1)
            fail("RESET_N must be released after reset_boot_normal");
         if (ft_wr_n !== 1'b1)
            fail("WR_N must be inactive after reset_boot_normal");
         if (ft_rd_n !== 1'b1)
            fail("RD_N must be inactive after reset_boot_normal");
         if (ft_oe_n !== 1'b1)
            fail("OE_N must be inactive after reset_boot_normal");
         if (dut.loopback_mode_ft !== 1'b0)
            fail("reset_boot_normal must start in normal mode");
         scenario_end("reset_boot_normal");
      end
   endtask

   task run_normal_path;
      begin
         scenario_start("normal_path");
         tb_reset();
         clear_monitors();
         test_gpio_mode();
         scenario_end("normal_path");
      end
   endtask

   task run_loopback_path;
      begin
         scenario_start("loopback_path");
         tb_reset();
         set_loopback_via_status();
         clear_monitors();
         test_loopback_mode();

         pulse_fpga_reset_only();
         set_loopback_via_status();
         short_loopback_payload_check(8);
         set_normal_via_status();
         scenario_end("loopback_path");
      end
   endtask

   task send_clear_command(input [DATA_LEN-1:0] cmd_word);
      begin
         clear_monitors();
         cmd_valid_pulses_n = 0;
         cmd_event_pulses_n = 0;
         send_ft_command_frame(cmd_word);
         if (cmd_event_pulses_n !== 1)
            fail("clear command must generate exactly one command event");
         if (cmd_valid_pulses_n !== 1)
            fail("clear command must generate exactly one known command pulse");
         wait_ft_cycles(8);
      end
   endtask

   task check_normal_fifo_full_blocks_write;
      reg [DATA_LEN-1:0] test_word;
      begin
         clear_monitors();
         ft_txe_n = 1'b1;
         test_word = 32'h44332211;

         force dut.normal_fifo_full = 1'b1;
         send_gpio_word(test_word);
         wait_gpio_cycles(2);
         #TB_POSEDGE_SAMPLE_DELAY;

         if (dut.normal_fifo_wen_req !== 1'b0)
            fail("normal FIFO write request must be blocked while FIFO is full");
         @(negedge gpio_clk);
         release dut.normal_fifo_full;
         wait_ft_cycles(4);
      end
   endtask

   task check_status_preempts_pending_normal_payload;
      integer i;
      integer timeout;
      begin
         clear_monitors();
         tx_stream_only_mode = 1'b1;
         allow_status_preempt_drop = 1'b1;
         ft_txe_n = 1'b1;

         for (i = 0; i < 16; i = i + 1)
            send_gpio_word(32'h71000000 | i[31:0]);
         wait_gpio_cycles(4);

         timeout = 0;
         while ((dut.normal_fifo_empty === 1'b1) && (timeout < 256)) begin
            @(posedge ft_clk);
            timeout = timeout + 1;
         end
         if (dut.normal_fifo_empty !== 1'b0)
            fail("normal FIFO did not receive payload before status preemption check");

         @(posedge ft_clk);
         ft_set_txe_now(1'b0);

         timeout = 0;
         while ((dut.ft601_fsm.tx_adapter.out_valid_ff !== 1'b1) &&
                (timeout < 256)) begin
            @(posedge ft_clk);
            timeout = timeout + 1;
         end
         if (dut.ft601_fsm.tx_adapter.out_valid_ff !== 1'b1)
            fail("TX adapter did not prefetch normal payload before status preemption check");

         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_ft_cycles(4);

         send_ft_command_frame(CMD_GET_STATUS);

         clear_monitors();
         tx_stream_only_mode = 1'b1;
         allow_status_preempt_drop = 1'b1;
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         wait_for_tx_total_words(2, 512);

         expect_captured_tx_word(0, STATUS_MAGIC, FULL_BE);
         if (tx_captured_be[1] !== FULL_BE)
            fail("status preemption check returned non-full status keep");
         if (tx_captured_words[1][31:6] !== 26'b0)
            fail("status preemption check returned non-zero reserved status bits");
         if (tx_captured_words[1][0] !== 1'b0)
            fail("status preemption check changed loopback mode");
         if (tx_captured_words[1][1] !== 1'b0)
            fail("status preemption check unexpectedly set service_frame_error");

         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         allow_status_preempt_drop = 1'b0;
         tx_stream_only_mode = 1'b0;
      end
   endtask

   task check_ft601_reset_command_pulse(input expected_loopback_mode);
      begin
         clear_monitors();
         ft_txe_n = 1'b1;
         cmd_valid_pulses_n = 0;
         cmd_event_pulses_n = 0;
         fork
            send_ft_command_frame(CMD_FT601_RESET);
            expect_ft601_reset_pulse_2clks();
         join
         if (cmd_event_pulses_n !== 1)
            fail("CMD_FT601_RESET must generate exactly one command event");
         if (cmd_valid_pulses_n !== 1)
            fail("CMD_FT601_RESET must generate exactly one known command pulse");
         if (dut.loopback_mode_ft !== expected_loopback_mode)
            fail("CMD_FT601_RESET must preserve runtime mode");
      end
   endtask

   task check_diagnostic_clear;
      begin
         clear_monitors();
         cmd_valid_pulses_n = 0;
         cmd_event_pulses_n = 0;
         send_malformed_service_frame();
         if (cmd_event_pulses_n !== 0)
            fail("malformed service frame must not generate command event");
         expect_status_bits(1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0);
         send_clear_command(CMD_CLR_SERVICE_ERROR);
         expect_status_bits(1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);

         send_malformed_service_frame();
         wait_ft_cycles(2);
         expect_status_bits(1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0);
         send_clear_command(CMD_CLR_SERVICE_ERROR);
         expect_status_bits(1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
      end
   endtask

   task run_diagnostics;
      begin
         scenario_start("diagnostics");
         tb_reset();

         expect_status_bits(1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
         expect_status_bits(1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);

         check_normal_fifo_full_blocks_write();
         expect_status_bits(1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
         check_status_preempts_pending_normal_payload();
         tb_reset();

         check_diagnostic_clear();
         check_ft601_reset_command_pulse(1'b0);
         set_loopback_via_status();
         check_ft601_reset_command_pulse(1'b1);
         set_normal_via_status();
         scenario_end("diagnostics");
      end
   endtask

   task run_ft601_boundary;
      begin
         scenario_start("ft601_boundary");
         tb_reset();
         check_chipscope_like_rx_takeover();
         scenario_end("ft601_boundary");
      end
   endtask

   task run_payload_boundary;
      begin
         scenario_start("payload_boundary");
         tb_reset();
         set_loopback_via_status();
         test_loopback_packet_boundary_integrity();
         scenario_end("payload_boundary");
      end
   endtask

   task run_loopback_counter64_diagnostic;
      begin
         scenario_start("loopback_counter64_diagnostic");
         tb_reset();
         set_loopback_via_status();
         test_loopback_counter64_diagnostic();
         scenario_end("loopback_counter64_diagnostic");
      end
   endtask

   task run_service_status_diagnostic;
      begin
         scenario_start("service_status_diagnostic");
         tb_reset();
         set_loopback_via_status();
         check_status_after_loopback_write_diagnostic();

         tb_reset();
         check_repeated_status_after_normal_pending_diagnostic();
         scenario_end("service_status_diagnostic");
      end
   endtask

   // Capture FT601 pins after the DUT posedge output boundary has settled.
   always @(posedge ft_clk or negedge ft_reset_n) begin
      if (!ft_reset_n) begin
         tx_words_n <= 0;
         rx_words_n <= 0;
         rx_active_cycles_n <= 0;
         oe_active_cycles_n <= 0;
         rx_burst_seen <= 1'b0;
         tx_burst_seen <= 1'b0;
         tx_payload_burst_seen <= 1'b0;
         ft_rx_axis_hs_n <= 0;
         loopback_fifo_wen_n <= 0;
         loopback_fifo_ren_n <= 0;
         tx_axis_hs_n <= 0;
         prev_ft_oe_n  <= 1'b1;
         prev_ft_rd_n  <= 1'b1;
         prev_ft_wr_n  <= 1'b1;
         prev_ft_txe_n_neg <= 1'b1;
         prev_ft_rxf_n <= 1'b1;
         loopback_fifo_wen_pre <= 1'b0;
         loopback_fifo_wdata_pre <= {FIFO_RX_LEN{1'b0}};
         prev_ft_rx_axis_stall <= 1'b0;
         prev_ft_rx_axis_tdata <= {DATA_LEN{1'b0}};
         prev_ft_rx_axis_tkeep <= {BE_LEN{1'b0}};
         prev_loopback_payload_axis_stall <= 1'b0;
         prev_loopback_payload_axis_tdata <= {DATA_LEN{1'b0}};
         prev_loopback_payload_axis_tkeep <= {BE_LEN{1'b0}};
         prev_normal_axis_stall <= 1'b0;
         prev_normal_axis_tdata <= {DATA_LEN{1'b0}};
         prev_normal_axis_tkeep <= {BE_LEN{1'b0}};
         prev_loopback_axis_stall <= 1'b0;
         prev_loopback_axis_tdata <= {DATA_LEN{1'b0}};
         prev_loopback_axis_tkeep <= {BE_LEN{1'b0}};
         prev_status_axis_stall <= 1'b0;
         prev_status_axis_tdata <= {DATA_LEN{1'b0}};
         prev_status_axis_tkeep <= {BE_LEN{1'b0}};
         prev_tx_axis_stall <= 1'b0;
         prev_tx_axis_tdata <= {DATA_LEN{1'b0}};
         prev_tx_axis_tkeep <= {BE_LEN{1'b0}};
         prev_status_tx_hold <= 1'b0;
         rx_expect_rd_after_oe       <= 1'b0;
         rx_expect_release_after_rxf <= 1'b0;
      end
      else begin
         loopback_fifo_wen_pre <= dut.loopback_fifo_wen;
         loopback_fifo_wdata_pre <= dut.loopback_fifo_wdata;

         #TB_POSEDGE_SAMPLE_DELAY;

         if (dut.cmd_event_valid)
            cmd_event_pulses_n <= cmd_event_pulses_n + 1;

         if (dut.cmd_decoder.cmd_known)
            cmd_valid_pulses_n <= cmd_valid_pulses_n + 1;

         if (prev_ft_rx_axis_stall && !dut.ft_rx_axis_tready) begin
            if (dut.ft_rx_axis_tvalid !== 1'b1)
               fail("FT RX AXIS valid dropped before ready");
            if ((dut.ft_rx_axis_tdata !== prev_ft_rx_axis_tdata) ||
                (dut.ft_rx_axis_tkeep !== prev_ft_rx_axis_tkeep))
               fail("FT RX AXIS data/keep changed while stalled");
         end

         prev_ft_rx_axis_stall <= dut.ft_rx_axis_tvalid && !dut.ft_rx_axis_tready;
         if (dut.ft_rx_axis_tvalid && !dut.ft_rx_axis_tready) begin
            prev_ft_rx_axis_tdata <= dut.ft_rx_axis_tdata;
            prev_ft_rx_axis_tkeep <= dut.ft_rx_axis_tkeep;
         end

         if (dut.loopback_fifo_wen && !(dut.loopback_payload_tvalid && dut.loopback_payload_tready))
            fail("loopback FIFO write occurred without payload AXIS handshake");

         if (prev_normal_axis_stall && !dut.normal_axis_tready &&
             !allow_status_preempt_drop && !status_tx_hold && !prev_status_tx_hold) begin
            if (dut.normal_axis_tvalid &&
                ((dut.normal_axis_tdata !== prev_normal_axis_tdata) ||
                 (dut.normal_axis_tkeep !== prev_normal_axis_tkeep)))
               fail("normal AXIS data/keep changed while stalled");
         end
         prev_normal_axis_stall <= dut.normal_axis_tvalid && !dut.normal_axis_tready;
         if (dut.normal_axis_tvalid && !dut.normal_axis_tready) begin
            prev_normal_axis_tdata <= dut.normal_axis_tdata;
            prev_normal_axis_tkeep <= dut.normal_axis_tkeep;
         end

         if (prev_loopback_payload_axis_stall && !dut.loopback_payload_tready) begin
            if (dut.loopback_payload_tvalid !== 1'b1)
               fail("loopback payload AXIS valid dropped before ready");
            if ((dut.loopback_payload_tdata !== prev_loopback_payload_axis_tdata) ||
                (dut.loopback_payload_tkeep !== prev_loopback_payload_axis_tkeep))
               fail("loopback payload AXIS data/keep changed while stalled");
         end

         prev_loopback_payload_axis_stall <= dut.loopback_payload_tvalid &&
                                             !dut.loopback_payload_tready;
         if (dut.loopback_payload_tvalid && !dut.loopback_payload_tready) begin
            prev_loopback_payload_axis_tdata <= dut.loopback_payload_tdata;
            prev_loopback_payload_axis_tkeep <= dut.loopback_payload_tkeep;
         end

         if (prev_loopback_axis_stall && !dut.loopback_axis_tready) begin
            if (dut.loopback_axis_tvalid !== 1'b1)
               fail("loopback AXIS valid dropped before ready");
            if ((dut.loopback_axis_tdata !== prev_loopback_axis_tdata) ||
                (dut.loopback_axis_tkeep !== prev_loopback_axis_tkeep))
               fail("loopback AXIS data/keep changed while stalled");
         end

         prev_loopback_axis_stall <= dut.loopback_axis_tvalid && !dut.loopback_axis_tready;
         if (dut.loopback_axis_tvalid && !dut.loopback_axis_tready) begin
            prev_loopback_axis_tdata <= dut.loopback_axis_tdata;
            prev_loopback_axis_tkeep <= dut.loopback_axis_tkeep;
         end

         if (prev_status_axis_stall && !dut.status_axis_tready) begin
            if (dut.status_axis_tvalid !== 1'b1)
               fail("status AXIS valid dropped before ready");
            if ((dut.status_axis_tdata !== prev_status_axis_tdata) ||
                (dut.status_axis_tkeep !== prev_status_axis_tkeep))
               fail("status AXIS data/keep changed while stalled");
         end
         if (dut.status_axis_tvalid && (dut.status_axis_tkeep !== FULL_BE))
            fail("status AXIS keep must be full");

         prev_status_axis_stall <= dut.status_axis_tvalid && !dut.status_axis_tready;
         if (dut.status_axis_tvalid && !dut.status_axis_tready) begin
            prev_status_axis_tdata <= dut.status_axis_tdata;
            prev_status_axis_tkeep <= dut.status_axis_tkeep;
         end

         if (prev_tx_axis_stall && !dut.tx_axis_tready &&
             !allow_status_preempt_drop && !status_tx_hold && !prev_status_tx_hold) begin
            if (dut.tx_axis_tvalid &&
                ((dut.tx_axis_tdata !== prev_tx_axis_tdata) ||
                 (dut.tx_axis_tkeep !== prev_tx_axis_tkeep)))
               fail("TX AXIS data/keep changed while stalled");
         end

         prev_tx_axis_stall <= dut.tx_axis_tvalid && !dut.tx_axis_tready;
         if (dut.tx_axis_tvalid && !dut.tx_axis_tready) begin
            prev_tx_axis_tdata <= dut.tx_axis_tdata;
            prev_tx_axis_tkeep <= dut.tx_axis_tkeep;
         end

         if (rx_expect_rd_after_oe) begin
            if (ft_rd_n === 1'b0)
               rx_expect_rd_after_oe <= 1'b0;
         end

         if (rx_expect_release_after_rxf) begin
            if ((ft_oe_n === 1'b1) && (ft_rd_n === 1'b1))
               rx_expect_release_after_rxf <= 1'b0;
         end

         if (prev_ft_oe_n && !ft_oe_n) begin
            if (ft_rd_n !== 1'b1)
               fail("RD_N must stay inactive in the cycle OE_N first asserts");
            rx_expect_rd_after_oe <= 1'b1;
         end

         if (prev_ft_rd_n && !ft_rd_n) begin
            if ((prev_ft_oe_n !== 1'b0) || (ft_oe_n !== 1'b0))
               fail("RD_N must assert only after OE_N is already active");
         end

         if (!prev_ft_rxf_n && ft_rxf_n && ((!ft_oe_n) || (!ft_rd_n)))
            rx_expect_release_after_rxf <= 1'b1;

         if (dut.ft_rx_axis_tvalid && dut.ft_rx_axis_tready) begin
            ft_rx_axis_hs_n <= ft_rx_axis_hs_n + 1;
            if (!rx_burst_seen) begin
               if (TB_VERBOSE_STREAM)
                  $display("INFO: FT601 RX burst started");
               rx_burst_seen <= 1'b1;
            end
         end

         if (rx_payload_check_en && loopback_fifo_wen_pre && (rx_words_n < 2))
            if (TB_VERBOSE_STREAM)
               $display("INFO: RX sample[%0d] data=%h be=%h", rx_words_n, loopback_fifo_wdata_pre[FIFO_RX_LEN-1:BE_LEN], loopback_fifo_wdata_pre[BE_LEN-1:0]);
         if (rx_payload_check_en && loopback_fifo_wen_pre) begin
            expect_rx_word(rx_words_n, loopback_fifo_wdata_pre[FIFO_RX_LEN-1:BE_LEN], loopback_fifo_wdata_pre[BE_LEN-1:0]);
            rx_words_n <= rx_words_n + 1;
         end

         if (dut.loopback_fifo_wen)
            loopback_fifo_wen_n <= loopback_fifo_wen_n + 1;
         if (dut.loopback_fifo_ren)
            loopback_fifo_ren_n <= loopback_fifo_ren_n + 1;
         if (dut.tx_axis_tvalid && dut.tx_axis_tready)
            tx_axis_hs_n <= tx_axis_hs_n + 1;

         if (!ft_wr_n && ((!ft_oe_n) || (!ft_rd_n)))
            fail("WR_N must not be active while OE_N/RD_N selects FT601 read direction");

         if ((!ft_oe_n) || (!ft_rd_n)) begin
            if (dut.ft601_wrapper.data_t_o_ff !== {DATA_LEN{1'b1}})
               fail("DATA bus must be tri-stated by FPGA during FT601 read");
            if (dut.ft601_wrapper.be_t_o_ff !== {BE_LEN{1'b1}})
               fail("BE bus must be tri-stated by FPGA during FT601 read");
         end

         if (!ft_wr_n) begin
            if (dut.ft601_wrapper.data_t_o_ff !== {DATA_LEN{1'b0}})
               fail("DATA bus must be driven by FPGA during FT601 write");
            if (dut.ft601_wrapper.be_t_o_ff !== {BE_LEN{1'b0}})
               fail("BE bus must be driven by FPGA during FT601 write");
            if (!tx_burst_seen) begin
               if (TB_VERBOSE_STREAM)
                  $display("INFO: FT601 TX burst started");
               tx_burst_seen <= 1'b1;
            end
            if (tx_total_words_n < TX_CAPTURE_WORDS_MAX) begin
               tx_captured_words[tx_total_words_n] <= ft_data_bus;
               tx_captured_be[tx_total_words_n] <= ft_be_bus;
            end
            tx_total_words_n <= tx_total_words_n + 1;

            if (tx_stream_only_mode) begin
               tx_payload_burst_seen <= 1'b0;
               if (TB_VERBOSE_STREAM)
                  $display("INFO: TX stream[%0d] data=%h be=%h", tx_total_words_n, ft_data_bus, ft_be_bus);
            end
            else begin
               tx_payload_burst_seen <= 1'b1;
               if (tx_words_n < 2) begin
                  if (TB_VERBOSE_STREAM)
                     $display("INFO: TX sample[%0d] data=%h be=%h", tx_words_n, ft_data_bus, ft_be_bus);
               end
               expect_tx_word(tx_words_n, ft_data_bus, ft_be_bus);
               tx_words_n <= tx_words_n + 1;
            end
         end
         else if (tx_payload_burst_seen && !prev_ft_txe_n_neg && !ft_txe_n && !prev_ft_wr_n && (tx_words_n < exp_words_n)) begin
            fail("WR_N must stay active for a continuous TX burst while TXE_N is low");
         end
         else if (prev_ft_wr_n == 1'b0) begin
            tx_payload_burst_seen <= 1'b0;
         end

         if (!ft_rd_n)
            rx_active_cycles_n <= rx_active_cycles_n + 1;
         if (!ft_oe_n)
            oe_active_cycles_n <= oe_active_cycles_n + 1;

         prev_ft_oe_n  <= ft_oe_n;
         prev_ft_rd_n  <= ft_rd_n;
         prev_ft_wr_n  <= ft_wr_n;
         prev_ft_txe_n_neg <= ft_txe_n;
         prev_ft_rxf_n <= ft_rxf_n;
         prev_status_tx_hold <= status_tx_hold;
      end
   end

   initial begin
      if (TB_VERBOSE_SCENARIO)
         $display("INFO: Testbench start. Universal bitstream mode");
      load_vectors();
      build_expected_words();

      run_reset_boot_normal();
      run_normal_path();
      run_loopback_path();
      run_loopback_counter64_diagnostic();
      run_service_status_diagnostic();
      run_diagnostics();
      run_ft601_boundary();
      run_payload_boundary();

      $display("TEST PASSED. Universal bitstream flow verified, words=%0d", exp_words_n);
      $finish;
   end

   initial begin
      $dumpfile("testbench.vcd");
      $dumpvars(0, testbench);
   end

endmodule
