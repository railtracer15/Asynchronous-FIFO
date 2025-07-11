`timescale 1ns / 1ps

module tb;
  // Parameters
  parameter DATA_WIDTH = 8;
  parameter PTR_WIDTH = 3;
  parameter DEPTH = 1 << PTR_WIDTH;
  parameter WRITE_DELAY = 10;    // cycles to wait for write side sync
  parameter READ_DELAY = 10;    // cycles to wait for read side sync
  parameter TIMEOUT = 1000;  // max cycles to wait in loops

  // Clocks & resets
  reg wclk = 0, rclk = 0;
  reg wrst_n = 0, rrst_n  = 0;
  // Control & data
  reg  w_en = 0, r_en = 0;
  reg  [DATA_WIDTH-1:0] datain       = 0;
  wire [DATA_WIDTH-1:0] dataout;
  wire full, empty;

  // Test variables
  integer i, timeout_cnt;
  reg [DATA_WIDTH-1:0] received;
  reg test_pass = 1;

  // Device Under Test
  asynchronous_fifo #(
    .DEPTH(DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .PTR_WIDTH(PTR_WIDTH)
) dut (
    .wclk(wclk),   
    .wrst_n(wrst_n),
    .rclk(rclk),  
    .rrst_n(rrst_n),
    .w_en(w_en),   
    .r_en(r_en),
    .data_in(datain),
    .data_out(dataout),
    .full(full),  
    .empty(empty)
  );

  // Clock generation
  always #10 wclk = ~wclk;   // 50 MHz
  always #25 rclk = ~rclk;   // 20 MHz

  // VCD dump
  initial begin
    $dumpfile("fifo_tb.vcd");
    $dumpvars(0, tb);
  end

  // Reset
  initial begin
    wrst_n = 0; rrst_n = 0;
    repeat (5) @(posedge wclk);
    repeat (5) @(posedge rclk);
    wrst_n = 1; rrst_n = 1;
  end

  // Task: write one word, with timeout
  task write_data(input [DATA_WIDTH-1:0] word);
    begin
      timeout_cnt = 0;
      // wait until not full or timeout
      while (full && timeout_cnt < TIMEOUT) begin
        @(posedge wclk);
        timeout_cnt = timeout_cnt + 1;
      end
      if (timeout_cnt == TIMEOUT) begin
        $display("[ERROR] write_data timeout waiting for !full");
        test_pass = 0;
        disable write_data;
      end

      // assert write
      @(posedge wclk);
      w_en   = 1;
      datain = word;
      @(posedge wclk);
      w_en = 0;
      $display("[WRITE] @%0t : %02h", $time, word);

      // allow write pointer to sync
      repeat (WRITE_DELAY) @(posedge rclk);
    end
  endtask

  // Task: read one word, with timeout & check
  task read_data(input [DATA_WIDTH-1:0] exp, output [DATA_WIDTH-1:0] got);
    begin
      timeout_cnt = 0;
      // wait until not empty or timeout
      while (empty && timeout_cnt < TIMEOUT) begin
        @(posedge rclk);
        timeout_cnt = timeout_cnt + 1;
      end
      if (timeout_cnt == TIMEOUT) begin
        $display("[ERROR] read_data timeout waiting for !empty");
        test_pass = 0;
        disable read_data;
      end

      // assert read
      @(posedge rclk);
      r_en = 1;
      @(posedge rclk);
      got = dataout;
      r_en = 0;
      $display("[ READ] @%0t : %02h (expected %02h)", $time, got, exp);

      // check match
      if (got !== exp) begin
        $display("[FAIL ] Mismatch: got %02h, expected %02h", got, exp);
        test_pass = 0;
      end

      // allow read pointer to sync
      repeat (READ_DELAY) @(posedge wclk);
    end
  endtask

  // Main test sequence
  initial begin
    wait(wrst_n && rrst_n);

    // Test 1: Sequential write/read
    $display("\n=== TEST 1: SEQUENTIAL WRITE/READ ===");
    write_data(8'h24);
    write_data(8'h81);
    write_data(8'h09);
    read_data (8'h24, received);
    read_data (8'h81, received);
    read_data (8'h09, received);

    // Test 2: Fill then empty FIFO
    $display("\n=== TEST 2: FILL/EMPTY FIFO ===");
    for (i = 0; i < DEPTH; i = i+1)
      write_data(i);
    for (i = 0; i < DEPTH; i = i+1)
      read_data(i, received);

    // Report result
    if (test_pass)
      $display("\n*** ALL TESTS PASSED ***");
    else
      $display("\n*** TESTS FAILED ***");

    #100 $finish;
  end

endmodule
