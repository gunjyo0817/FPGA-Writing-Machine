`define lc  26'd131   // C3
`define ld  26'd147   // D3
`define lbe 26'd156
`define le  26'd165   // E3
`define lf  26'd174   // F3
`define lg  26'd196   // G3
`define lba 26'd208
`define la  26'd220   // A3
`define lb  26'd247   // B3
`define lbb 26'd233
`define c   26'd262   // C4
`define d   26'd294   // D4
`define be  26'd311
`define e   26'd330   // E4
`define f   26'd349   // F4
`define g   26'd392   // G4
`define ba  26'd415
`define a   26'd440   // A4
`define bb  26'd466
`define b   26'd494   // B4
`define hc  26'd523   // C5
`define hd  26'd587   // D5
`define hbe 26'd622 
`define he  26'd659   // E5
`define hf  26'd698   // F5
`define hg  26'd784   // G5 
`define hba 26'd831 
`define ha  26'd880   // A5
`define hbb 26'd932
`define hb  26'd988   // B5
`define hhc 26'd1047
`define hhe 26'd1319
`define sil   26'd50000000 // slience

module final(
    input wire clk,
    input wire rst,
    input wire btnL,
    input wire btnR,
	input wire SW0, // claw
	input wire SW1,	// left
	input wire SW2, // right
	input wire SW3, // bottom
    inout wire PS2_DATA,
    inout wire PS2_CLK,
    output reg [15:0] LED,
	output audio_mclk, // master clock
    output audio_lrck, // left-right clock
    output audio_sck,  // serial clock
    output audio_sdin, // serial audio data input
	output pwm_left,
	output pwm_right,
	output pwm_bottom,
	output pwm_claw,
    output reg [3:0] digit,
    output reg [6:0] display
);

// state
parameter [1:0] IDLE = 2'b00;
parameter [1:0] TYPING = 2'b01;
parameter [1:0] WRITING = 2'b10;
reg [1:0] state, next_state;
// KEYBOARD
wire [110:0] key_down;
wire [8:0] last_change;
wire key_valid;
reg [3:0] key_num;
reg isPressed, next_isPressed;
integer i;
reg[15:0] num, next_num;
// 7-segment
reg [3:0] BCD0, BCD1, BCD2, BCD3;
reg [3:0] value;
wire clk_used;
clock_divider #(14) div1(.clk(clk), .en(1), .clk_div(clk_used));
// Writing
wire finish_writing;
// Audio
wire [15:0] audio_in_left, audio_in_right;
wire [7:0] ibeat1, ibeat2;
wire [7:0] ibeatNum;               // Beat counter
wire [25:0] freqL, freqR;           // Raw frequency, produced by music module
wire [21:0] freq_outL, freq_outR;    // Processed frequency, adapted to the clock rate of Basys3
wire clk_div22;
// debug
wire [3:0] index;

clock_divider #(.n(22)) clock_22(.clk(clk), .en(1), .clk_div(clk_div22));
assign freq_outL = 50000000 / freqL;
assign freq_outR = 50000000 / freqR;
assign ibeatNum = (state == TYPING) ? ibeat1 :
				(state == WRITING) ? ibeat2 : 0;

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
	.ibeat1(ibeat1),
	.ibeat2(ibeat2)
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
	.finish_writing(finish_writing),
	.clk(clk),
	.toneL(freqL),
	.toneR(freqR)
);

Servo_interface servo_claw (
	.sw({SW3, SW2, SW1, SW0}),
	.rst(rst),
	.clk(clk),
	.en(state == WRITING),
	.num(num),
	.state(state),
	.pwm_claw(pwm_claw),
	.pwm_left(pwm_left),
	.pwm_right(pwm_right),
	.pwm_bottom(pwm_bottom),
	.finish_writing(finish_writing),
	.index(index)
);

parameter [8:0] KEY_CODES [0:10] = {
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
	9'b0_0110_0110 // BACK
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
		LED <= 16'b1111_0000_0000_0000;
	end
	else begin
		LED <= next_led;
	end
end
always @* begin
	if(rst) begin
		next_led = 16'b1111_0000_0000_0000;
	end
	else begin
		next_led = 16'd0;
		case(state)
			IDLE: next_led[15:12] = 4'b1111;
			TYPING: next_led[11:8] = 4'b1111;
			WRITING: next_led[7:4] = 4'b1111;
		endcase

		next_led[3:0] = index + 1'b1;
		// if(SW0) next_led[0] = 1'b1;
		// else next_led[0] = 1'b0;
		// if(SW1) next_led[1] = 1'b1;
		// else next_led[1] = 1'b0;
		// if(SW2) next_led[2] = 1'b1;
		// else next_led[2] = 1'b0;
		// if(SW3) next_led[3] = 1'b1;
		// else next_led[3] = 1'b0;
	end
end

// Write
// always @* begin
// 	if(rst) begin
// 		finish_writing = 1'b0;
// 	end
// 	else begin
// 		finish_writing = 1'b0;
// 		if(state == WRITING) begin
// 			if(btnL == 1'b1) begin
// 				finish_writing = 1'b1;
// 			end
// 		end
// 	end
// end
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
                if(4'd9 >= key_num && key_num >= 0) begin
                    next_num[15:12] = num[11:8];
                    next_num[11:8] = num[7:4];
                    next_num[7:4] = num[3:0];
                    next_num[3:0] = key_num;
                end
                else if(key_down[last_change] == 1'b1 && last_change == 9'b0_0110_0110 && isPressed == 1'b0) begin //BACK
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
			for(i = 0; i < 11; i = i + 1) begin
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
	input [7:0] ibeatNum,
    input rst,
    input clk,
	input finish_writing,
    input [2:0] state,
	output reg [25:0] toneL,
    output reg [25:0] toneR
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
				// Start
				8'd0: toneR = `he;  8'd1: toneR = `he;
				8'd2: toneR = `he;  8'd3: toneR = `he;
				8'd4: toneR = `he;  8'd5: toneR = `he;
				8'd6: toneR = `he;  8'd7: toneR = `he;
				8'd8: toneR = `he;  8'd9: toneR = `he;
				8'd10: toneR = `he;  8'd11: toneR = `he;
				8'd12: toneR = `sil;  8'd13: toneR = `sil;
				8'd14: toneR = `sil;  8'd15: toneR = `sil;
				8'd16: toneR = `sil;  8'd17: toneR = `sil;
				8'd18: toneR = `he;  8'd19: toneR = `he;
				8'd20: toneR = `he;  8'd21: toneR = `he;
				8'd22: toneR = `he;  8'd23: toneR = `he;
				8'd24: toneR = `sil;  8'd25: toneR = `sil;
				8'd26: toneR = `sil;  8'd27: toneR = `sil;
				8'd28: toneR = `sil;  8'd29: toneR = `sil;
				8'd30: toneR = `hc;  8'd31: toneR = `hc;
				8'd32: toneR = `hc;  8'd33: toneR = `hc;
				8'd34: toneR = `hc;  8'd35: toneR = `hc;
				8'd36: toneR = `he;  8'd37: toneR = `he;
				8'd38: toneR = `he;  8'd39: toneR = `he;
				8'd40: toneR = `he;  8'd41: toneR = `he;
				8'd42: toneR = `he;  8'd43: toneR = `he;
				8'd44: toneR = `he;  8'd45: toneR = `he;
				8'd46: toneR = `he;  8'd47: toneR = `he;
				8'd48: toneR = `hg;  8'd49: toneR = `hg;
				8'd50: toneR = `hg;  8'd51: toneR = `hg;
				8'd52: toneR = `hg;  8'd53: toneR = `hg;
				8'd54: toneR = `hg;  8'd55: toneR = `hg;
				8'd56: toneR = `hg;  8'd57: toneR = `hg;
				8'd58: toneR = `hg;  8'd59: toneR = `hg;
				// Coin
				// 8'd60: toneR = `sil;  8'd61: toneR = `hb;
				// 8'd62: toneR = `hb;  8'd63: toneR = `hb;
				// 8'd64: toneR = `hb;  8'd65: toneR = `hb;
				// 8'd66: toneR = `hhe;  8'd67: toneR = `hhe;
				// 8'd68: toneR = `hhe;  8'd69: toneR = `hhe;
				// 8'd70: toneR = `hhe;  8'd71: toneR = `hhe;
				// 8'd72: toneR = `hhe;  8'd73: toneR = `hhe;
				// 8'd74: toneR = `hhe;  8'd75: toneR = `hhe;
				// 8'd76: toneR = `hhe;  8'd77: toneR = `hhe;
				// 8'd78: toneR = `hhe;  8'd79: toneR = `hhe;
				// 8'd80: toneR = `hhe;  8'd81: toneR = `hhe;
				// 8'd82: toneR = `hhe;  8'd83: toneR = `hhe;
                default: toneR = `sil;
            endcase
        end
		else if(state == WRITING) begin
            case(ibeatNum)
				// End
				8'd0: toneR = `sil;  8'd1: toneR = `sil;
				8'd2: toneR = `sil;  8'd3: toneR = `sil;
				8'd4: toneR = `c;  8'd5: toneR = `c;
				8'd6: toneR = `c;  8'd7: toneR = `c;
				8'd8: toneR = `e;  8'd9: toneR = `e;
				8'd10: toneR = `e;  8'd11: toneR = `e;
				8'd12: toneR = `g;  8'd13: toneR = `g;
				8'd14: toneR = `g;  8'd15: toneR = `g;
				8'd16: toneR = `hc;  8'd17: toneR = `hc;
				8'd18: toneR = `hc;  8'd19: toneR = `hc;
				8'd20: toneR = `he;  8'd21: toneR = `he;
				8'd22: toneR = `he;  8'd23: toneR = `he;
				8'd24: toneR = `hg;  8'd25: toneR = `hg;
				8'd26: toneR = `hg;  8'd27: toneR = `hg;
				8'd28: toneR = `hg;  8'd29: toneR = `hg;
				8'd30: toneR = `hg;  8'd31: toneR = `hg;
				8'd32: toneR = `hg;  8'd33: toneR = `hg;
				8'd34: toneR = `hg;  8'd35: toneR = `hg;
				8'd36: toneR = `he;  8'd37: toneR = `he;
				8'd38: toneR = `he;  8'd39: toneR = `he;
				8'd40: toneR = `he;  8'd41: toneR = `he;
				8'd42: toneR = `sil;  8'd43: toneR = `sil;
				8'd44: toneR = `sil;  8'd45: toneR = `sil;
				8'd46: toneR = `sil;  8'd47: toneR = `sil;
				8'd48: toneR = `sil;  8'd49: toneR = `sil;
				8'd50: toneR = `sil;  8'd51: toneR = `sil;
				8'd52: toneR = `c;  8'd53: toneR = `c;
				8'd54: toneR = `c;  8'd55: toneR = `c;
				8'd56: toneR = `be;  8'd57: toneR = `be;
				8'd58: toneR = `be;  8'd59: toneR = `be;
				8'd60: toneR = `ba;  8'd61: toneR = `ba;
				8'd62: toneR = `ba;  8'd63: toneR = `ba;
				8'd64: toneR = `hc;  8'd65: toneR = `hc;
				8'd66: toneR = `hc;  8'd67: toneR = `hc;
				8'd68: toneR = `hbe;  8'd69: toneR = `hbe;
				8'd70: toneR = `hbe;  8'd71: toneR = `hbe;
				8'd72: toneR = `hba;  8'd73: toneR = `hba;
				8'd74: toneR = `hba;  8'd75: toneR = `hba;
				8'd76: toneR = `hba;  8'd77: toneR = `hba;
				8'd78: toneR = `hba;  8'd79: toneR = `hba;
				8'd80: toneR = `hba;  8'd81: toneR = `hba;
				8'd82: toneR = `hba;  8'd83: toneR = `hba;
				8'd84: toneR = `hf;  8'd85: toneR = `hf;
				8'd86: toneR = `hf;  8'd87: toneR = `hf;
				8'd88: toneR = `hf;  8'd89: toneR = `hf;
				8'd90: toneR = `sil;  8'd91: toneR = `sil;
				8'd92: toneR = `sil;  8'd93: toneR = `sil;
				8'd94: toneR = `sil;  8'd95: toneR = `sil;
				8'd96: toneR = `sil;  8'd97: toneR = `sil;
				8'd98: toneR = `sil;  8'd99: toneR = `sil;
				8'd100: toneR = `d;  8'd101: toneR = `d;
				8'd102: toneR = `d;  8'd103: toneR = `d;
				8'd104: toneR = `f;  8'd105: toneR = `f;
				8'd106: toneR = `f;  8'd107: toneR = `f;
				8'd108: toneR = `bb;  8'd109: toneR = `bb;
				8'd110: toneR = `bb;  8'd111: toneR = `bb;
				8'd112: toneR = `hd;  8'd113: toneR = `hd;
				8'd114: toneR = `hd;  8'd115: toneR = `hd;
				8'd116: toneR = `hf;  8'd117: toneR = `hf;
				8'd118: toneR = `hf;  8'd119: toneR = `hf;
				8'd120: toneR = `hbb;  8'd121: toneR = `hbb;
				8'd122: toneR = `hbb;  8'd123: toneR = `hbb;
				8'd124: toneR = `hbb;  8'd125: toneR = `hbb;
				8'd126: toneR = `hbb;  8'd127: toneR = `hbb;
				8'd128: toneR = `hbb;  8'd129: toneR = `hbb;
				8'd130: toneR = `hbb;  8'd131: toneR = `hbb;
				8'd132: toneR = `hb;  8'd133: toneR = `hb;
				8'd134: toneR = `sil;  8'd135: toneR = `sil;
				8'd136: toneR = `hb;  8'd137: toneR = `hb;
				8'd138: toneR = `sil;  8'd139: toneR = `sil;
				8'd140: toneR = `hb;  8'd141: toneR = `hb;
				8'd142: toneR = `hb;  8'd143: toneR = `hb;
				8'd144: toneR = `hhc;  8'd145: toneR = `hhc;
				8'd146: toneR = `hhc;  8'd147: toneR = `hhc;
				8'd148: toneR = `hhc;  8'd149: toneR = `hhc;
				8'd150: toneR = `hhc;  8'd151: toneR = `hhc;
				8'd152: toneR = `hhc;  8'd153: toneR = `hhc;
				8'd154: toneR = `hhc;  8'd155: toneR = `hhc;
				8'd156: toneR = `hhc;  8'd157: toneR = `hhc;
				8'd158: toneR = `hhc;  8'd159: toneR = `hhc;
				8'd160: toneR = `hhc;  8'd161: toneR = `hhc;
				8'd162: toneR = `hhc;  8'd163: toneR = `hhc;
				8'd164: toneR = `hhc;  8'd165: toneR = `hhc;
				8'd166: toneR = `hhc;  8'd167: toneR = `hhc;
				8'd168: toneR = `hhc;  8'd169: toneR = `hhc;
				8'd170: toneR = `hhc;  8'd171: toneR = `hhc;
				8'd172: toneR = `hhc;  8'd173: toneR = `hhc;
				8'd174: toneR = `hhc;  8'd175: toneR = `hhc;
				8'd176: toneR = `hhc;  8'd177: toneR = `hhc;
				8'd178: toneR = `hhc;  8'd179: toneR = `hhc;
				8'd180: toneR = `hhc;  8'd181: toneR = `hhc;
				8'd182: toneR = `hhc;  8'd183: toneR = `hhc;
				8'd184: toneR = `hhc;  8'd185: toneR = `hhc;
				8'd186: toneR = `hhc;  8'd187: toneR = `hhc;
				8'd188: toneR = `hhc;  8'd189: toneR = `hhc;
				8'd190: toneR = `hhc;  8'd191: toneR = `hhc;
				default: toneR = `sil;
			endcase
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
                // Start
				8'd0: toneL= `le;  8'd1: toneL= `le;
				8'd2: toneL= `le;  8'd3: toneL= `le;
				8'd4: toneL= `le;  8'd5: toneL= `le;
				8'd6: toneL= `le;  8'd7: toneL= `le;
				8'd8: toneL= `le;  8'd9: toneL= `le;
				8'd10: toneL= `le;  8'd11: toneL= `le;
				8'd12: toneL= `le;  8'd13: toneL= `le;
				8'd14: toneL= `le;  8'd15: toneL= `le;
				8'd16: toneL= `le;  8'd17: toneL= `le;
				8'd18: toneL= `le;  8'd19: toneL= `le;
				8'd20: toneL= `le;  8'd21: toneL= `le;
				8'd22: toneL= `le;  8'd23: toneL= `le;
				8'd24: toneL= `le;  8'd25: toneL= `le;
				8'd26: toneL= `le;  8'd27: toneL= `le;
				8'd28: toneL= `le;  8'd29: toneL= `le;
				8'd30: toneL= `le;  8'd31: toneL= `le;
				8'd32: toneL= `le;  8'd33: toneL= `le;
				8'd34: toneL= `le;  8'd35: toneL= `le;
				8'd36: toneL= `le;  8'd37: toneL= `le;
				8'd38: toneL= `le;  8'd39: toneL= `le;
				8'd40: toneL= `le;  8'd41: toneL= `le;
				8'd42: toneL= `le;  8'd43: toneL= `le;
				8'd44: toneL= `le;  8'd45: toneL= `le;
				8'd46: toneL= `le;  8'd47: toneL= `le;
				8'd48: toneL= `la;  8'd49: toneL= `la;
				8'd50: toneL= `la;  8'd51: toneL= `la;
				8'd52: toneL= `la;  8'd53: toneL= `la;
				8'd54: toneL= `la;  8'd55: toneL= `la;
				8'd56: toneL= `la;  8'd57: toneL= `la;
				8'd58: toneL = `la;  8'd59: toneL = `la;
				// Coin
				// 8'd60: toneL = `sil;  8'd61: toneL = `hb;
				// 8'd62: toneL = `hb;  8'd63: toneL = `hb;
				// 8'd64: toneL = `hb;  8'd65: toneL = `hb;
				// 8'd66: toneL = `hhe;  8'd67: toneL = `hhe;
				// 8'd68: toneL = `hhe;  8'd69: toneL = `hhe;
				// 8'd70: toneL = `hhe;  8'd71: toneL = `hhe;
				// 8'd72: toneL = `hhe;  8'd73: toneL = `hhe;
				// 8'd74: toneL = `hhe;  8'd75: toneL = `hhe;
				// 8'd76: toneL = `hhe;  8'd77: toneL = `hhe;
				// 8'd78: toneL = `hhe;  8'd79: toneL = `hhe;
				// 8'd80: toneL = `hhe;  8'd81: toneL = `hhe;
				// 8'd82: toneL = `hhe;  8'd83: toneL = `hhe;
                default: toneL= `sil;
            endcase
        end
        else if(state == WRITING) begin
            case(ibeatNum)
				// End
				8'd0: toneL = `lg;  8'd1: toneL = `lg;
				8'd2: toneL = `lg;  8'd3: toneL = `lg;
				8'd4: toneL = `le;  8'd5: toneL = `le;
				8'd6: toneL = `le;  8'd7: toneL = `le;
				8'd8: toneL = `lg;  8'd9: toneL = `lg;
				8'd10: toneL = `lg;  8'd11: toneL = `lg;
				8'd12: toneL = `le;  8'd13: toneL = `le;
				8'd14: toneL = `le;  8'd15: toneL = `le;
				8'd16: toneL = `lg;  8'd17: toneL = `lg;
				8'd18: toneL = `lg;  8'd19: toneL = `lg;
				8'd20: toneL = `c;  8'd21: toneL = `c;
				8'd22: toneL = `c;  8'd23: toneL = `c;
				8'd24: toneL = `e;  8'd25: toneL = `e;
				8'd26: toneL = `e;  8'd27: toneL = `e;
				8'd28: toneL = `e;  8'd29: toneL = `e;
				8'd30: toneL = `e;  8'd31: toneL = `e;
				8'd32: toneL = `e;  8'd33: toneL = `e;
				8'd34: toneL = `e;  8'd35: toneL = `e;
				8'd36: toneL = `c;  8'd37: toneL = `c;
				8'd38: toneL = `c;  8'd39: toneL = `c;
				8'd40: toneL = `c;  8'd41: toneL = `c;
				8'd42: toneL = `sil;  8'd43: toneL = `sil;
				8'd44: toneL = `sil;  8'd45: toneL = `sil;
				8'd46: toneL = `sil;  8'd47: toneL = `sil;
				8'd48: toneL = `lba;  8'd49: toneL = `lba;
				8'd50: toneL = `lba;  8'd51: toneL = `lba;
				8'd52: toneL = `lbe;  8'd53: toneL = `lbe;
				8'd54: toneL = `lbe;  8'd55: toneL = `lbe;
				8'd56: toneL = `la;  8'd57: toneL = `la;
				8'd58: toneL = `la;  8'd59: toneL = `la;
				8'd60: toneL = `le;  8'd61: toneL = `le;
				8'd62: toneL = `le;  8'd63: toneL = `le;
				8'd64: toneL = `la;  8'd65: toneL = `la;
				8'd66: toneL = `la;  8'd67: toneL = `la;
				8'd68: toneL = `c;  8'd69: toneL = `c;
				8'd70: toneL = `c;  8'd71: toneL = `c;
				8'd72: toneL = `be;  8'd73: toneL = `be;
				8'd74: toneL = `be;  8'd75: toneL = `be;
				8'd76: toneL = `be;  8'd77: toneL = `be;
				8'd78: toneL = `be;  8'd79: toneL = `be;
				8'd80: toneL = `be;  8'd81: toneL = `be;
				8'd82: toneL = `be;  8'd83: toneL = `be;
				8'd84: toneL = `c;  8'd85: toneL = `c;
				8'd86: toneL = `c;  8'd87: toneL = `c;
				8'd88: toneL = `c;  8'd89: toneL = `c;
				8'd90: toneL = `sil;  8'd91: toneL = `sil;
				8'd92: toneL = `sil;  8'd93: toneL = `sil;
				8'd94: toneL = `sil;  8'd95: toneL = `sil;
				8'd96: toneL = `lbb;  8'd97: toneL = `lbb;
				8'd98: toneL = `lbb;  8'd99: toneL = `lbb;
				8'd100: toneL = `lf;  8'd101: toneL = `lf;
				8'd102: toneL = `lf;  8'd103: toneL = `lf;
				8'd104: toneL = `lb;  8'd105: toneL = `lb;
				8'd106: toneL = `lb;  8'd107: toneL = `lb;
				8'd108: toneL = `lf;  8'd109: toneL = `lf;
				8'd110: toneL = `lf;  8'd111: toneL = `lf;
				8'd112: toneL = `lb;  8'd113: toneL = `lb;
				8'd114: toneL = `lb;  8'd115: toneL = `lb;
				8'd116: toneL = `d;  8'd117: toneL = `d;
				8'd118: toneL = `d;  8'd119: toneL = `d;
				8'd120: toneL = `f;  8'd121: toneL = `f;
				8'd122: toneL = `f;  8'd123: toneL = `f;
				8'd124: toneL = `f;  8'd125: toneL = `f;
				8'd126: toneL = `f;  8'd127: toneL = `f;
				8'd128: toneL = `f;  8'd129: toneL = `f;
				8'd130: toneL = `f;  8'd131: toneL = `f;
				8'd132: toneL = `d;  8'd133: toneL = `d;
				8'd134: toneL = `d;  8'd135: toneL = `sil;
				8'd136: toneL = `d;  8'd137: toneL = `d;
				8'd138: toneL = `d;  8'd139: toneL = `sil;
				8'd140: toneL = `d;  8'd141: toneL = `d;
				8'd142: toneL = `d;  8'd143: toneL = `d;
				8'd144: toneL = `c;  8'd145: toneL = `c;
				8'd146: toneL = `c;  8'd147: toneL = `c;
				8'd148: toneL = `c;  8'd149: toneL = `c;
				8'd150: toneL = `c;  8'd151: toneL = `c;
				8'd152: toneL = `c;  8'd153: toneL = `c;
				8'd154: toneL = `c;  8'd155: toneL = `c;
				8'd156: toneL = `c;  8'd157: toneL = `c;
				8'd158: toneL = `c;  8'd159: toneL = `c;
				8'd160: toneL = `c;  8'd161: toneL = `c;
				8'd162: toneL = `c;  8'd163: toneL = `c;
				8'd164: toneL = `c;  8'd165: toneL = `c;
				8'd166: toneL = `c;  8'd167: toneL = `c;
				8'd168: toneL = `c;  8'd169: toneL = `c;
				8'd170: toneL = `c;  8'd171: toneL = `c;
				8'd172: toneL = `c;  8'd173: toneL = `c;
				8'd174: toneL = `c;  8'd175: toneL = `c;
				8'd176: toneL = `c;  8'd177: toneL = `c;
				8'd178: toneL = `c;  8'd179: toneL = `c;
				8'd180: toneL = `c;  8'd181: toneL = `c;
				8'd182: toneL = `c;  8'd183: toneL = `c;
				8'd184: toneL = `c;  8'd185: toneL = `c;
				8'd186: toneL = `c;  8'd187: toneL = `c;
				8'd188: toneL = `c;  8'd189: toneL = `c;
				8'd190: toneL = `c;  8'd191: toneL = `c;
				default: toneL = `sil;
			endcase
        end
		else
			toneL = `sil;
    end
endmodule