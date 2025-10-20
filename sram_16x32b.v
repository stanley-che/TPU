// sram_16x128b.v  —— 參數化版本
// 寫入：active-high wsb；csb=0 表示使能。
// 讀/寫皆為同步（posedge clk）。
module sram_16x128b #(
  parameter integer WIDTH = 128,   // ★ 資料位寬（你要 512 就實例化時覆寫）
  parameter integer DEPTH = 64,    // ★ 深度（你 sram_raddr_c* 是 6-bit，64 最安全）
  parameter integer AW    = 6      //   位址寬；若想自動，用 $clog2(DEPTH) 也行（需 -g2012）
)(
  input  wire               clk,
  input  wire               csb,     // active-low chip select；你外面綁 1'b0
  input  wire               wsb,     // active-high write enable
  input  wire [WIDTH-1:0]   wdata,
  input  wire [AW-1:0]      waddr,
  input  wire [AW-1:0]      raddr,
  output reg  [WIDTH-1:0]   rdata
);

  // 真正的記憶體
  reg [WIDTH-1:0] mem [0:DEPTH-1];

  // 同步讀寫
  always @(posedge clk) begin
    if (!csb) begin
      if (wsb)
        mem[waddr] <= wdata;
      rdata <= mem[raddr];
    end
  end

  // 給 testbench 預載資料用
  task char2sram;
    input [AW-1:0]      idx;
    input [WIDTH-1:0]   din;
    begin
      mem[idx] = din;
    end
  endtask

endmodule

