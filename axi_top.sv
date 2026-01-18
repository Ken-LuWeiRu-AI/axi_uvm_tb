//------------------------------------------------------------------------------
// File    : axi_top.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : Top-level AXI4 UVM testbench wrapper. Generates clock/reset,
//           instantiates AXI interface + DUT, binds virtual interface to UVM
//           components via uvm_config_db, then calls run_test().
//------------------------------------------------------------------------------
//
// Notes:
// - You must compile axi_if.sv and your axi_tb_pkg.sv before this file.
// - Path strings in uvm_config_db must match your UVM hierarchy.
//   (Adjust "uvm_test_top.env.agent.driver" etc. to your actual names.)
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "uvm_macros.svh"    // UVM macros
`include "axi_tb_pkg.sv"        // AXI package
`include "axi_if.sv"
import uvm_pkg::*;           // Import UVM package
import axi_tb_pkg::*;               // Import user-defined package (AXI environment)

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

    // AW
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

    // W
    .WDATA    (axi_vif.WDATA),
    .WSTRB    (axi_vif.WSTRB),
    .WLAST    (axi_vif.WLAST),
    .WVALID   (axi_vif.WVALID),
    .WREADY   (axi_vif.WREADY),

    // B
    .BID      (axi_vif.BID),
    .BRESP    (axi_vif.BRESP),
    .BVALID   (axi_vif.BVALID),
    .BREADY   (axi_vif.BREADY),

    // AR
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

    // R
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
    // Driver uses MASTER modport
    uvm_config_db#(virtual axi_if.MASTER_MP)::set(
      null, "uvm_test_top.env.agent.driver", "vif", axi_vif
    );

    // Monitor uses MON modport
    uvm_config_db#(virtual axi_if.MON_MP)::set(
      null, "uvm_test_top.env.agent.monitor", "vif", axi_vif
    );

    // Default test name (or override with +UVM_TESTNAME=xxx)
    run_test("axi_test");
  end

endmodule : axi_top
