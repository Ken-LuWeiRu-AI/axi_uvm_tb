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
  input  logic [7:0]                    AWLEN,
  input  logic [2:0]                    AWSIZE,
  input  axi_burst_e                     AWBURST,
  input  logic                          AWLOCK,
  input  logic [3:0]                    AWCACHE,
  input  logic [2:0]                    AWPROT,
  input  logic [3:0]                    AWQOS,
  input  logic [3:0]                    AWREGION,
  input  logic                          AWVALID,
  output logic                          AWREADY,

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
