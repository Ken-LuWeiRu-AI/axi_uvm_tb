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

//   // UVM
//   import uvm_pkg::*;
//   `include "uvm_macros.svh"

//   // Project common headers
//   `include "axi_defines.sv"
//   `include "axi_types.sv"

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  `include "axi_defines.sv"

  // `include "axi_common_pkg.sv"
  import axi_common_pkg::*;

  // NOTE:
  // - axi_if.sv is an interface (not a class). You usually compile it as a normal SV
  //   file, not inside a package. (You already `include "axi_if.sv" in axi_top.sv.)
  // - axi_mem_slave.sv is DUT module. Also compile separately, not in package.
  // - axi_top.sv is the simulation top. Not in package.

  // TB classes (order matters for dependencies)
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

`endif // _AXI_TB_PKG_SV_
