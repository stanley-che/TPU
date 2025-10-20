//---- systolic array (FP32) — bus 版介面（N/FPW），內部用 dawson FPU 乘加
`timescale 1ns/100ps

module systolic #(
  parameter integer N   = 8,   // 陣列邊長：8 或 16
  parameter integer FPW = 1    // 每 lane 每拍的 FP32 數量（目前實作等同 1）
)(
  input                   clk,
  input                   rstn,

  input  [N*32-1:0]       top_w_bus,
  input  [N-1:0]          top_w_v,
  input  [N*32-1:0]       left_d_bus,
  input  [N-1:0]          left_d_v,

  output reg [N*32-1:0]   acc_flat_bus,
  output reg [N-1:0]      acc_v_flat
);

  localparam integer FIRST_OUT      = N + 1;
  localparam integer PARALLEL_START = N + N + 1;

  reg  [31:0] data_q   [0:N-1][0:N-1];
  reg  [31:0] weight_q [0:N-1][0:N-1];

  integer i,j;
  reg [$clog2(N)-1:0] col_ptr, row_ptr;

  reg [8:0] cycle_num;
  reg [5:0] matrix_index;

  wire in_v = (|top_w_v) | (|left_d_v);

  function [31:0] pick32;
    input [N*32-1:0] bus;
    input integer    idx;
    begin
      pick32 = bus[(idx+1)*32-1 -: 32];
    end
  endfunction

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      col_ptr       <= {($clog2(N)){1'b0}};
      row_ptr       <= {($clog2(N)){1'b0}};
      cycle_num     <= 9'd0;
      matrix_index  <= 6'd0;
      for (i=0;i<N;i=i+1)
        for (j=0;j<N;j=j+1) begin
          weight_q[i][j] <= 32'h0000_0000;
          data_q  [i][j] <= 32'h0000_0000;
        end
    end else begin
      if (in_v) begin
        // 權重整列下移
        for (i=N-1;i>0;i=i-1)
          for (j=0;j<N;j=j+1)
            weight_q[i][j] <= weight_q[i-1][j];
        // row0 塞兩個 column
        weight_q[0][col_ptr] <= pick32(top_w_bus, col_ptr);
        if (col_ptr+1 < N)
          weight_q[0][col_ptr+1] <= pick32(top_w_bus, col_ptr+1);

        // 資料整行右移
        for (i=0;i<N;i=i+1)
          for (j=N-1;j>0;j=j-1)
            data_q[i][j] <= data_q[i][j-1];
        // col0 塞兩個 row
        data_q[row_ptr][0] <= pick32(left_d_bus, row_ptr);
        if (row_ptr+1 < N)
          data_q[row_ptr+1][0] <= pick32(left_d_bus, row_ptr+1);

        // ===== 這兩行是修正重點（用 + 2'd2） =====
        col_ptr <= (col_ptr >= N-2) ? {($clog2(N)){1'b0}} : (col_ptr + 2'd2);
        row_ptr <= (row_ptr >= N-2) ? {($clog2(N)){1'b0}} : (row_ptr + 2'd2);
        // =====================================

        cycle_num <= cycle_num + 9'd1;

        if (cycle_num >= FIRST_OUT) begin
          if (matrix_index == (2*N-1)) matrix_index <= 6'd0;
          else                         matrix_index <= matrix_index + 6'd1;
        end
      end
    end
  end

  // ===== FPU 乘加陣列 =====
  reg  [31:0] acc_reg [0:N-1][0:N-1];
  wire [31:0] mul_z [0:N-1][0:N-1];
  wire        mul_vs[0:N-1][0:N-1];
  wire [31:0] add_z [0:N-1][0:N-1];
  wire        add_vs[0:N-1][0:N-1];

  genvar gi, gj;
  generate
    for (gi=0; gi<N; gi=gi+1) begin: G_ROW
      for (gj=0; gj<N; gj=gj+1) begin: G_COL
        multiplier u_mul (
          .clk(clk), .rst(~rstn),
          .input_a(weight_q[gi][gj]),
          .input_a_stb(in_v), .input_a_ack(),
          .input_b(data_q[gi][gj]),
          .input_b_stb(in_v), .input_b_ack(),
          .output_z(mul_z[gi][gj]),
          .output_z_stb(mul_vs[gi][gj]),
          .output_z_ack(1'b1)
        );
        adder u_add (
          .clk(clk), .rst(~rstn),
          .input_a(acc_reg[gi][gj]),
          .input_a_stb(mul_vs[gi][gj]), .input_a_ack(),
          .input_b(mul_z[gi][gj]),
          .input_b_stb(mul_vs[gi][gj]), .input_b_ack(),
          .output_z(add_z[gi][gj]),
          .output_z_stb(add_vs[gi][gj]),
          .output_z_ack(1'b1)
        );

        wire first_hit =
          (cycle_num >= FIRST_OUT) &&
          ((gi+gj) == ((cycle_num - FIRST_OUT) % N));
        wire cont_hit  =
          (cycle_num >= PARALLEL_START && (gi+gj) == ((cycle_num - PARALLEL_START) % N)) ||
          ((cycle_num >= 1) && ((gi+gj) <= (cycle_num - 1)));

        always @(posedge clk or negedge rstn) begin
          if (!rstn)
            acc_reg[gi][gj] <= 32'h0000_0000;
          else if (in_v) begin
            if (first_hit && mul_vs[gi][gj])
              acc_reg[gi][gj] <= mul_z[gi][gj];
            else if (cont_hit && add_vs[gi][gj])
              acc_reg[gi][gj] <= add_z[gi][gj];
          end
        end
      end
    end
  endgenerate

integer ii, jj;
always @(posedge clk or negedge rstn) begin
  if (!rstn) begin
    acc_flat_bus <= {N*32{1'b0}};
    acc_v_flat   <= {N{1'b0}};
  end else begin
    acc_flat_bus <= {N*32{1'b0}};
    acc_v_flat   <= {N{1'b0}};
    // 上半
    for (ii=0; ii<N; ii=ii+1)
      for (jj=0; jj<N-ii; jj=jj+1)
        if (ii+jj == ((matrix_index < N) ? matrix_index : (matrix_index - N))) begin
          acc_flat_bus[ii*32 +: 32] <= acc_reg[ii][jj];
          acc_v_flat[ii]            <= 1'b1;
        end
    // 下半
    for (ii=1; ii<N; ii=ii+1)
      for (jj=N-ii; jj<N; jj=jj+1)
        if (ii+jj == ((matrix_index < N) ? (matrix_index + N) : matrix_index)) begin
          acc_flat_bus[ii*32 +: 32] <= acc_reg[ii][jj];
          acc_v_flat[ii]            <= 1'b1;
        end
  end
end


endmodule

