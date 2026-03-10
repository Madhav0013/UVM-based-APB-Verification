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
