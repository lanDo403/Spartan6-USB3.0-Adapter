`timescale 1ns / 1ps

module fifo_fsm
#(
	parameter DATA_LEN = 32,
	parameter BE_LEN   = 4
)
(
	input  						rst_n,
	input  						clk,
	
	input  						txe_n,		// Trancieve empty from FT601 
	input  						rxf_n,		// Recieve full from FT601
	input  [DATA_LEN-1:0]   data_i,	// Data from FIFO
	input  [DATA_LEN-1:0]   rx_data,		// Data from FT601
	input  [BE_LEN-1:0] 		be_i,			// Byte enable from FT601
	input 						full_fifo,
	input 						empty_fifo,
	
	output [DATA_LEN-1:0] 	data_o,		// DATA
	output [DATA_LEN-1:0]  	tx_data,		// Data to FT601
	output [BE_LEN-1:0]   	be_o,			// Byte enable to FT601
	output [BE_LEN-1:0]		fifo_be,
	output  						wr_n,    
	output   					rd_n,
	output   					oe_n,
	output 						drive_tx,
	output 						fifo_pop,
	output						fifo_append
    );
	 
	localparam IDLE     = 3'd0;
	localparam MODE     = 3'd1;  // Read or write selection
	localparam TX_START = 3'd2;  // Request the first TX word from FIFO
	localparam TX_BURST = 3'd3;  // Continuous write burst to FT601
	localparam RX_START = 3'd4;	// Assert OE#/RD# before the first RX word
	localparam RX_BURST = 3'd5;  // Continuous read burst from FT601
	
	reg [2:0] next_state;
	reg [2:0] state;
	
	reg [DATA_LEN-1:0] tx_data_ff, rx_data_ff;
	reg [BE_LEN-1:0] be_i_ff, be_o_ff;
	reg wr_ff, rd_ff, oe_ff;
	reg drive_tx_ff;
	reg fifo_pop_ff;
	reg fifo_append_ff;
	reg tx_word_valid_ff;
	reg tx_pop_pending_ff;
	
	wire tx_word_ready_w;
	wire [DATA_LEN-1:0] tx_word_w;
	
	assign tx_word_ready_w = tx_word_valid_ff | tx_pop_pending_ff;
	assign tx_word_w = tx_pop_pending_ff ? data_i : tx_data_ff;
	
	//-------------------------------------------------------------
	// state logic
	//-------------------------------------------------------------
	always @(negedge clk or negedge rst_n) begin
		if (!rst_n)
			state <= IDLE;
		else 
			state <= next_state;
	end
	
	//-------------------------------------------------------------
	// next_state logic
	//-------------------------------------------------------------	
	always @(*) begin
		next_state = state;
		case (state)
			IDLE: begin
															next_state = MODE;
			end
			MODE: begin
				if (!rxf_n && !full_fifo)
					next_state = RX_START;
				else if (!txe_n && (tx_word_ready_w || !empty_fifo)) begin
					if (tx_word_ready_w)
						next_state = TX_BURST;
					else
						next_state = TX_START;
				end
				else
					next_state = MODE;
			end
			TX_START: begin
				next_state = TX_BURST;
			end
			TX_BURST: begin
				if (tx_word_ready_w || (!empty_fifo && !txe_n))
					next_state = TX_BURST;
				else if (!rxf_n && !full_fifo)
					next_state = RX_START;
				else
					next_state = MODE;
			end
			RX_START: begin
				if (rxf_n || full_fifo) begin
					if (!txe_n && (tx_word_ready_w || !empty_fifo)) begin
						if (tx_word_ready_w)
							next_state = TX_BURST;
						else
							next_state = TX_START;
					end
					else
						next_state = MODE;
				end
				else
					next_state = RX_BURST;
			end
			RX_BURST: begin
				if (!rxf_n && !full_fifo)
					next_state = RX_BURST;
				else if (!txe_n && (tx_word_ready_w || !empty_fifo)) begin
					if (tx_word_ready_w)
						next_state = TX_BURST;
					else
						next_state = TX_START;
				end
				else
					next_state = MODE;
			end
			default: next_state = IDLE;
		endcase
	end
	
	
	//-------------------------------------------------------------
	// FF logic
	//-------------------------------------------------------------
	always @(negedge clk or negedge rst_n) begin
		if (!rst_n) begin
			rd_ff 			<= 1'b1;
			wr_ff 			<= 1'b1;
			oe_ff 			<= 1'b1;
			drive_tx_ff 	<= 1'b0;
			fifo_pop_ff 	<= 1'b0;
			fifo_append_ff <= 1'b0;
			tx_data_ff 		<= 32'd0;
			rx_data_ff  	<= 32'd0;
			be_i_ff			<= 4'd0;
			be_o_ff 			<= 4'd0;
			tx_word_valid_ff <= 1'b0;
			tx_pop_pending_ff <= 1'b0;
		end
		else begin
			wr_ff        	<= 1'b1;
			rd_ff        	<= 1'b1;
			oe_ff        	<= 1'b1;
			drive_tx_ff  	<= 1'b0;
			fifo_pop_ff 	<= 1'b0;
			fifo_append_ff <= 1'b0;
			
			// A FIFO pop requested on negedge is executed by the SRAM on the next posedge.
			// The word is therefore valid on data_i at the following negedge.
			if (tx_pop_pending_ff) begin
				tx_data_ff <= data_i;
				be_o_ff <= {BE_LEN{1'b1}};
				tx_word_valid_ff <= 1'b1;
				tx_pop_pending_ff <= 1'b0;
			end
			
			case (state)
			   IDLE, MODE: begin
					// wait
			   end
			   TX_START: begin
					if (!tx_word_ready_w && !empty_fifo) begin
						fifo_pop_ff <= 1'b1;
						tx_pop_pending_ff <= 1'b1;
					end
			   end
			   TX_BURST: begin
					if ((tx_word_ready_w) && !txe_n) begin
						drive_tx_ff <= 1'b1;
						wr_ff <= 1'b0;
						be_o_ff <= {BE_LEN{1'b1}};
						tx_data_ff <= tx_word_w;
						tx_word_valid_ff <= 1'b0;
						if (!empty_fifo) begin
							fifo_pop_ff <= 1'b1;
							tx_pop_pending_ff <= 1'b1;
						end
					end
					else if (!tx_word_ready_w && !empty_fifo) begin
						fifo_pop_ff <= 1'b1;
						tx_pop_pending_ff <= 1'b1;
					end
			   end
			   RX_START: begin
					drive_tx_ff <= 1'b0;
					oe_ff       <= 1'b0;
					rd_ff       <= 1'b0;
				end
				RX_BURST: begin
					drive_tx_ff <= 1'b0;
					oe_ff       <= 1'b0;
					rd_ff       <= 1'b0;
					if (!rxf_n && !full_fifo) begin
						rx_data_ff <= rx_data;
						be_i_ff <= be_i;
						fifo_append_ff <= 1'b1;
					end
				end
				default: begin
					// wait
				end
			endcase
		end
	end
	
	
	assign tx_data = tx_data_ff;
	assign data_o	= rx_data_ff;
	assign be_o = be_o_ff;
	assign wr_n = wr_ff;
	assign rd_n = rd_ff;
	assign oe_n = oe_ff;
	assign drive_tx = drive_tx_ff;	
	assign fifo_pop = fifo_pop_ff;
	assign fifo_be  = be_i_ff;
	assign fifo_append = fifo_append_ff;
		
endmodule
