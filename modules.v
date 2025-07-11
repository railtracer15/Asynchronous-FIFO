`timescale 1ns / 1ps
module tfsync#(parameter WIDTH = 3)(
    input [WIDTH:0] din,
    input clk,
    input rst,
    output reg [WIDTH:0] dout
);
    reg [WIDTH:0] dmeta1, dmeta2;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            dmeta1 <= 0;
            dmeta2 <= 0;
            dout <= 0;
        end else begin
            dmeta1 <= din;
            dmeta2 <= dmeta1;
            dout <= dmeta2;
        end
    end
endmodule


module wptr_handler #(parameter WIDTH = 3)(
    input wclk, wrst, w_en,
    input [WIDTH:0] g_rptr_sync,
    output reg [WIDTH:0] b_wptr,
    output reg [WIDTH:0] g_wptr,
    output reg full
    );
    
    wire [WIDTH:0] b_wptr_nxt;
    wire [WIDTH:0] g_wptr_nxt;
    wire w_full;
    
    assign b_wptr_nxt = b_wptr + (w_en & !full);
    assign g_wptr_nxt = b_wptr_nxt ^ (b_wptr_nxt>>1);
    
    always @(posedge wclk or negedge wrst) begin
        if (!wrst) begin
            b_wptr <= 0;
            g_wptr <= 0;
        end
        
        else begin
            b_wptr <= b_wptr_nxt;
            g_wptr <= g_wptr_nxt;
        end
    end
    
    assign w_full = (g_wptr_nxt == ({~(g_rptr_sync[WIDTH:WIDTH-1]), g_rptr_sync[WIDTH-2:0]}));
    
    always @(posedge wclk or negedge wrst) begin
        if (!wrst) full <= 0;
        else full <= w_full;
    end
endmodule

module rptr_handler #(parameter WIDTH=3)(
    input rclk, rrst, r_en,
    input [WIDTH:0] g_wptr_sync,
    output reg [WIDTH:0] b_rptr,
    output reg [WIDTH:0] g_rptr,
    output reg empty);
    
    wire [WIDTH:0] b_rptr_nxt;
    wire [WIDTH:0] g_rptr_nxt;
    wire r_emp;
    
    assign b_rptr_nxt = b_rptr + (r_en & !empty);
    assign g_rptr_nxt = b_rptr_nxt ^ (b_rptr_nxt >> 1);
    assign r_emp = (g_wptr_sync == g_rptr_nxt);
    
    always @(posedge rclk or negedge rrst) begin
        if (!rrst) begin
            b_rptr <= 0;
            g_rptr <= 0;
        end
        
        else begin
            b_rptr <= b_rptr_nxt;
            g_rptr <= g_rptr_nxt;
        end
    end
    
    always @(posedge rclk or negedge rrst) begin
        if (!rrst) empty <= 1;
        else empty <= r_emp;
    end
endmodule

module fifo #(parameter DEPTH = 8, DATA_WIDTH = 8, PTR_WIDTH = 3)(
    input wclk, w_en, rclk, r_en,
    input rrst_n, // Deal with classsic error
    input [PTR_WIDTH:0] b_wptr, b_rptr,
    input [DATA_WIDTH-1:0] data_in,
    input full, empty,
    output reg [DATA_WIDTH-1:0] data_out);
    
    reg [DATA_WIDTH-1:0] FIFO[0:DEPTH-1];
    
    always @(posedge wclk) begin
        if (w_en & !full) 
            FIFO[b_wptr[PTR_WIDTH-1:0]] <= data_in;
    end
    
    reg read_valid;

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            data_out <= 0;
            read_valid <= 0;
        end else begin
            if (r_en && !empty) begin
                data_out <= FIFO[b_rptr[PTR_WIDTH-1:0]];
                read_valid <= 1;
            end else begin
                read_valid <= 0;
            end
        end
    end


endmodule


module asynchronous_fifo #(
    parameter DEPTH      = 8,
    parameter DATA_WIDTH = 8,
    parameter PTR_WIDTH  = 3
)(
    input                    wclk,
    input                    wrst_n,
    input                    rclk,
    input                    rrst_n,
    input                    w_en,
    input                    r_en,
    input  [DATA_WIDTH-1:0]  data_in,
    output [DATA_WIDTH-1:0]  data_out,
    output                   full,
    output                   empty
);

    // raw (binary) pointers
    wire [PTR_WIDTH:0] b_wptr, b_rptr;
    // gray-coded pointers
    wire [PTR_WIDTH:0] g_wptr, g_rptr;
    // synchronized versions
    wire [PTR_WIDTH:0] g_wptr_sync, g_rptr_sync;

    //── Write pointer → Read clock domain ────────────────────────────
    //  We take the write-domain gray pointer (g_wptr)
    //  and synchronize it into the read clock domain (rclk).
    tfsync #(.WIDTH(PTR_WIDTH)) sync_wptr (
        .din  (g_wptr),
        .clk  (rclk),       // <- read clock
        .rst  (rrst_n),
        .dout (g_wptr_sync)
    );

    //── Read pointer → Write clock domain ────────────────────────────
    //  We take the read-domain gray pointer (g_rptr)
    //  and synchronize it into the write clock domain (wclk).
    tfsync #(.WIDTH(PTR_WIDTH)) sync_rptr (
        .din  (g_rptr),
        .clk  (wclk),       // <- write clock
        .rst  (wrst_n),
        .dout (g_rptr_sync)
    );

    //── Write Pointer & Full Flag ────────────────────────────────────
    wptr_handler #(.WIDTH(PTR_WIDTH)) wptr_h (
        .wclk        (wclk),
        .wrst        (wrst_n),
        .w_en        (w_en),
        .g_rptr_sync (g_rptr_sync),
        .b_wptr      (b_wptr),
        .g_wptr      (g_wptr),
        .full        (full)
    );

    //── Read Pointer & Empty Flag ────────────────────────────────────
    rptr_handler #(.WIDTH(PTR_WIDTH)) rptr_h (
        .rclk        (rclk),
        .rrst        (rrst_n),
        .r_en        (r_en),
        .g_wptr_sync (g_wptr_sync),
        .b_rptr      (b_rptr),
        .g_rptr      (g_rptr),
        .empty       (empty)
    );

    //── Dual-Port FIFO Memory ────────────────────────────────────────
    fifo #(
        .DEPTH      (DEPTH),
        .DATA_WIDTH (DATA_WIDTH),
        .PTR_WIDTH  (PTR_WIDTH)
    ) fifom (
        .wclk     (wclk),
        .w_en     (w_en),
        .rclk     (rclk),
        .r_en     (r_en),
        .rrst_n   (rrst_n),
        .b_wptr   (b_wptr),
        .b_rptr   (b_rptr),
        .data_in  (data_in),
        .full     (full),
        .empty    (empty),
        .data_out (data_out)
    );

endmodule

