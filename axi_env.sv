//------------------------------------------------------------------------------
// File    : axi_env.sv
// Author  : ken, Lu Wei-Ru
// Brief   : Top-level AXI4 UVM environment.
//           - create agent / rm / sb / cov
//           - connect agent streams to sb/cov
//           - provide rm handle to sb via config_db
//------------------------------------------------------------------------------

`ifndef _AXI_ENV_SV_
`define _AXI_ENV_SV_

class axi_env extends uvm_env;
  `uvm_component_utils(axi_env)

  // Components
  axi_agent          agent;
  axi_ref_model      rm;
  axi_scoreboard     sb;
  axi_cov_subscriber cov;   // optional

  // Knobs
  bit enable_cov = 1;
  bit verbose    = 0;

  // RM config knobs
  logic [`AXI_ADDR_WIDTH-1:0] base_addr       = `AXI_DEFAULT_BASE_ADDR;
  int unsigned                mem_bytes       = `AXI_DEFAULT_MEM_BYTES;
  bit                         check_addr      = 1;
  bit                         check_all_beats = 0;

  extern function new(string name="axi_env", uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);

endclass : axi_env

function axi_env::new(string name="axi_env", uvm_component parent=null);
  super.new(name, parent);
endfunction

function void axi_env::build_phase(uvm_phase phase);
  super.build_phase(phase);

  // knobs from config_db (optional)
  void'(uvm_config_db#(bit)::get(this, "", "enable_cov", enable_cov));
  void'(uvm_config_db#(bit)::get(this, "", "verbose",    verbose));

  void'(uvm_config_db#(logic [`AXI_ADDR_WIDTH-1:0])::get(this, "", "base_addr", base_addr));
  void'(uvm_config_db#(int unsigned)::get(this, "", "mem_bytes", mem_bytes));
  void'(uvm_config_db#(bit)::get(this, "", "check_addr", check_addr));
  void'(uvm_config_db#(bit)::get(this, "", "check_all_beats", check_all_beats));

  // create agent
  agent = axi_agent::type_id::create("agent", this);

  // create & configure RM (env owns RM config)
  rm = axi_ref_model::type_id::create("rm", this);
  rm.configure(base_addr, mem_bytes, check_addr, /*clear_mem*/ 1, /*check_all_beats*/ check_all_beats);

  // create scoreboard
  sb = axi_scoreboard::type_id::create("scoreboard", this);

  // pass RM to scoreboard via config_db (最穩，不怕 build order)
  uvm_config_db#(axi_ref_model)::set(this, "scoreboard", "rm", rm);

  // optional coverage
  if (enable_cov) begin
    cov = axi_cov_subscriber::type_id::create("cov", this);
  end

  // propagate verbosity
  uvm_config_db#(bit)::set(this, "scoreboard", "verbose", verbose);
endfunction

function void axi_env::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  // Plan-B streams -> Scoreboard
  agent.req_ap.connect(sb.req_imp);
  agent.rsp_ap.connect(sb.rsp_imp);

  // legacy stream -> Coverage (optional)
  if (enable_cov && (cov != null)) begin
    agent.ap.connect(cov.analysis_export);
  end
endfunction

`endif // _AXI_ENV_SV_
