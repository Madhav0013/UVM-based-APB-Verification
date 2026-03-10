//--------------------------------------------------------------
// File: tb/apb_if.sv
// Description: APB interface — signal bundle connecting DUT
//              to the UVM testbench components.
//
// NOTE: Clock and reset are INPUTS to this interface because
//       they are generated in tb_top.sv and shared between
//       the DUT and all verification components.
//
// NOTE: No clocking blocks are used. The driver and monitor
//       use @(posedge vif.PCLK) directly, which is simpler
//       and less error-prone for a first UVM project.
//--------------------------------------------------------------

interface apb_if (input logic PCLK, input logic PRESETn);

    // --- Bus control signals (driven by driver, sampled by monitor) ---
    logic        PSEL;       // Slave select
    logic        PENABLE;    // Enable phase indicator
    logic        PWRITE;     // Transfer direction: 1=write, 0=read

    // --- Address and data buses ---
    logic [31:0] PADDR;      // Address bus (driven by driver)
    logic [31:0] PWDATA;     // Write data (driven by driver)
    logic [31:0] PRDATA;     // Read data (driven by DUT)

    // --- Slave response signals (driven by DUT) ---
    logic        PREADY;     // Slave ready (DUT drives this)
    logic        PSLVERR;    // Slave error (DUT drives this)

endinterface
