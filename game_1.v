module game_top(
    input wire clk,
    input wire rst,
    input wire MISO,
    input wire [2:0] SW,
    inout wire PS2_DATA,
    inout wire PS2_CLK,
	input wire BtnU,
    input wire BtnD,
    input wire BtnL,
    output reg [15:0] LED,
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

// 射击频率控制时钟
wire shooter_bullet_clk;
clock_divider #(.n(19)) clk_div_shooter_bullet(  // 可调整分频比例
    .clk(clk),
    .clk_div(shooter_bullet_clk)
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
// FSM States
//============================================================
parameter MENU_IDLE = 3'b000;
parameter MENU_TUTORIAL = 3'b001;
parameter GAME_RUNNING = 3'b010;
parameter GAME_OVER = 3'b011;
parameter GAME_WIN = 3'b100;
parameter GAME_PAUSE = 3'b101;
parameter GAME_LOSE = 3'b110;

reg [2:0] current_state, next_state;
reg [2:0] prev_state; // 儲存進入 PAUSE 前的狀態
reg [1:0] menu_selected; // 0: Start Game, 1: Tutorial

//============================================================
// 音樂與音效
//============================================================
wire [21:0] music_note_div;
wire [15:0] audio_in_left, audio_in_right; // 背景音樂音訊
wire [15:0] bullet_audio;    // 子彈音效
reg bullet_sound_trigger;    // 子彈音效觸發

reg BtnU_pulse, BtnD_pulse;
reg [3:0] vol_num;

// 新增音樂模式信號
reg [1:0] music_mode;

// 根據 FSM 狀態設定音樂模式
always @(*) begin
    case (current_state)
        MENU_IDLE: music_mode = 2'b00; // 一般背景音樂
        GAME_RUNNING: music_mode = 2'b00; // 一般背景音樂
        GAME_WIN: music_mode = 2'b01; // 勝利音樂
        GAME_LOSE: music_mode = 2'b10; // 輸掉音樂
        default: music_mode = 2'b00; // 默認為一般背景音樂
    endcase
end

// 背景音樂模組
// 修改背景音樂模組實例化
background_music bgm_inst (
    .clk(clk_1Hz),   
    .rst(rst),
    .mode(music_mode), // 新增音樂模式信號
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
// 按鈕功能控制邏輯
//============================================================
// 中間信號
reg BtnU_menu, BtnD_menu;       // 控制選單
reg BtnU_volume, BtnD_volume;   // 控制音量

always @(posedge clk or posedge rst) begin
    if (rst) begin
        BtnU_pulse <= 0;
        BtnD_pulse <= 0;
        BtnU_menu <= 0;
        BtnD_menu <= 0;
        BtnU_volume <= 0;
        BtnD_volume <= 0;
    end else begin
        // 儲存按鈕的狀態
        BtnU_pulse <= BtnU;
        BtnD_pulse <= BtnD;

        // 在不同狀態下分配按鈕功能
        if (current_state == MENU_IDLE) begin
            BtnU_menu <= BtnU && ~BtnU_pulse;   // 按下 BtnU 控制選單
            BtnD_menu <= BtnD && ~BtnD_pulse;   // 按下 BtnD 控制選單
            BtnU_volume <= 0;                  // 選單時不控制音量
            BtnD_volume <= 0;
        end else if (current_state == GAME_RUNNING) begin
            BtnU_menu <= 0;                    // 遊戲中不控制選單
            BtnD_menu <= 0;
            BtnU_volume <= BtnU && ~BtnU_pulse; // 按下 BtnU 增加音量
            BtnD_volume <= BtnD && ~BtnD_pulse; // 按下 BtnD 減少音量
        end else begin
            BtnU_menu <= 0;                    // 其他狀態禁用按鈕功能
            BtnD_menu <= 0;
            BtnU_volume <= 0;
            BtnD_volume <= 0;
        end
    end
end

//============================================================
// 音量調整邏輯
//============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        vol_num <= 4'b0011; // 預設音量
    end else if (current_state == GAME_RUNNING) begin
        if (BtnU_volume && vol_num < 5) vol_num <= vol_num + 1; // 音量增加
        if (BtnD_volume && vol_num > 1) vol_num <= vol_num - 1; // 音量減少
    end
end

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

// 在游戏参数部分添加射击部队子弹相关定义
parameter MAX_SHOOTER_BULLETS = 10;  // 每个射击部队最多可以有的子弹数
reg [9:0] shooter_bullet_x[MAX_SHOOTERS-1:0][MAX_SHOOTER_BULLETS-1:0];
reg [9:0] shooter_bullet_y[MAX_SHOOTERS-1:0][MAX_SHOOTER_BULLETS-1:0];
reg shooter_bullet_active[MAX_SHOOTERS-1:0][MAX_SHOOTER_BULLETS-1:0];
reg signed [4:0] shooter_bullet_dx[MAX_SHOOTERS-1:0][MAX_SHOOTER_BULLETS-1:0];
reg signed [4:0] shooter_bullet_dy[MAX_SHOOTERS-1:0][MAX_SHOOTER_BULLETS-1:0];
// 在遊戲參數部分添加
reg [4:0] bullet_speed;
parameter BULLET_BASE_SPEED = 5;  // 基礎子彈速度

reg [7:0] score;

reg [7:0] health;  // 7-bit 可以表示 0-127，足夠表示 50
// 新增中間信號來處理來自不同來源的生命值減少
reg [7:0] enemy_damage;      // 敵人造成的傷害
reg [7:0] bullet_damage;     // 子彈造成的傷害
reg enemy_hit, bullet_hit_player;
// 修改射擊部隊的射擊機制
reg [7:0] shoot_timer [MAX_SHOOTERS-1:0];  // 每個射擊部隊的計時器

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

integer i,j;
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
    for (i = 0; i < MAX_SHOOTERS; i = i + 1) begin
        for (j = 0; j < MAX_SHOOTER_BULLETS; j = j + 1) begin
            shooter_bullet_active[i][j] = 0;
            shooter_bullet_x[i][j] = 0;
            shooter_bullet_y[i][j] = 0;
            shooter_bullet_dx[i][j] = 0;
            shooter_bullet_dy[i][j] = 0;
        end
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
            else if (BtnL) next_state = MENU_IDLE;         // 按下 BtnL 回到選單
            else next_state = MENU_TUTORIAL;
        end

        GAME_RUNNING: begin
            if (SW[0]) begin
                next_state = GAME_PAUSE; // SW[0] 觸發 PAUSE 狀態
            end else if (score >= 10) begin
                next_state = GAME_WIN; // 分數達到 10，切換到 WIN
            end else if (health == 0) begin // 當生命值為0時觸發LOSE
                next_state = GAME_LOSE;
            end else begin
                next_state = GAME_RUNNING;
            end
        end

        GAME_OVER: begin
            if (joystick_button[2]) next_state = MENU_IDLE;
            else next_state = GAME_OVER;
        end

        GAME_WIN: begin
            if (joystick_button[2]) next_state = MENU_IDLE; // 回到主選單
            else next_state = GAME_WIN;
        end
        
        GAME_LOSE: begin // LOSE狀態
            if (joystick_button[2]) next_state = MENU_IDLE; // 按按鈕返回主選單
            else next_state = GAME_LOSE;
        end

        GAME_PAUSE: begin // 新增的 PAUSE 狀態邏輯
            if (~SW[0]) begin // 關閉 SW[0]，回到之前的狀態
                next_state = prev_state;
            end else begin
                next_state = GAME_PAUSE;
            end
        end

        default: next_state = MENU_IDLE;
    endcase
end

//============================================================
// 儲存進入 PAUSE 前的狀態
//============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        prev_state <= MENU_IDLE;
    end else if (current_state != GAME_PAUSE && next_state == GAME_PAUSE) begin
        prev_state <= current_state; // 進入 PAUSE 前儲存當前狀態
    end
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
    end else if (current_state == MENU_TUTORIAL && BtnL) begin
        menu_selected <= 1; // 按下 BtnL 時將選項設為 1
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
            bullet_hit_enemy <= 0;
            bullet_hit_shooter <= 0;
        end 
        // 此处改为条件性重置击中标记
        if (bullet_active) begin  // 当子弹不活跃时重置击中标记
            bullet_hit_enemy <= 0;
            bullet_hit_shooter <= 0;
        end

        if (joystick_button[0] && !bullet_active && !shift_down) begin
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
                    if (score < 8'd99) score <= score + 1; // 達到 10 分會進入 WIN 狀態
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
        enemy_hit_player <= 0;
    end else if (current_state == GAME_RUNNING) begin
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
                    enemy_hit <= 1;
                    //health <= health - 5; //multiple driver
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
    end else if (current_state == GAME_RUNNING) begin
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

// 添加固定点数除法函数
function [4:0] fixed_point_div;
    input [31:0] dx, dy;
    reg [31:0] abs_dx, abs_dy;
    begin
        // 计算绝对值
        abs_dx = (dx[31]) ? -dx : dx;
        abs_dy = (dy[31]) ? -dy : dy;
        
        // 使用预先计算的比例
        if (abs_dx > abs_dy) begin
            fixed_point_div = 5'd5; // 最大速度
        end else if (abs_dx == abs_dy) begin
            fixed_point_div = 5'd4; // 对角线速度
        end else begin
            fixed_point_div = 5'd3; // 较小速度
        end
    end
endfunction

// 修改射擊部隊子彈生成的邏輯
always @(posedge shooter_bullet_clk or posedge rst) begin
    if (rst) begin
        for (i = 0; i < MAX_SHOOTERS; i = i + 1) begin
            shoot_timer[i] <= 0;
            for (j = 0; j < MAX_SHOOTER_BULLETS; j = j + 1) begin
                shooter_bullet_active[i][j] <= 0;
                shooter_bullet_x[i][j] <= 0;
                shooter_bullet_y[i][j] <= 0;
                shooter_bullet_dx[i][j] <= 0;
                shooter_bullet_dy[i][j] <= 0;
            end
        end
    end else if (current_state == GAME_RUNNING) begin
        // 每個活躍的射擊部隊都嘗試發射子彈
        for (i = 0; i < MAX_SHOOTERS; i = i + 1) begin
            if (shooter_active[i]) begin
                // 增加計時器
                shoot_timer[i] <= shoot_timer[i] + 1;
                
                // 每隔一定時間發射子彈（可調整間隔）
                if (shoot_timer[i] >= 8'd20) begin  // 調整這個數值可以改變射擊頻率
                    shoot_timer[i] <= 0;  // 重置計時器

                    // 尋找空閒的子彈槽
                    for (j = 0; j < MAX_SHOOTER_BULLETS; j = j + 1) begin
                        if (!shooter_bullet_active[i][j]) begin
                            // 發射新子彈
                            shooter_bullet_active[i][j] <= 1;
                            shooter_bullet_x[i][j] <= shooter_x[i] + 10;
                            shooter_bullet_y[i][j] <= shooter_y[i] + 10;

                            // 計算目標方向（瞄準玩家當前位置）
                            dx = $signed(player_x - shooter_x[i]);
                            dy = $signed(player_y - shooter_y[i]);

                            // 计算速度分量（参考玩家子弹逻辑）
                            magnitude = (dx*dx + dy*dy) >> 8;
                            
                            if (magnitude > 0) begin
                                shooter_bullet_active[i][j] <= 1;
                                shooter_bullet_x[i][j] <= shooter_x[i] + 10;
                                shooter_bullet_y[i][j] <= shooter_y[i] + 10;

                                // 设置速度分量
                                if (dx > 0)
                                    shooter_bullet_dx[i][j] <= (dx * 5) >> 9;
                                else
                                    shooter_bullet_dx[i][j] <= -(-dx * 5) >> 9;
                                
                                if (dy > 0)
                                    shooter_bullet_dy[i][j] <= (dy * 5) >> 9;
                                else
                                    shooter_bullet_dy[i][j] <= -(-dy * 5) >> 9;
                            end
                        end
                    end
                end
            end else begin
                shoot_timer[i] <= 0;  // 重置非活躍射擊部隊的計時器
            end
        end

        // 更新所有活躍子彈的位置
        for (i = 0; i < MAX_SHOOTERS; i = i + 1) begin
            for (j = 0; j < MAX_SHOOTER_BULLETS; j = j + 1) begin
                if (shooter_bullet_active[i][j]) begin
                    // 移動子彈（線性路徑）
                    shooter_bullet_x[i][j] <= shooter_bullet_x[i][j] + shooter_bullet_dx[i][j];
                    shooter_bullet_y[i][j] <= shooter_bullet_y[i][j] + shooter_bullet_dy[i][j];

                    // 檢查是否擊中玩家
                    if (shooter_bullet_x[i][j] + 5 >= player_x && 
                        shooter_bullet_x[i][j] < player_x + 20 &&
                        shooter_bullet_y[i][j] + 5 >= player_y && 
                        shooter_bullet_y[i][j] < player_y + 20) begin
                        shooter_bullet_active[i][j] <= 0;
                        health <= health - 2;
                    end
                    // 檢查是否離開螢幕
                    else if (shooter_bullet_x[i][j] < 5 || shooter_bullet_x[i][j] > 635 ||
                            shooter_bullet_y[i][j] < 5 || shooter_bullet_y[i][j] > 475) begin
                        shooter_bullet_active[i][j] <= 0;
                    end
                end
            end
        end
    end
end

//============================================================
// LED控制整合邏輯
//============================================================
// LED 閃爍控制
reg [1:0] blink_state; // 0: 全暗, 1: 全亮
reg [3:0] blink_count; // 閃爍計數器 (0~6)
reg blink_enable;      // 啟用閃爍控制
reg [15:0] led_next;   // LED 中間信號

always @(posedge clk_1Hz or posedge rst) begin
    if (rst) begin
        blink_state <= 0;       // 預設全暗
        blink_count <= 0;       // 重置閃爍計數
        blink_enable <= 0;      // 停止閃爍
        led_next <= 16'b0000_0000_0000_0000; // 全暗
    end else if (current_state == GAME_WIN) begin
        // GAME_WIN 狀態下執行 LED 閃爍
        if (!blink_enable) begin
            blink_enable <= 1;  // 啟用閃爍
            blink_count <= 0;   // 重置計數
        end else if (blink_count < 6) begin
            // 控制 LED 全亮或全暗 (每次閃爍切換一次)
            if (blink_state == 0) begin
                led_next <= 16'b1111_1111_1111_1111; // 全亮
                blink_state <= 1;
            end else begin
                led_next <= 16'b0000_0000_0000_0000; // 全暗
                blink_state <= 0;
                blink_count <= blink_count + 1; // 增加閃爍計數
            end
        end else begin
            // 閃爍完成，關閉 LED
            led_next <= 16'b0000_0000_0000_0000;    // 全暗
            blink_enable <= 0;  // 停止閃爍
        end
    end else if (current_state == GAME_RUNNING || current_state == GAME_PAUSE) begin
        // GAME_RUNNING 狀態下顯示音量
        case (vol_num)
            1: led_next <= 16'b0000_0000_0000_0001;
            2: led_next <= 16'b0000_0000_0000_0011;
            3: led_next <= 16'b0000_0000_0000_0111;
            4: led_next <= 16'b0000_0000_0000_1111;
            5: led_next <= 16'b0000_0000_0001_1111;
            default: led_next <= 16'b0000_0000_0000_0000;
        endcase
    end else begin
        // 其他狀態下，保持 LED 全暗
        led_next <= 16'b0000_0000_0000_0000;
        blink_enable <= 0;
    end
end

// 實際 LED 賦值邏輯
always @(posedge clk or posedge rst) begin
    if (rst) begin
        LED <= 16'b0000_0000_0000_0000;
    end else begin
        LED <= led_next;
    end
end


//============================================================
// 七段顯示器 (Score)
//============================================================;

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
        score_tens <= 4'b0000;
        score_ones <= 4'b0000;
    end else begin
        health_tens <= health / 10;
        health_ones <= health % 10;
        score_tens <= score / 10;    // 取十位數
        score_ones <= score % 10;    // 取個位數
    end
end

// 最後組合成16位數字
reg [15:0] game_status;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        game_status <= 16'h5000;  // 初始值
    end else begin
        game_status <= {health_tens, health_ones, score_tens, score_ones};
    end
end

reg [15:0] nums_to_display;

// 狀態切換時的顯示邏輯
always @(*) begin
    case (current_state)
        MENU_IDLE: nums_to_display <= 16'hFFFF;       // ----
        MENU_TUTORIAL: nums_to_display <= 16'hFFFF;   // ----
        GAME_RUNNING: nums_to_display <= game_status; // 顯示 health 和 score
        GAME_OVER: nums_to_display <= 16'hFFFF;       // ----
        GAME_WIN: nums_to_display <= {4'hF, 4'hA, 4'hB, 4'hC}; // WIN
        GAME_PAUSE: nums_to_display <= game_status;   // 顯示 health 和 score
        GAME_LOSE: nums_to_display <= {4'hD, 4'h0, 4'h5, 4'hE}; // LOSE
        default: nums_to_display <= 16'hFFFF;         // 預設為 ----
    endcase
end

SevenSegment m1(
    .display(display), 
    .digit(digit), 
    .nums(nums_to_display),
    .rst(rst), 
    .clk(clk)
);

//============================================================
// VGA Output Logic with Full RGB Pixel Data
//============================================================

integer e, p;

//================================================================
// (1) Define Scaling Factors
//================================================================
localparam SCALE_FACTOR = 4;       // Scaling factor (x4)
localparam IMG_W = 160;            // Original image width
localparam IMG_H = 120;            // Original image height
localparam SCALED_IMG_W = IMG_W * SCALE_FACTOR; // Scaled image width
localparam SCALED_IMG_H = IMG_H * SCALE_FACTOR; // Scaled image height

//================================================================
// (2) BRAM Interface Signals
//================================================================
reg  [16:0] image_pixel_addr;     // Address for BRAM
reg  [16:0] base_offset;          // Offset for each image
wire [11:0] pixel;                // 12-bit RGB pixel data from BRAM

//================================================================
// (3) Define Image Offsets
//================================================================
localparam IMG1_OFFSET = 17'd0;       // Image 1
localparam IMG2_OFFSET = 17'd19200;   // Image 2
localparam IMG3_OFFSET = 17'd38400;   // Image 3
localparam IMG4_OFFSET = 17'd57600;   // Image 4
localparam IMG5_OFFSET = 17'd76800;   // Image 5
localparam IMG6_OFFSET = 17'd96000;   // Image 6

//================================================================
// (4) Instantiate BRAM
//================================================================
blk_mem_gen_0 u_image_bram (
    .clka(clk_25),
    .wea(1'b0),
    .addra(image_pixel_addr),
    .dina(12'b0), // Initialize with zeros
    .douta(pixel) // 12-bit RGB output
);

//================================================================
// (5) Set Base Offset Based on State
//================================================================
always @(*) begin
    case (current_state)
        MENU_IDLE: base_offset = (menu_selected == 0) ? IMG1_OFFSET : IMG2_OFFSET;
        MENU_TUTORIAL: base_offset = IMG3_OFFSET;
        GAME_RUNNING: base_offset = 17'd0; // No image
        GAME_OVER: base_offset = 17'd0;    // No image
        GAME_WIN: base_offset = IMG4_OFFSET;
        GAME_PAUSE: base_offset = IMG5_OFFSET;
        GAME_LOSE: base_offset = IMG6_OFFSET;
        default: base_offset = 17'd0;
    endcase
end

//================================================================
// (6) Calculate BRAM Address for Pixel Data
//================================================================
always @(*) begin
    if (valid && (h_cnt < SCALED_IMG_W) && (v_cnt < SCALED_IMG_H)) begin
        // Calculate address based on scaled VGA coordinates
        image_pixel_addr = base_offset + 
                           ((v_cnt / SCALE_FACTOR) * IMG_W) + 
                           (h_cnt / SCALE_FACTOR);
    end else begin
        // Default address for out-of-range pixels
        image_pixel_addr = 17'd0;
    end
end

//================================================================
// (7) VGA Rendering Logic
//================================================================
always @(*) begin
    // Default background = black
    vgaRed   = 4'h0;
    vgaGreen = 4'h0;
    vgaBlue  = 4'h0;

    // Render within valid scan area
    if (valid && (h_cnt < 640) && (v_cnt < 480)) begin
        case (current_state)
            MENU_IDLE, MENU_TUTORIAL, GAME_WIN, GAME_PAUSE, GAME_LOSE: begin
                // Assign full RGB pixel data to VGA output
                {vgaRed, vgaGreen, vgaBlue} = pixel;
            end
            GAME_RUNNING: begin
                // Player
                if ((v_cnt >= player_y) && (v_cnt < player_y + 20) &&
                    (h_cnt >= player_x) && (h_cnt < player_x + 20)) begin
                    vgaRed = 4'hF; // Red for player
                end
                // Bullet
                else if (bullet_active &&
                         (v_cnt >= bullet_y) && (v_cnt < bullet_y + 10) &&
                         (h_cnt >= bullet_x) && (h_cnt < bullet_x + 5)) begin
                    vgaGreen = 4'hF; // Green for bullet
                end
                // Enemies
                else begin
                    for (e = 0; e < MAX_SHOOTERS; e = e + 1) begin
                        for (j = 0; j < MAX_SHOOTER_BULLETS; j = j + 1) begin
                            if (shooter_bullet_active[e][j] &&
                                v_cnt >= shooter_bullet_y[e][j] && v_cnt < shooter_bullet_y[e][j] + 5 &&
                                h_cnt >= shooter_bullet_x[e][j] && h_cnt < shooter_bullet_x[e][j] + 5) begin
                                vgaRed = 4'hF; // Yellow bullet = Red + Green
                                vgaGreen = 4'hF;
                                vgaBlue = 4'h0;
                            end
                        end
                    end
                    for (e = 0; e < MAX_ENEMIES; e = e + 1) begin
                        if (enemy_active[e] &&
                            (v_cnt >= enemy_y[e]) && (v_cnt < enemy_y[e] + 20) &&
                            (h_cnt >= enemy_x[e]) && (h_cnt < enemy_x[e] + 20)) begin
                            vgaBlue = 4'hF; // Blue for enemies
                        end
                    end
                    for (e = 0; e < MAX_SHOOTERS; e = e + 1) begin
                        if (shooter_active[e] &&
                            (v_cnt >= shooter_y[e]) && (v_cnt < shooter_y[e] + 20) &&
                            (h_cnt >= shooter_x[e]) && (h_cnt < shooter_x[e] + 20)) begin
                            vgaRed = 4'hF;    // Orange = Red + Green
                            vgaGreen = 4'h8;
                        end
                    end
                end
            end
            GAME_OVER: begin
                if ((v_cnt >= 100) && (v_cnt < 200) &&
                    (h_cnt >= 100) && (h_cnt < 500)) begin
                    vgaBlue = 4'hF; // Blue block for Game Over
                end
            end
            default: ; // Keep black for other states
        endcase
    end
end

endmodule
