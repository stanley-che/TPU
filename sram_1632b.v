// sram_16x128b.v  —— 相容極性 + 內建偵錯
module sram_16x128b #(
  parameter integer WIDTH = 512,
  parameter integer DEPTH = 64,
  parameter integer AW    = 6,
  parameter bit     WSB_ACTIVE_HIGH = 0  // ★ 預設 0 = 和常見 SRAM 一樣：wsb=0 表示寫
)(
  input  wire               clk,
  input  wire               csb,      // 0 = enable（你外面綁 0）
  input  wire               wsb,      // 依 WSB_ACTIVE_HIGH 解讀
  input  wire [WIDTH-1:0]   wdata,
  input  wire [AW-1:0]      waddr,
  input  wire [AW-1:0]      raddr,
  output reg  [WIDTH-1:0]   rdata
);

  reg [WIDTH-1:0] mem [0:DEPTH-1];

  // 先把記憶體清 0，避免一片 x 影響判斷
  integer ii;
  initial begin
    for (ii = 0; ii < DEPTH; ii = ii + 1) mem[ii] = {WIDTH{1'b0}};
    rdata = {WIDTH{1'b0}};
  end

  // 把極性統一成「active=1」
  wire we = WSB_ACTIVE_HIGH ? wsb : ~wsb;

  always @(posedge clk) begin
    if (!csb) begin
      if (we) begin
        mem[waddr] <= wdata;

        // ---- 偵錯輸出（看到 x 時會提示）----
        if (^waddr === 1'bx)
          $display("[SRAM-C] WARN: waddr is X at %0t", $time);
        if (^wdata === 1'bx)
          $display("[SRAM-C] WARN: wdata has X at %0t (addr=%0d)", $time, waddr);
      end
      rdata <= mem[raddr];
    end
  end

  // 給 testbench 預載
  task char2sram;
    input [AW-1:0] idx;
    input [WIDTH-1:0] din;
    begin mem[idx] = din; end
  endtask
endmodule

