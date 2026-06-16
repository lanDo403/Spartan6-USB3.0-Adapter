   // Runtime state and policy.
   // Default mode matches the legacy fail-fast behavior. Define TB_ACCUMULATE_ERRORS
   // during compilation to keep running after fail() and report aggregate errors.
`ifdef TB_ACCUMULATE_ERRORS
   localparam TB_FAIL_FAST = 1'b0;
`else
   localparam TB_FAIL_FAST = 1'b1;
`endif

`ifndef TB_WATCHDOG_FT_CYCLES
`define TB_WATCHDOG_FT_CYCLES 200000
`endif

   localparam integer TB_WATCHDOG_FT_CYCLES = `TB_WATCHDOG_FT_CYCLES;

   integer tb_error_count;
   reg     tb_regression_done;

   task runtime_powerup_init;
      begin
         tb_error_count = 0;
         tb_regression_done = 1'b0;
      end
   endtask

   task tb_print_failure_summary;
      begin
         $display("TEST FAILED. errors=%0d words=%0d", tb_error_count, exp_words_n);
      end
   endtask

   task fail(input [1023:0] msg);
      begin
         tb_error_count = tb_error_count + 1;
         $display("ERROR: %0s", msg);
         if (TB_FAIL_FAST) begin
            tb_regression_done = 1'b1;
            tb_print_failure_summary();
            $finish;
         end
      end
   endtask

   // Scenario banners keep the regression log readable.
   task scenario_start(input [1023:0] name);
      begin
         $display("SCENARIO START [%0d ns] %0s", $time, name);
      end
   endtask

   task scenario_end(input [1023:0] name);
      begin
         $display("SCENARIO END   [%0d ns] %0s", $time, name);
      end
   endtask

   task tb_finish_regression;
      begin
         tb_regression_done = 1'b1;
         if (tb_error_count == 0) begin
            $display("TEST PASSED. Universal bitstream flow verified, words=%0d", exp_words_n);
         end
         else begin
            tb_print_failure_summary();
         end
         $finish;
      end
   endtask

   initial begin
      repeat (TB_WATCHDOG_FT_CYCLES)
         @(posedge ft_clk);

      if (!tb_regression_done) begin
         fail("regression watchdog timeout");
         tb_regression_done = 1'b1;
         if (!TB_FAIL_FAST)
            tb_print_failure_summary();
         $finish;
      end
   end
