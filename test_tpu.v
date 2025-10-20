`timescale 1ns/100ps
`define cycle_period 10
//`define FSDB
//`define VCD
//`define End_CYCLE  250000 

module test_tpu;

//==================== 改成 FP32 / 16x16 ====================
localparam DATA_WIDTH      = 32;  // 單一元素位寬：IEEE-754 FP32
localparam OUT_DATA_WIDTH  = 32;  // 每個輸出元素同為 FP32
localparam SRAM_DATA_WIDTH = 32;  // A/B 類 SRAM 的資料埠寬仍為 32
localparam ARRAY_SIZE      = 16;  // 陣列大小 16×16
localparam WEIGHT_NUM = 25, WEIGHT_WIDTH = 4; // 原樣保留（若你仍使用）
localparam WIDTH=512,DEPTH=64;
//====== module I/O =====
reg clk;
reg srstn;
reg tpu_start;

wire tpu_finish;

// A/B 類 SRAM 的 bytemask/寫埠仍為 8b/32b 組合（預載走 char2sram，不影響）
wire sram_write_enable_a0;
wire sram_write_enable_a1;
wire sram_write_enable_b0;
wire sram_write_enable_b1;

// ★ C 類（結果）三顆，每列寬度改為 16×32 = 512 bit
wire sram_write_enable_c0;
wire sram_write_enable_c1;
wire sram_write_enable_c2;

wire [SRAM_DATA_WIDTH-1:0] sram_rdata_a0;
wire [SRAM_DATA_WIDTH-1:0] sram_rdata_a1;

wire [SRAM_DATA_WIDTH-1:0] sram_rdata_b0;
wire [SRAM_DATA_WIDTH-1:0] sram_rdata_b1;

wire [9:0] sram_raddr_a0;
wire [9:0] sram_raddr_a1;
wire [9:0] sram_raddr_b0;
wire [9:0] sram_raddr_b1;

wire [5:0] sram_raddr_c0;
wire [5:0] sram_raddr_c1;
wire [5:0] sram_raddr_c2;

wire [3:0] sram_bytemask_a;
wire [3:0] sram_bytemask_b;
wire [9:0] sram_waddr_a;
wire [9:0] sram_waddr_b;
wire [7:0] sram_wdata_a;
wire [7:0] sram_wdata_b;

// ★ 這裡原本寫的是 DATA_WIDTH*OUT_DATA_WIDTH（剛好 8*16=128）
//   FP32 之後要改為 ARRAY_SIZE*OUT_DATA_WIDTH（= 16*32 = 512）
wire [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] sram_wdata_c0;
wire [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] sram_wdata_c1;
wire [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] sram_wdata_c2;

wire [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] sram_rdata_c0;
wire [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] sram_rdata_c1;
wire [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] sram_rdata_c2;

wire [5:0] sram_waddr_c0;
wire [5:0] sram_waddr_c1;
wire [5:0] sram_waddr_c2;

wire signed [7:0] out; // 原樣保留（未使用）

//====== top connection =====
tpu_top my_tpu_top(
  .clk(clk),
  .srstn(srstn),
  .tpu_start(tpu_start),

  // input (weight/data) from SRAM A/B（32-bit）
  .sram_rdata_w0(sram_rdata_a0),
  .sram_rdata_w1(sram_rdata_a1),
  .sram_rdata_d0(sram_rdata_b0),
  .sram_rdata_d1(sram_rdata_b1),

  .sram_raddr_w0(sram_raddr_a0),
  .sram_raddr_w1(sram_raddr_a1),
  .sram_raddr_d0(sram_raddr_b0),
  .sram_raddr_d1(sram_raddr_b1),

  // output stripes to C SRAMs（每列 512b）
  .sram_write_enable_a0(sram_write_enable_c0),
  .sram_wdata_a(sram_wdata_c0),
  .sram_waddr_a(sram_waddr_c0),

  .sram_write_enable_b0(sram_write_enable_c1),
  .sram_wdata_b(sram_wdata_c1),
  .sram_waddr_b(sram_waddr_c1),

  .sram_write_enable_c0(sram_write_enable_c2),
  .sram_wdata_c(sram_wdata_c2),
  .sram_waddr_c(sram_waddr_c2),

  .tpu_done(tpu_finish)
);

// ===== A/B SRAM（128×32b；預載走 char2sram）=====
sram_128x32b sram_128x32b_a0(
  .clk(clk),
  .bytemask(sram_bytemask_a),
  .csb(1'b0),
  .wsb(sram_write_enable_a0),
  .wdata(sram_wdata_a), 
  .waddr(sram_waddr_a), 
  .raddr(sram_raddr_a0), 
  .rdata(sram_rdata_a0)
);

sram_128x32b sram_128x32b_a1(
  .clk(clk),
  .bytemask(sram_bytemask_a),
  .csb(1'b0),
  .wsb(sram_write_enable_a1),
  .wdata(sram_wdata_a), 
  .waddr(sram_waddr_a), 
  .raddr(sram_raddr_a1), 
  .rdata(sram_rdata_a1)
);

sram_128x32b sram_128x32b_b0(
  .clk(clk),
  .bytemask(sram_bytemask_b),
  .csb(1'b0),
  .wsb(sram_write_enable_b0),
  .wdata(sram_wdata_b), 
  .waddr(sram_waddr_b), 
  .raddr(sram_raddr_b0), 
  .rdata(sram_rdata_b0)
);

sram_128x32b sram_128x32b_b1(
  .clk(clk),
  .bytemask(sram_bytemask_b),
  .csb(1'b0),
  .wsb(sram_write_enable_b1),
  .wdata(sram_wdata_b), 
  .waddr(sram_waddr_b), 
  .raddr(sram_raddr_b1), 
  .rdata(sram_rdata_b1)
);

// ===== C SRAM（檔名不變，但寬度需升到 512b）=====
sram_16x128b #(.WIDTH(512), .DEPTH(64), .WSB_ACTIVE_HIGH(0)) sram_16x128b_c0(
  .clk(clk),
  .csb(1'b0),
  .wsb(sram_write_enable_c0),
  .wdata(sram_wdata_c0), // 512b
  .waddr(sram_waddr_c0), 
  .raddr(sram_raddr_c0), 
  .rdata(sram_rdata_c0)  // 512b
);
sram_16x128b #(.WIDTH(512), .DEPTH(64), .WSB_ACTIVE_HIGH(0)) sram_16x128b_c1(
  .clk(clk),
  .csb(1'b0),
  .wsb(sram_write_enable_c1),
  .wdata(sram_wdata_c1), 
  .waddr(sram_waddr_c1), 
  .raddr(sram_raddr_c1), 
  .rdata(sram_rdata_c1)
);
sram_16x128b #(.WIDTH(512), .DEPTH(64), .WSB_ACTIVE_HIGH(0)) sram_16x128b_c2(
  .clk(clk),
  .csb(1'b0),
  .wsb(sram_write_enable_c2),
  .wdata(sram_wdata_c2), 
  .waddr(sram_waddr_c2), 
  .raddr(sram_raddr_c2), 
  .rdata(sram_rdata_c2)
);

// ===== 波形 =====
`ifdef FSDB
initial begin
  $fsdbDumpfile("tpu.fsdb");
  $fsdbDumpvars("+mda");
end
`elsif VCD
initial begin
  $dumpfile("tpu.vcd");
  $dumpvars(0, test_tpu);
end
`endif

//====== clock =====
initial begin
  srstn = 1'b1;
  clk   = 1'b1;
  #(`cycle_period/2);
  while(1) begin
    #(`cycle_period/2) clk = ~clk; 
  end
end

//====== main =====
integer cycle_cnt;
integer i,j;

// ★ mat1/mat2 每列有 ARRAY_SIZE 個元素，每元素 32-bit
reg [ARRAY_SIZE*DATA_WIDTH-1:0]            mat1[0:ARRAY_SIZE*3-1];
reg [ARRAY_SIZE*DATA_WIDTH-1:0]            mat2[0:ARRAY_SIZE*3-1];

// ★ 臨時拼接區：把三批資料沿用你原本的拼接方式（位寬全面用 DATA_WIDTH）
reg [ARRAY_SIZE*3*DATA_WIDTH-1:0]          tmp_c_mat1[0:ARRAY_SIZE-1];
reg [ARRAY_SIZE*3*DATA_WIDTH-1:0]          tmp_c_mat2[0:ARRAY_SIZE-1];
reg [(ARRAY_SIZE*3+3)*DATA_WIDTH-1:0]      tmp_mat1[0:ARRAY_SIZE-1];
reg [(ARRAY_SIZE*3+3)*DATA_WIDTH-1:0]      tmp_mat2[0:ARRAY_SIZE-1];

// ★ golden 也升為 FP32（若你保留 bit-comparison，可改為容忍比較邏輯）
reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0]        golden1[0:ARRAY_SIZE-1];
reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0]        golden2[0:ARRAY_SIZE-1];
reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0]        golden3[0:ARRAY_SIZE-1];

// ★ 轉置/對角線打包後的 512b（原本 8×16b=128b，現在 16×32b=512b）
reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0]        trans_golden1[0:(ARRAY_SIZE*2-1)-1];
reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0]        trans_golden2[0:(ARRAY_SIZE*2-1)-1];
reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0]        trans_golden3[0:(ARRAY_SIZE*2-1)-1];

initial begin
  // ★ 改用 HEX（IEEE-754 FP32），每行一個值
  $readmemh("data/mat1.txt", mat1);
  $readmemh("data/mat2.txt", mat2);
  $readmemh("golden/golden1.txt", golden1);
  $readmemh("golden/golden2.txt", golden2);
  $readmemh("golden/golden3.txt", golden3);

  #(`cycle_period);
  data2sram;
  golden_transform;

  $write("|\nThree input groups of matrix (display skipped for FP32)\n|\n");

  // start
  tpu_start = 1'b0;
  cycle_cnt = 0;
  @(negedge clk); srstn = 1'b0;
  @(negedge clk); srstn = 1'b1;
  tpu_start = 1'b1;  // one-cycle pulse
  @(negedge clk); tpu_start = 1'b0;

  while(~tpu_finish) begin
    @(negedge clk); cycle_cnt = cycle_cnt + 1;
  end

  // ===== 三顆 SRAM 比對（bit-exact；如改容忍，請在 write_out 內做）
  for(i = 0; i<(ARRAY_SIZE*2-1); i = i+1) begin
    if(trans_golden1[i] == sram_16x128b_c0.mem[i])
      $write("sram #c0 address: %0d PASS!!\n", i[5:0]);
    else begin
      $write("You have wrong answer in the sram #c0 !!!\n\n");
      // 印 16 個 32b
      $write("Your answer at address %0d is \n", i[5:0]);
      for (j=ARRAY_SIZE; j>0; j=j-1)
        $write("%0d ", $signed(sram_16x128b_c0.mem[i][(j*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH]));
      $write("\nBut the golden answer is \n");
      for (j=ARRAY_SIZE; j>0; j=j-1)
        $write("%0d ", $signed(trans_golden1[i][(j*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH]));
      $write("\n");
      $finish;
    end
  end

  for(i = 0; i<(ARRAY_SIZE*2-1); i = i+1) begin
    if(trans_golden2[i] == sram_16x128b_c1.mem[i])
      $write("sram #c1 address: %0d PASS!!\n", i[5:0]);
    else begin
      $write("You have wrong answer in the sram #c1 !!!\n\n");
      $write("Your answer at address %0d is \n", i[5:0]);
      for (j=ARRAY_SIZE; j>0; j=j-1)
        $write("%0d ", $signed(sram_16x128b_c1.mem[i][(j*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH]));
      $write("\nBut the golden answer is \n");
      for (j=ARRAY_SIZE; j>0; j=j-1)
        $write("%0d ", $signed(trans_golden2[i][(j*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH]));
      $write("\n");
      $finish;
    end
  end

  for(i = 0; i<(ARRAY_SIZE*2-1); i = i+1) begin
    if(trans_golden3[i] == sram_16x128b_c2.mem[i])
      $write("sram #c2 address: %0d PASS!!\n", i[5:0]);
    else begin
      $write("You have wrong answer in the sram #c2 !!!\n\n");
      $write("Your answer at address %0d is \n", i[5:0]);
      for (j=ARRAY_SIZE; j>0; j=j-1)
        $write("%0d ", $signed(sram_16x128b_c2.mem[i][(j*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH]));
      $write("\nBut the golden answer is \n");
      for (j=ARRAY_SIZE; j>0; j=j-1)
        $write("%0d ", $signed(trans_golden3[i][(j*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH]));
      $write("\n");
      $finish;
    end
  end

  $display("Total cycle count C after three matrix evaluation = %0d.", cycle_cnt);
  #5 $finish;
end

// ======= 把三批輸入打包進四顆 128x32b SRAM（沿用你的流程）=======
task data2sram;
  begin
    // reset
    for(i = 0; i< ARRAY_SIZE ; i = i + 1) begin
      tmp_c_mat1[i] = 0; tmp_c_mat2[i] = 0;
      tmp_mat1[i]   = 0; tmp_mat2[i]   = 0;
    end
    // combine three batch together into tmp_mat1, tmp_mat2
    for(i = 0; i< 3 ; i = i + 1) begin
      for(j = 0; j< ARRAY_SIZE; j = j+1) begin
        tmp_c_mat1[j] = {mat1[ARRAY_SIZE*i+j], tmp_c_mat1[j][(ARRAY_SIZE*3*DATA_WIDTH-1) -: 2*DATA_WIDTH*ARRAY_SIZE]};
        tmp_c_mat2[j] = {mat2[ARRAY_SIZE*i+j], tmp_c_mat2[j][(ARRAY_SIZE*3*DATA_WIDTH-1) -: 2*DATA_WIDTH*ARRAY_SIZE]};
      end
    end
    for(i = 0; i< ARRAY_SIZE ; i = i + 1) begin
      case (i % 4)
        0: begin tmp_mat1[i] = {24'b0, tmp_c_mat1[i]}; tmp_mat2[i] = {24'b0, tmp_c_mat2[i]}; end
        1: begin tmp_mat1[i] = {16'b0, tmp_c_mat1[i], 8'b0}; tmp_mat2[i] = {16'b0, tmp_c_mat2[i], 8'b0}; end
        2: begin tmp_mat1[i] = { 8'b0, tmp_c_mat1[i],16'b0}; tmp_mat2[i] = { 8'b0, tmp_c_mat2[i],16'b0}; end
        3: begin tmp_mat1[i] = {tmp_c_mat1[i], 24'b0}; tmp_mat2[i] = {tmp_c_mat2[i], 24'b0}; end
        default: begin tmp_mat1[i] = 0; tmp_mat2[i] = 0; end
      endcase
    end

    // 預載到四顆 128x32b SRAM：每拍 4×32b（和你原本一致，只是 DATA_WIDTH 改 32）
    for(i = 0; i < 128; i=i+1) begin
      if(i < (ARRAY_SIZE*3+3)) begin
        sram_128x32b_a0.char2sram(i, { tmp_mat1[0][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH],
                                       tmp_mat1[1][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH],
                                       tmp_mat1[2][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH],
                                       tmp_mat1[3][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH] });
        sram_128x32b_a1.char2sram(i, { tmp_mat1[4][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH],
                                       tmp_mat1[5][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH],
                                       tmp_mat1[6][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH],
                                       tmp_mat1[7][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH] });

        sram_128x32b_b0.char2sram(i, { tmp_mat2[0][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH],
                                       tmp_mat2[1][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH],
                                       tmp_mat2[2][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH],
                                       tmp_mat2[3][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH] });
        sram_128x32b_b1.char2sram(i, { tmp_mat2[4][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH],
                                       tmp_mat2[5][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH],
                                       tmp_mat2[6][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH],
                                       tmp_mat2[7][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH] });
      end else begin
        sram_128x32b_a0.char2sram(i, 32'b0);
        sram_128x32b_a1.char2sram(i, 32'b0);
        sram_128x32b_b0.char2sram(i, 32'b0);
        sram_128x32b_b1.char2sram(i, 32'b0);
      end
    end

    // （可選）列印 A/B SRAM 預載結果 —— FP32 會很長，預設保留
    $write("SRAM a0 (preview first few)...\n");
    for(i = 0; i< 8 ; i = i + 1)
      $write("SRAM a0[%0d] = %h\n", i[7:0], sram_128x32b_a0.mem[i]);

    $write("SRAM b0 (preview first few)...\n");
    for(i = 0; i< 8 ; i = i + 1)
      $write("SRAM b0[%0d] = %h\n", i[7:0], sram_128x32b_b0.mem[i]);
  end
endtask	

// ======= 顯示原資料（原本逐 bit 列印，FP32 無意義；這裡保留框架但不輸出）=======
task display_data;
integer this_i, this_j, this_k;
  begin
    // 若要顯示成實數，可在這裡把 32-bit 轉 real 再 $display
    // 目前略過避免刷屏
  end
endtask

// ======= 生成三條對角線序（512b）作為 golden 的排布 =======
task golden_transform;
integer this_i, this_j, this_k;
  begin
    for(this_k=0; this_k<(ARRAY_SIZE*2-1); this_k=this_k+1) begin
      trans_golden1[this_k] = 0;
      trans_golden2[this_k] = 0;
      trans_golden3[this_k] = 0;
    end
    for(this_k=0; this_k<(ARRAY_SIZE*2-1); this_k=this_k+1) begin
      for(this_i=0; this_i<ARRAY_SIZE; this_i=this_i+1) begin
        for(this_j=0; this_j<ARRAY_SIZE; this_j=this_j+1) begin
          if((this_i+this_j)==this_k) begin
            // 依 j 由小到大，把 32b 值推入 512b 匯流排頭端
            trans_golden1[this_k] = { golden1[this_i][((this_j+1)*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH],
                                      trans_golden1[this_k][(ARRAY_SIZE*OUT_DATA_WIDTH-1) -: ((ARRAY_SIZE-1)*OUT_DATA_WIDTH)] };
            trans_golden2[this_k] = { golden2[this_i][((this_j+1)*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH],
                                      trans_golden2[this_k][(ARRAY_SIZE*OUT_DATA_WIDTH-1) -: ((ARRAY_SIZE-1)*OUT_DATA_WIDTH)] };
            trans_golden3[this_k] = { golden3[this_i][((this_j+1)*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH],
                                      trans_golden3[this_k][(ARRAY_SIZE*OUT_DATA_WIDTH-1) -: ((ARRAY_SIZE-1)*OUT_DATA_WIDTH)] };
          end
        end
      end
    end

    $write("Here shows the trans_golden1 (first few lines)…\n");
    for(this_k=0; this_k<4; this_k=this_k+1) begin
      for(this_i=ARRAY_SIZE; this_i>0; this_i=this_i-1)
        $write("%0d ", $signed(trans_golden1[this_k][(this_i*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH]));
      $write("\n\n");
    end
  end
endtask 


endmodule

