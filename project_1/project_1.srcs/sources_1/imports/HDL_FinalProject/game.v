/*1. 搖桿實際控制的是player位置，即player會隨著搖桿被控製的在銀幕上移動
2. 按下搖桿後，確實會射出子彈，但看起來目前邏輯是銀幕上只能有一顆子彈，而且移動速度太慢*/
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

// Initialize player position at screen center
initial begin
    player_x = 320; // Center of 640 width
    player_y = 240; // Center of 480 height
    bullet_active = 0;
    bullet_dx = 0;
    bullet_dy = -1; // Default upward
end

// Update player position based on joystick input
always @(posedge clk_25 or posedge rst) begin
    if (rst) begin
        player_x <= 320;
        player_y <= 240;
    end else begin
        // Map joystick_x and joystick_y range (0-1023) to screen dimensions (0-639, 0-479)
        player_x <= (joystick_x_final * 640) >> 10;
        player_y <= (joystick_y_final * 480) >> 10;
    end
end

// Bullet generation and movement
always @(posedge clk_1Hz or posedge rst) begin
    if (rst) begin
        bullet_active <= 0;
        bullet_x <= 0;
        bullet_y <= 0;
        bullet_dx <= 0;
        bullet_dy <= 0;
    end else if (joystick_button[0] && !bullet_active) begin  // 使用按鈕0觸發射擊
        bullet_active <= 1;
        bullet_x <= player_x + 10;  // 從玩家位置發射
        bullet_y <= player_y;
        
        // 基於512為中心判斷方向
        if (joystick_x_final > 612) begin  // 向右
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
        end
    end
    else if (bullet_active) begin  // 需要增加這部分
        if (bullet_x >= 5 && bullet_x <= 635 && bullet_y >= 5 && bullet_y <= 475) begin
            bullet_x <= bullet_x + bullet_dx;
            bullet_y <= bullet_y + bullet_dy;
        end else begin
            bullet_active <= 0;
        end
    end
end

// VGA output for player and bullet
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
