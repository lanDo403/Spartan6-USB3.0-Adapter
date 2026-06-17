   // RX priority: an RX request during TX must force TURNAROUND before read.
   task run_ft601_turnaround_rx_priority;
      integer timeout;
      begin
         scenario_start("ft601_turnaround_rx_priority");
         tb_reset();
         build_counter_expected_words(3);
         clear_monitors();

         send_gpio_word(exp_words[0]);
         send_gpio_word(exp_words[1]);
         send_gpio_word(exp_words[2]);
         wait_gpio_cycles(8);

         @(posedge ft_clk);
         ft_set_txe_now(1'b0);

         timeout = 0;
         while ((ft_wr_n !== 1'b0) && (timeout < 256)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;
            timeout = timeout + 1;
         end
         if (ft_wr_n !== 1'b0)
            fail("REQ-FT-003 TX burst did not start before RX priority request");

         ft_drive_rx_now(32'hCAFE_0001, FULL_BE, 1'b1, 1'b0);

         expect_internal_turnaround_before_read(256, "REQ-FT-003");

         @(posedge ft_clk);
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);
         wait_for_ft_rx_idle();

         ft_set_txe_now(1'b0);
         expect_payload_sequence(3, 4000, "REQ-FT-003 normal payload after RX takeover");
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();

         tb_cov_mark_req_ft601_turnaround_rx_priority();
         build_expected_words();
         scenario_end("ft601_turnaround_rx_priority");
      end
   endtask

   // RXF_N boundary: closing RX must not commit stale or partial words.
   task run_ft601_rxf_boundary;
      begin
         scenario_start("ft601_rxf_boundary");
         tb_reset();
         set_loopback_via_status();
         build_counter_expected_words(4);
         clear_monitors();
         ft_set_txe_now(1'b1);
         rx_payload_check_en = 1'b1;

         drive_expected_loopback_words_with_rx_gaps(4, 1, 3);
         wait_for_ft_rx_idle();
         host_idle();
         wait_ft_cycles(4);

         if (rx_words_n !== 4) begin
            $display("ERROR: REQ-RX-001 rx_words_n=%0d expected=4", rx_words_n);
            fail("REQ-RX-001 stale RX word was committed at RXF_N boundary");
         end
         if (loopback_fifo_wen_n !== 4) begin
            $display("ERROR: REQ-RX-001 loopback_fifo_wen_n=%0d expected=4", loopback_fifo_wen_n);
            fail("REQ-RX-001 loopback FIFO write count mismatch");
         end

         transmit_expected_words_with_txe_gaps(4, 2, 2);
         rx_payload_check_en = 1'b0;

         tb_cov_mark_req_ft601_rxf_boundary();
         build_expected_words();
         scenario_end("ft601_rxf_boundary");
      end
   endtask
