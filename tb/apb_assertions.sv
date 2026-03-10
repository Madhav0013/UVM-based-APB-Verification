//--------------------------------------------------------------
// File: tb/apb_assertions.sv
// Description: APB protocol assertions (SVA).
//              These check protocol correctness independently
//              of the scoreboard — they fire on every clock edge.
//
// ASSERTIONS INCLUDED:
//   1. PENABLE requires PSEL
//   2. Setup phase must precede enable phase
//   3. Address must remain stable during transfer
//   4. PWRITE must remain stable during transfer
//   5. PWDATA must remain stable during write transfer
//   6. Invalid address must raise PSLVERR
//   7. Valid address must NOT raise PSLVERR
//
// NOTE: All assertions are disabled during reset (disable iff)
//       because signal values are undefined during reset.
//--------------------------------------------------------------

module apb_assertions (
    input logic        PCLK,
    input logic        PRESETn,
    input logic        PSEL,
    input logic        PENABLE,
    input logic        PWRITE,
    input logic [31:0] PADDR,
    input logic [31:0] PWDATA,
    input logic [31:0] PRDATA,
    input logic        PREADY,
    input logic        PSLVERR
);

    // --- Assertion 1: PENABLE requires PSEL ---
    // APB spec: PENABLE should never be high if PSEL is low
    property p_enable_requires_sel;
        @(posedge PCLK) disable iff (!PRESETn)
        PENABLE |-> PSEL;
    endproperty
    a_enable_requires_sel: assert property (p_enable_requires_sel)
        else $error("APB VIOLATION: PENABLE=1 while PSEL=0");

    // --- Assertion 2: Setup before Enable ---
    // When PENABLE rises, the previous cycle must have had
    // PSEL=1 and PENABLE=0 (i.e., a proper setup phase)
    property p_setup_before_enable;
        @(posedge PCLK) disable iff (!PRESETn)
        $rose(PENABLE) |-> $past(PSEL) && !$past(PENABLE);
    endproperty
    a_setup_before_enable: assert property (p_setup_before_enable)
        else $error("APB VIOLATION: Enable without preceding setup");

    // --- Assertion 3: Address stability ---
    // PADDR must not change from setup to enable phase
    property p_addr_stable;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && !PENABLE) ##1 (PSEL && PENABLE) |-> $stable(PADDR);
    endproperty
    a_addr_stable: assert property (p_addr_stable)
        else $error("APB VIOLATION: PADDR changed during transfer");

    // --- Assertion 4: PWRITE stability ---
    // PWRITE must not change from setup to enable phase
    property p_pwrite_stable;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && !PENABLE) ##1 (PSEL && PENABLE) |-> $stable(PWRITE);
    endproperty
    a_pwrite_stable: assert property (p_pwrite_stable)
        else $error("APB VIOLATION: PWRITE changed during transfer");

    // --- Assertion 5: PWDATA stability during writes ---
    // PWDATA must not change during a write transfer
    property p_wdata_stable;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && !PENABLE && PWRITE) ##1 (PSEL && PENABLE) |-> $stable(PWDATA);
    endproperty
    a_wdata_stable: assert property (p_wdata_stable)
        else $error("APB VIOLATION: PWDATA changed during write");

    // --- Address validity wire (used by assertions 6 and 7) ---
    wire valid_addr = (PADDR == 32'h00) || (PADDR == 32'h04) ||
                      (PADDR == 32'h08) || (PADDR == 32'h0C);

    // --- Assertion 6: Invalid address must raise PSLVERR ---
    property p_invalid_addr_error;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && PREADY && !valid_addr) |-> PSLVERR;
    endproperty
    a_invalid_addr_error: assert property (p_invalid_addr_error)
        else $error("APB VIOLATION: Invalid addr no PSLVERR");

    // --- Assertion 7: Valid address must NOT raise PSLVERR ---
    property p_valid_addr_no_error;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && PREADY && valid_addr) |-> !PSLVERR;
    endproperty
    a_valid_addr_no_error: assert property (p_valid_addr_no_error)
        else $error("APB VIOLATION: Valid addr raised PSLVERR");

endmodule
