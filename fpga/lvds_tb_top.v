`timescale 1ns / 1ps
`include "fifo_top"

module lvds_tb;
   localparam integer TOTAL_WORDS = 3402;
   localparam integer PAUSE_LEN   = 16;

   localparam integer FPGA_DATA_GPIO_LEN = 8;
   localparam integer CHIP_BE_LEN = 4;
   localparam integer CHIP_DATA_LEN = 32;
   localparam integer FIFO_DEPTH = 4096;
	localparam integer ADDR_LEN = 12; $clog2(FIFO_DEPTH)
   localparam integer MAX_WORDS = (TOTAL_WORDS / 4) + 4;

   // Data from data_p file
   reg [7:0] byte_seq [0:TOTAL_WORDS-1]

   // FPGA input data from gpio
   reg gpio_clk = 1'b0;
   reg fpga_reset = 1'b0;
   reg gpio_strob = 1'b0;
   reg [7:0] gpio_data = 8'hff;

   // FPGA data to/from FT601
   reg chip_clk = 1'b0;
   reg chip_reset_n =1'b0;
   reg chip_txe_n = 1'b1;
   reg chip_rxf_n = 1'b1;
   reg chip_oe_n = 1'b1;
   reg chip_wr_n = 1'b1;
   reg chip_rd_n = 1'b1;
   reg [CHIP_BE_LEN-1:0] chip_be = 4'hf;
   reg [CHIP_DATA_LEN-1:0] chip_data = 32'hffffffff;

   always #10 lvds_clk  = ~lvds_clk;
   always #5  chip_clk  = ~chip_clk;

   fifo_top #() u_top (
      .LVDS_CLK(gpio_clk),
      .LVDS_DATA(gpio_data),
      .LVDS_STROB(gpio_strob),
      .FPGA_RESET(fpga_reset),
      .CLK(chip_clk),
      .RESET_N(chip_reset_n),
      .TXE_N(chip_txe_n),
      .RXF_N(chip_rxf_n),
      .OE_N(chip_oe_n),
      .WR_N(chip_wr_n),
      .RD_N(chip_rd_n),
      .BE(chip_be),
      .DATA(chip_data)
   );

   initial begin 
      fpga_reset = 1;
      #20;
      fpga_reset = 0;
      #100;
   end

   initial begin
      $dumpfile("lvds_tb_top.vcd");
      $dumpvars(0, lvds_tb_top);
   end
endmodule;