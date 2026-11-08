bind async_fifo async_fifo_sva #(
    .DATA_W (DATA_W),
    .DEPTH  (DEPTH)
) u_async_fifo_sva (
    .wclk      (wclk),
    .wrst_n    (wrst_n),
    .winc      (winc),
    .wdata     (wdata),
    .wfull     (wfull),

    .rclk      (rclk),
    .rrst_n    (rrst_n),
    .rinc      (rinc),
    .rdata     (rdata),
    .rempty    (rempty),

    .wptr_bin  (wptr_bin),
    .wptr_gray (wptr_gray),
    .rptr_bin  (rptr_bin),
    .rptr_gray (rptr_gray)
);
