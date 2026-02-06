//------------------------------------------------------------------------------
// File    : axi_top.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : Top-level AXI4 UVM testbench wrapper. Generates clock/reset,
//           instantiates AXI interface + DUT, binds virtual interface to UVM
//           components via uvm_config_db, then calls run_test().
//------------------------------------------------------------------------------
//
// Notes:
// - You must compile axi_if.sv and your axi_tb_pkg.sv before this file.
// - Path strings in uvm_config_db must match your UVM hierarchy.
//   (Adjust "uvm_test_top.env.agent.driver" etc. to your actual names.)
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "uvm_macros.svh"    // UVM macros
`include "axi_tb_pkg.sv"        // AXI package
`include "axi_if.sv"
import uvm_pkg::*;           // Import UVM package
import axi_tb_pkg::*;               // Import user-defined package (AXI environment)

module axi_top;

  // -------------------------
  // Clock / Reset
  // -------------------------
  logic ACLK;
  logic ARESETn;

  initial begin
    ACLK = 1'b0;
    forever #5 ACLK = ~ACLK;   // 100MHz
  end

  initial begin
    ARESETn = 1'b0;
    repeat (10) @(posedge ACLK);
    ARESETn = 1'b1;
  end

  // -------------------------
  // Interface instance
  // -------------------------
  axi_if axi_vif (
    .ACLK   (ACLK),
    .ARESETn(ARESETn)
  );

  // -------------------------
  // DUT instance
  // -------------------------
  axi_mem_slave #(
    .BASE_ADDR       (`AXI_DEFAULT_BASE_ADDR),
    .MEM_BYTES       (`AXI_DEFAULT_MEM_BYTES),
    .RD_LATENCY      (0),
    .WR_RESP_LATENCY (0),
    .CHECK_ADDR      (1)
  ) dut (
    .ACLK    (ACLK),
    .ARESETn (ARESETn),

    // AW write address - address and control
    .AWID     (axi_vif.AWID),
    .AWADDR   (axi_vif.AWADDR),
    .AWLEN    (axi_vif.AWLEN),
    .AWSIZE   (axi_vif.AWSIZE),
    .AWBURST  (axi_vif.AWBURST),
    .AWLOCK   (axi_vif.AWLOCK),
    .AWCACHE  (axi_vif.AWCACHE),
    .AWPROT   (axi_vif.AWPROT),
    .AWQOS    (axi_vif.AWQOS),
    .AWREGION (axi_vif.AWREGION),
    .AWVALID  (axi_vif.AWVALID),
    .AWREADY  (axi_vif.AWREADY),

    // W Write Data 
    .WDATA    (axi_vif.WDATA),
    .WSTRB    (axi_vif.WSTRB),
    .WLAST    (axi_vif.WLAST),
    .WVALID   (axi_vif.WVALID),
    .WREADY   (axi_vif.WREADY),

    // B Write Response
    .BID      (axi_vif.BID),
    .BRESP    (axi_vif.BRESP),
    .BVALID   (axi_vif.BVALID),
    .BREADY   (axi_vif.BREADY),

    // AR Read Address - address and control
    .ARID     (axi_vif.ARID),
    .ARADDR   (axi_vif.ARADDR),
    .ARLEN    (axi_vif.ARLEN),
    .ARSIZE   (axi_vif.ARSIZE),
    .ARBURST  (axi_vif.ARBURST),
    .ARLOCK   (axi_vif.ARLOCK),
    .ARCACHE  (axi_vif.ARCACHE),
    .ARPROT   (axi_vif.ARPROT),
    .ARQOS    (axi_vif.ARQOS),
    .ARREGION (axi_vif.ARREGION),
    .ARVALID  (axi_vif.ARVALID),
    .ARREADY  (axi_vif.ARREADY),

    // R Read Data
    .RID      (axi_vif.RID),
    .RDATA    (axi_vif.RDATA),
    .RRESP    (axi_vif.RRESP),
    .RLAST    (axi_vif.RLAST),
    .RVALID   (axi_vif.RVALID),
    .RREADY   (axi_vif.RREADY)
  );

  // -------------------------
  // UVM config + run_test
  // -------------------------
  initial begin
    // Driver uses MASTER modport
    uvm_config_db#(virtual axi_if.MASTER_MP)::set(
      null, "uvm_test_top.env.agent.driver", "vif", axi_vif
    );

    // Monitor uses MON modport
    uvm_config_db#(virtual axi_if.MON_MP)::set(
      null, "uvm_test_top.env.agent.monitor", "vif", axi_vif
    );

    // Default test name (or override with +UVM_TESTNAME=xxx)
    run_test("axi_test");
  end

endmodule : axi_top
//------------------------------------------------------------------------------
// File    : axi_test.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : AXI4 UVM test suite.
//           - Builds axi_env and propagates common knobs via uvm_config_db
//             (verbose, enable_cov, base_addr, mem_bytes, check_addr, check_all_beats).
//           - Provides tests for M0/M1 bring-up:
//               * axi_test        : single write then single read (same address)
//               * axi_smoke_test  : multiple single write/read pairs across addresses
//               * axi_burst_test  : burst write then burst read
//               * axi_stress_test : randomized read/write + WSTRB stress
//           - M2 (multi-outstanding / out-of-order) is NOT implemented (stub only).
//             Current environment assumes single-outstanding and in-order responses.
//------------------------------------------------------------------------------
// Notes:
// - Default top (axi_top.sv) runs: run_test("axi_test").
// - You can override with: +UVM_TESTNAME=axi_smoke_test, axi_burst_test, ...
// - This project assumes single-outstanding read and write (DUT/driver/monitor).
// - This project currently targets M0/M1 bring-up:
//     * Single outstanding write + single outstanding read
//     * In-order responses
// - M2 (multi-outstanding / out-of-order return) is NOT implemented yet.
//   To enable true M2 testing, you must upgrade:
//     1) DUT: accept multiple AW/AR and queue requests
//     2) Driver: issue requests without waiting for B/R completion
//     3) Monitor: reconstruct transactions per-ID (queues/maps)
//     4) Scoreboard: robust OOO matching (by ID and/or tag), and RM consistency

//------------------------------------------------------------------------------

`ifndef _AXI_TEST_SV_
`define _AXI_TEST_SV_
//------------------------------------------------------------------------------
// Base test
//------------------------------------------------------------------------------
class axi_test extends uvm_test;
  `uvm_component_utils(axi_test)

  axi_env env;

  // common knobs
  bit verbose    = 0;
  bit enable_cov = 1;

  logic [`AXI_ADDR_WIDTH-1:0] base_addr       = `AXI_DEFAULT_BASE_ADDR;
  int unsigned                mem_bytes       = `AXI_DEFAULT_MEM_BYTES;
  bit                         check_addr      = 1;
  bit                         check_all_beats = 0;

  function new(string name="axi_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // allow override by plusargs/config_db from top
    void'(uvm_config_db#(bit)::get(this, "", "verbose",    verbose));
    void'(uvm_config_db#(bit)::get(this, "", "enable_cov", enable_cov));

    void'(uvm_config_db#(logic [`AXI_ADDR_WIDTH-1:0])::get(this, "", "base_addr", base_addr));
    void'(uvm_config_db#(int unsigned)::get(this, "", "mem_bytes", mem_bytes));
    void'(uvm_config_db#(bit)::get(this, "", "check_addr", check_addr));
    void'(uvm_config_db#(bit)::get(this, "", "check_all_beats", check_all_beats));

    // push env knobs down
    uvm_config_db#(bit)::set(this, "env", "verbose",    verbose);
    uvm_config_db#(bit)::set(this, "env", "enable_cov", enable_cov);

    uvm_config_db#(logic [`AXI_ADDR_WIDTH-1:0])::set(this, "env", "base_addr", base_addr);
    uvm_config_db#(int unsigned)::set(this, "env", "mem_bytes", mem_bytes);
    uvm_config_db#(bit)::set(this, "env", "check_addr", check_addr);
    uvm_config_db#(bit)::set(this, "env", "check_all_beats", check_all_beats);

    env = axi_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_single_write_seq wr0;
    axi_single_read_seq  rd0;

    phase.raise_objection(this);

    // basic sanity: env.agent must be ACTIVE to have sequencer
    if (env.agent == null || env.agent.sequencer == null) begin
      `uvm_fatal(get_type_name(),
        "No sequencer found. Ensure agent is ACTIVE (UVM_ACTIVE) and env/agent created correctly.")
    end

    // M0 smoke: 1 write then 1 read (same addr)
    wr0 = axi_single_write_seq::type_id::create("wr0");
    rd0 = axi_single_read_seq ::type_id::create("rd0");

    // make them hit the same location (simple bring-up)
    wr0.addr = base_addr + 32'h000;
    rd0.addr = wr0.addr;

    // run sequences
    wr0.start(env.agent.sequencer);
    rd0.start(env.agent.sequencer);

    phase.drop_objection(this);
  endtask

endclass : axi_test

//------------------------------------------------------------------------------
// axi_smoke_test: a bit more coverage than axi_test (still M0)
//------------------------------------------------------------------------------
class axi_smoke_test extends axi_test;
  `uvm_component_utils(axi_smoke_test)

  function new(string name="axi_smoke_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    if (env.agent == null || env.agent.sequencer == null)
      `uvm_fatal(get_type_name(), "No sequencer found (agent must be ACTIVE).")

    // few single writes/reads across addresses
    for (int i = 0; i < 8; i++) begin
      axi_single_write_seq wr;
      axi_single_read_seq  rd;
      logic [`AXI_ADDR_WIDTH-1:0] a;

      a = base_addr + (i * 4);

      wr = axi_single_write_seq::type_id::create($sformatf("wr_%0d", i));
      rd = axi_single_read_seq ::type_id::create($sformatf("rd_%0d", i));

      wr.addr = a;
      rd.addr = a;

      // randomize id if you want; keep default size/len
      void'(wr.randomize() with { len==0; size==3'd2; });
      void'(rd.randomize() with { len==0; size==3'd2; });

      wr.start(env.agent.sequencer);
      rd.start(env.agent.sequencer);
    end

    phase.drop_objection(this);
  endtask

endclass : axi_smoke_test

//------------------------------------------------------------------------------
// axi_burst_test: M1 (burst write/read)
//------------------------------------------------------------------------------
class axi_burst_test extends axi_test;
  `uvm_component_utils(axi_burst_test)

  function new(string name="axi_burst_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_burst_write_seq bwr;
    axi_burst_read_seq  brd;

    phase.raise_objection(this);

    if (env.agent == null || env.agent.sequencer == null)
      `uvm_fatal(get_type_name(), "No sequencer found (agent must be ACTIVE).")

    bwr = axi_burst_write_seq::type_id::create("bwr");
    brd = axi_burst_read_seq ::type_id::create("brd");

    // make them share address; burst len is randomized by constraint (3..15)
    bwr.addr = base_addr + 32'h100;
    brd.addr = bwr.addr;

    // keep 32-bit word size for simplicity
    void'(bwr.randomize() with { size==3'd2; });
    void'(brd.randomize() with { size==3'd2; len==bwr.len; }); // match beats

    bwr.start(env.agent.sequencer);
    brd.start(env.agent.sequencer);

    phase.drop_objection(this);
  endtask

endclass : axi_burst_test

//------------------------------------------------------------------------------
// axi_stress_test: random mix read/write + random strobe
//------------------------------------------------------------------------------
class axi_stress_test extends axi_test;
  `uvm_component_utils(axi_stress_test)

  function new(string name="axi_stress_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_stress_seq s;

    phase.raise_objection(this);

    if (env.agent == null || env.agent.sequencer == null)
      `uvm_fatal(get_type_name(), "No sequencer found (agent must be ACTIVE).")

    s = axi_stress_seq::type_id::create("s");
    void'(s.randomize() with { num_iters inside {[50:200]}; });

    s.start(env.agent.sequencer);

    phase.drop_objection(this);
  endtask

endclass : axi_stress_test

//------------------------------------------------------------------------------
// axi_outstanding_test: M2 stub (will warn, not generate real outstanding)
//------------------------------------------------------------------------------
class axi_outstanding_test extends axi_test;
  `uvm_component_utils(axi_outstanding_test)

  function new(string name="axi_outstanding_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_outstanding_seq o;

    phase.raise_objection(this);

    if (env.agent == null || env.agent.sequencer == null)
      `uvm_fatal(get_type_name(), "No sequencer found (agent must be ACTIVE).")

    o = axi_outstanding_seq::type_id::create("o");
    o.start(env.agent.sequencer);

    phase.drop_objection(this);
  endtask

endclass : axi_outstanding_test

`endif // _AXI_TEST_SV_
//------------------------------------------------------------------------------
// File    : axi_env.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : Top-level AXI4 UVM environment. Instantiates agent, reference model,
//           scoreboard, and optional coverage subscriber. Connects monitor
//           streams to scoreboard/model/coverage and exports predicted stream
//           to scoreboard.
//------------------------------------------------------------------------------
//
// Notes:
// - Agent provides: driver/sequencer (ACTIVE) + monitor (always)
// - Monitor publishes axi_seq_item on agent.ap
// - Scoreboard consumes ACT from monitor, generates EXP internally via ref model
// - Coverage subscriber consumes same ACT stream
// - Ref model can be configured here (base/mem/check knobs)
//------------------------------------------------------------------------------

`ifndef _AXI_ENV_SV_
`define _AXI_ENV_SV_

class axi_env extends uvm_env;
  `uvm_component_utils(axi_env)

  // Components
  axi_agent          agent;
  axi_ref_model      rm;
  axi_scoreboard     sb;
  axi_cov_subscriber cov;   // optional

  // Knobs
  bit enable_cov = 1;
  bit verbose    = 0;

  // RM config knobs (default align with axi_mem_slave)
  logic [`AXI_ADDR_WIDTH-1:0] base_addr       = `AXI_DEFAULT_BASE_ADDR;
  int unsigned                mem_bytes       = `AXI_DEFAULT_MEM_BYTES;
  bit                         check_addr      = 1;
  bit                         check_all_beats = 0;

  extern function new(string name="axi_env", uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);

endclass : axi_env

function axi_env::new(string name="axi_env", uvm_component parent=null);
  super.new(name, parent);
endfunction

function void axi_env::build_phase(uvm_phase phase);
  super.build_phase(phase);

  // Allow override via config_db (optional)
  void'(uvm_config_db#(bit)::get(this, "", "enable_cov", enable_cov));
  void'(uvm_config_db#(bit)::get(this, "", "verbose",    verbose));

  void'(uvm_config_db#(logic [`AXI_ADDR_WIDTH-1:0])::get(this, "", "base_addr", base_addr));
  void'(uvm_config_db#(int unsigned)::get(this, "", "mem_bytes", mem_bytes));
  void'(uvm_config_db#(bit)::get(this, "", "check_addr", check_addr));
  void'(uvm_config_db#(bit)::get(this, "", "check_all_beats", check_all_beats));

  // Agent
  agent = axi_agent::type_id::create("agent", this);

  // Reference model (shared handle if you want to use elsewhere)
  rm = axi_ref_model::type_id::create("rm", this);
  rm.configure(base_addr, mem_bytes, check_addr, /*clear_mem*/ 1, /*check_all_beats*/ check_all_beats);

  // Scoreboard
  sb = axi_scoreboard::type_id::create("scoreboard", this);

  // Tell scoreboard to use our RM (so env controls config)
  sb.rm = rm;

  // Coverage (optional)
  if (enable_cov) begin
    cov = axi_cov_subscriber::type_id::create("cov", this);
  end

  // Optional: propagate verbosity
  sb.verbose = verbose;
  if (enable_cov && (cov != null)) begin
    // cov doesn't have verbose knob; keep as-is
  end
endfunction

function void axi_env::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  // Plan-B streams -> Scoreboard
  agent.req_ap.connect(sb.req_imp);
  agent.rsp_ap.connect(sb.rsp_imp);

  // legacy stream -> Coverage (保留)
  if (enable_cov && (cov != null)) begin
    agent.ap.connect(cov.analysis_export);
  end
endfunction


`endif // _AXI_ENV_SV_
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
//------------------------------------------------------------------------------
// File    : axi_sequencer.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : AXI sequencer for UVM TB. Arbitrates sequences that generate
//           axi_seq_item transactions and provides them to axi_driver.
//------------------------------------------------------------------------------
//
// Notes:
// - This is a thin wrapper around uvm_sequencer#(axi_seq_item).
// - Keep it simple for bring-up; add arbitration knobs later if needed.
//------------------------------------------------------------------------------

`ifndef _AXI_SEQUENCER_SV_
`define _AXI_SEQUENCER_SV_

class axi_sequencer extends uvm_sequencer #(axi_seq_item);
  `uvm_component_utils(axi_sequencer)

  function new(string name="axi_sequencer", uvm_component parent=null);
    super.new(name, parent);
  endfunction

endclass : axi_sequencer

`endif // _AXI_SEQUENCER_SV_
//------------------------------------------------------------------------------
// File    : axi_sequences.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : Collection of AXI4 sequences in a single file. Includes basic
//           directed read/write sequences (M0), burst sequences (M1), and
//           optional stress/outstanding sequences (M2).
//
// Sequence list (brief-aligned):
// - axi_base_seq
// - axi_single_write_seq
// - axi_single_read_seq
// - axi_burst_write_seq
// - axi_burst_read_seq
// - axi_stress_seq        (random len/size/addr/strb; stall is DUT/driver controlled)
// - axi_outstanding_seq   (M2 stub; requires multi-outstanding support in DUT/driver/monitor/SB)
//------------------------------------------------------------------------------

`ifndef _AXI_SEQUENCES_SV_
`define _AXI_SEQUENCES_SV_

//------------------------------------------------------------------------------
// axi_base_seq
//------------------------------------------------------------------------------
class axi_base_seq extends uvm_sequence #(axi_seq_item);
  `uvm_object_utils(axi_base_seq)

  // knobs (can be overridden by tests)
  rand logic [`AXI_ADDR_WIDTH-1:0] base_addr = `AXI_DEFAULT_BASE_ADDR;
  rand int unsigned                mem_bytes = `AXI_DEFAULT_MEM_BYTES;

  function new(string name="axi_base_seq");
    super.new(name);
  endfunction

  // pick an aligned address for given bytes/beat
  function automatic logic [`AXI_ADDR_WIDTH-1:0] pick_addr_aligned(int unsigned bytes_per_beat);
    logic [`AXI_ADDR_WIDTH-1:0] a;
    int unsigned mask;
    if (bytes_per_beat == 0) bytes_per_beat = 1;
    mask = bytes_per_beat - 1;

    // choose within memory (simple)
    a = base_addr + $urandom_range(0, (mem_bytes > 0) ? (mem_bytes-1) : 0);

    // align down
    a = (a & ~logic'({`AXI_ADDR_WIDTH{1'b0}} | mask));
    return a;
  endfunction

  function automatic int unsigned bytes_from_size(input logic [2:0] size);
    int unsigned b;
    b = (1 << int'(size));
    if (b == 0) b = 1;
    if (b > `AXI_STRB_WIDTH) b = `AXI_STRB_WIDTH; // guard
    return b;
  endfunction

endclass : axi_base_seq

//------------------------------------------------------------------------------
// axi_single_write_seq (M0)
// - single burst write transaction (len may be 0 => 1 beat)
//------------------------------------------------------------------------------
class axi_single_write_seq extends axi_base_seq;
  `uvm_object_utils(axi_single_write_seq)

  // knobs
  rand logic [`AXI_ID_WIDTH-1:0]    id;
  rand logic [`AXI_ADDR_WIDTH-1:0]  addr;
  rand logic [7:0]                  len;   // beats-1
  rand logic [2:0]                  size;  // log2(bytes/beat)

  // by default: 1 beat, 4B
  constraint c_def {
    len  inside {[0:0]};
    size == 3'd2;
  }

  function new(string name="axi_single_write_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item tr;
    int unsigned beats;
    int unsigned nbytes;

    tr = axi_seq_item::type_id::create("tr");

    // Decide fields
    beats  = int'(len) + 1;
    if (beats == 0) beats = 1;
    nbytes = bytes_from_size(size);

    // If addr not preset by test, pick aligned
    if (addr === '0) addr = pick_addr_aligned(nbytes);

    start_item(tr);
    tr.rw    = AXI_WRITE;
    tr.id    = id;
    tr.addr  = addr;
    tr.len   = len;
    tr.size  = size;
    tr.burst = AXI_BURST_INCR;

    // payload arrays
    tr.wdata = new[beats];
    tr.wstrb = new[beats];
    tr.rdata = new[0];

    foreach (tr.wdata[i]) tr.wdata[i] = $urandom();
    foreach (tr.wstrb[i]) tr.wstrb[i] = {`AXI_STRB_WIDTH{1'b1}}; // full write

    finish_item(tr);
  endtask

endclass : axi_single_write_seq

//------------------------------------------------------------------------------
// axi_single_read_seq (M0)
// - single burst read transaction
//------------------------------------------------------------------------------
class axi_single_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_single_read_seq)

  // knobs
  rand logic [`AXI_ID_WIDTH-1:0]    id;
  rand logic [`AXI_ADDR_WIDTH-1:0]  addr;
  rand logic [7:0]                  len;   // beats-1
  rand logic [2:0]                  size;  // log2(bytes/beat)

  constraint c_def {
    len  inside {[0:0]};
    size == 3'd2;
  }

  function new(string name="axi_single_read_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item tr;
    int unsigned beats;
    int unsigned nbytes;

    tr = axi_seq_item::type_id::create("tr");

    beats  = int'(len) + 1;
    if (beats == 0) beats = 1;
    nbytes = bytes_from_size(size);

    if (addr === '0) addr = pick_addr_aligned(nbytes);

    start_item(tr);
    tr.rw    = AXI_READ;
    tr.id    = id;
    tr.addr  = addr;
    tr.len   = len;
    tr.size  = size;
    tr.burst = AXI_BURST_INCR;

    tr.rdata = new[beats]; // driver fills
    tr.wdata = new[0];
    tr.wstrb = new[0];

    finish_item(tr);
  endtask

endclass : axi_single_read_seq

//------------------------------------------------------------------------------
// axi_burst_write_seq (M1)
// - directed "burst write" (explicitly meant for len>0)
//------------------------------------------------------------------------------
class axi_burst_write_seq extends axi_single_write_seq;
  `uvm_object_utils(axi_burst_write_seq)

  // default: 4~16 beats
  constraint c_burst {
    len inside {[3:15]};
  }

  function new(string name="axi_burst_write_seq");
    super.new(name);
  endfunction

endclass : axi_burst_write_seq

//------------------------------------------------------------------------------
// axi_burst_read_seq (M1)
// - directed "burst read" (explicitly meant for len>0)
//------------------------------------------------------------------------------
class axi_burst_read_seq extends axi_single_read_seq;
  `uvm_object_utils(axi_burst_read_seq)

  constraint c_burst {
    len inside {[3:15]};
  }

  function new(string name="axi_burst_read_seq");
    super.new(name);
  endfunction

endclass : axi_burst_read_seq

//------------------------------------------------------------------------------
// axi_stress_seq (M1-ish / stress)
// - random mix of read/write, random len/size/addr, random WSTRB patterns.
// - NOTE about "stall":
//   * true stall patterns come from backpressure (READY low) or driver inserting bubbles.
//   * With your current DUT (axi_mem_slave), you can create stalls by:
//       - setting RD_LATENCY / WR_RESP_LATENCY in DUT
//       - or editing DUT to toggle WREADY/RVALID patterns
//   * With driver, you can implement "bubble injection" by occasionally deasserting
//     AWVALID/WVALID/ARVALID/RREADY even when it *could* handshake.
//------------------------------------------------------------------------------
class axi_stress_seq extends axi_base_seq;
  `uvm_object_utils(axi_stress_seq)

  rand int unsigned num_iters;

  // constrain iterations
  constraint c_iters { num_iters inside {[20:200]}; }

  function new(string name="axi_stress_seq");
    super.new(name);
  endfunction

  virtual task body();
    for (int unsigned k = 0; k < num_iters; k++) begin
      bit do_write;
      logic [2:0] size;
      logic [7:0] len;
      logic [`AXI_ADDR_WIDTH-1:0] addr;
      logic [`AXI_ID_WIDTH-1:0] id;

      do_write = $urandom_range(0,1);
      size     = $urandom_range(0, $clog2(`AXI_STRB_WIDTH)); // guarded-ish
      if (size > 3'd5) size = 3'd2; // safety for 32-bit bus
      len      = $urandom_range(0, 15); // 1~16 beats for bring-up
      id       = $urandom_range(0, (1<<`AXI_ID_WIDTH)-1);

      addr = pick_addr_aligned(bytes_from_size(size));

      if (do_write) begin
        axi_seq_item tr;
        int unsigned beats = int'(len)+1;
        if (beats == 0) beats = 1;

        tr = axi_seq_item::type_id::create($sformatf("wr_%0d", k));

        start_item(tr);
        tr.rw    = AXI_WRITE;
        tr.id    = id;
        tr.addr  = addr;
        tr.len   = len;
        tr.size  = size;
        tr.burst = AXI_BURST_INCR;

        tr.wdata = new[beats];
        tr.wstrb = new[beats];
        tr.rdata = new[0];

        foreach (tr.wdata[i]) tr.wdata[i] = $urandom();

        // random strobe per beat (ensure not all-zero)
        foreach (tr.wstrb[i]) begin
          tr.wstrb[i] = $urandom();
          if (tr.wstrb[i] == '0) tr.wstrb[i] = {`AXI_STRB_WIDTH{1'b1}};
        end

        finish_item(tr);
      end else begin
        axi_seq_item tr;
        int unsigned beats = int'(len)+1;
        if (beats == 0) beats = 1;

        tr = axi_seq_item::type_id::create($sformatf("rd_%0d", k));

        start_item(tr);
        tr.rw    = AXI_READ;
        tr.id    = id;
        tr.addr  = addr;
        tr.len   = len;
        tr.size  = size;
        tr.burst = AXI_BURST_INCR;

        tr.rdata = new[beats];
        tr.wdata = new[0];
        tr.wstrb = new[0];

        finish_item(tr);
      end
    end
  endtask

endclass : axi_stress_seq

//------------------------------------------------------------------------------
// axi_outstanding_seq (M2 stub)
// - INTENTION: create multiple outstanding reads/writes to test reordering.
// - CURRENT PROJECT LIMITATION:
//   Your DUT/driver/monitor assume "one outstanding write" and "one outstanding read"
//   and in-order completion. A true M2 outstanding test requires:
//
//   1) DUT (axi_mem_slave) supports accepting next AW/AR before previous completes.
//      - That means AWREADY/ARREADY can stay high and internally queue requests.
//      - R channel can return beats for different IDs interleaved (read interleaving),
//        and B responses can return out of order.
//
//   2) Driver supports issuing multiple items without waiting for responses,
//      OR has separate threads per channel + a response collector.
//
//   3) Monitor reconstructs transactions per-ID (queues/maps), not single w_tr/r_tr.
//
//   4) Scoreboard matching mode M2 must be enabled (ooo matching by ID / tag),
//      and reference model must handle out-of-order observation correctly.
//
// So here we only provide a stub that warns and does nothing harmful.
//------------------------------------------------------------------------------
class axi_outstanding_seq extends axi_base_seq;
  `uvm_object_utils(axi_outstanding_seq)

  function new(string name="axi_outstanding_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_warning(get_type_name(),
    {"axi_outstanding_seq is a STUB. Your current DUT/driver/monitor are single-outstanding.\n",
    "To implement true M2 outstanding, upgrade DUT (queue requests), driver (issue without waiting),\n",
    "monitor (per-ID reconstruction), and scoreboard (enable_ooo_match + robust matching)."}
    );
    // no-op
  endtask

endclass : axi_outstanding_seq

`endif // _AXI_SEQUENCES_SV_
//------------------------------------------------------------------------------
// File    : axi_tb_pkg.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : AXI4 UVM testbench package. Central compile unit that imports UVM,
//           includes all TB classes (seq_item, sequencer, driver, monitor,
//           agent, ref model, scoreboard, coverage subscriber, env, tests,
//           sequences) and exposes them via a single package import.
//------------------------------------------------------------------------------

`ifndef _AXI_TB_PKG_SV_
`define _AXI_TB_PKG_SV_

package axi_tb_pkg;

//   // UVM
//   import uvm_pkg::*;
//   `include "uvm_macros.svh"

//   // Project common headers
//   `include "axi_defines.sv"
//   `include "axi_types.sv"

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  `include "axi_defines.sv"

  // `include "axi_common_pkg.sv"
  import axi_common_pkg::*;

  // NOTE:
  // - axi_if.sv is an interface (not a class). You usually compile it as a normal SV
  //   file, not inside a package. (You already `include "axi_if.sv" in axi_top.sv.)
  // - axi_mem_slave.sv is DUT module. Also compile separately, not in package.
  // - axi_top.sv is the simulation top. Not in package.

  // TB classes (order matters for dependencies)
  `include "axi_seq_item.sv"
  `include "axi_sequencer.sv"
  `include "axi_driver.sv"
  `include "axi_monitor.sv"
  `include "axi_agent.sv"

  `include "axi_ref_model.sv"
  `include "axi_scoreboard.sv"
  `include "axi_cov_subscriber.sv"
  `include "axi_env.sv"

  `include "axi_sequences.sv"
  `include "axi_test.sv"

endpackage : axi_tb_pkg

`endif // _AXI_TB_PKG_SV_
//------------------------------------------------------------------------------
// File    : axi_if.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : AXI4 SystemVerilog interface for UVM TB. Defines AW/W/B/AR/R signal
//           bundles, provides clocking blocks for cycle-accurate driving and
//           sampling, exposes MASTER/MON modports for virtual interface binding,
//           and includes basic handshake stability assertions (VALID-hold).
//------------------------------------------------------------------------------
//
// Notes:
// - This interface is intentionally "AXI4-full" oriented (supports bursts & IDs).
// - Keep this interface as the single source of truth for signal naming/sizing.
// - Assertions here are minimal and safe for bring-up. Add more as you mature.
// - This project intentionally ignores all AXI4 *USER sideband signals
//   (AWUSER/WUSER/BUSER/ARUSER/RUSER). They are optional and user-defined,
//   so we omit them to keep the DUT/TB minimal and interoperable.
//   If needed later, add them with a configurable AXI_USER_WIDTH and treat
//   unused values as constant '0.
//------------------------------------------------------------------------------

`ifndef _AXI_IF_SV_
`define _AXI_IF_SV_
import axi_common_pkg::*;
interface axi_if (
  input  logic ACLK,
  input  logic ARESETn
);

  //--------------------------------------------------------------------------
  // Write Address Channel (AW)
  //--------------------------------------------------------------------------
  logic [`AXI_ID_WIDTH-1:0]   AWID;
  logic [`AXI_ADDR_WIDTH-1:0] AWADDR;
  logic [7:0]                 AWLEN;    // beats-1
  logic [2:0]                 AWSIZE;   // log2(bytes/beat)
  axi_burst_e                 AWBURST;
  logic                       AWLOCK;   // AXI4: 1-bit
  logic [3:0]                 AWCACHE;
  logic [2:0]                 AWPROT;
  logic [3:0]                 AWQOS;
  logic [3:0]                 AWREGION;
  logic                       AWVALID;
  logic                       AWREADY;

  //--------------------------------------------------------------------------
  // Write Data Channel (W)
  //--------------------------------------------------------------------------
  logic [`AXI_DATA_WIDTH-1:0] WDATA;
  logic [`AXI_STRB_WIDTH-1:0] WSTRB;
  logic                       WLAST;
  logic                       WVALID;
  logic                       WREADY;

  //--------------------------------------------------------------------------
  // Write Response Channel (B)
  //--------------------------------------------------------------------------
  logic [`AXI_ID_WIDTH-1:0]   BID;
  axi_resp_e                  BRESP;
  logic                       BVALID;
  logic                       BREADY;

  //--------------------------------------------------------------------------
  // Read Address Channel (AR)
  //--------------------------------------------------------------------------
  logic [`AXI_ID_WIDTH-1:0]   ARID;
  logic [`AXI_ADDR_WIDTH-1:0] ARADDR;
  logic [7:0]                 ARLEN;    // beats-1
  logic [2:0]                 ARSIZE;   // log2(bytes/beat)
  axi_burst_e                 ARBURST;
  logic                       ARLOCK;   // AXI4: 1-bit
  logic [3:0]                 ARCACHE;
  logic [2:0]                 ARPROT;
  logic [3:0]                 ARQOS;
  logic [3:0]                 ARREGION;
  logic                       ARVALID;
  logic                       ARREADY;

  //--------------------------------------------------------------------------
  // Read Data Channel (R)
  //--------------------------------------------------------------------------
  logic [`AXI_ID_WIDTH-1:0]   RID;
  logic [`AXI_DATA_WIDTH-1:0] RDATA;
  axi_resp_e                  RRESP;
  logic                       RLAST;
  logic                       RVALID;
  logic                       RREADY;

  //--------------------------------------------------------------------------
  // Clocking blocks
  //--------------------------------------------------------------------------
  // Master driver clocking block (drives requests, receives responses)
  clocking m_cb @(posedge ACLK);
    default input #1step output #0;
    // AW
    output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION, AWVALID;
    input  AWREADY;
    // W
    output WDATA, WSTRB, WLAST, WVALID;
    input  WREADY;
    // B
    input  BID, BRESP, BVALID;
    output BREADY;
    // AR
    output ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARVALID;
    input  ARREADY;
    // R
    input  RID, RDATA, RRESP, RLAST, RVALID;
    output RREADY;
  endclocking

  // Passive monitor clocking block (samples everything)
  clocking mon_cb @(posedge ACLK);
    default input #1step output #0;
    // AW
    input AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION, AWVALID, AWREADY;
    // W
    input WDATA, WSTRB, WLAST, WVALID, WREADY;
    // B
    input BID, BRESP, BVALID, BREADY;
    // AR
    input ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARVALID, ARREADY;
    // R
    input RID, RDATA, RRESP, RLAST, RVALID, RREADY;
  endclocking

  //--------------------------------------------------------------------------
  // Modports (for virtual interface binding)
  //--------------------------------------------------------------------------
  modport MASTER_MP (clocking m_cb, input ACLK, input ARESETn);
  modport MON_MP    (clocking mon_cb, input ACLK, input ARESETn);

  //--------------------------------------------------------------------------
  // Minimal protocol assertions (bring-up friendly)
  //--------------------------------------------------------------------------
  // VALID-hold rule: once VALID is asserted, payload must stay stable until handshake occurs.
  // (We only assert stability when VALID=1 and READY=0.)

  // AW stable while waiting
  property p_aw_valid_hold;
    @(posedge ACLK) disable iff (!ARESETn)
      (AWVALID && !AWREADY) |-> $stable({AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION});
  endproperty
  a_aw_valid_hold: assert property (p_aw_valid_hold);

  // W stable while waiting
  property p_w_valid_hold;
    @(posedge ACLK) disable iff (!ARESETn)
      (WVALID && !WREADY) |-> $stable({WDATA, WSTRB, WLAST});
  endproperty
  a_w_valid_hold: assert property (p_w_valid_hold);

  // AR stable while waiting
  property p_ar_valid_hold;
    @(posedge ACLK) disable iff (!ARESETn)
      (ARVALID && !ARREADY) |-> $stable({ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION});
  endproperty
  a_ar_valid_hold: assert property (p_ar_valid_hold);

  // B channel: response must stay stable while waiting for BREADY
  property p_b_valid_hold;
    @(posedge ACLK) disable iff (!ARESETn)
      (BVALID && !BREADY) |-> $stable({BID, BRESP});
  endproperty
  a_b_valid_hold: assert property (p_b_valid_hold);

  // R channel: response/data must stay stable while waiting for RREADY
  property p_r_valid_hold;
    @(posedge ACLK) disable iff (!ARESETn)
      (RVALID && !RREADY) |-> $stable({RID, RDATA, RRESP, RLAST});
  endproperty
  a_r_valid_hold: assert property (p_r_valid_hold);

endinterface

`endif // _AXI_IF_SV_
//------------------------------------------------------------------------------
// File    : axi_mem_slave.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : Simple AXI4 memory-mapped slave DUT. Supports INCR bursts for read
//           and write, WSTRB byte enables, programmable response latency, and
//           optional address range checking (DECERR/SLVERR). Intended as a
//           learning DUT for AXI4 UVM verification.
//------------------------------------------------------------------------------
//
// Supported (M0/M1 bring-up target):
// - INCR bursts on AW/AR
// - WSTRB byte enables
// - Backpressure on W/R via WREADY/RVALID handshake (basic)
// - One outstanding write + one outstanding read at a time (simple design)
//
// Not supported (will respond with error):
// - FIXED/WRAP bursts (BRESP/RRESP = SLVERR)
// - Multiple outstanding writes/reads (AWREADY/ARREADY deassert while busy)
//
// Notes:
// - USER signals are intentionally omitted in this project.
// - Data is stored in a byte-addressable memory array.
//------------------------------------------------------------------------------

`ifndef _AXI_MEM_SLAVE_SV_
`define _AXI_MEM_SLAVE_SV_
import axi_common_pkg::*;
module axi_mem_slave #(
  parameter logic [`AXI_ADDR_WIDTH-1:0] BASE_ADDR      = `AXI_DEFAULT_BASE_ADDR,
  parameter int unsigned                MEM_BYTES      = `AXI_DEFAULT_MEM_BYTES,

  // Latency knobs (in cycles)
  parameter int unsigned                RD_LATENCY     = 0,  // delay from AR handshake to first RVALID
  parameter int unsigned                WR_RESP_LATENCY= 0,  // delay from last W beat handshake to BVALID

  // Address checking
  parameter bit                         CHECK_ADDR     = 1
)(
  input  logic                          ACLK,
  input  logic                          ARESETn,

  // -------------------------
  // AW channel
  // -------------------------
  input  logic [`AXI_ID_WIDTH-1:0]       AWID,
  input  logic [`AXI_ADDR_WIDTH-1:0]     AWADDR,
  input  logic [7:0]                     AWLEN,
  input  logic [2:0]                     AWSIZE,
  input  axi_burst_e                     AWBURST,
  input  logic                           AWLOCK,
  input  logic [3:0]                     AWCACHE,
  input  logic [2:0]                     AWPROT,
  input  logic [3:0]                     AWQOS,
  input  logic [3:0]                     AWREGION,
  input  logic                           AWVALID,
  output logic                           AWREADY,

  // -------------------------
  // W channel
  // -------------------------
  input  logic [`AXI_DATA_WIDTH-1:0]     WDATA,
  input  logic [`AXI_STRB_WIDTH-1:0]     WSTRB,
  input  logic                          WLAST,
  input  logic                          WVALID,
  output logic                          WREADY,

  // -------------------------
  // B channel
  // -------------------------
  output logic [`AXI_ID_WIDTH-1:0]       BID,
  output axi_resp_e                      BRESP,
  output logic                          BVALID,
  input  logic                          BREADY,

  // -------------------------
  // AR channel
  // -------------------------
  input  logic [`AXI_ID_WIDTH-1:0]       ARID,
  input  logic [`AXI_ADDR_WIDTH-1:0]     ARADDR,
  input  logic [7:0]                    ARLEN,
  input  logic [2:0]                    ARSIZE,
  input  axi_burst_e                     ARBURST,
  input  logic                          ARLOCK,
  input  logic [3:0]                    ARCACHE,
  input  logic [2:0]                    ARPROT,
  input  logic [3:0]                    ARQOS,
  input  logic [3:0]                    ARREGION,
  input  logic                          ARVALID,
  output logic                          ARREADY,

  // -------------------------
  // R channel
  // -------------------------
  output logic [`AXI_ID_WIDTH-1:0]       RID,
  output logic [`AXI_DATA_WIDTH-1:0]     RDATA,
  output axi_resp_e                      RRESP,
  output logic                          RLAST,
  output logic                          RVALID,
  input  logic                          RREADY
);

  // -------------------------
  // Byte-addressable memory
  // -------------------------
  logic [7:0] mem [0:MEM_BYTES-1];

  // -------------------------
  // Helpers
  // -------------------------
  function automatic int unsigned bytes_per_beat(input logic [2:0] size);
    return (1 << int'(size));
  endfunction

  function automatic bit addr_in_range(input logic [`AXI_ADDR_WIDTH-1:0] a);
    if (!CHECK_ADDR) return 1'b1;
    // treat address as byte address
    return (a >= BASE_ADDR) && (a < (BASE_ADDR + MEM_BYTES));
  endfunction

  function automatic int unsigned mem_index(input logic [`AXI_ADDR_WIDTH-1:0] a);
    // assumes a is in range
    return int'(a - BASE_ADDR);
  endfunction

  function automatic axi_resp_e burst_supported_resp(input axi_burst_e b);
    // only INCR supported in this learning DUT
    if (b == AXI_BURST_INCR) return AXI_RESP_OKAY;
    else                    return AXI_RESP_SLVERR;
  endfunction

  // Read a beat (full DATA_WIDTH) from byte memory; bytes outside range -> 0
  function automatic logic [`AXI_DATA_WIDTH-1:0] read_beat(
    input logic [`AXI_ADDR_WIDTH-1:0] addr,
    input int unsigned                nbytes
  );
    logic [`AXI_DATA_WIDTH-1:0] tmp;
    tmp = '0;
    for (int i = 0; i < `AXI_STRB_WIDTH; i++) begin
      if (i < nbytes) begin
        logic [`AXI_ADDR_WIDTH-1:0] ba = addr + i;
        if (addr_in_range(ba)) tmp[i*8 +: 8] = mem[mem_index(ba)];
        else                   tmp[i*8 +: 8] = 8'h00;
      end
    end
    return tmp;
  endfunction

  // Write a beat into byte memory using WSTRB; bytes outside range ignored
  task automatic write_beat(
    input logic [`AXI_ADDR_WIDTH-1:0] addr,
    input logic [`AXI_DATA_WIDTH-1:0] data,
    input logic [`AXI_STRB_WIDTH-1:0] strb,
    input int unsigned                nbytes
  );
    for (int i = 0; i < `AXI_STRB_WIDTH; i++) begin
      if (i < nbytes && strb[i]) begin
        logic [`AXI_ADDR_WIDTH-1:0] ba = addr + i;
        if (addr_in_range(ba)) mem[mem_index(ba)] = data[i*8 +: 8];
      end
    end
  endtask

  // -------------------------
  // Write channel state
  // -------------------------
  typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP_WAIT, W_RESP} w_state_e;
  w_state_e w_state;

  logic [`AXI_ID_WIDTH-1:0]       awid_q;
  logic [`AXI_ADDR_WIDTH-1:0]     awaddr_q;
  logic [7:0]                    awlen_q;
  logic [2:0]                    awsize_q;
  axi_burst_e                     awburst_q;

  int unsigned                    w_beats_total;
  int unsigned                    w_beat_idx;
  int unsigned                    w_bytes;
  int unsigned                    w_resp_cnt;
  axi_resp_e                      w_base_resp;   // OKAY or SLVERR for unsupported burst
  axi_resp_e                      w_range_resp;  // OKAY or DECERR based on addr range

  // -------------------------
  // Read channel state
  // -------------------------
  typedef enum logic [1:0] {R_IDLE, R_WAIT, R_SEND} r_state_e;
  r_state_e r_state;

  logic [`AXI_ID_WIDTH-1:0]       arid_q;
  logic [`AXI_ADDR_WIDTH-1:0]     araddr_q;
  logic [7:0]                    arlen_q;
  logic [2:0]                    arsize_q;
  axi_burst_e                     arburst_q;

  int unsigned                    r_beats_total;
  int unsigned                    r_beat_idx;
  int unsigned                    r_bytes;
  int unsigned                    r_lat_cnt;
  axi_resp_e                      r_base_resp;
  axi_resp_e                      r_range_resp;

  // -------------------------
  // Combinational READYs (simple)
  // -------------------------
  always_comb begin
    AWREADY = (w_state == W_IDLE);
    WREADY  = (w_state == W_DATA);
    ARREADY = (r_state == R_IDLE);
  end

  // -------------------------
  // Sequential logic
  // -------------------------
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      // init memory to 0
      for (int i = 0; i < MEM_BYTES; i++) begin
        mem[i] <= 8'h00;
      end

      // write state reset
      w_state       <= W_IDLE;
      awid_q        <= '0;
      awaddr_q      <= '0;
      awlen_q       <= '0;
      awsize_q      <= '0;
      awburst_q     <= AXI_BURST_INCR;
      w_beats_total <= 0;
      w_beat_idx    <= 0;
      w_bytes       <= 0;
      w_resp_cnt    <= 0;
      w_base_resp   <= AXI_RESP_OKAY;
      w_range_resp  <= AXI_RESP_OKAY;

      BID           <= '0;
      BRESP         <= AXI_RESP_OKAY;
      BVALID        <= 1'b0;

      // read state reset
      r_state       <= R_IDLE;
      arid_q        <= '0;
      araddr_q      <= '0;
      arlen_q       <= '0;
      arsize_q      <= '0;
      arburst_q     <= AXI_BURST_INCR;
      r_beats_total <= 0;
      r_beat_idx    <= 0;
      r_bytes       <= 0;
      r_lat_cnt     <= 0;
      r_base_resp   <= AXI_RESP_OKAY;
      r_range_resp  <= AXI_RESP_OKAY;

      RID           <= '0;
      RDATA         <= '0;
      RRESP         <= AXI_RESP_OKAY;
      RLAST         <= 1'b0;
      RVALID        <= 1'b0;
    end else begin
      // -------------------------
      // WRITE FSM
      // -------------------------
      case (w_state)
        W_IDLE: begin
          BVALID <= 1'b0;
          if (AWVALID && AWREADY) begin
            awid_q        <= AWID;
            awaddr_q      <= AWADDR;
            awlen_q       <= AWLEN;
            awsize_q      <= AWSIZE;
            awburst_q     <= AWBURST;

            w_beats_total <= int'(AWLEN) + 1;
            w_beat_idx    <= 0;
            w_bytes       <= bytes_per_beat(AWSIZE);

            w_base_resp   <= burst_supported_resp(AWBURST);

            // Range check policy:
            // - if any accessed byte is out of range => DECERR
            // For simplicity we only check the first address here and let per-byte
            // writes silently drop out-of-range bytes; TB can tighten later.
            w_range_resp  <= (CHECK_ADDR && !addr_in_range(AWADDR)) ? AXI_RESP_DECERR : AXI_RESP_OKAY;

            w_state       <= W_DATA;
          end
        end

        W_DATA: begin
          // Accept W beats
          if (WVALID && WREADY) begin
            logic [`AXI_ADDR_WIDTH-1:0] beat_addr;
            beat_addr = awaddr_q + (w_beat_idx * w_bytes);

            // perform write (even if out-of-range: drops out-of-range bytes)
            write_beat(beat_addr, WDATA, WSTRB, w_bytes);

            // advance beat index
            if (w_beat_idx + 1 >= w_beats_total) begin
              // Expect WLAST at final beat (learning DUT)
              // If missing/mismatched, we still complete but could be tightened to SLVERR.
              w_resp_cnt <= 0;
              w_state    <= (WR_RESP_LATENCY == 0) ? W_RESP : W_RESP_WAIT;
            end else begin
              w_beat_idx <= w_beat_idx + 1;
            end
          end
        end

        W_RESP_WAIT: begin
          if (w_resp_cnt + 1 >= WR_RESP_LATENCY) begin
            w_state <= W_RESP;
          end else begin
            w_resp_cnt <= w_resp_cnt + 1;
          end
        end

        W_RESP: begin
          // Drive response until accepted
          BID   <= awid_q;
          // Combine errors: unsupported burst -> SLVERR, out-of-range -> DECERR
          if (w_base_resp != AXI_RESP_OKAY)      BRESP <= w_base_resp;
          else if (w_range_resp != AXI_RESP_OKAY)BRESP <= w_range_resp;
          else                                  BRESP <= AXI_RESP_OKAY;

          BVALID <= 1'b1;

          if (BVALID && BREADY) begin
            BVALID  <= 1'b0;
            w_state <= W_IDLE;
          end
        end

        default: w_state <= W_IDLE;
      endcase

      // -------------------------
      // READ FSM
      // -------------------------
      case (r_state)
        R_IDLE: begin
          RVALID <= 1'b0;
          RLAST  <= 1'b0;

          if (ARVALID && ARREADY) begin
            arid_q        <= ARID;
            araddr_q      <= ARADDR;
            arlen_q       <= ARLEN;
            arsize_q      <= ARSIZE;
            arburst_q     <= ARBURST;

            r_beats_total <= int'(ARLEN) + 1;
            r_beat_idx    <= 0;
            r_bytes       <= bytes_per_beat(ARSIZE);

            r_base_resp   <= burst_supported_resp(ARBURST);
            r_range_resp  <= (CHECK_ADDR && !addr_in_range(ARADDR)) ? AXI_RESP_DECERR : AXI_RESP_OKAY;

            r_lat_cnt     <= 0;
            r_state       <= (RD_LATENCY == 0) ? R_SEND : R_WAIT;
          end
        end

        R_WAIT: begin
          if (r_lat_cnt + 1 >= RD_LATENCY) begin
            r_state <= R_SEND;
          end else begin
            r_lat_cnt <= r_lat_cnt + 1;
          end
        end

        R_SEND: begin
          // Hold stable while RVALID && !RREADY (AXI rule)
          if (!RVALID || (RVALID && RREADY)) begin
            logic [`AXI_ADDR_WIDTH-1:0] beat_addr;
            beat_addr = araddr_q + (r_beat_idx * r_bytes);

            RID   <= arid_q;
            RDATA <= read_beat(beat_addr, r_bytes);

            if (r_base_resp != AXI_RESP_OKAY)       RRESP <= r_base_resp;
            else if (r_range_resp != AXI_RESP_OKAY) RRESP <= r_range_resp;
            else                                    RRESP <= AXI_RESP_OKAY;

            RLAST <= (r_beat_idx + 1 >= r_beats_total);
            RVALID<= 1'b1;
          end

          if (RVALID && RREADY) begin
            if (RLAST) begin
              RVALID <= 1'b0;
              RLAST  <= 1'b0;
              r_state<= R_IDLE;
            end else begin
              r_beat_idx <= r_beat_idx + 1;
            end
          end
        end

        default: r_state <= R_IDLE;
      endcase
    end
  end

endmodule

`endif // _AXI_MEM_SLAVE_SV_
//------------------------------------------------------------------------------
// File    : axi_monitor.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : UVM AXI4 passive monitor.
//           - Publishes full axi_seq_item on ap (legacy/coverage)
//           - Publishes Plan-B event streams:
//               req_ap : AW/AR handshake events
//               rsp_ap : B handshake + each R beat events
//------------------------------------------------------------------------------
// Assumptions (bring-up):
// - One outstanding write at a time and one outstanding read at a time
// - In-order responses
//------------------------------------------------------------------------------

`ifndef _AXI_MONITOR_SV_
`define _AXI_MONITOR_SV_

class axi_monitor extends uvm_monitor;
  `uvm_component_utils(axi_monitor)

  virtual axi_if.MON_MP vif;

  // legacy: publish observed full transactions
  uvm_analysis_port #(axi_seq_item) ap;

  // Plan-B streams
  uvm_analysis_port #(axi_req_evt) req_ap;   // AW/AR handshake
  uvm_analysis_port #(axi_rsp_evt) rsp_ap;   // B handshake + R beats

  // tag counters per ID (separate for AW and AR)
  int unsigned aw_tag_cnt[int unsigned];
  int unsigned ar_tag_cnt[int unsigned];

  bit verbose = 0;

  // internal state (single outstanding)
  axi_seq_item w_tr;
  axi_seq_item r_tr;

  // beat tracking
  int unsigned w_beats_total;
  int unsigned w_beat_idx;

  int unsigned r_beats_total;
  int unsigned r_beat_idx;

  extern function new(string name="axi_monitor", uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);

  extern virtual task wait_reset_release();
  extern virtual task collect_write();
  extern virtual task collect_read();

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
// WRITE collector
//------------------------------------------------------------------------------
task axi_monitor::collect_write();
  forever begin
    // ★宣告都放最上面（Questa 規則）
    int unsigned aw_stall;
    int unsigned b_stall;

    axi_req_evt  req;
    axi_rsp_evt  rsp;

    int unsigned id_key;
    int unsigned tag;

    // -------------------------
    // Wait AW handshake + count stall
    // -------------------------
    aw_stall = 0;
    do begin
      @(posedge vif.ACLK);
      if (vif.mon_cb.AWVALID && !vif.mon_cb.AWREADY) aw_stall++;
    end while (!(vif.mon_cb.AWVALID && vif.mon_cb.AWREADY));

    // -------------------------
    // Allocate + snapshot WRITE transaction
    // -------------------------
    w_tr = axi_seq_item::type_id::create("w_tr");
    w_tr.rw    = AXI_WRITE;
    w_tr.id    = vif.mon_cb.AWID;
    w_tr.addr  = vif.mon_cb.AWADDR;
    w_tr.len   = vif.mon_cb.AWLEN;
    w_tr.size  = vif.mon_cb.AWSIZE;
    w_tr.burst = vif.mon_cb.AWBURST;

    w_tr.beats = int'(w_tr.len) + 1;
    if (w_tr.beats == 0) w_tr.beats = 1;

    w_tr.wdata = new[w_tr.beats];
    w_tr.wstrb = new[w_tr.beats];
    w_tr.rdata = new[0];

    w_tr.aw_wait = aw_stall;
    w_tr.w_wait  = 0;
    w_tr.b_wait  = 0;
    w_tr.ar_wait = 0;
    w_tr.r_wait  = 0;

    w_beats_total = w_tr.beats;
    w_beat_idx    = 0;

    // -------------------------
    // Plan-B: emit AW REQ (tag generated here)
    // -------------------------
    id_key = int'(vif.mon_cb.AWID);
    if (aw_tag_cnt.exists(id_key)) aw_tag_cnt[id_key] = aw_tag_cnt[id_key] + 1;
    else                          aw_tag_cnt[id_key] = 0;
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

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("MON: AW hs id=0x%0h tag=%0d addr=0x%0h len=%0d size=%0d burst=%0d aw_stall=%0d",
                  w_tr.id, tag, w_tr.addr, w_tr.len, w_tr.size, w_tr.burst, w_tr.aw_wait),
        UVM_MEDIUM)
    end

    // -------------------------
    // Collect W beats + count W stall
    // -------------------------
    while (w_beat_idx < w_beats_total) begin
      do begin
        @(posedge vif.ACLK);
        if (vif.mon_cb.WVALID && !vif.mon_cb.WREADY) w_tr.w_wait++;
      end while (!(vif.mon_cb.WVALID && vif.mon_cb.WREADY));

      w_tr.wdata[w_beat_idx] = vif.mon_cb.WDATA;
      w_tr.wstrb[w_beat_idx] = vif.mon_cb.WSTRB;

      if ((w_beat_idx == w_beats_total-1) && (vif.mon_cb.WLAST !== 1'b1)) begin
        `uvm_warning(get_type_name(), "MON: expected WLAST=1 on final beat, but saw WLAST!=1")
      end
      if ((w_beat_idx != w_beats_total-1) && (vif.mon_cb.WLAST === 1'b1)) begin
        `uvm_warning(get_type_name(), "MON: saw early WLAST=1 before final beat")
      end

      w_beat_idx++;
    end

    // -------------------------
    // Wait B handshake + count stall
    // -------------------------
    b_stall = 0;
    do begin
      @(posedge vif.ACLK);
      if (vif.mon_cb.BVALID && !vif.mon_cb.BREADY) b_stall++;
    end while (!(vif.mon_cb.BVALID && vif.mon_cb.BREADY));

    w_tr.b_wait = b_stall;
    w_tr.resp   = vif.mon_cb.BRESP;

    // -------------------------
    // Plan-B: emit B RSP (use SAME tag)
    // -------------------------
    rsp = axi_rsp_evt::type_id::create("b_rsp");
    rsp.kind     = AXI_EVT_B;
    rsp.rw       = AXI_WRITE;
    rsp.id       = vif.mon_cb.BID;      // in-order assumption; should match AWID
    rsp.tag      = tag;
    rsp.beat_idx = 0;
    rsp.resp     = vif.mon_cb.BRESP;
    rsp.data     = '0;
    rsp.strb     = '0;
    rsp.last     = 1'b1;
    rsp_ap.write(rsp);

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("MON: B hs id=0x%0h tag=%0d resp=%0d b_stall=%0d (publish WRITE)",
                  vif.mon_cb.BID, tag, vif.mon_cb.BRESP, w_tr.b_wait),
        UVM_MEDIUM)
    end

    // legacy publish
    ap.write(w_tr);
  end
endtask

//------------------------------------------------------------------------------
// READ collector
//------------------------------------------------------------------------------
task axi_monitor::collect_read();
  forever begin
    // ★宣告都放最上面
    int unsigned ar_stall;

    axi_req_evt  req;
    axi_rsp_evt  rsp;

    int unsigned id_key;
    int unsigned tag;

    // -------------------------
    // Wait AR handshake + count stall
    // -------------------------
    ar_stall = 0;
    do begin
      @(posedge vif.ACLK);
      if (vif.mon_cb.ARVALID && !vif.mon_cb.ARREADY) ar_stall++;
    end while (!(vif.mon_cb.ARVALID && vif.mon_cb.ARREADY));

    // -------------------------
    // Allocate + snapshot READ transaction
    // -------------------------
    r_tr = axi_seq_item::type_id::create("r_tr");
    r_tr.rw    = AXI_READ;
    r_tr.id    = vif.mon_cb.ARID;
    r_tr.addr  = vif.mon_cb.ARADDR;
    r_tr.len   = vif.mon_cb.ARLEN;
    r_tr.size  = vif.mon_cb.ARSIZE;
    r_tr.burst = vif.mon_cb.ARBURST;

    r_tr.beats = int'(r_tr.len) + 1;
    if (r_tr.beats == 0) r_tr.beats = 1;

    r_tr.rdata = new[r_tr.beats];
    r_tr.wdata = new[0];
    r_tr.wstrb = new[0];

    r_tr.aw_wait = 0;
    r_tr.w_wait  = 0;
    r_tr.b_wait  = 0;
    r_tr.ar_wait = ar_stall;
    r_tr.r_wait  = 0;

    r_beats_total = r_tr.beats;
    r_beat_idx    = 0;

    // -------------------------
    // Plan-B: emit AR REQ (tag generated here)
    // -------------------------
    id_key = int'(vif.mon_cb.ARID);
    if (ar_tag_cnt.exists(id_key)) ar_tag_cnt[id_key] = ar_tag_cnt[id_key] + 1;
    else                          ar_tag_cnt[id_key] = 0;
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

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("MON: AR hs id=0x%0h tag=%0d addr=0x%0h len=%0d size=%0d burst=%0d ar_stall=%0d",
                  r_tr.id, tag, r_tr.addr, r_tr.len, r_tr.size, r_tr.burst, r_tr.ar_wait),
        UVM_MEDIUM)
    end

    // -------------------------
    // Collect R beats + emit per-beat R events
    // -------------------------
    while (r_beat_idx < r_beats_total) begin
      do begin
        @(posedge vif.ACLK);
        if (vif.mon_cb.RVALID && !vif.mon_cb.RREADY) r_tr.r_wait++;
      end while (!(vif.mon_cb.RVALID && vif.mon_cb.RREADY));

      r_tr.rdata[r_beat_idx] = vif.mon_cb.RDATA;
      r_tr.resp              = vif.mon_cb.RRESP; // keep last resp seen

      rsp = axi_rsp_evt::type_id::create($sformatf("r_rsp_%0d", r_beat_idx));
      rsp.kind     = AXI_EVT_R;
      rsp.rw       = AXI_READ;
      rsp.id       = vif.mon_cb.RID;     // should match ARID under assumption
      rsp.tag      = tag;
      rsp.beat_idx = r_beat_idx;
      rsp.resp     = vif.mon_cb.RRESP;
      rsp.data     = vif.mon_cb.RDATA;
      rsp.strb     = '0;
      rsp.last     = (vif.mon_cb.RLAST === 1'b1);
      rsp_ap.write(rsp);

      if ((r_beat_idx == r_beats_total-1) && (vif.mon_cb.RLAST !== 1'b1)) begin
        `uvm_warning(get_type_name(), "MON: expected RLAST=1 on final beat, but saw RLAST!=1")
      end
      if ((r_beat_idx != r_beats_total-1) && (vif.mon_cb.RLAST === 1'b1)) begin
        `uvm_warning(get_type_name(), "MON: saw early RLAST=1 before final beat")
      end

      r_beat_idx++;

      if (vif.mon_cb.RLAST) begin
        if (r_beat_idx != r_beats_total) begin
          `uvm_warning(get_type_name(), "MON: RLAST arrived before expected beats; truncating read capture")
        end
        break;
      end
    end

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("MON: READ done id=0x%0h tag=%0d resp=%0d r_stall=%0d (publish READ)",
                  r_tr.id, tag, r_tr.resp, r_tr.r_wait),
        UVM_MEDIUM)
    end

    // legacy publish
    ap.write(r_tr);
  end
endtask

`endif // _AXI_MONITOR_SV_
//------------------------------------------------------------------------------
// File    : axi_cov_subscriber.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : AXI4 functional coverage subscriber. Samples reconstructed
//           transactions from the monitor to track stimulus completeness
//           (read/write, burst length/type, size, response, stall patterns).
//------------------------------------------------------------------------------
`ifndef _AXI_COV_SUBSCRIBER_SV_
`define _AXI_COV_SUBSCRIBER_SV_

class axi_cov_subscriber extends uvm_subscriber #(axi_seq_item);
  `uvm_component_utils(axi_cov_subscriber)

  covergroup axi_cg;

    // basic stimulus
    cp_rw    : coverpoint tr.rw;
    cp_len   : coverpoint tr.len {
      bins short = {[0:3]};
      bins mid   = {[4:15]};
      bins long  = {[16:255]};
    }
    cp_size  : coverpoint tr.size;
    cp_burst : coverpoint tr.burst;
    cp_resp  : coverpoint tr.resp;

    // Stall patterns
    cp_aw_wait : coverpoint tr.aw_wait {
      bins zero = {0};
      bins low  = {[1:3]};
      bins mid  = {[4:15]};
      bins high = {[16:$]};
    }

    cp_w_wait : coverpoint tr.w_wait {
      bins zero = {0};
      bins low  = {[1:3]};
      bins mid  = {[4:15]};
      bins high = {[16:$]};
    }

    cp_b_wait : coverpoint tr.b_wait {
      bins zero = {0};
      bins low  = {[1:3]};
      bins mid  = {[4:15]};
      bins high = {[16:$]};
    }

    cp_ar_wait : coverpoint tr.ar_wait {
      bins zero = {0};
      bins low  = {[1:3]};
      bins mid  = {[4:15]};
      bins high = {[16:$]};
    }

    cp_r_wait : coverpoint tr.r_wait {
      bins zero = {0};
      bins low  = {[1:3]};
      bins mid  = {[4:15]};
      bins high = {[16:$]};
    }

    // Useful crosses
    x_rw_resp   : cross cp_rw, cp_resp;
    x_rw_awwait : cross cp_rw, cp_aw_wait;
    x_rw_rwait  : cross cp_rw, cp_r_wait;
    x_size_wait : cross cp_size, cp_w_wait;

  endgroup

  axi_seq_item tr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    axi_cg = new;
  endfunction

  function void write(axi_seq_item t);
    tr = t;
    axi_cg.sample();
  endfunction

endclass
`endif // _AXI_COV_SUBSCRIBER_SV_
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
//------------------------------------------------------------------------------
// File    : axi_agent.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-01-18
// Brief   : AXI4 agent encapsulating sequencer/driver/monitor. Supports ACTIVE
//           and PASSIVE modes. In ACTIVE mode drives transactions; in PASSIVE
//           mode only monitors bus activity.
//------------------------------------------------------------------------------
// Notes:
// - Driver uses virtual axi_if.MASTER_MP
// - Monitor uses virtual axi_if.MON_MP
// - Active/passive controlled by is_active (UVM_ACTIVE/UVM_PASSIVE)
//------------------------------------------------------------------------------
`ifndef _AXI_AGENT_SV_
`define _AXI_AGENT_SV_

class axi_agent extends uvm_agent;
  `uvm_component_utils(axi_agent)

  // components
  axi_sequencer  sequencer;
  axi_driver     driver;
  axi_monitor    monitor;

  // legacy stream (full txn)
  uvm_analysis_port #(axi_seq_item) ap;

  // Plan-B streams (forwarded from monitor)
  uvm_analysis_port #(axi_req_evt) req_ap;
  uvm_analysis_port #(axi_rsp_evt) rsp_ap;

  extern function new(string name="axi_agent", uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);

endclass : axi_agent

function axi_agent::new(string name="axi_agent", uvm_component parent=null);
  super.new(name, parent);
  ap     = new("ap", this);
  req_ap = new("req_ap", this);
  rsp_ap = new("rsp_ap", this);
endfunction

function void axi_agent::build_phase(uvm_phase phase);
  super.build_phase(phase);

  // monitor always exists
  monitor = axi_monitor::type_id::create("monitor", this);

  if (is_active == UVM_ACTIVE) begin
    sequencer = axi_sequencer::type_id::create("sequencer", this);
    driver    = axi_driver   ::type_id::create("driver",    this);
  end
endfunction

function void axi_agent::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  if (is_active == UVM_ACTIVE) begin
    driver.seq_item_port.connect(sequencer.seq_item_export);
  end

  monitor.ap.connect(ap);

  // monitor's Plan-B ports forward to agent's analysis ports
  monitor.req_ap.connect(req_ap);
  monitor.rsp_ap.connect(rsp_ap);
endfunction

`endif // _AXI_AGENT_SV_
// axi_common_pkg.sv
`ifndef _AXI_COMMON_PKG_SV_
`define _AXI_COMMON_PKG_SV_

package axi_common_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // -------------------------
  // AXI enums (existing)
  // -------------------------
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

  // -------------------------
  // Plan-B event kind enum
  // -------------------------
  typedef enum int unsigned {
    AXI_EVT_AW = 0,
    AXI_EVT_W  = 1,
    AXI_EVT_B  = 2,
    AXI_EVT_AR = 3,
    AXI_EVT_R  = 4
  } axi_evt_kind_e;

  // -------------------------
  // Plan-B event objects
  // -------------------------

  // AW/AR handshake event
  class axi_req_evt extends uvm_object;
    `uvm_object_utils(axi_req_evt)

    axi_evt_kind_e kind;     // AXI_EVT_AW / AXI_EVT_AR
    axi_rw_e       rw;       // AXI_WRITE / AXI_READ

    // 這裡寬度如果你專案有 `AXI_ID_WIDTH / `AXI_ADDR_WIDTH 就改用那個
    logic [31:0]   id;
    int unsigned   tag;

    logic [63:0]   addr;
    logic [7:0]    len;
    logic [2:0]    size;
    axi_burst_e    burst;

    function new(string name="axi_req_evt");
      super.new(name);
      kind  = AXI_EVT_AW;
      rw    = AXI_READ;
      id    = '0;
      tag   = 0;
      addr  = '0;
      len   = '0;
      size  = '0;
      burst = AXI_BURST_INCR;
    endfunction
  endclass

  // B / R (and optional W) event
  class axi_rsp_evt extends uvm_object;
    `uvm_object_utils(axi_rsp_evt)

    axi_evt_kind_e kind;     // AXI_EVT_B / AXI_EVT_R / AXI_EVT_W(若你之後想加)
    axi_rw_e       rw;

    logic [31:0]   id;
    int unsigned   tag;

    int unsigned   beat_idx; // R/W beat index (scoreboard 用得到)
    axi_resp_e     resp;

    // data/strb 寬度同上，有 macro 就改
    logic [63:0]   data;
    logic [7:0]    strb;

    bit            last;

    function new(string name="axi_rsp_evt");
      super.new(name);
      kind     = AXI_EVT_B;
      rw       = AXI_READ;
      id       = '0;
      tag      = 0;
      beat_idx = 0;
      resp     = AXI_RESP_OKAY;
      data     = '0;
      strb     = '0;
      last     = 0;
    endfunction
  endclass

endpackage : axi_common_pkg

`endif
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
`ifndef _AXI_SCOREBOARD_SV_
`define _AXI_SCOREBOARD_SV_

class axi_scoreboard extends uvm_component;
  `uvm_component_utils(axi_scoreboard)

  // --------------------------------------------
  // Inputs: Plan-B streams from monitor
  // --------------------------------------------
  uvm_analysis_imp #(axi_req_evt, axi_scoreboard) req_imp;
  uvm_analysis_imp #(axi_rsp_evt, axi_scoreboard) rsp_imp;

  // Optional: keep legacy full ACT txn input if you want hybrid
  // uvm_analysis_imp #(axi_seq_item, axi_scoreboard) act_imp;

  axi_ref_model rm;

  bit verbose = 0;

  int unsigned pass_cnt = 0;
  int unsigned fail_cnt = 0;

  // --------------------------------------------
  // Pending contexts
  // key = (id, tag)
  // --------------------------------------------
  typedef struct packed {
    int unsigned id_key;
    int unsigned tag;
  } axi_key_t;

  function axi_key_t mk_key(input int unsigned id_key, input int unsigned tag);
    axi_key_t k;
    k.id_key = id_key;
    k.tag    = tag;
    return k;
  endfunction

  // READ pending
  typedef struct {
    axi_seq_item exp;        // expected full read txn
    int unsigned beat_idx;   // next expected beat to compare
    bit          active;
  } rd_ctx_t;

  // WRITE pending
  typedef struct {
    axi_seq_item exp;        // expected write txn (needs wdata/wstrb to predict)
    bit          have_wdata;
    bit          got_b;
    bit          active;
  } wr_ctx_t;

  rd_ctx_t rd_pending[axi_key_t];
  wr_ctx_t wr_pending[axi_key_t];

  extern function new(string name="axi_scoreboard", uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void report_phase(uvm_phase phase);

  // analysis callbacks (overload write for two types)
  extern function void write(axi_req_evt  req);
  extern function void write(axi_rsp_evt  rsp);

  // helpers
  extern function axi_seq_item build_exp_from_req(input axi_req_evt req);
  extern function bit compare_read_beat(input axi_seq_item exp, input int unsigned beat_idx,
                                       input axi_rsp_evt rsp);
  extern function void finalize_pass(string msg="");
  extern function void finalize_fail(string msg="");

endclass : axi_scoreboard


function axi_scoreboard::new(string name="axi_scoreboard", uvm_component parent=null);
  super.new(name, parent);
  req_imp = new("req_imp", this);
  rsp_imp = new("rsp_imp", this);
endfunction

function void axi_scoreboard::build_phase(uvm_phase phase);
  super.build_phase(phase);
  // rm = axi_ref_model::type_id::create("rm");
  // only if env did put rm then create
  if (rm == null) begin
    rm = axi_ref_model::type_id::create("rm");
  end
endfunction

function void axi_scoreboard::report_phase(uvm_phase phase);
  super.report_phase(phase);
  `uvm_info(get_type_name(),
            $sformatf("SCOREBOARD SUMMARY: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt),
            UVM_NONE)
endfunction

function void axi_scoreboard::finalize_pass(string msg="");
  pass_cnt++;
  if (verbose && (msg.len() > 0))
    `uvm_info(get_type_name(), $sformatf("PASS: %s", msg), UVM_LOW)
endfunction

function void axi_scoreboard::finalize_fail(string msg="");
  fail_cnt++;
  `uvm_error(get_type_name(), (msg.len()>0) ? msg : "FAIL")
endfunction


// ------------------------------------------------------------
// Build EXP txn from REQ (for READ: predict fills rdata)
// For WRITE: you still need wdata/wstrb before predict makes sense,
// so this function builds the skeleton.
// ------------------------------------------------------------
function axi_seq_item axi_scoreboard::build_exp_from_req(input axi_req_evt req);
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

  // allocate payload
  if (exp.rw == AXI_READ) begin
    exp.rdata = new[exp.beats];
    exp.wdata = new[0];
    exp.wstrb = new[0];
  end else begin
    // write: wait for W beats to fill
    exp.wdata = new[exp.beats];
    exp.wstrb = new[exp.beats];
    exp.rdata = new[0];
  end

  // default
  exp.resp = '0;

  return exp;
endfunction


// ------------------------------------------------------------
// REQ callback: create pending + build/predict EXP
// ------------------------------------------------------------
function void axi_scoreboard::write(axi_req_evt req);
  axi_key_t key;
  int unsigned id_key;

  id_key = int'(req.id);
  key    = mk_key(id_key, req.tag);

  if (req.rw == AXI_READ) begin
    rd_ctx_t ctx;

    ctx.exp      = build_exp_from_req(req);
    ctx.beat_idx = 0;
    ctx.active   = 1'b1;

    // predict immediately for READ (exp.rdata filled)
    rm.predict(ctx.exp);

    rd_pending[key] = ctx;

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("SB: REQ AR id=0x%0h tag=%0d addr=0x%0h len=%0d beats=%0d (RD pending)",
                  req.id, req.tag, req.addr, req.len, ctx.exp.beats),
        UVM_MEDIUM)
    end
  end else begin
    wr_ctx_t ctx;

    ctx.exp       = build_exp_from_req(req);
    ctx.have_wdata= 1'b0;
    ctx.got_b     = 1'b0;
    ctx.active    = 1'b1;

    wr_pending[key] = ctx;

    if (verbose) begin
      `uvm_info(get_type_name(),
        $sformatf("SB: REQ AW id=0x%0h tag=%0d addr=0x%0h len=%0d beats=%0d (WR pending)",
                  req.id, req.tag, req.addr, req.len, ctx.exp.beats),
        UVM_MEDIUM)
    end
  end
endfunction


// ------------------------------------------------------------
// Compare single read beat
// ------------------------------------------------------------
function bit axi_scoreboard::compare_read_beat(input axi_seq_item exp,
                                              input int unsigned beat_idx,
                                              input axi_rsp_evt rsp);
  bit ok;
  ok = 1'b1;

  if (beat_idx >= exp.rdata.size()) ok = 1'b0;
  else if (rsp.data !== exp.rdata[beat_idx]) ok = 1'b0;

  // resp compare (optional: compare every beat or only last)
  // if (rsp.resp !== exp.resp) ok = 1'b0;

  return ok;
endfunction


// ------------------------------------------------------------
// RSP callback: match pending and compare
// - R: beat-by-beat compare
// - W: collect beats (if you emit W events)
// - B: compare resp (and for write, ensure wdata is ready)
// ------------------------------------------------------------
function void axi_scoreboard::write(axi_rsp_evt rsp);
  axi_key_t key;
  int unsigned id_key;
  id_key = int'(rsp.id);
  key    = mk_key(id_key, rsp.tag);

  // -----------------------
  // READ DATA beat
  // -----------------------
  if (rsp.kind == AXI_EVT_R) begin
    if (!rd_pending.exists(key) || !rd_pending[key].active) begin
      finalize_fail($sformatf("SB: unexpected R beat id=0x%0h tag=%0d (no pending)", rsp.id, rsp.tag));
      return;
    end

    rd_ctx_t ctx;
    bit ok;

    ctx = rd_pending[key];

    ok = compare_read_beat(ctx.exp, ctx.beat_idx, rsp);
    if (!ok) begin
      finalize_fail($sformatf("SB: RDATA mismatch id=0x%0h tag=%0d beat=%0d ACT=0x%0h EXP=0x%0h",
                              rsp.id, rsp.tag, ctx.beat_idx, rsp.data, ctx.exp.rdata[ctx.beat_idx]));
    end else begin
      if (verbose) begin
        `uvm_info(get_type_name(),
          $sformatf("SB: R beat ok id=0x%0h tag=%0d beat=%0d data=0x%0h",
                    rsp.id, rsp.tag, ctx.beat_idx, rsp.data),
          UVM_LOW)
      end
    end

    ctx.beat_idx++;

    if (rsp.last) begin
      // final beat done => close pending
      ctx.active = 1'b0;
      rd_pending[key] = ctx;
      if (ok) finalize_pass($sformatf("READ done id=0x%0h tag=%0d beats=%0d", rsp.id, rsp.tag, ctx.beat_idx));
    end else begin
      rd_pending[key] = ctx;
    end

    return;
  end

  // -----------------------
  // WRITE DATA beat (optional)
  // -----------------------
  if (rsp.kind == AXI_EVT_W) begin
    if (!wr_pending.exists(key) || !wr_pending[key].active) begin
      finalize_fail($sformatf("SB: unexpected W beat id=0x%0h tag=%0d (no pending)", rsp.id, rsp.tag));
      return;
    end

    wr_ctx_t ctx;
    ctx = wr_pending[key];

    if (rsp.beat_idx >= ctx.exp.wdata.size()) begin
      finalize_fail($sformatf("SB: W beat overflow id=0x%0h tag=%0d beat=%0d", rsp.id, rsp.tag, rsp.beat_idx));
      return;
    end

    ctx.exp.wdata[rsp.beat_idx] = rsp.data;
    ctx.exp.wstrb[rsp.beat_idx] = rsp.strb;

    if (rsp.last) ctx.have_wdata = 1'b1;

    wr_pending[key] = ctx;
    return;
  end

  // -----------------------
  // WRITE RESP (B)
  // -----------------------
  if (rsp.kind == AXI_EVT_B) begin
    if (!wr_pending.exists(key) || !wr_pending[key].active) begin
      finalize_fail($sformatf("SB: unexpected B id=0x%0h tag=%0d (no pending)", rsp.id, rsp.tag));
      return;
    end

    wr_ctx_t ctx;
    ctx = wr_pending[key];

    if (!ctx.have_wdata) begin
      finalize_fail($sformatf("SB: got B before WDATA complete id=0x%0h tag=%0d", rsp.id, rsp.tag));
      return;
    end

    // now we can predict expected write side-effects + expected resp
    rm.predict(ctx.exp);

    if (rsp.resp !== ctx.exp.resp) begin
      finalize_fail($sformatf("SB: BRESP mismatch id=0x%0h tag=%0d ACT=%0d EXP=%0d",
                              rsp.id, rsp.tag, rsp.resp, ctx.exp.resp));
    end else begin
      finalize_pass($sformatf("WRITE done id=0x%0h tag=%0d resp=%0d", rsp.id, rsp.tag, rsp.resp));
    end

    ctx.active = 1'b0;
    wr_pending[key] = ctx;
    return;
  end
endfunction

`endif // _AXI_SCOREBOARD_SV_
// design.sv
`timescale 1ns/1ps

`include "axi_defines.sv"
`include "axi_types.sv"
`include "axi_mem_slave.sv"
