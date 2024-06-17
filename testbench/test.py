import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, FallingEdge, RisingEdge

@cocotb.test()
async def test_dram_controller(dut):
	dut._log.info("Start")
	dut.CEb.value = 1
	dut.WEb.value = 1
	dut.addr.value = 0
	clock = Clock(dut.clk, 11.76, units="ns")
	cocotb.start_soon(clock.start())
	dut.reset.value = 0
	await Timer(20, units="ns")
	dut.reset.value = 1
	await Timer(20, units="ns")

	while dut.init_done.value != 0:
		await Timer(250, units="ns")
		
	dut._log.info("Init done")
	dut._log.info("Letting it sit in refresh for a bit...")
	await Timer(2500, units="ns")
	
	# Write data into the same row, ensuring this tests lasts long enough
	# for the controller to HAVE to go do a refresh
	dut._log.info("Sequential writes")
	test_data = [36, 0x69, 222, 0, 255, 10, 0x88, 0x10, 22, 101, 102]
	dut.WEb.value = 0
	for i in range(0,11):
		dut.addr.value = i
		dut.din.value = test_data[i]
		dut.CEb.value = 0
		await ClockCycles(dut.clk, 58)
		dut.CEb.value = 1
		await ClockCycles(dut.clk, 38)
	dut.WEb.value = 1
	await ClockCycles(dut.clk, 10)
	
	# Now read the data back, once again taking a while
	dut._log.info("Sequential reads")
	for i in range(0,11):
		dut.addr.value = i
		dut.CEb.value = 0;
		await ClockCycles(dut.clk, 58)
		assert dut.dout.value == test_data[i]
		dut.CEb.value = 1
		await ClockCycles(dut.clk, 38)
	await ClockCycles(dut.clk, 550)
	
	# Now repeat the above test, but go as fast as possible on the reads and writes
	dut._log.info("Fast sequential writes")
	dut.WEb.value = 0
	for i in range(0,11):
		dut.addr.value = i<<1
		dut.din.value = test_data[i]
		dut.CEb.value = 0
		await ClockCycles(dut.clk, 4)
		while dut.ready.value != 1:
			await ClockCycles(dut.clk, 2)
		dut.CEb.value = 1
		await ClockCycles(dut.clk, 2)
	dut.WEb.value = 1
	
	dut._log.info("Fast sequential reads")
	for i in range(0,11):
		dut.addr.value = i<<1
		dut.CEb.value = 0
		await ClockCycles(dut.clk, 4)
		while dut.ready.value != 1:
			await ClockCycles(dut.clk, 2)
		assert dut.dout.value == test_data[i]
		dut.CEb.value = 1
		await ClockCycles(dut.clk, 2)
	await ClockCycles(dut.clk, 550)
	
	dut._log.info("Random writes")
	random_addresses = [36, 2768000, 2768128, 30000, 60000, 60001, 60002, 0, 102, 101, 100000]
	dut.WEb.value = 0
	for i in range(0,11):
		dut.addr.value = random_addresses[i]
		dut.din.value = test_data[i]
		dut.CEb.value = 0
		await ClockCycles(dut.clk, 4)
		while dut.ready.value != 1:
			await ClockCycles(dut.clk, 2)
		dut.CEb.value = 1
		await ClockCycles(dut.clk, 2)
	dut.WEb.value = 1
	
	dut._log.info("Random reads")
	for i in range(0,11):
		dut.addr.value = random_addresses[i]
		dut.CEb.value = 0
		await ClockCycles(dut.clk, 4)
		while dut.ready.value != 1:
			await ClockCycles(dut.clk, 2)
		assert dut.dout.value == test_data[i]
		dut.CEb.value = 1
		await ClockCycles(dut.clk, 2)
	await ClockCycles(dut.clk, 50)

	dut._log.info("Done.")
