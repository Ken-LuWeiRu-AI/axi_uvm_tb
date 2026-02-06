//------------------------------------------------------------------------------
// File    : axi_driver.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : UVM AXI4 master driver (Outstanding-capable, protocol-clean).
//           - Accepts items continuously (item_done immediately)
//           - AW/W/AR in separated threads
//           - Does NOT wait for B/R (responses handled by monitor/SB)
//           - Enforces VALID-hold: payload stable while VALID && !READY
//
// Key design points:
//   1) AW and W are decoupled but ordered per transaction:
//        - AW can go outstanding freely
//        - W has NO ID in AXI4 => must NOT interleave beats across write txns
//        - Therefore: AW thread hands a txn to W thread only after AW handshake
//   2) Driver never changes payload while VALID && !READY on any channel
//   3) Deassert VALID in the cycle after handshake using clocking block event
//------------------------------------------------------------------------------

`ifndef _AXI_DRIVER_SV_
`define _AXI_DRIVER_SV_

class axi_driver extends uvm_driver #(axi_seq_item);
  `uvm_component_utils(axi_driver)

  virtual axi_if.MASTER_MP vif;

  bit verbose = 0;

  axi_seq_item wr_q[$];
  axi_seq_item rd_q[$];
  int unsigned max_q_depth = 64;

  // AW -> W ordering bridge
  mailbox #(axi_seq_item) aw2w_mb;

  extern function new(string name="axi_driver", uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);

  extern virtual task reset_signals();
  extern virtual task wait_reset_release();

  extern virtual task accept_items();

  extern virtual task aw_thread();
  extern virtual task w_thread();
  extern virtual task ar_thread();

  extern virtual task drive_aw(axi_seq_item tr, output int unsigned stall_cycles);
  extern virtual task drive_ar(axi_seq_item tr, output int unsigned stall_cycles);
  extern virtual task drive_w_burst(axi_seq_item tr, output int unsigned stall_cycles);

endclass : axi_driver

function axi_driver::new(string name="axi_driver", uvm_component parent=null);
  super.new(name, parent);
  aw2w_mb = new();
endfunction

function void axi_driver::build_phase(uvm_phase phase);
  super.build_phase(phase);

  if (!uvm_config_db#(virtual axi_if.MASTER_MP)::get(this, "", "vif", vif)) begin
    `uvm_fatal(get_type_name(),
      "No vif for axi_driver (expect virtual axi_if.MASTER_MP in config_db key 'vif')")
  end

  void'(uvm_config_db#(bit)::get(this, "", "verbose", verbose));
  void'(uvm_config_db#(int unsigned)::get(this, "", "max_q_depth", max_q_depth));
endfunction

task axi_driver::reset_signals();
  // valids
  vif.m_cb.AWVALID <= 1'b0;
  vif.m_cb.WVALID  <= 1'b0;
  vif.m_cb.WLAST   <= 1'b0;
  vif.m_cb.ARVALID <= 1'b0;

  // response readies (we'll raise after reset)
  vif.m_cb.BREADY  <= 1'b0;
  vif.m_cb.RREADY  <= 1'b0;

  // payload init
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
  while (vif.ARESETn !== 1'b1) @(posedge vif.ACLK);
  @(posedge vif.ACLK);
endtask

task axi_driver::run_phase(uvm_phase phase);
  super.run_phase(phase);

  reset_signals();
  wait_reset_release();

  // policy: never stall responses
  vif.m_cb.BREADY <= 1'b1;
  vif.m_cb.RREADY <= 1'b1;

  fork
    accept_items();
    aw_thread();
    w_thread();
    ar_thread();
  join
endtask

//------------------------------------------------------------------------------
// accept_items: decouple sequencer (immediate item_done) and push into queues
//------------------------------------------------------------------------------
task axi_driver::accept_items();
  forever begin
    axi_seq_item tr;

    seq_item_port.get_next_item(tr);

    tr.beats = int'(tr.len) + 1;
    if (tr.beats == 0) tr.beats = 1;

    if (tr.rw == AXI_WRITE) begin
      if (tr.wdata.size() != tr.beats) `uvm_fatal(get_type_name(), "WRITE item wdata.size != beats")
      if (tr.wstrb.size() != tr.beats) `uvm_fatal(get_type_name(), "WRITE item wstrb.size != beats")
    end

    if (verbose) begin
      `uvm_info(get_type_name(), {"ACCEPT: ", tr.convert2string()}, UVM_MEDIUM)
    end

    if (tr.rw == AXI_WRITE) begin
      if (wr_q.size() >= max_q_depth) `uvm_fatal(get_type_name(), "wr_q overflow (max_q_depth reached)")
      wr_q.push_back(tr);
    end
    else begin
      if (rd_q.size() >= max_q_depth) `uvm_fatal(get_type_name(), "rd_q overflow (max_q_depth reached)")
      rd_q.push_back(tr);
    end

    seq_item_port.item_done();
  end
endtask

//------------------------------------------------------------------------------
// AW thread: pop write items, drive AW handshake, then enqueue to W via mailbox
//------------------------------------------------------------------------------
task axi_driver::aw_thread();
  forever begin
    axi_seq_item tr;
    int unsigned aw_stall;

    wait (wr_q.size() > 0);
    tr = wr_q.pop_front();

    drive_aw(tr, aw_stall);
    tr.aw_wait = aw_stall;

    // only after AW handshake, W is allowed to start for this txn
    aw2w_mb.put(tr);
  end
endtask

//------------------------------------------------------------------------------
// W thread: consume write txns from mailbox and send full burst (no interleave)
//------------------------------------------------------------------------------
task axi_driver::w_thread();
  forever begin
    axi_seq_item tr;
    int unsigned w_stall;

    aw2w_mb.get(tr);

    drive_w_burst(tr, w_stall);
    tr.w_wait = w_stall;

    // no B wait in driver (monitor/SB handles it)
    tr.b_wait = 0;
  end
endtask

//------------------------------------------------------------------------------
// AR thread: pop read items and drive AR handshake
//------------------------------------------------------------------------------
task axi_driver::ar_thread();
  forever begin
    axi_seq_item tr;
    int unsigned ar_stall;

    wait (rd_q.size() > 0);
    tr = rd_q.pop_front();

    drive_ar(tr, ar_stall);
    tr.ar_wait = ar_stall;

    // no R wait in driver
    tr.r_wait = 0;
  end
endtask

//------------------------------------------------------------------------------
// drive_aw: protocol-clean AW handshake with VALID-hold
//------------------------------------------------------------------------------
task axi_driver::drive_aw(axi_seq_item tr, output int unsigned stall_cycles);
  stall_cycles = 0;

  // align on clocking block (stable driving semantics)
  @(vif.m_cb);

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
  vif.m_cb.AWVALID  <= 1'b1;

  // hold payload stable while waiting
  while (vif.m_cb.AWREADY !== 1'b1) begin
    stall_cycles++;
    @(vif.m_cb);
  end

  // handshake occurred (AWVALID=1 && AWREADY=1 sampled this cycle)
  // deassert on next clocking event
  @(vif.m_cb);
  vif.m_cb.AWVALID <= 1'b0;
endtask

//------------------------------------------------------------------------------
// drive_ar: protocol-clean AR handshake with VALID-hold
//------------------------------------------------------------------------------
task axi_driver::drive_ar(axi_seq_item tr, output int unsigned stall_cycles);
  stall_cycles = 0;

  @(vif.m_cb);

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

  while (vif.m_cb.ARREADY !== 1'b1) begin
    stall_cycles++;
    @(vif.m_cb);
  end

  @(vif.m_cb);
  vif.m_cb.ARVALID <= 1'b0;
endtask

//------------------------------------------------------------------------------
// drive_w_burst: send full W burst for a txn (no interleave), VALID-hold correct
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
// drive_w_burst: send full W burst for a txn (no interleave), VALID-hold correct
//------------------------------------------------------------------------------
task axi_driver::drive_w_burst(axi_seq_item tr, output int unsigned stall_cycles);
  int unsigned beat_cnt;
  int unsigned beat_last;

  stall_cycles = 0;

  beat_cnt  = 0;
  beat_last = int'(tr.len); // AXI: LEN = beats-1

  // 對齊 clocking block event，避免第一拍排程怪異
  @(vif.m_cb);

  // 初始化（只做一次）
  vif.m_cb.WVALID <= 1'b0;
  vif.m_cb.WLAST  <= 1'b0;
  vif.m_cb.WDATA  <= '0;
  vif.m_cb.WSTRB  <= '0;

  // 檢查資料長度（防止你 EXP 變 X）
  if (tr.wdata.size() != (beat_last + 1)) begin
    `uvm_fatal(get_type_name(), "drive_w_burst: tr.wdata.size() != beats")
  end
  if (tr.wstrb.size() != (beat_last + 1)) begin
    `uvm_fatal(get_type_name(), "drive_w_burst: tr.wstrb.size() != beats")
  end

  // 鎖住第一拍 payload，然後拉 VALID
  vif.m_cb.WDATA  <= tr.wdata[beat_cnt];
  vif.m_cb.WSTRB  <= tr.wstrb[beat_cnt];
  vif.m_cb.WLAST  <= (beat_cnt == beat_last);
  vif.m_cb.WVALID <= 1'b1;

  // 送完 beats
  while (beat_cnt <= beat_last) begin
    @(vif.m_cb);

    if (!vif.ARESETn) begin
      vif.m_cb.WVALID <= 1'b0;
      vif.m_cb.WLAST  <= 1'b0;
      break;
    end

    // 沒握手：只計 stall，不要動任何 payload/VALID（維持 VALID-hold）
    if (!(vif.m_cb.WVALID && vif.m_cb.WREADY)) begin
      stall_cycles++;
      continue;
    end

    // 握手成功：前進到下一拍
    beat_cnt++;

    if (beat_cnt <= beat_last) begin
      // 更新下一拍 payload（下一個 cycle 取樣）
      vif.m_cb.WDATA  <= tr.wdata[beat_cnt];
      vif.m_cb.WSTRB  <= tr.wstrb[beat_cnt];
      vif.m_cb.WLAST  <= (beat_cnt == beat_last);
      vif.m_cb.WVALID <= 1'b1;
    end
    else begin
      // 最後一拍握手完成後，下一個 cycle 收掉 VALID/WLAST
      vif.m_cb.WVALID <= 1'b0;
      vif.m_cb.WLAST  <= 1'b0;
    end
  end
endtask




`endif // _AXI_DRIVER_SV_
