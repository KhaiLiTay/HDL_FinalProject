/*沒有什麼大問題
TODO：隨機生成多個敵人*/
module game_top(
    input wire clk,
    input wire rst,
    input wire MISO,
    input wire [2:0] SW,
    inout wire PS2_DATA,
    inout wire PS2_CLK,
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
// 從PmodJSTK文档中可以看到，搖杆数据格式如下：
wire [9:0] joystick_x = {joystick_data[9:8], joystick_data[23:16]};
wire [9:0] joystick_y = {joystick_data[25:24], joystick_data[39:32]};
// 從示例代碼可看到按鈕的處理方式
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


wire joystick_num;
assign joystick_num = (SW[0] == 1'b1) ? {x_bcd} : {y_bcd};
SevenSegment m1(.display(display), .digit(digit), .nums(joystick_num), .rst(rst), .clk(clk));

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
reg [9:0] enemy_x;
reg [9:0] enemy_y;
reg enemy_active;
reg bullet_hit;

reg signed [15:0] dx, dy; // 允許負值
reg [15:0] magnitude;

parameter CENTER_X = 512;  // 搖杆中心X座標
parameter CENTER_Y = 512;  // 搖杆中心Y座標
parameter DEAD_ZONE = 100; // 死區範圍
parameter MAX_BULLET_SPEED = 5; // 子彈最大速度

// Keyboard interface
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
parameter [8:0] KEY_W = 9'b0_0001_1101; // W key
parameter [8:0] KEY_A = 9'b0_0001_1100; // A key
parameter [8:0] KEY_S = 9'b0_0001_1011; // S key
parameter [8:0] KEY_D = 9'b0_0010_0011; // D key

// Game mode controlled by holding SHIFT key
wire shift_down = key_down[9'b0_0001_0010] | key_down[9'b0_0101_1001];

// Initialize player position at screen center
initial begin
    player_x = 320; // Center of 640 width
    player_y = 240; // Center of 480 height
    bullet_active = 0;
    bullet_dx = 0;
    bullet_dy = -1; // Default upward
    enemy_x = 100; // Initial position of enemy
    enemy_y = 100;
    enemy_active = 1;
end

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
    end else if (shift_down) begin
        // Shift key pressed: control player movement with joystick
        if (joystick_x_final > 0 && joystick_x_final < 1023) begin
            player_x <= player_x + (joystick_x_final * 640) >> 10;
        end
        if (joystick_y_final > 0 && joystick_y_final < 1023) begin
            player_y <= player_y + (joystick_y_final * 480) >> 10;
        end
    end else begin
        if (!prev_key_w && key_down[KEY_W] && player_y > 5) begin
            player_y <= player_y - 5;
        end
        if (!prev_key_s && key_down[KEY_S] && player_y < 475) begin
            player_y <= player_y + 5;
        end
        if (!prev_key_a && key_down[KEY_A] && player_x > 5) begin
            player_x <= player_x - 5;
        end
        if (!prev_key_d && key_down[KEY_D] && player_x < 635) begin
            player_x <= player_x + 5;
        end

        prev_key_w <= key_down[KEY_W];
        prev_key_a <= key_down[KEY_A];
        prev_key_s <= key_down[KEY_S];
        prev_key_d <= key_down[KEY_D];
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
        enemy_active <= 1;
        enemy_x <= 100;
        enemy_y <= 100;
        bullet_hit <= 0;
    end else if (joystick_button[0] && !bullet_active && !shift_down) begin
        // Shift not pressed: control bullet direction
        dx = $signed(joystick_x_final) - $signed(CENTER_X);
        dy = $signed(joystick_y_final) - $signed(CENTER_Y);
        magnitude = (dx * dx + dy * dy) >> 8; // 除以256作為縮旺因子
        if (magnitude > DEAD_ZONE * DEAD_ZONE >> 8) begin
            bullet_active <= 1;
            bullet_x <= player_x + 10;
            bullet_y <= player_y;
            bullet_hit <= 0;
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
    end else if (bullet_active) begin
        if (bullet_x >= 5 && bullet_x <= 635 && bullet_y >= 5 && bullet_y <= 475) begin
            bullet_x <= bullet_x + bullet_dx;
            bullet_y <= bullet_y + bullet_dy;
        end else begin
            bullet_active <= 0;
        end
        if (enemy_active &&
            bullet_x + 5 >= enemy_x && bullet_x < enemy_x + 20 &&
            bullet_y + 10 >= enemy_y && bullet_y < enemy_y + 20) begin
            enemy_active <= 0; // Enemy disappears when hit
            bullet_active <= 0; // Reset bullet
            bullet_hit <= 1;
        end
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
        end else if (enemy_active && v_cnt >= enemy_y && v_cnt < enemy_y + 20 && h_cnt >= enemy_x && h_cnt < enemy_x + 20) begin
            vgaRed = 4'h0; // Enemy block in blue
            vgaGreen = 4'h0;
            vgaBlue = 4'hF;
        end else begin
            vgaRed = 4'h0;
            vgaGreen = 4'h0;
            vgaBlue = 4'h0;
        end
    end else begin
        vgaRed = 4'h0;
        vgaGreen = 4'h0;
        vgaBlue = 4'h0;
    end
end

endmodule