module async_fifo_sva #(
    parameter DATA_W = 8,
    parameter DEPTH  = 8,
    parameter PTR_W  = $clog2(DEPTH)
)(
    input logic              wclk,
    input logic              wrst_n,
    input logic              winc,
    input logic [DATA_W-1:0] wdata,
    input logic              wfull,

    input logic              rclk,
    input logic              rrst_n,
    input logic              rinc,
    input logic [DATA_W-1:0] rdata,
    input logic              rempty,

    input logic [PTR_W:0]    wptr_bin,
    input logic [PTR_W:0]    wptr_gray,
    input logic [PTR_W:0]    rptr_bin,
    input logic [PTR_W:0]    rptr_gray
);

    // ----------------------------------------------
    // Helper signals
    // ----------------------------------------------
    logic w_acc;
    logic r_acc;

    assign w_acc = winc && !wfull;
    assign r_acc = rinc && !rempty;

    // true occupancy (reference view across both domains)
    logic [PTR_W:0] occ;
    assign occ = wptr_bin - rptr_bin;

    // ----------------------------------------------
    // Environment assumptions
    // Both resets are asserted / released together.
    // ----------------------------------------------
    m_reset_sync_w: assume property (@(posedge wclk) wrst_n == rrst_n);
    m_reset_sync_r: assume property (@(posedge rclk) wrst_n == rrst_n);

    // ----------------------------------------------
    // Write-domain pointer properties
    // ----------------------------------------------
    a_w_ptr_inc: assert property (
        @(posedge wclk) disable iff (!wrst_n)
        w_acc |=> wptr_bin == $past(wptr_bin) + 1'b1
    );

    a_w_ptr_hold: assert property (
        @(posedge wclk) disable iff (!wrst_n)
        !w_acc |=> $stable(wptr_bin)
    );

    a_w_gray_enc: assert property (
        @(posedge wclk) disable iff (!wrst_n)
        wptr_gray == ((wptr_bin >> 1) ^ wptr_bin)
    );

    // gray property that makes the CDC safe: at most one bit changes
    a_w_gray_onehot: assert property (
        @(posedge wclk) disable iff (!wrst_n)
        1'b1 |=> $onehot0(wptr_gray ^ $past(wptr_gray))
    );

    // ----------------------------------------------
    // Read-domain pointer properties
    // ----------------------------------------------
    a_r_ptr_inc: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        r_acc |=> rptr_bin == $past(rptr_bin) + 1'b1
    );

    a_r_ptr_hold: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        !r_acc |=> $stable(rptr_bin)
    );

    a_r_gray_enc: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        rptr_gray == ((rptr_bin >> 1) ^ rptr_bin)
    );

    a_r_gray_onehot: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        1'b1 |=> $onehot0(rptr_gray ^ $past(rptr_gray))
    );

    // ----------------------------------------------
    // Occupancy / flag properties
    // wfull / rempty are conservative: they may assert early
    // (stale synchronized pointer) but never late.
    // ----------------------------------------------
    a_occ_le_depth_w: assert property (
        @(posedge wclk) disable iff (!wrst_n)
        occ <= DEPTH
    );

    a_occ_le_depth_r: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        occ <= DEPTH
    );

    a_full_conservative: assert property (
        @(posedge wclk) disable iff (!wrst_n)
        (occ == DEPTH) |-> wfull
    );

    a_empty_conservative: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        (occ == 0) |-> rempty
    );

    // ----------------------------------------------
    // Data integrity / ordering scoreboard
    //
    // sym_data is an undriven signal (free input in JG), made a
    // symbolic constant with $stable assumes in both domains.
    // The first accepted write of sym_data records its write
    // pointer (tag_idx). The first accepted read at that pointer
    // must return sym_data (rdata is combinational from memory).
    // Because the match is by pointer position, this checks both
    // data integrity and FIFO ordering for any data value.
    // ----------------------------------------------
    logic [DATA_W-1:0] sym_data;

    m_sym_stable_w: assume property (@(posedge wclk) $stable(sym_data));
    m_sym_stable_r: assume property (@(posedge rclk) $stable(sym_data));

    logic            tag_seen;     // write domain
    logic [PTR_W:0]  tag_idx;    // write domain
    logic            rd_done;    // read domain

    logic tag_push;
    logic tag_pop;

    assign tag_push = w_acc && (wdata == sym_data) && !tag_seen;
    assign tag_pop  = tag_seen && !rd_done && r_acc && (rptr_bin == tag_idx);

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            tag_seen <= 1'b0;
            tag_idx <= '0;
        end
        else if (tag_push) begin
            tag_seen <= 1'b1;
            tag_idx <= wptr_bin;
        end
    end

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n)
            rd_done <= 1'b0;
        else if (tag_pop)
            rd_done <= 1'b1;
    end

    // Helper invariant (aids convergence): the tagged entry is still
    // inside the FIFO until it is popped.
    a_tag_in_fifo: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        (tag_seen && !rd_done) |-> ((tag_idx - rptr_bin) < occ)
    );

    a_data_integrity: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        tag_pop |-> (rdata == sym_data)
    );

    // ----------------------------------------------
    // Spurious behaviour (nothing happens without a cause)
    //
    // The synchronized pointers only ever move forward, so a flag can
    // only RISE because of a local accepted operation. It may stay
    // high longer than needed (stale view), but must clear (see
    // forward progress below).
    // ----------------------------------------------
    a_wfull_needs_write: assert property (
        @(posedge wclk) disable iff (!wrst_n)
        $rose(wfull) |-> $past(w_acc)
    );

    a_rempty_needs_read: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        $rose(rempty) |-> $past(r_acc)
    );

    // No spurious data: the symbolic value can only come out of an
    // accepted read after it was accepted by a write
    a_no_spurious_data: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        (r_acc && (rdata == sym_data)) |-> tag_seen
    );

    // ----------------------------------------------
    // Forward progress (liveness, needs JG liveness engines)
    //
    // Clocks are free-running (both tick infinitely often). Fairness:
    // the consumer reads / the producer writes infinitely often.
    // ----------------------------------------------
    m_rinc_fair: assume property (@(posedge rclk) always (s_eventually rinc));
    m_winc_fair: assume property (@(posedge wclk) always (s_eventually winc));

    // A stale flag (asserted although occupancy says otherwise) must clear
    a_wfull_stale_clears: assert property (
        @(posedge wclk) disable iff (!wrst_n)
        (wfull && (occ < DEPTH)) |-> s_eventually !wfull
    );

    a_rempty_stale_clears: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        (rempty && (occ > 0)) |-> s_eventually !rempty
    );

    // A full FIFO drains, an empty FIFO fills
    a_wfull_clears: assert property (
        @(posedge wclk) disable iff (!wrst_n)
        wfull |-> s_eventually !wfull
    );

    a_rempty_clears: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        rempty |-> s_eventually !rempty
    );

    // A written item is never stranded: it is eventually read out
    a_tag_delivered: assert property (
        @(posedge rclk) disable iff (!rrst_n)
        (tag_seen && !rd_done) |-> s_eventually rd_done
    );

    // ----------------------------------------------
    // Cover properties (reachability / vacuity checks)
    // ----------------------------------------------
    c_wfull:            cover property (@(posedge wclk) disable iff (!wrst_n) wfull);
    c_wfull_recovers:   cover property (@(posedge wclk) disable iff (!wrst_n) wfull ##[1:$] !wfull);
    c_wr_when_full:     cover property (@(posedge wclk) disable iff (!wrst_n) winc && wfull);
    c_occ_full:         cover property (@(posedge wclk) disable iff (!wrst_n) occ == DEPTH);

    c_rempty_after_use: cover property (@(posedge rclk) disable iff (!rrst_n) r_acc ##1 rempty);
    c_rd_when_empty:    cover property (@(posedge rclk) disable iff (!rrst_n) rinc && rempty);
    c_rempty_recovers:  cover property (@(posedge rclk) disable iff (!rrst_n) rempty ##[1:$] !rempty);

    c_tag_push:         cover property (@(posedge wclk) disable iff (!wrst_n) tag_push);
    c_tag_pop:          cover property (@(posedge rclk) disable iff (!rrst_n) tag_pop);
    c_tag_pop_deep:     cover property (@(posedge rclk) disable iff (!rrst_n) tag_pop && (occ > 2));

    // stale flags are reachable (non-vacuity of the spurious / liveness checks)
    c_wfull_stale:      cover property (@(posedge wclk) disable iff (!wrst_n) wfull && (occ < DEPTH));
    c_rempty_stale:     cover property (@(posedge rclk) disable iff (!rrst_n) rempty && (occ > 0));
    c_tag_delivered:    cover property (@(posedge rclk) disable iff (!rrst_n) tag_seen ##[1:$] rd_done);

endmodule
