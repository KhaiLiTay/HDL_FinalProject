module game_top(
    input wire clk,
    input wire rst,
    input wire MISO,
    input wire [2:0] SW,
    inout wire PS2_DATA,
    inout wire PS2_CLK,
    output reg [2:0] LED,			// LEDs 2, 1, and 0
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

// Clock divider for 25MHz VGA clock
wire clk_25;
clock_divider #(.n(2)) clk_div_25MHz(
    .clk(clk),
    .clk_div(clk_25)
);

// Clock divider for 1Hz bullet firing rate
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

// Clock divider for bullet movement speed
wire clk_bullet;
clock_divider #(.n(20)) clk_div_bullet(
    .clk(clk),
    .clk_div(clk_bullet)
);

// Pmod JSTK interface
wire [39:0] joystick_data;
wire [7:0] sndData;
// Data to be sent to PmodJSTK, lower two bits will turn on leds on PmodJSTK
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



// Extract joystick components
// 從PmodJSTK文檔中可以看到，搖桿數據格式如下：
wire [9:0] joystick_x = {joystick_data[9:8], joystick_data[23:16]};
wire [9:0] joystick_y = {joystick_data[25:24], joystick_data[39:32]};
// 從示例代碼可以看到按鈕的處理方式
wire [2:0] joystick_button = {joystick_data[1], joystick_data[2], joystick_data[0]};

// Binary to BCD 轉換器實例
wire [15:0] x_bcd, y_bcd;
wire x_convert_done, y_convert_done;

Binary_To_BCD x_converter(
    .CLK(clk),
    .RST(rst),
    .START(1'b1),        // 持續轉換
    .BIN(joystick_x),
    .BCDOUT(x_bcd)
);

Binary_To_BCD y_converter(
    .CLK(clk),
    .RST(rst),
    .START(1'b1),        // 持續轉換
    .BIN(joystick_y),
    .BCDOUT(y_bcd)
);

// 這兩個 wire 沒有事先宣告
wire [15:0] joystick_x_final;  
wire [15:0] joystick_y_final;
// 應該改為合併數字的寫法，將BCD值轉回二進制：
assign joystick_x_final = (x_bcd[15:12] * 16'd1000) + (x_bcd[11:8] * 16'd100) + (x_bcd[7:4] * 16'd10) + x_bcd[3:0];
assign joystick_y_final = (y_bcd[15:12] * 16'd1000) + (y_bcd[11:8] * 16'd100) + (y_bcd[7:4] * 16'd10) + y_bcd[3:0];

// Score register
reg [7:0] score;

wire [15:0] nums;
assign nums = {4'hF, 4'hF, score[7:4], score[3:0]};
SevenSegment m1(.display(display), .digit(digit), .nums(nums), .rst(rst), .clk(clk));

// VGA controller signals
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

//music
wire [21:0] music_note_div;
wire [15:0] audio_in_left, audio_in_right; // 音頻數據

wire [15:0] bullet_audio;    // 子彈音效信號
reg bullet_sound_trigger;    // 子彈音效觸發信號

wire [15:0] mixed_audio;

background_music bgm_inst (
    .clk(clk_1Hz),   // 使用 1Hz 時鐘控制音階變化速度
    .rst(rst),
    .note_div(music_note_div)
);
buzzer_control music_gen (
    .clk(clk),
    .rst(rst),
    .note_div(music_note_div),    // 背景音樂的音符分頻值
    .audio_left(audio_in_left),  // 音頻左聲道輸出
    .audio_right(audio_in_right),// 音頻右聲道輸出
    .vol_num(3'b011)             // 預設音量
);
speaker_control speaker (
    .clk(clk),
    .rst(rst),
    .audio_in_left(mixed_audio), // 混合後的音頻
    .audio_in_right(mixed_audio),// 混合後的音頻
    .audio_mclk(audio_mclk),
    .audio_lrck(audio_lrck),
    .audio_sck(audio_sck),
    .audio_sdin(audio_sdin)
);
bullet_sound bullet_sound_inst (
    .clk(clk),                // 系統時鐘
    .rst(rst),                // 重置信號
    .trigger(bullet_sound_trigger), // 子彈音效觸發信號
    .audio(bullet_audio)      // 子彈音效輸出
);
audio_mixer audio_mixer_inst (
    .bgm_audio(audio_in_left),    // 背景音樂
    .sfx_audio(bullet_audio),     // 子彈音效
    .mixed_audio(mixed_audio)     // 混合音頻
);

// Player and bullet positions
reg [9:0] player_x;
reg [9:0] player_y;
reg [9:0] bullet_x;
reg [9:0] bullet_y;
reg bullet_active;
reg signed [9:0] bullet_dx;
reg signed [9:0] bullet_dy;

// Enemy position and state


reg bullet_hit;
// 最大敌人数
parameter MAX_ENEMIES = 10;

// 敌人位置和状态
reg [9:0] enemy_x[MAX_ENEMIES - 1:0];
reg [9:0] enemy_y[MAX_ENEMIES - 1:0];
reg enemy_active[MAX_ENEMIES - 1:0];

reg signed [31:0] dx, dy;
reg [31:0] magnitude;

parameter CENTER_X = 512;  // 搖桿中心X座標
parameter CENTER_Y = 512;  // 搖桿中心Y座標
parameter DEAD_ZONE = 100; // 死區範圍
parameter MAX_BULLET_SPEED = 5; // 子彈最大速度

integer i;
reg [9:0] LFSR;

// 在參數區域添加敵人速度參數
parameter ENEMY_SPEED = 2;  // 敵人移動速度
// 在 reg 宣告區域添加敵人移動相關的寄存器
reg signed [9:0] enemy_dx[MAX_ENEMIES - 1:0];  // 敵人 X 方向速度
reg signed [9:0] enemy_dy[MAX_ENEMIES - 1:0];  // 敵人 Y 方向速度

// Initialize player position at screen center
initial begin
    player_x = 320; // Center of 640 width
    player_y = 240; // Center of 480 height
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
end

// Update player position based on joystick input
always @(posedge clk_25 or posedge rst) begin
    if (rst) begin
        player_x <= 320;
        player_y <= 240;
    end else begin
        // Map joystick_x and joystick_y range (0-1023) to screen dimensions (0-639, 0-479)
        //player_x <= (joystick_x_final * 640) >> 10;
        //player_y <= (joystick_y_final * 480) >> 10;
    end
end

// Bullet generation and movement
always @(posedge clk_bullet or posedge rst) begin
    if (rst) begin
        bullet_active <= 0;
        bullet_x <= 0;
        bullet_y <= 0;
        bullet_dx <= 0;
        bullet_dy <= 0;
        bullet_hit <= 0;
        for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
            enemy_active[i] <= 0;
            enemy_x[i] <= 0;
            enemy_y[i] <= 0;
            enemy_dx[i] <= 0;
            enemy_dy[i] <= 0;
        end
        score <= 0; // Reset score
        bullet_sound_trigger <= 0; // 重置音效觸發信號
    end else if (joystick_button[0] && !bullet_active) begin  // 使用按鈕0觸發射擊
        // 計算搖桿相對於中心的偏移
            dx = $signed(joystick_x_final) - $signed(CENTER_X);
            dy = $signed(joystick_y_final) - $signed(CENTER_Y);
            
            // 計算向量長度（使用近似值避免除法）
            magnitude = (dx * dx + dy * dy) >> 8; // 除以256作為縮放因子
            
            // 只有當搖桿移動超過死區時才發射
            if (magnitude > DEAD_ZONE * DEAD_ZONE >> 8) begin
                bullet_active <= 1;
                bullet_x <= player_x + 10;
                bullet_y <= player_y;
                bullet_hit <= 0;
                bullet_sound_trigger <= 1; // 觸發子彈音效

                // 標準化方向向量並乘以速度
                // 使用位移運算代替除法，並保持合適的精度
                if (dx > 0) begin
                    bullet_dx <= (dx * MAX_BULLET_SPEED) >> 9;
                end else begin
                    bullet_dx <= -(-dx * MAX_BULLET_SPEED) >> 9;
                end
                
                if (dy > 0) begin
                    bullet_dy <= (dy * MAX_BULLET_SPEED) >> 9;
                end else begin
                    bullet_dy <= -(-dy * MAX_BULLET_SPEED) >> 9;
                end
            end
    end
    else if (bullet_active) begin  // 需要增加這部分
        if (bullet_x >= 5 && bullet_x <= 635 && bullet_y >= 5 && bullet_y <= 475) begin
            bullet_x <= bullet_x + bullet_dx;
            bullet_y <= bullet_y + bullet_dy;
        end else begin
            bullet_active <= 0;
        end
        // 檢查子彈和敵人碰撞
        for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
            if (enemy_active[i]) begin
                if (bullet_x + 5 >= enemy_x[i] && bullet_x < enemy_x[i] + 20 &&
                    bullet_y + 10 >= enemy_y[i] && bullet_y < enemy_y[i] + 20) begin
                    enemy_active[i] <= 0;
                    bullet_active <= 0;
                    bullet_hit <= 1;
                    if (score <= 8'd99) score <= score + 1;
                end else begin
                    // 敵人移動邏輯
                    dx = $signed(player_x) - $signed(enemy_x[i]);
                    dy = $signed(player_y) - $signed(enemy_y[i]);
                    
                    // 更新敵人方向
                    if (dx > 0) enemy_dx[i] <= ENEMY_SPEED;
                    else if (dx < 0) enemy_dx[i] <= -ENEMY_SPEED;
                    else enemy_dx[i] <= 0;
                    
                    if (dy > 0) enemy_dy[i] <= ENEMY_SPEED;
                    else if (dy < 0) enemy_dy[i] <= -ENEMY_SPEED;
                    else enemy_dy[i] <= 0;

                    // 更新敵人位置
                    if (enemy_x[i] + enemy_dx[i] >= 0 && enemy_x[i] + enemy_dx[i] < 640)
                        enemy_x[i] <= enemy_x[i] + enemy_dx[i];
                    if (enemy_y[i] + enemy_dy[i] >= 0 && enemy_y[i] + enemy_dy[i] < 480)
                        enemy_y[i] <= enemy_y[i] + enemy_dy[i];
                end
            end
        end
    end
    else begin
        for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
            if (!enemy_active[i]) begin
                //random_seed <= LFSR;
                enemy_x[i] <= LFSR % 640; // 随机x坐标
                enemy_y[i] <= LFSR % 480; // 随机y坐标
                enemy_active[i] <= 1;
            end
        end
        bullet_sound_trigger <= 0; // 停止音效觸發信號
    end
end

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



// VGA output for player, bullet, and enemy
always @(*) begin
    vgaRed = 4'h0;
    vgaGreen = 4'h0;
    vgaBlue = 4'h0;
    if (valid) begin
        if (v_cnt >= player_y && v_cnt < player_y + 20 && h_cnt >= player_x && h_cnt < player_x + 20) begin
            vgaRed = 4'hF; // Player block in red
            vgaGreen = 4'h0;
            vgaBlue = 4'h0;
        end else if (bullet_active && v_cnt >= bullet_y && v_cnt < bullet_y + 10 && h_cnt >= bullet_x && h_cnt < bullet_x + 5) begin
            vgaRed = 4'h0;
            vgaGreen = 4'hF; // Bullet block in green
            vgaBlue = 4'h0;
        end 
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

//============================================================
// 七段顯示器 (Score 與 搖桿座標切換)
// SW[0] = 0 顯示 Score
// SW[0] = 1, SW[1] = 1 顯示 x_bcd
// SW[0] = 1, SW[1] = 0 顯示 y_bcd
//============================================================
/*wire [15:0] score_bcd = {4'hF,4'hF,score[7:4],score[3:0]};
wire [15:0] nums_to_display = (SW[0] == 1'b0) ? score_bcd :
                              (SW[1] == 1'b1) ? x_bcd : y_bcd;

SevenSegment m1(
    .display(display), 
    .digit(digit), 
    .nums(nums_to_display),
    .rst(rst), 
    .clk(clk)
);*/