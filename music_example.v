module background_music(
    input wire clk,          // 系統時鐘
    input wire rst,          // 重置信號
    output reg [21:0] note_div // 輸出當前音符的分頻值
);
    reg [2:0] note_index;    // 音階索引
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            note_index <= 3'b000; // 從 do 開始
        end else begin
            note_index <= (note_index == 3'b110) ? 3'b000 : note_index + 1'b1; // 循環 do 到 si
        end
    end

    // 根據索引選擇對應音階的分頻值
    always @(*) begin
        case (note_index)
            3'b000: note_div = 22'd191571; // do
            3'b001: note_div = 22'd170068; // re
            3'b010: note_div = 22'd151515; // mi
            3'b011: note_div = 22'd142857; // fa
            3'b100: note_div = 22'd127551; // so
            3'b101: note_div = 22'd113636; // la
            3'b110: note_div = 22'd101214; // si
            default: note_div = 22'd0;     // 無音
        endcase
    end
endmodule

module bullet_sound(
    input wire clk,            // 系統時鐘
    input wire rst,            // 重置信號
    input wire trigger,        // 音效觸發信號
    output reg [15:0] audio    // 音效輸出
);
    reg [21:0] clk_cnt;        // 時鐘計數器
    reg [21:0] note_div;       // 當前音符分頻值
    reg active;                // 音效是否啟動
    reg [31:0] duration_cnt;   // 音效持續時間計數器

    // 設定比 si 更高的頻率（如高音 do）
    localparam HIGH_FREQ = 22'd90000;   // 90kHz 高音
    localparam DURATION = 32'd5000000; // 1秒持續時間 (50MHz 時鐘)

    // 初始化參數
    initial begin
        note_div = HIGH_FREQ;   // 預設為高音
        active = 0;
        audio = 0;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            active <= 0;
            duration_cnt <= 0;
            clk_cnt <= 0;
            audio <= 0;
        end else if (trigger && !active) begin
            active <= 1;               // 啟動音效
            duration_cnt <= DURATION; // 設定音效持續時間
        end else if (active) begin
            if (duration_cnt == 0) begin
                active <= 0;           // 停止音效
                audio <= 0;            // 靜音
            end else begin
                duration_cnt <= duration_cnt - 1;

                // 生成方波音頻信號
                if (clk_cnt == note_div) begin
                    clk_cnt <= 0;
                    audio <= ~audio;   // 方波信號翻轉
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end
        end else begin
            audio <= 0;                // 無音效時保持靜音
        end
    end
endmodule

module audio_mixer(
    input wire [15:0] bgm_audio,   // 背景音樂
    input wire [15:0] sfx_audio,  // 子彈音效
    output wire [15:0] mixed_audio // 混合音頻
);
    assign mixed_audio = (sfx_audio != 16'h0000) ? sfx_audio : bgm_audio;

endmodule
