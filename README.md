# mini-ddr2

DDR2 Memory Controller fit into a 1€ MAX II CPLD with just 240 LUs. Its incredibly slow, but works!

Currently only works with x4 DRAMs. To demonstrate basic functionality, the CPLD is programmed to respond to byte-wide reads/writes on a "flat" address/data bus. ``A_f`` are the 24 address lines, ``Q_f`` is the data bus. Operation is controlled via ``WEb_f`` and ``CS_f`` (not to be confused with the similarly-named DDR2 signals). A ``ready`` output indicates if the last read/write request has completed processing.

# Implementation Details

After releasing the reset input, the CPLD runs through the DDR2 initialization sequence. Slowly. I optimized it for size, not speed, so it takes several tens of thousands of clock cycles to complete. Once it does, the controller enters the main state machine.

## Idle

The controller idles by spamming refresh commands to the DDR2 as fast as it can, which is only interrupted by a falling edge on the ``CS_f`` input, which it recognizes at the end of the current refresh by moving on to the next state. ``ready`` immediately goes low when ``CS_f`` does.

## Activate

The input address, ``A_f``, is split into row, column and bank addresses and a ACTIVATE command is sent to the DDR2 to select the bank and row. The controller then hits the only fork in its state machine depending on the state of ``WEb_f``.

## Read

A READ with auto-precharge is sent to the DDR2 and a byte is read from the first two nibbles transmitted and presented on ``Q_f`` while the controller returns to the idle state. ``ready`` goes high. The read data continues to be visible on ``Q_f`` until ``CS_f`` goes high.

## Write

A WRITE with auto-precharge is sent to the DDR2 and a byte stored into the first two nibbles (controlled via DM). Afterwards, the controller returns to the idle state. ``ready`` goes high.

# Speed

This thing is slow. Real slow. This is due to several factors:

* The CPLD does not make timings above 80MHz
* The CPLD clock is divided by two to obtain the DDR2 clock (40MHz)
* A precharge is run after every individual read and write, even if they’re in the same row, due to the simplistic state machine
* ``CS_f`` is only recognized at the conclusion of the current refresh cycle, which may be as many as 5 clocks.

I am hoping to improve this in the future.
