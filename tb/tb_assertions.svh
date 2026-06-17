`ifndef TB_ASSERTIONS_SVH
`define TB_ASSERTIONS_SVH

   localparam [5:0] TB_FSM_ARB         = 6'b000001;
   localparam [5:0] TB_FSM_TX_PREFETCH = 6'b000010;
   localparam [5:0] TB_FSM_TX_BURST    = 6'b000100;
   localparam [5:0] TB_FSM_RX_START    = 6'b001000;
   localparam [5:0] TB_FSM_RX_BURST    = 6'b010000;
   localparam [5:0] TB_FSM_TURNAROUND  = 6'b100000;

   localparam [1:0] TB_MODE_IDLE      = 2'b00;
   localparam [1:0] TB_MODE_WAIT_IDLE = 2'b01;
   localparam [1:0] TB_MODE_COMMIT    = 2'b10;

   function automatic tb_ft601_fsm_state_legal(
      input [5:0] state_i
   );
      begin
         tb_ft601_fsm_state_legal =
            (state_i == TB_FSM_ARB) ||
            (state_i == TB_FSM_TX_PREFETCH) ||
            (state_i == TB_FSM_TX_BURST) ||
            (state_i == TB_FSM_RX_START) ||
            (state_i == TB_FSM_RX_BURST) ||
            (state_i == TB_FSM_TURNAROUND);
      end
   endfunction

   function automatic tb_ft601_fsm_transition_legal(
      input [5:0] prev_state_i,
      input [5:0] state_i
   );
      begin
         case (prev_state_i)
            TB_FSM_ARB:
               tb_ft601_fsm_transition_legal =
                  (state_i == TB_FSM_ARB) ||
                  (state_i == TB_FSM_RX_START) ||
                  (state_i == TB_FSM_TX_PREFETCH);

            TB_FSM_TX_PREFETCH:
               tb_ft601_fsm_transition_legal =
                  (state_i == TB_FSM_TX_PREFETCH) ||
                  (state_i == TB_FSM_TX_BURST) ||
                  (state_i == TB_FSM_TURNAROUND);

            TB_FSM_TX_BURST:
               tb_ft601_fsm_transition_legal =
                  (state_i == TB_FSM_TX_BURST) ||
                  (state_i == TB_FSM_TURNAROUND);

            TB_FSM_RX_START:
               tb_ft601_fsm_transition_legal = (state_i == TB_FSM_RX_BURST);

            TB_FSM_RX_BURST:
               tb_ft601_fsm_transition_legal =
                  (state_i == TB_FSM_RX_BURST) ||
                  (state_i == TB_FSM_TURNAROUND);

            TB_FSM_TURNAROUND:
               tb_ft601_fsm_transition_legal = (state_i == TB_FSM_ARB);

            default:
               tb_ft601_fsm_transition_legal = 1'b0;
         endcase
      end
   endfunction

   function automatic tb_cmd_mode_state_legal(
      input [1:0] state_i
   );
      begin
         tb_cmd_mode_state_legal =
            (state_i == TB_MODE_IDLE) ||
            (state_i == TB_MODE_WAIT_IDLE) ||
            (state_i == TB_MODE_COMMIT);
      end
   endfunction

   function automatic tb_cmd_mode_transition_legal(
      input [1:0] prev_state_i,
      input [1:0] state_i
   );
      begin
         case (prev_state_i)
            TB_MODE_IDLE:
               tb_cmd_mode_transition_legal =
                  (state_i == TB_MODE_IDLE) ||
                  (state_i == TB_MODE_WAIT_IDLE);

            TB_MODE_WAIT_IDLE:
               tb_cmd_mode_transition_legal =
                  (state_i == TB_MODE_WAIT_IDLE) ||
                  (state_i == TB_MODE_COMMIT);

            TB_MODE_COMMIT:
               tb_cmd_mode_transition_legal = (state_i == TB_MODE_IDLE);

            default:
               tb_cmd_mode_transition_legal = 1'b0;
         endcase
      end
   endfunction

   // Native SVA layer. These concurrent properties mirror the always-on
   // procedural checks below, but express the temporal protocol contract directly.
   sequence s_ft601_write_active;
      ft601_mon.wr_n === 1'b0;
   endsequence

   sequence s_ft601_read_active;
      (ft601_mon.oe_n === 1'b0) || (ft601_mon.rd_n === 1'b0);
   endsequence

   sequence s_ft601_reset_low;
      ft_reset_n === 1'b0;
   endsequence

   // AXIS-like streams: payload must stay stable while valid is backpressured.
   property p_ft_rx_axis_hold_when_stalled;
      @(negedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (ft_rx_axis_mon.valid && !ft_rx_axis_mon.ready) |=>
            (ft_rx_axis_mon.valid &&
             (ft_rx_axis_mon.data === $past(ft_rx_axis_mon.data)) &&
             (ft_rx_axis_mon.keep === $past(ft_rx_axis_mon.keep)));
   endproperty

   property p_normal_axis_data_hold_when_stalled;
      @(negedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (normal_axis_mon.valid && !normal_axis_mon.ready) |=>
            (normal_axis_mon.ready ||
             ((normal_axis_mon.data === $past(normal_axis_mon.data)) &&
              (normal_axis_mon.keep === $past(normal_axis_mon.keep))));
   endproperty

   property p_loopback_payload_axis_hold_when_stalled;
      @(negedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (loopback_payload_axis_mon.valid && !loopback_payload_axis_mon.ready) |=>
            (loopback_payload_axis_mon.valid &&
             (loopback_payload_axis_mon.data === $past(loopback_payload_axis_mon.data)) &&
             (loopback_payload_axis_mon.keep === $past(loopback_payload_axis_mon.keep)));
   endproperty

   property p_loopback_axis_hold_when_stalled;
      @(negedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (loopback_axis_mon.valid && !loopback_axis_mon.ready) |=>
            (loopback_axis_mon.valid &&
             (loopback_axis_mon.data === $past(loopback_axis_mon.data)) &&
             (loopback_axis_mon.keep === $past(loopback_axis_mon.keep)));
   endproperty

   property p_status_axis_hold_when_stalled;
      @(negedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (status_axis_mon.valid && !status_axis_mon.ready) |=>
            (status_axis_mon.valid &&
             (status_axis_mon.data === $past(status_axis_mon.data)) &&
             (status_axis_mon.keep === $past(status_axis_mon.keep)));
   endproperty

   property p_tx_axis_hold_when_stalled;
      @(negedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (tx_axis_mon.valid && !tx_axis_mon.ready) |=>
            (tx_axis_mon.valid &&
             (tx_axis_mon.data === $past(tx_axis_mon.data)) &&
             (tx_axis_mon.keep === $past(tx_axis_mon.keep)));
   endproperty

   // FT601 boundary: no read/write overlap and correct tri-state direction.
   property p_ft601_no_direction_conflict;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         s_ft601_write_active |-> ((ft601_mon.oe_n === 1'b1) &&
                                   (ft601_mon.rd_n === 1'b1));
   endproperty

   property p_ft601_write_only_when_txe_open;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         ($past(dut.ft_rst_n_i === 1'b1) &&
          ($past(ft601_mon.wr_n) === 1'b1) &&
          (ft601_mon.wr_n === 1'b0)) |->
            (dut.ft601_wrapper.txe_n_ff === 1'b0);
   endproperty

   property p_ft601_read_only_when_rxf_open;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         ($past(dut.ft_rst_n_i === 1'b1) &&
          ((($past(ft601_mon.rd_n) === 1'b1) && (ft601_mon.rd_n === 1'b0)) ||
           (($past(ft601_mon.oe_n) === 1'b1) && (ft601_mon.oe_n === 1'b0)))) |->
            (dut.ft601_wrapper.rxf_n_ff === 1'b0);
   endproperty

   property p_ft601_bus_tristate_on_read;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         s_ft601_read_active |-> ((ft601_mon.data_t === {DATA_LEN{1'b1}}) &&
                                  (ft601_mon.be_t === {BE_LEN{1'b1}}));
   endproperty

   property p_ft601_bus_drive_on_write;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         s_ft601_write_active |-> ((ft601_mon.data_t === {DATA_LEN{1'b0}}) &&
                                   (ft601_mon.be_t === {BE_LEN{1'b0}}));
   endproperty

   // FT601 FSM: only documented phases and transitions are accepted.
   property p_ft601_fsm_legal_state;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         tb_ft601_fsm_state_legal(dut.ft601_fsm.state);
   endproperty

   property p_ft601_fsm_legal_transition;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         $past(dut.ft_rst_n_i === 1'b1) |->
            tb_ft601_fsm_transition_legal($past(dut.ft601_fsm.state),
                                          dut.ft601_fsm.state);
   endproperty

   property p_ft601_rx_takeover_uses_turnaround;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (((dut.ft601_fsm.state === TB_FSM_TX_PREFETCH) ||
           (dut.ft601_fsm.state === TB_FSM_TX_BURST)) &&
          (dut.ft601_fsm.rx_takeover_req === 1'b1)) |=>
            (dut.ft601_fsm.state === TB_FSM_TURNAROUND);
   endproperty

   // Service/arbiter policy: status priority and payload hold rules.
   property p_arbiter_status_priority;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (dut.status_frame_active === 1'b1) |->
            ((dut.axis_tx_arbiter.status_sel === 1'b1) &&
             (dut.axis_tx_arbiter.loopback_sel === 1'b0) &&
             (dut.axis_tx_arbiter.normal_sel === 1'b0));
   endproperty

   property p_arbiter_output_hold_when_stalled;
      @(negedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (tx_axis_mon.valid && !tx_axis_mon.ready) |=>
            (tx_axis_mon.valid &&
             (tx_axis_mon.data === $past(tx_axis_mon.data)) &&
             (tx_axis_mon.keep === $past(tx_axis_mon.keep)));
   endproperty

   property p_service_payload_block_policy;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         dut.status_payload_block ===
            (dut.mode_switch_busy_ft ||
             dut.status_req ||
             dut.status_frame_active ||
             dut.service_status_policy.status_payload_hold_ff);
   endproperty

   property p_service_hold_release_is_safe;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         ($past(dut.service_status_policy.status_payload_hold_ff === 1'b1) &&
          (dut.service_status_policy.status_payload_hold_ff === 1'b0)) |->
            (($past(dut.service_status_policy.status_txe_low_seen_ff) === 1'b1) &&
             ($past(dut.status_req) === 1'b0) &&
             ($past(dut.status_frame_active) === 1'b0) &&
             ($past(dut.fsm_idle_o) === 1'b1));
   endproperty

   // RX router: command framing and loopback payload routing stay exclusive.
   property p_router_cmd_magic_waits_opcode;
      @(negedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (dut.rx_stream_router.s_axis_hs &&
          dut.rx_stream_router.cmd_magic_match) |=>
            (dut.rx_stream_router.cmd_wait_opcode_ff === 1'b1);
   endproperty

   property p_router_full_opcode_generates_event;
      @(negedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (dut.rx_stream_router.s_axis_hs &&
          dut.rx_stream_router.cmd_wait_opcode_ff &&
          dut.rx_stream_router.s_axis_full_keep) |=>
            (dut.cmd_event_valid === 1'b1);
   endproperty

   property p_router_bad_opcode_generates_diagnostic;
      @(negedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (dut.rx_stream_router.s_axis_hs &&
          dut.rx_stream_router.cmd_wait_opcode_ff &&
          !dut.rx_stream_router.s_axis_full_keep) |=>
            (dut.service_frame_error_pulse === 1'b1);
   endproperty

   property p_router_payload_only_in_loopback;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         (dut.loopback_fifo_wen === 1'b1) |->
            ((dut.loopback_mode_ft === 1'b1) &&
             (dut.loopback_payload_tvalid === 1'b1) &&
             (dut.loopback_payload_tready === 1'b1));
   endproperty

   // CMD_FT601_RESET affects only the external RESET_N pulse.
   property p_cmd_ft601_reset_exact_two_cycles;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         $rose(dut.cmd_decoder.ft601_reset_pipe_ff[1]) |->
            (s_ft601_reset_low ##1 s_ft601_reset_low ##1 (ft_reset_n === 1'b1));
   endproperty

   property p_cmd_ft601_reset_not_internal_reset;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         s_ft601_reset_low |-> (dut.ft_rst_n_i === 1'b1);
   endproperty

   property p_cmd_ft601_reset_preserves_mode;
      @(posedge ft_clk) disable iff (dut.ft_rst_n_i !== 1'b1)
         ((ft_reset_n === 1'b0) && ($past(ft_reset_n) === 1'b0)) |->
            (dut.loopback_mode_ft === $past(dut.loopback_mode_ft));
   endproperty

   // SVA failures call fail(), so they are visible in the regression result.
   a_sva_ft_rx_axis_hold: assert property (p_ft_rx_axis_hold_when_stalled)
      else fail("SVA REQ-AXIS-001 FT RX AXIS changed while stalled");

   a_sva_normal_axis_hold: assert property (p_normal_axis_data_hold_when_stalled)
      else fail("SVA REQ-AXIS-001 normal AXIS data changed while stalled");

   a_sva_loopback_payload_axis_hold: assert property (p_loopback_payload_axis_hold_when_stalled)
      else fail("SVA REQ-AXIS-001 loopback payload AXIS changed while stalled");

   a_sva_loopback_axis_hold: assert property (p_loopback_axis_hold_when_stalled)
      else fail("SVA REQ-AXIS-001 loopback AXIS changed while stalled");

   a_sva_status_axis_hold: assert property (p_status_axis_hold_when_stalled)
      else fail("SVA REQ-AXIS-001 status AXIS changed while stalled");

   a_sva_tx_axis_hold: assert property (p_tx_axis_hold_when_stalled)
      else fail("SVA REQ-AXIS-001 TX AXIS changed while stalled");

   a_sva_ft601_no_direction_conflict: assert property (p_ft601_no_direction_conflict)
      else fail("SVA REQ-FT-001 FT601 write/read directions overlapped");

   a_sva_ft601_write_only_when_txe_open: assert property (p_ft601_write_only_when_txe_open)
      else fail("SVA REQ-FT-001 WR_N started while registered TXE_N is closed");

   a_sva_ft601_read_only_when_rxf_open: assert property (p_ft601_read_only_when_rxf_open)
      else fail("SVA REQ-FT-001 RD_N/OE_N started while registered RXF_N is closed");

   a_sva_ft601_bus_tristate_on_read: assert property (p_ft601_bus_tristate_on_read)
      else fail("SVA REQ-FT-001 FPGA drives FT601 bus during read");

   a_sva_ft601_bus_drive_on_write: assert property (p_ft601_bus_drive_on_write)
      else fail("SVA REQ-FT-001 FPGA tri-states FT601 bus during write");

   a_sva_ft601_fsm_legal_state: assert property (p_ft601_fsm_legal_state)
      else fail("SVA REQ-FSM-001 ft601_fsm entered illegal state");

   a_sva_ft601_fsm_legal_transition: assert property (p_ft601_fsm_legal_transition)
      else fail("SVA REQ-FSM-001 ft601_fsm used illegal transition");

   a_sva_ft601_rx_takeover_uses_turnaround: assert property (p_ft601_rx_takeover_uses_turnaround)
      else fail("SVA REQ-FT-003 RX takeover did not enter TURNAROUND");

   a_sva_arbiter_status_priority: assert property (p_arbiter_status_priority)
      else fail("SVA REQ-ARB-001 status source lost arbiter priority");

   a_sva_arbiter_output_hold_when_stalled: assert property (p_arbiter_output_hold_when_stalled)
      else fail("SVA REQ-ARB-001 arbiter output changed while stalled");

   a_sva_service_payload_block_policy: assert property (p_service_payload_block_policy)
      else fail("SVA REQ-POL-001 payload block policy mismatch");

   a_sva_service_hold_release_is_safe: assert property (p_service_hold_release_is_safe)
      else fail("SVA REQ-STS-002 status hold released before safe drain point");

   a_sva_router_cmd_magic_waits_opcode: assert property (p_router_cmd_magic_waits_opcode)
      else fail("SVA REQ-SVC-001 service magic did not arm opcode wait");

   a_sva_router_full_opcode_generates_event: assert property (p_router_full_opcode_generates_event)
      else fail("SVA REQ-SVC-001 full-keep opcode did not generate command event");

   a_sva_router_bad_opcode_generates_diagnostic: assert property (p_router_bad_opcode_generates_diagnostic)
      else fail("SVA REQ-SVC-002 malformed opcode did not generate diagnostic pulse");

   a_sva_router_payload_only_in_loopback: assert property (p_router_payload_only_in_loopback)
      else fail("SVA REQ-LB-002 payload entered loopback FIFO outside loopback handshake");

   a_sva_cmd_ft601_reset_exact_two_cycles: assert property (p_cmd_ft601_reset_exact_two_cycles)
      else fail("SVA REQ-RST-002 CMD_FT601_RESET did not create exact two-cycle RESET_N pulse");

   a_sva_cmd_ft601_reset_not_internal_reset: assert property (p_cmd_ft601_reset_not_internal_reset)
      else fail("SVA REQ-RST-002 CMD_FT601_RESET affected internal FT reset");

   a_sva_cmd_ft601_reset_preserves_mode: assert property (p_cmd_ft601_reset_preserves_mode)
      else fail("SVA REQ-RST-002 CMD_FT601_RESET changed loopback mode");

   task automatic tb_assert_now(
      input        condition,
      input [1023:0] message
   );
      begin
         assert (condition) else fail(message);
      end
   endtask

   // Shared immediate check for AXIS-like stability after a stalled cycle.
   task automatic tb_assert_axis_stall_stable(
      input [1023:0]       valid_message,
      input [1023:0]       data_message,
      input                prev_stall,
      input                valid,
      input                ready,
      input [DATA_LEN-1:0] data,
      input [BE_LEN-1:0]   keep,
      input [DATA_LEN-1:0] prev_data,
      input [BE_LEN-1:0]   prev_keep,
      input                check_valid_hold
   );
      begin
         if (prev_stall && !ready) begin
            if (check_valid_hold)
               tb_assert_now(valid === 1'b1, valid_message);

            if (valid === 1'b1)
               tb_assert_now(((data === prev_data) && (keep === prev_keep)), data_message);
         end
      end
   endtask

   // Portable immediate assertions for stream stability; active in all simulators.
   task automatic tb_assert_axis_invariants;
      begin
         tb_assert_axis_stall_stable(
            "FT RX AXIS valid dropped before ready",
            "FT RX AXIS data/keep changed while stalled",
            prev_ft_rx_axis_stall,
            ft_rx_axis_mon.valid,
            ft_rx_axis_mon.ready,
            ft_rx_axis_mon.data,
            ft_rx_axis_mon.keep,
            prev_ft_rx_axis_tdata,
            prev_ft_rx_axis_tkeep,
            1'b1
         );

         tb_assert_axis_stall_stable(
            "",
            "normal AXIS data/keep changed while stalled",
            prev_normal_axis_stall &&
               !allow_status_preempt_drop &&
               !status_tx_hold &&
               !prev_status_tx_hold,
            normal_axis_mon.valid,
            normal_axis_mon.ready,
            normal_axis_mon.data,
            normal_axis_mon.keep,
            prev_normal_axis_tdata,
            prev_normal_axis_tkeep,
            1'b0
         );

         tb_assert_axis_stall_stable(
            "loopback payload AXIS valid dropped before ready",
            "loopback payload AXIS data/keep changed while stalled",
            prev_loopback_payload_axis_stall,
            loopback_payload_axis_mon.valid,
            loopback_payload_axis_mon.ready,
            loopback_payload_axis_mon.data,
            loopback_payload_axis_mon.keep,
            prev_loopback_payload_axis_tdata,
            prev_loopback_payload_axis_tkeep,
            1'b1
         );

         tb_assert_axis_stall_stable(
            "loopback AXIS valid dropped before ready",
            "loopback AXIS data/keep changed while stalled",
            prev_loopback_axis_stall,
            loopback_axis_mon.valid,
            loopback_axis_mon.ready,
            loopback_axis_mon.data,
            loopback_axis_mon.keep,
            prev_loopback_axis_tdata,
            prev_loopback_axis_tkeep,
            1'b1
         );

         tb_assert_axis_stall_stable(
            "status AXIS valid dropped before ready",
            "status AXIS data/keep changed while stalled",
            prev_status_axis_stall,
            status_axis_mon.valid,
            status_axis_mon.ready,
            status_axis_mon.data,
            status_axis_mon.keep,
            prev_status_axis_tdata,
            prev_status_axis_tkeep,
            1'b1
         );

         tb_assert_now(!((status_axis_mon.valid === 1'b1) &&
                         (status_axis_mon.keep !== FULL_BE)),
                       "status AXIS keep must be full");

         tb_assert_axis_stall_stable(
            "TX AXIS valid dropped before ready",
            "TX AXIS data/keep changed while stalled",
            prev_tx_axis_stall,
            tx_axis_mon.valid,
            tx_axis_mon.ready,
            tx_axis_mon.data,
            tx_axis_mon.keep,
            prev_tx_axis_tdata,
            prev_tx_axis_tkeep,
            1'b1
         );

         tb_assert_now(!((dut.loopback_fifo_wen === 1'b1) &&
                         ((loopback_payload_axis_mon.valid &&
                           loopback_payload_axis_mon.ready) === 1'b0)),
                       "loopback FIFO write occurred without payload AXIS handshake");
      end
   endtask

   task automatic tb_assert_ft601_direction_timing;
      begin
         if ((prev_ft_oe_n === 1'b1) && (ft601_mon.oe_n === 1'b0))
            tb_assert_now(ft601_mon.rd_n === 1'b1,
                          "RD_N must stay inactive in the cycle OE_N first asserts");

         if ((prev_ft_rd_n === 1'b1) && (ft601_mon.rd_n === 1'b0))
            tb_assert_now(((prev_ft_oe_n === 1'b0) && (ft601_mon.oe_n === 1'b0)),
                          "RD_N must assert only after OE_N is already active");
      end
   endtask

   task automatic tb_assert_ft601_flag_access;
      begin
         // The current TB stimulus may deassert RXF_N/TXE_N on a sampled edge and
         // then wait for release. These assertions therefore guard access start;
         // full post-deassert release timing remains in the procedural drivers.
         if ((prev_ft_rd_n === 1'b1) && (ft601_mon.rd_n === 1'b0))
            tb_assert_now(dut.ft601_wrapper.rxf_n_ff === 1'b0,
                          "RD_N must assert only while registered RXF_N is active");

         if (!allow_status_preempt_drop &&
             (prev_ft_wr_n === 1'b1) &&
             (ft601_mon.wr_n === 1'b0))
            tb_assert_now(dut.ft601_wrapper.txe_n_ff === 1'b0,
                          "WR_N must assert only while registered TXE_N is active");
      end
   endtask

   task automatic tb_assert_ft601_bus_invariants;
      begin
         tb_assert_now(!((ft601_mon.wr_n === 1'b0) &&
                         ((ft601_mon.oe_n === 1'b0) ||
                          (ft601_mon.rd_n === 1'b0))),
                       "WR_N must not be active while OE_N/RD_N selects FT601 read direction");

         // White-box diagnostic: these wrapper enables are the only unambiguous
         // way to verify FPGA-side tri-state intent on the resolved inout bus.
         if ((ft601_mon.oe_n === 1'b0) || (ft601_mon.rd_n === 1'b0)) begin
            tb_assert_now(ft601_mon.data_t === {DATA_LEN{1'b1}},
                          "DATA bus must be tri-stated by FPGA during FT601 read");
            tb_assert_now(ft601_mon.be_t === {BE_LEN{1'b1}},
                          "BE bus must be tri-stated by FPGA during FT601 read");
         end

         if (ft601_mon.wr_n === 1'b0) begin
            tb_assert_now(ft601_mon.data_t === {DATA_LEN{1'b0}},
                          "DATA bus must be driven by FPGA during FT601 write");
            tb_assert_now(ft601_mon.be_t === {BE_LEN{1'b0}},
                          "BE bus must be driven by FPGA during FT601 write");
         end

         if (dut.ft_rst_n_i === 1'b0) begin
            tb_assert_now(ft601_mon.wr_n === 1'b1,
                          "WR_N must stay inactive during internal FT reset");
            tb_assert_now(ft601_mon.rd_n === 1'b1,
                          "RD_N must stay inactive during internal FT reset");
            tb_assert_now(ft601_mon.oe_n === 1'b1,
                          "OE_N must stay inactive during internal FT reset");
            tb_assert_now(ft601_mon.data_t === {DATA_LEN{1'b1}},
                          "DATA bus must be tri-stated during internal FT reset");
            tb_assert_now(ft601_mon.be_t === {BE_LEN{1'b1}},
                          "BE bus must be tri-stated during internal FT reset");
         end
      end
   endtask

   task automatic tb_assert_ft601_write_stability;
      begin
         if (ft601_mon.wr_n === 1'b0) begin
            tb_assert_now((^ft601_mon.data !== 1'bx),
                          "DATA bus must be known during active FT601 write");
            tb_assert_now((^ft601_mon.be !== 1'bx),
                          "BE bus must be known during active FT601 write");
         end
      end
   endtask

   task automatic tb_assert_ft601_continuous_tx_burst;
      begin
         tb_assert_now(!((tx_payload_burst_seen === 1'b1) &&
                         (prev_ft_txe_n_neg === 1'b0) &&
                         (ft601_mon.txe_n === 1'b0) &&
                         (ft601_mon.rxf_n === 1'b1) &&
                         (ft601_mon.oe_n === 1'b1) &&
                         (ft601_mon.rd_n === 1'b1) &&
                         (dut.mode_switch_busy_ft !== 1'b1) &&
                         (dut.status_payload_block !== 1'b1) &&
                         (prev_ft_wr_n === 1'b0) &&
                         (ft601_mon.wr_n === 1'b1) &&
                         (tx_words_n < exp_words_n)),
                       "WR_N must stay active for a continuous TX burst while TXE_N is low");
      end
   endtask

   task automatic tb_assert_ft601_fsm_invariants;
      begin
         tb_assert_now(tb_ft601_fsm_state_legal(dut.ft601_fsm.state),
                       "REQ-FSM-001 ft601_fsm entered an illegal state");
         tb_assert_now(tb_ft601_fsm_transition_legal(prev_fsm_state,
                                                     dut.ft601_fsm.state),
                       "REQ-FSM-001 ft601_fsm used an illegal transition");

         if (dut.fsm_idle_o === 1'b1) begin
            tb_assert_now(dut.ft601_fsm.state === TB_FSM_ARB,
                          "REQ-FSM-001 fsm_idle_o asserted outside ARB");
            tb_assert_now((dut.ft601_fsm.tx_idle === 1'b1) &&
                          (dut.ft601_fsm.rx_idle === 1'b1),
                          "REQ-FSM-001 fsm_idle_o asserted while adapters are busy");
            tb_assert_now((dut.fsm_wr_o === 1'b1) &&
                          (dut.fsm_rd_o === 1'b1) &&
                          (dut.fsm_oe_o === 1'b1) &&
                          (dut.drive_tx === 1'b0),
                          "REQ-FSM-001 fsm_idle_o asserted while FT controls are active");
         end

         tb_assert_now(!((dut.ft601_fsm.state == TB_FSM_ARB) &&
                         (dut.ft601_fsm.rx_start_req === 1'b1) &&
                         (dut.drive_tx === 1'b1)),
                       "REQ-FT-003 RX priority in ARB must not pre-drive TX bus");
      end
   endtask

   task automatic tb_assert_axis_arbiter_invariants;
      begin
         tb_assert_now(dut.status_axis_tready ===
                       (dut.axis_tx_arbiter.can_load &&
                        dut.axis_tx_arbiter.status_sel),
                       "REQ-ARB-001 status ready must match selected status source");
         tb_assert_now(dut.loopback_axis_tready ===
                       (dut.axis_tx_arbiter.can_load &&
                        dut.axis_tx_arbiter.loopback_sel),
                       "REQ-ARB-001 loopback ready must match selected loopback source");
         tb_assert_now(dut.normal_axis_tready ===
                       (dut.axis_tx_arbiter.can_load &&
                        dut.axis_tx_arbiter.normal_sel),
                       "REQ-ARB-001 normal ready must match selected normal source");

         tb_assert_now(!((dut.axis_tx_arbiter.status_sel === 1'b1) &&
                         ((dut.axis_tx_arbiter.loopback_sel === 1'b1) ||
                          (dut.axis_tx_arbiter.normal_sel === 1'b1))),
                       "REQ-ARB-001 status source must be exclusive");
         tb_assert_now(!((dut.axis_tx_arbiter.loopback_sel === 1'b1) &&
                         (dut.axis_tx_arbiter.normal_sel === 1'b1)),
                       "REQ-ARB-001 loopback and normal sources must be exclusive");

         if ((prev_tx_axis_stall === 1'b1) && (tx_axis_mon.ready === 1'b0))
            tb_assert_now(tx_axis_mon.valid === 1'b1,
                          "REQ-ARB-001 arbiter output valid dropped under downstream stall");
      end
   endtask

   task automatic tb_assert_service_policy_invariants;
      begin
         tb_assert_now(dut.status_payload_block ===
                       (dut.mode_switch_busy_ft ||
                        dut.status_req ||
                        dut.status_frame_active ||
                        dut.service_status_policy.status_payload_hold_ff),
                       "REQ-POL-001 payload block flag does not match policy inputs");
         tb_assert_now(dut.status_source_block === dut.mode_switch_busy_ft,
                       "REQ-POL-001 status source block must follow mode switch busy");
         tb_assert_now(dut.rx_router_block_ft ===
                       (dut.mode_switch_busy_ft && dut.fsm_idle_o),
                       "REQ-POL-001 router block must assert only for idle mode-switch window");
         tb_assert_now(dut.status_start_ready === dut.fsm_idle_o,
                       "REQ-POL-001 status start-ready must follow FT FSM idle");

         if ((prev_status_payload_hold === 1'b1) &&
             (dut.service_status_policy.status_payload_hold_ff === 1'b0)) begin
            tb_assert_now(prev_status_txe_low_seen === 1'b1,
                          "REQ-STS-002 status hold released before host opened TX window");
            tb_assert_now((prev_status_req === 1'b0) &&
                          (prev_status_frame_active === 1'b0) &&
                          (prev_fsm_idle === 1'b1),
                          "REQ-STS-002 status hold released before status pipeline became idle");
         end
      end
   endtask

   task automatic tb_assert_status_source_invariants;
      begin
         tb_assert_now(dut.status_frame_active ===
                       (dut.status_source.active_ff ||
                        dut.status_source.req_queued_ff),
                       "REQ-STS-001 status frame_active must cover active or queued frame");
         tb_assert_now(dut.status_axis_tvalid ===
                       (dut.status_source.active_ff &&
                        (dut.status_source.frame_words_left_ff != 2'd0)),
                       "REQ-STS-001 status valid must match active frame word count");

         if (dut.status_source.active_ff === 1'b1) begin
            tb_assert_now((dut.status_source.frame_words_left_ff == 2'd1) ||
                          (dut.status_source.frame_words_left_ff == 2'd2),
                          "REQ-STS-001 status frame has illegal word count");
            tb_assert_now(dut.status_axis_tkeep === FULL_BE,
                          "REQ-STS-001 status frame keep must be full");

            if (dut.status_source.frame_header_ff === 1'b1) begin
               tb_assert_now(dut.status_source.frame_words_left_ff == 2'd2,
                             "REQ-STS-001 status header must be the first frame word");
               tb_assert_now(dut.status_axis_tdata === STATUS_MAGIC,
                             "REQ-STS-001 status header word must be STATUS_MAGIC");
            end
            else begin
               tb_assert_now(dut.status_axis_tdata[DATA_LEN-1:6] ===
                             {(DATA_LEN-6){1'b0}},
                             "REQ-STS-001 unused status bits must be zero");
               tb_assert_now(dut.status_axis_tdata[5:0] ===
                             dut.status_source.status_bits_ff,
                             "REQ-STS-001 status data word must match captured status bits");
            end
         end
      end
   endtask

   task automatic tb_assert_router_invariants;
      begin
         tb_assert_now(!(dut.rx_stream_router.cmd_valid_ff &&
                         dut.rx_stream_router.service_frame_error_ff),
                       "REQ-LB-002 router must not report command and malformed opcode together");

         if (dut.rx_stream_router.payload_word_accept === 1'b1) begin
            tb_assert_now(dut.loopback_mode_ft === 1'b1,
                          "REQ-LB-002 payload route may be selected only in loopback mode");
            tb_assert_now(dut.rx_stream_router.cmd_magic_match === 1'b0,
                          "REQ-LB-002 service magic must not route as payload");
            tb_assert_now(dut.rx_stream_router.s_axis_has_keep === 1'b1,
                          "REQ-LB-002 zero-keep word must not route as payload");
         end

         if (dut.loopback_payload_tvalid === 1'b1)
            tb_assert_now(|dut.loopback_payload_tkeep,
                          "REQ-LB-002 loopback payload valid requires nonzero keep");

         if (dut.rx_router_block_ft === 1'b1)
            tb_assert_now(dut.ft_rx_axis_tready === 1'b0,
                          "REQ-POL-001 router must not accept RX stream while blocked");
      end
   endtask

   task automatic tb_assert_cmd_decoder_invariants;
      begin
         tb_assert_now(tb_cmd_mode_state_legal(dut.cmd_decoder.mode_state_ff),
                       "REQ-MODE-001 cmd_decoder entered an illegal mode state");
         tb_assert_now(tb_cmd_mode_transition_legal(prev_cmd_mode_state,
                                                    dut.cmd_decoder.mode_state_ff),
                       "REQ-MODE-001 cmd_decoder used an illegal mode transition");
         tb_assert_now(dut.mode_switch_busy_ft ===
                       (dut.cmd_decoder.mode_state_ff != TB_MODE_IDLE),
                       "REQ-MODE-001 mode_switch_busy must match mode FSM state");

         if (dut.cmd_decoder.mode_state_ff == TB_MODE_COMMIT)
            tb_assert_now(dut.loopback_mode_ft === dut.cmd_decoder.mode_target_ff,
                          "REQ-MODE-001 committed mode must match target mode");

         tb_assert_now(dut.status_req === dut.cmd_decoder.get_status_cmd,
                       "REQ-SVC-001 status_req must be generated only by GET_STATUS");
         tb_assert_now(dut.cmd_decoder.ft601_reset_n_o ===
                       !(|dut.cmd_decoder.ft601_reset_pipe_ff),
                       "REQ-RST-002 FT601 reset output must match reset pulse pipeline");

         if ((dut.cmd_event_valid === 1'b1) &&
             (dut.cmd_decoder.cmd_known === 1'b0))
            tb_assert_now(dut.status_req === 1'b0,
                          "REQ-SVC-003 unknown command must not request status");
      end
   endtask

   task automatic tb_assert_sampled_protocol_invariants;
      begin
         if (dut.ft_rst_n_i === 1'b1) begin
            tb_assert_axis_invariants();
            tb_assert_ft601_direction_timing();
            tb_assert_ft601_flag_access();
            tb_assert_ft601_bus_invariants();
            tb_assert_ft601_write_stability();
            tb_assert_ft601_continuous_tx_burst();
            tb_assert_ft601_fsm_invariants();
            tb_assert_axis_arbiter_invariants();
            tb_assert_service_policy_invariants();
            tb_assert_status_source_invariants();
            tb_assert_router_invariants();
            tb_assert_cmd_decoder_invariants();
         end
      end
   endtask

`endif
