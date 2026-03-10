// sim/filelist.f — Compile order for APB UVM verification project

// RTL (DUT)
../rtl/apb_slave.sv

// Interface
../tb/apb_if.sv

// Assertions
../tb/apb_assertions.sv

// Top-level testbench (includes all UVM class files via `include)
../tb/tb_top.sv
