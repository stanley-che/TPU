//-------do the address select for 32 queue, each queue size 32+32-1---
`timescale 1ns/100ps
module addr_sel
(
    input clk,
    input [6:0] addr_serial_num,   // max 0..127 之內（控制器保證範圍）

    //sel for w0~w7
    output reg [9:0] sram_raddr_w0,  // bank 0
    output reg [9:0] sram_raddr_w1,  // bank 1 (offset)

    //sel for d0~d7
    output reg [9:0] sram_raddr_d0,
    output reg [9:0] sram_raddr_d1
);

    // ===== 可調參數 =====
    // 128x32b SRAM 深度
    localparam integer DEPTH          = 128;   // 地址 0..127
    // 每 32-bit word 可容納的元素數（int8=4；FP32=1）
    localparam integer PACK_PER_WORD  = 1;     // FP32 請設 1；若回到 int8 可改成 4

    // ===== next-state wires =====
    wire [9:0] w0_nx;
    wire [9:0] w1_nx;
    wire [9:0] d0_nx;
    wire [9:0] d1_nx;

    // 同步輸出暫存器（保持你原本時序）
    always @(posedge clk) begin
        sram_raddr_w0 <= w0_nx;
        sram_raddr_w1 <= w1_nx;
        sram_raddr_d0 <= d0_nx;
        sram_raddr_d1 <= d1_nx;
    end

    // ---- 飽和式地址產生 ----
    // bank0：直接用 serial（超界則飽和到 DEPTH-1=127）
    assign w0_nx = (addr_serial_num < DEPTH) ? {3'b000, addr_serial_num} : (DEPTH-1);
    assign d0_nx = (addr_serial_num < DEPTH) ? {3'b000, addr_serial_num} : (DEPTH-1);

    // bank1：往前偏移 PACK_PER_WORD；不足則給 127（無效保護）
    assign w1_nx = (addr_serial_num >= PACK_PER_WORD) ?
                    ( ({3'b000, addr_serial_num} - PACK_PER_WORD[9:0]) < DEPTH ?
                      ({3'b000, addr_serial_num} - PACK_PER_WORD[9:0]) : (DEPTH-1) )
                   : (DEPTH-1);

    assign d1_nx = (addr_serial_num >= PACK_PER_WORD) ?
                    ( ({3'b000, addr_serial_num} - PACK_PER_WORD[9:0]) < DEPTH ?
                      ({3'b000, addr_serial_num} - PACK_PER_WORD[9:0]) : (DEPTH-1) )
                   : (DEPTH-1);

endmodule

