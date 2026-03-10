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
