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
//------------------------------------------------------------------------------
// axi_outstanding_rand_seq (L2-2 bring-up)
// - Generate many reqs back-to-back (driver is no-wait + channel threads)
// - Goal: create pressure / multiple in-flight, not true OOO return yet
//------------------------------------------------------------------------------
class axi_outstanding_rand_seq extends axi_base_seq;
  `uvm_object_utils(axi_outstanding_rand_seq)

  // knobs
  rand int unsigned num_reqs;          // total requests
  rand int unsigned write_pct;         // 0..100
  rand logic [7:0]  max_len;           // max beats-1 (0..15)
  rand logic [2:0]  fixed_size;        // default keep 4B
  rand int unsigned id_max;            // id range: 0..id_max (bring-up suggest 0 or 3)
  rand int unsigned addr_hot_pct;      // 0..100, use hot address occasionally

  constraint c_knobs {
    num_reqs     inside {[100:300]};
    write_pct    inside {[40:60]};
    max_len      inside {[0:15]};
    fixed_size   == 3'd2;         // 4 bytes/beat on 32-bit bus
    id_max       inside {[0:3]};  // bring-up: few IDs
    addr_hot_pct inside {[0:50]};
  }

  function new(string name="axi_outstanding_rand_seq");
    super.new(name);
  endfunction

  virtual task body();
    logic [`AXI_ADDR_WIDTH-1:0] hot_addr;
    int unsigned hot_nbytes;

    hot_nbytes = bytes_from_size(fixed_size);
    hot_addr   = pick_addr_aligned(hot_nbytes);

    for (int unsigned k = 0; k < num_reqs; k++) begin
      axi_seq_item tr;

      bit do_write;
      logic [7:0] len;
      logic [2:0] size;
      logic [`AXI_ID_WIDTH-1:0] id;
      logic [`AXI_ADDR_WIDTH-1:0] addr;

      int unsigned beats;
      int unsigned nbytes;

      do_write = ($urandom_range(0,99) < int'(write_pct));
      size     = fixed_size;
      len      = $urandom_range(0, int'(max_len));

      beats = int'(len) + 1;
      if (beats == 0) beats = 1;

      // ID: bring-up uses small range (0..id_max)
      id = $urandom_range(0, int'(id_max));

      nbytes = bytes_from_size(size);

      // address: sometimes reuse hot address to create hazards/locality
      if ($urandom_range(0,99) < int'(addr_hot_pct))
        addr = hot_addr;
      else
        addr = pick_addr_aligned(nbytes);

      tr = axi_seq_item::type_id::create($sformatf("ooo_req_%0d", k));

      start_item(tr);

      tr.id    = id;
      tr.addr  = addr;
      tr.len   = len;
      tr.size  = size;
      tr.burst = AXI_BURST_INCR;

      if (do_write) begin
        tr.rw    = AXI_WRITE;

        tr.wdata = new[beats];
        tr.wstrb = new[beats];
        tr.rdata = new[0];

        foreach (tr.wdata[i]) tr.wdata[i] = $urandom();

        // strobe: mostly full, sometimes random (avoid all-zero)
        foreach (tr.wstrb[i]) begin
          if ($urandom_range(0,9) < 8)
            tr.wstrb[i] = {`AXI_STRB_WIDTH{1'b1}};
          else begin
            tr.wstrb[i] = $urandom();
            if (tr.wstrb[i] == '0) tr.wstrb[i] = {`AXI_STRB_WIDTH{1'b1}};
          end
        end
      end
      else begin
        tr.rw    = AXI_READ;

        // L2 driver won't fill; monitor/SB must consume R-channel data
        tr.rdata = new[beats];
        tr.wdata = new[0];
        tr.wstrb = new[0];
      end

      finish_item(tr);
    end
  endtask

endclass : axi_outstanding_rand_seq


`endif // _AXI_SEQUENCES_SV_
