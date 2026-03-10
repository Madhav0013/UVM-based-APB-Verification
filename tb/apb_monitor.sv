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
