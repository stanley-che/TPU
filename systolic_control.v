//-----controller for systolic array----
// 保持模組名與介面，參數化 ARRAY_SIZE，加入 PIPELINE_MARGIN（FPU 管線保險）
`timescale 1ns/100ps
module systolic_controll #(
  parameter ARRAY_SIZE       = 8,   // 8 或 16
  parameter PIPELINE_MARGIN  = 8    // 額外等待拍數，補 FPU 乘/加管線延遲
)
(
  input              clk,
  input              srstn,
  input              tpu_start,          // total enable signal

  output reg         sram_write_enable,

  // addr_sel
  output reg [6:0]   addr_serial_num,

  // systolic array
  output reg         alu_start,          // shift & multiply start
  output reg [8:0]   cycle_num,          // for systolic.v
  output reg [5:0]   matrix_index,       // index for write-out SRAM data
  output reg [1:0]   data_set,

  output reg         tpu_done            // done signal
);

  // ====== 內部衍生參數（全部由 ARRAY_SIZE 推導） ======
  localparam integer FIRST_OUT        = ARRAY_SIZE + 1;
  localparam integer PARALLEL_START   = ARRAY_SIZE + ARRAY_SIZE + 1;
  // 你的 matrix_index 走 0..(2*ARRAY_SIZE-1)
  localparam integer LAST_MIDX        = (2*ARRAY_SIZE - 1);
  // 最晚寫出結束後，再等 PIPELINE_MARGIN 拍以 cover FPU latency
  localparam integer SAFE_CYCLE_LIMIT  = (FIRST_OUT + LAST_MIDX + PIPELINE_MARGIN);

  // ====== state ======
  localparam IDLE      = 3'd0,
             LOAD_DATA = 3'd1,
             WAIT1     = 3'd2,
             ROLLING   = 3'd3;

  reg [2:0] state, state_nx;

  reg [1:0] data_set_nx;
  reg       tpu_done_nx;

  // addr_sel
  reg [6:0] addr_serial_num_nx;

  // systolic
  reg [8:0] cycle_num_nx;
  reg [5:0] matrix_index_nx;

  //====== reg updates ======
  always @(posedge clk) begin
    if (~srstn) begin
      state           <= IDLE;
      data_set        <= 2'd0;
      cycle_num       <= 9'd0;
      matrix_index    <= 6'd0;
      addr_serial_num <= 7'd0;
      tpu_done        <= 1'b0;
    end else begin
      state           <= state_nx;
      data_set        <= data_set_nx;
      cycle_num       <= cycle_num_nx;
      matrix_index    <= matrix_index_nx;
      addr_serial_num <= addr_serial_num_nx;
      tpu_done        <= tpu_done_nx;
    end
  end

  //====== state transition / tpu_done ======
  always @(*) begin
    case (state)
      IDLE: begin
        state_nx     = tpu_start ? LOAD_DATA : IDLE;
        tpu_done_nx  = 1'b0;
      end
      LOAD_DATA: begin
        state_nx     = WAIT1;
        tpu_done_nx  = 1'b0;
      end
      WAIT1: begin
        state_nx     = ROLLING;
        tpu_done_nx  = 1'b0;
      end
      ROLLING: begin
        // 結束條件：
        // 1) 已走完所有對角線（matrix_index == LAST_MIDX，等價你原本的 15）
        // 2) data_set == 1（維持你原本兩輪資料集的結束條件）
        // 3) cycle_num 也走過 SAFE_CYCLE_LIMIT（確保 FPU 管線完全沖空）
        if ((matrix_index == LAST_MIDX) && (data_set == 2'd1) && (cycle_num >= SAFE_CYCLE_LIMIT)) begin
          state_nx    = IDLE;
          tpu_done_nx = 1'b1;
        end else begin
          state_nx    = ROLLING;
          tpu_done_nx = 1'b0;
        end
      end
      default: begin
        state_nx     = IDLE;
        tpu_done_nx  = 1'b0;
      end
    endcase
  end

  //====== addr_serial_num ======
  always @(*) begin
    case (state)
      IDLE:       addr_serial_num_nx = tpu_start ? 7'd0 : addr_serial_num;
      LOAD_DATA:  addr_serial_num_nx = 7'd1;
      WAIT1:      addr_serial_num_nx = 7'd2;
      ROLLING:    addr_serial_num_nx = (addr_serial_num == 7'd127) ? addr_serial_num : (addr_serial_num + 7'd1);
      default:    addr_serial_num_nx = 7'd0;
    endcase
  end

  //====== alu_start / cycle_num / matrix_index / data_set / sram_write_enable ======
  always @(*) begin
    case (state)
      IDLE: begin
        alu_start        = 1'b0;
        cycle_num_nx     = 9'd0;
        matrix_index_nx  = 6'd0;
        data_set_nx      = 2'd0;
        sram_write_enable= 1'b0;
      end

      LOAD_DATA: begin
        alu_start        = 1'b0;
        cycle_num_nx     = 9'd0;
        matrix_index_nx  = 6'd0;
        data_set_nx      = 2'd0;
        sram_write_enable= 1'b0;
      end

      WAIT1: begin
        alu_start        = 1'b0;
        cycle_num_nx     = 9'd0;
        matrix_index_nx  = 6'd0;
        data_set_nx      = 2'd0;
        sram_write_enable= 1'b0;
      end

      ROLLING: begin
        alu_start        = 1'b1;
        cycle_num_nx     = cycle_num + 9'd1;

        if (cycle_num >= FIRST_OUT) begin
          // 進入可寫階段：每拍遞增 matrix_index（0..LAST_MIDX）
          if (matrix_index == LAST_MIDX) begin
            matrix_index_nx  = 6'd0;
            data_set_nx      = data_set + 2'd1; // 維持你原本兩輪資料集
          end else begin
            matrix_index_nx  = matrix_index + 6'd1;
            data_set_nx      = data_set;
          end
          sram_write_enable  = 1'b1;
        end else begin
          matrix_index_nx    = 6'd0;
          data_set_nx        = data_set;
          sram_write_enable  = 1'b0;
        end
      end

      default: begin
        alu_start        = 1'b0;
        cycle_num_nx     = 9'd0;
        matrix_index_nx  = 6'd0;
        data_set_nx      = 2'd0;
        sram_write_enable= 1'b0;
      end
    endcase
  end

endmodule

