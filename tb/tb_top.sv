//--------------------------------------------------------------
// File: tb/tb_top.sv
// Description: Top-level testbench module — simulation entry point.
//
// WHAT THIS FILE DOES:
//   1. Generates clock (100 MHz, 10ns period)
//   2. Generates reset (active-low, held for 5 clock cycles)
//   3. Instantiates the APB interface
//   4. Instantiates the DUT and connects it to the interface
//   5. Instantiates the assertion module
//   6. Passes the virtual interface to UVM via config_db
//   7. Calls run_test() to start the UVM test
//   8. Provides a timeout safety net
//
// NOTE: All UVM class files are included via `include directives.
//       This means tb_top.sv must be compiled AFTER all the
//       class files, OR the includes must be in dependency order.
//--------------------------------------------------------------

`timescale 1ns/1ps

// Import UVM base library
import uvm_pkg::*;
`include "uvm_macros.svh"

// Include all UVM class files in dependency order
// (Each file depends on the ones above it)
`include "apb_seq_item.sv"
`include "apb_sequencer.sv"
`include "apb_driver.sv"
`include "apb_monitor.sv"
`include "apb_agent.sv"
`include "apb_scoreboard.sv"
`include "apb_env.sv"
`include "apb_sequences.sv"
`include "apb_test.sv"

module tb_top;

    // =========================================================
    // CLOCK AND RESET
    // =========================================================
    logic PCLK;
    logic PRESETn;

    // Clock: 100 MHz (10ns period, toggle every 5ns)
    initial PCLK = 0;
    always #5 PCLK = ~PCLK;

    // =========================================================
    // INTERFACE INSTANTIATION
    // =========================================================
    apb_if vif(.PCLK(PCLK), .PRESETn(PRESETn));

    // =========================================================
    // DUT INSTANTIATION
    // Connect DUT ports to interface signals
    // =========================================================
    apb_slave dut (
        .PCLK     (PCLK),
        .PRESETn  (PRESETn),
        .PSEL     (vif.PSEL),
        .PENABLE  (vif.PENABLE),
        .PWRITE   (vif.PWRITE),
        .PADDR    (vif.PADDR),
        .PWDATA   (vif.PWDATA),
        .PRDATA   (vif.PRDATA),
        .PREADY   (vif.PREADY),
        .PSLVERR  (vif.PSLVERR)
    );

    // =========================================================
    // ASSERTIONS MODULE INSTANTIATION
    // Monitors the same signals as the DUT for protocol checks
    // =========================================================
    apb_assertions apb_assert_inst (
        .PCLK     (PCLK),
        .PRESETn  (PRESETn),
        .PSEL     (vif.PSEL),
        .PENABLE  (vif.PENABLE),
        .PWRITE   (vif.PWRITE),
        .PADDR    (vif.PADDR),
        .PWDATA   (vif.PWDATA),
        .PRDATA   (vif.PRDATA),
        .PREADY   (vif.PREADY),
        .PSLVERR  (vif.PSLVERR)
    );

    // =========================================================
    // RESET GENERATION
    // Hold reset for 5 clock cycles, initialize bus to idle
    // =========================================================
    initial begin
        PRESETn     = 1'b0;    // Assert reset (active low)
        vif.PSEL    = 1'b0;    // Bus idle
        vif.PENABLE = 1'b0;
        vif.PWRITE  = 1'b0;
        vif.PADDR   = 32'h0;
        vif.PWDATA  = 32'h0;
        repeat (5) @(posedge PCLK);  // Hold reset for 5 clocks
        PRESETn = 1'b1;               // Release reset
        `uvm_info("TB_TOP", "Reset released", UVM_LOW)
    end

    // =========================================================
    // UVM LAUNCH
    // Pass virtual interface to all UVM components via config_db,
    // then start the test specified by +UVM_TESTNAME plusarg
    // =========================================================
    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", vif);
        run_test();  // Test name comes from +UVM_TESTNAME=<name>
    end

    // =========================================================
    // TIMEOUT SAFETY NET
    // If a test forgets to drop its objection, this prevents
    // the simulation from running forever
    // =========================================================
    initial begin
        #100us;
        `uvm_fatal("TB_TOP", "Simulation timeout: test did not finish in 100 us")
    end

endmodule
