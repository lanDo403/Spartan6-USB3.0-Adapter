   // Scoreboard state:
   // - external acceptance: expected payload words and TX/RX compare helpers
   reg [31:0]      exp_words [0:MAX_WORDS-1];
   reg [BE_LEN-1:0] exp_be   [0:MAX_WORDS-1];
   integer         exp_words_n;
   integer         tx_words_n;
   integer         rx_words_n;
   integer         tx_total_words_n;
   integer         cmd_valid_pulses_n;
   integer         cmd_event_pulses_n;
   reg             rx_payload_check_en;
   reg             tx_stream_only_mode;
   reg [DATA_LEN-1:0] tx_captured_words [0:TX_CAPTURE_WORDS_MAX-1];
   reg [BE_LEN-1:0]   tx_captured_be    [0:TX_CAPTURE_WORDS_MAX-1];

   task scoreboard_powerup_init;
      integer cap_i;
      begin
         exp_words_n = 0;
         tx_words_n = 0;
         rx_words_n = 0;
         tx_total_words_n = 0;
         cmd_valid_pulses_n = 0;
         cmd_event_pulses_n = 0;
         rx_payload_check_en = 1'b0;
         tx_stream_only_mode = 1'b0;
         for (cap_i = 0; cap_i < TX_CAPTURE_WORDS_MAX; cap_i = cap_i + 1) begin
            tx_captured_words[cap_i] = {DATA_LEN{1'b0}};
            tx_captured_be[cap_i] = {BE_LEN{1'b0}};
         end
      end
   endtask

   function automatic status_t build_expected_status(
      input logic loopback_mode_i,
      input logic service_frame_error_i,
      input logic tx_fifo_empty_i,
      input logic tx_fifo_full_i,
      input logic loopback_fifo_empty_i,
      input logic loopback_fifo_full_i
   );
      begin
         build_expected_status.loopback_mode = loopback_mode_i;
         build_expected_status.service_frame_error = service_frame_error_i;
         build_expected_status.tx_fifo_empty = tx_fifo_empty_i;
         build_expected_status.tx_fifo_full = tx_fifo_full_i;
         build_expected_status.loopback_fifo_empty = loopback_fifo_empty_i;
         build_expected_status.loopback_fifo_full = loopback_fifo_full_i;
      end
   endfunction

   // Encodes the public status bitfield so tests compare against the same layout as the RTL.
   function automatic [DATA_LEN-1:0] build_status_word(
      input logic loopback_mode_i,
      input logic service_frame_error_i,
      input logic tx_fifo_empty_i,
      input logic tx_fifo_full_i,
      input logic loopback_fifo_empty_i,
      input logic loopback_fifo_full_i
   );
      begin
         build_status_word = pack_status(build_expected_status(loopback_mode_i,
                                                               service_frame_error_i,
                                                               tx_fifo_empty_i,
                                                               tx_fifo_full_i,
                                                               loopback_fifo_empty_i,
                                                               loopback_fifo_full_i));
      end
   endfunction

   task scoreboard_reset_command_counters;
      begin
         cmd_valid_pulses_n = 0;
         cmd_event_pulses_n = 0;
      end
   endtask

   task expect_command_event_counts(
      input [1023:0] ctx,
      input integer  expected_events,
      input integer  expected_known
   );
      begin
         if (cmd_event_pulses_n !== expected_events) begin
            $display("ERROR: %0s cmd_event_pulses_n=%0d expected=%0d",
                     ctx, cmd_event_pulses_n, expected_events);
            fail("service command event count mismatch");
         end
         if (cmd_valid_pulses_n !== expected_known) begin
            $display("ERROR: %0s cmd_valid_pulses_n=%0d expected=%0d",
                     ctx, cmd_valid_pulses_n, expected_known);
            fail("known service command count mismatch");
         end
      end
   endtask

   task expect_known_command_accepted(input [1023:0] ctx);
      begin
         expect_command_event_counts(ctx, 1, 1);
      end
   endtask

   task expect_no_known_command_event(input [1023:0] ctx);
      begin
         expect_command_event_counts(ctx, 0, 0);
      end
   endtask

   task expect_loopback_mode(
      input         expected_mode,
      input [1023:0] ctx
   );
      begin
         if (dut.loopback_mode_ft !== expected_mode) begin
            $display("ERROR: %0s loopback_mode_ft=%b expected=%b",
                     ctx, dut.loopback_mode_ft, expected_mode);
            fail("loopback mode side effect mismatch");
         end
      end
   endtask

   // Classification: external acceptance. Compare raw EP82 capture against exp_words/exp_be.
   task expect_captured_expected_words(
      input integer word_count
   );
      integer i;
      begin
         if (tx_total_words_n !== word_count) begin
            $display("ERROR: tx_total_words_n=%0d expected=%0d", tx_total_words_n, word_count);
            fail("captured EP82 payload length mismatch");
         end

         for (i = 0; i < word_count; i = i + 1)
            expect_captured_tx_word(i, exp_words[i], exp_be[i]);
      end
   endtask

   task scoreboard_observe_tx_payload_word(
      input integer        wi,
      input [DATA_LEN-1:0] got_data,
      input [BE_LEN-1:0]   got_be
   );
      begin
         if (dut.loopback_mode_ft)
            tb_cov_mark_loopback_payload(got_be, exp_words_n);
         else
            tb_cov_mark_normal_payload_keep(got_be);
         expect_tx_word(wi, got_data, got_be);
      end
   endtask

   task scoreboard_observe_rx_payload_word(
      input integer        wi,
      input [DATA_LEN-1:0] got_data,
      input [BE_LEN-1:0]   got_be
   );
      begin
         if (dut.loopback_mode_ft)
            tb_cov_mark_loopback_payload(got_be, exp_words_n);
         expect_rx_word(wi, got_data, got_be);
      end
   endtask

   // Classification: external acceptance. Payload comparators for exact word-for-word scenarios.
   task expect_tx_word(
      input integer        wi,
      input [DATA_LEN-1:0] got_data,
      input [BE_LEN-1:0]   got_be
   );
      begin
         if (wi >= exp_words_n) begin
            fail("unexpected FT601 TX word");
         end
         else begin
            if (got_data !== exp_words[wi]) begin
               $display("ERROR: TX word [%0d] got=%h expected=%h", wi, got_data, exp_words[wi]);
               fail("FT601 TX word mismatch");
            end
            if (got_be !== exp_be[wi]) begin
               $display("ERROR: TX BE [%0d] got=%h expected=%h", wi, got_be, exp_be[wi]);
               fail("FT601 TX byte-enable mismatch");
            end
         end
      end
   endtask

   task expect_rx_word(
      input integer        wi,
      input [DATA_LEN-1:0] got_data,
      input [BE_LEN-1:0]   got_be
   );
      begin
         if (wi >= exp_words_n) begin
            fail("unexpected FT601 RX word");
         end
         else begin
            if (got_data !== exp_words[wi]) begin
               $display("ERROR: RX word [%0d] got=%h expected=%h", wi, got_data, exp_words[wi]);
               fail("FT601 RX word mismatch");
            end
            if (got_be !== exp_be[wi]) begin
               $display("ERROR: RX BE [%0d] got=%h expected=%h", wi, got_be, exp_be[wi]);
               fail("FT601 RX byte-enable mismatch");
            end
         end
      end
   endtask

   task wait_for_tx_words(
      input integer expected_words,
      input integer timeout_cycles
   );
      integer i;
      begin
         for (i = 0; i < timeout_cycles; i = i + 1) begin
            if (tx_words_n == expected_words)
               i = timeout_cycles;
            else
               @(negedge ft_clk);
         end

         if (tx_words_n !== expected_words) begin
            $display("ERROR: TX timeout, got=%0d expected=%0d", tx_words_n, expected_words);
            fail("TX word wait timeout");
         end
      end
   endtask

   task wait_for_tx_total_words(
      input integer expected_words,
      input integer timeout_cycles
   );
      integer i;
      begin
         for (i = 0; i < timeout_cycles; i = i + 1) begin
            if (tx_total_words_n == expected_words)
               i = timeout_cycles;
            else
               @(negedge ft_clk);
         end

         if (tx_total_words_n !== expected_words) begin
            $display("ERROR: TX total-word timeout, got=%0d expected=%0d", tx_total_words_n, expected_words);
            fail("TX total-word wait timeout");
         end
      end
   endtask

   task expect_payload_sequence(
      input integer  word_count,
      input integer  timeout_cycles,
      input [1023:0] ctx
   );
      begin
         if (tx_stream_only_mode)
            fail("payload sequence check requires payload scoreboard mode");
         wait_for_tx_words(word_count, timeout_cycles);
         if (tx_total_words_n < word_count) begin
            $display("ERROR: %0s tx_total_words_n=%0d expected_at_least=%0d",
                     ctx, tx_total_words_n, word_count);
            fail("payload sequence capture shorter than expected");
         end
      end
   endtask

   task expect_captured_tx_word(
      input integer        wi,
      input [DATA_LEN-1:0] expected_data,
      input [BE_LEN-1:0]   expected_be
   );
      begin
         if (wi >= tx_total_words_n) begin
            fail("captured TX stream is shorter than expected");
         end
         else if (wi >= TX_CAPTURE_WORDS_MAX) begin
            fail("captured TX stream index exceeds TX_CAPTURE_WORDS_MAX");
         end
         else begin
            if (tx_captured_words[wi] !== expected_data) begin
               $display("ERROR: TX captured word [%0d] got=%h expected=%h", wi, tx_captured_words[wi], expected_data);
               fail("captured TX word mismatch");
            end
            if (tx_captured_be[wi] !== expected_be) begin
               $display("ERROR: TX captured BE [%0d] got=%h expected=%h", wi, tx_captured_be[wi], expected_be);
               fail("captured TX byte-enable mismatch");
            end
         end
      end
   endtask

   task find_status_magic_in_capture(
      input  integer max_stale_words,
      output integer status_index
   );
      integer i;
      begin
         status_index = -1;
         for (i = 0; i < tx_total_words_n; i = i + 1) begin
            if ((tx_captured_words[i] === STATUS_MAGIC) &&
                (tx_captured_be[i] === FULL_BE) &&
                (status_index < 0))
               status_index = i;
         end

         if (status_index < 0)
            fail("STATUS_MAGIC was not found in captured EP82 stream");
         if (status_index > max_stale_words) begin
            $display("ERROR: status_index=%0d max_stale_words=%0d",
                     status_index, max_stale_words);
            fail("too many stale payload words before status response");
         end
      end
   endtask

   task expect_status_frame_at(
      input integer        first_word_index,
      input [DATA_LEN-1:0] expected_status_word
   );
      begin
         expect_captured_tx_word(first_word_index, STATUS_MAGIC, FULL_BE);
         expect_captured_tx_word(first_word_index + 1, expected_status_word, FULL_BE);
      end
   endtask

   task expect_status_response(
      input integer        max_stale_words,
      input [DATA_LEN-1:0] expected_status_word
   );
      integer status_index;
      begin
         find_status_magic_in_capture(max_stale_words, status_index);
         if ((status_index + 1) >= tx_total_words_n) begin
            $display("ERROR: status_index=%0d tx_total_words_n=%0d",
                     status_index, tx_total_words_n);
            fail("status response is missing status_word after STATUS_MAGIC");
         end
         tb_cov_mark_get_status_stale_prefix(status_index);
         expect_status_frame_at(status_index, expected_status_word);
      end
   endtask

   task expect_only_status_response(
      input [DATA_LEN-1:0] expected_status_word
   );
      begin
         if (tx_total_words_n !== 2) begin
            $display("ERROR: tx_total_words_n=%0d expected=2", tx_total_words_n);
            fail("exactly two TX words are expected for a pure status response");
         end
         expect_status_response(0, expected_status_word);
      end
   endtask

   task expect_captured_status_then_expected_words(
      input [DATA_LEN-1:0] expected_status_word,
      input integer        payload_word_count,
      input integer        max_stale_words
   );
      integer status_index;
      integer i;
      integer expected_total;
      begin
         find_status_magic_in_capture(max_stale_words, status_index);
         expected_total = status_index + 2 + payload_word_count;
         if (tx_total_words_n !== expected_total) begin
            $display("ERROR: tx_total_words_n=%0d expected=%0d", tx_total_words_n, expected_total);
            fail("shared EP82 status+payload length mismatch");
         end

         tb_cov_mark_get_status_stale_prefix(status_index);
         expect_status_frame_at(status_index, expected_status_word);
         for (i = 0; i < payload_word_count; i = i + 1)
            expect_captured_tx_word(status_index + 2 + i, exp_words[i], exp_be[i]);
      end
   endtask

   // Classification: protocol invariant helper.
   task expect_no_unexpected_tx(
      input integer  cycles,
      input [1023:0] ctx
   );
      integer start_words;
      begin
         start_words = tx_total_words_n;
         wait_ft_cycles(cycles);
         if (tx_total_words_n !== start_words) begin
            $display("ERROR: %0s tx_total_words_n changed from %0d to %0d",
                     ctx, start_words, tx_total_words_n);
            fail("FT601 transmitted data while TXE_N was inactive");
         end
      end
   endtask

   task expect_no_tx_for_cycles(input integer cycles);
      begin
         expect_no_unexpected_tx(cycles, "unexpected FT601 TX activity");
      end
   endtask
