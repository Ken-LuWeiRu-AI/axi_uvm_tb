//------------------------------------------------------------------------------
// File    : axi_seq_item.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : AXI transaction item for UVM TB. Represents a single AXI command
//           (read or write) with optional burst. Used by sequences/driver/
//           monitor/scoreboard.
//------------------------------------------------------------------------------
//
// Notes:
// - This TB models at "transaction level": one seq_item can represent
//   one burst (multiple beats) for WRITE or READ.
// - USER sideband signals are intentionally omitted in this project.
// - For WRITE: wdata/wstrb arrays length = beats; rdata unused.
// - For READ : rdata array length = beats; wdata/wstrb unused.
//------------------------------------------------------------------------------

`ifndef _AXI_SEQ_ITEM_SV_
`define _AXI_SEQ_ITEM_SV_

class axi_seq_item extends uvm_sequence_item;
  `uvm_object_utils(axi_seq_item)

  // -------------------------
  // Request
  // -------------------------
  rand axi_rw_e                      rw;         // AXI_READ / AXI_WRITE
  rand logic [`AXI_ID_WIDTH-1:0]     id;
  rand logic [`AXI_ADDR_WIDTH-1:0]   addr;       // start address (byte addr)

  // burst fields
  rand logic [7:0]                   len;        // AxLEN (beats-1)
  rand logic [2:0]                   size;       // log2(bytes per beat)
  rand axi_burst_e                   burst;      // only INCR used by our DUT

  // -------------------------
  // Data payload (variable-length)
  // -------------------------
  // beats = len + 1
  rand logic [`AXI_DATA_WIDTH-1:0]   wdata[];     // write data beats
  rand logic [`AXI_STRB_WIDTH-1:0]   wstrb[];     // byte enables per beat

  // -------------------------
  // Response / observed
  // -------------------------
  logic [`AXI_DATA_WIDTH-1:0]        rdata[];     // read data beats
  axi_resp_e                        resp;        // OKAY/SLVERR/DECERR (simplified)

  // Optional debug
  int unsigned                       beats;       // cached beats = len+1
  int unsigned                       aw_wait;     // cycles waited for AWREADY (optional fill)
  int unsigned                       w_wait;      // cycles waited for WREADY (optional fill)
  int unsigned                       b_wait;      // cycles waited for BVALID (optional fill)
  int unsigned                       ar_wait;     // cycles waited for ARREADY (optional fill)
  int unsigned                       r_wait;      // cycles waited for RVALID (optional fill)

  // -------------------------
  // Constraints (safe defaults)
  // -------------------------
  constraint c_default_burst {
    burst == AXI_BURST_INCR;
  }

  // common sizes: 4 bytes/beat for 32-bit data
  constraint c_default_size {
    size == 3'd2; // 2^2 = 4 bytes
  }

  // keep bursts small for bring-up
  constraint c_default_len {
    len inside {[0:15]}; // 1~16 beats
  }

  // Make arrays match burst beats
  constraint c_array_sizes {
    beats == int'(len) + 1;

    if (rw == AXI_WRITE) {
      wdata.size() == beats;
      wstrb.size() == beats;
      rdata.size() == 0;
    } else {
      rdata.size() == beats;
      wdata.size() == 0;
      wstrb.size() == 0;
    }
  }

  // For writes, default full strobe unless overridden by sequence
  constraint c_full_strobe {
    if (rw == AXI_WRITE) {
      foreach (wstrb[i]) wstrb[i] == {`AXI_STRB_WIDTH{1'b1}};
    }
  }

  // -------------------------
  // Methods
  // -------------------------
  function new(string name="axi_seq_item");
    super.new(name);
    resp  = AXI_RESP_OKAY;
    beats = 0;
    aw_wait = 0; w_wait = 0; b_wait = 0; ar_wait = 0; r_wait = 0;
  endfunction

  function string convert2string();
    return $sformatf("AXI item: %s id=0x%0h addr=0x%0h len=%0d(beats=%0d) size=%0d burst=%0d resp=%0d",
                      (rw==AXI_WRITE) ? "WRITE" : "READ",
                      id, addr, len, (int'(len)+1), size, burst, resp);
  endfunction

endclass : axi_seq_item

`endif // _AXI_SEQ_ITEM_SV_
