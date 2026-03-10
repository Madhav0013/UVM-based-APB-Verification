	imescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"
//--------------------------------------------------------------
// File: tb/apb_seq_item.sv
// Description: APB transaction object (UVM sequence item).
//              Represents a single APB read or write transfer.
//
// FIELDS:
//   pwrite  — transfer direction (randomized stimulus)
//   paddr   — target address (randomized stimulus)
//   pwdata  — write data (randomized stimulus)
//   prdata  — read data (filled by driver/monitor after transfer)
//   pslverr — error flag (filled by driver/monitor after transfer)
//
// CONSTRAINT:
//   c_valid_addr constrains paddr to valid register addresses
//   by default. Sequences that need invalid addresses disable
//   this constraint using: req.c_valid_addr.constraint_mode(0)
//--------------------------------------------------------------

class apb_seq_item extends uvm_sequence_item;

    // --- Randomizable fields (stimulus — set before driving) ---
    rand bit        pwrite;     // 1 = write, 0 = read
    rand bit [31:0] paddr;      // Target address
    rand bit [31:0] pwdata;     // Write data (only used when pwrite=1)

    // --- Response fields (filled AFTER the transfer completes) ---
    bit [31:0]      prdata;     // Read data returned by DUT
    bit             pslverr;    // Error flag returned by DUT

    // --- UVM factory registration and field automation ---
    // This enables automatic print, copy, compare, pack/unpack
    `uvm_object_utils_begin(apb_seq_item)
        `uvm_field_int(pwrite,  UVM_ALL_ON)
        `uvm_field_int(paddr,   UVM_ALL_ON)
        `uvm_field_int(pwdata,  UVM_ALL_ON)
        `uvm_field_int(prdata,  UVM_ALL_ON)
        `uvm_field_int(pslverr, UVM_ALL_ON)
    `uvm_object_utils_end

    // --- Constructor ---
    function new(string name = "apb_seq_item");
        super.new(name);
    endfunction

    // --- Default constraint: only generate valid register addresses ---
    // Sequences that need invalid addresses disable this constraint
    constraint c_valid_addr {
        paddr inside {32'h00, 32'h04, 32'h08, 32'h0C};
    }

endclass
//--------------------------------------------------------------
// File: tb/apb_sequencer.sv
// Description: APB sequencer — a standard UVM sequencer
//              parameterized to apb_seq_item.
//
// PURPOSE: Acts as a FIFO pipeline between sequences (which
//          generate transactions) and the driver (which
//          consumes them and drives pins).
//
// NOTE: No custom logic needed. The base class does all the work.
//--------------------------------------------------------------

class apb_sequencer extends uvm_sequencer #(apb_seq_item);
    `uvm_component_utils(apb_sequencer)

    function new(string name = "apb_sequencer", uvm_component parent);
        super.new(name, parent);
    endfunction
endclass
//--------------------------------------------------------------
// File: tb/apb_driver.sv
// Description: APB driver — receives apb_seq_item transactions
//              from the sequencer and converts them into APB
//              signal activity on the interface.
//
// PROTOCOL IMPLEMENTATION:
//   For each transaction, the driver performs:
//     1. SETUP phase  — assert PSEL, place address/control/data
//     2. ENABLE phase — assert PENABLE, transfer executes
//     3. SAMPLE       — capture PRDATA and PSLVERR from DUT
//     4. IDLE         — deassert all controls
//
// TIMING:
//   Each phase takes exactly 1 clock cycle.
//   Total: 3 clock cycles per transaction.
//
// IMPORTANT: The driver writes response data (prdata, pslverr)
//   back into the request object so sequences can inspect
//   results if needed.
//--------------------------------------------------------------

class apb_driver extends uvm_driver #(apb_seq_item);
    `uvm_component_utils(apb_driver)

    // Virtual interface handle — connected to DUT through config_db
    virtual apb_if vif;

    function new(string name = "apb_driver", uvm_component parent);
        super.new(name, parent);
    endfunction

    // --- Build phase: retrieve virtual interface from config_db ---
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Could not get virtual interface from config_db")
    endfunction

    // --- Run phase: main driver loop ---
    virtual task run_phase(uvm_phase phase);
        apb_seq_item req;

        // Initialize bus to IDLE state before any transactions
        vif.PSEL    <= 0;
        vif.PENABLE <= 0;
        vif.PWRITE  <= 0;
        vif.PADDR   <= 0;
        vif.PWDATA  <= 0;

        // Infinite loop: get transaction, drive it, mark done
        forever begin
            seq_item_port.get_next_item(req);   // Block until sequence provides a transaction
            drive_transfer(req);                 // Drive the APB transfer
            seq_item_port.item_done();           // Tell sequencer we're done
        end
    endtask

    // --- Drive one complete APB transfer ---
    virtual task drive_transfer(apb_seq_item req);

        // ============================================
        // CYCLE 1: SETUP PHASE
        // Assert PSEL, deassert PENABLE
        // Place address, direction, and write data
        // ============================================
        @(posedge vif.PCLK);
        vif.PSEL    <= 1'b1;
        vif.PENABLE <= 1'b0;           // Setup phase: PENABLE must be 0
        vif.PWRITE  <= req.pwrite;
        vif.PADDR   <= req.paddr;
        if (req.pwrite)
            vif.PWDATA <= req.pwdata;   // Only drive write data for writes

        // ============================================
        // CYCLE 2: ENABLE PHASE
        // Assert PENABLE — transfer executes this cycle
        // Address/control/data must remain stable
        // ============================================
        @(posedge vif.PCLK);
        vif.PENABLE <= 1'b1;           // Enable phase: transfer executes

        // ============================================
        // CYCLE 3: SAMPLE RESPONSE + RETURN TO IDLE
        // At the next posedge, the DUT's combinational
        // outputs (PRDATA, PSLVERR) are valid and stable.
        // Sample them, then return bus to idle state.
        // ============================================
        @(posedge vif.PCLK);
        req.prdata  = vif.PRDATA;       // Capture DUT read data
        req.pslverr = vif.PSLVERR;      // Capture DUT error flag

        // Return bus to idle
        vif.PSEL    <= 1'b0;
        vif.PENABLE <= 1'b0;
        vif.PWRITE  <= 1'b0;
        vif.PADDR   <= 32'h0;
        vif.PWDATA  <= 32'h0;

    endtask

endclass
//--------------------------------------------------------------
// File: tb/apb_monitor.sv
// Description: APB monitor — passively observes bus activity,
//              reconstructs transactions, publishes to scoreboard,
//              and collects functional coverage.
//
// TRANSACTION DETECTION:
//   A completed APB transfer is detected when:
//     PSEL && PENABLE && PREADY
//   At that moment, all bus signals are valid and can be sampled.
//
// ANALYSIS PORT:
//   The monitor uses a uvm_analysis_port to broadcast observed
//   transactions. The scoreboard subscribes to this port.
//   This decouples observation from checking.
//
// FUNCTIONAL COVERAGE:
//   Embedded in the monitor for simplicity. Tracks:
//   - Read vs Write transactions
//   - Which addresses are accessed
//   - Whether PSLVERR occurs
//   - Cross coverage of direction x address
//--------------------------------------------------------------

class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)

    // Virtual interface handle
    virtual apb_if vif;

    // Analysis port — broadcasts observed transactions to scoreboard
    uvm_analysis_port #(apb_seq_item) ap;

    // Transaction handle for coverage sampling
    apb_seq_item cov_txn;

    // =========================================================
    // FUNCTIONAL COVERAGE GROUP
    // =========================================================
    covergroup apb_cg;
        // Coverpoint: transaction direction
        cp_rw: coverpoint cov_txn.pwrite {
            bins write = {1};
            bins read  = {0};
        }
        // Coverpoint: accessed address
        cp_addr: coverpoint cov_txn.paddr {
            bins ctrl     = {32'h00};   // CTRL register
            bins status_r = {32'h04};   // STATUS register
            bins data_r   = {32'h08};   // DATA register
            bins config_r = {32'h0C};   // CONFIG register
            bins invalid  = default;    // Any other address
        }
        // Coverpoint: error flag
        cp_error: coverpoint cov_txn.pslverr {
            bins no_err = {0};          // Normal access
            bins err    = {1};          // Error access
        }
        // Cross coverage: every combination of direction x address
        // This ensures we've tested read AND write to EVERY register
        cx_rw_addr: cross cp_rw, cp_addr;
    endgroup

    function new(string name = "apb_monitor", uvm_component parent);
        super.new(name, parent);
        apb_cg = new();  // Create coverage group instance
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);  // Create analysis port
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "Could not get virtual interface from config_db")
    endfunction

    // --- Run phase: continuously watch for completed transfers ---
    virtual task run_phase(uvm_phase phase);
        forever begin
            apb_seq_item txn;

            @(posedge vif.PCLK);

            // Detect a completed transfer
            if (vif.PSEL && vif.PENABLE && vif.PREADY) begin
                // Reconstruct the observed transaction
                txn = apb_seq_item::type_id::create("txn");
                txn.pwrite  = vif.PWRITE;
                txn.paddr   = vif.PADDR;
                txn.pwdata  = vif.PWDATA;
                txn.prdata  = vif.PRDATA;
                txn.pslverr = vif.PSLVERR;

                // Log the observed transaction
                `uvm_info("MON", $sformatf("Observed %s addr=0x%0h wdata=0x%0h rdata=0x%0h err=%0b",
                    txn.pwrite ? "WRITE" : "READ",
                    txn.paddr, txn.pwdata, txn.prdata, txn.pslverr), UVM_MEDIUM)

                // Sample functional coverage
                cov_txn = txn;
                apb_cg.sample();

                // Broadcast to scoreboard
                ap.write(txn);
            end
        end
    endtask

    // --- Report phase: print final coverage percentage ---
    virtual function void report_phase(uvm_phase phase);
        `uvm_info("MON", $sformatf("Functional Coverage: %.1f%%",
            apb_cg.get_coverage()), UVM_LOW)
    endfunction

endclass
//--------------------------------------------------------------
// File: tb/apb_agent.sv
// Description: APB agent — groups sequencer, driver, and monitor
//              into one reusable verification block.
//
// CONNECTIONS (done in connect_phase):
//   driver.seq_item_port  →  sequencer.seq_item_export
//   (monitor's analysis port is connected in the environment)
//
// NOTE: This is an active-only agent. Passive mode (monitor-only)
//       could be added later for protocol checking without driving,
//       but is not needed for this project.
//--------------------------------------------------------------

class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)

    apb_sequencer seqr;   // Transaction pipeline
    apb_driver    drv;    // Pin-level driver
    apb_monitor   mon;    // Bus observer

    function new(string name = "apb_agent", uvm_component parent);
        super.new(name, parent);
    endfunction

    // --- Build phase: create all sub-components ---
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        seqr = apb_sequencer::type_id::create("seqr", this);
        drv  = apb_driver::type_id::create("drv", this);
        mon  = apb_monitor::type_id::create("mon", this);
    endfunction

    // --- Connect phase: wire driver to sequencer ---
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction

endclass
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
//--------------------------------------------------------------
// File: tb/apb_env.sv
// Description: APB verification environment
//--------------------------------------------------------------
class apb_env extends uvm_env;
    `uvm_component_utils(apb_env)

    apb_agent      agt;
    apb_scoreboard scb;

    function new(string name = "apb_env", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = apb_agent::type_id::create("agt", this);
        scb = apb_scoreboard::type_id::create("scb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.ap.connect(scb.analysis_export);
    endfunction

endclass
//--------------------------------------------------------------
// File: tb/apb_sequences.sv
// Description: APB stimulus sequences — 7 different patterns
//              covering all verification scenarios.
//--------------------------------------------------------------

// =============================================================
// SEQUENCE 1: Single Write
// Writes one specific value to one specific address.
// Used by: smoke test, directed tests
// =============================================================
class apb_write_seq extends uvm_sequence #(apb_seq_item);
    `uvm_object_utils(apb_write_seq)

    bit [31:0] addr;    // Target address (set by test before starting)
    bit [31:0] data;    // Write data (set by test before starting)

    function new(string name = "apb_write_seq");
        super.new(name);
    endfunction

    virtual task body();
        apb_seq_item req;
        req = apb_seq_item::type_id::create("req");
        start_item(req);
        assert(req.randomize() with {
            pwrite == 1;
            paddr  == addr;
            pwdata == data;
        }) else `uvm_error("SEQ", "Randomization failed")
        finish_item(req);
    endtask
endclass

// =============================================================
// SEQUENCE 2: Single Read
// Reads from one specific address.
// Used by: smoke test, directed tests
// =============================================================
class apb_read_seq extends uvm_sequence #(apb_seq_item);
    `uvm_object_utils(apb_read_seq)

    bit [31:0] addr;    // Target address (set by test before starting)

    function new(string name = "apb_read_seq");
        super.new(name);
    endfunction

    virtual task body();
        apb_seq_item req;
        req = apb_seq_item::type_id::create("req");
        start_item(req);
        assert(req.randomize() with {
            pwrite == 0;
            paddr  == addr;
        }) else `uvm_error("SEQ", "Randomization failed")
        finish_item(req);
    endtask
endclass

// =============================================================
// SEQUENCE 3: Write then Readback
// Writes a value to a register, then reads it back.
// The scoreboard will verify the readback matches.
// This is the fundamental register verification pattern.
// =============================================================
class apb_write_read_seq extends uvm_sequence #(apb_seq_item);
    `uvm_object_utils(apb_write_read_seq)

    bit [31:0] addr;
    bit [31:0] data;

    function new(string name = "apb_write_read_seq");
        super.new(name);
    endfunction

    virtual task body();
        apb_seq_item req;

        // Phase 1: Write
        req = apb_seq_item::type_id::create("req");
        start_item(req);
        assert(req.randomize() with {
            pwrite == 1;
            paddr  == addr;
            pwdata == data;
        }) else `uvm_error("SEQ", "Randomization failed")
        finish_item(req);

        // Phase 2: Read back same address
        req = apb_seq_item::type_id::create("req");
        start_item(req);
        assert(req.randomize() with {
            pwrite == 0;
            paddr  == addr;
        }) else `uvm_error("SEQ", "Randomization failed")
        finish_item(req);
    endtask
endclass

// =============================================================
// SEQUENCE 4: All Register Access
// Writes unique values to all 4 registers, then reads them
// all back. Verifies the entire register map works.
// =============================================================
class apb_all_reg_seq extends uvm_sequence #(apb_seq_item);
    `uvm_object_utils(apb_all_reg_seq)

    function new(string name = "apb_all_reg_seq");
        super.new(name);
    endfunction

    virtual task body();
        // Addresses and data for all 4 registers
        bit [31:0] addrs[4]  = '{32'h00, 32'h04, 32'h08, 32'h0C};
        bit [31:0] datas[4]  = '{32'hAAAA_0000, 32'hBBBB_1111,
                                  32'hCCCC_2222, 32'hDDDD_3333};
        apb_seq_item req;

        // Write all 4 registers
        foreach (addrs[i]) begin
            req = apb_seq_item::type_id::create("req");
            start_item(req);
            assert(req.randomize() with {
                pwrite == 1;
                paddr  == addrs[i];
                pwdata == datas[i];
            }) else `uvm_error("SEQ", "Randomization failed")
            finish_item(req);
        end

        // Read all 4 registers back
        foreach (addrs[i]) begin
            req = apb_seq_item::type_id::create("req");
            start_item(req);
            assert(req.randomize() with {
                pwrite == 0;
                paddr  == addrs[i];
            }) else `uvm_error("SEQ", "Randomization failed")
            finish_item(req);
        end
    endtask
endclass

// =============================================================
// SEQUENCE 5: Invalid Address Access
// Accesses addresses NOT in the register map (0x10, 0x14, 0x20, 0xFF).
// Both reads and writes to each invalid address.
// Expects PSLVERR = 1 from the DUT for every access.
// NOTE: Must disable c_valid_addr constraint to allow illegal addrs.
// =============================================================
class apb_invalid_addr_seq extends uvm_sequence #(apb_seq_item);
    `uvm_object_utils(apb_invalid_addr_seq)

    function new(string name = "apb_invalid_addr_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] bad_addrs[4] = '{32'h10, 32'h14, 32'h20, 32'hFF};
        apb_seq_item req;

        foreach (bad_addrs[i]) begin
            // Invalid WRITE
            req = apb_seq_item::type_id::create("req");
            start_item(req);
            req.c_valid_addr.constraint_mode(0);  // Disable valid-addr constraint
            assert(req.randomize() with {
                pwrite == 1;
                paddr  == bad_addrs[i];
            }) else `uvm_error("SEQ", "Randomization failed")
            finish_item(req);

            // Invalid READ
            req = apb_seq_item::type_id::create("req");
            start_item(req);
            req.c_valid_addr.constraint_mode(0);  // Disable valid-addr constraint
            assert(req.randomize() with {
                pwrite == 0;
                paddr  == bad_addrs[i];
            }) else `uvm_error("SEQ", "Randomization failed")
            finish_item(req);
        end
    endtask
endclass

// =============================================================
// SEQUENCE 6: Random Valid Sequence
// Generates N random valid read/write transactions.
// The randomizer picks direction, address, and data randomly
// (constrained to valid addresses by c_valid_addr).
// This is the stress test — finds bugs through volume.
// =============================================================
class apb_random_seq extends uvm_sequence #(apb_seq_item);
    `uvm_object_utils(apb_random_seq)

    int unsigned num_txns = 20;  // Configurable transaction count

    function new(string name = "apb_random_seq");
        super.new(name);
    endfunction

    virtual task body();
        apb_seq_item req;
        repeat (num_txns) begin
            req = apb_seq_item::type_id::create("req");
            start_item(req);
            assert(req.randomize()) else `uvm_error("SEQ", "Randomization failed")
            finish_item(req);
        end
    endtask
endclass

// =============================================================
// SEQUENCE 7: Back-to-Back Sequence
// Rapid sequential writes to all registers followed by
// rapid sequential reads. Tests that the DUT handles
// consecutive transfers without corruption.
// =============================================================
class apb_back_to_back_seq extends uvm_sequence #(apb_seq_item);
    `uvm_object_utils(apb_back_to_back_seq)

    function new(string name = "apb_back_to_back_seq");
        super.new(name);
    endfunction

    virtual task body();
        apb_seq_item req;

        // Back-to-back WRITES: 4 consecutive writes, no gaps
        for (int i = 0; i < 4; i++) begin
            req = apb_seq_item::type_id::create("req");
            start_item(req);
            assert(req.randomize() with {
                pwrite == 1;
                paddr  == (i * 4);                   // 0x00, 0x04, 0x08, 0x0C
                pwdata == (32'hF000_0000 + i);        // Recognizable pattern
            }) else `uvm_error("SEQ", "Randomization failed")
            finish_item(req);
        end

        // Back-to-back READS: 4 consecutive reads, no gaps
        for (int i = 0; i < 4; i++) begin
            req = apb_seq_item::type_id::create("req");
            start_item(req);
            assert(req.randomize() with {
                pwrite == 0;
                paddr  == (i * 4);                   // 0x00, 0x04, 0x08, 0x0C
            }) else `uvm_error("SEQ", "Randomization failed")
            finish_item(req);
        end
    endtask
endclass
//--------------------------------------------------------------
// File: tb/apb_test.sv
// Description: UVM test classes — control which sequences run.
//
// TEST HIERARCHY:
//   apb_base_test     — builds environment (parent of all tests)
//   apb_smoke_test    — 1 write + 1 read (basic sanity)
//   apb_reg_test      — write/read all 4 registers
//   apb_invalid_test  — invalid address accesses
//   apb_random_test   — 30 random valid transactions
//   apb_full_test     — ALL sequences combined (the big one)
//
// HOW TO SELECT A TEST:
//   Pass +UVM_TESTNAME=<test_class_name> as a simulator plusarg
//   Example: +UVM_TESTNAME=apb_full_test
//--------------------------------------------------------------

// --- Base Test: builds environment, waits for reset ---
class apb_base_test extends uvm_test;
    `uvm_component_utils(apb_base_test)

    apb_env env;

    function new(string name = "apb_base_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = apb_env::type_id::create("env", this);
    endfunction

    // Default: just wait for reset, then finish
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        #200ns;   // Wait for reset to complete (reset is 5 clocks = 50ns, margin added)
        phase.drop_objection(this);
    endtask
endclass

// --- Smoke Test: minimal sanity check ---
class apb_smoke_test extends apb_base_test;
    `uvm_component_utils(apb_smoke_test)

    function new(string name = "apb_smoke_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_write_seq wr_seq;
        apb_read_seq  rd_seq;

        phase.raise_objection(this);
        #200ns;  // Wait for reset

        // Write 0xDEADBEEF to CTRL register (address 0x00)
        wr_seq = apb_write_seq::type_id::create("wr_seq");
        wr_seq.addr = 32'h00;
        wr_seq.data = 32'hDEAD_BEEF;
        wr_seq.start(env.agt.seqr);

        // Read back CTRL register — scoreboard checks the match
        rd_seq = apb_read_seq::type_id::create("rd_seq");
        rd_seq.addr = 32'h00;
        rd_seq.start(env.agt.seqr);

        #100ns;
        phase.drop_objection(this);
    endtask
endclass

// --- Register Access Test: all 4 registers ---
class apb_reg_test extends apb_base_test;
    `uvm_component_utils(apb_reg_test)

    function new(string name = "apb_reg_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_all_reg_seq all_seq;

        phase.raise_objection(this);
        #200ns;

        all_seq = apb_all_reg_seq::type_id::create("all_seq");
        all_seq.start(env.agt.seqr);

        #100ns;
        phase.drop_objection(this);
    endtask
endclass

// --- Invalid Address Test ---
class apb_invalid_test extends apb_base_test;
    `uvm_component_utils(apb_invalid_test)

    function new(string name = "apb_invalid_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_invalid_addr_seq inv_seq;

        phase.raise_objection(this);
        #200ns;

        inv_seq = apb_invalid_addr_seq::type_id::create("inv_seq");
        inv_seq.start(env.agt.seqr);

        #100ns;
        phase.drop_objection(this);
    endtask
endclass

// --- Random Test ---
class apb_random_test extends apb_base_test;
    `uvm_component_utils(apb_random_test)

    function new(string name = "apb_random_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_random_seq rand_seq;

        phase.raise_objection(this);
        #200ns;

        rand_seq = apb_random_seq::type_id::create("rand_seq");
        rand_seq.num_txns = 30;  // 30 random transactions
        rand_seq.start(env.agt.seqr);

        #100ns;
        phase.drop_objection(this);
    endtask
endclass

// --- Full Functional Test: ALL sequences combined ---
class apb_full_test extends apb_base_test;
    `uvm_component_utils(apb_full_test)

    function new(string name = "apb_full_test", uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_write_read_seq   wr_rd_seq;
        apb_all_reg_seq      all_seq;
        apb_invalid_addr_seq inv_seq;
        apb_random_seq       rand_seq;
        apb_back_to_back_seq b2b_seq;

        phase.raise_objection(this);
        #200ns;

        // 1. Write-Readback: verify basic write-then-read correctness
        `uvm_info("TEST", "===== Write-Readback Sequence =====", UVM_LOW)
        wr_rd_seq = apb_write_read_seq::type_id::create("wr_rd_seq");
        wr_rd_seq.addr = 32'h08;
        wr_rd_seq.data = 32'hCAFE_BABE;
        wr_rd_seq.start(env.agt.seqr);

        // 2. All-Register: write/read every register in the map
        `uvm_info("TEST", "===== All-Register Sequence =====", UVM_LOW)
        all_seq = apb_all_reg_seq::type_id::create("all_seq");
        all_seq.start(env.agt.seqr);

        // 3. Invalid Address: test error handling
        `uvm_info("TEST", "===== Invalid Address Sequence =====", UVM_LOW)
        inv_seq = apb_invalid_addr_seq::type_id::create("inv_seq");
        inv_seq.start(env.agt.seqr);

        // 4. Random: stress test with varied traffic
        `uvm_info("TEST", "===== Random Sequence (30 txns) =====", UVM_LOW)
        rand_seq = apb_random_seq::type_id::create("rand_seq");
        rand_seq.num_txns = 30;
        rand_seq.start(env.agt.seqr);

        // 5. Back-to-Back: rapid consecutive transfers
        `uvm_info("TEST", "===== Back-to-Back Sequence =====", UVM_LOW)
        b2b_seq = apb_back_to_back_seq::type_id::create("b2b_seq");
        b2b_seq.start(env.agt.seqr);

        #200ns;
        phase.drop_objection(this);
    endtask
endclass
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
