//------------------------------------------------------------------------------
// File    : axi_driver.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : UVM AXI4 master driver. Drives AW/W/AR channels and receives B/R
//           responses via axi_if.MASTER_MP clocking block. Supports VALID-hold,
//           burst transfers (WLAST/RLAST). This bring-up version assumes
//           single outstanding write OR read at a time (matches axi_mem_slave).
//------------------------------------------------------------------------------
//
// Notes:
// - USER sideband signals are intentionally omitted in this project.
// - This driver is "simple but correct":
//   * Holds payload stable while VALID && !READY
//   * Issues full burst for write/read
//   * Waits for B or all R beats before completing item
// - Outstanding/ID reordering is NOT implemented here (add later).
//------------------------------------------------------------------------------

`ifndef _AXI_DRIVER_SV_
`define _AXI_DRIVER_SV_

class axi_driver extends uvm_driver #(axi_seq_item);
  `uvm_component_utils(axi_driver)

  virtual axi_if.MASTER_MP vif;

  // knobs
  bit verbose = 0;

  extern function new(string name="axi_driver", uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);

  // helpers
  extern virtual task reset_signals();
  extern virtual task wait_reset_release();

  // main actions
  extern virtual task drive_item(axi_seq_item tr);
  extern virtual task do_write(axi_seq_item tr);
  extern virtual task do_read(axi_seq_item tr);

  // channel primitives
  extern virtual task drive_aw(axi_seq_item tr, output int unsigned wait_cycles);
  extern virtual task drive_w (axi_seq_item tr, output int unsigned wait_cycles);
  extern virtual task recv_b  (axi_seq_item tr, output int unsigned wait_cycles);

  extern virtual task drive_ar(axi_seq_item tr, output int unsigned wait_cycles);
  extern virtual task recv_r  (axi_seq_item tr, output int unsigned wait_cycles);

endclass : axi_driver

//------------------------------------------------------------------------------
// ctor / build
//------------------------------------------------------------------------------
function axi_driver::new(string name="axi_driver", uvm_component parent=null);
  super.new(name, parent);
endfunction

function void axi_driver::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(virtual axi_if.MASTER_MP)::get(this, "", "vif", vif))
    `uvm_fatal(get_type_name(), "No vif for axi_driver (expect virtual axi_if.MASTER_MP in config_db key 'vif')")
endfunction

//------------------------------------------------------------------------------
// reset / run
//------------------------------------------------------------------------------
task axi_driver::reset_signals();
  // drive all VALIDs low, READYs default for responses
  vif.m_cb.AWVALID <= 1'b0;
  vif.m_cb.WVALID  <= 1'b0;
  vif.m_cb.BREADY  <= 1'b0;

  vif.m_cb.ARVALID <= 1'b0;
  vif.m_cb.RREADY  <= 1'b0;

  // payload don't-care but set to 0 for cleanliness
  vif.m_cb.AWID     <= '0;
  vif.m_cb.AWADDR   <= '0;
  vif.m_cb.AWLEN    <= '0;
  vif.m_cb.AWSIZE   <= '0;
  vif.m_cb.AWBURST  <= AXI_BURST_INCR;
  vif.m_cb.AWLOCK   <= 1'b0;
  vif.m_cb.AWCACHE  <= 4'h0;
  vif.m_cb.AWPROT   <= 3'h0;
  vif.m_cb.AWQOS    <= 4'h0;
  vif.m_cb.AWREGION <= 4'h0;

  vif.m_cb.WDATA    <= '0;
  vif.m_cb.WSTRB    <= '0;
  vif.m_cb.WLAST    <= 1'b0;

  vif.m_cb.ARID     <= '0;
  vif.m_cb.ARADDR   <= '0;
  vif.m_cb.ARLEN    <= '0;
  vif.m_cb.ARSIZE   <= '0;
  vif.m_cb.ARBURST  <= AXI_BURST_INCR;
  vif.m_cb.ARLOCK   <= 1'b0;
  vif.m_cb.ARCACHE  <= 4'h0;
  vif.m_cb.ARPROT   <= 3'h0;
  vif.m_cb.ARQOS    <= 4'h0;
  vif.m_cb.ARREGION <= 4'h0;
endtask

task axi_driver::wait_reset_release();
  // wait for ARESETn==1, and align to clock edge
  while (vif.ARESETn !== 1'b1) @(posedge vif.ACLK);
  @(posedge vif.ACLK);
endtask

task axi_driver::run_phase(uvm_phase phase);
  super.run_phase(phase);

  // init
  reset_signals();

  // wait reset
  wait_reset_release();

  forever begin
    axi_seq_item tr;

    seq_item_port.get_next_item(tr);

    if (verbose) `uvm_info(get_type_name(), {"Drive: ", tr.convert2string()}, UVM_MEDIUM)

    drive_item(tr);

    seq_item_port.item_done();
  end
endtask

//------------------------------------------------------------------------------
// item dispatch
//------------------------------------------------------------------------------
task axi_driver::drive_item(axi_seq_item tr);
  // cache beats (avoid depending on constraint var)
  tr.beats = int'(tr.len) + 1;

  // basic sanity
  if (tr.beats == 0) tr.beats = 1;

  // ensure arrays exist properly (in case user made custom item)
  if (tr.rw == AXI_WRITE) begin
    if (tr.wdata.size() != tr.beats) `uvm_fatal(get_type_name(), "WRITE item wdata.size != beats")
    if (tr.wstrb.size() != tr.beats) `uvm_fatal(get_type_name(), "WRITE item wstrb.size != beats")
  end else begin
    if (tr.rdata.size() != tr.beats) begin
      // allocate for driver to fill (common)
      tr.rdata = new[tr.beats];
    end
  end

  // execute
  if (tr.rw == AXI_WRITE) do_write(tr);
  else                   do_read(tr);
endtask

//------------------------------------------------------------------------------
// WRITE: AW -> W* -> B
//------------------------------------------------------------------------------
task axi_driver::do_write(axi_seq_item tr);
  int unsigned aw_wait, w_wait, b_wait;

  // 1) AW
  drive_aw(tr, aw_wait);
  tr.aw_wait = aw_wait;

  // 2) W beats
  drive_w(tr, w_wait);
  tr.w_wait = w_wait;

  // 3) B response
  recv_b(tr, b_wait);
  tr.b_wait = b_wait;
endtask

task axi_driver::drive_aw(axi_seq_item tr, output int unsigned wait_cycles);
  wait_cycles = 0;

  // present payload
  vif.m_cb.AWID     <= tr.id;
  vif.m_cb.AWADDR   <= tr.addr;
  vif.m_cb.AWLEN    <= tr.len;
  vif.m_cb.AWSIZE   <= tr.size;
  vif.m_cb.AWBURST  <= tr.burst;
  vif.m_cb.AWLOCK   <= 1'b0;
  vif.m_cb.AWCACHE  <= 4'h0;
  vif.m_cb.AWPROT   <= 3'h0;
  vif.m_cb.AWQOS    <= 4'h0;
  vif.m_cb.AWREGION <= 4'h0;

  // assert VALID and hold until READY
  vif.m_cb.AWVALID  <= 1'b1;

  do begin
    @(posedge vif.ACLK);
    if (!vif.m_cb.AWREADY) wait_cycles++;
  end while (!vif.m_cb.AWREADY);

  // handshake happened on this cycle edge, deassert next cycle
  vif.m_cb.AWVALID <= 1'b0;
endtask

task axi_driver::drive_w(axi_seq_item tr, output int unsigned wait_cycles);
  wait_cycles = 0;

  // drive beats sequentially; hold each beat stable until WREADY
  for (int unsigned i = 0; i < tr.beats; i++) begin
    vif.m_cb.WDATA  <= tr.wdata[i];
    vif.m_cb.WSTRB  <= tr.wstrb[i];
    vif.m_cb.WLAST  <= (i == (tr.beats-1));

    vif.m_cb.WVALID <= 1'b1;

    do begin
      @(posedge vif.ACLK);
      if (!vif.m_cb.WREADY) wait_cycles++;
    end while (!vif.m_cb.WREADY);

    // beat accepted
    vif.m_cb.WVALID <= 1'b0;
    vif.m_cb.WLAST  <= 1'b0;
  end
endtask

task axi_driver::recv_b(axi_seq_item tr, output int unsigned wait_cycles);
  wait_cycles = 0;

  // be ready to accept B, hold until BVALID then handshake
  vif.m_cb.BREADY <= 1'b1;

  do begin
    @(posedge vif.ACLK);
    if (!vif.m_cb.BVALID) wait_cycles++;
  end while (!vif.m_cb.BVALID);

  // capture
  tr.resp = vif.m_cb.BRESP;

  // complete handshake this cycle if BVALID already high (it is)
  // keep BREADY high for one more cycle then drop (polite)
  @(posedge vif.ACLK);
  vif.m_cb.BREADY <= 1'b0;
endtask

//------------------------------------------------------------------------------
// READ: AR -> R* (until RLAST)
//------------------------------------------------------------------------------
task axi_driver::do_read(axi_seq_item tr);
  int unsigned ar_wait, r_wait;

  drive_ar(tr, ar_wait);
  tr.ar_wait = ar_wait;

  recv_r(tr, r_wait);
  tr.r_wait = r_wait;
endtask

task axi_driver::drive_ar(axi_seq_item tr, output int unsigned wait_cycles);
  wait_cycles = 0;

  vif.m_cb.ARID     <= tr.id;
  vif.m_cb.ARADDR   <= tr.addr;
  vif.m_cb.ARLEN    <= tr.len;
  vif.m_cb.ARSIZE   <= tr.size;
  vif.m_cb.ARBURST  <= tr.burst;
  vif.m_cb.ARLOCK   <= 1'b0;
  vif.m_cb.ARCACHE  <= 4'h0;
  vif.m_cb.ARPROT   <= 3'h0;
  vif.m_cb.ARQOS    <= 4'h0;
  vif.m_cb.ARREGION <= 4'h0;

  vif.m_cb.ARVALID  <= 1'b1;

  do begin
    @(posedge vif.ACLK);
    if (!vif.m_cb.ARREADY) wait_cycles++;
  end while (!vif.m_cb.ARREADY);

  vif.m_cb.ARVALID <= 1'b0;
endtask

task axi_driver::recv_r(axi_seq_item tr, output int unsigned wait_cycles);
  // ---- declarations MUST be first (Questa strict) ----
  int unsigned beat;
  axi_resp_e   last_resp;

  // ---- statements ----
  wait_cycles = 0;

  // ready to accept all R beats
  vif.m_cb.RREADY <= 1'b1;

  beat      = 0;
  last_resp = AXI_RESP_OKAY;

  // keep receiving until RLAST observed & accepted
  forever begin
    @(posedge vif.ACLK);

    if (!vif.m_cb.RVALID) begin
      wait_cycles++;
      continue;
    end

    // if RVALID high, handshake occurs because we keep RREADY high
    if (beat < tr.rdata.size()) tr.rdata[beat] = vif.m_cb.RDATA;
    last_resp = vif.m_cb.RRESP;

    if (vif.m_cb.RLAST) begin
      tr.resp = last_resp;
      beat++;
      break;
    end

    beat++;
    if (beat >= tr.beats) begin
      // safety: if slave forgot RLAST, stop after beats
      tr.resp = last_resp;
      `uvm_warning(get_type_name(),
        "R channel: reached expected beats but RLAST not seen; stopping to avoid hang")
      break;
    end
  end

  // drop RREADY
  @(posedge vif.ACLK);
  vif.m_cb.RREADY <= 1'b0;
endtask



`endif // _AXI_DRIVER_SV_
