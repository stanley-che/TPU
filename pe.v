// pe.v — IEEE-754 FP32 processing element using dawsonjon/fpu
// 保持模組名 `pe` 與 I/O 風格（in_w: 上方流下的權重；in_d: 左邊流入的資料）
`timescale 1ns/100ps
module pe #
(
  parameter FPW = 32
)
(
  input               clk,
  input               rstn,
  input  [FPW-1:0]    in_w,
  input  [FPW-1:0]    in_d,
  input               in_v,     // 本拍有效
  output reg [FPW-1:0] out_w,   // 往下一列
  output reg [FPW-1:0] out_d,   // 往右一行
  output reg          out_v,    // 有效往前推
  output [FPW-1:0]    acc_out,  // 本 PE 的累加值
  output              acc_v
);

  // 1 拍前推（維持脈動節奏）
  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      out_w <= {FPW{1'b0}};
      out_d <= {FPW{1'b0}};
      out_v <= 1'b0;
    end else begin
      out_w <= in_w;
      out_d <= in_d;
      out_v <= in_v;
    end
  end

  // FP32 乘法：multiplier（dawson FPU）
  wire [31:0] mul_z;
  wire        mul_z_stb;

  multiplier u_fp_mul (
    .clk(clk), .rst(~rstn),
    .input_a(in_w), .input_a_stb(in_v), .input_a_ack(),
    .input_b(in_d), .input_b_stb(in_v), .input_b_ack(),
    .output_z(mul_z), .output_z_stb(mul_z_stb), .output_z_ack(1'b1)
  );

  // FP32 累加：adder（acc + mul_z）
  reg  [31:0] acc_reg;
  wire [31:0] add_z;
  wire        add_z_stb;

  adder u_fp_add (
    .clk(clk), .rst(~rstn),
    .input_a(acc_reg), .input_a_stb(mul_z_stb), .input_a_ack(),
    .input_b(mul_z),   .input_b_stb(mul_z_stb), .input_b_ack(),
    .output_z(add_z),  .output_z_stb(add_z_stb), .output_z_ack(1'b1)
  );

  always @(posedge clk or negedge rstn) begin
    if (!rstn)        acc_reg <= 32'h0000_0000; // +0.0
    else if (add_z_stb) acc_reg <= add_z;
  end

  assign acc_out = acc_reg;
  assign acc_v   = add_z_stb;

endmodule

