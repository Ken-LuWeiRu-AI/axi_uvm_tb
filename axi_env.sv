//------------------------------------------------------------------------------
// File    : axi_env.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : Top-level AXI4 UVM environment. Instantiates agent, reference model,
//           scoreboard, and optional coverage subscriber. Connects monitor
//           streams to scoreboard/model/coverage and exports predicted stream
//           to scoreboard.
//------------------------------------------------------------------------------
//
// Notes:
// - Agent provides: driver/sequencer (ACTIVE) + monitor (always)
// - Monitor publishes axi_seq_item on agent.ap
// - Scoreboard consumes ACT from monitor, generates EXP internally via ref model
// - Coverage subscriber consumes same ACT stream
// - Ref model can be configured here (base/mem/check knobs)
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

  // RM config knobs (default align with axi_mem_slave)
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

  // Allow override via config_db (optional)
  void'(uvm_config_db#(bit)::get(this, "", "enable_cov", enable_cov));
  void'(uvm_config_db#(bit)::get(this, "", "verbose",    verbose));

  void'(uvm_config_db#(logic [`AXI_ADDR_WIDTH-1:0])::get(this, "", "base_addr", base_addr));
  void'(uvm_config_db#(int unsigned)::get(this, "", "mem_bytes", mem_bytes));
  void'(uvm_config_db#(bit)::get(this, "", "check_addr", check_addr));
  void'(uvm_config_db#(bit)::get(this, "", "check_all_beats", check_all_beats));

  // Agent
  agent = axi_agent::type_id::create("agent", this);

  // Reference model (shared handle if you want to use elsewhere)
  rm = axi_ref_model::type_id::create("rm", this);
  rm.configure(base_addr, mem_bytes, check_addr, /*clear_mem*/ 1, /*check_all_beats*/ check_all_beats);

  // Scoreboard
  sb = axi_scoreboard::type_id::create("scoreboard", this);

  // Tell scoreboard to use our RM (so env controls config)
  sb.rm = rm;

  // Coverage (optional)
  if (enable_cov) begin
    cov = axi_cov_subscriber::type_id::create("cov", this);
  end

  // Optional: propagate verbosity
  sb.verbose = verbose;
  if (enable_cov && (cov != null)) begin
    // cov doesn't have verbose knob; keep as-is
  end
endfunction

function void axi_env::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  // Monitor stream -> Scoreboard
  agent.ap.connect(sb.act_imp);

  // Monitor stream -> Coverage
  if (enable_cov && (cov != null)) begin
    agent.ap.connect(cov.analysis_export);
  end
endfunction

`endif // _AXI_ENV_SV_
