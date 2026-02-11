//------------------------------------------------------------------------------
// File    : axi_driver.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-02-08
// Brief   : UVM AXI4 Master Driver.
//           A high-performance, protocol-compliant AXI4 master driver designed
//           for advanced verification.
//
//           Key Features:
//           - Multiple Outstanding Support: Decouples sequence generation
//             from bus driving using internal queues, enabling high-throughput
//             pipelined transactions (L2).
//           - Flow Control (Backpressure): Implements intelligent queue
//             management to automatically stall the sequencer when internal
//             buffers are full, preventing overflow without assertions.
//           - Protocol Stability: Enforces the AXI "VALID-Hold" rule by
//             explicitly re-driving payload signals during stall cycles, ensuring
//             glitch-free operation.
//           - Multi-Threaded Architecture: Utilizes separate, concurrent
//             threads for Write Address (AW), Write Data (W), and Read Address (AR)
//             channels to maximize bus utilization.
//           - Data Integrity: Clones incoming sequence items to isolate driver
//             data from sequence handle reuse, preventing data corruption.
//           - Robust Reset Handling: Monitors asynchronous reset globally and
//             locally within threads to ensure clean recovery from reset events.
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

  // response readies
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

  vif.m_cb.BREADY <= 1'b1;
  vif.m_cb.RREADY <= 1'b1;

  fork
    accept_items();
    aw_thread();
    w_thread();
    ar_thread();
    
    // Global reset monitor
    forever begin
      @(negedge vif.ARESETn);
      reset_signals();
      wait_reset_release();
      vif.m_cb.BREADY <= 1'b1;
      vif.m_cb.RREADY <= 1'b1;
    end
  join
endtask

//------------------------------------------------------------------------------
// accept_items: Decouple, CLONE, and push to queues (With Flow Control)
//------------------------------------------------------------------------------
task axi_driver::accept_items();
  forever begin
    axi_seq_item tr;
    axi_seq_item tr_clone;

    seq_item_port.get_next_item(tr);

    // Clone to prevent handle aliasing
    if (!$cast(tr_clone, tr.clone())) begin
      `uvm_fatal(get_type_name(), "Failed to cast cloned item.")
    end

    tr_clone.beats = int'(tr_clone.len) + 1;
    if (tr_clone.beats == 0) tr_clone.beats = 1;

    // --- WRITE PATH FLOW CONTROL ---
    if (tr_clone.rw == AXI_WRITE) begin
      // Sanity check
      if (tr_clone.wdata.size() != tr_clone.beats) 
        `uvm_fatal(get_type_name(), "WRITE item wdata.size != beats")
      if (tr_clone.wstrb.size() != tr_clone.beats) 
        `uvm_fatal(get_type_name(), "WRITE item wstrb.size != beats")

      // [CRITICAL FIX]: Wait if queue is full
      wait (wr_q.size() < max_q_depth);
      
      wr_q.push_back(tr_clone);
    end
    
    // --- READ PATH FLOW CONTROL ---
    else begin
      // [CRITICAL FIX]: Wait if queue is full
      wait (rd_q.size() < max_q_depth);
      
      rd_q.push_back(tr_clone);
    end

    if (verbose) `uvm_info(get_type_name(), {"ACCEPT: ", tr_clone.convert2string()}, UVM_MEDIUM)

    // Only tell sequence we are done once we've successfully queued it
    seq_item_port.item_done();
  end
endtask

//------------------------------------------------------------------------------
// AW thread
//------------------------------------------------------------------------------
task axi_driver::aw_thread();
  forever begin
    axi_seq_item tr;
    int unsigned aw_stall;

    if (vif.ARESETn === 1'b0) begin
      @(posedge vif.ACLK);
      continue;
    end

    wait (wr_q.size() > 0);
    tr = wr_q.pop_front();

    drive_aw(tr, aw_stall);
    tr.aw_wait = aw_stall;

    aw2w_mb.put(tr);
  end
endtask

//------------------------------------------------------------------------------
// W thread
//------------------------------------------------------------------------------
task axi_driver::w_thread();
  forever begin
    axi_seq_item tr;
    int unsigned w_stall;

    if (vif.ARESETn === 1'b0) begin
      @(posedge vif.ACLK);
      continue;
    end

    aw2w_mb.get(tr);

    drive_w_burst(tr, w_stall);
    tr.w_wait = w_stall;
    tr.b_wait = 0;
  end
endtask

//------------------------------------------------------------------------------
// AR thread
//------------------------------------------------------------------------------
task axi_driver::ar_thread();
  forever begin
    axi_seq_item tr;
    int unsigned ar_stall;

    if (vif.ARESETn === 1'b0) begin
      @(posedge vif.ACLK);
      continue;
    end

    wait (rd_q.size() > 0);
    tr = rd_q.pop_front();

    drive_ar(tr, ar_stall);
    tr.ar_wait = ar_stall;
    tr.r_wait = 0;
  end
endtask

//------------------------------------------------------------------------------
// drive_aw: Re-drives payload every cycle until handshake
//------------------------------------------------------------------------------
task axi_driver::drive_aw(axi_seq_item tr, output int unsigned stall_cycles);
  stall_cycles = 0;

  // Align to clock edge
  @(vif.m_cb);

  // Loop until handshake happens
  while (1) begin
    // 1. Drive Payload (every cycle)
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

    // 2. Sample inputs
    @(vif.m_cb);

    // 3. Reset Check
    if (vif.ARESETn === 1'b0) begin
      vif.m_cb.AWVALID <= 1'b0;
      return;
    end

    // 4. Handshake Check
    if (vif.m_cb.AWREADY === 1'b1) begin
      // Handshake done, deassert VALID next cycle
      vif.m_cb.AWVALID <= 1'b0;
      break;
    end else begin
      // Still waiting
      stall_cycles++;
    end
  end
endtask

//------------------------------------------------------------------------------
// drive_ar: Re-drives payload every cycle until handshake
//------------------------------------------------------------------------------
task axi_driver::drive_ar(axi_seq_item tr, output int unsigned stall_cycles);
  stall_cycles = 0;

  @(vif.m_cb);

  while (1) begin
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

    @(vif.m_cb);

    if (vif.ARESETn === 1'b0) begin
      vif.m_cb.ARVALID <= 1'b0;
      return;
    end

    if (vif.m_cb.ARREADY === 1'b1) begin
      vif.m_cb.ARVALID <= 1'b0;
      break;
    end else begin
      stall_cycles++;
    end
  end
endtask

//------------------------------------------------------------------------------
// drive_w_burst: Re-drives current beat until handshake
//------------------------------------------------------------------------------
task axi_driver::drive_w_burst(axi_seq_item tr, output int unsigned stall_cycles);
  int unsigned beat_cnt;
  int unsigned beat_last;

  stall_cycles = 0;
  beat_cnt     = 0;
  beat_last    = int'(tr.len);

  // Align to clock edge
  @(vif.m_cb);

  while (beat_cnt <= beat_last) begin
    // 1. Drive Payload for CURRENT beat (re-drive every cycle)
    vif.m_cb.WDATA  <= tr.wdata[beat_cnt];
    vif.m_cb.WSTRB  <= tr.wstrb[beat_cnt];
    vif.m_cb.WLAST  <= (beat_cnt == beat_last);
    vif.m_cb.WVALID <= 1'b1;

    // 2. Sample
    @(vif.m_cb);

    // 3. Reset Check
    if (vif.ARESETn === 1'b0) begin
      vif.m_cb.WVALID <= 1'b0;
      vif.m_cb.WLAST  <= 1'b0;
      return;
    end

    // 4. Handshake Check
    if (vif.m_cb.WREADY === 1'b1) begin
      // This beat is done
      beat_cnt++;
      // If we just finished the last beat, drop VALID
      if (beat_cnt > beat_last) begin
        vif.m_cb.WVALID <= 1'b0;
        vif.m_cb.WLAST  <= 1'b0;
      end
    end else begin
      // Stalled: counter does not increment, loop repeats, re-driving same data
      stall_cycles++;
    end
  end
endtask

`endif // _AXI_DRIVER_SV_