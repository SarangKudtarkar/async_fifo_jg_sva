module async_fifo #(
    parameter DATA_W = 8,
    parameter DEPTH  = 8,
    parameter PTR_W  = $clog2(DEPTH)
)(
    // write domain
    input  logic              wclk,
    input  logic              wrst_n,
    input  logic              winc,
    input  logic [DATA_W-1:0] wdata,
    output logic              wfull,

    // read domain
    input  logic              rclk,
    input  logic              rrst_n,
    input  logic              rinc,
    output logic [DATA_W-1:0] rdata,
    output logic              rempty
);

    logic [DATA_W-1:0] mem [0:DEPTH-1];

    // pointers carry one extra (wrap) bit
    logic [PTR_W:0] wptr_bin,  wptr_gray;
    logic [PTR_W:0] rptr_bin,  rptr_gray;
    logic [PTR_W:0] wptr_bin_next, wptr_gray_next;
    logic [PTR_W:0] rptr_bin_next, rptr_gray_next;

    // synchronizers
    logic [PTR_W:0] rptr_gray_w1, rptr_gray_w2;   // rptr -> wclk domain
    logic [PTR_W:0] wptr_gray_r1, wptr_gray_r2;   // wptr -> rclk domain

    logic winc_ok, rinc_ok;
    logic wfull_next, rempty_next;

    logic [PTR_W-1:0] waddr;
    logic [PTR_W-1:0] raddr;

    assign waddr = wptr_bin[PTR_W-1:0];
    assign raddr = rptr_bin[PTR_W-1:0];

    assign rdata = mem[raddr];

    // ---------------- synchronizers ----------------
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            rptr_gray_w1 <= '0;
            rptr_gray_w2 <= '0;
        end
        else begin
            rptr_gray_w1 <= rptr_gray;
            rptr_gray_w2 <= rptr_gray_w1;
        end
    end

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            wptr_gray_r1 <= '0;
            wptr_gray_r2 <= '0;
        end
        else begin
            wptr_gray_r1 <= wptr_gray;
            wptr_gray_r2 <= wptr_gray_r1;
        end
    end

    // ---------------- write domain ----------------
    assign winc_ok        = winc && !wfull;
    assign wptr_bin_next  = wptr_bin + {{PTR_W{1'b0}}, winc_ok};
    assign wptr_gray_next = (wptr_bin_next >> 1) ^ wptr_bin_next;

    // full: next gray wptr equals rptr gray with the top two bits inverted
    assign wfull_next = (wptr_gray_next ==
                         {~rptr_gray_w2[PTR_W:PTR_W-1], rptr_gray_w2[PTR_W-2:0]});

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wptr_bin  <= '0;
            wptr_gray <= '0;
            wfull     <= 1'b0;
        end
        else begin
            wptr_bin  <= wptr_bin_next;
            wptr_gray <= wptr_gray_next;
            wfull     <= wfull_next;
        end
    end

    always_ff @(posedge wclk) begin
        if (winc_ok)
            mem[waddr] <= wdata;
    end

    // ---------------- read domain ----------------
    assign rinc_ok        = rinc && !rempty;
    assign rptr_bin_next  = rptr_bin + {{PTR_W{1'b0}}, rinc_ok};
    assign rptr_gray_next = (rptr_bin_next >> 1) ^ rptr_bin_next;

    // empty: next gray rptr equals synchronized gray wptr
    assign rempty_next = (rptr_gray_next == wptr_gray_r2);

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rptr_bin  <= '0;
            rptr_gray <= '0;
            rempty    <= 1'b1;
        end
        else begin
            rptr_bin  <= rptr_bin_next;
            rptr_gray <= rptr_gray_next;
            rempty    <= rempty_next;
        end
    end

endmodule
