//-------ori data is from systolic array, output to quantized data-------
`timescale 1ns/1ps

// FP32 版 quantize：保留模組名/參數，不做量化，純 pass-through。
// - 推薦設定：ARRAY_SIZE=16，DATA_WIDTH=32，OUTPUT_DATA_WIDTH=32
// - 輸入/輸出皆為 IEEE-754 32-bit，寬度以 OUTPUT_DATA_WIDTH 為準。
module quantize#(
    parameter ARRAY_SIZE = 8,
    parameter SRAM_DATA_WIDTH = 32,     // 保留參數（未使用）
    parameter DATA_WIDTH = 32,          // FP32
    parameter OUTPUT_DATA_WIDTH = 32    // FP32
)
(
    // 改為依 OUTPUT_DATA_WIDTH 定義寬度：每個元素就是一個 FP32
    input  signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] ori_data,
    output reg signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] quantized_data
);

integer i;

// FP32 不需要量化／飽和：逐 lane 直通
always @* begin
    for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
        quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]
            = ori_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
    end
end

endmodule

