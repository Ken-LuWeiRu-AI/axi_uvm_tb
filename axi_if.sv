//------------------------------------------------------------------------------
// File    : axi_if.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : AXI4 SystemVerilog interface for UVM TB. Defines AW/W/B/AR/R signal
//           bundles, provides clocking blocks for cycle-accurate driving and
//           sampling, exposes MASTER/MON modports for virtual interface binding,
//           and includes basic handshake stability assertions (VALID-hold).
//------------------------------------------------------------------------------
//
// Notes:
// - This interface is intentionally "AXI4-full" oriented (supports bursts & IDs).
// - Keep this interface as the single source of truth for signal naming/sizing.
// - Assertions here are minimal and safe for bring-up. Add more as you mature.
// - This project intentionally ignores all AXI4 *USER sideband signals.
//------------------------------------------------------------------------------

`ifndef _AXI_IF_SV_
`define _AXI_IF_SV_

import axi_common_pkg::*;

interface axi_if (
  input  logic ACLK,
  input  logic ARESETn
);

  //--------------------------------------------------------------------------
  // Write Address Channel (AW)
  //--------------------------------------------------------------------------
  logic [`AXI_ID_WIDTH-1:0]   AWID;
  logic [`AXI_ADDR_WIDTH-1:0] AWADDR;
  logic [7:0]                 AWLEN;    // beats-1
  logic [2:0]                 AWSIZE;   // log2(bytes/beat)
  axi_burst_e                 AWBURST;
  logic                       AWLOCK;   // AXI4: 1-bit
  logic [3:0]                 AWCACHE;
  logic [2:0]                 AWPROT;
  logic [3:0]                 AWQOS;
  logic [3:0]                 AWREGION;
  logic                       AWVALID;
  logic                       AWREADY;

  //--------------------------------------------------------------------------
  // Write Data Channel (W)
  //--------------------------------------------------------------------------
  logic [`AXI_DATA_WIDTH-1:0] WDATA;
  logic [`AXI_STRB_WIDTH-1:0] WSTRB;
  logic                       WLAST;
  logic                       WVALID;
  logic                       WREADY;

  //--------------------------------------------------------------------------
  // Write Response Channel (B)
  //--------------------------------------------------------------------------
  logic [`AXI_ID_WIDTH-1:0]   BID;
  axi_resp_e                  BRESP;
  logic                       BVALID;
  logic                       BREADY;

  //--------------------------------------------------------------------------
  // Read Address Channel (AR)
  //--------------------------------------------------------------------------
  logic [`AXI_ID_WIDTH-1:0]   ARID;
  logic [`AXI_ADDR_WIDTH-1:0] ARADDR;
  logic [7:0]                 ARLEN;    // beats-1
  logic [2:0]                 ARSIZE;   // log2(bytes/beat)
  axi_burst_e                 ARBURST;
  logic                       ARLOCK;   // AXI4: 1-bit
  logic [3:0]                 ARCACHE;
  logic [2:0]                 ARPROT;
  logic [3:0]                 ARQOS;
  logic [3:0]                 ARREGION;
  logic                       ARVALID;
  logic                       ARREADY;

  //--------------------------------------------------------------------------
  // Read Data Channel (R)
  //--------------------------------------------------------------------------
  logic [`AXI_ID_WIDTH-1:0]   RID;
  logic [`AXI_DATA_WIDTH-1:0] RDATA;
  axi_resp_e                  RRESP;
  logic                       RLAST;
  logic                       RVALID;
  logic                       RREADY;

  //--------------------------------------------------------------------------
  // Clocking blocks
  //--------------------------------------------------------------------------
  // Master driver clocking block (drives requests, receives responses)
  clocking m_cb @(posedge ACLK);
    default input #1step output #0;
    // AW
    output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION, AWVALID;
    input  AWREADY;
    // W
    output WDATA, WSTRB, WLAST, WVALID;
    input  WREADY;
    // B
    input  BID, BRESP, BVALID;
    output BREADY;
    // AR
    output ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARVALID;
    input  ARREADY;
    // R
    input  RID, RDATA, RRESP, RLAST, RVALID;
    output RREADY;
  endclocking

  // Passive monitor clocking block (samples everything)
  clocking mon_cb @(posedge ACLK);
    default input #1step output #0;
    // AW
    input AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION, AWVALID, AWREADY;
    // W
    input WDATA, WSTRB, WLAST, WVALID, WREADY;
    // B
    input BID, BRESP, BVALID, BREADY;
    // AR
    input ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARVALID, ARREADY;
    // R
    input RID, RDATA, RRESP, RLAST, RVALID, RREADY;
  endclocking

  //--------------------------------------------------------------------------
  // Modports (for virtual interface binding)
  //--------------------------------------------------------------------------
  modport MASTER_MP (clocking m_cb,   input ACLK, input ARESETn);
  modport MON_MP    (clocking mon_cb, input ACLK, input ARESETn);

  //--------------------------------------------------------------------------
  // Minimal protocol assertions (bring-up friendly)
  //--------------------------------------------------------------------------
  // VALID-hold rule:
  //   Once VALID is asserted, payload must remain stable until handshake occurs.
  //
  // IMPORTANT (UVM clocking block interaction):
  //   Driver uses m_cb with output #0 skew, so raw @(posedge ACLK) assertions can
  //   see "in-edge" changes and produce false failures. Therefore, we sample
  //   via mon_cb (input #1step), consistent with monitor sampling.
  //--------------------------------------------------------------------------

  // AW stable while waiting
  property p_aw_valid_hold;
    @(mon_cb) disable iff (!ARESETn)
      (mon_cb.AWVALID && !mon_cb.AWREADY)
        |-> $stable({mon_cb.AWID, mon_cb.AWADDR, mon_cb.AWLEN, mon_cb.AWSIZE,
                     mon_cb.AWBURST, mon_cb.AWLOCK, mon_cb.AWCACHE, mon_cb.AWPROT,
                     mon_cb.AWQOS, mon_cb.AWREGION});
  endproperty
  a_aw_valid_hold: assert property (p_aw_valid_hold);

  // W stable while stalled (VALID && !READY) across stall cycles
  property p_w_valid_hold;
    @(mon_cb) disable iff (!ARESETn)
      // 若本拍 stall，則下一拍若仍 stall，payload 必須維持穩定
      (mon_cb.WVALID && !mon_cb.WREADY)
        |=> (!mon_cb.WREADY) |-> $stable({mon_cb.WDATA, mon_cb.WSTRB, mon_cb.WLAST});
  endproperty
  a_w_valid_hold: assert property (p_w_valid_hold);


  // AR stable while waiting
  property p_ar_valid_hold;
    @(mon_cb) disable iff (!ARESETn)
      (mon_cb.ARVALID && !mon_cb.ARREADY)
        |-> $stable({mon_cb.ARID, mon_cb.ARADDR, mon_cb.ARLEN, mon_cb.ARSIZE,
                     mon_cb.ARBURST, mon_cb.ARLOCK, mon_cb.ARCACHE, mon_cb.ARPROT,
                     mon_cb.ARQOS, mon_cb.ARREGION});
  endproperty
  a_ar_valid_hold: assert property (p_ar_valid_hold);

  // B stable while waiting
  property p_b_valid_hold;
    @(mon_cb) disable iff (!ARESETn)
      (mon_cb.BVALID && !mon_cb.BREADY)
        |-> $stable({mon_cb.BID, mon_cb.BRESP});
  endproperty
  a_b_valid_hold: assert property (p_b_valid_hold);

  // R stable while waiting
  property p_r_valid_hold;
    @(mon_cb) disable iff (!ARESETn)
      (mon_cb.RVALID && !mon_cb.RREADY)
        |-> $stable({mon_cb.RID, mon_cb.RDATA, mon_cb.RRESP, mon_cb.RLAST});
  endproperty
  a_r_valid_hold: assert property (p_r_valid_hold);

endinterface

`endif // _AXI_IF_SV_
