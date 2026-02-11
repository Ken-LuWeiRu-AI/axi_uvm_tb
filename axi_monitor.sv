//------------------------------------------------------------------------------
// File    : axi_monitor.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-02-08
// Brief   : UVM AXI4 Passive Monitor.
//           - Supports Multiple Outstanding transactions (L2).
//           - Supports Out-of-Order (OOO) responses using per-ID queues.
//           - Reconstructs high-level events (Req/Rsp) from bus signaling.
//           - Validates fundamental AXI ordering rules (e.g. W must follow AW).
//------------------------------------------------------------------------------

`ifndef _AXI_MONITOR_SV_
`define _AXI_MONITOR_SV_

class axi_monitor extends uvm_monitor;
  `uvm_component_utils(axi_monitor)

  virtual axi_if.MON_MP vif;

  // legacy (keep port, but not fully assembled in this L2 version)
  uvm_analysis_port #(axi_seq_item) ap;

  // Plan-B streams
  uvm_analysis_port #(axi_req_evt) req_ap;
  uvm_analysis_port #(axi_rsp_evt) rsp_ap;

  // tag counters per ID
  int unsigned aw_tag_cnt[int unsigned];
  int unsigned ar_tag_cnt[int unsigned];

  bit verbose = 0;

  // -----------------------------
  // Outstanding tracking structs
  // -----------------------------
  typedef struct {
    logic [`AXI_ID_WIDTH-1:0]    id;
    int unsigned                tag;
    logic [`AXI_ADDR_WIDTH-1:0]  addr;
    logic [7:0]                  len;     // beats-1
    logic [2:0]                  size;
    axi_burst_e                  burst;
    int unsigned                 exp_beats;
    int unsigned                 beat_idx;
  } w_ctx_t;

  typedef struct {
    logic [`AXI_ID_WIDTH-1:0]    id;
    int unsigned                tag;
    logic [`AXI_ADDR_WIDTH-1:0]  addr;
    logic [7:0]                  len;     // beats-1
    logic [2:0]                  size;
    axi_burst_e                  burst;
    int unsigned                 exp_beats;
    int unsigned                 beat_idx;
  } r_ctx_t;

  // W attribution FIFO (AW order)
  w_ctx_t w_fifo[$];

  // per-ID tag queue for B (because B has BID)
  int unsigned b_tag_q[int unsigned][$];

  // per-ID read ctx queue for R (because R has RID)
  r_ctx_t r_q[int unsigned][$];

  // -----------------------------
  // methods
  // -----------------------------
  extern function new(string name="axi_monitor", uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);

  extern virtual task wait_reset_release();

  // channel threads
  extern virtual task aw_thread();
  extern virtual task w_thread();
  extern virtual task b_thread();
  extern virtual task ar_thread();
  extern virtual task r_thread();

endclass : axi_monitor

function axi_monitor::new(string name="axi_monitor", uvm_component parent=null);
  super.new(name, parent);
  ap     = new("ap", this);
  req_ap = new("req_ap", this);
  rsp_ap = new("rsp_ap", this);
endfunction

function void axi_monitor::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(virtual axi_if.MON_MP)::get(this, "", "vif", vif)) begin
    `uvm_fatal(get_type_name(),
      "No vif for axi_monitor (expect virtual axi_if.MON_MP in config_db key 'vif')")
  end
  void'(uvm_config_db#(bit)::get(this, "", "verbose", verbose));
endfunction

task axi_monitor::wait_reset_release();
  while (vif.ARESETn !== 1'b1) @(posedge vif.ACLK);
  @(posedge vif.ACLK);
endtask

task axi_monitor::run_phase(uvm_phase phase);
  super.run_phase(phase);
  wait_reset_release();

  fork
    aw_thread();
    w_thread();
    b_thread();
    ar_thread();
    r_thread();
  join_none
endtask

//------------------------------------------------------------------------------
// AW thread: create tag, emit req, push write ctx into w_fifo, and push tag into b_tag_q[id]
//------------------------------------------------------------------------------
task axi_monitor::aw_thread();
  forever begin
    int unsigned aw_stall;
    axi_req_evt  req;
    int unsigned id_key;
    int unsigned tag;

    w_ctx_t ctx;

    aw_stall = 0;
    do begin
      @(posedge vif.ACLK);
      if (vif.mon_cb.AWVALID && !vif.mon_cb.AWREADY) aw_stall++;
    end while (!(vif.mon_cb.AWVALID && vif.mon_cb.AWREADY));

    id_key = int'(vif.mon_cb.AWID);
    if (aw_tag_cnt.exists(id_key)) aw_tag_cnt[id_key]++; else aw_tag_cnt[id_key] = 0;
    tag = aw_tag_cnt[id_key];

    req = axi_req_evt::type_id::create("aw_req");
    req.kind  = AXI_EVT_AW;
    req.rw    = AXI_WRITE;
    req.id    = vif.mon_cb.AWID;
    req.tag   = tag;
    req.addr  = vif.mon_cb.AWADDR;
    req.len   = vif.mon_cb.AWLEN;
    req.size  = vif.mon_cb.AWSIZE;
    req.burst = vif.mon_cb.AWBURST;
    req_ap.write(req);

    ctx.id        = vif.mon_cb.AWID;
    ctx.tag       = tag;
    ctx.addr      = vif.mon_cb.AWADDR;
    ctx.len       = vif.mon_cb.AWLEN;
    ctx.size      = vif.mon_cb.AWSIZE;
    ctx.burst     = vif.mon_cb.AWBURST;
    ctx.exp_beats = int'(ctx.len) + 1;
    if (ctx.exp_beats == 0) ctx.exp_beats = 1;
    ctx.beat_idx  = 0;

    w_fifo.push_back(ctx);
    b_tag_q[id_key].push_back(tag);

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("MON: AW hs id=0x%0h tag=%0d addr=0x%0h len=%0d aw_stall=%0d (w_fifo=%0d)",
                  ctx.id, ctx.tag, ctx.addr, ctx.len, aw_stall, w_fifo.size()),
        UVM_MEDIUM)
    end
  end
endtask

//------------------------------------------------------------------------------
// W thread: attribute beats to w_fifo.front (W has no ID), emit W events, pop on WLAST
//------------------------------------------------------------------------------
task axi_monitor::w_thread();
  forever begin
    axi_rsp_evt rsp_w;
    w_ctx_t     cur;

    // wait a W handshake
    do begin
      @(posedge vif.ACLK);
    end while (!(vif.mon_cb.WVALID && vif.mon_cb.WREADY));

    if (w_fifo.size() == 0) begin
      `uvm_error(get_type_name(), "MON: W beat seen but w_fifo is empty (no prior AW?)")
      continue;
    end

    cur = w_fifo[0];

    rsp_w = axi_rsp_evt::type_id::create($sformatf("w_rsp_%0d", cur.beat_idx));
    rsp_w.kind     = AXI_EVT_W;
    rsp_w.rw       = AXI_WRITE;
    rsp_w.id       = cur.id;      // from AW order
    rsp_w.tag      = cur.tag;
    rsp_w.beat_idx = cur.beat_idx;
    rsp_w.resp     = AXI_RESP_OKAY;
    rsp_w.data     = vif.mon_cb.WDATA;
    rsp_w.strb     = vif.mon_cb.WSTRB;
    rsp_w.last     = (vif.mon_cb.WLAST === 1'b1);
    rsp_ap.write(rsp_w);

    cur.beat_idx++;
    w_fifo[0] = cur;

    // consistency warnings (do NOT use as loop control; loop is event-driven)
    if ((cur.beat_idx == cur.exp_beats) && (vif.mon_cb.WLAST !== 1'b1)) begin
      `uvm_warning(get_type_name(),
        $sformatf("MON: expected WLAST=1 on final beat, but saw WLAST!=1 (id=0x%0h tag=%0d exp=%0d)",
                  cur.id, cur.tag, cur.exp_beats))
    end
    if ((cur.beat_idx != cur.exp_beats) && (vif.mon_cb.WLAST === 1'b1)) begin
      `uvm_warning(get_type_name(),
        $sformatf("MON: saw early WLAST=1 before expected beats (id=0x%0h tag=%0d exp=%0d got=%0d)",
                  cur.id, cur.tag, cur.exp_beats, cur.beat_idx))
    end

    if (vif.mon_cb.WLAST === 1'b1) begin
      void'(w_fifo.pop_front());
      if (verbose) begin
        `uvm_info(get_type_name(),
          $sformatf("MON: W burst done id=0x%0h tag=%0d (remain w_fifo=%0d)",
                    cur.id, cur.tag, w_fifo.size()),
          UVM_MEDIUM)
      end
    end
  end
endtask

//------------------------------------------------------------------------------
// B thread: use BID to pop tag from b_tag_q[BID], emit B event
//------------------------------------------------------------------------------
task axi_monitor::b_thread();
  forever begin
    int unsigned b_stall;
    axi_rsp_evt  rsp_b;

    int unsigned bid_key;
    int unsigned tag;

    b_stall = 0;
    do begin
      @(posedge vif.ACLK);
      if (vif.mon_cb.BVALID && !vif.mon_cb.BREADY) b_stall++;
    end while (!(vif.mon_cb.BVALID && vif.mon_cb.BREADY));

    bid_key = int'(vif.mon_cb.BID);

    if (!b_tag_q.exists(bid_key) || (b_tag_q[bid_key].size() == 0)) begin
      `uvm_error(get_type_name(),
        $sformatf("MON: got B but no pending tag for BID=0x%0h", vif.mon_cb.BID))
      tag = 0;
    end else begin
      tag = b_tag_q[bid_key].pop_front();
    end

    rsp_b = axi_rsp_evt::type_id::create("b_rsp");
    rsp_b.kind     = AXI_EVT_B;
    rsp_b.rw       = AXI_WRITE;
    rsp_b.id       = vif.mon_cb.BID;
    rsp_b.tag      = tag;
    rsp_b.beat_idx = 0;
    rsp_b.resp     = vif.mon_cb.BRESP;
    rsp_b.data     = '0;
    rsp_b.strb     = '0;
    rsp_b.last     = 1'b1;
    rsp_ap.write(rsp_b);

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("MON: B hs bid=0x%0h tag=%0d resp=%0d b_stall=%0d",
                  vif.mon_cb.BID, tag, vif.mon_cb.BRESP, b_stall),
        UVM_MEDIUM)
    end
  end
endtask

//------------------------------------------------------------------------------
// AR thread: create tag, emit req, push read ctx into r_q[id]
//------------------------------------------------------------------------------
task axi_monitor::ar_thread();
  forever begin
    int unsigned ar_stall;
    axi_req_evt  req;

    int unsigned id_key;
    int unsigned tag;

    r_ctx_t ctx;

    ar_stall = 0;
    do begin
      @(posedge vif.ACLK);
      if (vif.mon_cb.ARVALID && !vif.mon_cb.ARREADY) ar_stall++;
    end while (!(vif.mon_cb.ARVALID && vif.mon_cb.ARREADY));

    id_key = int'(vif.mon_cb.ARID);
    if (ar_tag_cnt.exists(id_key)) ar_tag_cnt[id_key]++; else ar_tag_cnt[id_key] = 0;
    tag = ar_tag_cnt[id_key];

    req = axi_req_evt::type_id::create("ar_req");
    req.kind  = AXI_EVT_AR;
    req.rw    = AXI_READ;
    req.id    = vif.mon_cb.ARID;
    req.tag   = tag;
    req.addr  = vif.mon_cb.ARADDR;
    req.len   = vif.mon_cb.ARLEN;
    req.size  = vif.mon_cb.ARSIZE;
    req.burst = vif.mon_cb.ARBURST;
    req_ap.write(req);

    ctx.id        = vif.mon_cb.ARID;
    ctx.tag       = tag;
    ctx.addr      = vif.mon_cb.ARADDR;
    ctx.len       = vif.mon_cb.ARLEN;
    ctx.size      = vif.mon_cb.ARSIZE;
    ctx.burst     = vif.mon_cb.ARBURST;
    ctx.exp_beats = int'(ctx.len) + 1;
    if (ctx.exp_beats == 0) ctx.exp_beats = 1;
    ctx.beat_idx  = 0;

    r_q[id_key].push_back(ctx);

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("MON: AR hs id=0x%0h tag=%0d addr=0x%0h len=%0d ar_stall=%0d (r_q[%0d]=%0d)",
                  ctx.id, ctx.tag, ctx.addr, ctx.len, ar_stall, id_key, r_q[id_key].size()),
        UVM_MEDIUM)
    end
  end
endtask

//------------------------------------------------------------------------------
// R thread: use RID to select per-ID queue front, emit R events, pop on RLAST
//------------------------------------------------------------------------------
task axi_monitor::r_thread();
  forever begin
    axi_rsp_evt rsp_r;
    int unsigned rid_key;
    r_ctx_t cur;

    do begin
      @(posedge vif.ACLK);
    end while (!(vif.mon_cb.RVALID && vif.mon_cb.RREADY));

    rid_key = int'(vif.mon_cb.RID);

    if (!r_q.exists(rid_key) || (r_q[rid_key].size() == 0)) begin
      `uvm_error(get_type_name(),
        $sformatf("MON: R beat seen but no pending AR for RID=0x%0h", vif.mon_cb.RID))
      continue;
    end

    cur = r_q[rid_key][0];

    rsp_r = axi_rsp_evt::type_id::create($sformatf("r_rsp_%0d", cur.beat_idx));
    rsp_r.kind     = AXI_EVT_R;
    rsp_r.rw       = AXI_READ;
    rsp_r.id       = vif.mon_cb.RID;
    rsp_r.tag      = cur.tag;
    rsp_r.beat_idx = cur.beat_idx;
    rsp_r.resp     = vif.mon_cb.RRESP;
    rsp_r.data     = vif.mon_cb.RDATA;
    rsp_r.strb     = '0;
    rsp_r.last     = (vif.mon_cb.RLAST === 1'b1);
    rsp_ap.write(rsp_r);

    cur.beat_idx++;
    r_q[rid_key][0] = cur;

    if ((cur.beat_idx == cur.exp_beats) && (vif.mon_cb.RLAST !== 1'b1)) begin
      `uvm_warning(get_type_name(),
        $sformatf("MON: expected RLAST=1 on final beat, but saw RLAST!=1 (rid=0x%0h tag=%0d exp=%0d)",
                  vif.mon_cb.RID, cur.tag, cur.exp_beats))
    end
    if ((cur.beat_idx != cur.exp_beats) && (vif.mon_cb.RLAST === 1'b1)) begin
      `uvm_warning(get_type_name(),
        $sformatf("MON: saw early RLAST=1 before expected beats (rid=0x%0h tag=%0d exp=%0d got=%0d)",
                  vif.mon_cb.RID, cur.tag, cur.exp_beats, cur.beat_idx))
    end

    if (vif.mon_cb.RLAST === 1'b1) begin
      void'(r_q[rid_key].pop_front());
      if (verbose) begin
        `uvm_info(get_type_name(),
          $sformatf("MON: R burst done rid=0x%0h tag=%0d (remain r_q[%0d]=%0d)",
                    vif.mon_cb.RID, cur.tag, rid_key, r_q[rid_key].size()),
          UVM_MEDIUM)
      end
    end
  end
endtask

`endif // _AXI_MONITOR_SV_
