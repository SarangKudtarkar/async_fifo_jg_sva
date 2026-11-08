clear -all

analyze -sv12 \
    rtl/async_fifo.sv \
    formal/async_fifo_sva.sv \
    formal/async_fifo_bind.sv

# DUT is the top; checker comes in through the bind
elaborate -top async_fifo

# two independent clocks (no fixed phase / frequency relation)
clock wclk
clock rclk

# JG needs a simple reset expression (no || / &&). rrst_n is tied to
# wrst_n by the m_reset_sync_* assumes in the checker, so one pin is enough.
reset -expression {!wrst_n}

# proves asserts and checks reachability of covers
prove -all

report -summary
report -results
