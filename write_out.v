//-----this module is for writing data out------
// 檔名/模組名/Port 皆不變；參數化支援 ARRAY_SIZE=16、OUTPUT_DATA_WIDTH=32(推薦)
`timescale 1ns/100ps
module write_out#(
    parameter ARRAY_SIZE = 8,
    parameter OUTPUT_DATA_WIDTH = 16
)
(
    input clk,
    input srstn,
    input sram_write_enable,              // 上層可寫期的使能（高態表示此拍有有效資料要寫）

    input [1:0] data_set,
    input [5:0] matrix_index,            // 0 .. (2*ARRAY_SIZE-1)

    input signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] quantized_data,

    // active-low write enables（與你原本一致：0 = write）
    output reg sram_write_enable_a0,
    output reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_a,
    output reg [5:0] sram_waddr_a,

    output reg sram_write_enable_b0,
    output reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_b,
    output reg [5:0] sram_waddr_b,

    output reg sram_write_enable_c0,
    output reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_c,
    output reg [5:0] sram_waddr_c
);

integer i;
localparam integer MAX_INDEX   = ARRAY_SIZE - 1;
localparam integer DIAG_LAST   = 2*ARRAY_SIZE - 1;  // 8->15, 16->31

// output FFs (next-state)
reg sram_write_enable_a0_nx, sram_write_enable_b0_nx, sram_write_enable_c0_nx;
reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_a_nx, sram_wdata_b_nx, sram_wdata_c_nx;
reg [5:0] sram_waddr_a_nx, sram_waddr_b_nx, sram_waddr_c_nx;

//---sequential logic-----
always @(posedge clk) begin
    if (~srstn) begin
        sram_write_enable_a0 <= 1'b1;
        sram_write_enable_b0 <= 1'b1;
        sram_write_enable_c0 <= 1'b1;

        sram_wdata_a <= {ARRAY_SIZE*OUTPUT_DATA_WIDTH{1'b0}};
        sram_wdata_b <= {ARRAY_SIZE*OUTPUT_DATA_WIDTH{1'b0}};
        sram_wdata_c <= {ARRAY_SIZE*OUTPUT_DATA_WIDTH{1'b0}};

        sram_waddr_a <= 6'd0;
        sram_waddr_b <= 6'd0;
        sram_waddr_c <= 6'd0;
    end else begin
        sram_write_enable_a0 <= sram_write_enable_a0_nx;
        sram_write_enable_b0 <= sram_write_enable_b0_nx;
        sram_write_enable_c0 <= sram_write_enable_c0_nx;

        sram_wdata_a <= sram_wdata_a_nx;
        sram_wdata_b <= sram_wdata_b_nx;
        sram_wdata_c <= sram_wdata_c_nx;

        sram_waddr_a <= sram_waddr_a_nx;
        sram_waddr_b <= sram_waddr_b_nx;
        sram_waddr_c <= sram_waddr_c_nx;
    end
end

//---------------- A0：write_enable_X0 = 0 means write ----------------
always @(*) begin
    // 預設不寫、資料清 0
    sram_write_enable_a0_nx = 1'b1;
    sram_waddr_a_nx         = 6'd0;
    sram_wdata_a_nx         = {ARRAY_SIZE*OUTPUT_DATA_WIDTH{1'b0}};

    if (sram_write_enable) begin
        case (data_set)
            2'd0: begin
                if (matrix_index < ARRAY_SIZE) begin
                    // 上半三角（含主對角線）
                    sram_write_enable_a0_nx = 1'b0;
                    for (i=0; i<ARRAY_SIZE; i=i+1) begin
                        if (i <= matrix_index)
                            sram_wdata_a_nx[(MAX_INDEX-i)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]
                                = quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
                    end
                    sram_waddr_a_nx = matrix_index;
                end else begin
                    // mix（跨越主對角線後半）
                    sram_write_enable_a0_nx = 1'b0;
                    for (i=0; i<ARRAY_SIZE; i=i+1) begin
                        if (i < (DIAG_LAST - matrix_index)) // 由 15-matrix_index 改為泛化
                            sram_wdata_a_nx[(MAX_INDEX-i)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]
                                = quantized_data[(i + 1 + (matrix_index - ARRAY_SIZE))*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
                    end
                    sram_waddr_a_nx = matrix_index;
                end
            end

            default: ; // 維持預設不寫
        endcase
    end
end

//---------------- B0：write_enable_X0 = 0 means write ----------------
always @(*) begin
    sram_write_enable_b0_nx = 1'b1;
    sram_waddr_b_nx         = 6'd0;
    sram_wdata_b_nx         = {ARRAY_SIZE*OUTPUT_DATA_WIDTH{1'b0}};

    if (sram_write_enable) begin
        case (data_set)
            2'd0: begin
                if (matrix_index < ARRAY_SIZE) begin
                    // 全部由 a0 佔用，上半時 b0 不寫
                    sram_write_enable_b0_nx = 1'b1;
                end else begin
                    // mix（下半一部分塞 b0）
                    sram_write_enable_b0_nx = 1'b0;
                    for (i=0; i<ARRAY_SIZE; i=i+1) begin
                        if (i <= (matrix_index - ARRAY_SIZE))
                            sram_wdata_b_nx[(MAX_INDEX-i)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]
                                = quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
                    end
                    sram_waddr_b_nx = matrix_index - ARRAY_SIZE;
                end
            end

            2'd1: begin
                if (matrix_index < ARRAY_SIZE) begin
                    // 第二個資料集：上半的右側片段
                    sram_write_enable_b0_nx = 1'b0;
                    for (i=0; i<ARRAY_SIZE; i=i+1) begin
                        if (i < (ARRAY_SIZE - matrix_index - 1))
                            sram_wdata_b_nx[(MAX_INDEX-i)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]
                                = quantized_data[(i + 1 + matrix_index)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
                    end
                    sram_waddr_b_nx = matrix_index + ARRAY_SIZE;
                end else begin
                    sram_write_enable_b0_nx = 1'b1; // 不寫
                end
            end

            default: ; // 不寫
        endcase
    end
end

//---------------- C0：write_enable_X0 = 0 means write ----------------
always @(*) begin
    sram_write_enable_c0_nx = 1'b1;
    sram_waddr_c_nx         = 6'd0;
    sram_wdata_c_nx         = {ARRAY_SIZE*OUTPUT_DATA_WIDTH{1'b0}};

    if (sram_write_enable) begin
        case (data_set)
            2'd1: begin
                if (matrix_index < ARRAY_SIZE) begin
                    // 第二個資料集的上半（含主對角線）
                    sram_write_enable_c0_nx = 1'b0;
                    for (i=0; i<ARRAY_SIZE; i=i+1) begin
                        if (i <= matrix_index)
                            sram_wdata_c_nx[(MAX_INDEX-i)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]
                                = quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
                    end
                    sram_waddr_c_nx = matrix_index;
                end else begin
                    // mix（跨越主對角線後半）
                    sram_write_enable_c0_nx = 1'b0;
                    for (i=0; i<ARRAY_SIZE; i=i+1) begin
                        if (i < (DIAG_LAST - matrix_index)) // 由 15-matrix_index 改為泛化
                            sram_wdata_c_nx[(MAX_INDEX-i)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]
                                = quantized_data[(i + 1 + (matrix_index - ARRAY_SIZE))*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
                    end
                    sram_waddr_c_nx = matrix_index;
                end
            end

            default: ; // 不寫
        endcase
    end
end

endmodule

