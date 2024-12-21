module game_top(
    input wire clk,
    input wire rst,
    input wire MISO,
    input wire [2:0] SW,
    inout wire PS2_DATA,
    inout wire PS2_CLK,
	input wire BtnU,
    input wire BtnD,
    output reg [4:0] LED,
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

// 添加敵人移動時鐘
wire enemy_move_clk;
clock_divider #(.n(23)) clk_div_enemy(  // 可調整分頻比例
    .clk(clk),
    .clk_div(enemy_move_clk)
);

// 添加射擊部隊移動時鐘
wire shooter_move_clk;
clock_divider #(.n(24)) clk_div_shooter(  // 可調整分頻比例
    .clk(clk),
    .clk_div(shooter_move_clk)
);
//============================================================
// FSM States
//============================================================
parameter MENU_IDLE = 3'b000;
parameter MENU_TUTORIAL = 3'b001;
parameter GAME_RUNNING = 3'b010;
parameter GAME_OVER = 3'b011;
parameter GAME_WIN = 3'b100;

reg [2:0] current_state, next_state;
reg [1:0] menu_selected; // 0: Start Game, 1: Tutorial

//============================================================
// FSM Logic
//============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        current_state <= MENU_IDLE;
    end else begin
        current_state <= next_state;
    end
end

always @(*) begin
    case (current_state)
        MENU_IDLE: begin
            if (joystick_button[0]) begin
                if (menu_selected == 0) next_state = GAME_RUNNING;
                else if (menu_selected == 1) next_state = MENU_TUTORIAL;
                else next_state = MENU_IDLE;
            end else next_state = MENU_IDLE;
        end
        
        MENU_TUTORIAL: begin
            if (joystick_button[1]) next_state = MENU_IDLE; // 回到選單
            else next_state = MENU_TUTORIAL;
        end

        GAME_RUNNING: begin
            if (score >= 10) next_state = GAME_WIN; // 分數達到 10，切換到 WIN
            else next_state = GAME_RUNNING;
        end

        GAME_OVER: begin
            if (joystick_button[2]) next_state = MENU_IDLE;
            else next_state = GAME_OVER;
        end

        GAME_WIN: begin
            if (joystick_button[2]) next_state = MENU_IDLE; // 回到主選單
            else next_state = GAME_WIN;
        end

        default: next_state = MENU_IDLE;
    endcase
end

//============================================================
// Menu Selection Logic
//============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        menu_selected <= 0;
    end else if (current_state == MENU_IDLE) begin
        if (BtnU && menu_selected > 0) menu_selected <= menu_selected - 1;
        else if (BtnD && menu_selected < 1) menu_selected <= menu_selected + 1;
    end
end

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

reg BtnU_pulse, BtnD_pulse;
reg [3:0] vol_num;

always @ (posedge clk) begin
    if (rst) begin
        BtnU_pulse <= 0;
        BtnD_pulse <= 0;
    end else begin
        BtnU_pulse <= BtnU;
        BtnD_pulse <= BtnD;
    end
end

// 音量調整邏輯
always @(posedge clk or posedge rst) begin
    if (rst) begin
        vol_num <= 4'b0011; // 預設音量
    end else begin
        if (BtnU && ~BtnU_pulse && vol_num < 5) begin
            vol_num <= vol_num + 1; // 音量增加
        end
        if (BtnD && ~BtnD_pulse && vol_num > 1) begin
            vol_num <= vol_num - 1; // 音量減少
        end
    end
end

// 音量LED顯示
always @ (posedge clk or posedge rst) begin
		if (rst) begin
			LED[4:0] <= 0;
		end 
		else begin
			case(vol_num)
			1: LED[4:0] <= 5'b0_0001;
			2: LED[4:0] <= 5'b0_0011;
			3: LED[4:0] <= 5'b0_0111;
			4: LED[4:0] <= 5'b0_1111;
			5: LED[4:0] <= 5'b1_1111;
			default: begin			
				LED[4:0] <= 0;
			end
			endcase
		end
	end

// 背景音樂模組
reg BtnU_pulse, BtnD_pulse;
reg [3:0] vol_num;

always @ (posedge clk) begin
    if (rst) begin
        BtnU_pulse <= 0;
        BtnD_pulse <= 0;
    end else begin
        BtnU_pulse <= BtnU;
        BtnD_pulse <= BtnD;
    end
end

// 音量調整邏輯
always @(posedge clk or posedge rst) begin
    if (rst) begin
        vol_num <= 4'b0011; // 預設音量
    end else begin
        if (BtnU && ~BtnU_pulse && vol_num < 5) begin
            vol_num <= vol_num + 1; // 音量增加
        end
        if (BtnD && ~BtnD_pulse && vol_num > 1) begin
            vol_num <= vol_num - 1; // 音量減少
        end
    end
end

// 音量LED顯示
always @ (posedge clk or posedge rst) begin
		if (rst) begin
			LED[4:0] <= 0;
		end 
		else begin
			case(vol_num)
			1: LED[4:0] <= 5'b0_0001;
			2: LED[4:0] <= 5'b0_0011;
			3: LED[4:0] <= 5'b0_0111;
			4: LED[4:0] <= 5'b0_1111;
			5: LED[4:0] <= 5'b1_1111;
			default: begin			
				LED[4:0] <= 0;
			end
			endcase
		end
	end

// 背景音樂模組
background_music bgm_inst (
    .clk(clk_1Hz),   
    .rst(rst),
    .note_div(music_note_div)
);

// 音頻控制模組 (支援音量調整)
buzzer_control music_gen (
    .clk(clk),
    .rst(rst),
    .note_div(music_note_div),    
    .audio_left(audio_in_left),  
    .audio_right(audio_in_right),
    .vol_num(vol_num) // 音量調整輸入
);

// 音頻輸出模組

bullet_sound bullet_sound_inst (
    .clk(clk),               // 系統時鐘
    .rst(rst),               // 重置信號
    .trigger(bullet_sound_trigger), // 音效觸發
    .vol_num(vol_num),       // 音量控制
    .audio(bullet_audio)     // 音效輸出
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
// 修改敵人位置和速度的定義為有符號數
reg signed [10:0] enemy_x[MAX_ENEMIES - 1:0];  // 改為11位有符號數，可以處理負值
reg [9:0] enemy_y[MAX_ENEMIES - 1:0];          // y座標不需要處理負值
reg signed [4:0] enemy_dx[MAX_ENEMIES - 1:0];  // 已經是有符號數

reg enemy_active[MAX_ENEMIES - 1:0];
// 在遊戲參數部分添加
parameter signed ENEMY_SPEED = 10;  // 敵人移動速度

// 在多敵人設定部分添加
reg [MAX_ENEMIES-1:0] bullet_hit_enemy;  // 新增：用於標記被子彈擊中的敵人

// 在遊戲參數部分添加
parameter MAX_SHOOTERS = 5;  // 射擊部隊的最大數量
reg signed [10:0] shooter_x[MAX_SHOOTERS - 1:0];
reg [9:0] shooter_y[MAX_SHOOTERS - 1:0];
reg shooter_active[MAX_SHOOTERS - 1:0];
reg signed [4:0] shooter_dx[MAX_SHOOTERS - 1:0];
reg [MAX_SHOOTERS-1:0] bullet_hit_shooter;  // 新增：用於標記被子彈擊中的射擊部隊


reg [7:0] score;

reg [7:0] health;  // 7-bit 可以表示 0-127，足夠表示 50
reg [MAX_ENEMIES-1:0] enemy_hit_player;  // 用於標記撞到玩家的敵人

reg signed [31:0] dx, dy;
reg [31:0] magnitude;

parameter CENTER_X = 512;  
parameter CENTER_Y = 512;  
parameter DEAD_ZONE = 100; 
parameter MAX_BULLET_SPEED = 5; 
// 標準化方向向量，使總速度恆定為 MAX_BULLET_SPEED
// 使用更大的位寬來避免精度損失
reg signed [31:0] normalized_dx, normalized_dy;
reg [31:0] sqrt_mag;

integer i;
reg [9:0] LFSR;

// 初始值
initial begin
    player_x = 320;
    player_y = 240;
    bullet_active = 0;
    bullet_dx = 0;
    bullet_dy = -1;
    for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
        enemy_x[i] = 0;
        enemy_y[i] = 0;
        enemy_active[i] = 0;
        enemy_dx[i] = 0;  // 添加速度初始化
    end
    // 在 initial begin 中添加
    for (i = 0; i < MAX_SHOOTERS; i = i + 1) begin
        shooter_x[i] = 0;
        shooter_y[i] = 0;
        shooter_active[i] = 0;
        shooter_dx[i] = 0;
    end
    score = 0;
    bullet_sound_trigger = 0;
    health = 50;  // 設置初始生命值為50
    enemy_hit_player = 0;
end

//============================================================
// LFSR 隨機數生成，用於敵人隨機位置
//============================================================
/*always @(posedge clk_1Hz or posedge rst) begin
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
end*/

always @(posedge clk_1Hz or posedge rst) begin
    if (rst) begin
        LFSR <= 10'b1010_1010_10;  // 不能全為0的初始值
    end else begin
        // 10-bit maximum-length LFSR
        // Polynomial: x^10 + x^7 + 1
        LFSR <= {LFSR[8:0], LFSR[9] ^ LFSR[6]};
    end
end

//============================================================
// 玩家位置更新 (WASD 或 搖桿控制)
//============================================================
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
        /*for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
            bullet_hit_enemy[i] <= 0;
        end*/
        bullet_hit_enemy <= 0;
        bullet_hit_shooter <= 0;
    end else begin
        // 如果進入 WIN 狀態，重置分數與相關變數
        if (current_state == GAME_WIN) begin
            bullet_active <= 0;
            bullet_x <= 0;
            bullet_y <= 0;
            bullet_dx <= 0;
            bullet_dy <= 0;
            bullet_hit <= 0;
            score <= 0; // 分數重置
            bullet_sound_trigger <= 0;
            for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
                enemy_active[i] <= 0;
            end
        end else if (joystick_button[0] && !bullet_active && !shift_down) begin
            /*for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
            bullet_hit_enemy[i] <= 0;
        end*/
        // 此处改为条件性重置击中标记
        if (bullet_active) begin  // 当子弹不活跃时重置击中标记
            bullet_hit_enemy <= 0;
            bullet_hit_shooter <= 0;
        end
        // 按下搖桿按鈕(不在shift模式)來發射子彈
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
                    //enemy_active[i] <= 0;
                    bullet_hit_enemy[i] <= 1;
                    bullet_active <= 0;
                    bullet_hit <= 1;
                    if (score < 8'd9) score <= score + 1; // 達到 10 分會進入 WIN 狀態
                end
            end

            // 檢測子彈撞擊射擊部隊
            for (i = 0; i < MAX_SHOOTERS; i = i + 1) begin
                if (shooter_active[i] &&
                    bullet_x + 5 >= shooter_x[i] && bullet_x < shooter_x[i] + 20 &&
                    bullet_y + 10 >= shooter_y[i] && bullet_y < shooter_y[i] + 20) begin
                    bullet_hit_shooter[i] <= 1;  // 設置射擊部隊被擊中標記
                    bullet_active <= 0;
                    bullet_hit <= 1;
                    if (score < 8'd99) score <= score + 2;  // 可以給更多分數
                end
            end

            // 檢測子彈撞擊射擊部隊
            for (i = 0; i < MAX_SHOOTERS; i = i + 1) begin
                if (shooter_active[i] &&
                    bullet_x + 5 >= shooter_x[i] && bullet_x < shooter_x[i] + 20 &&
                    bullet_y + 10 >= shooter_y[i] && bullet_y < shooter_y[i] + 20) begin
                    bullet_hit_shooter[i] <= 1;  // 設置射擊部隊被擊中標記
                    bullet_active <= 0;
                    bullet_hit <= 1;
                    if (score < 8'd99) score <= score + 2;  // 可以給更多分數
                end
            end
        end else begin
            bullet_sound_trigger <= 0;
            // 沒有子彈動作時，隨機產生新的敵人(若有空缺)
            /*for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
                if (!enemy_active[i]) begin
                    enemy_x[i] <= LFSR % 640;
                    enemy_y[i] <= LFSR % 480;
                    enemy_active[i] <= 1;
                end
            end*/
        end
    end
end

// 新增一個專門用於敵人生成的 always 區塊
always @(posedge enemy_move_clk or posedge rst) begin
    if (rst) begin
        for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
            enemy_active[i] <= 0;
            enemy_x[i] <= 0;
            enemy_y[i] <= 0;
            enemy_dx[i] <= 0;
        end
        health <= 50;
        enemy_hit_player <= 0;
    end else begin
        enemy_hit_player <= 0;  // 重置碰撞標記
        // 第一部分：處理現有敵人的移動
        for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
            if (bullet_hit_enemy[i]) begin
                enemy_active[i] <= 0;  // 被子彈擊中
            end else if (enemy_active[i]) begin
                // 檢查是否撞到玩家
                if (enemy_x[i] + 20 >= player_x && enemy_x[i] < player_x + 20 &&
                    enemy_y[i] + 20 >= player_y && enemy_y[i] < player_y + 20) begin
                    enemy_hit_player[i] <= 1;  // 標記撞到玩家
                    enemy_active[i] <= 0;      // 敵人消失
                    if (health >= 8'd5) begin     // 確保生命值不會變成負數
                        health <= health - 8'd5;
                    end else begin
                        health <= 0;
                    end
                end
                else begin
                    enemy_x[i] <= enemy_x[i] + enemy_dx[i];
                
                    if ((enemy_dx[i] > 0 && enemy_x[i] > 660) ||
                        (enemy_dx[i] < 0 && enemy_x[i] < -20)) begin
                        enemy_active[i] <= 0;  // 離開螢幕
                    end
                end
            end
            // 第二部分：生成新敵人
            else begin  // 當敵人不活動時，嘗試生成新的
                if (!enemy_active[i] && LFSR[0]) begin
                    enemy_x[i] <= -20;
                    enemy_dx[i] <= ENEMY_SPEED;
                end else begin
                    enemy_x[i] <= 660;
                    enemy_dx[i] <= -ENEMY_SPEED;
                end
                enemy_y[i] <= (LFSR % 480) + 20;
                enemy_active[i] <= 1;
            end
        end
    end
end

// 射擊部隊的生成與移動邏輯
always @(posedge shooter_move_clk or posedge rst) begin
    if (rst) begin
        for (i = 0; i < MAX_SHOOTERS; i = i + 1) begin
            shooter_active[i] <= 0;
            shooter_x[i] <= 0;
            shooter_y[i] <= 0;
            shooter_dx[i] <= 0;
        end
    end else begin
        for (i = 0; i < MAX_SHOOTERS; i = i + 1) begin
            if (bullet_hit_shooter[i]) begin
                shooter_active[i] <= 0;  // 被子彈擊中
            end 
            else if (shooter_active[i]) begin
                // 更新射擊部隊位置
                shooter_x[i] <= shooter_x[i] + shooter_dx[i];
                
                // 檢查是否離開螢幕
                if ((shooter_dx[i] > 0 && shooter_x[i] > 660) ||
                    (shooter_dx[i] < 0 && shooter_x[i] < -20)) begin
                    shooter_active[i] <= 0;
                end
            end 
            else begin  // 生成新的射擊部隊
                if (!shooter_active[i] && LFSR[2:0] == 3'b111) begin  // 降低生成機率
                    if (LFSR[0]) begin
                        shooter_x[i] <= -20;
                        shooter_dx[i] <= ENEMY_SPEED;
                    end else begin
                        shooter_x[i] <= 660;
                        shooter_dx[i] <= -ENEMY_SPEED;
                    end
                    shooter_y[i] <= LFSR[3] ? 0 : 460;  // 只在頂端或底部生成
                    shooter_active[i] <= 1;
                end
            end
        end
    end
end

//=====================
//For Testing
//assign LED[5] = enemy_active[0];
//=====================

//============================================================
// 七段顯示器 (Score 與 搖桿座標切換)
// SW[0] = 0 顯示 Score
// SW[0] = 1, SW[1] = 1 顯示 x_bcd
// SW[0] = 1, SW[1] = 0 顯示 y_bcd
//============================================================
//wire [15:0] score_bcd = {4'hF,4'hF,score[7:4],score[3:0]};
/*wire [15:0] bcd = {health[7:4],health[3:0],score[7:4],score[3:0]};
wire [15:0] nums_to_display = (SW[0] == 1'b0) ? bcd :
                              (SW[1] == 1'b1) ? x_bcd : y_bcd;

SevenSegment m1(
    .display(display), 
    .digit(digit), 
    .nums(nums_to_display),
    .rst(rst), 
    .clk(clk)
);*/

// 將health和score組合成一個16位的nums
wire [15:0] game_status;
// 根據switch選擇顯示內容
wire [15:0] nums_to_display = (SW[0] == 1'b0) ? game_status :
                              (SW[1] == 1'b1) ? x_bcd : y_bcd;

// 當score改變時，我們需要更新最後兩位數字
// 例如，score = 12 時，最後兩位要顯示12
reg [3:0] score_tens;    // 分數的十位數
reg [3:0] score_ones;    // 分數的個位數


// 同樣地，處理health的十位和個位
reg [3:0] health_tens;   // 生命值的十位數
reg [3:0] health_ones;   // 生命值的個位數

always @(*) begin
    if (rst) begin
        health_tens <= 4'b0101;  // 初始值50的十位數
        health_ones <= 4'b0000;  // 初始值50的個位數
        score_tens <= 4'b000;
        score_ones <= 4'b000;
    end else begin
        health_tens <= health / 10;
        health_ones <= health % 10;
        score_tens <= score / 10;    // 取十位數
        score_ones <= score % 10;    // 取個位數
    end
end

// 最後組合成16位數字
assign game_status = {health_tens, health_ones, score_tens, score_ones};

SevenSegment m1(
    .display(display), 
    .digit(digit), 
    .nums(nums_to_display),
    .rst(rst), 
    .clk(clk)
);

//============================================================
// VGA 輸出
//============================================================
integer j,e;
wire start_pixel;
wire tu_menu_pixel;
wire tutorial_pixel;
wire win_pixel;

wire [16:0] menu_start_addr      = ((v_cnt >> 1) * 320) + (h_cnt >> 1);
wire [16:0] menu_tutorial_addr   = ((v_cnt >> 1) * 320) + (h_cnt >> 1);
wire [16:0] tutorial_screen_addr = ((v_cnt >> 1) * 320) + (h_cnt >> 1);
wire [16:0] win_addr             = ((v_cnt >> 1) * 320) + (h_cnt >> 1);

blk_mem_gen_0 menu_start (
    .clka(clk_25),
    .wea(1'b0),
    .addra((menu_start_addr < 76800) ? menu_start_addr : 17'd0),
    .dina(0),
    .douta(start_pixel)
);

blk_mem_gen_1 menu_tutorial (
    .clka(clk_25),
    .wea(1'b0),
    .addra((menu_tutorial_addr < 76800) ? menu_tutorial_addr : 17'd0),
    .dina(0),
    .douta(tu_menu_pixel)
);

blk_mem_gen_2 tutorial_screen (
    .clka(clk_25),
    .wea(1'b0),
    .addra((tutorial_screen_addr < 76800) ? tutorial_screen_addr : 17'd0),
    .dina(0),
    .douta(tutorial_pixel)
);

blk_mem_gen_3 win_image (
    .clka(clk_25),
    .wea(1'b0),
    .addra((win_addr < 76800) ? win_addr : 17'd0),
    .dina(0),
    .douta(win_pixel)
);

// VGA Rendering Logic
always @(*) begin
    // 先預設背景 = 黑
    vgaRed   = 4'h0;
    vgaGreen = 4'h0;
    vgaBlue  = 4'h0;

    // 確保只在有效掃描區域(640×480)內進行繪圖
    if (valid && (h_cnt < 640) && (v_cnt < 480)) begin
        case (current_state)

            //----------------------------------------
            // 狀態 1: MENU_IDLE
            //----------------------------------------
            MENU_IDLE: begin
                // 顯示不同圖片來對應選單 (Start / Tutorial)
                // 此處只會顯示被選到的圖片 (根據您原本程式的寫法)
                if (menu_start_addr < 76800 && menu_selected == 0) begin
                    // 若此像素在 BRAM 中為 1，顯示白色
                    if (start_pixel == 1'b1) begin
                        vgaRed   = 4'hF;
                        vgaGreen = 4'hF;
                        vgaBlue  = 4'hF;
                    end
                end
                else if (menu_tutorial_addr < 76800 && menu_selected == 1) begin
                    if (tu_menu_pixel == 1'b1) begin
                        vgaRed   = 4'hF;
                        vgaGreen = 4'hF;
                        vgaBlue  = 4'hF;
                    end
                end
            end

            //----------------------------------------
            // 狀態 2: MENU_TUTORIAL
            //----------------------------------------
            MENU_TUTORIAL: begin
                // 顯示 Tutorial 大圖
                if (tutorial_screen_addr < 76800) begin
                    if (tutorial_pixel == 1'b1) begin
                        vgaRed   = 4'hF;
                        vgaGreen = 4'hF;
                        vgaBlue  = 4'hF;
                    end
                end
            end

            //----------------------------------------
            // 狀態 3: GAME_RUNNING
            //----------------------------------------
            GAME_RUNNING: begin
                // 先保留背景 = 黑
                // 再依序判斷座標，畫 Player, Bullet, Enemies

                // 1) Player
                if ((v_cnt >= player_y) && (v_cnt < player_y + 20) &&
                    (h_cnt >= player_x) && (h_cnt < player_x + 20))
                begin
                    // 顯示紅色方塊
                    vgaRed = 4'hF; 
                end

                // 2) Bullet
                else if (bullet_active &&
                         (v_cnt >= bullet_y) && (v_cnt < bullet_y + 10) &&
                         (h_cnt >= bullet_x) && (h_cnt < bullet_x + 5))
                begin
                    // 顯示綠色子彈
                    vgaGreen = 4'hF;
                end

                // 3) Enemies
                else begin
                    // 預設先維持黑色
                    for (e = 0; e < MAX_ENEMIES; e = e + 1) begin
                        if (enemy_active[e] &&
                            (v_cnt >= enemy_y[e]) && (v_cnt < enemy_y[e] + 20) &&
                            (h_cnt >= enemy_x[e]) && (h_cnt < enemy_x[e] + 20))
                        begin
                            // 顯示藍色方塊
                            vgaBlue = 4'hF;
                        end
                    end
                end
            end

            //----------------------------------------
            // 狀態 4: GAME_OVER
            //----------------------------------------
            GAME_OVER: begin
                // 簡單以藍色區塊示意 Game Over 畫面
                if ((v_cnt >= 100) && (v_cnt < 200) &&
                    (h_cnt >= 100) && (h_cnt < 500))
                begin
                    vgaBlue = 4'hF;
                end
            end

            //----------------------------------------
            // 狀態 5: GAME_WIN
            //----------------------------------------
            GAME_WIN: begin
                if (win_addr < 76800) begin
                    if (win_pixel == 1'b1) begin
                        vgaRed   = 4'hF;
                        vgaGreen = 4'hF;
                        vgaBlue  = 4'hF;
                    end
                end
            end


            default: ; // 其他狀態預設黑
        endcase
    end
end


endmodule
