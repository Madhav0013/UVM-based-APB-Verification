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
