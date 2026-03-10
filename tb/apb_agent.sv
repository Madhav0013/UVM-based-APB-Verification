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
