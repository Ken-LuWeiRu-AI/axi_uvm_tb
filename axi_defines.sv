//------------------------------------------------------------------------------
// File    : axi_defines.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : Global AXI4 parameter definitions shared by DUT/interface/UVM TB.
//           Keeps bus widths and common constants consistent across the project.
//------------------------------------------------------------------------------
//
// Notes:
// - Change widths here to scale the whole project.
// - STRB width is derived from DATA width (byte lanes).
// - AXI4 supports up to 256 beats per burst (AxLEN is 8-bit, beats = AxLEN+1).
//------------------------------------------------------------------------------

`ifndef _AXI_DEFINES_SV_
`define _AXI_DEFINES_SV_

  // -------------------------
  // Global widths (project-wide)
  // -------------------------
  `define AXI_ADDR_WIDTH 32
  `define AXI_DATA_WIDTH 32
  `define AXI_ID_WIDTH    4

  // Derived
  `define AXI_STRB_WIDTH (`AXI_DATA_WIDTH/8)

  // -------------------------
  // AXI4 common constants
  // -------------------------
  // AxLEN is 8-bit, beats per burst = AxLEN + 1, so maximum beats is 256.
  `define AXI_MAX_BURST_BEATS 256
  `define AXI_MAX_AxLEN       8'hFF  // 255 -> 256 beats

  // Useful default address range for simple memory slave demos (optional)
  // You can ignore these if your DUT has its own address decoding.
  `define AXI_DEFAULT_BASE_ADDR 32'h0000_0000
  `define AXI_DEFAULT_MEM_BYTES 4096  // 4KB

  // -------------------------
  // Helper macros (optional)
  // -------------------------
  // Convert AxLEN field to beats (int)
  `define AXI_LEN_TO_BEATS(_axlen) (int'((_axlen) + 1))

  // Bytes per beat from AxSIZE (AxSIZE = log2(bytes))
  `define AXI_SIZE_TO_BYTES(_axsize) (1 << int'(_axsize))

`endif // _AXI_DEFINES_SV_
