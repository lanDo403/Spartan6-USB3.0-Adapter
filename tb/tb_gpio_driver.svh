   // Loads byte stimulus from data_p; later helpers repack it into expected 32-bit words.
   task load_vectors;
      integer fd_p;
      integer i;
      begin
         fd_p = $fopen("data_p", "r");
         if (fd_p == 0)
            fd_p = $fopen("source/data_p", "r");
         if (fd_p == 0)
            fail("cannot open data_p");
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Loading stimulus bytes from data_p");

         for (i = 0; i < TOTAL_WORDS; i = i + 1) begin
            if ($fscanf(fd_p, "%h\n", byte_seq_p[i]) != 1)
               fail("cannot read byte from data_p");
         end

         $fclose(fd_p);
         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Stimulus file loaded");
      end
   endtask

   // Detects the idle-byte pattern inserted into data_p to model gaps on GPIO_STROB.
   task is_pause_template_at(
      input  integer idx,
      output reg     is_pause
   );
      integer t;
      reg [7:0] expected;
      begin
         is_pause = 1'b1;

         if (idx + PAUSE_LEN > TOTAL_WORDS)
            is_pause = 1'b0;
         else begin
            for (t = 0; t < PAUSE_LEN; t = t + 1) begin
               expected = 8'h00;
               if ((t % 4) == 0)
                  expected = 8'hFF;
               if (byte_seq_p[idx + t] !== expected)
                  is_pause = 1'b0;
            end
         end
      end
   endtask

   // Software model of packer8to32 used to build the expected TX/loopback word stream.
   task append_expected_packer_cycle;
      input [GPIO_LEN-1:0] data_i;
      input                strobe_i;
      inout [1:0]          cnt;
      inout [DATA_LEN-1:0] data_shift;
      inout [BE_LEN-1:0]   keep_shift;

      reg [GPIO_LEN-1:0]   byte_w;
      reg [DATA_LEN-1:0]   data_next;
      reg [BE_LEN-1:0]     keep_next;
      begin
         byte_w = strobe_i ? data_i : {GPIO_LEN{1'b0}};
         data_next = {byte_w, data_shift[DATA_LEN-1:GPIO_LEN]};
         keep_next = {strobe_i, keep_shift[BE_LEN-1:1]};

         if (cnt == 2'd0) begin
            if (strobe_i) begin
               data_shift = {data_i, {(DATA_LEN-GPIO_LEN){1'b0}}};
               keep_shift = {1'b1, {(BE_LEN-1){1'b0}}};
               cnt = 2'd1;
            end
         end
         else if (cnt == 2'd3) begin
            if (|keep_next) begin
               exp_words[exp_words_n] = data_next;
               exp_be[exp_words_n] = keep_next;
               exp_words_n = exp_words_n + 1;
            end
            data_shift = {DATA_LEN{1'b0}};
            keep_shift = {BE_LEN{1'b0}};
            cnt = 2'd0;
         end
         else begin
            data_shift = data_next;
            keep_shift = keep_next;
            cnt = cnt + 1'b1;
         end
      end
   endtask

   // Builders for the main payload and smaller synthetic/counter-based diagnostic payloads.
   task build_expected_words;
      integer i;
      integer t;
      reg [1:0]  cnt;
      reg        pause_here;
      reg [DATA_LEN-1:0] data_shift;
      reg [BE_LEN-1:0] keep_shift;
      begin
         cnt = 2'd0;
         data_shift = {DATA_LEN{1'b0}};
         keep_shift = {BE_LEN{1'b0}};
         exp_words_n = 0;

         i = 0;
         while (i < TOTAL_WORDS) begin
            is_pause_template_at(i, pause_here);

            if (pause_here) begin
               for (t = 0; t < PAUSE_LEN; t = t + 1) begin
                  append_expected_packer_cycle(byte_seq_p[i], 1'b0, cnt, data_shift, keep_shift);
                  i = i + 1;
               end
            end
            else begin
               append_expected_packer_cycle(byte_seq_p[i], 1'b1, cnt, data_shift, keep_shift);
               i = i + 1;
            end
         end

         for (t = 0; t < 3; t = t + 1)
            append_expected_packer_cycle({GPIO_LEN{1'b0}}, 1'b0, cnt, data_shift, keep_shift);

         if (TB_VERBOSE_SCENARIO)
            $display("INFO: Built %0d expected 32-bit words", exp_words_n);
      end
   endtask

   task build_synthetic_expected_words(input integer word_count);
      integer i;
      begin
         if (word_count > MAX_WORDS)
            fail("synthetic expected word count exceeds MAX_WORDS");

         exp_words_n = word_count;
         for (i = 0; i < word_count; i = i + 1) begin
            exp_words[i] = 32'h80000000 | i[31:0];
            exp_be[i] = FULL_BE;
         end
      end
   endtask

   task build_counter_expected_words(input integer word_count);
      integer i;
      begin
         if (word_count > MAX_WORDS)
            fail("counter expected word count exceeds MAX_WORDS");

         exp_words_n = word_count;
         for (i = 0; i < word_count; i = i + 1) begin
            exp_words[i] = i + 1;
            exp_be[i] = FULL_BE;
         end
      end
   endtask

   task send_one_gpio_byte(
      input [GPIO_LEN-1:0] data_i,
      input                strobe_i
   );
      begin
         @(posedge gpio_clk);
         #1;
         gpio_data  = data_i;
         gpio_strob = strobe_i;
      end
   endtask

`ifdef TB_HAS_SV_QUEUE_PORTS
   task automatic gpio_send_bytes(
      input byte bytes[$],
      input bit  strobes[$]
   );
      integer i;
      reg [GPIO_LEN-1:0] data_i;
      begin
         if (bytes.size() != strobes.size())
            fail("gpio_send_bytes byte/strobe queue size mismatch");

         for (i = 0; i < bytes.size(); i = i + 1) begin
            data_i = bytes[i];
            send_one_gpio_byte(data_i, strobes[i]);
         end

         send_gpio_idle_cycle();
      end
   endtask
`endif

   task send_gpio_idle_cycle;
      begin
         send_one_gpio_byte({GPIO_LEN{1'b0}}, 1'b0);
      end
   endtask

   task send_gpio_stream;
      integer idx;
      integer t;
      reg pause_here;
      begin
         idx = 0;
         while (idx < TOTAL_WORDS) begin
            is_pause_template_at(idx, pause_here);

            if (pause_here) begin
               for (t = 0; t < PAUSE_LEN; t = t + 1) begin
                  send_one_gpio_byte(byte_seq_p[idx], 1'b0);
                  idx = idx + 1;
               end
            end
            else begin
               send_one_gpio_byte(byte_seq_p[idx], 1'b1);
               idx = idx + 1;
            end
         end

         send_gpio_idle_cycle();
      end
   endtask

   task wait_gpio_cycles(input integer cycles);
      integer i;
      begin
         for (i = 0; i < cycles; i = i + 1)
            @(posedge gpio_clk);
      end
   endtask

   // Pushes one 32-bit word onto the GPIO-side packer in little-endian byte order.
   task send_gpio_word(
      input [DATA_LEN-1:0] word_i
   );
      begin
         send_one_gpio_byte(word_i[7:0], 1'b1);
         send_one_gpio_byte(word_i[15:8], 1'b1);
         send_one_gpio_byte(word_i[23:16], 1'b1);
         send_one_gpio_byte(word_i[31:24], 1'b1);
         send_gpio_idle_cycle();
      end
   endtask
