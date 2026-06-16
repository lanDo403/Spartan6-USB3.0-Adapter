   // Simple timing helpers for the FT clock domain and FT601 host-side control.
   task wait_ft_cycles(input integer cycles);
      integer i;
      begin
         for (i = 0; i < cycles; i = i + 1)
            @(negedge ft_clk);
      end
   endtask

   task ft_set_txe_now(input val);
      begin
         #1;
         ft_txe_n = val;
      end
   endtask

   task ft_drive_rx_now(
      input [DATA_LEN-1:0] data_i,
      input [BE_LEN-1:0]   be_i,
      input                drive_en_i,
      input                rxf_n_i
   );
      begin
         #1;
         host_drive_en = drive_en_i;
         host_be_drv   = be_i;
         host_data_drv = data_i;
         ft_rxf_n      = rxf_n_i;
      end
   endtask

   task host_idle;
      begin
         #1;
         ft_txe_n = 1'b1;
         ft_rxf_n = 1'b1;
         host_drive_en = 1'b0;
         host_data_drv = {DATA_LEN{1'b0}};
         host_be_drv = {BE_LEN{1'b0}};
      end
   endtask

   task host_send_raw_word(
      input ft601_word_t word
   );
      integer timeout;
      begin
         @(posedge ft_clk);
         ft_drive_rx_now(word.data, word.keep, 1'b1, 1'b0);

         timeout = 0;
         while ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("host raw FT601 RX word transaction did not start");
         end

         @(posedge ft_clk);
         if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
            fail("host raw FT601 RX word read has an unexpected gap");
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);

         timeout = 0;
         while ((ft_rd_n !== 1'b1) || (ft_oe_n !== 1'b1)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("host raw FT601 RX word transaction did not complete");
         end

         @(posedge ft_clk);
         wait_for_ft_rx_idle();
         host_idle();
         wait_ft_cycles(3);
      end
   endtask

   task host_read_words_capture(
      input  integer max_words,
      output integer word_count
   );
      integer quiet_count;
      integer timeout;
      integer last_total_words;
      begin
         if (max_words < 0)
            fail("host_read_words_capture max_words must be non-negative");
         if (max_words > TX_CAPTURE_WORDS_MAX)
            fail("host_read_words_capture max_words exceeds TX_CAPTURE_WORDS_MAX");

         clear_monitors();
         tx_stream_only_mode = 1'b1;
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);

         quiet_count = 0;
         timeout = 0;
         last_total_words = -1;
         while ((tx_total_words_n < max_words) &&
                (quiet_count < 8) &&
                (timeout < 40000)) begin
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

         if (timeout >= 40000)
            fail("host_read_words_capture timed out");

         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         tx_stream_only_mode = 1'b0;
         word_count = tx_total_words_n;
      end
   endtask

`ifdef TB_HAS_SV_QUEUE_STRUCT
   task automatic host_read_words(
      input int max_words,
      output ft601_word_t words[$]
   );
      integer i;
      integer word_count;
      begin
         host_read_words_capture(max_words, word_count);
         words.delete();
         for (i = 0; i < word_count; i = i + 1)
            words.push_back(make_word(tx_captured_words[i], tx_captured_be[i]));
      end
   endtask
`endif

   // Wait until the FT601 FSM fully returns to ARB/idle after RX or TX traffic.
   task wait_for_ft_rx_idle;
      integer timeout;
      begin
         timeout = 0;
         while ((((ft_rd_n !== 1'b1) || (ft_oe_n !== 1'b1)) || (dut.ft601_fsm.state !== FSM_ARB)) && (timeout < 64)) begin
            @(posedge ft_clk);
            timeout = timeout + 1;
         end

         if ((ft_rd_n !== 1'b1) || (ft_oe_n !== 1'b1) || (dut.ft601_fsm.state !== FSM_ARB))
            fail("FT601 RX path did not return to ARB/idle");
      end
   endtask

   task wait_for_ft_tx_idle;
      integer timeout;
      begin
         timeout = 0;
         while (((ft_wr_n !== 1'b1) || (dut.ft601_fsm.state !== FSM_ARB)) && (timeout < 64)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;
            timeout = timeout + 1;
         end

         if ((ft_wr_n !== 1'b1) || (dut.ft601_fsm.state !== FSM_ARB))
            fail("FT601 TX path did not return to ARB/idle");
      end
   endtask

   // FT601 RX stimulus generators for contiguous bursts and bursts with deliberate packet gaps.
   task drive_ft_loopback_stream;
      integer i;
      integer timeout;
      begin
         if (exp_words_n <= 0)
            fail("loopback stimulus is empty");

         @(posedge ft_clk);
         ft_drive_rx_now(exp_words[0], exp_be[0], 1'b1, 1'b0);

         timeout = 0;
         while ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("FT601 RX burst did not start");
         end

         for (i = 0; i < exp_words_n; i = i + 1) begin
            @(posedge ft_clk);
            if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
               fail("RX burst has an unexpected gap");
            if (i + 1 < exp_words_n)
               ft_drive_rx_now(exp_words[i + 1], exp_be[i + 1], 1'b1, 1'b0);
            else
               ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);
         end
      end
   endtask

   task drive_first_expected_loopback_words(
      input integer count
   );
      integer i;
      integer timeout;
      begin
         if (count <= 0)
            fail("loopback burst helper requires a positive word count");
         if (count > exp_words_n)
            fail("loopback burst helper count exceeds expected stimulus size");

         @(posedge ft_clk);
         ft_drive_rx_now(exp_words[0], exp_be[0], 1'b1, 1'b0);

         timeout = 0;
         while ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("short FT601 RX burst did not start");
         end

         for (i = 0; i < count; i = i + 1) begin
            @(posedge ft_clk);
            if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
               fail("short RX burst has an unexpected gap");
            if (i + 1 < count)
               ft_drive_rx_now(exp_words[i + 1], exp_be[i + 1], 1'b1, 1'b0);
            else
               ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);
         end
      end
   endtask

   task drive_expected_loopback_words_with_rx_gaps(
      input integer count,
      input integer gap_interval,
      input integer gap_cycles
   );
      integer i;
      integer chunk_left;
      integer timeout;
      begin
         if (count <= 0)
            fail("gapped RX burst requires a positive word count");
         if (count > exp_words_n)
            fail("gapped RX burst count exceeds expected stimulus size");

         i = 0;
         while (i < count) begin
            chunk_left = gap_interval;
            if (chunk_left <= 0)
               chunk_left = count;
            if (chunk_left > (count - i))
               chunk_left = count - i;

            @(posedge ft_clk);
            ft_drive_rx_now(exp_words[i], exp_be[i], 1'b1, 1'b0);

            timeout = 0;
            while ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0)) begin
               @(negedge ft_clk);
               timeout = timeout + 1;
               if (timeout > 128)
                  fail("gapped FT601 RX burst did not start");
            end

            while (chunk_left > 0) begin
               @(posedge ft_clk);
               if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
                  fail("gapped RX burst has an unexpected gap before packet boundary");
               if ((chunk_left > 1) && (i + 1 < count))
                  ft_drive_rx_now(exp_words[i + 1], exp_be[i + 1], 1'b1, 1'b0);
               else
                  ft_drive_rx_now(exp_words[i], exp_be[i], 1'b1, 1'b1);
               i = i + 1;
               chunk_left = chunk_left - 1;
            end

            if (i < count) begin
               tb_cov_mark_rxf_backpressure();
               wait_ft_cycles(gap_cycles);
            end
         end
      end
   endtask

   // Service-frame injectors for valid commands and malformed service-error checks.
   task send_ft_command_frame(
      input [DATA_LEN-1:0] cmd_word
   );
      integer timeout;
      begin
         if (TB_VERBOSE_COMMAND)
            $display("INFO: Sending FT601 command frame magic=%h opcode=%h", CMD_MAGIC, cmd_word);

         tb_cov_mark_command(cmd_word);

         @(posedge ft_clk);
         ft_drive_rx_now(CMD_MAGIC, FULL_BE, 1'b1, 1'b0);

         timeout = 0;
         while ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("FT601 command frame RX transaction did not start");
         end

         @(posedge ft_clk);
         if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
            fail("command frame magic read has an unexpected gap");
         ft_drive_rx_now(cmd_word, FULL_BE, 1'b1, 1'b0);

         @(posedge ft_clk);
         if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
            fail("command frame opcode read has an unexpected gap");
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);

         timeout = 0;
         while ((ft_rd_n !== 1'b1) || (ft_oe_n !== 1'b1)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("FT601 command frame RX transaction did not complete");
         end

         @(posedge ft_clk);
         wait_for_ft_rx_idle();
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);
         wait_ft_cycles(3);
      end
   endtask

   task send_malformed_service_frame;
      integer timeout;
      begin
         @(posedge ft_clk);
         ft_drive_rx_now(CMD_MAGIC, FULL_BE, 1'b1, 1'b0);

         timeout = 0;
         while ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("malformed service frame RX transaction did not start");
         end

         @(posedge ft_clk);
         if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
            fail("malformed service frame magic read has an unexpected gap");
         ft_drive_rx_now(CMD_GET_STATUS, {BE_LEN{1'b0}}, 1'b1, 1'b0);

         @(posedge ft_clk);
         if ((ft_rd_n !== 1'b0) || (ft_oe_n !== 1'b0))
            fail("malformed service frame opcode read has an unexpected gap");
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);

         timeout = 0;
         while ((ft_rd_n !== 1'b1) || (ft_oe_n !== 1'b1)) begin
            @(negedge ft_clk);
            timeout = timeout + 1;
            if (timeout > 64)
               fail("malformed service frame RX transaction did not complete");
         end

         @(posedge ft_clk);
         wait_for_ft_rx_idle();
         ft_drive_rx_now({DATA_LEN{1'b0}}, {BE_LEN{1'b0}}, 1'b0, 1'b1);
         wait_ft_cycles(3);
      end
   endtask

   task transmit_expected_words_with_txe_gaps(
      input integer expected_count,
      input integer gap_interval,
      input integer gap_cycles
   );
      integer timeout;
      integer last_count;
      begin
         timeout = 0;
         last_count = tx_words_n;
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);

         while ((tx_words_n < expected_count) && (timeout < 40000)) begin
            @(posedge ft_clk);
            #TB_POSEDGE_SAMPLE_DELAY;

            if (tx_words_n != last_count) begin
               last_count = tx_words_n;
               timeout = 0;
               if ((tx_words_n < expected_count) &&
                   (gap_interval > 0) &&
                   ((tx_words_n % gap_interval) == 0)) begin
                  tb_cov_mark_txe_backpressure();
                  ft_set_txe_now(1'b1);
                  wait_ft_cycles(gap_cycles);
                  ft_set_txe_now(1'b0);
               end
            end
            else begin
               timeout = timeout + 1;
            end
         end

         if (tx_words_n !== expected_count)
            fail("gapped TX did not transmit the expected number of words");

         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
      end
   endtask
