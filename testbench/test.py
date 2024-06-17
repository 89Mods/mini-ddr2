import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

@cocotb.test()
async def test_dram_controller(dut):
	dut._log.info("Start")
	dut.CEb.value = 1
	dut.WEb.value = 1
	dut.addr.value = 0
	clock = Clock(dut.clk, 12.5, units="ns")
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
	
	dut._log.info("Trying a write")
	dut.addr.value = 0
	dut.din.value = 36
	dut.CEb.value = 0
	dut.WEb.value = 0
	await ClockCycles(dut.clk, 256)
	dut.CEb.value = 1
	await ClockCycles(dut.clk, 256)
	
	dut._log.info("Trying a write")
	dut.addr.value = 1
	dut.din.value = 0x69
	dut.CEb.value = 0
	dut.WEb.value = 0
	await ClockCycles(dut.clk, 256)
	dut.CEb.value = 1
	await ClockCycles(dut.clk, 256)
	dut.WEb.value = 1
	
	dut._log.info("Trying a read")
	dut.addr.value = 0
	dut.CEb.value = 0
	await ClockCycles(dut.clk, 6)
	await ClockCycles(dut.clk, 32)
	assert dut.dout.value == 36
	dut.CEb.value = 1
	await ClockCycles(dut.clk, 16)
	
	dut._log.info("Trying a read")
	dut.addr.value = 1
	dut.CEb.value = 0
	await ClockCycles(dut.clk, 32)
	await ClockCycles(dut.clk, 32)
	assert dut.dout.value == 0x69
	dut.CEb.value = 1

	dut._log.info("Done.")
