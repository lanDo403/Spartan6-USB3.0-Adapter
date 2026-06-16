`ifndef TB_PKG_SV
`define TB_PKG_SV

package tb_pkg;
   localparam int TOTAL_WORDS = 3402;
   localparam int PAUSE_LEN   = 16;

   localparam int GPIO_LEN    = 8;
   localparam int DATA_LEN    = 32;
   localparam int BE_LEN      = 4;
   localparam int FIFO_RX_LEN = DATA_LEN + BE_LEN;
   localparam int FIFO_DEPTH  = 8192;
   localparam int MAX_WORDS   = 1200;

   localparam logic [DATA_LEN-1:0] CMD_MAGIC = 32'hA55A5AA5;
   localparam logic [DATA_LEN-1:0] STATUS_MAGIC = 32'h5AA55AA5;
   localparam logic [DATA_LEN-1:0] CMD_CLR_SERVICE_ERROR = 32'h00000001;
   localparam logic [DATA_LEN-1:0] CMD_SET_LOOPBACK = 32'hA5A50004;
   localparam logic [DATA_LEN-1:0] CMD_SET_NORMAL = 32'hA5A50005;
   localparam logic [DATA_LEN-1:0] CMD_GET_STATUS = 32'hA5A50006;
   localparam logic [DATA_LEN-1:0] CMD_FT601_RESET = 32'hA5A50007;
   localparam logic [BE_LEN-1:0]   FULL_BE = {BE_LEN{1'b1}};

   localparam int   TX_CAPTURE_WORDS_MAX = MAX_WORDS;
   localparam logic TB_VERBOSE_STREAM = 1'b0;
   localparam logic TB_VERBOSE_COMMAND = 1'b0;
   localparam logic TB_VERBOSE_SCENARIO = 1'b0;
   localparam int   TB_POSEDGE_SAMPLE_DELAY = 2;
   localparam logic [5:0] FSM_ARB = 6'b000001;

   typedef struct packed {
      logic [BE_LEN-1:0]   keep;
      logic [DATA_LEN-1:0] data;
   } tb_axis_word_t;

   typedef struct packed {
      logic [DATA_LEN-1:0] data;
      logic [BE_LEN-1:0]   keep;
   } ft601_word_t;

   typedef enum logic [2:0] {
      SVC_CLR_SERVICE_ERROR,
      SVC_SET_LOOPBACK,
      SVC_SET_NORMAL,
      SVC_GET_STATUS,
      SVC_FT601_RESET,
      SVC_UNKNOWN
   } service_cmd_t;

   typedef struct packed {
      logic loopback_mode;
      logic service_frame_error;
      logic tx_fifo_empty;
      logic tx_fifo_full;
      logic loopback_fifo_empty;
      logic loopback_fifo_full;
   } status_t;

   function automatic ft601_word_t make_word(
      input logic [DATA_LEN-1:0] data,
      input logic [BE_LEN-1:0]   keep
   );
      begin
         make_word.data = data;
         make_word.keep = keep;
      end
   endfunction

   function automatic logic [DATA_LEN-1:0] service_opcode(
      input service_cmd_t cmd
   );
      begin
         case (cmd)
            SVC_CLR_SERVICE_ERROR: service_opcode = CMD_CLR_SERVICE_ERROR;
            SVC_SET_LOOPBACK:      service_opcode = CMD_SET_LOOPBACK;
            SVC_SET_NORMAL:        service_opcode = CMD_SET_NORMAL;
            SVC_GET_STATUS:        service_opcode = CMD_GET_STATUS;
            SVC_FT601_RESET:       service_opcode = CMD_FT601_RESET;
            default:               service_opcode = 32'hFFFF_FFFF;
         endcase
      end
   endfunction

   function automatic logic [DATA_LEN-1:0] pack_status(
      input status_t status
   );
      begin
         pack_status = {DATA_LEN{1'b0}};
         pack_status[0] = status.loopback_mode;
         pack_status[1] = status.service_frame_error;
         pack_status[2] = status.tx_fifo_empty;
         pack_status[3] = status.tx_fifo_full;
         pack_status[4] = status.loopback_fifo_empty;
         pack_status[5] = status.loopback_fifo_full;
      end
   endfunction

   function automatic status_t unpack_status(
      input logic [DATA_LEN-1:0] word
   );
      begin
         unpack_status.loopback_mode = word[0];
         unpack_status.service_frame_error = word[1];
         unpack_status.tx_fifo_empty = word[2];
         unpack_status.tx_fifo_full = word[3];
         unpack_status.loopback_fifo_empty = word[4];
         unpack_status.loopback_fifo_full = word[5];
      end
   endfunction
endpackage

`endif
