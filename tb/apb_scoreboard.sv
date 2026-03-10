//--------------------------------------------------------------
// File: tb/apb_scoreboard.sv
// Description: APB scoreboard — maintains an expected register
//              model and checks every observed transaction.
//
// HOW IT WORKS:
//   1. Receives observed transactions from monitor (via analysis port)
//   2. For WRITES to valid addresses: updates the expected model
//   3. For READS from valid addresses: compares DUT PRDATA vs expected
//   4. For INVALID addresses: verifies PSLVERR is asserted
//   5. Prints a summary in report_phase
//
// EXPECTED MODEL:
//   exp_regs[0] = CTRL   (addr 0x00, reset: 0x00000000)
//   exp_regs[1] = STATUS (addr 0x04, reset: 0x00000001)
//   exp_regs[2] = DATA   (addr 0x08, reset: 0x00000000)
//   exp_regs[3] = CONFIG (addr 0x0C, reset: 0x00000000)
//
// CRITICAL: The reset values here MUST match the DUT exactly.
//           If they don't, every read before a write will mismatch.
//--------------------------------------------------------------

class apb_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(apb_scoreboard)

    // Analysis import — receives transactions from monitor
    uvm_analysis_imp #(apb_seq_item, apb_scoreboard) analysis_export;

    // Expected register model (mirrors DUT's internal registers)
    logic [31:0] exp_regs[4];

    // Transaction counters
    int total_txns = 0;
    int pass_count = 0;
    int fail_count = 0;

    function new(string name = "apb_scoreboard", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);

        // Initialize expected model to SAME reset values as DUT
        exp_regs[0] = 32'h0000_0000;  // CTRL
        exp_regs[1] = 32'h0000_0001;  // STATUS — note: resets to 1!
        exp_regs[2] = 32'h0000_0000;  // DATA
        exp_regs[3] = 32'h0000_0000;  // CONFIG
    endfunction

    // --- Helper: convert APB address to register index ---
    // Returns -1 for invalid addresses
    function int addr_to_idx(logic [31:0] addr);
        case (addr)
            32'h00: return 0;   // CTRL
            32'h04: return 1;   // STATUS
            32'h08: return 2;   // DATA
            32'h0C: return 3;   // CONFIG
            default: return -1; // Invalid
        endcase
    endfunction

    // --- Called automatically when monitor publishes a transaction ---
    virtual function void write(apb_seq_item txn);
        int idx;
        total_txns++;
        idx = addr_to_idx(txn.paddr);

        if (idx >= 0) begin
            // ===== VALID ADDRESS =====

            // First check: valid address should NOT have PSLVERR
            if (txn.pslverr) begin
                `uvm_error("SCB", $sformatf(
                    "TXN #%0d: Valid addr 0x%0h but PSLVERR=1!",
                    total_txns, txn.paddr))
                fail_count++;
                return;
            end

            if (txn.pwrite) begin
                // WRITE: update the expected register model
                exp_regs[idx] = txn.pwdata;
                `uvm_info("SCB", $sformatf(
                    "TXN #%0d: WRITE addr=0x%0h data=0x%08h — model updated",
                    total_txns, txn.paddr, txn.pwdata), UVM_MEDIUM)
                pass_count++;
            end else begin
                // READ: compare DUT's PRDATA against our expected value
                if (txn.prdata === exp_regs[idx]) begin
                    `uvm_info("SCB", $sformatf(
                        "TXN #%0d: READ  addr=0x%0h — MATCH (0x%08h)",
                        total_txns, txn.paddr, txn.prdata), UVM_MEDIUM)
                    pass_count++;
                end else begin
                    `uvm_error("SCB", $sformatf(
                        "TXN #%0d: READ  addr=0x%0h — MISMATCH exp=0x%08h got=0x%08h",
                        total_txns, txn.paddr, exp_regs[idx], txn.prdata))
                    fail_count++;
                end
            end

        end else begin
            // ===== INVALID ADDRESS =====
            // DUT should assert PSLVERR for any address not in the register map
            if (!txn.pslverr) begin
                `uvm_error("SCB", $sformatf(
                    "TXN #%0d: Invalid addr 0x%0h but PSLVERR=0!",
                    total_txns, txn.paddr))
                fail_count++;
            end else begin
                `uvm_info("SCB", $sformatf(
                    "TXN #%0d: Invalid addr 0x%0h — PSLVERR correctly asserted",
                    total_txns, txn.paddr), UVM_MEDIUM)
                pass_count++;
            end
        end
    endfunction

    // --- Report phase: print final summary ---
    virtual function void report_phase(uvm_phase phase);
        `uvm_info("SCB", "========================================", UVM_LOW)
        `uvm_info("SCB", "         SCOREBOARD SUMMARY             ", UVM_LOW)
        `uvm_info("SCB", $sformatf("  Total transactions : %0d", total_txns), UVM_LOW)
        `uvm_info("SCB", $sformatf("  Pass               : %0d", pass_count), UVM_LOW)
        `uvm_info("SCB", $sformatf("  Fail               : %0d", fail_count), UVM_LOW)
        `uvm_info("SCB", "========================================", UVM_LOW)
        if (fail_count > 0)
            `uvm_error("SCB", $sformatf("TEST FAILED — %0d mismatches detected", fail_count))
        else
            `uvm_info("SCB", "*** TEST PASSED — all checks matched ***", UVM_LOW)
    endfunction

endclass
