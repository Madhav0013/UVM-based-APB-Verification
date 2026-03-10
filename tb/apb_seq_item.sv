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
