   // Public reset smoke: pins idle, buses released, normal mode selected.
   task run_reset_boot_normal;
      begin
         scenario_start("reset_boot_normal");
         tb_cov_mark_main_reset_boot_normal();
         tb_reset();
         clear_monitors();
         if (ft_reset_n !== 1'b1)
            fail("RESET_N must be released after reset_boot_normal");
         if (ft_wr_n !== 1'b1)
            fail("WR_N must be inactive after reset_boot_normal");
         if (ft_rd_n !== 1'b1)
            fail("RD_N must be inactive after reset_boot_normal");
         if (ft_oe_n !== 1'b1)
            fail("OE_N must be inactive after reset_boot_normal");
         if (ft601_mon.data_t !== {DATA_LEN{1'b1}})
            fail("DATA bus must be tri-stated after reset_boot_normal");
         if (ft601_mon.be_t !== {BE_LEN{1'b1}})
            fail("BE bus must be tri-stated after reset_boot_normal");
         if (ft_data_bus !== {DATA_LEN{1'bz}})
            fail("DATA bus must resolve to high-Z after reset_boot_normal");
         if (ft_be_bus !== {BE_LEN{1'bz}})
            fail("BE bus must resolve to high-Z after reset_boot_normal");
         expect_loopback_mode(1'b0, "reset_boot_normal must start in normal mode");
         scenario_end("reset_boot_normal");
      end
   endtask

   // Normal path: GPIO bytes are packed and sent as ordered FT601 TX words.
   task test_gpio_mode;
      begin
         expect_loopback_mode(1'b0, "GPIO-mode test start");
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Starting GPIO to FT601 mode test");

         send_gpio_stream();
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: GPIO stimulus sent into packer/FIFO path");
         wait_gpio_cycles(8);

         tb_cov_mark_txe_backpressure();
         expect_no_unexpected_tx(8, "normal_path while TXE_N inactive");
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Confirmed TX path stays idle while TXE_N is inactive");
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: TXE_N asserted low, waiting for FT601 transmission");

         expect_payload_sequence(exp_words_n, 12000, "normal_path payload");

         if (rx_active_cycles_n != 0)
            fail("RD_N became active in GPIO TX-only mode");
         if (oe_active_cycles_n != 0)
            fail("OE_N became active in GPIO TX-only mode");
         expect_internal_normal_fifo_empty("GPIO-mode transmission");
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: GPIO mode test passed, transmitted %0d words", tx_words_n);
      end
   endtask

   // Main scenario wrapper for the GPIO-to-FT601 datapath.
   task run_normal_path;
      begin
         scenario_start("normal_path");
         tb_cov_mark_main_normal_path();
         tb_reset();
         clear_monitors();
         test_gpio_mode();
         scenario_end("normal_path");
      end
   endtask

   // FPGA_RESET must reset internal domains without pulsing FT601 RESET_N.
   task pulse_fpga_reset_only;
      integer n;
      begin
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Pulsing FPGA_RESET to exit loopback mode");
         rx_payload_check_en = 1'b0;
         tx_stream_only_mode = 1'b1;

         @(negedge gpio_clk);
         gpio_strob    = 1'b0;
         gpio_data     = {GPIO_LEN{1'b0}};
         host_idle();
         fpga_reset    = 1'b1;
         tb_cov_set_normal_mode();

         #1;
         if (ft_reset_n !== 1'b1)
            fail("RESET_N output must remain high during FPGA_RESET pulse");

         for (n = 0; n < 4; n = n + 1)
            @(posedge gpio_clk);
         for (n = 0; n < 4; n = n + 1)
            @(posedge ft_clk);

         fpga_reset = 1'b0;

         #1;
         if (ft_reset_n !== 1'b1)
            fail("RESET_N output must stay high after FPGA_RESET pulse");

         wait_for_internal_reset_release("FPGA_RESET pulse");

         wait_gpio_cycles(4);
         wait_ft_cycles(4);

         expect_internal_loopback_mode_sync(1'b0, "FPGA_RESET pulse");

         if (TB_VERBOSE_SCENARIO)
            $display("INFO: FPGA_RESET returned the design to normal mode");
      end
   endtask

   // Loopback path: host RX payload returns on the shared FT601 TX endpoint.
   task test_loopback_mode;
      begin
         expect_loopback_mode(1'b1, "Loopback-mode test start");
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Starting FT601 loopback mode test");

         ft_set_txe_now(1'b1);
         rx_payload_check_en = 1'b1;
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: TXE_N held high during FT601 receive phase");

         scoreboard_reset_command_counters();
         host_send_command(SVC_CLR_SERVICE_ERROR);
         if (rx_words_n !== 0)
            fail("control frame must not increment loopback RX payload counter");
         expect_known_command_accepted("loopback control frame");
         expect_internal_loopback_fifo_empty("loopback control frame");
         wait_gpio_cycles(4);

         drive_ft_loopback_stream();
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: FT601 RX stimulus burst driven into DUT from data_p words");
         wait_for_ft_rx_idle();
         wait_ft_cycles(4);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: DUT accepted payload words into loopback path, counted=%0d", rx_words_n);

         expect_no_unexpected_tx(8, "loopback_path while TXE_N inactive");
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Confirmed TX path stays idle while TXE_N is inactive");
         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: TXE_N asserted low, FT601 may accept loopback data");

         expect_payload_sequence(exp_words_n, 16000, "loopback_path payload");
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: DUT returned %0d words back to FT601", tx_words_n);

         if (rx_active_cycles_n == 0)
            fail("RD_N never became active in loopback mode");
         if (oe_active_cycles_n == 0)
            fail("OE_N never became active in loopback mode");
         expect_internal_loopback_fifo_empty("loopback transmission");
         rx_payload_check_en = 1'b0;
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Loopback mode test passed, looped back %0d words", tx_words_n);
      end
   endtask

   // Compact loopback transfer used after mode/reset transitions.
   task short_loopback_payload_check(input integer word_count);
      begin
         expect_loopback_mode(1'b1, "short loopback payload check");

         clear_monitors();
         ft_set_txe_now(1'b1);
         rx_payload_check_en = 1'b1;
         drive_first_expected_loopback_words(word_count);
         wait_for_ft_rx_idle();
         wait_ft_cycles(4);
         expect_no_unexpected_tx(8, "short_loopback while TXE_N inactive");

         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         expect_payload_sequence(word_count, 2000, "short_loopback payload");
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();
         rx_payload_check_en = 1'b0;
      end
   endtask

   // Main scenario wrapper for loopback enable, payload return, and reset exit.
   task run_loopback_path;
      begin
         scenario_start("loopback_path");
         tb_cov_mark_main_loopback_path();
         tb_reset();
         set_loopback_via_status();
         clear_monitors();
         test_loopback_mode();

         pulse_fpga_reset_only();
         set_loopback_via_status();
         short_loopback_payload_check(8);
         set_normal_via_status();
         scenario_end("loopback_path");
      end
   endtask

   // CMD_FT601_RESET creates only the external FT601 reset pulse.
   task check_ft601_reset_command_pulse(input expected_loopback_mode);
      begin
         clear_monitors();
         ft_set_txe_now(1'b1);
         scoreboard_reset_command_counters();
         fork
            host_send_command(SVC_FT601_RESET);
            expect_ft601_reset_pulse_2clks();
         join
         expect_known_command_accepted("CMD_FT601_RESET");
         expect_loopback_mode(expected_loopback_mode, "CMD_FT601_RESET must preserve runtime mode");
      end
   endtask

   // Service diagnostics are sticky until the matching clear command arrives.
   task check_service_error_clear;
      begin
         clear_monitors();
         scoreboard_reset_command_counters();
         send_malformed_service_frame();
         expect_no_known_command_event("malformed service frame");
         expect_status_response_bits(1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0);
         send_clear_command(SVC_CLR_SERVICE_ERROR);
         expect_status_response_bits(1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);

         send_malformed_service_frame();
         wait_ft_cycles(2);
         expect_status_response_bits(1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0);
         send_clear_command(SVC_CLR_SERVICE_ERROR);
         expect_status_response_bits(1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
      end
   endtask

   // FT601 reset command must not clear service diagnostics.
   task check_ft601_reset_preserves_service_error;
      begin
         clear_monitors();
         scoreboard_reset_command_counters();
         send_malformed_service_frame();
         expect_no_known_command_event("malformed service frame before CMD_FT601_RESET");
         check_ft601_reset_command_pulse(1'b0);
         expect_status_response_bits(1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0);
         send_clear_command(SVC_CLR_SERVICE_ERROR);
         expect_status_response_bits(1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
      end
   endtask

   // FT601 reset command must not drop normal payload already queued for TX.
   task check_ft601_reset_preserves_pending_normal_payload;
      begin
         expect_loopback_mode(1'b0, "pending normal payload reset check");

         build_counter_expected_words(1);
         clear_monitors();
         ft_set_txe_now(1'b1);
         send_gpio_word(exp_words[0]);
         wait_gpio_cycles(8);
         expect_no_unexpected_tx(4, "pending normal payload while TXE_N inactive");

         check_ft601_reset_command_pulse(1'b0);

         @(posedge ft_clk);
         ft_set_txe_now(1'b0);
         expect_payload_sequence(1, 2000, "CMD_FT601_RESET pending normal payload");
         @(posedge ft_clk);
         ft_set_txe_now(1'b1);
         wait_for_ft_tx_idle();

         build_expected_words();
      end
   endtask

   // Main scenario wrapper for status, diagnostics, mode control, and reset command.
   task run_service_control;
      begin
         scenario_start("service_control");
         tb_cov_mark_main_service_control();
         tb_reset();

         expect_status_response_bits(1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
         expect_status_response_bits(1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);

         check_service_error_clear();
         check_ft601_reset_preserves_service_error();
         check_ft601_reset_preserves_pending_normal_payload();
         check_ft601_reset_command_pulse(1'b0);
         set_loopback_via_status();
         check_ft601_reset_command_pulse(1'b1);
         set_normal_via_status();
         scenario_end("service_control");
      end
   endtask
