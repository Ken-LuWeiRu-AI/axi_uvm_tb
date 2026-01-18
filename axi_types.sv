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

endpackage : axi_common_pkg

`endif
