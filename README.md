# mini-ddr2

DDR2 Memory Controller fit into a 1€ MAX II CPLD with just 240 LUs. Its incredibly slow, but works!

Currently only works with x4 DRAMs. To demonstrate basic functionality, the CPLD is programmed to respond to byte-wide reads/writes on a "flat" address/data bus. ``A_f`` are the 24 address lines, ``Q_f`` is the data bus. Operation is controlled via ``WEb_f`` and ``CS_f`` (not to be confused with the similarly-named DDR2 signals). A ``ready`` output indicates if the last read/write request has completed processing.

# Implementation Details

After releasing the reset input, the CPLD runs through the DDR2 initialization sequence. Slowly. I optimized it for size, not speed, so it takes several tens of thousands of clock cycles to complete. Once it does, the controller enters the main state machine.

When idle, the controller spams DDR2 refresh commands as fast as it can, only interrupted by a falling edge on ``CS_f`` requesting a memory access. ``A_f`` is split into a bank, column and row address and the proper bank and column activated before the memory access.

Both reads and writes use the minimum burst length of 4, but are only byte-wide, using the first two nibbles in the burst, least-significant half first.

At the start of any read or write leaving the idle loop, the controller starts a timer, only precharging the current bank and returning to idle mode once this expires. This allows for further reads or writes to the same bank and row to be registered and processed immediatly.

If the bank or row change, a precharge and then activate are executed to switch to the new addresses. This does not reset the timer.

# Timing

Max tested clock speed for the CPLD is 85MHz. This is divided by two to arrive at the DDR2 clock of 42.5MHz. Works fine, despite violating the min clock speed for the DDR2 chip in the example by over 150MHz.

Quartus says the design does not meet timings above this clock speed. Propagation delay times begin to mess with the timing at this stage anyways.

The best-case scenario is a sequential write, taking 12 CPLD clock cycles (141ns).

The worst case is a non-sequential read requiring a switch to a different row, at 22 CPLD clock cycles (258ns).

It may be possible to improve this by playing with the timing parameters. Sadly, this design uses 240/240 LUs, so there is otherwise no more room for improvement.
