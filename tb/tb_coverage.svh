`ifndef TB_COVERAGE_SVH
`define TB_COVERAGE_SVH

   integer cov_main_reset_boot_normal;
   integer cov_main_normal_path;
   integer cov_main_loopback_path;
   integer cov_main_service_control;

   integer cov_cmd_normal_get_status;
   integer cov_cmd_normal_set_loopback;
   integer cov_cmd_normal_clear;
   integer cov_cmd_normal_ft601_reset;
   integer cov_cmd_loopback_get_status;
   integer cov_cmd_loopback_set_normal;
   integer cov_cmd_loopback_clear;
   integer cov_cmd_loopback_ft601_reset;

   integer cov_get_status_pending_payload;
   integer cov_txe_backpressure;
   integer cov_rxf_backpressure;

   integer cov_req_reset_normal_mode;
   integer cov_req_get_status_stale_none;
   integer cov_req_get_status_stale_payload;
   integer cov_req_status_window_txe_opened_idle;
   integer cov_req_mode_switch_active_ft_traffic;
   integer cov_req_normal_payload_keep_full;
   integer cov_req_normal_payload_keep_partial;
   integer cov_req_loopback_payload_keep_full;
   integer cov_req_loopback_payload_keep_partial;
   integer cov_req_loopback_payload_len_short;
   integer cov_req_loopback_payload_len_long;
   integer cov_req_rxf_backpressure_normal;
   integer cov_req_rxf_backpressure_loopback;
   integer cov_req_txe_backpressure_normal;
   integer cov_req_txe_backpressure_loopback;
   integer cov_req_txe_backpressure_status;
   integer cov_req_ft_direction_tx;
   integer cov_req_ft_direction_rx;
   integer cov_req_ft_direction_turnaround;
   integer cov_req_arbiter_status_ready;
   integer cov_req_arbiter_loopback_ready;
   integer cov_req_arbiter_normal_ready;
   integer cov_req_router_service_normal;
   integer cov_req_router_service_loopback;
   integer cov_req_router_payload_loopback_full;
   integer cov_req_router_payload_loopback_partial;
   integer cov_req_fsm_arb_idle;
   integer cov_req_fsm_tx_from_arb;
   integer cov_req_fsm_rx_from_arb;
   integer cov_req_fsm_turnaround_from_tx;
   integer cov_req_fsm_turnaround_from_rx;
   integer cov_req_axis_stall_seen;

   integer cov_req_ft601_turnaround_rx_priority;
   integer cov_req_ft601_rxf_boundary;
   integer cov_req_payload_long_gapped_loopback;
   integer cov_req_control_status_window;
   integer cov_req_control_mode_switch_idle;
   integer cov_req_control_router_demux;
   integer cov_req_control_unknown_opcode;
   integer cov_req_control_arbiter_priority;

   integer cov_mode_loopback_model;
   integer cov_missing_bins;

   localparam [5:0] TB_COV_FSM_ARB         = 6'b000001;
   localparam [5:0] TB_COV_FSM_TX_PREFETCH = 6'b000010;
   localparam [5:0] TB_COV_FSM_TX_BURST    = 6'b000100;
   localparam [5:0] TB_COV_FSM_RX_START    = 6'b001000;
   localparam [5:0] TB_COV_FSM_RX_BURST    = 6'b010000;
   localparam [5:0] TB_COV_FSM_TURNAROUND  = 6'b100000;

   localparam integer TB_COV_MODE_NORMAL   = 0;
   localparam integer TB_COV_MODE_LOOPBACK = 1;
   localparam integer TB_COV_KEEP_ZERO     = 0;
   localparam integer TB_COV_KEEP_FULL     = 1;
   localparam integer TB_COV_KEEP_PARTIAL  = 2;
   localparam integer TB_COV_LEN_SHORT     = 0;
   localparam integer TB_COV_LEN_LONG      = 1;
   localparam integer TB_COV_SRC_NORMAL    = 0;
   localparam integer TB_COV_SRC_LOOPBACK  = 1;
   localparam integer TB_COV_SRC_STATUS    = 2;
   localparam integer TB_COV_DIR_TX        = 0;
   localparam integer TB_COV_DIR_RX        = 1;
   localparam integer TB_COV_DIR_TURN      = 2;
   localparam integer TB_COV_ROUTE_SERVICE = 0;
   localparam integer TB_COV_ROUTE_PAYLOAD = 1;
   localparam integer TB_COV_FSM_CAUSE_IDLE        = 0;
   localparam integer TB_COV_FSM_CAUSE_TX_REQUEST  = 1;
   localparam integer TB_COV_FSM_CAUSE_RX_REQUEST  = 2;
   localparam integer TB_COV_FSM_CAUSE_RX_TAKEOVER = 3;
   localparam integer TB_COV_FSM_CAUSE_RX_COMPLETE = 4;
   localparam integer TB_COV_AXIS_FT_RX            = 0;
   localparam integer TB_COV_AXIS_NORMAL           = 1;
   localparam integer TB_COV_AXIS_LOOPBACK_PAYLOAD = 2;
   localparam integer TB_COV_AXIS_LOOPBACK         = 3;
   localparam integer TB_COV_AXIS_STATUS           = 4;
   localparam integer TB_COV_AXIS_TX               = 5;
   localparam integer TB_COV_IGNORE                = 0;

   localparam integer TB_COV_RESET_BOOT_NORMAL = 1;

   localparam integer TB_COV_CMD_NORMAL_GET_STATUS     = 1;
   localparam integer TB_COV_CMD_NORMAL_SET_LOOPBACK   = 2;
   localparam integer TB_COV_CMD_NORMAL_CLEAR_ERROR    = 3;
   localparam integer TB_COV_CMD_NORMAL_FT601_RESET    = 4;
   localparam integer TB_COV_CMD_LOOPBACK_GET_STATUS   = 5;
   localparam integer TB_COV_CMD_LOOPBACK_SET_NORMAL   = 6;
   localparam integer TB_COV_CMD_LOOPBACK_CLEAR_ERROR  = 7;
   localparam integer TB_COV_CMD_LOOPBACK_FT601_RESET  = 8;

   localparam integer TB_COV_STATUS_STALE_NONE    = 1;
   localparam integer TB_COV_STATUS_STALE_PAYLOAD = 2;
   localparam integer TB_COV_STATUS_WINDOW_OPEN   = 3;

   localparam integer TB_COV_MODE_SWITCH_ACTIVE_TRAFFIC = 1;

   localparam integer TB_COV_PAYLOAD_KEEP_NORMAL_FULL      = 1;
   localparam integer TB_COV_PAYLOAD_KEEP_NORMAL_PARTIAL   = 2;
   localparam integer TB_COV_PAYLOAD_KEEP_LOOPBACK_FULL    = 3;
   localparam integer TB_COV_PAYLOAD_KEEP_LOOPBACK_PARTIAL = 4;
   localparam integer TB_COV_PAYLOAD_LEN_LOOPBACK_SHORT    = 11;
   localparam integer TB_COV_PAYLOAD_LEN_LOOPBACK_LONG     = 12;

   localparam integer TB_COV_BACKPRESSURE_RXF_NORMAL   = 1;
   localparam integer TB_COV_BACKPRESSURE_RXF_LOOPBACK = 2;
   localparam integer TB_COV_BACKPRESSURE_TXE_NORMAL   = 11;
   localparam integer TB_COV_BACKPRESSURE_TXE_LOOPBACK = 12;
   localparam integer TB_COV_BACKPRESSURE_TXE_STATUS   = 13;

   localparam integer TB_COV_FT_DIR_TX         = 1;
   localparam integer TB_COV_FT_DIR_RX         = 2;
   localparam integer TB_COV_FT_DIR_TURNAROUND = 3;

   localparam integer TB_COV_ARB_NORMAL_READY    = 1;
   localparam integer TB_COV_ARB_NORMAL_STALL    = 2;
   localparam integer TB_COV_ARB_LOOPBACK_READY  = 3;
   localparam integer TB_COV_ARB_LOOPBACK_STALL  = 4;
   localparam integer TB_COV_ARB_STATUS_READY    = 5;
   localparam integer TB_COV_ARB_STATUS_STALL    = 6;

   localparam integer TB_COV_ROUTER_SERVICE_NORMAL           = 1;
   localparam integer TB_COV_ROUTER_SERVICE_LOOPBACK         = 2;
   localparam integer TB_COV_ROUTER_PAYLOAD_LOOPBACK_FULL    = 3;
   localparam integer TB_COV_ROUTER_PAYLOAD_LOOPBACK_PARTIAL = 4;

   localparam integer TB_COV_FSM_TRANS_ARB_IDLE        = 1;
   localparam integer TB_COV_FSM_TRANS_TX_FROM_ARB     = 2;
   localparam integer TB_COV_FSM_TRANS_RX_FROM_ARB     = 3;
   localparam integer TB_COV_FSM_TRANS_TURN_FROM_TX    = 4;
   localparam integer TB_COV_FSM_TRANS_TURN_FROM_RX    = 5;

   localparam integer TB_COV_AXIS_STALL_NORMAL   = 1;
   localparam integer TB_COV_AXIS_STALL_LOOPBACK = 2;
   localparam integer TB_COV_AXIS_STALL_TX       = 3;

   function automatic integer tb_cov_mode_class(input loopback_mode_i);
      begin
         tb_cov_mode_class = loopback_mode_i ? TB_COV_MODE_LOOPBACK : TB_COV_MODE_NORMAL;
      end
   endfunction

   function automatic integer tb_cov_keep_class(input [BE_LEN-1:0] keep_i);
      begin
         if (keep_i == FULL_BE)
            tb_cov_keep_class = TB_COV_KEEP_FULL;
         else if (keep_i != {BE_LEN{1'b0}})
            tb_cov_keep_class = TB_COV_KEEP_PARTIAL;
         else
            tb_cov_keep_class = TB_COV_KEEP_ZERO;
      end
   endfunction

   function automatic integer tb_cov_len_class(input integer payload_words);
      begin
         tb_cov_len_class = (payload_words > 1024) ? TB_COV_LEN_LONG : TB_COV_LEN_SHORT;
      end
   endfunction

   function automatic integer tb_cov_selected_source_class;
      begin
         if (dut.status_frame_active || dut.status_req)
            tb_cov_selected_source_class = TB_COV_SRC_STATUS;
         else if (dut.loopback_mode_ft)
            tb_cov_selected_source_class = TB_COV_SRC_LOOPBACK;
         else
            tb_cov_selected_source_class = TB_COV_SRC_NORMAL;
      end
   endfunction

   function automatic integer tb_cov_command_event(
      input integer mode_i,
      input [DATA_LEN-1:0] cmd_i
   );
      begin
         tb_cov_command_event = TB_COV_IGNORE;
         if (mode_i == TB_COV_MODE_NORMAL) begin
            if (cmd_i == CMD_GET_STATUS)
               tb_cov_command_event = TB_COV_CMD_NORMAL_GET_STATUS;
            else if (cmd_i == CMD_SET_LOOPBACK)
               tb_cov_command_event = TB_COV_CMD_NORMAL_SET_LOOPBACK;
            else if (cmd_i == CMD_CLR_SERVICE_ERROR)
               tb_cov_command_event = TB_COV_CMD_NORMAL_CLEAR_ERROR;
            else if (cmd_i == CMD_FT601_RESET)
               tb_cov_command_event = TB_COV_CMD_NORMAL_FT601_RESET;
         end
         else if (mode_i == TB_COV_MODE_LOOPBACK) begin
            if (cmd_i == CMD_GET_STATUS)
               tb_cov_command_event = TB_COV_CMD_LOOPBACK_GET_STATUS;
            else if (cmd_i == CMD_SET_NORMAL)
               tb_cov_command_event = TB_COV_CMD_LOOPBACK_SET_NORMAL;
            else if (cmd_i == CMD_CLR_SERVICE_ERROR)
               tb_cov_command_event = TB_COV_CMD_LOOPBACK_CLEAR_ERROR;
            else if (cmd_i == CMD_FT601_RESET)
               tb_cov_command_event = TB_COV_CMD_LOOPBACK_FT601_RESET;
         end
      end
   endfunction

   function automatic integer tb_cov_status_stale_event(input integer stale_words_i);
      begin
         tb_cov_status_stale_event = (stale_words_i == 0) ?
                                     TB_COV_STATUS_STALE_NONE :
                                     TB_COV_STATUS_STALE_PAYLOAD;
      end
   endfunction

   function automatic integer tb_cov_status_window_event(
      input integer txe_opened_i,
      input integer fsm_idle_i
   );
      begin
         tb_cov_status_window_event = (txe_opened_i && fsm_idle_i) ?
                                      TB_COV_STATUS_WINDOW_OPEN :
                                      TB_COV_IGNORE;
      end
   endfunction

   function automatic integer tb_cov_payload_keep_event(
      input integer payload_kind_i,
      input [BE_LEN-1:0] keep_i
   );
      integer keep_class_i;
      begin
         keep_class_i = tb_cov_keep_class(keep_i);
         tb_cov_payload_keep_event = TB_COV_IGNORE;
         if (payload_kind_i == TB_COV_MODE_NORMAL) begin
            if (keep_class_i == TB_COV_KEEP_FULL)
               tb_cov_payload_keep_event = TB_COV_PAYLOAD_KEEP_NORMAL_FULL;
            else if (keep_class_i == TB_COV_KEEP_PARTIAL)
               tb_cov_payload_keep_event = TB_COV_PAYLOAD_KEEP_NORMAL_PARTIAL;
         end
         else if (payload_kind_i == TB_COV_MODE_LOOPBACK) begin
            if (keep_class_i == TB_COV_KEEP_FULL)
               tb_cov_payload_keep_event = TB_COV_PAYLOAD_KEEP_LOOPBACK_FULL;
            else if (keep_class_i == TB_COV_KEEP_PARTIAL)
               tb_cov_payload_keep_event = TB_COV_PAYLOAD_KEEP_LOOPBACK_PARTIAL;
         end
      end
   endfunction

   function automatic integer tb_cov_payload_len_event(
      input integer payload_kind_i,
      input integer length_class_i
   );
      begin
         tb_cov_payload_len_event = TB_COV_IGNORE;
         if (payload_kind_i == TB_COV_MODE_LOOPBACK) begin
            if (length_class_i == TB_COV_LEN_LONG)
               tb_cov_payload_len_event = TB_COV_PAYLOAD_LEN_LOOPBACK_LONG;
            else
               tb_cov_payload_len_event = TB_COV_PAYLOAD_LEN_LOOPBACK_SHORT;
         end
      end
   endfunction

   function automatic integer tb_cov_backpressure_rxf_event(
      input integer rxf_seen_i,
      input integer mode_i
   );
      begin
         tb_cov_backpressure_rxf_event = TB_COV_IGNORE;
         if (rxf_seen_i) begin
            if (mode_i == TB_COV_MODE_LOOPBACK)
               tb_cov_backpressure_rxf_event = TB_COV_BACKPRESSURE_RXF_LOOPBACK;
            else
               tb_cov_backpressure_rxf_event = TB_COV_BACKPRESSURE_RXF_NORMAL;
         end
      end
   endfunction

   function automatic integer tb_cov_backpressure_txe_event(
      input integer txe_seen_i,
      input integer source_i
   );
      begin
         tb_cov_backpressure_txe_event = TB_COV_IGNORE;
         if (txe_seen_i) begin
            if (source_i == TB_COV_SRC_STATUS)
               tb_cov_backpressure_txe_event = TB_COV_BACKPRESSURE_TXE_STATUS;
            else if (source_i == TB_COV_SRC_LOOPBACK)
               tb_cov_backpressure_txe_event = TB_COV_BACKPRESSURE_TXE_LOOPBACK;
            else
               tb_cov_backpressure_txe_event = TB_COV_BACKPRESSURE_TXE_NORMAL;
         end
      end
   endfunction

   function automatic integer tb_cov_direction_event(
      input integer direction_i,
      input integer turnaround_i
   );
      begin
         tb_cov_direction_event = TB_COV_IGNORE;
         if ((direction_i == TB_COV_DIR_TX) && !turnaround_i)
            tb_cov_direction_event = TB_COV_FT_DIR_TX;
         else if ((direction_i == TB_COV_DIR_RX) && !turnaround_i)
            tb_cov_direction_event = TB_COV_FT_DIR_RX;
         else if ((direction_i == TB_COV_DIR_TURN) && turnaround_i)
            tb_cov_direction_event = TB_COV_FT_DIR_TURNAROUND;
      end
   endfunction

   function automatic integer tb_cov_arbiter_event(
      input integer source_i,
      input integer downstream_ready_i
   );
      begin
         tb_cov_arbiter_event = TB_COV_IGNORE;
         if (source_i == TB_COV_SRC_STATUS)
            tb_cov_arbiter_event = downstream_ready_i ? TB_COV_ARB_STATUS_READY :
                                                       TB_COV_ARB_STATUS_STALL;
         else if (source_i == TB_COV_SRC_LOOPBACK)
            tb_cov_arbiter_event = downstream_ready_i ? TB_COV_ARB_LOOPBACK_READY :
                                                       TB_COV_ARB_LOOPBACK_STALL;
         else if (source_i == TB_COV_SRC_NORMAL)
            tb_cov_arbiter_event = downstream_ready_i ? TB_COV_ARB_NORMAL_READY :
                                                       TB_COV_ARB_NORMAL_STALL;
      end
   endfunction

   function automatic integer tb_cov_router_event(
      input integer route_i,
      input integer mode_i,
      input integer keep_class_i
   );
      begin
         tb_cov_router_event = TB_COV_IGNORE;
         if ((route_i == TB_COV_ROUTE_SERVICE) && (mode_i == TB_COV_MODE_NORMAL))
            tb_cov_router_event = TB_COV_ROUTER_SERVICE_NORMAL;
         else if ((route_i == TB_COV_ROUTE_SERVICE) && (mode_i == TB_COV_MODE_LOOPBACK))
            tb_cov_router_event = TB_COV_ROUTER_SERVICE_LOOPBACK;
         else if ((route_i == TB_COV_ROUTE_PAYLOAD) &&
                  (mode_i == TB_COV_MODE_LOOPBACK) &&
                  (keep_class_i == TB_COV_KEEP_FULL))
            tb_cov_router_event = TB_COV_ROUTER_PAYLOAD_LOOPBACK_FULL;
         else if ((route_i == TB_COV_ROUTE_PAYLOAD) &&
                  (mode_i == TB_COV_MODE_LOOPBACK) &&
                  (keep_class_i == TB_COV_KEEP_PARTIAL))
            tb_cov_router_event = TB_COV_ROUTER_PAYLOAD_LOOPBACK_PARTIAL;
      end
   endfunction

   function automatic integer tb_cov_fsm_transition_event(
      input [5:0] state_i,
      input integer cause_i
   );
      begin
         tb_cov_fsm_transition_event = TB_COV_IGNORE;
         if ((state_i == TB_COV_FSM_ARB) &&
             (cause_i == TB_COV_FSM_CAUSE_IDLE))
            tb_cov_fsm_transition_event = TB_COV_FSM_TRANS_ARB_IDLE;
         else if ((state_i == TB_COV_FSM_TX_PREFETCH) &&
                  (cause_i == TB_COV_FSM_CAUSE_TX_REQUEST))
            tb_cov_fsm_transition_event = TB_COV_FSM_TRANS_TX_FROM_ARB;
         else if ((state_i == TB_COV_FSM_RX_START) &&
                  (cause_i == TB_COV_FSM_CAUSE_RX_REQUEST))
            tb_cov_fsm_transition_event = TB_COV_FSM_TRANS_RX_FROM_ARB;
         else if ((state_i == TB_COV_FSM_TURNAROUND) &&
                  (cause_i == TB_COV_FSM_CAUSE_RX_TAKEOVER))
            tb_cov_fsm_transition_event = TB_COV_FSM_TRANS_TURN_FROM_TX;
         else if ((state_i == TB_COV_FSM_TURNAROUND) &&
                  (cause_i == TB_COV_FSM_CAUSE_RX_COMPLETE))
            tb_cov_fsm_transition_event = TB_COV_FSM_TRANS_TURN_FROM_RX;
      end
   endfunction

   function automatic integer tb_cov_axis_stall_event(
      input integer stream_i,
      input integer stall_seen_i
   );
      begin
         tb_cov_axis_stall_event = TB_COV_IGNORE;
         if (stall_seen_i) begin
            if (stream_i == TB_COV_AXIS_NORMAL)
               tb_cov_axis_stall_event = TB_COV_AXIS_STALL_NORMAL;
            else if (stream_i == TB_COV_AXIS_LOOPBACK)
               tb_cov_axis_stall_event = TB_COV_AXIS_STALL_LOOPBACK;
            else if (stream_i == TB_COV_AXIS_TX)
               tb_cov_axis_stall_event = TB_COV_AXIS_STALL_TX;
         end
      end
   endfunction

`ifdef TB_HAS_SV_COVERGROUP
   // REQ: reset_boot_normal - FPGA_RESET releases the DUT into normal mode.
   covergroup tb_cov_reset_cg with function sample(int reset_event_i);
      option.per_instance = 1;
      option.name = "tb_cov_reset";
      cp_reset_req: coverpoint reset_event_i {
         bins reset_boot_normal = {TB_COV_RESET_BOOT_NORMAL};
      }
   endgroup

   // REQ: diagnostics/control - supported service commands in legal modes.
   covergroup tb_cov_command_cg with function sample(int command_event_i);
      option.per_instance = 1;
      option.name = "tb_cov_command";
      cp_command_req: coverpoint command_event_i {
         bins normal_get_status = {TB_COV_CMD_NORMAL_GET_STATUS};
         bins normal_set_loopback = {TB_COV_CMD_NORMAL_SET_LOOPBACK};
         bins normal_clear_error = {TB_COV_CMD_NORMAL_CLEAR_ERROR};
         bins normal_ft601_reset = {TB_COV_CMD_NORMAL_FT601_RESET};
         bins loopback_get_status = {TB_COV_CMD_LOOPBACK_GET_STATUS};
         bins loopback_set_normal = {TB_COV_CMD_LOOPBACK_SET_NORMAL};
         bins loopback_clear_error = {TB_COV_CMD_LOOPBACK_CLEAR_ERROR};
         bins loopback_ft601_reset = {TB_COV_CMD_LOOPBACK_FT601_RESET};
      }
   endgroup

   // REQ: diagnostics/status - status frame discovery and service window release.
   covergroup tb_cov_status_cg with function sample(int status_event_i);
      option.per_instance = 1;
      option.name = "tb_cov_status";
      cp_status_req: coverpoint status_event_i {
         bins stale_prefix_none = {TB_COV_STATUS_STALE_NONE};
         bins stale_prefix_payload = {TB_COV_STATUS_STALE_PAYLOAD};
         bins txe_opened_fsm_idle = {TB_COV_STATUS_WINDOW_OPEN};
      }
   endgroup

   // REQ: mode switch policy - mode changes while FT traffic is active.
   covergroup tb_cov_mode_switch_cg with function sample(int mode_switch_event_i);
      option.per_instance = 1;
      option.name = "tb_cov_mode_switch";
      cp_mode_switch_req: coverpoint mode_switch_event_i {
         bins active_ft_traffic = {TB_COV_MODE_SWITCH_ACTIVE_TRAFFIC};
      }
   endgroup

   // REQ: normal/loopback payload - byte-enable masks and loopback length classes.
   covergroup tb_cov_payload_cg with function sample(int keep_event_i,
                                                     int length_event_i);
      option.per_instance = 1;
      option.name = "tb_cov_payload";
      cp_payload_keep_req: coverpoint keep_event_i {
         bins normal_full = {TB_COV_PAYLOAD_KEEP_NORMAL_FULL};
         bins normal_partial = {TB_COV_PAYLOAD_KEEP_NORMAL_PARTIAL};
         bins loopback_full = {TB_COV_PAYLOAD_KEEP_LOOPBACK_FULL};
         bins loopback_partial = {TB_COV_PAYLOAD_KEEP_LOOPBACK_PARTIAL};
      }
      cp_loopback_len_req: coverpoint length_event_i {
         bins loopback_short = {TB_COV_PAYLOAD_LEN_LOOPBACK_SHORT};
         bins loopback_long = {TB_COV_PAYLOAD_LEN_LOOPBACK_LONG};
      }
   endgroup

   // REQ: FT601 backpressure - RXF_N/TXE_N closure in normal, loopback, and status paths.
   covergroup tb_cov_backpressure_cg with function sample(int rxf_event_i,
                                                          int txe_event_i);
      option.per_instance = 1;
      option.name = "tb_cov_backpressure";
      cp_rxf_req: coverpoint rxf_event_i {
         bins normal = {TB_COV_BACKPRESSURE_RXF_NORMAL};
         bins loopback = {TB_COV_BACKPRESSURE_RXF_LOOPBACK};
      }
      cp_txe_req: coverpoint txe_event_i {
         bins normal = {TB_COV_BACKPRESSURE_TXE_NORMAL};
         bins loopback = {TB_COV_BACKPRESSURE_TXE_LOOPBACK};
         bins status = {TB_COV_BACKPRESSURE_TXE_STATUS};
      }
   endgroup

   // REQ: FT601 boundary - TX, RX, and turnaround bus direction phases are observed.
   covergroup tb_cov_ft601_direction_cg with function sample(int direction_event_i);
      option.per_instance = 1;
      option.name = "tb_cov_ft601_direction";
      cp_direction_req: coverpoint direction_event_i {
         bins tx = {TB_COV_FT_DIR_TX};
         bins rx = {TB_COV_FT_DIR_RX};
         bins turnaround = {TB_COV_FT_DIR_TURNAROUND};
      }
   endgroup

   // REQ: TX arbiter - selected sources are observed with ready and stall.
   covergroup tb_cov_arbiter_cg with function sample(int arbiter_event_i);
      option.per_instance = 1;
      option.name = "tb_cov_arbiter";
      cp_arbiter_req: coverpoint arbiter_event_i {
         bins normal_ready = {TB_COV_ARB_NORMAL_READY};
         bins normal_stall = {TB_COV_ARB_NORMAL_STALL};
         bins loopback_ready = {TB_COV_ARB_LOOPBACK_READY};
         bins loopback_stall = {TB_COV_ARB_LOOPBACK_STALL};
         bins status_ready = {TB_COV_ARB_STATUS_READY};
         bins status_stall = {TB_COV_ARB_STATUS_STALL};
      }
   endgroup

   // REQ: RX router - service frames and loopback payload are demuxed by mode and keep.
   covergroup tb_cov_router_cg with function sample(int router_event_i);
      option.per_instance = 1;
      option.name = "tb_cov_router";
      cp_router_req: coverpoint router_event_i {
         bins service_normal = {TB_COV_ROUTER_SERVICE_NORMAL};
         bins service_loopback = {TB_COV_ROUTER_SERVICE_LOOPBACK};
         bins payload_loopback_full = {TB_COV_ROUTER_PAYLOAD_LOOPBACK_FULL};
         bins payload_loopback_partial = {TB_COV_ROUTER_PAYLOAD_LOOPBACK_PARTIAL};
      }
   endgroup

   // REQ: FT601 FSM - all legal states and requirement-level transitions are observed.
   covergroup tb_cov_fsm_cg with function sample(logic [5:0] state_i,
                                                 int transition_event_i);
      option.per_instance = 1;
      option.name = "tb_cov_fsm";
      cp_state: coverpoint state_i {
         bins arb = {TB_COV_FSM_ARB};
         bins tx_prefetch = {TB_COV_FSM_TX_PREFETCH};
         bins tx_burst = {TB_COV_FSM_TX_BURST};
         bins rx_start = {TB_COV_FSM_RX_START};
         bins rx_burst = {TB_COV_FSM_RX_BURST};
         bins turnaround = {TB_COV_FSM_TURNAROUND};
      }
      cp_transition_req: coverpoint transition_event_i {
         bins arb_idle = {TB_COV_FSM_TRANS_ARB_IDLE};
         bins tx_from_arb = {TB_COV_FSM_TRANS_TX_FROM_ARB};
         bins rx_from_arb = {TB_COV_FSM_TRANS_RX_FROM_ARB};
         bins turnaround_from_tx = {TB_COV_FSM_TRANS_TURN_FROM_TX};
         bins turnaround_from_rx = {TB_COV_FSM_TRANS_TURN_FROM_RX};
      }
   endgroup

   // REQ: AXIS-like streams - all monitored streams are seen and required stalls occur.
   covergroup tb_cov_axis_cg with function sample(int stream_i,
                                                  int stall_event_i);
      option.per_instance = 1;
      option.name = "tb_cov_axis";
      cp_stream: coverpoint stream_i {
         bins ft_rx = {TB_COV_AXIS_FT_RX};
         bins normal = {TB_COV_AXIS_NORMAL};
         bins loopback_payload = {TB_COV_AXIS_LOOPBACK_PAYLOAD};
         bins loopback = {TB_COV_AXIS_LOOPBACK};
         bins status = {TB_COV_AXIS_STATUS};
         bins tx = {TB_COV_AXIS_TX};
      }
      cp_stall_req: coverpoint stall_event_i {
         bins normal_stall = {TB_COV_AXIS_STALL_NORMAL};
         bins loopback_stall = {TB_COV_AXIS_STALL_LOOPBACK};
         bins tx_stall = {TB_COV_AXIS_STALL_TX};
      }
   endgroup

   tb_cov_reset_cg           native_reset_cg = new();
   tb_cov_command_cg         native_command_cg = new();
   tb_cov_status_cg          native_status_cg = new();
   tb_cov_mode_switch_cg     native_mode_switch_cg = new();
   tb_cov_payload_cg         native_payload_cg = new();
   tb_cov_backpressure_cg    native_backpressure_cg = new();
   tb_cov_ft601_direction_cg native_ft601_direction_cg = new();
   tb_cov_arbiter_cg         native_arbiter_cg = new();
   tb_cov_router_cg          native_router_cg = new();
   tb_cov_fsm_cg             native_fsm_cg = new();
   tb_cov_axis_cg            native_axis_cg = new();
`endif

   task coverage_powerup_init;
      begin
         cov_main_reset_boot_normal = 0;
         cov_main_normal_path = 0;
         cov_main_loopback_path = 0;
         cov_main_service_control = 0;

         cov_cmd_normal_get_status = 0;
         cov_cmd_normal_set_loopback = 0;
         cov_cmd_normal_clear = 0;
         cov_cmd_normal_ft601_reset = 0;
         cov_cmd_loopback_get_status = 0;
         cov_cmd_loopback_set_normal = 0;
         cov_cmd_loopback_clear = 0;
         cov_cmd_loopback_ft601_reset = 0;

         cov_get_status_pending_payload = 0;
         cov_txe_backpressure = 0;
         cov_rxf_backpressure = 0;

         cov_req_reset_normal_mode = 0;
         cov_req_get_status_stale_none = 0;
         cov_req_get_status_stale_payload = 0;
         cov_req_status_window_txe_opened_idle = 0;
         cov_req_mode_switch_active_ft_traffic = 0;
         cov_req_normal_payload_keep_full = 0;
         cov_req_normal_payload_keep_partial = 0;
         cov_req_loopback_payload_keep_full = 0;
         cov_req_loopback_payload_keep_partial = 0;
         cov_req_loopback_payload_len_short = 0;
         cov_req_loopback_payload_len_long = 0;
         cov_req_rxf_backpressure_normal = 0;
         cov_req_rxf_backpressure_loopback = 0;
         cov_req_txe_backpressure_normal = 0;
         cov_req_txe_backpressure_loopback = 0;
         cov_req_txe_backpressure_status = 0;
         cov_req_ft_direction_tx = 0;
         cov_req_ft_direction_rx = 0;
         cov_req_ft_direction_turnaround = 0;
         cov_req_arbiter_status_ready = 0;
         cov_req_arbiter_loopback_ready = 0;
         cov_req_arbiter_normal_ready = 0;
         cov_req_router_service_normal = 0;
         cov_req_router_service_loopback = 0;
         cov_req_router_payload_loopback_full = 0;
         cov_req_router_payload_loopback_partial = 0;
         cov_req_fsm_arb_idle = 0;
         cov_req_fsm_tx_from_arb = 0;
         cov_req_fsm_rx_from_arb = 0;
         cov_req_fsm_turnaround_from_tx = 0;
         cov_req_fsm_turnaround_from_rx = 0;
         cov_req_axis_stall_seen = 0;

         cov_req_ft601_turnaround_rx_priority = 0;
         cov_req_ft601_rxf_boundary = 0;
         cov_req_payload_long_gapped_loopback = 0;
         cov_req_control_status_window = 0;
         cov_req_control_mode_switch_idle = 0;
         cov_req_control_router_demux = 0;
         cov_req_control_unknown_opcode = 0;
         cov_req_control_arbiter_priority = 0;

         cov_mode_loopback_model = 0;
         cov_missing_bins = 0;
      end
   endtask

   task tb_cov_set_normal_mode;
      begin
         cov_mode_loopback_model = 0;
      end
   endtask

   task tb_cov_mark_main_reset_boot_normal; begin cov_main_reset_boot_normal = cov_main_reset_boot_normal + 1; end endtask
   task tb_cov_mark_main_normal_path;       begin cov_main_normal_path = cov_main_normal_path + 1; end endtask
   task tb_cov_mark_main_loopback_path;     begin cov_main_loopback_path = cov_main_loopback_path + 1; end endtask
   task tb_cov_mark_main_service_control;   begin cov_main_service_control = cov_main_service_control + 1; end endtask

   task tb_cov_mark_reset_normal_mode;
      begin
         cov_req_reset_normal_mode = cov_req_reset_normal_mode + 1;
`ifdef TB_HAS_SV_COVERGROUP
         native_reset_cg.sample(TB_COV_RESET_BOOT_NORMAL);
`endif
      end
   endtask

   task tb_cov_mark_get_status_pending_payload;
      begin
         cov_get_status_pending_payload = cov_get_status_pending_payload + 1;
      end
   endtask

   task tb_cov_mark_get_status_stale_prefix(input integer stale_words);
      begin
         if (stale_words == 0)
            cov_req_get_status_stale_none = cov_req_get_status_stale_none + 1;
         else
            cov_req_get_status_stale_payload = cov_req_get_status_stale_payload + 1;
`ifdef TB_HAS_SV_COVERGROUP
         native_status_cg.sample(tb_cov_status_stale_event(stale_words));
`endif
      end
   endtask

   task tb_cov_mark_status_window_release(
      input txe_opened,
      input fsm_idle
   );
      begin
         if (txe_opened && fsm_idle)
            cov_req_status_window_txe_opened_idle = cov_req_status_window_txe_opened_idle + 1;
`ifdef TB_HAS_SV_COVERGROUP
         native_status_cg.sample(tb_cov_status_window_event(txe_opened, fsm_idle));
`endif
      end
   endtask

   task tb_cov_mark_mode_switch_active_traffic;
      begin
         cov_req_mode_switch_active_ft_traffic = cov_req_mode_switch_active_ft_traffic + 1;
`ifdef TB_HAS_SV_COVERGROUP
         native_mode_switch_cg.sample(TB_COV_MODE_SWITCH_ACTIVE_TRAFFIC);
`endif
      end
   endtask

   task tb_cov_mark_normal_payload_keep(input [BE_LEN-1:0] keep_i);
      begin
         if (keep_i == FULL_BE)
            cov_req_normal_payload_keep_full = cov_req_normal_payload_keep_full + 1;
         else if (keep_i != {BE_LEN{1'b0}})
            cov_req_normal_payload_keep_partial = cov_req_normal_payload_keep_partial + 1;
`ifdef TB_HAS_SV_COVERGROUP
         native_payload_cg.sample(tb_cov_payload_keep_event(TB_COV_MODE_NORMAL, keep_i),
                                  TB_COV_IGNORE);
`endif
      end
   endtask

   task tb_cov_mark_loopback_payload(
      input [BE_LEN-1:0] keep_i,
      input integer      payload_words
   );
      begin
         if (keep_i == FULL_BE)
            cov_req_loopback_payload_keep_full = cov_req_loopback_payload_keep_full + 1;
         else if (keep_i != {BE_LEN{1'b0}})
            cov_req_loopback_payload_keep_partial = cov_req_loopback_payload_keep_partial + 1;

         if (payload_words > 1024)
            cov_req_loopback_payload_len_long = cov_req_loopback_payload_len_long + 1;
         else if (payload_words > 0)
            cov_req_loopback_payload_len_short = cov_req_loopback_payload_len_short + 1;
`ifdef TB_HAS_SV_COVERGROUP
         native_payload_cg.sample(tb_cov_payload_keep_event(TB_COV_MODE_LOOPBACK, keep_i),
                                  tb_cov_payload_len_event(TB_COV_MODE_LOOPBACK,
                                                           tb_cov_len_class(payload_words)));
`endif
      end
   endtask

   task tb_cov_mark_txe_backpressure;
      begin
         cov_txe_backpressure = cov_txe_backpressure + 1;
         if (dut.status_frame_active || dut.status_req)
            cov_req_txe_backpressure_status = cov_req_txe_backpressure_status + 1;
         else if (dut.loopback_mode_ft)
            cov_req_txe_backpressure_loopback = cov_req_txe_backpressure_loopback + 1;
         else
            cov_req_txe_backpressure_normal = cov_req_txe_backpressure_normal + 1;
`ifdef TB_HAS_SV_COVERGROUP
         native_backpressure_cg.sample(TB_COV_IGNORE,
                                       tb_cov_backpressure_txe_event(1,
                                                                     tb_cov_selected_source_class()));
`endif
      end
   endtask

   task tb_cov_mark_rxf_backpressure;
      begin
         cov_rxf_backpressure = cov_rxf_backpressure + 1;
         if (dut.loopback_mode_ft)
            cov_req_rxf_backpressure_loopback = cov_req_rxf_backpressure_loopback + 1;
         else
            cov_req_rxf_backpressure_normal = cov_req_rxf_backpressure_normal + 1;
`ifdef TB_HAS_SV_COVERGROUP
         native_backpressure_cg.sample(tb_cov_backpressure_rxf_event(1,
                                                                     tb_cov_mode_class(dut.loopback_mode_ft)),
                                       TB_COV_IGNORE);
`endif
      end
   endtask

   task tb_cov_mark_req_ft601_turnaround_rx_priority; begin cov_req_ft601_turnaround_rx_priority = cov_req_ft601_turnaround_rx_priority + 1; end endtask
   task tb_cov_mark_req_ft601_rxf_boundary;           begin cov_req_ft601_rxf_boundary = cov_req_ft601_rxf_boundary + 1; end endtask
   task tb_cov_mark_req_payload_long_gapped_loopback;  begin cov_req_payload_long_gapped_loopback = cov_req_payload_long_gapped_loopback + 1; end endtask
   task tb_cov_mark_req_control_status_window;         begin cov_req_control_status_window = cov_req_control_status_window + 1; end endtask
   task tb_cov_mark_req_control_mode_switch_idle;      begin cov_req_control_mode_switch_idle = cov_req_control_mode_switch_idle + 1; end endtask
   task tb_cov_mark_req_control_router_demux;          begin cov_req_control_router_demux = cov_req_control_router_demux + 1; end endtask
   task tb_cov_mark_req_control_unknown_opcode;        begin cov_req_control_unknown_opcode = cov_req_control_unknown_opcode + 1; end endtask
   task tb_cov_mark_req_control_arbiter_priority;      begin cov_req_control_arbiter_priority = cov_req_control_arbiter_priority + 1; end endtask

   task tb_cov_mark_command(input [DATA_LEN-1:0] cmd_word);
      begin
`ifdef TB_HAS_SV_COVERGROUP
         native_command_cg.sample(tb_cov_command_event(tb_cov_mode_class(cov_mode_loopback_model),
                                                       cmd_word));
`endif
         if (cov_mode_loopback_model == 0) begin
            if (cmd_word == CMD_GET_STATUS)
               cov_cmd_normal_get_status = cov_cmd_normal_get_status + 1;
            else if (cmd_word == CMD_SET_LOOPBACK)
               cov_cmd_normal_set_loopback = cov_cmd_normal_set_loopback + 1;
            else if (cmd_word == CMD_CLR_SERVICE_ERROR)
               cov_cmd_normal_clear = cov_cmd_normal_clear + 1;
            else if (cmd_word == CMD_FT601_RESET)
               cov_cmd_normal_ft601_reset = cov_cmd_normal_ft601_reset + 1;
         end
         else begin
            if (cmd_word == CMD_GET_STATUS)
               cov_cmd_loopback_get_status = cov_cmd_loopback_get_status + 1;
            else if (cmd_word == CMD_SET_NORMAL)
               cov_cmd_loopback_set_normal = cov_cmd_loopback_set_normal + 1;
            else if (cmd_word == CMD_CLR_SERVICE_ERROR)
               cov_cmd_loopback_clear = cov_cmd_loopback_clear + 1;
            else if (cmd_word == CMD_FT601_RESET)
               cov_cmd_loopback_ft601_reset = cov_cmd_loopback_ft601_reset + 1;
         end

         if (cmd_word == CMD_SET_LOOPBACK)
            cov_mode_loopback_model = 1;
         else if (cmd_word == CMD_SET_NORMAL)
            cov_mode_loopback_model = 0;
      end
   endtask

   task tb_cov_sample_passive(input [5:0] prev_fsm_state_i);
      begin
         if (dut.ft_rst_n_i === 1'b1) begin
            if (ft601_mon.wr_n === 1'b0)
               cov_req_ft_direction_tx = cov_req_ft_direction_tx + 1;
            if ((ft601_mon.rd_n === 1'b0) || (ft601_mon.oe_n === 1'b0))
               cov_req_ft_direction_rx = cov_req_ft_direction_rx + 1;
            if (dut.ft601_fsm.state === TB_COV_FSM_TURNAROUND)
               cov_req_ft_direction_turnaround = cov_req_ft_direction_turnaround + 1;
`ifdef TB_HAS_SV_COVERGROUP
            if (ft601_mon.wr_n === 1'b0)
               native_ft601_direction_cg.sample(tb_cov_direction_event(TB_COV_DIR_TX, 0));
            if ((ft601_mon.rd_n === 1'b0) || (ft601_mon.oe_n === 1'b0))
               native_ft601_direction_cg.sample(tb_cov_direction_event(TB_COV_DIR_RX, 0));
            if (dut.ft601_fsm.state === TB_COV_FSM_TURNAROUND)
               native_ft601_direction_cg.sample(tb_cov_direction_event(TB_COV_DIR_TURN, 1));
`endif

            if ((ft601_mon.txe_n === 1'b1) &&
                (dut.status_frame_active || dut.status_req))
               cov_req_txe_backpressure_status = cov_req_txe_backpressure_status + 1;
`ifdef TB_HAS_SV_COVERGROUP
            if ((ft601_mon.txe_n === 1'b1) &&
                (dut.status_frame_active || dut.status_req))
               native_backpressure_cg.sample(TB_COV_IGNORE,
                                             tb_cov_backpressure_txe_event(1,
                                                                           TB_COV_SRC_STATUS));
`endif

            if (dut.axis_tx_arbiter.status_sel && dut.status_axis_tready)
               cov_req_arbiter_status_ready = cov_req_arbiter_status_ready + 1;
            if (dut.axis_tx_arbiter.loopback_sel && dut.loopback_axis_tready)
               cov_req_arbiter_loopback_ready = cov_req_arbiter_loopback_ready + 1;
            if (dut.axis_tx_arbiter.normal_sel && dut.normal_axis_tready)
               cov_req_arbiter_normal_ready = cov_req_arbiter_normal_ready + 1;
`ifdef TB_HAS_SV_COVERGROUP
            if (dut.axis_tx_arbiter.status_sel)
               native_arbiter_cg.sample(tb_cov_arbiter_event(TB_COV_SRC_STATUS,
                                                              dut.status_axis_tready));
            if (dut.axis_tx_arbiter.loopback_sel)
               native_arbiter_cg.sample(tb_cov_arbiter_event(TB_COV_SRC_LOOPBACK,
                                                              dut.loopback_axis_tready));
            if (dut.axis_tx_arbiter.normal_sel)
               native_arbiter_cg.sample(tb_cov_arbiter_event(TB_COV_SRC_NORMAL,
                                                              dut.normal_axis_tready));
`endif

            if (dut.cmd_event_valid) begin
               if (dut.loopback_mode_ft)
                  cov_req_router_service_loopback = cov_req_router_service_loopback + 1;
               else
                  cov_req_router_service_normal = cov_req_router_service_normal + 1;
`ifdef TB_HAS_SV_COVERGROUP
               native_router_cg.sample(tb_cov_router_event(TB_COV_ROUTE_SERVICE,
                                                           tb_cov_mode_class(dut.loopback_mode_ft),
                                                           TB_COV_KEEP_FULL));
`endif
            end

            if (loopback_payload_axis_mon.valid && loopback_payload_axis_mon.ready) begin
               if (loopback_payload_axis_mon.keep == FULL_BE)
                  cov_req_router_payload_loopback_full = cov_req_router_payload_loopback_full + 1;
               else if (loopback_payload_axis_mon.keep != {BE_LEN{1'b0}})
                  cov_req_router_payload_loopback_partial = cov_req_router_payload_loopback_partial + 1;
`ifdef TB_HAS_SV_COVERGROUP
               native_router_cg.sample(tb_cov_router_event(TB_COV_ROUTE_PAYLOAD,
                                                           TB_COV_MODE_LOOPBACK,
                                                           tb_cov_keep_class(loopback_payload_axis_mon.keep)));
`endif
            end

            if (dut.ft601_fsm.state === TB_COV_FSM_ARB)
               cov_req_fsm_arb_idle = cov_req_fsm_arb_idle + 1;
            if ((prev_fsm_state_i === TB_COV_FSM_ARB) &&
                (dut.ft601_fsm.state === TB_COV_FSM_TX_PREFETCH))
               cov_req_fsm_tx_from_arb = cov_req_fsm_tx_from_arb + 1;
            if ((prev_fsm_state_i === TB_COV_FSM_ARB) &&
                (dut.ft601_fsm.state === TB_COV_FSM_RX_START))
               cov_req_fsm_rx_from_arb = cov_req_fsm_rx_from_arb + 1;
            if (((prev_fsm_state_i === TB_COV_FSM_TX_PREFETCH) ||
                 (prev_fsm_state_i === TB_COV_FSM_TX_BURST)) &&
                (dut.ft601_fsm.state === TB_COV_FSM_TURNAROUND))
               cov_req_fsm_turnaround_from_tx = cov_req_fsm_turnaround_from_tx + 1;
            if ((prev_fsm_state_i === TB_COV_FSM_RX_BURST) &&
                (dut.ft601_fsm.state === TB_COV_FSM_TURNAROUND))
               cov_req_fsm_turnaround_from_rx = cov_req_fsm_turnaround_from_rx + 1;
`ifdef TB_HAS_SV_COVERGROUP
            native_fsm_cg.sample(dut.ft601_fsm.state, TB_COV_IGNORE);
            if (dut.ft601_fsm.state === TB_COV_FSM_ARB)
               native_fsm_cg.sample(dut.ft601_fsm.state,
                                     tb_cov_fsm_transition_event(dut.ft601_fsm.state,
                                                                 TB_COV_FSM_CAUSE_IDLE));
            if ((prev_fsm_state_i === TB_COV_FSM_ARB) &&
                (dut.ft601_fsm.state === TB_COV_FSM_TX_PREFETCH))
               native_fsm_cg.sample(dut.ft601_fsm.state,
                                     tb_cov_fsm_transition_event(dut.ft601_fsm.state,
                                                                 TB_COV_FSM_CAUSE_TX_REQUEST));
            if ((prev_fsm_state_i === TB_COV_FSM_ARB) &&
                (dut.ft601_fsm.state === TB_COV_FSM_RX_START))
               native_fsm_cg.sample(dut.ft601_fsm.state,
                                     tb_cov_fsm_transition_event(dut.ft601_fsm.state,
                                                                 TB_COV_FSM_CAUSE_RX_REQUEST));
            if (((prev_fsm_state_i === TB_COV_FSM_TX_PREFETCH) ||
                 (prev_fsm_state_i === TB_COV_FSM_TX_BURST)) &&
                (dut.ft601_fsm.state === TB_COV_FSM_TURNAROUND))
               native_fsm_cg.sample(dut.ft601_fsm.state,
                                     tb_cov_fsm_transition_event(dut.ft601_fsm.state,
                                                                 TB_COV_FSM_CAUSE_RX_TAKEOVER));
            if ((prev_fsm_state_i === TB_COV_FSM_RX_BURST) &&
                (dut.ft601_fsm.state === TB_COV_FSM_TURNAROUND))
               native_fsm_cg.sample(dut.ft601_fsm.state,
                                     tb_cov_fsm_transition_event(dut.ft601_fsm.state,
                                                                 TB_COV_FSM_CAUSE_RX_COMPLETE));
`endif

            if ((ft_rx_axis_mon.valid && !ft_rx_axis_mon.ready) ||
                (normal_axis_mon.valid && !normal_axis_mon.ready) ||
                (loopback_payload_axis_mon.valid && !loopback_payload_axis_mon.ready) ||
                (loopback_axis_mon.valid && !loopback_axis_mon.ready) ||
                (status_axis_mon.valid && !status_axis_mon.ready) ||
                (tx_axis_mon.valid && !tx_axis_mon.ready))
               cov_req_axis_stall_seen = cov_req_axis_stall_seen + 1;
`ifdef TB_HAS_SV_COVERGROUP
            native_axis_cg.sample(TB_COV_AXIS_FT_RX,
                                  tb_cov_axis_stall_event(TB_COV_AXIS_FT_RX,
                                                          ft_rx_axis_mon.valid && !ft_rx_axis_mon.ready));
            native_axis_cg.sample(TB_COV_AXIS_NORMAL,
                                  tb_cov_axis_stall_event(TB_COV_AXIS_NORMAL,
                                                          normal_axis_mon.valid && !normal_axis_mon.ready));
            native_axis_cg.sample(TB_COV_AXIS_LOOPBACK_PAYLOAD,
                                  tb_cov_axis_stall_event(TB_COV_AXIS_LOOPBACK_PAYLOAD,
                                                          loopback_payload_axis_mon.valid && !loopback_payload_axis_mon.ready));
            native_axis_cg.sample(TB_COV_AXIS_LOOPBACK,
                                  tb_cov_axis_stall_event(TB_COV_AXIS_LOOPBACK,
                                                          loopback_axis_mon.valid && !loopback_axis_mon.ready));
            native_axis_cg.sample(TB_COV_AXIS_STATUS,
                                  tb_cov_axis_stall_event(TB_COV_AXIS_STATUS,
                                                          status_axis_mon.valid && !status_axis_mon.ready));
            native_axis_cg.sample(TB_COV_AXIS_TX,
                                  tb_cov_axis_stall_event(TB_COV_AXIS_TX,
                                                          tx_axis_mon.valid && !tx_axis_mon.ready));
`endif
         end
      end
   endtask

   task tb_cov_print_bin(input [1023:0] name, input integer hits);
      begin
         $display("COVERAGE BIN %-48s hits=%0d", name, hits);
      end
   endtask

   task tb_cov_require(input [1023:0] name, input integer hits);
      begin
         tb_cov_print_bin(name, hits);
         if (hits <= 0) begin
            cov_missing_bins = cov_missing_bins + 1;
            $display("COVERAGE MISSING: %0s", name);
         end
      end
   endtask

   task tb_cov_report_all_bins;
      begin
         tb_cov_print_bin("public.main.reset_boot_normal", cov_main_reset_boot_normal);
         tb_cov_print_bin("public.main.normal_path", cov_main_normal_path);
         tb_cov_print_bin("public.main.loopback_path", cov_main_loopback_path);
         tb_cov_print_bin("public.main.service_control", cov_main_service_control);
         tb_cov_print_bin("public.cmd.normal.GET_STATUS", cov_cmd_normal_get_status);
         tb_cov_print_bin("public.cmd.normal.SET_LOOPBACK", cov_cmd_normal_set_loopback);
         tb_cov_print_bin("public.cmd.normal.CLR_SERVICE_ERROR", cov_cmd_normal_clear);
         tb_cov_print_bin("public.cmd.normal.FT601_RESET", cov_cmd_normal_ft601_reset);
         tb_cov_print_bin("public.cmd.loopback.GET_STATUS", cov_cmd_loopback_get_status);
         tb_cov_print_bin("public.cmd.loopback.SET_NORMAL", cov_cmd_loopback_set_normal);
         tb_cov_print_bin("public.cmd.loopback.CLR_SERVICE_ERROR", cov_cmd_loopback_clear);
         tb_cov_print_bin("public.cmd.loopback.FT601_RESET", cov_cmd_loopback_ft601_reset);
         tb_cov_print_bin("public.GET_STATUS.pending_payload", cov_get_status_pending_payload);
         tb_cov_print_bin("public.backpressure.TXE_N", cov_txe_backpressure);
         tb_cov_print_bin("public.backpressure.RXF_N", cov_rxf_backpressure);
         tb_cov_print_bin("requirements.reset.normal_mode", cov_req_reset_normal_mode);
         tb_cov_print_bin("requirements.GET_STATUS.stale_prefix.none", cov_req_get_status_stale_none);
         tb_cov_print_bin("requirements.GET_STATUS.stale_prefix.payload", cov_req_get_status_stale_payload);
         tb_cov_print_bin("requirements.status_window.TXE_N_opened.fsm_idle", cov_req_status_window_txe_opened_idle);
         tb_cov_print_bin("requirements.mode_switch.active_ft_traffic", cov_req_mode_switch_active_ft_traffic);
         tb_cov_print_bin("requirements.normal_payload.keep.full", cov_req_normal_payload_keep_full);
         tb_cov_print_bin("requirements.normal_payload.keep.partial", cov_req_normal_payload_keep_partial);
         tb_cov_print_bin("requirements.loopback_payload.keep.full", cov_req_loopback_payload_keep_full);
         tb_cov_print_bin("requirements.loopback_payload.keep.partial", cov_req_loopback_payload_keep_partial);
         tb_cov_print_bin("requirements.loopback_payload.length.short", cov_req_loopback_payload_len_short);
         tb_cov_print_bin("requirements.loopback_payload.length.long", cov_req_loopback_payload_len_long);
         tb_cov_print_bin("requirements.RXF_N_backpressure.normal_mode", cov_req_rxf_backpressure_normal);
         tb_cov_print_bin("requirements.RXF_N_backpressure.loopback_mode", cov_req_rxf_backpressure_loopback);
         tb_cov_print_bin("requirements.TXE_N_backpressure.normal_source", cov_req_txe_backpressure_normal);
         tb_cov_print_bin("requirements.TXE_N_backpressure.loopback_source", cov_req_txe_backpressure_loopback);
         tb_cov_print_bin("requirements.TXE_N_backpressure.status_source", cov_req_txe_backpressure_status);
         tb_cov_print_bin("requirements.FT601_direction.tx", cov_req_ft_direction_tx);
         tb_cov_print_bin("requirements.FT601_direction.rx", cov_req_ft_direction_rx);
         tb_cov_print_bin("requirements.FT601_direction.turnaround", cov_req_ft_direction_turnaround);
         tb_cov_print_bin("requirements.arbiter_selected_source.status.downstream_ready", cov_req_arbiter_status_ready);
         tb_cov_print_bin("requirements.arbiter_selected_source.loopback.downstream_ready", cov_req_arbiter_loopback_ready);
         tb_cov_print_bin("requirements.arbiter_selected_source.normal.downstream_ready", cov_req_arbiter_normal_ready);
         tb_cov_print_bin("requirements.router_route.service.normal_mode", cov_req_router_service_normal);
         tb_cov_print_bin("requirements.router_route.service.loopback_mode", cov_req_router_service_loopback);
         tb_cov_print_bin("requirements.router_route.payload.loopback.full_keep", cov_req_router_payload_loopback_full);
         tb_cov_print_bin("requirements.router_route.payload.loopback.partial_keep", cov_req_router_payload_loopback_partial);
         tb_cov_print_bin("requirements.FSM_state.ARB.cause.idle", cov_req_fsm_arb_idle);
         tb_cov_print_bin("requirements.FSM_state.TX_PREFETCH.cause.tx_request", cov_req_fsm_tx_from_arb);
         tb_cov_print_bin("requirements.FSM_state.RX_START.cause.rx_request", cov_req_fsm_rx_from_arb);
         tb_cov_print_bin("requirements.FSM_state.TURNAROUND.cause.rx_takeover", cov_req_fsm_turnaround_from_tx);
         tb_cov_print_bin("requirements.FSM_state.TURNAROUND.cause.rx_complete", cov_req_fsm_turnaround_from_rx);
         tb_cov_print_bin("requirements.AXIS_stream.stall_seen", cov_req_axis_stall_seen);
         tb_cov_print_bin("requirements.ft601.turnaround_rx_priority", cov_req_ft601_turnaround_rx_priority);
         tb_cov_print_bin("requirements.ft601.rxf_boundary", cov_req_ft601_rxf_boundary);
         tb_cov_print_bin("requirements.payload.long_gapped_loopback", cov_req_payload_long_gapped_loopback);
         tb_cov_print_bin("requirements.control.status_window", cov_req_control_status_window);
         tb_cov_print_bin("requirements.control.mode_switch_idle", cov_req_control_mode_switch_idle);
         tb_cov_print_bin("requirements.control.router_demux", cov_req_control_router_demux);
         tb_cov_print_bin("requirements.control.unknown_opcode", cov_req_control_unknown_opcode);
         tb_cov_print_bin("requirements.control.arbiter_priority", cov_req_control_arbiter_priority);
      end
   endtask

   task tb_cov_require_public_bins;
      begin
         tb_cov_require("public.main.reset_boot_normal", cov_main_reset_boot_normal);
         tb_cov_require("public.main.normal_path", cov_main_normal_path);
         tb_cov_require("public.main.loopback_path", cov_main_loopback_path);
         tb_cov_require("public.main.service_control", cov_main_service_control);
         tb_cov_require("public.cmd.normal.GET_STATUS", cov_cmd_normal_get_status);
         tb_cov_require("public.cmd.normal.SET_LOOPBACK", cov_cmd_normal_set_loopback);
         tb_cov_require("public.cmd.normal.FT601_RESET", cov_cmd_normal_ft601_reset);
         tb_cov_require("public.cmd.loopback.GET_STATUS", cov_cmd_loopback_get_status);
         tb_cov_require("public.cmd.loopback.SET_NORMAL", cov_cmd_loopback_set_normal);
         tb_cov_require("public.cmd.loopback.CLR_SERVICE_ERROR", cov_cmd_loopback_clear);
         tb_cov_require("public.cmd.loopback.FT601_RESET", cov_cmd_loopback_ft601_reset);
      end
   endtask

   task tb_cov_require_directed_requirement_bins;
      begin
         tb_cov_require("requirements.reset.normal_mode", cov_req_reset_normal_mode);
         tb_cov_require("requirements.GET_STATUS.stale_prefix.none", cov_req_get_status_stale_none);
         tb_cov_require("requirements.GET_STATUS.stale_prefix.payload", cov_req_get_status_stale_payload);
         tb_cov_require("requirements.status_window.TXE_N_opened.fsm_idle", cov_req_status_window_txe_opened_idle);
         tb_cov_require("requirements.mode_switch.active_ft_traffic", cov_req_mode_switch_active_ft_traffic);
         tb_cov_require("requirements.normal_payload.keep.full", cov_req_normal_payload_keep_full);
         tb_cov_require("requirements.normal_payload.keep.partial", cov_req_normal_payload_keep_partial);
         tb_cov_require("requirements.loopback_payload.keep.full", cov_req_loopback_payload_keep_full);
         tb_cov_require("requirements.loopback_payload.keep.partial", cov_req_loopback_payload_keep_partial);
         tb_cov_require("requirements.loopback_payload.length.short", cov_req_loopback_payload_len_short);
         tb_cov_require("requirements.loopback_payload.length.long", cov_req_loopback_payload_len_long);
         tb_cov_require("requirements.RXF_N_backpressure.normal_mode", cov_req_rxf_backpressure_normal);
         tb_cov_require("requirements.RXF_N_backpressure.loopback_mode", cov_req_rxf_backpressure_loopback);
         tb_cov_require("requirements.TXE_N_backpressure.normal_source", cov_req_txe_backpressure_normal);
         tb_cov_require("requirements.TXE_N_backpressure.loopback_source", cov_req_txe_backpressure_loopback);
         tb_cov_require("requirements.TXE_N_backpressure.status_source", cov_req_txe_backpressure_status);
         tb_cov_require("requirements.FT601_direction.tx", cov_req_ft_direction_tx);
         tb_cov_require("requirements.FT601_direction.rx", cov_req_ft_direction_rx);
         tb_cov_require("requirements.FT601_direction.turnaround", cov_req_ft_direction_turnaround);
         tb_cov_require("requirements.arbiter_selected_source.status.downstream_ready", cov_req_arbiter_status_ready);
         tb_cov_require("requirements.arbiter_selected_source.loopback.downstream_ready", cov_req_arbiter_loopback_ready);
         tb_cov_require("requirements.arbiter_selected_source.normal.downstream_ready", cov_req_arbiter_normal_ready);
         tb_cov_require("requirements.router_route.service.normal_mode", cov_req_router_service_normal);
         tb_cov_require("requirements.router_route.service.loopback_mode", cov_req_router_service_loopback);
         tb_cov_require("requirements.router_route.payload.loopback.full_keep", cov_req_router_payload_loopback_full);
         tb_cov_require("requirements.router_route.payload.loopback.partial_keep", cov_req_router_payload_loopback_partial);
         tb_cov_require("requirements.FSM_state.ARB.cause.idle", cov_req_fsm_arb_idle);
         tb_cov_require("requirements.FSM_state.TX_PREFETCH.cause.tx_request", cov_req_fsm_tx_from_arb);
         tb_cov_require("requirements.FSM_state.RX_START.cause.rx_request", cov_req_fsm_rx_from_arb);
         tb_cov_require("requirements.FSM_state.TURNAROUND.cause.rx_takeover", cov_req_fsm_turnaround_from_tx);
         tb_cov_require("requirements.FSM_state.TURNAROUND.cause.rx_complete", cov_req_fsm_turnaround_from_rx);
         tb_cov_require("requirements.AXIS_stream.stall_seen", cov_req_axis_stall_seen);
         tb_cov_require("requirements.ft601.turnaround_rx_priority", cov_req_ft601_turnaround_rx_priority);
         tb_cov_require("requirements.ft601.rxf_boundary", cov_req_ft601_rxf_boundary);
         tb_cov_require("requirements.payload.long_gapped_loopback", cov_req_payload_long_gapped_loopback);
         tb_cov_require("requirements.control.status_window", cov_req_control_status_window);
         tb_cov_require("requirements.control.mode_switch_idle", cov_req_control_mode_switch_idle);
         tb_cov_require("requirements.control.router_demux", cov_req_control_router_demux);
         tb_cov_require("requirements.control.unknown_opcode", cov_req_control_unknown_opcode);
         tb_cov_require("requirements.control.arbiter_priority", cov_req_control_arbiter_priority);
      end
   endtask

   task tb_cov_check_requirements;
      begin
         cov_missing_bins = 0;
         $display("COVERAGE SUMMARY BEGIN");
         tb_cov_require_public_bins();
`ifndef TB_REGRESSION_MAIN
         tb_cov_require_directed_requirement_bins();
`endif
         $display("COVERAGE SUMMARY END missing_bins=%0d", cov_missing_bins);
         if (cov_missing_bins != 0)
            fail("functional coverage requirements not met");
      end
   endtask

`endif
