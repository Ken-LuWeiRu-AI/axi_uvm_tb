//------------------------------------------------------------------------------
// File    : axi_agent.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : AXI4 agent encapsulating sequencer/driver/monitor. Supports ACTIVE
//           and PASSIVE modes. In ACTIVE mode drives transactions; in PASSIVE
//           mode only monitors bus activity.
//------------------------------------------------------------------------------
// Notes:
// - Driver uses virtual axi_if.MASTER_MP
// - Monitor uses virtual axi_if.MON_MP
// - Active/passive controlled by is_active (UVM_ACTIVE/UVM_PASSIVE)
//------------------------------------------------------------------------------

`ifndef _AXI_AGENT_SV_
`define _AXI_AGENT_SV_

class axi_agent extends uvm_agent;
  `uvm_component_utils(axi_agent)

  // components
  axi_sequencer  sequencer;
  axi_driver     driver;
  axi_monitor    monitor;

  // analysis passthrough
  uvm_analysis_port #(axi_seq_item) ap;

  extern function new(string name="axi_agent", uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);

endclass : axi_agent

function axi_agent::new(string name="axi_agent", uvm_component parent=null);
  super.new(name, parent);
  ap = new("ap", this);
endfunction

function void axi_agent::build_phase(uvm_phase phase);
  super.build_phase(phase);

  // monitor always exists
  monitor = axi_monitor::type_id::create("monitor", this);

  if (is_active == UVM_ACTIVE) begin
    sequencer = axi_sequencer::type_id::create("sequencer", this);
    driver    = axi_driver   ::type_id::create("driver",    this);
  end
endfunction

function void axi_agent::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  // driver <-> sequencer
  if (is_active == UVM_ACTIVE) begin
    driver.seq_item_port.connect(sequencer.seq_item_export);
  end

  // monitor -> agent analysis port
  monitor.ap.connect(ap);
endfunction

`endif // _AXI_AGENT_SV_
