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
