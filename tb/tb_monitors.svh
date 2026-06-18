   // Monitor state for always-on protocol invariants and diagnostic counters.
   integer rx_active_cycles_n;
   integer oe_active_cycles_n;
   reg     rx_burst_seen;
   reg     tx_burst_seen;
   reg     tx_payload_burst_seen;
   integer ft_rx_axis_hs_n;
   integer loopback_fifo_wen_n;
   integer loopback_fifo_ren_n;
   integer tx_axis_hs_n;
   reg     prev_ft_oe_n;
   reg     prev_ft_rd_n;
   reg     prev_ft_wr_n;
   reg     prev_ft_txe_n_neg;
   // Previous-cycle snapshots used by FT601 timing checks and AXIS stall-stability assertions.
   reg                    loopback_fifo_wen_pre;
   reg [FIFO_RX_LEN-1:0]  loopback_fifo_wdata_pre;
   reg [DATA_LEN-1:0]     ft_write_data_sample;
   reg [BE_LEN-1:0]       ft_write_be_sample;
   reg [5:0]              prev_fsm_state;
   reg [1:0]              prev_cmd_mode_state;
   reg                    prev_status_payload_hold;
   reg                    prev_status_txe_low_seen;
   reg                    prev_status_req;
   reg                    prev_status_frame_active;
   reg                    prev_fsm_idle;
   reg                    prev_ft_rx_axis_stall;
   reg [DATA_LEN-1:0]     prev_ft_rx_axis_tdata;
   reg [BE_LEN-1:0]       prev_ft_rx_axis_tkeep;
   reg                    prev_loopback_payload_axis_stall;
   reg [DATA_LEN-1:0]     prev_loopback_payload_axis_tdata;
   reg [BE_LEN-1:0]       prev_loopback_payload_axis_tkeep;
   reg                    prev_normal_axis_stall;
   reg [DATA_LEN-1:0]     prev_normal_axis_tdata;
   reg [BE_LEN-1:0]       prev_normal_axis_tkeep;
   reg                    prev_loopback_axis_stall;
   reg [DATA_LEN-1:0]     prev_loopback_axis_tdata;
   reg [BE_LEN-1:0]       prev_loopback_axis_tkeep;
   reg                    prev_status_axis_stall;
   reg [DATA_LEN-1:0]     prev_status_axis_tdata;
   reg [BE_LEN-1:0]       prev_status_axis_tkeep;
   reg                    prev_tx_axis_stall;
   reg [DATA_LEN-1:0]     prev_tx_axis_tdata;
   reg [BE_LEN-1:0]       prev_tx_axis_tkeep;
   reg                    allow_status_preempt_drop;
   reg                    prev_status_tx_hold;
   integer                ft601_reset_low_cycles_n;
   reg                    ft601_reset_low_mode;

   `include "tb_assertions.svh"

   task monitor_powerup_init;
      begin
         rx_active_cycles_n = 0;
         oe_active_cycles_n = 0;
         rx_burst_seen = 1'b0;
         tx_burst_seen = 1'b0;
         tx_payload_burst_seen = 1'b0;
         prev_ft_oe_n = 1'b1;
         prev_ft_rd_n = 1'b1;
         prev_ft_wr_n = 1'b1;
         prev_ft_txe_n_neg = 1'b1;
         cmd_valid_pulses_n = 0;
         cmd_event_pulses_n = 0;
         rx_payload_check_en = 1'b0;
         tx_stream_only_mode = 1'b0;
         ft_write_data_sample = {DATA_LEN{1'b0}};
         ft_write_be_sample = {BE_LEN{1'b0}};
         prev_fsm_state = FSM_ARB;
         prev_cmd_mode_state = 2'b00;
         prev_status_payload_hold = 1'b0;
         prev_status_txe_low_seen = 1'b0;
         prev_status_req = 1'b0;
         prev_status_frame_active = 1'b0;
         prev_fsm_idle = 1'b0;
         prev_loopback_payload_axis_stall = 1'b0;
         prev_loopback_payload_axis_tdata = {DATA_LEN{1'b0}};
         prev_loopback_payload_axis_tkeep = {BE_LEN{1'b0}};
         prev_normal_axis_stall = 1'b0;
         prev_normal_axis_tdata = {DATA_LEN{1'b0}};
         prev_normal_axis_tkeep = {BE_LEN{1'b0}};
         prev_loopback_axis_stall = 1'b0;
         prev_loopback_axis_tdata = {DATA_LEN{1'b0}};
         prev_loopback_axis_tkeep = {BE_LEN{1'b0}};
         prev_status_axis_stall = 1'b0;
         prev_status_axis_tdata = {DATA_LEN{1'b0}};
         prev_status_axis_tkeep = {BE_LEN{1'b0}};
         prev_tx_axis_stall = 1'b0;
         prev_tx_axis_tdata = {DATA_LEN{1'b0}};
         prev_tx_axis_tkeep = {BE_LEN{1'b0}};
         allow_status_preempt_drop = 1'b0;
         prev_status_tx_hold = 1'b0;
         ft601_reset_low_cycles_n = 0;
         ft601_reset_low_mode = 1'b0;
      end
   endtask

   // Clears counters, capture buffers, and previous-cycle snapshots between checks.
   task clear_monitors;
      integer cap_i;
      begin
         tx_words_n = 0;
         tx_total_words_n = 0;
         rx_words_n = 0;
         rx_active_cycles_n = 0;
         oe_active_cycles_n = 0;
         rx_burst_seen = 1'b0;
         tx_burst_seen = 1'b0;
         tx_payload_burst_seen = 1'b0;
         ft_rx_axis_hs_n = 0;
         loopback_fifo_wen_n = 0;
         loopback_fifo_ren_n = 0;
         tx_axis_hs_n = 0;
         prev_ft_oe_n = ft601_mon.oe_n;
         prev_ft_rd_n = ft601_mon.rd_n;
         prev_ft_wr_n = ft601_mon.wr_n;
         prev_ft_txe_n_neg = ft601_mon.txe_n;
         cmd_valid_pulses_n = 0;
         cmd_event_pulses_n = 0;
         rx_payload_check_en = 1'b0;
         tx_stream_only_mode = 1'b0;
         ft_write_data_sample = {DATA_LEN{1'b0}};
         ft_write_be_sample = {BE_LEN{1'b0}};
         prev_fsm_state = dut.ft601_fsm.state;
         prev_cmd_mode_state = dut.cmd_decoder.mode_state_ff;
         prev_status_payload_hold = dut.service_status_policy.status_payload_hold_ff;
         prev_status_txe_low_seen = dut.service_status_policy.status_txe_low_seen_ff;
         prev_status_req = dut.status_req;
         prev_status_frame_active = dut.status_frame_active;
         prev_fsm_idle = dut.fsm_idle_o;
         prev_loopback_payload_axis_stall = 1'b0;
         prev_loopback_payload_axis_tdata = {DATA_LEN{1'b0}};
         prev_loopback_payload_axis_tkeep = {BE_LEN{1'b0}};
         prev_normal_axis_stall = 1'b0;
         prev_normal_axis_tdata = {DATA_LEN{1'b0}};
         prev_normal_axis_tkeep = {BE_LEN{1'b0}};
         prev_loopback_axis_stall = 1'b0;
         prev_loopback_axis_tdata = {DATA_LEN{1'b0}};
         prev_loopback_axis_tkeep = {BE_LEN{1'b0}};
         prev_status_axis_stall = 1'b0;
         prev_status_axis_tdata = {DATA_LEN{1'b0}};
         prev_status_axis_tkeep = {BE_LEN{1'b0}};
         prev_tx_axis_stall = 1'b0;
         prev_tx_axis_tdata = {DATA_LEN{1'b0}};
         prev_tx_axis_tkeep = {BE_LEN{1'b0}};
         prev_status_tx_hold = status_tx_hold;
         for (cap_i = 0; cap_i < TX_CAPTURE_WORDS_MAX; cap_i = cap_i + 1) begin
            tx_captured_words[cap_i] = {DATA_LEN{1'b0}};
            tx_captured_be[cap_i] = {BE_LEN{1'b0}};
         end
      end
   endtask

   // Classification: protocol invariant and diagnostic monitor.
   // - counts FT and AXIS handshakes
   // - captures transmitted words for raw EP82 reads
   // - delegates externally visible payload checks to the scoreboard
   // - feeds clocking-block sampled snapshots into tb_assertions.svh
   always @(ft601_mon.monitor_cb or negedge ft601_mon.reset_n) begin
      if (!ft601_mon.reset_n) begin
         tx_words_n <= 0;
         rx_words_n <= 0;
         rx_active_cycles_n <= 0;
         oe_active_cycles_n <= 0;
         rx_burst_seen <= 1'b0;
         tx_burst_seen <= 1'b0;
         tx_payload_burst_seen <= 1'b0;
         ft_rx_axis_hs_n <= 0;
         loopback_fifo_wen_n <= 0;
         loopback_fifo_ren_n <= 0;
         tx_axis_hs_n <= 0;
         prev_ft_oe_n  <= 1'b1;
         prev_ft_rd_n  <= 1'b1;
         prev_ft_wr_n  <= 1'b1;
         prev_ft_txe_n_neg <= 1'b1;
         loopback_fifo_wen_pre <= 1'b0;
         loopback_fifo_wdata_pre <= {FIFO_RX_LEN{1'b0}};
         ft_write_data_sample <= {DATA_LEN{1'b0}};
         ft_write_be_sample <= {BE_LEN{1'b0}};
         prev_fsm_state <= FSM_ARB;
         prev_cmd_mode_state <= 2'b00;
         prev_status_payload_hold <= 1'b0;
         prev_status_txe_low_seen <= 1'b0;
         prev_status_req <= 1'b0;
         prev_status_frame_active <= 1'b0;
         prev_fsm_idle <= 1'b0;
         prev_ft_rx_axis_stall <= 1'b0;
         prev_ft_rx_axis_tdata <= {DATA_LEN{1'b0}};
         prev_ft_rx_axis_tkeep <= {BE_LEN{1'b0}};
         prev_loopback_payload_axis_stall <= 1'b0;
         prev_loopback_payload_axis_tdata <= {DATA_LEN{1'b0}};
         prev_loopback_payload_axis_tkeep <= {BE_LEN{1'b0}};
         prev_normal_axis_stall <= 1'b0;
         prev_normal_axis_tdata <= {DATA_LEN{1'b0}};
         prev_normal_axis_tkeep <= {BE_LEN{1'b0}};
         prev_loopback_axis_stall <= 1'b0;
         prev_loopback_axis_tdata <= {DATA_LEN{1'b0}};
         prev_loopback_axis_tkeep <= {BE_LEN{1'b0}};
         prev_status_axis_stall <= 1'b0;
         prev_status_axis_tdata <= {DATA_LEN{1'b0}};
         prev_status_axis_tkeep <= {BE_LEN{1'b0}};
         prev_tx_axis_stall <= 1'b0;
         prev_tx_axis_tdata <= {DATA_LEN{1'b0}};
         prev_tx_axis_tkeep <= {BE_LEN{1'b0}};
         prev_status_tx_hold <= 1'b0;
      end
      else begin
         loopback_fifo_wen_pre <= dut.loopback_fifo_wen;
         loopback_fifo_wdata_pre <= dut.loopback_fifo_wdata;

         #TB_POSEDGE_SAMPLE_DELAY;

         if (dut.cmd_event_valid)
            cmd_event_pulses_n <= cmd_event_pulses_n + 1;

         if (dut.cmd_decoder.cmd_known)
            cmd_valid_pulses_n <= cmd_valid_pulses_n + 1;

         tb_assert_sampled_protocol_invariants();
         tb_cov_sample_passive(prev_fsm_state);

         prev_ft_rx_axis_stall <= ft_rx_axis_mon.monitor_cb.valid &&
                                  !ft_rx_axis_mon.monitor_cb.ready;
         if (ft_rx_axis_mon.monitor_cb.valid && !ft_rx_axis_mon.monitor_cb.ready) begin
            prev_ft_rx_axis_tdata <= ft_rx_axis_mon.monitor_cb.data;
            prev_ft_rx_axis_tkeep <= ft_rx_axis_mon.monitor_cb.keep;
         end

         prev_normal_axis_stall <= normal_axis_mon.monitor_cb.valid &&
                                   !normal_axis_mon.monitor_cb.ready;
         if (normal_axis_mon.monitor_cb.valid && !normal_axis_mon.monitor_cb.ready) begin
            prev_normal_axis_tdata <= normal_axis_mon.monitor_cb.data;
            prev_normal_axis_tkeep <= normal_axis_mon.monitor_cb.keep;
         end

         prev_loopback_payload_axis_stall <= loopback_payload_axis_mon.monitor_cb.valid &&
                                             !loopback_payload_axis_mon.monitor_cb.ready;
         if (loopback_payload_axis_mon.monitor_cb.valid &&
             !loopback_payload_axis_mon.monitor_cb.ready) begin
            prev_loopback_payload_axis_tdata <= loopback_payload_axis_mon.monitor_cb.data;
            prev_loopback_payload_axis_tkeep <= loopback_payload_axis_mon.monitor_cb.keep;
         end

         prev_loopback_axis_stall <= loopback_axis_mon.monitor_cb.valid &&
                                     !loopback_axis_mon.monitor_cb.ready;
         if (loopback_axis_mon.monitor_cb.valid && !loopback_axis_mon.monitor_cb.ready) begin
            prev_loopback_axis_tdata <= loopback_axis_mon.monitor_cb.data;
            prev_loopback_axis_tkeep <= loopback_axis_mon.monitor_cb.keep;
         end

         prev_status_axis_stall <= status_axis_mon.monitor_cb.valid &&
                                   !status_axis_mon.monitor_cb.ready;
         if (status_axis_mon.monitor_cb.valid && !status_axis_mon.monitor_cb.ready) begin
            prev_status_axis_tdata <= status_axis_mon.monitor_cb.data;
            prev_status_axis_tkeep <= status_axis_mon.monitor_cb.keep;
         end

         prev_tx_axis_stall <= tx_axis_mon.monitor_cb.valid && !tx_axis_mon.monitor_cb.ready;
         if (tx_axis_mon.monitor_cb.valid && !tx_axis_mon.monitor_cb.ready) begin
            prev_tx_axis_tdata <= tx_axis_mon.monitor_cb.data;
            prev_tx_axis_tkeep <= tx_axis_mon.monitor_cb.keep;
         end

         if (ft_rx_axis_mon.monitor_cb.valid && ft_rx_axis_mon.monitor_cb.ready) begin
            ft_rx_axis_hs_n <= ft_rx_axis_hs_n + 1;
            if (!rx_burst_seen) begin
               if (TB_VERBOSE_STREAM)
                  $display("INFO: FT601 RX burst started");
               rx_burst_seen <= 1'b1;
            end
         end

         if (rx_payload_check_en && loopback_fifo_wen_pre && (rx_words_n < 2))
            if (TB_VERBOSE_STREAM)
               $display("INFO: RX sample[%0d] data=%h be=%h", rx_words_n, loopback_fifo_wdata_pre[FIFO_RX_LEN-1:BE_LEN], loopback_fifo_wdata_pre[BE_LEN-1:0]);
         if (rx_payload_check_en && loopback_fifo_wen_pre) begin
            scoreboard_observe_rx_payload_word(rx_words_n, loopback_fifo_wdata_pre[FIFO_RX_LEN-1:BE_LEN], loopback_fifo_wdata_pre[BE_LEN-1:0]);
            rx_words_n <= rx_words_n + 1;
         end

         if (dut.loopback_fifo_wen)
            loopback_fifo_wen_n <= loopback_fifo_wen_n + 1;
         if (dut.loopback_fifo_ren)
            loopback_fifo_ren_n <= loopback_fifo_ren_n + 1;
         if (tx_axis_mon.monitor_cb.valid && tx_axis_mon.monitor_cb.ready)
            tx_axis_hs_n <= tx_axis_hs_n + 1;

         if (!ft601_mon.monitor_cb.wr_n) begin
            if (!tx_burst_seen) begin
               if (TB_VERBOSE_STREAM)
                  $display("INFO: FT601 TX burst started");
               tx_burst_seen <= 1'b1;
            end
            if (tx_total_words_n < TX_CAPTURE_WORDS_MAX) begin
               tx_captured_words[tx_total_words_n] <= ft601_mon.monitor_cb.data;
               tx_captured_be[tx_total_words_n] <= ft601_mon.monitor_cb.be;
            end
            tx_total_words_n <= tx_total_words_n + 1;

            if (tx_stream_only_mode) begin
               tx_payload_burst_seen <= 1'b0;
               if (TB_VERBOSE_STREAM)
                  $display("INFO: TX stream[%0d] data=%h be=%h", tx_total_words_n,
                           ft601_mon.monitor_cb.data, ft601_mon.monitor_cb.be);
            end
            else begin
               tx_payload_burst_seen <= 1'b1;
               if (tx_words_n < 2) begin
                  if (TB_VERBOSE_STREAM)
                     $display("INFO: TX sample[%0d] data=%h be=%h", tx_words_n,
                              ft601_mon.monitor_cb.data, ft601_mon.monitor_cb.be);
               end
               scoreboard_observe_tx_payload_word(tx_words_n,
                                                  ft601_mon.monitor_cb.data,
                                                  ft601_mon.monitor_cb.be);
               tx_words_n <= tx_words_n + 1;
            end
         end
         else if (prev_ft_wr_n == 1'b0) begin
            tx_payload_burst_seen <= 1'b0;
         end

         if (!ft601_mon.monitor_cb.rd_n)
            rx_active_cycles_n <= rx_active_cycles_n + 1;
         if (!ft601_mon.monitor_cb.oe_n)
            oe_active_cycles_n <= oe_active_cycles_n + 1;

         prev_ft_oe_n  <= ft601_mon.monitor_cb.oe_n;
         prev_ft_rd_n  <= ft601_mon.monitor_cb.rd_n;
         prev_ft_wr_n  <= ft601_mon.monitor_cb.wr_n;
         prev_ft_txe_n_neg <= ft601_mon.monitor_cb.txe_n;
         prev_fsm_state <= dut.ft601_fsm.state;
         prev_cmd_mode_state <= dut.cmd_decoder.mode_state_ff;
         prev_status_payload_hold <= dut.service_status_policy.status_payload_hold_ff;
         prev_status_txe_low_seen <= dut.service_status_policy.status_txe_low_seen_ff;
         prev_status_req <= dut.status_req;
         prev_status_frame_active <= dut.status_frame_active;
         prev_fsm_idle <= dut.fsm_idle_o;
         prev_status_tx_hold <= status_tx_hold;
      end
   end

   // Active write data/BE must not change inside a sampled FT601 write window.
   always @(negedge ft_clk) begin
      #1;
      if ((dut.ft_rst_n_i === 1'b1) && (ft_wr_n === 1'b0)) begin
         ft_write_data_sample = ft601_mon.data;
         ft_write_be_sample = ft601_mon.be;
         #3;
         if ((dut.ft_rst_n_i === 1'b1) && (ft_wr_n === 1'b0)) begin
            tb_assert_now(ft601_mon.data === ft_write_data_sample,
                          "REQ-FT-002 DATA bus changed inside active FT601 write window");
            tb_assert_now(ft601_mon.be === ft_write_be_sample,
                          "REQ-FT-002 BE bus changed inside active FT601 write window");
         end
      end
   end

   // CMD_FT601_RESET is an external FT601 reset pulse, not an internal RTL reset.
   always @(posedge ft_clk) begin
      #TB_POSEDGE_SAMPLE_DELAY;

      if (dut.ft_rst_n_i !== 1'b1) begin
         ft601_reset_low_cycles_n = 0;
         ft601_reset_low_mode = 1'b0;
      end
      else if (ft_reset_n === 1'b0) begin
         if (ft601_reset_low_cycles_n == 0)
            ft601_reset_low_mode = dut.loopback_mode_ft;
         else
            tb_assert_now(dut.loopback_mode_ft === ft601_reset_low_mode,
                          "REQ-RST-002 CMD_FT601_RESET must not alter loopback mode");

         ft601_reset_low_cycles_n = ft601_reset_low_cycles_n + 1;
         tb_assert_now(ft601_reset_low_cycles_n <= 2,
                       "REQ-RST-002 CMD_FT601_RESET pulse lasted longer than two FT clocks");
      end
      else begin
         if (ft601_reset_low_cycles_n != 0)
            tb_assert_now(ft601_reset_low_cycles_n == 2,
                          "REQ-RST-002 CMD_FT601_RESET pulse must last exactly two FT clocks");
         ft601_reset_low_cycles_n = 0;
      end
   end
