//------------------------------------------------------------------------------
// File    : axi_agent.sv
// Author  : ken, Lu Wei-Ru
// Brief   : AXI4 agent (sequencer/driver/monitor).
//           - ACTIVE: seqr+drv+mon
//           - PASSIVE: mon only
//           - re-export monitor streams:
//               ap     : axi_seq_item (legacy full txn)
//               req_ap : axi_req_evt  (Plan-B request events)
//               rsp_ap : axi_rsp_evt  (Plan-B response/data events)
//------------------------------------------------------------------------------

`ifndef _AXI_AGENT_SV_
`define _AXI_AGENT_SV_

class axi_agent extends uvm_agent;
  `uvm_component_utils(axi_agent)

  // components
  axi_sequencer  sequencer;
  axi_driver     driver;
  axi_monitor    monitor;

  // exported streams
  uvm_analysis_port #(axi_seq_item) ap;
  uvm_analysis_port #(axi_req_evt)  req_ap;
  uvm_analysis_port #(axi_rsp_evt)  rsp_ap;

  extern function new(string name="axi_agent", uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);

endclass : axi_agent

function axi_agent::new(string name="axi_agent", uvm_component parent=null);
  super.new(name, parent);
endfunction

function void axi_agent::build_phase(uvm_phase phase);
  super.build_phase(phase);

  // create ports here (比在 new() 建更穩)
  ap     = new("ap", this);
  req_ap = new("req_ap", this);
  rsp_ap = new("rsp_ap", this);

  // monitor always exists
  monitor = axi_monitor::type_id::create("monitor", this);

  // active parts
  if (is_active == UVM_ACTIVE) begin
    sequencer = axi_sequencer::type_id::create("sequencer", this);
    driver    = axi_driver   ::type_id::create("driver",    this);
  end
endfunction

function void axi_agent::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  // connect seqr<->drv
  if (is_active == UVM_ACTIVE) begin
    driver.seq_item_port.connect(sequencer.seq_item_export);
  end

  // monitor -> agent ports (re-export)
  monitor.ap.connect(ap);
  monitor.req_ap.connect(req_ap);
  monitor.rsp_ap.connect(rsp_ap);
endfunction

`endif // _AXI_AGENT_SV_
