   // Status window: service response has priority while payload is held intact.
   task run_status_window_with_payload;
      reg     expected_loopback_fifo_empty;
      reg [DATA_LEN-1:0] expected_status;
      begin
         scenario_start("status_window_with_payload");
         tb_reset();
         set_loopback_via_status();
         build_counter_expected_words(1);

         clear_monitors();
         ft_set_txe_now(1'b1);
         rx_payload_check_en = 1'b1;
         drive_first_expected_loopback_words(1);
         wait_for_ft_rx_idle();
         host_idle();
         wait_ft_cycles(4);
         rx_payload_check_en = 1'b0;

         if (rx_words_n !== 1)
            fail("REQ-STS-002 pending loopback payload was not accepted");
         if (loopback_fifo_wen_n !== 1)
            fail("REQ-STS-002 pending loopback FIFO write count mismatch");

         expect_internal_loopback_payload_pending("REQ-STS-002 pending loopback payload",
                                                  expected_loopback_fifo_empty);

         clear_monitors();
         tx_stream_only_mode = 1'b1;
         ft_set_txe_now(1'b1);
         scoreboard_reset_command_counters();
         host_send_command(SVC_GET_STATUS);
         expect_known_command_accepted("REQ-STS-002 CMD_GET_STATUS");
         expect_status_response_pending("REQ-STS-002 status window");

         expect_internal_status_payload_blocking("REQ-STS-002 status window");

         expected_status = build_status_word(1'b1,
                                             1'b0,
                                             1'b1,
                                             1'b0,
                                             expected_loopback_fifo_empty,
                                             1'b0);
         host_capture_ep82_exact_words(2, 512);
         expect_status_response(2, expected_status);
         expect_status_response_idle("REQ-STS-002 status window");

         clear_monitors();
         ft_set_txe_now(1'b0);
         expect_payload_sequence(1, 2000, "REQ-STS-002 payload after status window");
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();

         tb_cov_mark_req_control_status_window();
         tb_cov_mark_get_status_pending_payload();
         build_expected_words();

         tb_reset();
         set_loopback_via_status();
         build_counter_expected_words(1);

         clear_monitors();
         ft_set_txe_now(1'b1);
         rx_payload_check_en = 1'b1;
         drive_first_expected_loopback_words(1);
         wait_for_ft_rx_idle();
         host_idle();
         wait_ft_cycles(4);
         rx_payload_check_en = 1'b0;

         clear_monitors();
         tx_stream_only_mode = 1'b1;
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         wait_for_tx_total_words(1, 512);
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();

         scoreboard_reset_command_counters();
         host_send_command(SVC_GET_STATUS);
         expect_known_command_accepted("REQ-STS-003 CMD_GET_STATUS with stale prefix");
         expected_status = build_status_word(1'b1,
                                             1'b0,
                                             1'b1,
                                             1'b0,
                                             1'b1,
                                             1'b0);
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         wait_for_tx_total_words(3, 512);
         expect_status_response(2, expected_status);
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         tx_stream_only_mode = 1'b0;
         expect_status_response_idle("REQ-STS-003 stale prefix status window");

         build_expected_words();
         scenario_end("status_window_with_payload");
      end
   endtask

   // Mode switch: command is accepted, but mode commit waits for safe FT idle.
   task run_mode_switch_waits_idle;
      integer timeout;
      begin
         scenario_start("mode_switch_waits_idle");
         tb_reset();
         build_counter_expected_words(8);

         send_gpio_word(exp_words[0]);
         send_gpio_word(exp_words[1]);
         send_gpio_word(exp_words[2]);
         send_gpio_word(exp_words[3]);
         send_gpio_word(exp_words[4]);
         send_gpio_word(exp_words[5]);
         send_gpio_word(exp_words[6]);
         send_gpio_word(exp_words[7]);
         wait_gpio_cycles(8);

         clear_monitors();
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);

         timeout = 0;
         while ((ft_wr_n !== 1'b0) && (timeout < 256)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;
            timeout = timeout + 1;
         end
         if (ft_wr_n !== 1'b0)
            fail("REQ-MODE-001 active FT traffic did not start before mode switch request");
         tb_cov_mark_mode_switch_active_traffic();

         scoreboard_reset_command_counters();
         host_send_command(SVC_SET_LOOPBACK);
         expect_known_command_accepted("REQ-MODE-001 CMD_SET_LOOPBACK");

         expect_internal_mode_switch_commit_after_idle(1'b1, 512, "REQ-MODE-001");

         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         send_checked_command(SVC_SET_NORMAL, "REQ-MODE-001 CMD_SET_NORMAL");
         expect_loopback_mode(1'b0, "REQ-MODE-001 SET_NORMAL");

         ft_set_txe_now(1'b0);
         expect_payload_sequence(8, 4000, "REQ-MODE-001 preserved normal payload");
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();

         tb_cov_mark_req_control_mode_switch_idle();
         build_expected_words();
         scenario_end("mode_switch_waits_idle");
      end
   endtask

   // RX router: service frames and payload words stay on separate paths.
   task run_router_demux_backpressure;
      begin
         scenario_start("router_demux_backpressure");
         tb_reset();

         build_counter_expected_words(2);
         clear_monitors();
         drive_expected_loopback_words_with_rx_gaps(2, 1, 2);
         wait_for_ft_rx_idle();
         host_idle();
         wait_ft_cycles(4);
         if (loopback_fifo_wen_n !== 0)
            fail("REQ-NORM-002 normal-mode host RX payload must not enter loopback FIFO");
         expect_command_event_counts("REQ-NORM-002 normal payload", 0, 0);

         set_loopback_via_status();
         build_counter_expected_words(1);

         clear_monitors();
         ft_set_txe_now(1'b1);
         rx_payload_check_en = 1'b1;
         scoreboard_reset_command_counters();
         host_send_command(SVC_CLR_SERVICE_ERROR);
         expect_known_command_accepted("REQ-LB-002 service command in loopback mode");
         if (rx_words_n !== 0)
            fail("REQ-LB-002 service command must not be counted as loopback payload");
         if (loopback_fifo_wen_n !== 0)
            fail("REQ-LB-002 service command must not write loopback FIFO");

         scoreboard_reset_command_counters();
         host_send_command(SVC_UNKNOWN);
         expect_command_event_counts("REQ-SVC-003 unknown opcode", 1, 0);
         expect_loopback_mode(1'b1, "REQ-SVC-003 unknown opcode must preserve mode");
         if (tx_total_words_n !== 0)
            fail("REQ-SVC-003 unknown opcode must not create a status response");
         tb_cov_mark_req_control_unknown_opcode();

         host_send_raw_word(make_word(exp_words[0], exp_be[0]));
         if (rx_words_n !== 1)
            fail("REQ-LB-002 loopback payload word was not routed to payload path");
         if (loopback_fifo_wen_n !== 1)
            fail("REQ-LB-002 loopback FIFO write count mismatch");

         ft_set_txe_now(1'b0);
         expect_payload_sequence(1, 1000, "REQ-LB-002 loopback payload after service demux");
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         rx_payload_check_en = 1'b0;

         tb_cov_mark_req_control_router_demux();
         build_expected_words();
         scenario_end("router_demux_backpressure");
      end
   endtask

   // TX arbiter: status wins first, then loopback, then normal payload.
   task run_arbiter_priority;
      reg expected_loopback_fifo_empty;
      reg [DATA_LEN-1:0] expected_status;
      begin
         scenario_start("arbiter_priority");

         tb_reset();
         set_loopback_via_status();
         build_counter_expected_words(1);
         clear_monitors();
         ft_set_txe_now(1'b1);
         rx_payload_check_en = 1'b1;
         drive_first_expected_loopback_words(1);
         wait_for_ft_rx_idle();
         host_idle();
         wait_ft_cycles(4);
         rx_payload_check_en = 1'b0;
         sample_internal_loopback_fifo_empty("REQ-ARB-001 pending loopback payload",
                                             expected_loopback_fifo_empty);

         scoreboard_reset_command_counters();
         host_send_command(SVC_GET_STATUS);
         expect_known_command_accepted("REQ-ARB-001 GET_STATUS over loopback payload");
         expect_status_response_pending("REQ-ARB-001 status priority over loopback");
         expected_status = build_status_word(1'b1,
                                             1'b0,
                                             1'b1,
                                             1'b0,
                                             expected_loopback_fifo_empty,
                                             1'b0);
         host_capture_ep82_exact_words(2, 512);
         expect_status_response(0, expected_status);
         expect_status_response_idle("REQ-ARB-001 status priority over loopback");

         clear_monitors();
         ft_set_txe_now(1'b0);
         expect_payload_sequence(1, 1000, "REQ-ARB-001 loopback payload after status");
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();

         tb_reset();
         build_counter_expected_words(1);
         send_gpio_word(exp_words[0]);
         wait_gpio_cycles(8);
         send_checked_command(SVC_SET_LOOPBACK, "REQ-ARB-001 SET_LOOPBACK with normal payload pending");
         expect_loopback_mode(1'b1, "REQ-ARB-001 SET_LOOPBACK");

         build_synthetic_expected_words(1);
         clear_monitors();
         ft_set_txe_now(1'b1);
         rx_payload_check_en = 1'b1;
         drive_first_expected_loopback_words(1);
         wait_for_ft_rx_idle();
         host_idle();
         wait_ft_cycles(4);
         rx_payload_check_en = 1'b0;

         ft_set_txe_now(1'b0);
         expect_payload_sequence(1, 1000, "REQ-ARB-001 loopback selected over pending normal");
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();

         tb_cov_mark_req_control_arbiter_priority();
         build_expected_words();
         scenario_end("arbiter_priority");
      end
   endtask
