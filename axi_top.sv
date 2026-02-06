//------------------------------------------------------------------------------
// File    : axi_top.sv
// Author  : ken, Lu Wei-Ru
// Brief   : Top-level AXI4 UVM testbench wrapper (EDA Playground friendly)
//
// Key rules for stability:
// - In EDA Playground (or when compile order is unknown), keep `include of packages.
// - Do NOT wildcard-import axi_common_pkg in this top scope.
// - Import only axi_tb_pkg for UVM test/env visibility.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

// 1) Common types package (axi_common_pkg)
//    NOTE: This file must be included/compiled exactly once (guarded by `ifndef).
`include "axi_types.sv"

// 2) UVM macros (ok to include here)
`include "uvm_macros.svh"

// 3) TB package (axi_tb_pkg)
//    IMPORTANT: axi_tb_pkg.sv must NOT re-export axi_common_pkg types with typedef duplicates.
`include "axi_tb_pkg.sv"

// 4) Interface
`include "axi_if.sv"

// Import UVM + TB package into top scope (for run_test / test class visibility)
import uvm_pkg::*;
import axi_tb_pkg::*;

//------------------------------------------------------------------------------
// Top module
//------------------------------------------------------------------------------
module axi_top;

  // -------------------------
  // Clock / Reset
  // -------------------------
  logic ACLK;
  logic ARESETn;

  initial begin
    ACLK = 1'b0;
    forever #5 ACLK = ~ACLK;   // 100MHz
  end

  initial begin
    ARESETn = 1'b0;
    repeat (10) @(posedge ACLK);
    ARESETn = 1'b1;
  end

  // -------------------------
  // Interface instance
  // -------------------------
  axi_if axi_vif (
    .ACLK   (ACLK),
    .ARESETn(ARESETn)
  );

  // -------------------------
  // DUT instance
  // -------------------------
  axi_mem_slave #(
    .BASE_ADDR       (`AXI_DEFAULT_BASE_ADDR),
    .MEM_BYTES       (`AXI_DEFAULT_MEM_BYTES),
    .RD_LATENCY      (0),
    .WR_RESP_LATENCY (0),
    .CHECK_ADDR      (1)
  ) dut (
    .ACLK    (ACLK),
    .ARESETn (ARESETn),

    .AWID     (axi_vif.AWID),
    .AWADDR   (axi_vif.AWADDR),
    .AWLEN    (axi_vif.AWLEN),
    .AWSIZE   (axi_vif.AWSIZE),
    .AWBURST  (axi_vif.AWBURST),
    .AWLOCK   (axi_vif.AWLOCK),
    .AWCACHE  (axi_vif.AWCACHE),
    .AWPROT   (axi_vif.AWPROT),
    .AWQOS    (axi_vif.AWQOS),
    .AWREGION (axi_vif.AWREGION),
    .AWVALID  (axi_vif.AWVALID),
    .AWREADY  (axi_vif.AWREADY),

    .WDATA    (axi_vif.WDATA),
    .WSTRB    (axi_vif.WSTRB),
    .WLAST    (axi_vif.WLAST),
    .WVALID   (axi_vif.WVALID),
    .WREADY   (axi_vif.WREADY),

    .BID      (axi_vif.BID),
    .BRESP    (axi_vif.BRESP),
    .BVALID   (axi_vif.BVALID),
    .BREADY   (axi_vif.BREADY),

    .ARID     (axi_vif.ARID),
    .ARADDR   (axi_vif.ARADDR),
    .ARLEN    (axi_vif.ARLEN),
    .ARSIZE   (axi_vif.ARSIZE),
    .ARBURST  (axi_vif.ARBURST),
    .ARLOCK   (axi_vif.ARLOCK),
    .ARCACHE  (axi_vif.ARCACHE),
    .ARPROT   (axi_vif.ARPROT),
    .ARQOS    (axi_vif.ARQOS),
    .ARREGION (axi_vif.ARREGION),
    .ARVALID  (axi_vif.ARVALID),
    .ARREADY  (axi_vif.ARREADY),

    .RID      (axi_vif.RID),
    .RDATA    (axi_vif.RDATA),
    .RRESP    (axi_vif.RRESP),
    .RLAST    (axi_vif.RLAST),
    .RVALID   (axi_vif.RVALID),
    .RREADY   (axi_vif.RREADY)
  );

  // -------------------------
  // UVM config + run_test
  // -------------------------
  initial begin
    uvm_config_db#(virtual axi_if.MASTER_MP)::set(
      null, "uvm_test_top.env.agent.driver", "vif", axi_vif
    );

    uvm_config_db#(virtual axi_if.MON_MP)::set(
      null, "uvm_test_top.env.agent.monitor", "vif", axi_vif
    );

    run_test("axi_test");
  end

endmodule : axi_top
