module game_top(
    input wire clk,
    input wire rst,
    input wire MISO,
    input wire [2:0] SW,
    inout wire PS2_DATA,
    inout wire PS2_CLK,
    output reg [2:0] LED,           // 可自行使用
    output wire MOSI,
    output wire SCLK,
    output wire SS,
    output reg [3:0] vgaRed,
    output reg [3:0] vgaGreen,
    output reg [3:0] vgaBlue,
    output wire hsync,
    output wire vsync,
    output wire [6:0] display,
    output wire [3:0] digit,
    output wire audio_mclk, // 主時鐘
    output wire audio_lrck, // 左右聲道切換信號
    output wire audio_sck,  // 串行時鐘
    output wire audio_sdin  // 串行音頻數據
);

//============================================================
// Clock Dividers
//============================================================
wire clk_25;
clock_divider #(.n(2)) clk_div_25MHz(
    .clk(clk),
    .clk_div(clk_25)
);

// 1Hz，用於 LFSR 等定時動作
wire clk_1Hz;
clock_divider #(.n(25)) clk_div_1Hz(
    .clk(clk),
    .clk_div(clk_1Hz)
);

wire clk_5MHz;
clock_divider #(.n(5)) clk_div_5MHz(
    .clk(clk),
    .clk_div(clk_5MHz)
);

// 子彈移動速度時鐘 (降低子彈移動頻率)
wire clk_bullet;
clock_divider #(.n(20)) clk_div_bullet(
    .clk(clk),
    .clk_div(clk_bullet)
);

// 新增敵人移動時鐘
wire clk_enemy;
clock_divider #(.n(23)) clk_div_enemy(  // 可以調整 n 的值來改變敵人移動速度
    .clk(clk),
    .clk_div(clk_enemy)
);

//============================================================
// Pmod JSTK (搖桿) Interface
//============================================================
wire [39:0] joystick_data;
wire [7:0] sndData;
assign sndData = {8'b100000, {SW[1], SW[2]}};

PmodJSTK jstk_inst(
    .CLK(clk),
    .RST(rst),
    .sndRec(clk_5MHz),
    .DIN(sndData),
    .MISO(MISO),
    .MOSI(MOSI),
    .SCLK(SCLK),
    .SS(SS),
    .DOUT(joystick_data)
);

// 搖桿 x, y 值 (10 bits)
wire [9:0] joystick_x = {joystick_data[9:8], joystick_data[23:16]};
wire [9:0] joystick_y = {joystick_data[25:24], joystick_data[39:32]};
// 按鈕
wire [2:0] joystick_button = {joystick_data[1], joystick_data[2], joystick_data[0]};

//============================================================
// Binary to BCD 轉換 (顯示用)
//============================================================
wire [15:0] x_bcd, y_bcd;
Binary_To_BCD x_converter(
    .CLK(clk),
    .RST(rst),
    .START(1'b1),
    .BIN(joystick_x),
    .BCDOUT(x_bcd)
);

Binary_To_BCD y_converter(
    .CLK(clk),
    .RST(rst),
    .START(1'b1),
    .BIN(joystick_y),
    .BCDOUT(y_bcd)
);

// 將 BCD 轉回 16 位二進位數值
wire [15:0] joystick_x_final = (x_bcd[15:12] * 16'd1000) + (x_bcd[11:8] * 16'd100) + (x_bcd[7:4] * 16'd10) + x_bcd[3:0];
wire [15:0] joystick_y_final = (y_bcd[15:12] * 16'd1000) + (y_bcd[11:8] * 16'd100) + (y_bcd[7:4] * 16'd10) + y_bcd[3:0];

//============================================================
// 七段顯示器 (Score)
//============================================================
reg [7:0] score;
wire [15:0] nums;
assign nums = {4'hF, 4'hF, score[7:4], score[3:0]};
SevenSegment m1(.display(display), .digit(digit), .nums(nums), .rst(rst), .clk(clk));

//============================================================
// Keyboard Interface
//============================================================
wire [511:0] key_down;
wire [8:0] last_change;
wire been_ready;

KeyboardDecoder key_de (
    .key_down(key_down),
    .last_change(last_change),
    .key_valid(been_ready),
    .PS2_DATA(PS2_DATA),
    .PS2_CLK(PS2_CLK),
    .rst(rst),
    .clk(clk)
);

// WASD Keycodes
parameter [8:0] KEY_W = 9'b0_0001_1101; // W
parameter [8:0] KEY_A = 9'b0_0001_1100; // A
parameter [8:0] KEY_S = 9'b0_0001_1011; // S
parameter [8:0] KEY_D = 9'b0_0010_0011; // D

// SHIFT鍵控制模式
parameter [8:0] LEFT_SHIFT_CODES  = 9'b0_0001_0010;
parameter [8:0] RIGHT_SHIFT_CODES = 9'b0_0101_1001;

wire shift_down = key_down[LEFT_SHIFT_CODES] | key_down[RIGHT_SHIFT_CODES];

//============================================================
// VGA 控制器
//============================================================
wire [9:0] h_cnt;
wire [9:0] v_cnt;
wire valid;
vga_controller vga_inst(
    .pclk(clk_25),
    .reset(rst),
    .h_cnt(h_cnt),
    .v_cnt(v_cnt),
    .valid(valid),
    .hsync(hsync),
    .vsync(vsync)
);

//============================================================
// 音樂與音效
//============================================================
wire [21:0] music_note_div;
wire [15:0] audio_in_left, audio_in_right; // 背景音樂音訊
wire [15:0] bullet_audio;    // 子彈音效
reg bullet_sound_trigger;    // 子彈音效觸發

background_music bgm_inst (
    .clk(clk_1Hz),   
    .rst(rst),
    .note_div(music_note_div)
);

buzzer_control music_gen (
    .clk(clk),
    .rst(rst),
    .note_div(music_note_div),    
    .audio_left(audio_in_left),  
    .audio_right(audio_in_right),
    .vol_num(3'b011)
);

bullet_sound bullet_sound_inst (
    .clk(clk),              
    .rst(rst),              
    .trigger(bullet_sound_trigger), 
    .audio(bullet_audio)    
);

wire [15:0] mixed_audio;
audio_mixer audio_mixer_inst (
    .bgm_audio(audio_in_left),
    .sfx_audio(bullet_audio),
    .mixed_audio(mixed_audio)
);

speaker_control speaker (
    .clk(clk),
    .rst(rst),
    .audio_in_left(mixed_audio),
    .audio_in_right(mixed_audio),
    .audio_mclk(audio_mclk),
    .audio_lrck(audio_lrck),
    .audio_sck(audio_sck),
    .audio_sdin(audio_sdin)
);

//============================================================
// 遊戲參數與變數
//============================================================
reg [9:0] player_x;
reg [9:0] player_y;

reg [9:0] bullet_x;
reg [9:0] bullet_y;
reg bullet_active;
reg signed [9:0] bullet_dx;
reg signed [9:0] bullet_dy;
reg bullet_hit;

// 多敵人設定
parameter MAX_ENEMIES = 10;
reg [9:0] enemy_x[MAX_ENEMIES - 1:0];
reg [9:0] enemy_y[MAX_ENEMIES - 1:0];
reg enemy_active[MAX_ENEMIES - 1:0];

// 在參數區域添加敵人速度參數
parameter ENEMY_SPEED = 2;  // 敵人移動速度
// 在 reg 宣告區域添加敵人移動相關的寄存器
reg signed [9:0] enemy_dx[MAX_ENEMIES - 1:0];  // 敵人 X 方向速度
reg signed [9:0] enemy_dy[MAX_ENEMIES - 1:0];  // 敵人 Y 方向速度


reg signed [15:0] dx, dy; // 允許負值
reg [15:0] magnitude;

parameter CENTER_X = 512;  // 搖杆中心X座標
parameter CENTER_Y = 512;  // 搖杆中心Y座標
parameter DEAD_ZONE = 100; // 死區範圍
parameter MAX_BULLET_SPEED = 5; // 子彈最大速度

integer i;
reg [9:0] LFSR;

// Initialize player position at screen center
initial begin
    player_x = 320;
    player_y = 240;
    bullet_active = 0;
    bullet_dx = 0;
    bullet_dy = -1; // Default upward
    for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
        enemy_x[i] = 0;
        enemy_y[i] = 0;
        enemy_active[i] = 0;
        enemy_dx[i] = 0;
        enemy_dy[i] = 0;
    end
    score = 0; // Initial score is 0
    bullet_sound_trigger = 0;
end

//============================================================
// LFSR 隨機數生成，用於敵人隨機位置
//============================================================
always @(posedge clk_1Hz or posedge rst) begin
    if (rst) begin
        LFSR <= 10'b1010_0000_00;
    end else begin
        LFSR[9] <= LFSR[1];
        LFSR[8] <= LFSR[4];
        LFSR[7] <= LFSR[8] ^ LFSR[1];
        LFSR[6] <= LFSR[7] ^ LFSR[1];
        LFSR[5] <= LFSR[6];
        LFSR[4] <= LFSR[5] ^ LFSR[1];
        LFSR[3] <= LFSR[4];
        LFSR[2] <= LFSR[3];
        LFSR[1] <= LFSR[2];
        LFSR[0] <= LFSR[9];
    end
end

//============================================================
// 玩家位置更新 (WASD 或 搖桿控制)
//============================================================
// Update player position based on joystick input, WASD keys, or control mode
reg prev_key_w, prev_key_a, prev_key_s, prev_key_d;
always @(posedge clk_25 or posedge rst) begin
    if (rst) begin
        player_x <= 320;
        player_y <= 240;
        prev_key_w <= 0;
        prev_key_a <= 0;
        prev_key_s <= 0;
        prev_key_d <= 0;
    end else begin
        // 使用 SHIFT 控制模式：搖桿移動玩家位置(較平滑)
        if (shift_down) begin
            // 根據搖桿值，將範圍 0-1023 映射到螢幕範圍
            // player_x, player_y = map(joystick_x_final,0-1023)到 0-639, 0-479
            // 簡單做法： player_x,player_y直接用比例計算
            player_x <= (joystick_x_final * 640) >> 10;
            player_y <= (joystick_y_final * 480) >> 10;
        end else begin
            // 未按 SHIFT：用 WASD 每次按下移動固定距離
            if (!prev_key_w && key_down[KEY_W] && player_y > 5) player_y <= player_y - 5;
            if (!prev_key_s && key_down[KEY_S] && player_y < 475) player_y <= player_y + 5;
            if (!prev_key_a && key_down[KEY_A] && player_x > 5) player_x <= player_x - 5;
            if (!prev_key_d && key_down[KEY_D] && player_x < 635) player_x <= player_x + 5;

            prev_key_w <= key_down[KEY_W];
            prev_key_a <= key_down[KEY_A];
            prev_key_s <= key_down[KEY_S];
            prev_key_d <= key_down[KEY_D];
        end
    end
end

//============================================================
// 子彈生成與移動、敵人生成與消滅
//============================================================
always @(posedge clk_bullet or posedge rst) begin
    if (rst) begin
        bullet_active <= 0;
        bullet_x <= 0;
        bullet_y <= 0;
        bullet_dx <= 0;
        bullet_dy <= 0;
        bullet_hit <= 0;
        score <= 0;
        bullet_sound_trigger <= 0;
        for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
            enemy_active[i] <= 0;
        end
    end else begin
        // 按下搖桿按鈕(不在shift模式)來發射子彈
        if (joystick_button[0] && !bullet_active && !shift_down) begin
            dx = $signed(joystick_x_final) - $signed(CENTER_X);
            dy = $signed(joystick_y_final) - $signed(CENTER_Y);

            magnitude = (dx*dx + dy*dy) >> 8;

            if (magnitude > (DEAD_ZONE*DEAD_ZONE)>>8) begin
                bullet_active <= 1;
                bullet_x <= player_x + 10;
                bullet_y <= player_y;
                bullet_hit <= 0;
                bullet_sound_trigger <= 1;

                if (dx > 0) bullet_dx <= (dx * MAX_BULLET_SPEED) >> 9;
                else        bullet_dx <= -(-dx * MAX_BULLET_SPEED) >> 9;
                
                if (dy > 0) bullet_dy <= (dy * MAX_BULLET_SPEED) >> 9;
                else        bullet_dy <= -(-dy * MAX_BULLET_SPEED) >> 9;
            end
        end else if (bullet_active) begin
            bullet_sound_trigger <= 0; // 發射後關閉音效觸發
            if (bullet_x >= 5 && bullet_x <= 635 && bullet_y >= 5 && bullet_y <= 475) begin
                bullet_x <= bullet_x + bullet_dx;
                bullet_y <= bullet_y + bullet_dy;
            end else begin
                bullet_active <= 0;
            end

            // 檢測子彈撞擊敵人
            for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
                if (enemy_active[i] &&
                    bullet_x + 5 >= enemy_x[i] && bullet_x < enemy_x[i] + 20 &&
                    bullet_y + 10 >= enemy_y[i] && bullet_y < enemy_y[i] + 20) begin
                    enemy_active[i] <= 0;
                    bullet_active <= 0;
                    bullet_hit <= 1;
                    if (score < 8'd99) score <= score + 1;
                end
            end
        end else begin
            bullet_sound_trigger <= 0;
            // 沒有子彈動作時，隨機產生新的敵人(若有空缺)
            for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
                if (!enemy_active[i]) begin
                    enemy_x[i] <= LFSR % 640;
                    enemy_y[i] <= LFSR % 480;
                    enemy_active[i] <= 1;
                end
            end
        end
    end
end


//============================================================
// VGA 輸出
//============================================================
// VGA output for player, bullet, and enemy
always @(*) begin
    vgaRed = 4'h0;
    vgaGreen = 4'h0;
    vgaBlue = 4'h0;
    if (valid) begin
        // 玩家
        if (v_cnt >= player_y && v_cnt < player_y + 20 && h_cnt >= player_x && h_cnt < player_x + 20) begin
            vgaRed = 4'hF; // Player block in red
            vgaGreen = 4'h0;
            vgaBlue = 4'h0;
        end 
        // 子彈
        else if (bullet_active && v_cnt >= bullet_y && v_cnt < bullet_y + 10 && h_cnt >= bullet_x && h_cnt < bullet_x + 5) begin
            vgaRed = 4'h0;
            vgaGreen = 4'hF; // Bullet block in green
            vgaBlue = 4'h0;
        end 
        // 敵人
        else begin
            for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
                if (enemy_active[i] && v_cnt >= enemy_y[i] && v_cnt < enemy_y[i] + 20 && h_cnt >= enemy_x[i] && h_cnt < enemy_x[i] + 20) begin
                    vgaBlue = 4'hF; // Enemy block in blue
                end
            end
        end
    end
end

endmodule
