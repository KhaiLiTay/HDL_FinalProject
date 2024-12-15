module speaker_control(
    input clk,  // clock from the crystal
    input rst,  // active high reset
    input [15:0] audio_in_left, // left channel audio data input
    input [15:0] audio_in_right, // right channel audio data input
    output audio_mclk, // master clock
    output audio_lrck, // left-right clock, Word Select clock, or sample rate clock
    output audio_sck, // serial clock
    output reg audio_sdin // serial audio data input
    ); 

    // Declare internal signal nodes 
    wire [8:0] clk_cnt_next;
    reg [8:0] clk_cnt;
    reg [15:0] audio_left, audio_right;

    // Counter for the clock divider
    assign clk_cnt_next = clk_cnt + 1'b1;

    always @(posedge clk or posedge rst)
        if (rst == 1'b1)
            clk_cnt <= 9'd0;
        else
            clk_cnt <= clk_cnt_next;

    // Assign divided clock output
    assign audio_mclk = clk_cnt[1];
    assign audio_lrck = clk_cnt[8];
    assign audio_sck = 1'b1; // use internal serial clock mode

    // audio input data buffer
    always @(posedge clk_cnt[8] or posedge rst)
        if (rst == 1'b1)
            begin
                audio_left <= 16'd0;
                audio_right <= 16'd0;
            end
        else
            begin
                audio_left <= audio_in_left;
                audio_right <= audio_in_right;
            end

    always @*
        case (clk_cnt[8:4])
            5'b00000: audio_sdin = audio_right[0];
            5'b00001: audio_sdin = audio_left[15];
            5'b00010: audio_sdin = audio_left[14];
            5'b00011: audio_sdin = audio_left[13];
            5'b00100: audio_sdin = audio_left[12];
            5'b00101: audio_sdin = audio_left[11];
            5'b00110: audio_sdin = audio_left[10];
            5'b00111: audio_sdin = audio_left[9];
            5'b01000: audio_sdin = audio_left[8];
            5'b01001: audio_sdin = audio_left[7];
            5'b01010: audio_sdin = audio_left[6];
            5'b01011: audio_sdin = audio_left[5];
            5'b01100: audio_sdin = audio_left[4];
            5'b01101: audio_sdin = audio_left[3];
            5'b01110: audio_sdin = audio_left[2];
            5'b01111: audio_sdin = audio_left[1];
            5'b10000: audio_sdin = audio_left[0];
            5'b10001: audio_sdin = audio_right[15];
            5'b10010: audio_sdin = audio_right[14];
            5'b10011: audio_sdin = audio_right[13];
            5'b10100: audio_sdin = audio_right[12];
            5'b10101: audio_sdin = audio_right[11];
            5'b10110: audio_sdin = audio_right[10];
            5'b10111: audio_sdin = audio_right[9];
            5'b11000: audio_sdin = audio_right[8];
            5'b11001: audio_sdin = audio_right[7];
            5'b11010: audio_sdin = audio_right[6];
            5'b11011: audio_sdin = audio_right[5];
            5'b11100: audio_sdin = audio_right[4];
            5'b11101: audio_sdin = audio_right[3];
            5'b11110: audio_sdin = audio_right[2];
            5'b11111: audio_sdin = audio_right[1];
            default: audio_sdin = 1'b0;
        endcase

endmodule

module buzzer_control(
    clk, // clock from crystal
    rst, // active high reset
    note_div, // div for note generation
    audio_left, // left sound audio
    audio_right, // right sound audio
    vol_num
    );
    
    // I/O declaration
	input clk; // clock from crystal
	input rst; // active high reset
	input [21:0] note_div; // div for note generation
	output [15:0] audio_left; // left sound audio
	output [15:0] audio_right; // right sound audio
	input [3:0]vol_num;
	
	// Declare internal signals
	reg [21:0] clk_cnt_next, clk_cnt;
	reg b_clk, b_clk_next;
	// Note frequency generation
	always @(posedge clk or posedge rst)
		if (rst == 1'b1) begin
			clk_cnt <= 22'd0;
			b_clk <= 1'b0;
		end 
		else begin
			clk_cnt <= clk_cnt_next;
			b_clk <= b_clk_next;
		end
	always @* begin
		if (clk_cnt == note_div) begin
			clk_cnt_next = 22'd0;
			b_clk_next = ~b_clk;
		end 
		else begin
			clk_cnt_next = clk_cnt + 1'b1;
			b_clk_next = b_clk;
		end
	end
	// Assign the amplitude of the note

	reg [15:0] AMP_P, AMP_N;

	always @(posedge clk or posedge rst) begin
		if (rst == 1'b1) begin
			AMP_N <= 16'hC000;
			AMP_P <= 16'h4000;
		end 
		else begin
			case(vol_num)
			5:begin //14
				AMP_N <= 16'hC000;
				AMP_P <= 16'h4000;
			end 
			4:begin //13
				AMP_N <= 16'hE000;
				AMP_P <= 16'h2000;
			end
			3:begin //12
				AMP_N <= 16'hF000;
				AMP_P <= 16'h1000;
			end
			2:begin //11
				AMP_N <= 16'hF800;
				AMP_P <= 16'h0800;
			end
			1:begin //10
				AMP_N <= 16'hFC00;
				AMP_P <= 16'h0400;
			end
			default: begin //10
				AMP_N <= 16'hFC00;
				AMP_P <= 16'h0400;
			end
		endcase
		end
	end


	assign audio_left = (b_clk == 1'b0) ? AMP_N : AMP_P;
	assign audio_right = (b_clk == 1'b0) ? AMP_N : AMP_P;
endmodule
