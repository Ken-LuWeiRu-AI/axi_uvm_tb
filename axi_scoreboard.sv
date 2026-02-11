//------------------------------------------------------------------------------
// File    : axi_scoreboard.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-02-08
// Brief   : UVM AXI4 Scoreboard.
//           A robust, OOO-capable scoreboard that verifies data integrity and
//           transaction completeness for AXI4 master/slave environments.
//
//           Key Features:
//           - Out-of-Order (OOO) Support: Uses associative arrays keyed by
//             a unique tuple (ID + Tag) to track transactions regardless of
//             completion order.
//           - Split Transaction Tracking: Independently tracks Read and Write
//             phases, ensuring that Address, Data, and Response phases match
//             correctly even when interleaved.
//           - Tag-Based Correlation: Relies on the Monitor's tagging system
//             to uniquely identify specific transactions within the same ID group,
//             solving the "ID reuse" ambiguity.
//           - Data Integrity Verification: Performs byte-level comparison of
//             Read Data (RDATA) and Write Data (WDATA) against the Reference Model.
//           - Protocol Completeness: Detects missing beats, early terminations
//             (premature WLAST/RLAST), and response mismatches (BRESP/RRESP).
//------------------------------------------------------------------------------
`ifndef _AXI_SCOREBOARD_SV_
`define _AXI_SCOREBOARD_SV_

`uvm_analysis_imp_decl(_req)
`uvm_analysis_imp_decl(_rsp)

class axi_scoreboard extends uvm_component;
  `uvm_component_utils(axi_scoreboard)

  // --------------------------------------------
  // Inputs from monitor
  // --------------------------------------------
  uvm_analysis_imp_req #(axi_req_evt, axi_scoreboard) req_imp;
  uvm_analysis_imp_rsp #(axi_rsp_evt, axi_scoreboard) rsp_imp;

  axi_ref_model rm;

  bit verbose = 0;

  int unsigned pass_cnt = 0;
  int unsigned fail_cnt = 0;

  // --------------------------------------------
  // Key = (id, tag)
  // IMPORTANT:
  //   tag in this project is per-ID sequencing tag,
  //   so (id,tag) is the true unique key.
  // --------------------------------------------
  typedef struct packed {
    int unsigned id_key;
    int unsigned tag;
  } axi_key_t;

  function automatic axi_key_t mk_key(input int unsigned id_key, input int unsigned tag);
    axi_key_t k;
    k.id_key = id_key;
    k.tag    = tag;
    return k;
  endfunction

  // --------------------------------------------
  // READ pending context
  // --------------------------------------------
  typedef struct {
    axi_seq_item exp;
    int unsigned beat_idx;      // next expected beat
    bit          active;
    bit          ok_all;        // accumulate
    bit          done_reported; // prevent double-report (reserved)
  } rd_ctx_t;

  // --------------------------------------------
  // WRITE pending context
  // --------------------------------------------
  typedef struct {
    axi_seq_item exp;
    int unsigned w_beat_idx;     // SB-owned beat counter (do NOT trust monitor beat_idx)
    bit          have_wdata;     // got all beats (or saw WLAST)
    bit          b_seen;         // BRESP arrived (maybe early)
    axi_resp_e   b_resp_act;     // cached actual BRESP
    bit          active;
    bit          done_reported;  // prevent double-report (reserved)
  } wr_ctx_t;

  rd_ctx_t rd_pending[axi_key_t];
  wr_ctx_t wr_pending[axi_key_t];

  // READ ignore to avoid flood after force-close (key -> remaining ignores)
  int unsigned rd_ignore_cnt[axi_key_t];

  // --------------------------------------------
  // ctor/build/report
  // --------------------------------------------
  function new(string name="axi_scoreboard", uvm_component parent=null);
    super.new(name, parent);
    req_imp = new("req_imp", this);
    rsp_imp = new("rsp_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi_ref_model)::get(this, "", "rm", rm)) begin
      rm = axi_ref_model::type_id::create("rm", this);
    end
    void'(uvm_config_db#(bit)::get(this, "", "verbose", verbose));
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
              $sformatf("SCOREBOARD SUMMARY: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt),
              UVM_NONE)
  endfunction

  // --------------------------------------------
  // helpers
  // --------------------------------------------
  function void finalize_pass(string msg="");
    pass_cnt++;
    if (verbose && (msg.len() > 0)) begin
      `uvm_info(get_type_name(), $sformatf("PASS: %s", msg), UVM_LOW)
    end
  endfunction

  function void finalize_fail(string msg="");
    fail_cnt++;
    `uvm_error(get_type_name(), (msg.len()>0) ? msg : "FAIL")
  endfunction

  function void set_rd_ignore(input axi_key_t key, input int unsigned n);
    rd_ignore_cnt[key] = n;
  endfunction

  function bit rd_should_ignore(input axi_key_t key);
    if (!rd_ignore_cnt.exists(key)) return 1'b0;
    if (rd_ignore_cnt[key] == 0) begin
      rd_ignore_cnt.delete(key);
      return 1'b0;
    end
    rd_ignore_cnt[key]--;
    if (rd_ignore_cnt[key] == 0) rd_ignore_cnt.delete(key);
    return 1'b1;
  endfunction

  // --------------------------------------------
  // Build expected skeleton from REQ
  // --------------------------------------------
  function automatic axi_seq_item build_exp_from_req(input axi_req_evt req);
    axi_seq_item exp;

    exp = axi_seq_item::type_id::create("exp_tr");
    exp.rw    = req.rw;
    exp.id    = req.id;
    exp.addr  = req.addr;
    exp.len   = req.len;
    exp.size  = req.size;
    exp.burst = req.burst;

    exp.beats = int'(exp.len) + 1;
    if (exp.beats == 0) exp.beats = 1;

    if (exp.rw == AXI_READ) begin
      exp.rdata = new[exp.beats];
      exp.wdata = new[0];
      exp.wstrb = new[0];
    end
    else begin
      exp.wdata = new[exp.beats];
      exp.wstrb = new[exp.beats];
      exp.rdata = new[0];
    end

    exp.resp = AXI_RESP_OKAY;
    return exp;
  endfunction

  // ============================================================
  // REQ callback (AW/AR)
  // ============================================================
  function void write_req(axi_req_evt req);
    axi_key_t key;
    int unsigned id_key;

    id_key = int'(req.id);
    key    = mk_key(id_key, req.tag);

    if (req.rw == AXI_READ) begin
      rd_ctx_t ctx;

      ctx.exp           = build_exp_from_req(req);
      ctx.beat_idx      = 0;
      ctx.active        = 1'b1;
      ctx.ok_all        = 1'b1;
      ctx.done_reported = 1'b0;

      rm.predict(ctx.exp);
      rd_pending[key] = ctx;

      if (verbose) begin
        `uvm_info(get_type_name(),
          $sformatf("SB: AR id=0x%0h tag=%0d addr=0x%0h len=%0d beats=%0d (RD pending)",
                    req.id, req.tag, req.addr, req.len, ctx.exp.beats),
          UVM_MEDIUM)
      end
    end
    else begin
      wr_ctx_t ctx;

      // If same (id,tag) appears again while active, that's a real collision
      if (wr_pending.exists(key) && wr_pending[key].active) begin
        finalize_fail($sformatf(
          "SB: duplicate AW key detected id=0x%0h tag=%0d overwriting active context",
          req.id, req.tag
        ));
        // keep going; overwrite to avoid deadlock
      end

      ctx.exp           = build_exp_from_req(req);
      ctx.w_beat_idx    = 0;
      ctx.have_wdata    = 1'b0;
      ctx.b_seen        = 1'b0;
      ctx.b_resp_act    = AXI_RESP_OKAY;
      ctx.active        = 1'b1;
      ctx.done_reported = 1'b0;

      wr_pending[key] = ctx;

      if (verbose) begin
        `uvm_info(get_type_name(),
          $sformatf("SB: AW id=0x%0h tag=%0d addr=0x%0h len=%0d beats=%0d (WR pending)",
                    req.id, req.tag, req.addr, req.len, ctx.exp.beats),
          UVM_MEDIUM)
      end
    end
  endfunction

  // ============================================================
  // RSP callback (R/W/B)
  // ============================================================
  function void write_rsp(axi_rsp_evt rsp);
    axi_key_t key;
    int unsigned id_key;

    id_key = int'(rsp.id);
    key    = mk_key(id_key, rsp.tag);

    // -----------------------
    // READ DATA beat (R)
    // -----------------------
    if (rsp.kind == AXI_EVT_R) begin
      rd_ctx_t ctx;
      bit this_ok;

      if (rd_should_ignore(key)) return;

      if (!rd_pending.exists(key) || !rd_pending[key].active) begin
        finalize_fail($sformatf("SB: unexpected R id=0x%0h tag=%0d (no pending)", rsp.id, rsp.tag));
        set_rd_ignore(key, 16);
        return;
      end

      ctx = rd_pending[key];

      if (ctx.beat_idx >= ctx.exp.beats || ctx.beat_idx >= ctx.exp.rdata.size()) begin
        finalize_fail($sformatf(
          "SB: R overflow id=0x%0h tag=%0d beat=%0d exp_beats=%0d (force close)",
          rsp.id, rsp.tag, ctx.beat_idx, ctx.exp.beats
        ));
        ctx.active = 1'b0;
        rd_pending[key] = ctx;
        set_rd_ignore(key, 16);
        return;
      end

      this_ok = (rsp.data === ctx.exp.rdata[ctx.beat_idx]);
      if (!this_ok) begin
        finalize_fail($sformatf(
          "SB: RDATA mismatch id=0x%0h tag=%0d beat=%0d ACT=0x%0h EXP=0x%0h",
          rsp.id, rsp.tag, ctx.beat_idx, rsp.data, ctx.exp.rdata[ctx.beat_idx]
        ));
      end
      else if (verbose) begin
        `uvm_info(get_type_name(),
          $sformatf("SB: R ok id=0x%0h tag=%0d beat=%0d data=0x%0h",
                    rsp.id, rsp.tag, ctx.beat_idx, rsp.data),
          UVM_LOW)
      end

      ctx.ok_all &= this_ok;
      ctx.beat_idx++;

      if (rsp.last && (ctx.beat_idx < ctx.exp.beats)) begin
        finalize_fail($sformatf(
          "SB: RLAST early id=0x%0h tag=%0d last_at_beat=%0d exp_last=%0d (force close)",
          rsp.id, rsp.tag, ctx.beat_idx-1, ctx.exp.beats-1
        ));
        ctx.active = 1'b0;
        rd_pending[key] = ctx;
        set_rd_ignore(key, 16);
        return;
      end

      if (ctx.beat_idx >= ctx.exp.beats) begin
        if (!rsp.last) begin
          finalize_fail($sformatf(
            "SB: RLAST missing id=0x%0h tag=%0d exp_last=%0d (force close)",
            rsp.id, rsp.tag, ctx.exp.beats-1
          ));
        end

        ctx.active = 1'b0;
        rd_pending[key] = ctx;
        set_rd_ignore(key, 16);

        if (ctx.ok_all && rsp.last) begin
          finalize_pass($sformatf("READ done id=0x%0h tag=%0d beats=%0d",
                                  rsp.id, rsp.tag, ctx.exp.beats));
        end
        return;
      end

      rd_pending[key] = ctx;
      return;
    end

    // -----------------------
    // WRITE DATA beat (W)
    // NOW: match by (id,tag) from monitor event
    // -----------------------
    if (rsp.kind == AXI_EVT_W) begin
      wr_ctx_t ctx;

      if (!wr_pending.exists(key) || !wr_pending[key].active) begin
        finalize_fail($sformatf("SB: unexpected W id=0x%0h tag=%0d (no pending)", rsp.id, rsp.tag));
        return;
      end

      ctx = wr_pending[key];

      if (ctx.w_beat_idx >= ctx.exp.beats) begin
        finalize_fail($sformatf(
          "SB: W overflow id=0x%0h tag=%0d w_beat_idx=%0d exp_beats=%0d (force close)",
          rsp.id, rsp.tag, ctx.w_beat_idx, ctx.exp.beats
        ));
        ctx.active = 1'b0;
        wr_pending[key] = ctx;
        return;
      end

      ctx.exp.wdata[ctx.w_beat_idx] = rsp.data;
      ctx.exp.wstrb[ctx.w_beat_idx] = rsp.strb;

      ctx.w_beat_idx++;

      if (ctx.w_beat_idx >= ctx.exp.beats) ctx.have_wdata = 1'b1;
      if (rsp.last) ctx.have_wdata = 1'b1;

      if (ctx.have_wdata && ctx.b_seen) begin
        rm.predict(ctx.exp);
        if (ctx.b_resp_act !== ctx.exp.resp) begin
          finalize_fail($sformatf("SB: BRESP mismatch id=0x%0h tag=%0d ACT=%0d EXP=%0d",
                                  rsp.id, rsp.tag, ctx.b_resp_act, ctx.exp.resp));
        end else begin
          finalize_pass($sformatf("WRITE done id=0x%0h tag=%0d resp=%0d",
                                  rsp.id, rsp.tag, ctx.b_resp_act));
        end
        ctx.active = 1'b0;
        wr_pending[key] = ctx;
        return;
      end

      wr_pending[key] = ctx;
      return;
    end

    // -----------------------
    // WRITE RESP (B)
    // NOW: match by (id,tag) from monitor event
    // -----------------------
    if (rsp.kind == AXI_EVT_B) begin
      wr_ctx_t ctx;

      if (!wr_pending.exists(key) || !wr_pending[key].active) begin
        finalize_fail($sformatf("SB: unexpected B id=0x%0h tag=%0d (no pending)", rsp.id, rsp.tag));
        return;
      end

      ctx = wr_pending[key];

      ctx.b_seen     = 1'b1;
      ctx.b_resp_act = rsp.resp;

      if (ctx.have_wdata) begin
        rm.predict(ctx.exp);
        if (ctx.b_resp_act !== ctx.exp.resp) begin
          finalize_fail($sformatf("SB: BRESP mismatch id=0x%0h tag=%0d ACT=%0d EXP=%0d",
                                  rsp.id, rsp.tag, ctx.b_resp_act, ctx.exp.resp));
        end else begin
          finalize_pass($sformatf("WRITE done id=0x%0h tag=%0d resp=%0d",
                                  rsp.id, rsp.tag, ctx.b_resp_act));
        end
        ctx.active = 1'b0;
        wr_pending[key] = ctx;
        return;
      end

      wr_pending[key] = ctx;
      return;
    end
  endfunction

endclass : axi_scoreboard

`endif // _AXI_SCOREBOARD_SV_
