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
//--------------------------------------------------------------
// File: rtl/apb_slave.sv
// Description: APB slave with 4 internal 32-bit registers.
//              Combinational read path, zero wait-state.
//--------------------------------------------------------------

module apb_slave (
    input  logic        PCLK,       // APB clock
    input  logic        PRESETn,    // Active-low async reset
    input  logic        PSEL,       // Slave select
    input  logic        PENABLE,    // Enable phase indicator
    input  logic        PWRITE,     // 1 = write, 0 = read
    input  logic [31:0] PADDR,      // Address bus
    input  logic [31:0] PWDATA,     // Write data bus
    output logic [31:0] PRDATA,     // Read data bus (combinational)
    output logic        PREADY,     // Slave ready (always 1)
    output logic        PSLVERR     // Slave error (combinational)
);

    // =========================================================
    // Internal Registers
    // These are the 4 registers the slave exposes to the bus.
    // Each is 32-bit, word-aligned at 4-byte intervals.
    // =========================================================
    logic [31:0] ctrl_reg;      // Address 0x00, reset: 0x00000000
    logic [31:0] status_reg;    // Address 0x04, reset: 0x00000001
    logic [31:0] data_reg;      // Address 0x08, reset: 0x00000000
    logic [31:0] config_reg;    // Address 0x0C, reset: 0x00000000

    // =========================================================
    // PREADY: Always ready — zero wait-state slave
    // In a more complex design, PREADY could be deasserted to
    // insert wait states, but we keep it simple here.
    // =========================================================
    assign PREADY = 1'b1;

    // =========================================================
    // Transfer detection wires
    // A valid APB transfer occurs when PSEL and PENABLE are
    // both high (the enable phase). PWRITE distinguishes
    // between read and write operations.
    // =========================================================
    wire apb_write = PSEL & PENABLE & PWRITE;   // Write transfer active
    wire apb_read  = PSEL & PENABLE & ~PWRITE;  // Read transfer active

    // =========================================================
    // Address validity check
    // Only 4 addresses are valid in our register map.
    // Anything else is an illegal access.
    // =========================================================
    wire valid_addr = (PADDR == 32'h00) || (PADDR == 32'h04) ||
                      (PADDR == 32'h08) || (PADDR == 32'h0C);

    // =========================================================
    // WRITE LOGIC (Clocked)
    // Registers update on the clock edge during the enable phase.
    // Only valid addresses cause a register write.
    // =========================================================
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            // Asynchronous reset — all registers go to defined values
            ctrl_reg   <= 32'h0000_0000;
            status_reg <= 32'h0000_0001;  // NOTE: STATUS resets to 1, not 0
            data_reg   <= 32'h0000_0000;
            config_reg <= 32'h0000_0000;
        end else if (apb_write && valid_addr) begin
            // Decode address and write to the correct register
            case (PADDR[3:0])
                4'h0: ctrl_reg   <= PWDATA;
                4'h4: status_reg <= PWDATA;
                4'h8: data_reg   <= PWDATA;
                4'hC: config_reg <= PWDATA;
                default: ;  // Should not reach here due to valid_addr check
            endcase
        end
    end

    // =========================================================
    // READ LOGIC (Combinational)
    // PRDATA is driven combinationally so it's valid during the
    // enable phase — no extra clock cycle delay. This makes
    // the monitor's job much simpler.
    // =========================================================
    always_comb begin
        PRDATA = 32'h0000_0000;  // Default: zero
        if (apb_read) begin
            if (valid_addr) begin
                case (PADDR[3:0])
                    4'h0: PRDATA = ctrl_reg;
                    4'h4: PRDATA = status_reg;
                    4'h8: PRDATA = data_reg;
                    4'hC: PRDATA = config_reg;
                    default: PRDATA = 32'h0;
                endcase
            end
            // Invalid address: PRDATA stays at default 0
        end
    end

    // =========================================================
    // PSLVERR LOGIC (Combinational)
    // Error flag asserts during any active transfer to an
    // invalid address. Deasserts when bus is idle.
    // =========================================================
    assign PSLVERR = (PSEL & PENABLE) ? ~valid_addr : 1'b0;

endmodule
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
