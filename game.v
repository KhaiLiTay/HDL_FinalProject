/*沒有什麼大問題
TODO：隨機生成多個敵人*/
module game_top(
    input wire clk,
    input wire rst,
    input wire MISO,
    input wire [2:0] SW,
    output wire MOSI,
    output wire SCLK,
    output wire SS,
    output reg [3:0] vgaRed,
    output reg [3:0] vgaGreen,
    output reg [3:0] vgaBlue,
    output wire hsync,
    output wire vsync,
    output wire [6:0] display,
    output wire [3:0] digit
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

// Data to be sent to PmodJSTK, lower two bits will turn on leds on PmodJSTK
assign sndData = {8'b100000, {SW[1], SW[2]}};

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
assign joystick_x_final = (x_bcd[15:12] * 1000) + (x_bcd[11:8] * 100) + (x_bcd[7:4] * 10) + x_bcd[3:0];
assign joystick_y_final = (y_bcd[15:12] * 1000) + (y_bcd[11:8] * 100) + (y_bcd[7:4] * 10) + y_bcd[3:0];

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

// Player and bullet positions
reg [9:0] player_x;
reg [9:0] player_y;
reg [9:0] bullet_x;
reg [9:0] bullet_y;
reg bullet_active;
reg signed [9:0] bullet_dx;
reg signed [9:0] bullet_dy;

// Enemy position and state

/*reg [9:0] enemy_x;
reg [9:0] enemy_y;
reg enemy_active;*/
reg bullet_hit;
// 最大敌人数
parameter MAX_ENEMIES = 10;

// 敌人位置和状态
reg [9:0] enemy_x[MAX_ENEMIES - 1:0];
reg [9:0] enemy_y[MAX_ENEMIES - 1:0];
reg enemy_active[MAX_ENEMIES - 1:0];

// 随机数生成器（伪随机数）
reg [9:0] random_seed;


reg signed [15:0] dx, dy; // 允许负值
reg [15:0] magnitude;

parameter CENTER_X = 512;  // 搖桿中心X座標
parameter CENTER_Y = 512;  // 搖桿中心Y座標
parameter DEAD_ZONE = 100; // 死區範圍
parameter MAX_BULLET_SPEED = 5; // 子彈最大速度

integer i;
reg [9:0] LFSR;

// Initialize player position at screen center
initial begin
    player_x = 320; // Center of 640 width
    player_y = 240; // Center of 480 height
    bullet_active = 0;
    bullet_dx = 0;
    bullet_dy = -1; // Default upward
    /*enemy_x = 100; // Initial position of enemy
    enemy_y = 100;
    enemy_active = 1;*/
    //random_seed = 10'b0101010101; // 初始随机种子
    for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
        enemy_x[i] = 0;
        enemy_y[i] = 0;
        enemy_active[i] = 0;
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
        /*enemy_active <= 1;
        enemy_x <= 100;
        enemy_y <= 100;*/
        bullet_hit <= 0;
        for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
            enemy_active[i] <= 0;
        end
        score <= 0; // Reset score
    end else if (joystick_button[0] && !bullet_active) begin  // 使用按鈕0觸發射擊
        /*bullet_active <= 1;
        bullet_x <= player_x + 10;  // 从玩家位置发射
        bullet_y <= player_y;
        bullet_hit <= 0;*/

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
        
        // 基於512為中心判斷方向
        /*if (joystick_x_final > 612) begin  // 向右
            bullet_dx <= 3;
            bullet_dy <= (joystick_y_final > 612) ? 3 : (joystick_y_final < 412) ? -3 : 0;
        end
        else if (joystick_x_final < 412) begin  // 向左
            bullet_dx <= -3;
            bullet_dy <= (joystick_y_final > 612) ? 3 : (joystick_y_final < 412) ? -3 : 0;
        end
        else begin  // x軸中立
            bullet_dx <= 0;
            bullet_dy <= (joystick_y_final > 612) ? 3 : (joystick_y_final < 412) ? -3 : 0;
        end*/
    end
    else if (bullet_active) begin  // 需要增加這部分
        if (bullet_x >= 5 && bullet_x <= 635 && bullet_y >= 5 && bullet_y <= 475) begin
            bullet_x <= bullet_x + bullet_dx;
            bullet_y <= bullet_y + bullet_dy;
        end else begin
            bullet_active <= 0;
        end

        // Enemy hit detection
        /*if (enemy_active &&
            bullet_x + 5 >= enemy_x && bullet_x < enemy_x + 20 &&
            bullet_y + 10 >= enemy_y && bullet_y < enemy_y + 20) begin
            enemy_active <= 0; // Enemy disappears when hit
            bullet_active <= 0; // Reset bullet
            bullet_hit <= 1;
        end*/
        for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
            if (enemy_active[i] &&
                bullet_x + 5 >= enemy_x[i] && bullet_x < enemy_x[i] + 20 &&
                bullet_y + 10 >= enemy_y[i] && bullet_y < enemy_y[i] + 20) begin
                enemy_active[i] <= 0; // 敌人消失
                bullet_active <= 0; // 子弹消失
                bullet_hit <= 1;
                if (score <= 8'd99) begin  // 確保分數不會超過99
                    score <= score + 1; // 每次得分加10
                end
            end
        end
    end
    else begin
        for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
            if (!enemy_active[i]) begin
                random_seed <= LFSR;
                enemy_x[i] <= random_seed % 640; // 随机x坐标
                enemy_y[i] <= random_seed % 480; // 随机y坐标
                enemy_active[i] <= 1;
                //break; // 每次只生成一个敌人
            end
        end
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
    if (valid) begin
        if (v_cnt >= player_y && v_cnt < player_y + 20 && h_cnt >= player_x && h_cnt < player_x + 20) begin
            vgaRed = 4'hF; // Player block in red
            vgaGreen = 4'h0;
            vgaBlue = 4'h0;
        end else if (bullet_active && v_cnt >= bullet_y && v_cnt < bullet_y + 10 && h_cnt >= bullet_x && h_cnt < bullet_x + 5) begin
            vgaRed = 4'h0;
            vgaGreen = 4'hF; // Bullet block in green
            vgaBlue = 4'h0;
        end /*else if (enemy_active && v_cnt >= enemy_y && v_cnt < enemy_y + 20 && h_cnt >= enemy_x && h_cnt < enemy_x + 20) begin
            vgaRed = 4'h0; // Enemy block in blue
            vgaGreen = 4'h0;
            vgaBlue = 4'hF;
        end*/
        else begin
            for (i = 0; i < MAX_ENEMIES; i = i + 1) begin
                if (enemy_active[i] && v_cnt >= enemy_y[i] && v_cnt < enemy_y[i] + 20 && h_cnt >= enemy_x[i] && h_cnt < enemy_x[i] + 20) begin
                    vgaBlue = 4'hF; // Enemy block in blue
                end
            end
        end 
    end else begin
        vgaRed = 4'h0;
        vgaGreen = 4'h0;
        vgaBlue = 4'h0;
    end
end

endmodule
