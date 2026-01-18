//------------------------------------------------------------------------------
// File    : axi_monitor.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : UVM AXI4 passive monitor. Samples AXI channels via axi_if.MON_MP
//           clocking block, reconstructs transaction-level axi_seq_item for
//           WRITE (AW+W+BRESP) and READ (AR+R), and publishes them on analysis
//           ports for scoreboard/subscriber.
//------------------------------------------------------------------------------
//
// Notes:
// - USER sideband signals are intentionally omitted in this project.
// - Bring-up monitor assumption (matches axi_mem_slave + simple driver):
//   * One outstanding write at a time and one outstanding read at a time.
//   * In-order responses.
// - This version also measures "stall patterns" as cycle counts of
//   (VALID && !READY) per channel, stored into axi_seq_item.{aw_wait,w_wait,
//   b_wait,ar_wait,r_wait} for coverage.
//------------------------------------------------------------------------------

`ifndef _AXI_MONITOR_SV_
`define _AXI_MONITOR_SV_

class axi_monitor extends uvm_monitor;
  `uvm_component_utils(axi_monitor)

  virtual axi_if.MON_MP vif;

  // publish observed transactions
  uvm_analysis_port #(axi_seq_item) ap;

  // knobs
  bit verbose = 0;

  // internal state (single outstanding write/read)
  axi_seq_item w_tr;
  axi_seq_item r_tr;

  // write tracking
  int unsigned w_beats_total;
  int unsigned w_beat_idx;

  // read tracking
  int unsigned r_beats_total;
  int unsigned r_beat_idx;

  extern function new(string name="axi_monitor", uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);

  // helpers
  extern virtual task wait_reset_release();

  // collectors
  extern virtual task collect_write();
  extern virtual task collect_read();

endclass : axi_monitor

function axi_monitor::new(string name="axi_monitor", uvm_component parent=null);
  super.new(name, parent);
  ap = new("ap", this);
endfunction

function void axi_monitor::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(virtual axi_if.MON_MP)::get(this, "", "vif", vif))
    `uvm_fatal(get_type_name(), "No vif for axi_monitor (expect virtual axi_if.MON_MP in config_db key 'vif')")
endfunction

task axi_monitor::wait_reset_release();
  while (vif.ARESETn !== 1'b1) @(posedge vif.ACLK);
  @(posedge vif.ACLK);
endtask

task axi_monitor::run_phase(uvm_phase phase);
  super.run_phase(phase);

  wait_reset_release();

  fork
    collect_write();
    collect_read();
  join
endtask

//------------------------------------------------------------------------------
// WRITE collector: measure stalls + AW handshake -> W beats -> B handshake -> pub
//------------------------------------------------------------------------------
task axi_monitor::collect_write();
  forever begin
    int unsigned aw_stall;
    int unsigned b_stall;

    // -------------------------
    // Wait AW handshake + count AW stall (AWVALID && !AWREADY)
    // -------------------------
    aw_stall = 0;

    // Wait until AWVALID is seen, counting stall cycles while AWREADY=0
    do begin
      @(posedge vif.ACLK);
      if (vif.mon_cb.AWVALID && !vif.mon_cb.AWREADY)
        aw_stall++;
    end while (!(vif.mon_cb.AWVALID && vif.mon_cb.AWREADY));

    // Snapshot AW payload at handshake
    w_tr = axi_seq_item::type_id::create("w_tr");
    w_tr.rw    = AXI_WRITE;
    w_tr.id    = vif.mon_cb.AWID;
    w_tr.addr  = vif.mon_cb.AWADDR;
    w_tr.len   = vif.mon_cb.AWLEN;
    w_tr.size  = vif.mon_cb.AWSIZE;
    w_tr.burst = vif.mon_cb.AWBURST;

    w_tr.beats = int'(w_tr.len) + 1;
    if (w_tr.beats == 0) w_tr.beats = 1;

    // allocate arrays
    w_tr.wdata = new[w_tr.beats];
    w_tr.wstrb = new[w_tr.beats];
    w_tr.rdata = new[0];

    // init stall counters
    w_tr.aw_wait = aw_stall;
    w_tr.w_wait  = 0;
    w_tr.b_wait  = 0;
    w_tr.ar_wait = 0;
    w_tr.r_wait  = 0;

    w_beats_total = w_tr.beats;
    w_beat_idx    = 0;

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("MON: AW hs id=0x%0h addr=0x%0h len=%0d size=%0d burst=%0d aw_stall=%0d",
                  w_tr.id, w_tr.addr, w_tr.len, w_tr.size, w_tr.burst, w_tr.aw_wait),
        UVM_MEDIUM)
    end

    // -------------------------
    // Collect W beats (handshake) + count W stall (WVALID && !WREADY)
    // (sum over all beats)
    // -------------------------
    while (w_beat_idx < w_beats_total) begin
      do begin
        @(posedge vif.ACLK);
        if (vif.mon_cb.WVALID && !vif.mon_cb.WREADY)
          w_tr.w_wait++;
      end while (!(vif.mon_cb.WVALID && vif.mon_cb.WREADY));

      w_tr.wdata[w_beat_idx] = vif.mon_cb.WDATA;
      w_tr.wstrb[w_beat_idx] = vif.mon_cb.WSTRB;

      // optional: WLAST consistency check
      if ((w_beat_idx == w_beats_total-1) && (vif.mon_cb.WLAST !== 1'b1)) begin
        `uvm_warning(get_type_name(), "MON: expected WLAST=1 on final beat, but saw WLAST!=1")
      end
      if ((w_beat_idx != w_beats_total-1) && (vif.mon_cb.WLAST === 1'b1)) begin
        `uvm_warning(get_type_name(), "MON: saw early WLAST=1 before final beat")
      end

      w_beat_idx++;
    end

    // -------------------------
    // Wait B handshake (response) + count B stall (BVALID && !BREADY)
    // -------------------------
    b_stall = 0;
    do begin
      @(posedge vif.ACLK);
      if (vif.mon_cb.BVALID && !vif.mon_cb.BREADY)
        b_stall++;
    end while (!(vif.mon_cb.BVALID && vif.mon_cb.BREADY));

    w_tr.b_wait = b_stall;
    w_tr.resp   = vif.mon_cb.BRESP;

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("MON: B hs id=0x%0h resp=%0d b_stall=%0d (publishing WRITE)",
                  vif.mon_cb.BID, vif.mon_cb.BRESP, w_tr.b_wait),
        UVM_MEDIUM)
    end

    // publish observed write transaction
    ap.write(w_tr);
  end
endtask

//------------------------------------------------------------------------------
// READ collector: measure stalls + AR handshake -> R beats until RLAST -> pub
//------------------------------------------------------------------------------
task axi_monitor::collect_read();
  forever begin
    int unsigned ar_stall;

    // -------------------------
    // Wait AR handshake + count AR stall (ARVALID && !ARREADY)
    // -------------------------
    ar_stall = 0;
    do begin
      @(posedge vif.ACLK);
      if (vif.mon_cb.ARVALID && !vif.mon_cb.ARREADY)
        ar_stall++;
    end while (!(vif.mon_cb.ARVALID && vif.mon_cb.ARREADY));

    // Snapshot AR payload at handshake
    r_tr = axi_seq_item::type_id::create("r_tr");
    r_tr.rw    = AXI_READ;
    r_tr.id    = vif.mon_cb.ARID;
    r_tr.addr  = vif.mon_cb.ARADDR;
    r_tr.len   = vif.mon_cb.ARLEN;
    r_tr.size  = vif.mon_cb.ARSIZE;
    r_tr.burst = vif.mon_cb.ARBURST;

    r_tr.beats = int'(r_tr.len) + 1;
    if (r_tr.beats == 0) r_tr.beats = 1;

    // allocate arrays
    r_tr.rdata = new[r_tr.beats];
    r_tr.wdata = new[0];
    r_tr.wstrb = new[0];

    // init stall counters
    r_tr.aw_wait = 0;
    r_tr.w_wait  = 0;
    r_tr.b_wait  = 0;
    r_tr.ar_wait = ar_stall;
    r_tr.r_wait  = 0;

    r_beats_total = r_tr.beats;
    r_beat_idx    = 0;

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("MON: AR hs id=0x%0h addr=0x%0h len=%0d size=%0d burst=%0d ar_stall=%0d",
                  r_tr.id, r_tr.addr, r_tr.len, r_tr.size, r_tr.burst, r_tr.ar_wait),
        UVM_MEDIUM)
    end

    // -------------------------
    // Collect R beats + count R stall (RVALID && !RREADY)
    // (sum over all beats)
    // -------------------------
    while (r_beat_idx < r_beats_total) begin
      do begin
        @(posedge vif.ACLK);
        if (vif.mon_cb.RVALID && !vif.mon_cb.RREADY)
          r_tr.r_wait++;
      end while (!(vif.mon_cb.RVALID && vif.mon_cb.RREADY));

      r_tr.rdata[r_beat_idx] = vif.mon_cb.RDATA;
      r_tr.resp              = vif.mon_cb.RRESP; // keep last resp seen

      // RLAST consistency check
      if ((r_beat_idx == r_beats_total-1) && (vif.mon_cb.RLAST !== 1'b1)) begin
        `uvm_warning(get_type_name(), "MON: expected RLAST=1 on final beat, but saw RLAST!=1")
      end
      if ((r_beat_idx != r_beats_total-1) && (vif.mon_cb.RLAST === 1'b1)) begin
        `uvm_warning(get_type_name(), "MON: saw early RLAST=1 before final beat")
      end

      r_beat_idx++;

      if (vif.mon_cb.RLAST) begin
        // if RLAST arrives early, stop collecting to avoid overflow
        if (r_beat_idx != r_beats_total) begin
          `uvm_warning(get_type_name(), "MON: RLAST arrived before expected beats; truncating read capture")
        end
        break;
      end
    end

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("MON: READ done id=0x%0h resp=%0d r_stall=%0d (publishing READ)",
                  r_tr.id, r_tr.resp, r_tr.r_wait),
        UVM_MEDIUM)
    end

    // publish observed read transaction
    ap.write(r_tr);
  end
endtask

`endif // _AXI_MONITOR_SV_
