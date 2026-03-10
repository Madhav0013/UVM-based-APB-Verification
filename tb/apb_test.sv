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
