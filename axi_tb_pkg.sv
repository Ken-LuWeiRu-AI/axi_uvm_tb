//------------------------------------------------------------------------------
// File    : axi_tb_pkg.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : AXI4 UVM testbench package. Central compile unit that imports UVM,
//           includes all TB classes (seq_item, sequencer, driver, monitor,
//           agent, ref model, scoreboard, coverage subscriber, env, tests,
//           sequences) and exposes them via a single package import.
//------------------------------------------------------------------------------
`ifndef _AXI_TB_PKG_SV_
`define _AXI_TB_PKG_SV_

package axi_tb_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "axi_defines.sv"

  // TB 內需要 common types 就直接 import
  import axi_common_pkg::*;

  // TB classes
  `include "axi_seq_item.sv"
  `include "axi_sequencer.sv"
  `include "axi_driver.sv"
  `include "axi_monitor.sv"
  `include "axi_agent.sv"
  `include "axi_ref_model.sv"
  `include "axi_scoreboard.sv"
  `include "axi_cov_subscriber.sv"
  `include "axi_env.sv"
  `include "axi_sequences.sv"
  `include "axi_test.sv"

endpackage : axi_tb_pkg

`endif
