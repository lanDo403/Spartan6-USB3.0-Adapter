   task host_send_command(
      input service_cmd_t cmd
   );
      begin
         send_ft_command_frame(service_opcode(cmd));
      end
   endtask

   // Sends a service command frame and checks that cmd_decoder reports exactly one known command.
   task send_checked_command(
      input service_cmd_t  cmd,
      input [1023:0]       cmd_name
   );
      begin
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         scoreboard_reset_command_counters();
         host_send_command(cmd);
         expect_known_command_accepted(cmd_name);
         wait_ft_cycles(8);
      end
   endtask

   // Host-like raw read from the shared EP82 stream until TX returns to quiet/ARB state.
   task host_capture_ep82_until_quiet(
      input integer quiet_cycles,
      input integer timeout_cycles
   );
      integer quiet_count;
      integer timeout;
      integer last_total_words;
      begin
         clear_monitors();
         tx_stream_only_mode = 1'b1;
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);

         quiet_count = 0;
         timeout = 0;
         last_total_words = -1;
         while ((quiet_count < quiet_cycles) && (timeout < timeout_cycles)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;

            if (tx_total_words_n !== last_total_words) begin
               last_total_words = tx_total_words_n;
               quiet_count = 0;
            end
            else if ((ft_wr_n === 1'b1) && (dut.ft601_fsm.state === FSM_ARB)) begin
               quiet_count = quiet_count + 1;
            end
            else begin
               quiet_count = 0;
            end

            timeout = timeout + 1;
         end

         if (timeout >= timeout_cycles)
            fail("host EP82 read did not quiesce");

         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         tx_stream_only_mode = 1'b0;
      end
   endtask

   // Host-like short read from EP82: keep TXE_N low only until a bounded number
   // of words is observed, then stop immediately. This models a dedicated
   // service/status read while payload may still be pending behind it.
   task host_capture_ep82_exact_words(
      input integer expected_words,
      input integer timeout_cycles
   );
      integer timeout;
      begin
         clear_monitors();
         tx_stream_only_mode = 1'b1;
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);

         timeout = 0;
         while ((tx_total_words_n < expected_words) && (timeout < timeout_cycles)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;
            timeout = timeout + 1;
         end

         if (timeout >= timeout_cycles)
            fail("host EP82 exact-word read timed out");
         if (tx_total_words_n !== expected_words) begin
            $display("ERROR: tx_total_words_n=%0d expected=%0d", tx_total_words_n, expected_words);
            fail("host EP82 exact-word read length mismatch");
         end

         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         tx_stream_only_mode = 1'b0;
      end
   endtask

   // A status reply is pending internally but must not leak onto EP82 yet.
   task expect_status_response_pending(
      input [1023:0] ctx
   );
      begin
         wait_ft_cycles(2);
         if (tx_total_words_n !== 0) begin
            $display("ERROR: %0s tx_total_words_n=%0d ft_txe_n=%b word0=%h be0=%h word1=%h be1=%h",
                     ctx,
                     tx_total_words_n,
                     ft_txe_n,
                     tx_captured_words[0],
                     tx_captured_be[0],
                     tx_captured_words[1],
                     tx_captured_be[1]);
            fail("status response reached FT601 TX bus before explicit host drain");
         end
         if (dut.service_status_policy.status_payload_hold_ff !== 1'b1) begin
            $display("ERROR: %0s status_payload_hold_ff=%b", ctx, dut.service_status_policy.status_payload_hold_ff);
            fail("status payload hold must stay asserted while status response is pending");
         end
      end
   endtask

   // Service/status pipeline is empty, regardless of hold-flag release details.
   task expect_status_response_pipeline_empty(
      input [1023:0] ctx
   );
      begin
         wait_ft_cycles(2);
         if (dut.status_frame_active !== 1'b0) begin
            $display("ERROR: %0s status_frame_active=%b", ctx, dut.status_frame_active);
            fail("status response must be idle after host EP82 drain");
         end
         if (dut.status_source.req_queued_ff !== 1'b0) begin
            $display("ERROR: %0s req_queued_ff=%b", ctx, dut.status_source.req_queued_ff);
            fail("status request queue must clear after host EP82 drain");
         end
         if (dut.status_source.active_ff !== 1'b0) begin
            $display("ERROR: %0s active_ff=%b", ctx, dut.status_source.active_ff);
            fail("status source active flag must clear after host EP82 drain");
         end
         if (dut.ft601_fsm.tx_adapter.out_valid_ff !== 1'b0) begin
            $display("ERROR: %0s out_valid_ff=%b", ctx, dut.ft601_fsm.tx_adapter.out_valid_ff);
            fail("TX adapter output buffer must clear after host EP82 drain");
         end
         if (dut.ft601_fsm.tx_adapter.buf_valid_ff !== 1'b0) begin
            $display("ERROR: %0s buf_valid_ff=%b", ctx, dut.ft601_fsm.tx_adapter.buf_valid_ff);
            fail("TX adapter staging buffer must clear after host EP82 drain");
         end
      end
   endtask

   // Status pipeline and hold logic must be fully drained after host read.
   task expect_status_response_idle(
      input [1023:0] ctx
   );
      begin
         expect_status_response_pipeline_empty(ctx);
         #1;
         if (dut.service_status_policy.status_payload_hold_ff !== 1'b0) begin
            $display("ERROR: %0s status_payload_hold_ff=%b", ctx, dut.service_status_policy.status_payload_hold_ff);
            fail("status payload hold must clear after host EP82 drain");
         end
         tb_cov_mark_status_window_release(1'b1, dut.fsm_idle_o);
      end
   endtask

   // Status helpers used by service-path checks and mode-switch commands.
   task expect_status_response_bits(
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
         scoreboard_reset_command_counters();

         host_send_command(SVC_GET_STATUS);
         expect_known_command_accepted("CMD_GET_STATUS");

         expect_no_unexpected_tx(8, "status response before host read");
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         wait_for_tx_total_words(2, 256);
         expect_only_status_response(expected_status);
         if ((expected_tx_fifo_empty === 1'b0) ||
             (expected_loopback_fifo_empty === 1'b0))
            tb_cov_mark_get_status_pending_payload();
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         tx_stream_only_mode = 1'b0;
      end
   endtask

   task set_loopback_via_status;
      begin
         clear_monitors();
         send_checked_command(SVC_SET_LOOPBACK, "CMD_SET_LOOPBACK");
         expect_loopback_mode(1'b1, "CMD_SET_LOOPBACK");
         expect_status_response_bits(1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
      end
   endtask

   task set_normal_via_status;
      begin
         clear_monitors();
         send_checked_command(SVC_SET_NORMAL, "CMD_SET_NORMAL");
         expect_loopback_mode(1'b0, "CMD_SET_NORMAL");
         expect_status_response_bits(1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
      end
   endtask

   task send_clear_command(input service_cmd_t cmd);
      begin
         clear_monitors();
         scoreboard_reset_command_counters();
         host_send_command(cmd);
         expect_known_command_accepted("clear service command");
         wait_ft_cycles(8);
      end
   endtask
