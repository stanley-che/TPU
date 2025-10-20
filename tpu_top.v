// tpu_top.v — diagonal feed, FP32, 16x16, single-lane-per-cycle
`timescale 1ns/100ps
module tpu_top
(
  input               clk,
  input               srstn,
  input               tpu_start,

  // ===== inputs from A/B SRAMs =====
  input  [31:0]       sram_rdata_w0,
  input  [31:0]       sram_rdata_w1,
  input  [31:0]       sram_rdata_d0,
  input  [31:0]       sram_rdata_d1,

  output [9:0]        sram_raddr_w0,
  output [9:0]        sram_raddr_w1,
  output [9:0]        sram_raddr_d0,
  output [9:0]        sram_raddr_d1,

  // ===== outputs to C SRAMs (three stripes) =====
  output              sram_write_enable_a0,
  output [16*32-1:0]  sram_wdata_a,
  output [5:0]        sram_waddr_a,

  output              sram_write_enable_b0,
  output [16*32-1:0]  sram_wdata_b,
  output [5:0]        sram_waddr_b,

  output              sram_write_enable_c0,
  output [16*32-1:0]  sram_wdata_c,
  output [5:0]        sram_waddr_c,

  output              tpu_done
);

  // -------- params --------
  localparam int N   = 16;
  localparam int FPW = 32;
  localparam int C_BUS_W = N*FPW; // 512

  // -------- run control --------
  reg        running;
  reg [7:0]  t;       // 簡單拍數（可依需要調長）
  wire kick = tpu_start & ~running;

  always @(posedge clk or negedge srstn) begin
    if (!srstn) begin
      running <= 1'b0; t <= 8'd0;
    end else if (kick) begin
      running <= 1'b1; t <= 8'd0;
    end else if (running) begin
      if (t < 8'd63) t <= t + 8'd1; else running <= 1'b0;
    end
  end
  assign tpu_done = ~running;

  // -------- read addr gen (交錯) --------
  reg [9:0] raddr_w0, raddr_w1, raddr_d0, raddr_d1;
  always @(posedge clk or negedge srstn) begin
    if (!srstn) begin
      raddr_w0 <= 10'd0; raddr_w1 <= 10'd0;
      raddr_d0 <= 10'd0; raddr_d1 <= 10'd0;
    end else if (running) begin
      if (!t[0]) begin
        raddr_w0 <= raddr_w0 + 10'd1;
        raddr_d0 <= raddr_d0 + 10'd1;
      end else begin
        raddr_w1 <= raddr_w1 + 10'd1;
        raddr_d1 <= raddr_d1 + 10'd1;
      end
    end
  end
  assign sram_raddr_w0 = raddr_w0;
  assign sram_raddr_w1 = raddr_w1;
  assign sram_raddr_d0 = raddr_d0;
  assign sram_raddr_d1 = raddr_d1;

  // -------- boundary buses into systolic --------
  reg  [N*FPW-1:0] top_w_bus, left_d_bus;
  reg              in_v;
  wire [N-1:0]     in_v_bus = {N{in_v}};

  always @(posedge clk or negedge srstn) begin
    if (!srstn) begin
      top_w_bus  <= '0;
      left_d_bus <= '0;
      in_v       <= 1'b0;
    end else if (running) begin
      // 清零後只在 (t % N) 的 lane 塞入 32b 值
      top_w_bus  <= '0;
      left_d_bus <= '0;
      in_v       <= 1'b1;
      top_w_bus [ (t % N)*FPW +: FPW ]  <= (!t[0]) ? sram_rdata_w0 : sram_rdata_w1;
      left_d_bus[ (t % N)*FPW +: FPW ]  <= (!t[0]) ? sram_rdata_d0 : sram_rdata_d1;
    end else begin
      in_v <= 1'b0;
    end
  end

  // -------- systolic array --------
  wire [N*FPW-1:0] acc_flat_bus;  // 每個 lane 32b，共 16 lane
  wire [N-1:0]     acc_v_flat;    // 每 lane 的 valid

  systolic #(.N(N), .FPW(FPW)) u_array (
    .clk(clk), .rstn(srstn),
    .top_w_bus(top_w_bus),   .top_w_v(in_v_bus),
    .left_d_bus(left_d_bus), .left_d_v(in_v_bus),
    .acc_flat_bus(acc_flat_bus),
    .acc_v_flat(acc_v_flat)
  );

  // -------- stripe pack & write (每條對角線都寫一列) --------
reg  [C_BUS_W-1:0] acc_bus_d1;
reg  [15:0]        acc_v_d1;
always @(posedge clk or negedge srstn) begin
  if (!srstn) begin
    acc_bus_d1 <= '0;
    acc_v_d1   <= '0;
  end else begin
    acc_bus_d1 <= acc_flat_bus;  // 把整條 lane 資料/valid 各延遲 1 拍
    acc_v_d1   <= acc_v_flat;
  end
end

wire any_valid = |acc_v_d1;

reg  [C_BUS_W-1:0] stripe_q;
reg                we_q;
reg  [5:0]         wrow_q;

always @(posedge clk or negedge srstn) begin
  if (!srstn) begin
    stripe_q <= '0;
    we_q     <= 1'b0;
    wrow_q   <= '0;
  end else begin
    stripe_q <= '0;   // 給預設，避免 X
    we_q     <= 1'b0;

    // 只覆蓋有效的 lane；其他保持 0（符合 golden：前幾條對角線有很多 0）
    for (int k = 0; k < 16; k++) begin
      if (acc_v_d1[k])
        stripe_q[k*32 +: 32] <= acc_bus_d1[k*32 +: 32];
    end

    if (any_valid) begin
      we_q   <= 1'b1;          // 每條對角線都寫一列
      wrow_q <= wrow_q + 6'd1; // 依序寫到 addr 0..(2*N-2)
    end
  end
end

assign sram_write_enable_a0 = we_q;
assign sram_waddr_a         = wrow_q;
assign sram_wdata_a         = stripe_q;

assign sram_write_enable_b0 = we_q;
assign sram_waddr_b         = wrow_q;
assign sram_wdata_b         = stripe_q;

assign sram_write_enable_c0 = we_q;
assign sram_waddr_c         = wrow_q;
assign sram_wdata_c         = stripe_q;

always @(posedge clk) if (we_q) $display("WRITE row=%0d  lane_valid=%b", wrow_q, acc_v_d1);

endmodule

