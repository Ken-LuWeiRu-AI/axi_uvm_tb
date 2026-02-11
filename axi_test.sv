//------------------------------------------------------------------------------
// File    : axi_test.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-02-08
// Brief   : AXI4 UVM Test Suite.
//           A collection of UVM tests ranging from basic connectivity checks to
//           advanced stress scenarios.
//
//           Included Tests:
//           - axi_test (Base):
//             - Performs M0 bring-up with a single write and read to the same address.
//           - axi_smoke_test:
//             - Validates basic read/write operations across multiple addresses.
//           - axi_burst_test (M1):
//             - Verifies burst functionality with multi-beat transactions.
//           - axi_stress_test:
//             - Applies randomized stress with mixed read/write traffic and
//               varied strobe patterns.
//           - axi_outstanding_rand_test (M2):
//             - Generates high-throughput, back-to-back requests to exercise
//               multiple outstanding transactions and out-of-order responses.
//
//           Environment Configuration:
//           - Propagates key parameters (base_addr, memory size, coverage enable)
//             from the test layer down to the environment and components via
//             uvm_config_db.
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
//------------------------------------------------------------------------------
// axi_outstanding_rand_test: real outstanding traffic generator (L2 bring-up)
//------------------------------------------------------------------------------
class axi_outstanding_rand_test extends axi_test;
  `uvm_component_utils(axi_outstanding_rand_test)

  function new(string name="axi_outstanding_rand_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_outstanding_rand_seq s;

    phase.raise_objection(this);

    // ✅ outstanding traffic: responses will lag behind requests
    phase.phase_done.set_drain_time(this, 2000ns); // 先放大一點，之後再調

    if (env.agent == null || env.agent.sequencer == null)
      `uvm_fatal(get_type_name(), "No sequencer found (agent must be ACTIVE).")

    s = axi_outstanding_rand_seq::type_id::create("s");
    void'(s.randomize() with {
      num_reqs   inside {[100:300]};
      write_pct  inside {[40:60]};
      fixed_size == 3'd2;
      max_len    inside {[0:15]};
    });

    s.start(env.agent.sequencer);

    phase.drop_objection(this);
  endtask

endclass : axi_outstanding_rand_test

`endif // _AXI_TEST_SV_
