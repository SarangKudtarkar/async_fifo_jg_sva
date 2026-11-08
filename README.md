# Async FIFO Formal Verification (JasperGold SVA style)

Dual-clock FIFO (gray pointers, 2-FF synchronizers) plus a bound SVA checker.
Extends the sync FIFO example in fifo_jg_sva.

## Files

- rtl/async_fifo.sv                DUT (DEPTH: power of two, >= 4)
- formal/async_fifo_sva.sv         SVA checker (assert / assume / cover + scoreboard)
- formal/async_fifo_bind.sv        bind of checker into async_fifo
- scripts/async_fifo_formal.tcl    JasperGold script

## Run

From the repository root:

    jg scripts/async_fifo_formal.tcl   (or: jg, then source scripts/async_fifo_formal.tcl)

## What is checked

- Pointers: advance only on accepted write / read, stable otherwise.
- Gray coding: encoding matches binary, at most one bit changes per cycle
  (the property that makes the synchronizers safe).
- Occupancy (reference view wptr_bin - rptr_bin): never exceeds DEPTH.
- Flags are conservative: occupancy == DEPTH implies wfull, occupancy == 0
  implies rempty. They may assert early, never late.
- Data integrity and ordering: a symbolic data value tagged on its first write
  must come out when the read pointer reaches that slot.

## Notes

- Both clocks are free and unrelated. JasperGold treats separately declared
  clocks as asynchronous, so the synchronizers are modelled as plain flops.
- Resets are constrained to assert and release together
  (m_reset_sync_*). Relax this if you want to study independent resets.
- sym_data is an undriven signal in the checker, treated as a free input and
  constrained with $stable assumes (symbolic constant).
- rdata is combinational from memory, so the integrity assert compares in the
  same cycle as the accepted read (unlike the sync FIFO's registered output).
- Spurious behaviour: wfull / rempty can only rise after a local accepted
  write / read (synchronized pointers only move forward), and the symbolic
  data value can only be read after it was written. A flag may lag
  (stay high although occupancy says otherwise) but must clear.
- Forward progress (liveness): wfull / rempty always clear, stale flags
  clear, and a written item is eventually read. These rely on the
  fairness assumes m_rinc_fair / m_winc_fair and on both clocks ticking
  infinitely often. Use JG liveness engines; these take longer than the
  safety asserts.
- Review the cover results first: a vacuous cover means the assertions
  are not exercising the interesting behavior. c_wfull_stale and
  c_rempty_stale show the stale-flag case is actually reachable.

## Extensions worth trying

- Break the design on purpose (binary pointer sync, wrong full compare,
  flag that never clears) and confirm the checker catches it.
