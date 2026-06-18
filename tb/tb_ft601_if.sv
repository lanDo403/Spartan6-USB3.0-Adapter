`ifndef TB_FT601_IF_SV
`define TB_FT601_IF_SV

// Passive FT601 bus view plus wrapper tri-state intent for boundary checks.
interface tb_ft601_if #(
   parameter int DATA_LEN = 32,
   parameter int BE_LEN   = 4
);
   wire                clk;
   wire                reset_n;
   wire                txe_n;
   wire                rxf_n;
   wire                oe_n;
   wire                wr_n;
   wire                rd_n;
   wire [DATA_LEN-1:0] data;
   wire [BE_LEN-1:0]   be;

   // White-box wrapper intent for resolved inout tri-state checks.
   wire [DATA_LEN-1:0] data_t;
   wire [BE_LEN-1:0]   be_t;

   clocking monitor_cb @(posedge clk);
      default input #0 output #0;
      input reset_n;
      input txe_n;
      input rxf_n;
      input oe_n;
      input wr_n;
      input rd_n;
      input data;
      input be;
      input data_t;
      input be_t;
   endclocking

   modport passive (
      clocking monitor_cb,
      input clk,
      input reset_n,
      input txe_n,
      input rxf_n,
      input oe_n,
      input wr_n,
      input rd_n,
      input data,
      input be,
      input data_t,
      input be_t
   );
endinterface

`endif
