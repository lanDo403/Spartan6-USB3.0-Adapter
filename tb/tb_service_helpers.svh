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

   // White-box helper boundary: scenarios should call these named checks instead
   // of reaching into dut.* directly. These points validate internal state that
   // is either not observable on FT601 pins or would require perturbing stimulus
   // with an extra status transaction.
   task expect_internal_normal_fifo_empty(
      input [1023:0] ctx
   );
      begin
         if (dut.normal_fifo_empty !== 1'b1) begin
            $display("ERROR: %0s normal_fifo_empty=%b", ctx, dut.normal_fifo_empty);
            fail("normal FIFO must be empty");
         end
      end
   endtask

   task expect_internal_loopback_fifo_empty(
      input [1023:0] ctx
   );
      begin
         if (dut.loopback_fifo_empty !== 1'b1) begin
            $display("ERROR: %0s loopback_fifo_empty=%b", ctx, dut.loopback_fifo_empty);
            fail("loopback FIFO must be empty");
         end
      end
   endtask

   task sample_internal_loopback_fifo_empty(
      input [1023:0] ctx,
      output reg     empty_o
   );
      begin
         if ((dut.loopback_fifo_empty !== 1'b0) &&
             (dut.loopback_fifo_empty !== 1'b1)) begin
            $display("ERROR: %0s loopback_fifo_empty=%b", ctx, dut.loopback_fifo_empty);
            fail("loopback FIFO empty flag is unknown");
         end
         empty_o = dut.loopback_fifo_empty;
      end
   endtask

   task expect_internal_loopback_payload_pending(
      input [1023:0] ctx,
      output reg     loopback_fifo_empty_o
   );
      integer timeout;
      begin
         timeout = 0;
         while ((dut.loopback_fifo_empty !== 1'b0) &&
                (dut.loopback_fifo_axis_tvalid !== 1'b1) &&
                (timeout < 512)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;
            timeout = timeout + 1;
         end

         if ((dut.loopback_fifo_empty !== 1'b0) &&
             (dut.loopback_fifo_axis_tvalid !== 1'b1))
            fail("loopback payload did not remain pending before status request");

         sample_internal_loopback_fifo_empty(ctx, loopback_fifo_empty_o);
      end
   endtask

   task expect_internal_status_payload_blocking(
      input [1023:0] ctx
   );
      begin
         if (dut.status_payload_block !== 1'b1) begin
            $display("ERROR: %0s status_payload_block=%b", ctx, dut.status_payload_block);
            fail("payload must be blocked while status response is pending");
         end
         if (dut.loopback_fifo_ren !== 1'b0) begin
            $display("ERROR: %0s loopback_fifo_ren=%b", ctx, dut.loopback_fifo_ren);
            fail("loopback FIFO read must not occur while status window blocks payload");
         end
      end
   endtask

   task expect_internal_mode_switch_commit_after_idle(
      input         expected_mode,
      input integer timeout_cycles,
      input [1023:0] ctx
   );
      integer timeout;
      reg     busy_seen;
      begin
         timeout = 0;
         busy_seen = 1'b0;
         while ((dut.loopback_mode_ft !== expected_mode) && (timeout < timeout_cycles)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;
            if (dut.mode_switch_busy_ft)
               busy_seen = 1'b1;
            if ((dut.loopback_mode_ft === expected_mode) && (dut.fsm_idle_o !== 1'b1))
               fail("mode committed before FT path became idle");
            timeout = timeout + 1;
         end

         if (dut.loopback_mode_ft !== expected_mode) begin
            $display("ERROR: %0s loopback_mode_ft=%b expected=%b",
                     ctx, dut.loopback_mode_ft, expected_mode);
            fail("mode switch did not commit");
         end
         if (!busy_seen)
            fail("mode switch busy state was not observed");
      end
   endtask

   task expect_internal_turnaround_before_read(
      input integer  timeout_cycles,
      input [1023:0] ctx
   );
      integer timeout;
      reg     turnaround_seen;
      begin
         timeout = 0;
         turnaround_seen = 1'b0;
         while (((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0)) &&
                (timeout < timeout_cycles)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;
            if (dut.ft601_fsm.state === TB_FSM_TURNAROUND)
               turnaround_seen = 1'b1;
            timeout = timeout + 1;
         end

         if (!turnaround_seen)
            fail("RX priority must pass through TURNAROUND");
         if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
            fail("RX priority request did not reach FT601 read phase");
      end
   endtask

   task wait_for_internal_reset_release(
      input [1023:0] ctx
   );
      integer gpio_release_cycles;
      integer ft_release_cycles;
      begin
         gpio_release_cycles = 0;
         while ((dut.gpio_rst_n_i !== 1'b1) && (gpio_release_cycles < 4)) begin
            @(posedge gpio_clk);
            gpio_release_cycles = gpio_release_cycles + 1;
         end
         if (dut.gpio_rst_n_i !== 1'b1)
            fail("gpio reset synchronizer did not release");

         ft_release_cycles = 0;
         while ((dut.ft_rst_n_i !== 1'b1) && (ft_release_cycles < 4)) begin
            @(posedge ft_clk);
            ft_release_cycles = ft_release_cycles + 1;
         end
         if (dut.ft_rst_n_i !== 1'b1)
            fail("FT reset synchronizer did not release");
      end
   endtask

   task expect_internal_loopback_mode_sync(
      input         expected_mode,
      input [1023:0] ctx
   );
      begin
         expect_loopback_mode(expected_mode, ctx);
         if (dut.loopback_mode_gpio !== expected_mode) begin
            $display("ERROR: %0s loopback_mode_gpio=%b expected=%b",
                     ctx, dut.loopback_mode_gpio, expected_mode);
            fail("loopback mode did not synchronize into GPIO domain");
         end
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
