//------------------------------------------------------------------------------
// File    : axi_types.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : Common AXI4 typedefs/enums shared by DUT/interface/UVM TB.
//------------------------------------------------------------------------------
//
// Notes:
// - Encodings follow AMBA AXI4 convention:
//   * AxBURST: 2'b00 FIXED, 2'b01 INCR, 2'b10 WRAP (2'b11 reserved)
//   * xRESP : 2'b00 OKAY,  2'b01 EXOKAY,2'b10 SLVERR,2'b11 DECERR
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// File    : axi_types.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : Common AXI4 typedefs/enums shared by DUT/interface/UVM TB.
//------------------------------------------------------------------------------
//
// Notes:
// - Encodings follow AMBA AXI4 convention:
//   * AxBURST: 2'b00 FIXED, 2'b01 INCR, 2'b10 WRAP (2'b11 reserved)
//   * xRESP : 2'b00 OKAY,  2'b01 EXOKAY,2'b10 SLVERR,2'b11 DECERR
//------------------------------------------------------------------------------
 
 `ifndef _AXI_TYPES_SV_
`define _AXI_TYPES_SV_

package axi_common_pkg;

  // 讓 uvm_object / `uvm_object_utils 可用
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

  class axi_req_evt extends uvm_object;
    `uvm_object_utils(axi_req_evt)

    axi_evt_kind_e kind;     // AXI_EVT_AW / AXI_EVT_AR
    axi_rw_e       rw;       // AXI_WRITE / AXI_READ

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

  class axi_rsp_evt extends uvm_object;
    `uvm_object_utils(axi_rsp_evt)

    axi_evt_kind_e kind;     // AXI_EVT_B / AXI_EVT_R / AXI_EVT_W
    axi_rw_e       rw;

    logic [31:0]   id;
    int unsigned   tag;

    int unsigned   beat_idx;
    axi_resp_e     resp;

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
