//------------------------------------------------------------------------------
// File    : axi_sequencer.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : AXI sequencer for UVM TB. Arbitrates sequences that generate
//           axi_seq_item transactions and provides them to axi_driver.
//------------------------------------------------------------------------------
//
// Notes:
// - This is a thin wrapper around uvm_sequencer#(axi_seq_item).
// - Keep it simple for bring-up; add arbitration knobs later if needed.
//------------------------------------------------------------------------------

`ifndef _AXI_SEQUENCER_SV_
`define _AXI_SEQUENCER_SV_

class axi_sequencer extends uvm_sequencer #(axi_seq_item);
  `uvm_component_utils(axi_sequencer)

  function new(string name="axi_sequencer", uvm_component parent=null);
    super.new(name, parent);
  endfunction

endclass : axi_sequencer

`endif // _AXI_SEQUENCER_SV_
