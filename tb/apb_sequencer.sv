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
