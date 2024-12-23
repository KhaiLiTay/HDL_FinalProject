module background_music(
    input wire clk,          // 系統時鐘
    input wire rst,          // 重置信號
    input wire [1:0] mode,   // 音樂模式: 00=一般, 01=勝利, 10=輸掉
    output reg [21:0] note_div // 音符分頻值
);
 
    reg [4:0] note_index;    // 音階索引
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            note_index <= 3'b00000; // 從第一顆音開始
        end else begin
            note_index <= (note_index == 5'd31) ? 5'b00000 : note_index + 1'b1; // 循環播放
        end
    end

    // 根據模式和索引輸出對應旋律
    always @(*) begin
        case (mode)
            2'b00: begin // 一般狀態音樂
                case (note_index)
                    // 第一小節
                    5'd0: note_div = 22'd127551; // so
                    5'd1: note_div = 22'd113636; // la
                    5'd2: note_div = 22'd127551; // so
                    5'd3: note_div = 22'd142857; // fa
                    // 第二小節
                    5'd4: note_div = 22'd151515; // mi
                    5'd5: note_div = 22'd142857; // fa
                    5'd6: note_div = 22'd127551; // so
                    5'd7: note_div = 22'd127551; // so
                    // 第三小節
                    5'd8: note_div = 22'd170068; // re
                    5'd9: note_div = 22'd151515; // mi
                    5'd10: note_div = 22'd142857; // fa
                    5'd11: note_div = 22'd142857; // fa
                    // 第四小節
                    5'd12: note_div = 22'd151515; // mi
                    5'd13: note_div = 22'd142857; // fa
                    5'd14: note_div = 22'd127551; // so
                    5'd15: note_div = 22'd127551; // so
                    // 第五小節
                    5'd16: note_div = 22'd127551; // so
                    5'd17: note_div = 22'd113636; // la
                    5'd18: note_div = 22'd127551; // so
                    5'd19: note_div = 22'd142857; // fa
                    // 第六小節
                    5'd20: note_div = 22'd151515; // mi
                    5'd21: note_div = 22'd142857; // fa
                    5'd22: note_div = 22'd127551; // so
                    5'd23: note_div = 22'd127551; // so
                    // 第七小節
                    5'd24: note_div = 22'd170068; // re
                    5'd25: note_div = 22'd170068; // re
                    5'd26: note_div = 22'd127551; // so
                    5'd27: note_div = 22'd127551; // so
                    // 第八小節
                    5'd28: note_div = 22'd151515; // mi
                    5'd29: note_div = 22'd191571; // do
                    5'd30: note_div = 22'd191571; // do
                    5'd31: note_div = 22'd191571; // do
                    default: note_div = 22'd0;
                endcase
            end
            2'b01: begin // 勝利音樂
                case (note_index)
                    // 第一小節
                    5'd0: note_div = 22'd151515; // mi
                    5'd1: note_div = 22'd151515; // mi
                    5'd2: note_div = 22'd142857; // fa
                    5'd3: note_div = 22'd127551; // so
                    // 第二小節
                    5'd4: note_div = 22'd127551; // so
                    5'd5: note_div = 22'd142857; // fa
                    5'd6: note_div = 22'd151515; // mi
                    5'd7: note_div = 22'd170068; // re
                    // 第三小節
                    5'd8: note_div = 22'd191571; // do
                    5'd9: note_div = 22'd191571; // do
                    5'd10: note_div = 22'd170068; // re
                    5'd11: note_div = 22'd151515; // mi
                    // 第四小節
                    5'd12: note_div = 22'd151515; // mi
                    5'd13: note_div = 22'd151515; // mi
                    5'd14: note_div = 22'd170068; // re
                    5'd15: note_div = 22'd170068; // re
                    // 第五小節
                    5'd16: note_div = 22'd151515; // mi
                    5'd17: note_div = 22'd151515; // mi
                    5'd18: note_div = 22'd142857; // fa
                    5'd19: note_div = 22'd127551; // so
                    // 第六小節
                    5'd20: note_div = 22'd127551; // so
                    5'd21: note_div = 22'd142857; // fa
                    5'd22: note_div = 22'd151515; // mi
                    5'd23: note_div = 22'd170068; // re
                    // 第七小節
                    5'd24: note_div = 22'd191571; // do
                    5'd25: note_div = 22'd191571; // do
                    5'd26: note_div = 22'd170068; // re
                    5'd27: note_div = 22'd151515; // mi
                    // 第八小節
                    5'd28: note_div = 22'd170068; // re
                    5'd29: note_div = 22'd170068; // re
                    5'd30: note_div = 22'd191571; // do
                    5'd31: note_div = 22'd191571; // do
                    default: note_div = 22'd0;
            endcase
        end
            2'b10: begin // 輸掉音樂
                case (note_index)
                    // 第一小節
                    5'd0: note_div = 22'd151515; // mi
                    5'd1: note_div = 22'd170068; // re
                    5'd2: note_div = 22'd191571; // do
                    5'd3: note_div = 22'd191571; // do
                    // 第二小節
                    5'd4: note_div = 22'd170068; // re
                    5'd5: note_div = 22'd151515; // mi
                    5'd6: note_div = 22'd142857; // fa
                    5'd7: note_div = 22'd127551; // so
                    // 第三小節
                    5'd8: note_div = 22'd151515; // mi
                    5'd9: note_div = 22'd142857; // fa
                    5'd10: note_div = 22'd127551; // so
                    5'd11: note_div = 22'd142857; // fa
                    // 第四小節
                    5'd12: note_div = 22'd170068; // re
                    5'd13: note_div = 22'd151515; // mi
                    5'd14: note_div = 22'd191571; // do
                    5'd15: note_div = 22'd191571; // do
                    // 第五小節
                    5'd16: note_div = 22'd151515; // mi
                    5'd17: note_div = 22'd170068; // re
                    5'd18: note_div = 22'd191571; // do
                    5'd19: note_div = 22'd191571; // do
                    // 第六小節
                    5'd20: note_div = 22'd170068; // re
                    5'd21: note_div = 22'd151515; // mi
                    5'd22: note_div = 22'd142857; // fa
                    5'd23: note_div = 22'd151515; // mi
                    // 第七小節
                    5'd24: note_div = 22'd170068; // re
                    5'd25: note_div = 22'd191571; // do
                    5'd26: note_div = 22'd101214; // ti
                    5'd27: note_div = 22'd113636; // la
                    // 第八小節
                    5'd28: note_div = 22'd191571; // do
                    5'd29: note_div = 22'd170068; // re
                    5'd30: note_div = 22'd151515; // mi
                    5'd31: note_div = 22'd191571; // do
                    default: note_div = 22'd0; // 停頓
                endcase
            end
            default: note_div = 22'd0;
        endcase
    end
endmodule

module bullet_sound(
    input wire clk,            // 系統時鐘
    input wire rst,            // 重置信號
    input wire trigger,        // 音效觸發信號
    input wire [3:0] vol_num,  // 音量控制輸入
    output reg [15:0] audio    // 音效輸出
);
    reg [21:0] clk_cnt;        // 時鐘計數器
    reg [21:0] note_div;       // 當前音符分頻值
    reg active;                // 音效是否啟動
    reg [31:0] duration_cnt;   // 音效持續時間計數器
    reg [15:0] AMP_P, AMP_N;   // 音效振幅

    // 高音頻率
    localparam HIGH_FREQ = 22'd90000;   // 90kHz 高音
    localparam DURATION = 32'd5000000; // 1秒持續時間 (50MHz 時鐘)

    // 初始化參數
    initial begin
        note_div = HIGH_FREQ;  // 預設為高音
        active = 0;
        audio = 0;
    end

    // 根據音量設置振幅
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            AMP_P <= 16'h4000;  // 預設振幅
            AMP_N <= 16'hC000;
        end else begin
            case (vol_num)
                5: begin AMP_P <= 16'h4000; AMP_N <= 16'hC000; end
                4: begin AMP_P <= 16'h3000; AMP_N <= 16'hD000; end
                3: begin AMP_P <= 16'h2000; AMP_N <= 16'hE000; end
                2: begin AMP_P <= 16'h1000; AMP_N <= 16'hF000; end
                1: begin AMP_P <= 16'h0800; AMP_N <= 16'hF800; end
                default: begin AMP_P <= 16'h0400; AMP_N <= 16'hFC00; end
            endcase
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            active <= 0;
            duration_cnt <= 0;
            clk_cnt <= 0;
            audio <= 0;
        end else if (trigger && !active) begin
            active <= 1;               // 啟動音效
            duration_cnt <= DURATION;  // 設定音效持續時間
        end else if (active) begin
            if (duration_cnt == 0) begin
                active <= 0;           // 停止音效
                audio <= 0;            // 靜音
            end else begin
                duration_cnt <= duration_cnt - 1;

                // 生成方波音頻信號
                if (clk_cnt == note_div) begin
                    clk_cnt <= 0;
                    audio <= (audio == AMP_P) ? AMP_N : AMP_P; // 方波切換
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end
        end else begin
            audio <= 0;  // 無音效時保持靜音
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
