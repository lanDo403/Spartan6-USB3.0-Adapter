`timescale 1ns / 1ps
`include "LVDS.v"
`include "packer8to32.v"
`include "fifo_dualport.v"
`include "sram_dp.v"
`include "fifo_fsm.v"

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
/* verilator lint_on UNUSEDPARAM */
/* verilator lint_on DECLFILENAME */

module lvds_tb;

   // Test parameters
   localparam integer TOTAL_WORDS       = 3402;
   localparam integer PAUSE_LEN         = 16;
   localparam integer LVDS_LEN          = 8;
   localparam integer DATA_LEN          = 32;
   localparam integer BE_LEN            = 4;
   localparam integer FIFO_DEPTH        = 1024;
   localparam integer ADDR_LEN          = 10;
   localparam integer MAX_WORDS         = (TOTAL_WORDS / 4) + 4;
   localparam integer FSM_RX_MAX_WORDS  = 8;

   // TB signals
   reg                  tb_clock;
   reg                  tb_ft_clk;
   reg                  tb_strob;
   reg                  fpga_reset;
   reg                  rst_n;
   reg  [LVDS_LEN-1:0]  data_p;

   reg                  auto_read_en;
   reg                  manual_rd_req;
   reg                  lvds_check_en;
   reg                  pack_check_en;
   reg                  fifo_check_en;
   reg                  fsm_mode_en;
   reg                  fsm_tx_check_en;
   reg                  fsm_rx_check_en;

   // FT601-side stimulus for fifo_fsm
   reg                  ft_txe_n;
   reg                  ft_rxf_n;
   reg                  ft_full_fifo;
   reg  [DATA_LEN-1:0]  ft_rx_data;
   reg  [BE_LEN-1:0]    ft_rx_be;

   // Input bytes loaded from file
   reg [7:0] byte_seq_p [0:TOTAL_WORDS-1];

   // Expected TX words built only from bytes sent with strobe = 1
   reg [31:0] exp_words [0:MAX_WORDS-1];
   integer    exp_words_n;

   // Expected RX words for fifo_fsm receive path checks
   reg [DATA_LEN-1:0] fsm_rx_exp_data [0:FSM_RX_MAX_WORDS-1];
   reg [BE_LEN-1:0]   fsm_rx_exp_be   [0:FSM_RX_MAX_WORDS-1];
   integer            fsm_rx_exp_n;

   integer pack_words_n;
   integer got_words_n;
   integer fsm_tx_words_n;
   integer fsm_rx_words_n;
   integer fsm_rd_pulses_n;

   // Clock generators (tb_clock 50 MHz, tb_ft_clk 100 MHz)
   always #10 tb_clock  = ~tb_clock;
   always #5  tb_ft_clk = ~tb_ft_clk;

   initial begin
      tb_clock        = 1'b0;
      tb_ft_clk       = 1'b0;
      tb_strob        = 1'b0;
      fpga_reset      = 1'b0;
      rst_n           = 1'b0;
      data_p          = 8'h00;
      auto_read_en    = 1'b0;
      manual_rd_req   = 1'b0;
      lvds_check_en   = 1'b0;
      pack_check_en   = 1'b0;
      fifo_check_en   = 1'b0;
      fsm_mode_en     = 1'b0;
      fsm_tx_check_en = 1'b0;
      fsm_rx_check_en = 1'b0;
      ft_txe_n        = 1'b1;
      ft_rxf_n        = 1'b1;
      ft_full_fifo    = 1'b0;
      ft_rx_data      = 32'd0;
      ft_rx_be        = 4'd0;
      fsm_rx_exp_n    = 0;
   end

   // =========================================================
   // DUT: LVDS -> packer8to32 -> fifo_dualport + sram_dp + fifo_fsm
   // =========================================================
   wire [LVDS_LEN-1:0] DataOUT;
   wire                StrobOUT;
   wire                ClockOUT;

   LVDS #(
      .LVDS_LEN(LVDS_LEN)
   ) u_lvds (
      .clk_i(tb_clock),
      .strob_i(tb_strob),
      .data_i(data_p),
      .data_o(DataOUT),
      .strob_o(StrobOUT),
      .clk_o(ClockOUT)
   );

   wire [DATA_LEN-1:0] pack_data;
   wire                pack_vld;

   packer8to32 #(
      .DATA_LEN(DATA_LEN),
      .LVDS_LEN(LVDS_LEN)
   ) u_packer (
      .clk(ClockOUT),
      .rst_a(fpga_reset),
      .valid_i(StrobOUT),
      .data_i(DataOUT),
      .valid_o(pack_vld),
      .data_o(pack_data)
   );

   // FIFO + SRAM
   wire [DATA_LEN-1:0] fifo_data_o;
   wire [DATA_LEN-1:0] sram_in;
   wire [DATA_LEN-1:0] sram_out;
   wire                fifo_wen_o;
   wire                fifo_ren_o;
   wire [ADDR_LEN-1:0] fifo_addr_wr;
   wire [ADDR_LEN-1:0] fifo_addr_rd;
   wire                fifo_full;
   wire                fifo_empty;
   wire                fifo_overflow;
   wire                fifo_underflow;

   // fifo_fsm interface
   wire [DATA_LEN-1:0] fsm_tx_data;
   wire [DATA_LEN-1:0] fsm_rx_data_o;
   wire [BE_LEN-1:0]   fsm_tx_be;
   wire [BE_LEN-1:0]   fsm_fifo_be;
   wire                fsm_wr_n;
   wire                fsm_rd_n;
   wire                fsm_oe_n;
   wire                fsm_drive_tx;
   wire                fsm_fifo_pop;
   wire                fsm_fifo_append;

   wire                fifo_rd_req;
   reg                 fifo_ren_d;

   assign fifo_rd_req = fsm_mode_en ? fsm_fifo_pop : (manual_rd_req | (auto_read_en & ~fifo_empty));

   fifo_dualport #(
      .DATA_LEN(DATA_LEN),
      .DEPTH(FIFO_DEPTH)
   ) u_fifo (
      .clk_wr(ClockOUT),
      .clk_rd(tb_ft_clk),
      .rst_a(fpga_reset),
      .rst_n(rst_n),
      .wen_i(pack_vld),
      .ren_i(fifo_rd_req),
      .sram_data_r(sram_out),
      .data_i(pack_data),
      .data_o(fifo_data_o),
      .sram_data_w(sram_in),
      .wen_o(fifo_wen_o),
      .ren_o(fifo_ren_o),
      .wr_addr_o(fifo_addr_wr),
      .rd_addr_o(fifo_addr_rd),
      .full(fifo_full),
      .empty(fifo_empty),
      .overflow(fifo_overflow),
      .underflow(fifo_underflow)
   );

   sram_dp #(
      .DATA_LEN(DATA_LEN),
      .DEPTH(FIFO_DEPTH)
   ) u_sram (
      .wr_clk(ClockOUT),
      .rd_clk(tb_ft_clk),
      .wen(fifo_wen_o),
      .ren(fifo_ren_o),
      .wr_addr(fifo_addr_wr),
      .rd_addr(fifo_addr_rd),
      .data_i(sram_in),
      .data_o(sram_out)
   );

   fifo_fsm #(
      .DATA_LEN(DATA_LEN),
      .BE_LEN(BE_LEN)
   ) u_fsm (
      .rst_n(rst_n),
      .clk(tb_ft_clk),
      .txe_n(ft_txe_n),
      .rxf_n(ft_rxf_n),
      .data_i(fifo_data_o),
      .rx_data(ft_rx_data),
      .be_i(ft_rx_be),
      .full_fifo(ft_full_fifo),
      .empty_fifo(fifo_empty),
      .data_o(fsm_rx_data_o),
      .tx_data(fsm_tx_data),
      .be_o(fsm_tx_be),
      .fifo_be(fsm_fifo_be),
      .wr_n(fsm_wr_n),
      .rd_n(fsm_rd_n),
      .oe_n(fsm_oe_n),
      .drive_tx(fsm_drive_tx),
      .fifo_pop(fsm_fifo_pop),
      .fifo_append(fsm_fifo_append)
   );

   // =========================================================
   // Tasks
   // =========================================================
   task tb_reset;
      integer n;
      begin
         auto_read_en    = 1'b0;
         manual_rd_req   = 1'b0;
         lvds_check_en   = 1'b0;
         pack_check_en   = 1'b0;
         fifo_check_en   = 1'b0;
         fsm_mode_en     = 1'b0;
         fsm_tx_check_en = 1'b0;
         fsm_rx_check_en = 1'b0;
         ft_txe_n        = 1'b1;
         ft_rxf_n        = 1'b1;
         ft_full_fifo    = 1'b0;
         ft_rx_data      = 32'd0;
         ft_rx_be        = 4'd0;
         fsm_rx_exp_n    = 0;
         rst_n           = 1'b0;
         fpga_reset      = 1'b1;
         tb_strob        = 1'b0;
         data_p          = 8'h00;

         for (n = 0; n < 4; n = n + 1)
            @(posedge tb_clock);

         rst_n      = 1'b1;
         fpga_reset = 1'b0;

         for (n = 0; n < 2; n = n + 1)
            @(posedge tb_clock);
         for (n = 0; n < 2; n = n + 1)
            @(posedge tb_ft_clk);

         lvds_check_en = 1'b1;
      end
   endtask

   task load_vectors;
      integer fd_p;
      integer i;
      begin
         fd_p = $fopen("data_p", "r");
         if (fd_p == 0) begin
            $display("ERROR: cannot open data_p");
            #1000;
            $finish;
         end

         for (i = 0; i < TOTAL_WORDS; i = i + 1) begin
            if ($fscanf(fd_p, "%h\n", byte_seq_p[i]) != 1) begin
               $display("ERROR: cannot read byte [%0d] from data_p", i);
               $stop;
            end
         end

         $fclose(fd_p);
      end
   endtask

   // Testbench helper: this byte sequence is only a pause template.
   // DUT validity is defined only by strobe.
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

   task build_expected_words;
      integer i;
      reg [31:0] w;
      reg [1:0]  cnt;
      reg        pause_here;
      begin
         w = 32'd0;
         cnt = 2'd0;
         exp_words_n = 0;

         i = 0;
         while (i < TOTAL_WORDS) begin
            is_pause_template_at(i, pause_here);

            if (pause_here)
               i = i + PAUSE_LEN;
            else begin
               case (cnt)
                  2'd0: w[7:0]   = byte_seq_p[i];
                  2'd1: w[15:8]  = byte_seq_p[i];
                  2'd2: w[23:16] = byte_seq_p[i];
                  2'd3: begin
                     w[31:24] = byte_seq_p[i];
                     exp_words[exp_words_n] = w;
                     exp_words_n = exp_words_n + 1;
                  end
               endcase
               cnt = cnt + 1'b1;
               i = i + 1;
            end
         end

         if (cnt != 2'd0)
            $display("WARNING: valid bytes count is not multiple of 4");
      end
   endtask

   // Drive data on negedge so LVDS.v captures stable values on the next posedge.
   task send_one_byte(input [7:0] bp, input strobe);
      begin
         @(negedge tb_clock);
         data_p   = bp;
         tb_strob = strobe;
      end
   endtask

   task send_all;
      integer idx;
      integer t;
      reg pause_here;
      begin
         idx = 0;
         while (idx < TOTAL_WORDS) begin
            is_pause_template_at(idx, pause_here);

            if (pause_here) begin
               for (t = 0; t < PAUSE_LEN; t = t + 1) begin
                  send_one_byte(byte_seq_p[idx], 1'b0);
                  idx = idx + 1;
               end
            end
            else begin
               send_one_byte(byte_seq_p[idx], 1'b1);
               idx = idx + 1;
            end
         end

         @(negedge tb_clock);
         tb_strob = 1'b0;
      end
   endtask

   task send_overflow_burst(input integer words_n);
      integer wi;
      integer bi;
      reg [7:0] burst_byte;
      begin
         burst_byte = 8'h10;
         for (wi = 0; wi < words_n; wi = wi + 1) begin
            for (bi = 0; bi < 4; bi = bi + 1) begin
               send_one_byte(burst_byte, 1'b1);
               burst_byte = burst_byte + 1'b1;
            end
         end

         @(negedge tb_clock);
         tb_strob = 1'b0;
      end
   endtask

   task expect_packer_word(input integer wi, input [31:0] got);
      begin
         if (wi >= exp_words_n) begin
            $display("ERROR: packer produced unexpected word [%0d] = %h", wi, got);
            $stop;
         end
         if (got !== exp_words[wi]) begin
            $display("ERROR: packer word [%0d] got=%h expected=%h", wi, got, exp_words[wi]);
            $stop;
         end
      end
   endtask

   task expect_fifo_word(input integer wi, input [31:0] got);
      begin
         if (wi >= exp_words_n) begin
            $display("ERROR: FIFO produced unexpected word [%0d] = %h", wi, got);
            $stop;
         end
         if (got !== exp_words[wi]) begin
            $display("ERROR: FIFO word [%0d] got=%h expected=%h", wi, got, exp_words[wi]);
            $stop;
         end
      end
   endtask

   task expect_fsm_tx_word(
      input integer     wi,
      input [31:0]      got_data,
      input [BE_LEN-1:0] got_be
   );
      begin
         if (wi >= exp_words_n) begin
            $display("ERROR: fifo_fsm transmitted unexpected word [%0d] = %h", wi, got_data);
            $stop;
         end
         if (got_data !== exp_words[wi]) begin
            $display("ERROR: fifo_fsm TX word [%0d] got=%h expected=%h", wi, got_data, exp_words[wi]);
            $stop;
         end
         if (got_be !== {BE_LEN{1'b1}}) begin
            $display("ERROR: fifo_fsm TX BE [%0d] got=%h expected=%h", wi, got_be, {BE_LEN{1'b1}});
            $stop;
         end
         if (!fsm_drive_tx) begin
            $display("ERROR: fifo_fsm drive_tx must be active during TX word [%0d]", wi);
            $stop;
         end
         if (fsm_wr_n !== 1'b0) begin
            $display("ERROR: fifo_fsm WR_N must be active during TX word [%0d]", wi);
            $stop;
         end
         if (fsm_rd_n !== 1'b1) begin
            $display("ERROR: fifo_fsm RD_N must stay inactive during TX word [%0d]", wi);
            $stop;
         end
         if (fsm_oe_n !== 1'b1) begin
            $display("ERROR: fifo_fsm OE_N must stay inactive during TX word [%0d]", wi);
            $stop;
         end
      end
   endtask

   task expect_fsm_rx_word(
      input integer     wi,
      input [31:0]      got_data,
      input [BE_LEN-1:0] got_be
   );
      begin
         if (wi >= fsm_rx_exp_n) begin
            $display("ERROR: fifo_fsm received unexpected RX word [%0d] = %h", wi, got_data);
            $stop;
         end
         if (got_data !== fsm_rx_exp_data[wi]) begin
            $display("ERROR: fifo_fsm RX word [%0d] got=%h expected=%h", wi, got_data, fsm_rx_exp_data[wi]);
            $stop;
         end
         if (got_be !== fsm_rx_exp_be[wi]) begin
            $display("ERROR: fifo_fsm RX BE [%0d] got=%h expected=%h", wi, got_be, fsm_rx_exp_be[wi]);
            $stop;
         end
      end
   endtask

   task wait_ft_cycles(input integer cycles);
      integer k;
      begin
         for (k = 0; k < cycles; k = k + 1)
            @(posedge tb_ft_clk);
      end
   endtask

   task wait_lvds_cycles(input integer cycles);
      integer k;
      begin
         for (k = 0; k < cycles; k = k + 1)
            @(posedge tb_clock);
      end
   endtask

   task pulse_read_when_empty;
      begin
         @(negedge tb_ft_clk);
         manual_rd_req = 1'b1;
         @(posedge tb_ft_clk);
         @(negedge tb_ft_clk);
         manual_rd_req = 1'b0;
      end
   endtask

   task wait_for_fsm_tx_words(input integer expected_words, input integer timeout_cycles);
      integer k;
      begin
         for (k = 0; k < timeout_cycles; k = k + 1) begin
            if (fsm_tx_words_n == expected_words)
               k = timeout_cycles;
            else
               @(posedge tb_ft_clk);
         end
         if (fsm_tx_words_n !== expected_words) begin
            $display("ERROR: fifo_fsm TX timeout. got_words=%0d expected_words=%0d", fsm_tx_words_n, expected_words);
            $stop;
         end
      end
   endtask

   task expect_no_fsm_tx_for_cycles(input integer cycles);
      integer start_words;
      begin
         start_words = fsm_tx_words_n;
         wait_ft_cycles(cycles);
         if (fsm_tx_words_n !== start_words) begin
            $display("ERROR: fifo_fsm transmitted data while TXE_N was inactive");
            $stop;
         end
      end
   endtask

   task drive_fsm_rx_word(input [31:0] word_i, input [BE_LEN-1:0] be_i);
      integer timeout;
      begin
         @(negedge tb_ft_clk);
         ft_rx_data = word_i;
         ft_rx_be   = be_i;
         ft_rxf_n   = 1'b0;

         timeout = 0;
         while (fsm_rd_n !== 1'b0) begin
            @(posedge tb_ft_clk);
            timeout = timeout + 1;
            if (timeout > 32) begin
               $display("ERROR: fifo_fsm did not assert RD_N for RX word %h", word_i);
               $stop;
            end
         end

         timeout = 0;
         while (fsm_fifo_append !== 1'b1) begin
            @(posedge tb_ft_clk);
            timeout = timeout + 1;
            if (timeout > 32) begin
               $display("ERROR: fifo_fsm did not append RX word %h", word_i);
               $stop;
            end
         end

         @(negedge tb_ft_clk);
         ft_rxf_n = 1'b1;
      end
   endtask

   task test_fifo_underflow;
      begin
         wait_ft_cycles(2);
         if (!fifo_empty) begin
            $display("ERROR: FIFO must be empty before underflow test");
            $stop;
         end

         pulse_read_when_empty();
         wait_ft_cycles(2);

         if (!fifo_underflow) begin
            $display("ERROR: FIFO underflow flag was not asserted");
            $stop;
         end
      end
   endtask

   task test_fifo_overflow;
      begin
         send_overflow_burst(FIFO_DEPTH + 8);
         wait_lvds_cycles(16);

         if (!fifo_full) begin
            $display("ERROR: FIFO full flag was not asserted during overflow test");
            $stop;
         end
         if (!fifo_overflow) begin
            $display("ERROR: FIFO overflow flag was not asserted");
            $stop;
         end
      end
   endtask

   task test_nominal_direct_fifo_path;
      begin
         pack_check_en = 1'b1;
         fifo_check_en = 1'b1;
         auto_read_en  = 1'b1;

         send_all();
         wait_ft_cycles(2000);

         if (pack_words_n !== exp_words_n) begin
            $display("ERROR: packer word count does not match expected count");
            $stop;
         end
         if (got_words_n !== exp_words_n) begin
            $display("ERROR: FIFO word count does not match expected count");
            $stop;
         end
         if (!fifo_empty) begin
            $display("ERROR: FIFO is not empty after direct read test");
            $stop;
         end
         if (fifo_overflow) begin
            $display("ERROR: FIFO overflow must remain low during nominal direct path test");
            $stop;
         end
         if (fifo_underflow) begin
            $display("ERROR: FIFO underflow must remain low during nominal direct path test");
            $stop;
         end
      end
   endtask

   task test_fsm_tx_path;
      begin
         pack_check_en   = 1'b1;
         fsm_mode_en     = 1'b1;
         fsm_tx_check_en = 1'b1;
         ft_txe_n        = 1'b1;

         send_all();
         wait_lvds_cycles(8);

         if (pack_words_n !== exp_words_n) begin
            $display("ERROR: packer word count does not match expected count before fifo_fsm TX");
            $stop;
         end
         if (fifo_empty) begin
            $display("ERROR: FIFO must contain data before fifo_fsm TX starts");
            $stop;
         end

         expect_no_fsm_tx_for_cycles(8);

         @(negedge tb_ft_clk);
         ft_txe_n = 1'b0;

         wait_for_fsm_tx_words(exp_words_n, 6000);

         if (!fifo_empty) begin
            $display("ERROR: FIFO is not empty after fifo_fsm TX test");
            $stop;
         end
         if (fsm_rd_pulses_n != 0) begin
            $display("ERROR: fifo_fsm must not read FT601 during TX-only test");
            $stop;
         end
      end
   endtask

   task test_fsm_rx_blocked_by_full;
      integer start_rd_pulses;
      integer start_rx_words;
      begin
         fsm_mode_en     = 1'b1;
         fsm_rx_check_en = 1'b1;
         ft_full_fifo    = 1'b1;
         start_rd_pulses = fsm_rd_pulses_n;
         start_rx_words  = fsm_rx_words_n;

         @(negedge tb_ft_clk);
         ft_rx_data = 32'hCAFEBABE;
         ft_rx_be   = 4'hF;
         ft_rxf_n   = 1'b0;

         wait_ft_cycles(8);

         if (fsm_rd_pulses_n !== start_rd_pulses) begin
            $display("ERROR: fifo_fsm issued RD_N pulse while RX FIFO was full");
            $stop;
         end
         if (fsm_rx_words_n !== start_rx_words) begin
            $display("ERROR: fifo_fsm appended RX data while RX FIFO was full");
            $stop;
         end
         if (fsm_oe_n !== 1'b1) begin
            $display("ERROR: fifo_fsm OE_N must stay inactive when RX is blocked");
            $stop;
         end

         @(negedge tb_ft_clk);
         ft_rxf_n    = 1'b1;
         ft_full_fifo = 1'b0;
      end
   endtask

   task test_fsm_rx_path;
      begin
         fsm_mode_en     = 1'b1;
         fsm_rx_check_en = 1'b1;
         ft_txe_n        = 1'b1;
         ft_rxf_n        = 1'b1;
         ft_full_fifo    = 1'b0;

         fsm_rx_exp_n         = 3;
         fsm_rx_exp_data[0]   = 32'h11223344;
         fsm_rx_exp_be[0]     = 4'hF;
         fsm_rx_exp_data[1]   = 32'hA5A55A5A;
         fsm_rx_exp_be[1]     = 4'h3;
         fsm_rx_exp_data[2]   = 32'h55AA1234;
         fsm_rx_exp_be[2]     = 4'hC;

         drive_fsm_rx_word(fsm_rx_exp_data[0], fsm_rx_exp_be[0]);
         drive_fsm_rx_word(fsm_rx_exp_data[1], fsm_rx_exp_be[1]);
         drive_fsm_rx_word(fsm_rx_exp_data[2], fsm_rx_exp_be[2]);

         wait_ft_cycles(6);

         if (fsm_rx_words_n !== fsm_rx_exp_n) begin
            $display("ERROR: fifo_fsm RX word count got=%0d expected=%0d", fsm_rx_words_n, fsm_rx_exp_n);
            $stop;
         end
         if (fsm_rd_pulses_n !== fsm_rx_exp_n) begin
            $display("ERROR: fifo_fsm RD_N pulse count got=%0d expected=%0d", fsm_rd_pulses_n, fsm_rx_exp_n);
            $stop;
         end
      end
   endtask

   // =========================================================
   // MAIN
   // =========================================================
   initial begin
      load_vectors();
      build_expected_words();

      tb_reset();
      test_fifo_underflow();

      tb_reset();
      test_fifo_overflow();

      tb_reset();
      test_nominal_direct_fifo_path();

      tb_reset();
      test_fsm_tx_path();

      tb_reset();
      test_fsm_rx_blocked_by_full();

      tb_reset();
      test_fsm_rx_path();

      $display("TEST IS PASSED!");
      $stop;
   end

   // =========================================================
   // LVDS output checks in input clock domain
   // =========================================================
   always @(posedge tb_clock) begin
      if (lvds_check_en) begin
         #1;
         if (ClockOUT !== tb_clock) begin
            $display("ERROR: LVDS clock output does not follow input clock");
            $stop;
         end
         if (DataOUT !== data_p) begin
            $display("ERROR: LVDS data mismatch. got=%h expected=%h", DataOUT, data_p);
            $stop;
         end
         if (StrobOUT !== tb_strob) begin
            $display("ERROR: LVDS strobe mismatch. got=%b expected=%b", StrobOUT, tb_strob);
            $stop;
         end
      end
   end

   // =========================================================
   // Packer output checks in input clock domain
   // =========================================================
   always @(posedge ClockOUT or posedge fpga_reset) begin
      if (fpga_reset) begin
         pack_words_n <= 0;
      end
      else if (pack_check_en && pack_vld) begin
         expect_packer_word(pack_words_n, pack_data);
         pack_words_n <= pack_words_n + 1;
      end
   end

   // =========================================================
   // Direct FIFO read monitor in FT clock domain
   // =========================================================
   always @(posedge tb_ft_clk or negedge rst_n) begin
      if (!rst_n) begin
         fifo_ren_d  <= 1'b0;
         got_words_n <= 0;
      end
      else begin
         fifo_ren_d <= fifo_ren_o;
         if (!fsm_mode_en && fifo_check_en && fifo_ren_d) begin
            expect_fifo_word(got_words_n, fifo_data_o);
            got_words_n <= got_words_n + 1;
         end
      end
   end

   // =========================================================
   // fifo_fsm TX/RX monitor in FT clock domain
   // =========================================================
   always @(posedge tb_ft_clk or negedge rst_n) begin
      if (!rst_n) begin
         fsm_tx_words_n <= 0;
         fsm_rx_words_n <= 0;
         fsm_rd_pulses_n <= 0;
      end
      else begin
         if (fsm_tx_check_en && !fsm_wr_n) begin
            expect_fsm_tx_word(fsm_tx_words_n, fsm_tx_data, fsm_tx_be);
            fsm_tx_words_n <= fsm_tx_words_n + 1;
         end

         if (fsm_rx_check_en && !fsm_rd_n) begin
            if (fsm_oe_n !== 1'b0) begin
               $display("ERROR: fifo_fsm must drive OE_N low before/with RD_N");
               $stop;
            end
            if (fsm_drive_tx !== 1'b0) begin
               $display("ERROR: fifo_fsm drive_tx must be low during RX");
               $stop;
            end
            if (fsm_wr_n !== 1'b1) begin
               $display("ERROR: fifo_fsm WR_N must stay inactive during RX");
               $stop;
            end
            fsm_rd_pulses_n <= fsm_rd_pulses_n + 1;
         end

         if (fsm_rx_check_en && fsm_fifo_append) begin
            expect_fsm_rx_word(fsm_rx_words_n, fsm_rx_data_o, fsm_fifo_be);
            fsm_rx_words_n <= fsm_rx_words_n + 1;
         end
      end
   end

   initial begin
      $dumpfile("lvds_tb.vcd");
      $dumpvars(0, lvds_tb);
   end

endmodule
