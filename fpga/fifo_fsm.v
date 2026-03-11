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
	 
	localparam IDLE   = 3'd0;
	localparam MODE   = 3'd1;  // Read or write
	localparam W_POP  = 3'd2;  // 
	localparam W_PREP = 3'd3;  // DATA/BE
	localparam W_STB  = 3'd4;  // WR# impulse 1 clock period
	localparam R_OE   = 3'd5;	// OE#=0, wait 1 clock period
	localparam R_STB  = 3'd6;  // RD# impulse 1 clock period
	localparam R_CAP  = 3'd7;  // Data capture
	
	reg [2:0] next_state;
	reg [2:0] state;
	
	reg [DATA_LEN-1:0] tx_data_ff, rx_data_ff;
	reg [BE_LEN-1:0] be_i_ff, be_o_ff;
	reg wr_ff, rd_ff, oe_ff;
	reg drive_tx_ff;
	reg fifo_pop_ff;
	reg fifo_append_ff;
	
	//-------------------------------------------------------------
	// state logic
	//-------------------------------------------------------------
	always @(posedge clk or negedge rst_n) begin
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
				if (!rxf_n && !full_fifo)			next_state = R_OE;
				else if (!txe_n && !empty_fifo)	next_state = W_POP;
				else										next_state = MODE;
			end
			W_POP: begin
				if (txe_n || empty_fifo)			next_state = MODE;	// nothing to write
				else                 				next_state = W_PREP;
			end
			W_PREP: begin
				if (txe_n || empty_fifo) 			next_state = MODE;
				else                 				next_state = W_STB;
			end
			W_STB: begin
				if (!rxf_n && !full_fifo)		next_state = R_OE;
				else if (!txe_n && !empty_fifo)	next_state = W_POP;
				else                       		next_state = MODE;
			end
			R_OE: begin
				if (rxf_n || full_fifo)			next_state = MODE;  // nothing to read
				else										next_state = R_STB;
			end
			R_STB: begin
															next_state = R_CAP;
			end
			R_CAP: begin
				if (!rxf_n && !full_fifo)		next_state = R_OE;
				else if (!txe_n && !empty_fifo)	next_state = W_POP;
				else              					next_state = MODE;
			end
			default: next_state = IDLE;
		endcase
	end
	
	
	//-------------------------------------------------------------
	// FF logic
	//-------------------------------------------------------------
	always @(posedge clk or negedge rst_n) begin
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
		end
		else begin
			wr_ff        	<= 1'b1;
			rd_ff        	<= 1'b1;
			oe_ff        	<= 1'b1;
			drive_tx_ff  	<= 1'b0;
			fifo_pop_ff 	<= 1'b0;
			fifo_append_ff <= 1'b0;
			case (state)
			   IDLE, MODE: begin
					// wait
			   end
			   W_POP: begin
					fifo_pop_ff <= 1'b1;  // 1-cycle pop
				   oe_ff       <= 1'b1;
				   drive_tx_ff <= 1'b0;
			   end
			   W_PREP: begin
					oe_ff       <= 1'b1;
					drive_tx_ff <= 1'b1;
					if (!txe_n && !empty_fifo) begin
						tx_data_ff <= data_i;
						be_o_ff      <= {BE_LEN{1'b1}}; // 4'hF
					end
			   end
			   W_STB: begin
					oe_ff       <= 1'b1;
				   drive_tx_ff <= 1'b1;
				   wr_ff       <= 1'b0;
			   end
			   R_OE: begin
					drive_tx_ff <= 1'b0;
					oe_ff       <= 1'b0;
			   end
				R_STB: begin
					drive_tx_ff <= 1'b0;
					oe_ff       <= 1'b0;
					rd_ff       <= 1'b0;  // 1-cycle RD# strobe
				end
				R_CAP: begin
					drive_tx_ff <= 1'b0;
					oe_ff       <= 1'b0;
					if (!rxf_n && !full_fifo) begin
						rx_data_ff <= rx_data;
						be_i_ff <= be_i;
						fifo_append_ff <= 1'b1;
					end
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
