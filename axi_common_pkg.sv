// axi_common_pkg.sv
`ifndef _AXI_COMMON_PKG_SV_
`define _AXI_COMMON_PKG_SV_

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
