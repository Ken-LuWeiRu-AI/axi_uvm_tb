//------------------------------------------------------------------------------
// File    : axi_ref_model.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : Simple AXI reference model for scoreboard. Keeps a byte-addressable
//           memory mirror and predicts read data / responses based on observed
//           transactions (axi_seq_item). Intended for INCR bursts + WSTRB.
//------------------------------------------------------------------------------
//
// Notes:
// - This project ignores USER sideband signals.
// - This ref model is "loose but useful" for bring-up:
//   * Supports INCR bursts (others => SLVERR)
//   * Optional address range check (DECERR)
//   * For writes: applies WSTRB per beat to mirrored memory
//   * For reads : returns mirrored memory content per beat
// - If you later support multiple outstanding or different sizes, extend here.
//------------------------------------------------------------------------------

`ifndef _AXI_REF_MODEL_SV_
`define _AXI_REF_MODEL_SV_

class axi_ref_model extends uvm_object;
  `uvm_object_utils(axi_ref_model)

  // mirror memory (byte-addressable)
  byte unsigned mem[];

  // config
  logic [`AXI_ADDR_WIDTH-1:0] base_addr;
  int unsigned                mem_bytes;
  bit                         check_addr;

  // behavior knobs
  bit                         check_all_beats; // if 1: check every beat range, else only start addr

  extern function new(string name="axi_ref_model");

  extern function void configure(
    logic [`AXI_ADDR_WIDTH-1:0] base_addr_i,
    int unsigned                mem_bytes_i,
    bit                         check_addr_i,
    bit                         clear_mem = 1,
    bit                         check_all_beats_i = 0
  );

  // helpers
  extern function int unsigned bytes_per_beat(input logic [2:0] size);
  extern function bit         addr_in_range(input logic [`AXI_ADDR_WIDTH-1:0] a);
  extern function int unsigned mem_index(input logic [`AXI_ADDR_WIDTH-1:0] a);
  extern function axi_resp_e  burst_supported_resp(input axi_burst_e b);

  extern function axi_resp_e  range_resp_for_tr(input axi_seq_item tr,
                                                          input int unsigned beats,
                                                          input int unsigned nbytes);

  extern function logic [`AXI_DATA_WIDTH-1:0] read_beat(
    input logic [`AXI_ADDR_WIDTH-1:0] addr,
    input int unsigned                nbytes
  );

  extern function void write_beat(
    input logic [`AXI_ADDR_WIDTH-1:0] addr,
    input logic [`AXI_DATA_WIDTH-1:0] data,
    input logic [`AXI_STRB_WIDTH-1:0] strb,
    input int unsigned                nbytes
  );


  extern function void predict(inout axi_seq_item tr);

endclass : axi_ref_model

//------------------------------------------------------------------------------
// ctor
//------------------------------------------------------------------------------
function axi_ref_model::new(string name="axi_ref_model");
  super.new(name);
  base_addr       = `AXI_DEFAULT_BASE_ADDR;
  mem_bytes       = `AXI_DEFAULT_MEM_BYTES;
  check_addr      = 1'b1;
  check_all_beats = 1'b0;

  mem = new[mem_bytes];
  foreach (mem[i]) mem[i] = 8'h00;
endfunction

//------------------------------------------------------------------------------
// configure
//------------------------------------------------------------------------------
function void axi_ref_model::configure(
  logic [`AXI_ADDR_WIDTH-1:0] base_addr_i,
  int unsigned                mem_bytes_i,
  bit                         check_addr_i,
  bit                         clear_mem = 1,
  bit                         check_all_beats_i = 0
);
  base_addr       = base_addr_i;
  mem_bytes       = (mem_bytes_i == 0) ? 1 : mem_bytes_i;
  check_addr      = check_addr_i;
  check_all_beats = check_all_beats_i;

  // resize if needed
  if (mem.size() != mem_bytes) begin
    mem = new[mem_bytes];
    clear_mem = 1; // new allocation -> always clear
  end

  if (clear_mem) begin
    foreach (mem[i]) mem[i] = 8'h00;
  end
endfunction

//------------------------------------------------------------------------------
// helpers
//------------------------------------------------------------------------------
function automatic int unsigned axi_ref_model::bytes_per_beat(input logic [2:0] size);
  int unsigned b;
  b = (1 << int'(size));

  // guard: do not exceed bus byte lanes (STRB_WIDTH)
  if (b == 0) b = 1;
  if (b > `AXI_STRB_WIDTH) b = `AXI_STRB_WIDTH;

  return b;
endfunction

function automatic bit axi_ref_model::addr_in_range(input logic [`AXI_ADDR_WIDTH-1:0] a);
  if (!check_addr) return 1'b1;
  return (a >= base_addr) && (a < (base_addr + mem_bytes));
endfunction

function automatic int unsigned axi_ref_model::mem_index(input logic [`AXI_ADDR_WIDTH-1:0] a);
  return int'(a - base_addr);
endfunction

function automatic axi_resp_e axi_ref_model::burst_supported_resp(input axi_burst_e b);
  if (b == AXI_BURST_INCR) return AXI_RESP_OKAY;
  else                    return AXI_RESP_SLVERR;
endfunction

// decide DECERR policy (start addr only, or all beats)
function automatic axi_resp_e axi_ref_model::range_resp_for_tr(
  input axi_seq_item tr,
  input int unsigned beats,
  input int unsigned nbytes
);
  int unsigned i;
  logic [`AXI_ADDR_WIDTH-1:0] beat_addr;
  logic [`AXI_ADDR_WIDTH-1:0] last_b;

  if (!check_addr) return AXI_RESP_OKAY;

  if (!addr_in_range(tr.addr)) return AXI_RESP_DECERR;
  if (!check_all_beats) return AXI_RESP_OKAY;

  for (i = 0; i < beats; i++) begin
    beat_addr = tr.addr + (i * nbytes);

    if (!addr_in_range(beat_addr)) return AXI_RESP_DECERR;

    if (nbytes > 0) begin
      last_b = beat_addr + (nbytes - 1);
      if (!addr_in_range(last_b)) return AXI_RESP_DECERR;
    end
  end

  return AXI_RESP_OKAY;
endfunction

//------------------------------------------------------------------------------
// read a beat from mirror
//------------------------------------------------------------------------------
function automatic logic [`AXI_DATA_WIDTH-1:0] axi_ref_model::read_beat(
  input logic [`AXI_ADDR_WIDTH-1:0] addr,
  input int unsigned                nbytes
);
  logic [`AXI_DATA_WIDTH-1:0] tmp;
  int i;
  logic [`AXI_ADDR_WIDTH-1:0] ba;

  tmp = '0;

  for (i = 0; i < `AXI_STRB_WIDTH; i++) begin
    if (i < nbytes) begin
      ba = addr + i;

      if (addr_in_range(ba)) tmp[i*8 +: 8] = mem[mem_index(ba)];
      else                   tmp[i*8 +: 8] = 8'h00;
    end
  end

  return tmp;
endfunction
//------------------------------------------------------------------------------
// write a beat into mirror (WSTRB)
//------------------------------------------------------------------------------
function automatic void axi_ref_model::write_beat(
  input logic [`AXI_ADDR_WIDTH-1:0] addr,
  input logic [`AXI_DATA_WIDTH-1:0] data,
  input logic [`AXI_STRB_WIDTH-1:0] strb,
  input int unsigned                nbytes
);
  int i;
  logic [`AXI_ADDR_WIDTH-1:0] ba;

  for (i = 0; i < `AXI_STRB_WIDTH; i++) begin
    if (i < nbytes && strb[i]) begin
      ba = addr + i;
      if (addr_in_range(ba)) mem[mem_index(ba)] = data[i*8 +: 8];
    end
  end
endfunction

//------------------------------------------------------------------------------
// Predict response + (for READ) predicted data
//------------------------------------------------------------------------------
function void axi_ref_model::predict(inout axi_seq_item tr);
  // declarations FIRST (Questa strict)
  int unsigned beats;
  int unsigned nbytes;
  axi_resp_e   base_resp;
  axi_resp_e   range_resp;
  int unsigned i;
  logic [`AXI_ADDR_WIDTH-1:0] beat_addr;

  // beats
  beats = int'(tr.len) + 1;
  if (beats == 0) beats = 1;

  // bytes per beat (guarded)
  nbytes = bytes_per_beat(tr.size);

  // base resp from burst support
  base_resp = burst_supported_resp(tr.burst);

  // range resp policy (start addr only by default)
  range_resp = range_resp_for_tr(tr, beats, nbytes);

  // combined resp
  if (base_resp != AXI_RESP_OKAY)        tr.resp = base_resp;
  else if (range_resp != AXI_RESP_OKAY)  tr.resp = range_resp;
  else                                   tr.resp = AXI_RESP_OKAY;

  // -------------------------
  // data prediction / mirror update
  // -------------------------
  if (tr.rw == AXI_WRITE) begin
    if (tr.wdata.size() != beats) begin
      `uvm_warning("AXI_RM",
        $sformatf("WRITE wdata.size(%0d) != beats(%0d), resizing", tr.wdata.size(), beats))
      tr.wdata = new[beats];
    end
    if (tr.wstrb.size() != beats) begin
      `uvm_warning("AXI_RM",
        $sformatf("WRITE wstrb.size(%0d) != beats(%0d), resizing", tr.wstrb.size(), beats))
      tr.wstrb = new[beats];
      foreach (tr.wstrb[i]) tr.wstrb[i] = {`AXI_STRB_WIDTH{1'b1}};
    end

    for (i = 0; i < beats; i++) begin
      beat_addr = tr.addr + (i * nbytes);
      write_beat(beat_addr, tr.wdata[i], tr.wstrb[i], nbytes);
    end

    if (tr.rdata.size() != 0) tr.rdata = new[0];

  end else begin
    if (tr.rdata.size() != beats) tr.rdata = new[beats];

    for (i = 0; i < beats; i++) begin
      beat_addr  = tr.addr + (i * nbytes);
      tr.rdata[i]= read_beat(beat_addr, nbytes);
    end

    if (tr.wdata.size() != 0) tr.wdata = new[0];
    if (tr.wstrb.size() != 0) tr.wstrb = new[0];
  end
endfunction

`endif // _AXI_REF_MODEL_SV_
