// axi_common_pkg.sv
`ifndef _AXI_COMMON_PKG_SV_
`define _AXI_COMMON_PKG_SV_

package axi_common_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // -------------------------
  // AXI enums (existing)
  // -------------------------
  typedef enum logic [1:0] {
    AXI_BURST_FIXED = 2'b00,
    AXI_BURST_INCR  = 2'b01,
    AXI_BURST_WRAP  = 2'b10,
    AXI_BURST_RSVD  = 2'b11
  } axi_burst_e;

  typedef enum logic [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } axi_resp_e;

  typedef enum bit {
    AXI_READ  = 1'b0,
    AXI_WRITE = 1'b1
  } axi_rw_e;

  // -------------------------
  // Plan-B event kind enum
  // -------------------------
  typedef enum int unsigned {
    AXI_EVT_AW = 0,
    AXI_EVT_W  = 1,
    AXI_EVT_B  = 2,
    AXI_EVT_AR = 3,
    AXI_EVT_R  = 4
  } axi_evt_kind_e;

  // -------------------------
  // Plan-B event objects
  // -------------------------

  // AW/AR handshake event
  class axi_req_evt extends uvm_object;
    `uvm_object_utils(axi_req_evt)

    axi_evt_kind_e kind;     // AXI_EVT_AW / AXI_EVT_AR
    axi_rw_e       rw;       // AXI_WRITE / AXI_READ

    // 這裡寬度如果你專案有 `AXI_ID_WIDTH / `AXI_ADDR_WIDTH 就改用那個
    logic [31:0]   id;
    int unsigned   tag;

    logic [63:0]   addr;
    logic [7:0]    len;
    logic [2:0]    size;
    axi_burst_e    burst;

    function new(string name="axi_req_evt");
      super.new(name);
      kind  = AXI_EVT_AW;
      rw    = AXI_READ;
      id    = '0;
      tag   = 0;
      addr  = '0;
      len   = '0;
      size  = '0;
      burst = AXI_BURST_INCR;
    endfunction
  endclass

  // B / R (and optional W) event
  class axi_rsp_evt extends uvm_object;
    `uvm_object_utils(axi_rsp_evt)

    axi_evt_kind_e kind;     // AXI_EVT_B / AXI_EVT_R / AXI_EVT_W(若你之後想加)
    axi_rw_e       rw;

    logic [31:0]   id;
    int unsigned   tag;

    int unsigned   beat_idx; // R/W beat index (scoreboard 用得到)
    axi_resp_e     resp;

    // data/strb 寬度同上，有 macro 就改
    logic [63:0]   data;
    logic [7:0]    strb;

    bit            last;

    function new(string name="axi_rsp_evt");
      super.new(name);
      kind     = AXI_EVT_B;
      rw       = AXI_READ;
      id       = '0;
      tag      = 0;
      beat_idx = 0;
      resp     = AXI_RESP_OKAY;
      data     = '0;
      strb     = '0;
      last     = 0;
    endfunction
  endclass

endpackage : axi_common_pkg

`endif
