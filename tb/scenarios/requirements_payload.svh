   // Payload robustness: long gapped loopback bursts preserve order and byte enables.
   task run_long_gapped_loopback_payload;
      integer long_count;
      begin
         scenario_start("long_gapped_loopback_payload");
         tb_reset();
         set_loopback_via_status();

         long_count = 1100;
         build_counter_expected_words(long_count);
         clear_monitors();
         ft_set_txe_now(1'b1);
         rx_payload_check_en = 1'b1;

         drive_expected_loopback_words_with_rx_gaps(long_count, 128, 3);
         wait_for_ft_rx_idle();
         host_idle();
         wait_ft_cycles(8);

         if (rx_words_n !== long_count) begin
            $display("ERROR: REQ-BND-001 rx_words_n=%0d expected=%0d", rx_words_n, long_count);
            fail("REQ-BND-001 long gapped RX count mismatch");
         end
         if (loopback_fifo_wen_n !== long_count) begin
            $display("ERROR: REQ-BND-001 loopback_fifo_wen_n=%0d expected=%0d", loopback_fifo_wen_n, long_count);
            fail("REQ-BND-001 long gapped loopback FIFO write count mismatch");
         end

         transmit_expected_words_with_txe_gaps(long_count, 128, 2);
         if (tx_words_n !== long_count) begin
            $display("ERROR: REQ-BND-001 tx_words_n=%0d expected=%0d", tx_words_n, long_count);
            fail("REQ-BND-001 long gapped TX count mismatch");
         end

         rx_payload_check_en = 1'b0;
         tb_cov_mark_req_payload_long_gapped_loopback();
         build_expected_words();
         scenario_end("long_gapped_loopback_payload");
      end
   endtask
