SIM ?= icarus
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES += $(PWD)/tb.v $(PWD)/ddr2_model.v $(PWD)/../top.v

TOPLEVEL = tb

MODULE = test

COMPILE_ARGS += -DBENCH

include $(shell cocotb-config --makefiles)/Makefile.sim
