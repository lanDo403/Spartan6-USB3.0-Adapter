`ifndef TB_AXIS_IF_SV
`define TB_AXIS_IF_SV

// Passive AXIS-like monitor view; drivers still operate through testbench tasks.
interface tb_axis_if #(
   parameter int DATA_LEN = 32,
   parameter int BE_LEN   = 4
);
   wire                clk;
   wire                rst_n;
   wire                valid;
   wire                ready;
   wire [DATA_LEN-1:0] data;
   wire [BE_LEN-1:0]   keep;

   clocking monitor_cb @(posedge clk);
      default input #0 output #0;
      input rst_n;
      input valid;
      input ready;
      input data;
      input keep;
   endclocking

   modport passive (
      clocking monitor_cb,
      input clk,
      input rst_n,
      input valid,
      input ready,
      input data,
      input keep
   );
endinterface

`endif
