`define lc  32'd131   // C3
`define ld  32'd147   // D3
`define le  32'd165   // E3
`define lf  32'd174   // F3
`define lg  32'd196   // G3
`define la  32'd220   // A3
`define lb  32'd247   // B3
`define c   32'd262   // C4
`define d   32'd294   // D4
`define e   32'd330   // E4
`define f   32'd349   // F4
`define g   32'd392   // G4
`define a   32'd440   // A4
`define b   32'd494   // B4
`define hc  32'd523   // C5
`define hd  32'd587   // D5
`define he  32'd659   // E5
`define hf  32'd698   // F5
`define hg  32'd784   // G5 
`define ha  32'd880   // A5
`define hb  32'd988   // B5

`define sil   32'd50000000 // slience
module final(
    input wire clk,
    input wire rst,
    input wire btnL,
    input wire btnR,
	input wire SW0,
    inout wire PS2_DATA,
    inout wire PS2_CLK,
    output reg [15:0] LED,
	output audio_mclk, // master clock
    output audio_lrck, // left-right clock
    output audio_sck,  // serial clock
    output audio_sdin, // serial audio data input
    output reg [3:0] digit,
    output reg [6:0] display
);

// state
parameter [1:0] IDLE = 2'b00;
parameter [1:0] TYPING = 2'b01;
parameter [1:0] WRITING = 2'b10;
reg [2:0] state, next_state;
// KEYBOARD
wire [125:0] key_down;
wire [8:0] last_change;
reg [8:0] pre_last_change, next_pre_last_change;
wire key_valid;
reg [3:0] key_num;
reg isPressed, next_isPressed;
integer i;
reg[15:0] num, next_num;
// 7-segment
reg [3:0] BCD0, BCD1, BCD2, BCD3;
reg [3:0] value;
wire clk_used;
clock_divider #(14) div1(.clk(clk), .clk_div(clk_used));
// Writing
reg finish_writing;
// Audio
wire [15:0] audio_in_left, audio_in_right;
wire [11:0] ibeatNum;               // Beat counter
wire [31:0] freqL, freqR;           // Raw frequency, produced by music module
wire [21:0] freq_outL, freq_outR;    // Processed frequency, adapted to the clock rate of Basys3
wire clk_div22;

clock_divider #(.n(22)) clock_22(.clk(clk), .clk_div(clk_div22));
assign freq_outL = 50000000 / freqL;
assign freq_outR = 50000000 / freqR;

KeyboardDecoder kbd(
	.key_down(key_down),
	.last_change(last_change),
	.key_valid(key_valid),
	.PS2_DATA(PS2_DATA),
	.PS2_CLK(PS2_CLK),
	.rst(rst),
	.clk(clk)
);

player_control playerCtrl_00 ( 
	.clk(clk_div22),
	.reset(rst),
	.state(state),
	.ibeat(ibeatNum)
);

speaker_control sc(
	.clk(clk), 
	.rst(rst), 
	.audio_in_left(audio_in_left),      // left channel audio data input
	.audio_in_right(audio_in_right),    // right channel audio data input
	.audio_mclk(audio_mclk),            // master clock
	.audio_lrck(audio_lrck),            // left-right clock
	.audio_sck(audio_sck),              // serial clock
	.audio_sdin(audio_sdin)             // serial audio data input
);

note_gen noteGen_00(
	.clk(clk), 
	.rst(rst), 
	.note_div_left(freq_outL), 
	.note_div_right(freq_outR), 
	.audio_left(audio_in_left),     // left sound audio
	.audio_right(audio_in_right)    // right sound audio
);

music music_00 (
	.ibeatNum(ibeatNum),
	.state(state),
	.rst(rst),
	.clk(clk),
	.toneL(freqL),
	.toneR(freqR)
);

parameter [8:0] KEY_CODES [0:21] = {
	9'b0_0100_0101,	// 0 => 45
	9'b0_0001_0110,	// 1 => 16
	9'b0_0001_1110,	// 2 => 1E
	9'b0_0010_0110,	// 3 => 26
	9'b0_0010_0101,	// 4 => 25
	9'b0_0010_1110,	// 5 => 2E
	9'b0_0011_0110,	// 6 => 36
	9'b0_0011_1101,	// 7 => 3D
	9'b0_0011_1110,	// 8 => 3E
	9'b0_0100_0110,	// 9 => 46
	
	9'b0_0111_0000, // right_0 => 70
	9'b0_0110_1001, // right_1 => 69
	9'b0_0111_0010, // right_2 => 72
	9'b0_0111_1010, // right_3 => 7A
	9'b0_0110_1011, // right_4 => 6B
	9'b0_0111_0011, // right_5 => 73
	9'b0_0111_0100, // right_6 => 74
	9'b0_0110_1100, // right_7 => 6C
	9'b0_0111_0101, // right_8 => 75
	9'b0_0111_1101, // right_9 => 7D
    9'b0_0110_0110, // BACK
    9'b0_0101_1010  // ENTER
};
// state transition
always @* begin
	if(rst) next_state = IDLE;
	else begin
		next_state = state;
		case (state)
			IDLE: begin
				if(btnR == 1'b1) next_state = TYPING;
			end
			TYPING: begin //enter
				if(key_valid == 1'b1 && key_down[last_change] == 1'b1) begin
					if(last_change == 9'b0_0101_1010) next_state = WRITING;
				end
			end
			WRITING: begin
				if(finish_writing == 1'b1) next_state = IDLE;
			end
			default: next_state = IDLE;
		endcase
	end
end
// state transition
always @(posedge clk or posedge rst) begin
	if(rst) state <= IDLE;
	else state <= next_state;
end

// LED
reg [15:0] next_led;
always @(posedge clk or posedge rst) begin
	if (rst) begin
		LED <= 16'b0000_0000_0000_0000;
	end
	else begin
		LED <= next_led;
	end
end
always @* begin
	if(rst) begin
		next_led = 16'd0;
	end
	else begin
		next_led = 16'd0;
		case(state)
			IDLE: next_led[15:12] = 4'b1111;
			TYPING: next_led[11:8] = 4'b1111;
			WRITING: next_led[7:4] = 4'b1111;
		endcase

		if(SW0) next_led[0] = 1'b1;
		else next_led[0] = 1'b0;
	end
end

// Write
always @* begin
	if(rst) begin
		finish_writing = 1'b0;
	end
	else begin
		finish_writing = 1'b0;
		if(state == WRITING) begin
			if(btnL == 1'b1) begin
				finish_writing = 1'b1;
			end
		end
	end
end
// num
always @(posedge clk_used, posedge rst) begin
	if(rst) begin
		num[3:0] <= 4'd10;
        num[7:4] <= 4'd10;
        num[11:8] <= 4'd10;
        num[15:12] <= 4'd10;
	end
	else begin
		if(state == IDLE) begin
			num[3:0] <= 4'd10;
			num[7:4] <= 4'd10;
			num[11:8] <= 4'd10;
			num[15:12] <= 4'd10;
		end
		else
        	num <= next_num;
    end
end
// num
always @(*) begin
    if(rst) begin
        next_num[3:0] = 4'd10;
        next_num[7:4] = 4'd10;
        next_num[11:8] = 4'd10;
        next_num[15:12] = 4'd10;
    end
    else begin
        if(state == TYPING) begin
            if(key_valid == 1'b1 && key_down[last_change] == 1'b1 && (isPressed == 1'b0)) begin
                if(key_num <= 4'd9 && key_num >= 0) begin
                    next_num[15:12] = num[11:8];
                    next_num[11:8] = num[7:4];
                    next_num[7:4] = num[3:0];
                    next_num[3:0] = key_num;
                end
                else if(last_change == 9'b0_0110_0110) begin //BACK
                    next_num[3:0] = num[7:4];
                    next_num[7:4] = num[11:8];
                    next_num[11:8] = num[15:12];
                    next_num[15:12] = 4'd10;
                end
                else begin
                    next_num = next_num;
                end
            end
			else
				next_num = next_num;
		end
		else if(state == WRITING)
			next_num = next_num;
		else begin // IDLE
			next_num[3:0] = 4'd10;
			next_num[7:4] = 4'd10;
			next_num[11:8] = 4'd10;
			next_num[15:12] = 4'd10;
		end
    end
end

// KEYBOARD - KEY_CODES map to key_num
always @ (*) begin
	case (last_change)
		KEY_CODES[00] : key_num = 4'b0000;
		KEY_CODES[01] : key_num = 4'b0001;
		KEY_CODES[02] : key_num = 4'b0010;
		KEY_CODES[03] : key_num = 4'b0011;
		KEY_CODES[04] : key_num = 4'b0100;
		KEY_CODES[05] : key_num = 4'b0101;
		KEY_CODES[06] : key_num = 4'b0110;
		KEY_CODES[07] : key_num = 4'b0111;
		KEY_CODES[08] : key_num = 4'b1000;
		KEY_CODES[09] : key_num = 4'b1001;

		KEY_CODES[10] : key_num = 4'b0000;
		KEY_CODES[11] : key_num = 4'b0001;
		KEY_CODES[12] : key_num = 4'b0010;
		KEY_CODES[13] : key_num = 4'b0011;
		KEY_CODES[14] : key_num = 4'b0100;
		KEY_CODES[15] : key_num = 4'b0101;
		KEY_CODES[16] : key_num = 4'b0110;
		KEY_CODES[17] : key_num = 4'b0111;
		KEY_CODES[18] : key_num = 4'b1000;
		KEY_CODES[19] : key_num = 4'b1001;
		default		  : key_num = 4'b1111;
	endcase
end

// KEYBOARD - detect whether there are multiple keys pressed
always @(posedge clk, posedge rst) begin
	if(rst)
		isPressed <= 1'b0;
	else
		isPressed <= next_isPressed;	
end

always @(*) begin
	if(rst)
		next_isPressed = 1'b0;
	else begin
		if(state == TYPING) begin
			next_isPressed = 1'b0;
			for(i = 0; i < 22; i = i + 1) begin
				if(key_down[KEY_CODES[i]] == 1'b1)
					next_isPressed = 1'b1;
				else
					next_isPressed = next_isPressed;
			end
		end
		else
			next_isPressed = 1'b0;
	end
end

// 7 segment display
always @(posedge clk_used) begin
    case (digit)
        4'b1110 : begin
            value = BCD1;
            digit = 4'b1101;
        end
        4'b1101 : begin
            value = BCD2;
            digit = 4'b1011;
        end
        4'b1011 : begin
            value = BCD3;
            digit = 4'b0111;
        end
        4'b0111 : begin
            value = BCD0;
            digit = 4'b1110;
        end
        default : begin
            value = BCD0;
            digit = 4'b1110;
        end
    endcase
end
// BCD
always @(*) begin
	case (state)
	IDLE: begin
		BCD0 = 4'd10;
		BCD1 = 4'd10;
		BCD2 = 4'd10;
		BCD3 = 4'd10;
	end
	default: begin
		BCD0 = num[3:0];
		BCD1 = num[7:4];
		BCD2 = num[11:8];
		BCD3 = num[15:12];
	end
	endcase
end
// display
always @(*) begin
    case(value)
        4'd0 : display = 7'b100_0000;
        4'd1 : display = 7'b111_1001;
        4'd2 : display = 7'b010_0100;
        4'd3 : display = 7'b011_0000;
        4'd4 : display = 7'b001_1001;
        4'd5 : display = 7'b001_0010;
        4'd6 : display = 7'b000_0010;
        4'd7 : display = 7'b111_1000;
        4'd8 : display = 7'b000_0000;
        4'd9 : display = 7'b001_0000;
        4'd10: display = 7'b011_1111; // NONE(-)
        default : display = 7'b111_1111;
    endcase
end

endmodule

module music (
	input [11:0] ibeatNum,
    input rst,
    input clk,
    input [2:0] state,
	output reg [31:0] toneL,
    output reg [31:0] toneR
);
	// state
	parameter [1:0] IDLE = 2'b00;
	parameter [1:0] TYPING = 2'b01;
	parameter [1:0] WRITING = 2'b10;

    always @* begin
        if(rst) begin
            toneR = `sil;
        end
        else if(state == TYPING) begin
            case(ibeatNum)
				12'd0: toneR = `he;  12'd1: toneR = `he;
				12'd2: toneR = `he;  12'd3: toneR = `he;
				12'd4: toneR = `he;  12'd5: toneR = `he;
				12'd6: toneR = `he;  12'd7: toneR = `he;
				12'd8: toneR = `he;  12'd9: toneR = `he;
				12'd10: toneR = `he;  12'd11: toneR = `he;
				12'd12: toneR = `sil;  12'd13: toneR = `sil;
				12'd14: toneR = `sil;  12'd15: toneR = `sil;
				12'd16: toneR = `sil;  12'd17: toneR = `sil;
				12'd18: toneR = `he;  12'd19: toneR = `he;
				12'd20: toneR = `he;  12'd21: toneR = `he;
				12'd22: toneR = `he;  12'd23: toneR = `he;
				12'd24: toneR = `sil;  12'd25: toneR = `sil;
				12'd26: toneR = `sil;  12'd27: toneR = `sil;
				12'd28: toneR = `sil;  12'd29: toneR = `sil;
				12'd30: toneR = `hc;  12'd31: toneR = `hc;
				12'd32: toneR = `hc;  12'd33: toneR = `hc;
				12'd34: toneR = `hc;  12'd35: toneR = `hc;
				12'd36: toneR = `he;  12'd37: toneR = `he;
				12'd38: toneR = `he;  12'd39: toneR = `he;
				12'd40: toneR = `he;  12'd41: toneR = `he;
				12'd42: toneR = `he;  12'd43: toneR = `he;
				12'd44: toneR = `he;  12'd45: toneR = `he;
				12'd46: toneR = `he;  12'd47: toneR = `he;
				12'd48: toneR = `hg;  12'd49: toneR = `hg;
				12'd50: toneR = `hg;  12'd51: toneR = `hg;
				12'd52: toneR = `hg;  12'd53: toneR = `hg;
				12'd54: toneR = `hg;  12'd55: toneR = `hg;
				12'd56: toneR = `hg;  12'd57: toneR = `hg;
                default: toneR = `sil;
            endcase
        end
		else if(state == WRITING) begin
            toneR = `sil;
        end
		else
			toneR = `sil;
    end

    always @(*) begin
        if(rst) begin
            toneL = `sil;
        end
        else if(state == TYPING) begin
            case(ibeatNum)
                // --- Measure 0 ---
				12'd0: toneL= `le;  12'd1: toneL= `le;
				12'd2: toneL= `le;  12'd3: toneL= `le;
				12'd4: toneL= `le;  12'd5: toneL= `le;
				12'd6: toneL= `le;  12'd7: toneL= `le;
				12'd8: toneL= `le;  12'd9: toneL= `le;
				12'd10: toneL= `le;  12'd11: toneL= `le;
				12'd12: toneL= `le;  12'd13: toneL= `le;
				12'd14: toneL= `le;  12'd15: toneL= `le;
				12'd16: toneL= `le;  12'd17: toneL= `le;
				12'd18: toneL= `le;  12'd19: toneL= `le;
				12'd20: toneL= `le;  12'd21: toneL= `le;
				12'd22: toneL= `le;  12'd23: toneL= `le;
				12'd24: toneL= `le;  12'd25: toneL= `le;
				12'd26: toneL= `le;  12'd27: toneL= `le;
				12'd28: toneL= `le;  12'd29: toneL= `le;
				12'd30: toneL= `le;  12'd31: toneL= `le;
				12'd32: toneL= `le;  12'd33: toneL= `le;
				12'd34: toneL= `le;  12'd35: toneL= `le;
				12'd36: toneL= `le;  12'd37: toneL= `le;
				12'd38: toneL= `le;  12'd39: toneL= `le;
				12'd40: toneL= `le;  12'd41: toneL= `le;
				12'd42: toneL= `le;  12'd43: toneL= `le;
				12'd44: toneL= `le;  12'd45: toneL= `le;
				12'd46: toneL= `le;  12'd47: toneL= `le;
				12'd48: toneL= `la;  12'd49: toneL= `la;
				12'd50: toneL= `la;  12'd51: toneL= `la;
				12'd52: toneL= `la;  12'd53: toneL= `la;
				12'd54: toneL= `la;  12'd55: toneL= `la;
				12'd56: toneL= `la;  12'd57: toneL= `la;
                default: toneL= `sil;
            endcase
        end
        else if(state == WRITING) begin
            toneL = `sil;
        end
		else
			toneL = `sil;
    end
endmodule