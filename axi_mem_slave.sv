//------------------------------------------------------------------------------
// File    : axi_mem_slave.sv
// Author  : ken, Lu Wei-Ru
// Created : 2026-02-08
// Brief   : Out-of-Order (OOO) AXI4 memory-mapped slave DUT.
//           - Supports INCR bursts for Read and Write.
//           - Supports Out-of-Order responses for transactions with DIFFERENT IDs.
//           - Enforces strict In-Order responses for transactions with the SAME ID.
//           - Uses SystemVerilog dynamic queues [$] for task management.
//------------------------------------------------------------------------------
`ifndef _AXI_MEM_SLAVE_SV_
`define _AXI_MEM_SLAVE_SV_
import axi_common_pkg::*;

module axi_mem_slave #(
  parameter logic [`AXI_ADDR_WIDTH-1:0] BASE_ADDR      = `AXI_DEFAULT_BASE_ADDR,
  parameter int unsigned                MEM_BYTES      = `AXI_DEFAULT_MEM_BYTES,
  parameter int unsigned                RD_LATENCY     = 0,
  parameter int unsigned                WR_RESP_LATENCY= 0,
  parameter bit                         CHECK_ADDR     = 1
)(
  input  logic                          ACLK,
  input  logic                          ARESETn,
  // AW
  input  logic [`AXI_ID_WIDTH-1:0]      AWID,
  input  logic [`AXI_ADDR_WIDTH-1:0]    AWADDR,
  input  logic [7:0]                    AWLEN,
  input  logic [2:0]                    AWSIZE,
  input  axi_burst_e                    AWBURST,
  input  logic                          AWLOCK,
  input  logic [3:0]                    AWCACHE,
  input  logic [2:0]                    AWPROT,
  input  logic [3:0]                    AWQOS,
  input  logic [3:0]                    AWREGION,
  input  logic                          AWVALID,
  output logic                          AWREADY,
  // W
  input  logic [`AXI_DATA_WIDTH-1:0]    WDATA,
  input  logic [`AXI_STRB_WIDTH-1:0]    WSTRB,
  input  logic                          WLAST,
  input  logic                          WVALID,
  output logic                          WREADY,
  // B
  output logic [`AXI_ID_WIDTH-1:0]      BID,
  output axi_resp_e                     BRESP,
  output logic                          BVALID,
  input  logic                          BREADY,
  // AR
  input  logic [`AXI_ID_WIDTH-1:0]      ARID,
  input  logic [`AXI_ADDR_WIDTH-1:0]    ARADDR,
  input  logic [7:0]                    ARLEN,
  input  logic [2:0]                    ARSIZE,
  input  axi_burst_e                    ARBURST,
  input  logic                          ARLOCK,
  input  logic [3:0]                    ARCACHE,
  input  logic [2:0]                    ARPROT,
  input  logic [3:0]                    ARQOS,
  input  logic [3:0]                    ARREGION,
  input  logic                          ARVALID,
  output logic                          ARREADY,
  // R
  output logic [`AXI_ID_WIDTH-1:0]      RID,
  output logic [`AXI_DATA_WIDTH-1:0]    RDATA,d
  output axi_resp_e                     RRESP,
  output logic                          RLAST,
  output logic                          RVALID,
  input  logic                          RREADY
);

  // Memory Array
  logic [7:0] mem [0:MEM_BYTES-1];

  // --- Helpers ---
  function automatic int unsigned bytes_per_beat(input logic [2:0] size);
    return (1 << int'(size));
  endfunction

  function automatic bit addr_in_range(input logic [`AXI_ADDR_WIDTH-1:0] a);
    if (!CHECK_ADDR) return 1'b1;
    return (a >= BASE_ADDR) && (a < (BASE_ADDR + MEM_BYTES));
  endfunction

  function automatic int unsigned mem_index(input logic [`AXI_ADDR_WIDTH-1:0] a);
    return int'(a - BASE_ADDR);
  endfunction

  function automatic axi_resp_e burst_supported_resp(input axi_burst_e b);
    if (b == AXI_BURST_INCR) return AXI_RESP_OKAY;
    else                    return AXI_RESP_SLVERR;
  endfunction

  function automatic logic [`AXI_DATA_WIDTH-1:0] read_beat(input logic [`AXI_ADDR_WIDTH-1:0] addr, input int unsigned nbytes);
    logic [`AXI_DATA_WIDTH-1:0] tmp = '0;
    for (int i = 0; i < `AXI_STRB_WIDTH; i++) begin
      if (i < nbytes) begin
        logic [`AXI_ADDR_WIDTH-1:0] ba = addr + i;
        if (addr_in_range(ba)) tmp[i*8 +: 8] = mem[mem_index(ba)];
        else                   tmp[i*8 +: 8] = 8'h00;
      end
    end
    return tmp;
  endfunction

  task automatic write_beat(input logic [`AXI_ADDR_WIDTH-1:0] addr, input logic [`AXI_DATA_WIDTH-1:0] data, input logic [`AXI_STRB_WIDTH-1:0] strb, input int unsigned nbytes);
    for (int i = 0; i < `AXI_STRB_WIDTH; i++) begin
      if (i < nbytes && strb[i]) begin
        logic [`AXI_ADDR_WIDTH-1:0] ba = addr + i;
        if (addr_in_range(ba)) mem[mem_index(ba)] = data[i*8 +: 8];
      end
    end
  endtask

  // -----------------------------------------------------------------------
  // STRUCTS
  // -----------------------------------------------------------------------
  typedef struct packed {
    logic [`AXI_ID_WIDTH-1:0]       id;
    logic [`AXI_ADDR_WIDTH-1:0]     addr;
    logic [7:0]                     len;
    logic [2:0]                     size;
    axi_burst_e                     burst;
    logic [15:0]                    bytes;
    axi_resp_e                      base_resp;
    axi_resp_e                      range_resp;
  } req_t;

  req_t aw_fifo[$]; 
  req_t b_pool[$];

  typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} w_state_e;
  w_state_e w_state;
  
  req_t        w_cur; 
  int unsigned w_beat_idx;
  int unsigned w_resp_cnt;

  req_t ar_pool[$];

  typedef enum logic [1:0] {R_IDLE, R_WAIT, R_SEND} r_state_e;
  r_state_e r_state;

  req_t        r_cur;
  int unsigned r_beats_total;
  int unsigned r_beat_idx;
  int unsigned r_lat_cnt;

  // -----------------------------------------------------------------------
  // MAIN LOGIC
  // -----------------------------------------------------------------------
  assign AWREADY = (aw_fifo.size() < 16);
  assign WREADY  = (w_state == W_DATA);
  assign ARREADY = (ar_pool.size() < 16);

  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      for (int i = 0; i < MEM_BYTES; i++) mem[i] <= 8'h00;
      w_state <= W_IDLE;
      w_beat_idx <= 0; w_resp_cnt <= 0;
      aw_fifo.delete();
      b_pool.delete();
      BID <= '0; BRESP <= AXI_RESP_OKAY; BVALID <= 1'b0;

      r_state <= R_IDLE;
      r_beat_idx <= 0; r_lat_cnt <= 0;
      ar_pool.delete();
      RID <= '0; RDATA <= '0; RRESP <= AXI_RESP_OKAY; RLAST <= 1'b0; RVALID <= 1'b0;
    end else begin
      // --- 1. AW Channel ---
      if (AWVALID && AWREADY) begin
        req_t tmp;
        tmp.id = AWID; tmp.addr = AWADDR; tmp.len = AWLEN; tmp.size = AWSIZE; tmp.burst = AWBURST;
        tmp.bytes = bytes_per_beat(AWSIZE);
        tmp.base_resp = burst_supported_resp(AWBURST);
        tmp.range_resp= (CHECK_ADDR && !addr_in_range(AWADDR)) ? AXI_RESP_DECERR : AXI_RESP_OKAY;
        aw_fifo.push_back(tmp);
      end

      // --- 2. Write Data & Response ---
      case (w_state)
        W_IDLE: begin
          BVALID <= 1'b0;
          if (aw_fifo.size() > 0) begin
            w_cur = aw_fifo.pop_front();
            w_beat_idx <= 0;
            w_state    <= W_DATA;
          end
          else if (b_pool.size() > 0 && !BVALID) begin
             w_state <= W_RESP; 
          end
        end

        W_DATA: begin
          if (WVALID && WREADY) begin
            logic [`AXI_ADDR_WIDTH-1:0] beat_addr;
            beat_addr = w_cur.addr + (w_beat_idx * w_cur.bytes);
            write_beat(beat_addr, WDATA, WSTRB, w_cur.bytes);

            if (w_beat_idx + 1 >= (int'(w_cur.len) + 1)) begin
              b_pool.push_back(w_cur);
              w_state <= W_IDLE; 
            end else begin
              w_beat_idx <= w_beat_idx + 1;
            end
          end
        end
        
        W_RESP: begin
           if (!BVALID) begin
              int idx;
              req_t b_item;
              logic [`AXI_ID_WIDTH-1:0] target_id; // FIX: Declare variable first

              idx = $urandom_range(0, b_pool.size()-1);
              target_id = b_pool[idx].id;          // FIX: Assign after declaration

              foreach(b_pool[i]) begin
                 if (b_pool[i].id == target_id) begin
                    idx = i;
                    break;
                 end
              end
              
              b_item = b_pool[idx];
              b_pool.delete(idx);

              BID   <= b_item.id;
              if (b_item.base_resp != AXI_RESP_OKAY)       BRESP <= b_item.base_resp;
              else if (b_item.range_resp != AXI_RESP_OKAY) BRESP <= b_item.range_resp;
              else                                         BRESP <= AXI_RESP_OKAY;
              BVALID <= 1'b1;
           end 
           else if (BVALID && BREADY) begin
              BVALID <= 1'b0;
              w_state <= W_IDLE;
           end
        end
        default: w_state <= W_IDLE;
      endcase

      // --- 3. AR Channel ---
      if (ARVALID && ARREADY) begin
        req_t tmp;
        tmp.id = ARID; tmp.addr = ARADDR; tmp.len = ARLEN; tmp.size = ARSIZE; tmp.burst = ARBURST;
        tmp.bytes = bytes_per_beat(ARSIZE);
        tmp.base_resp = burst_supported_resp(ARBURST);
        tmp.range_resp= (CHECK_ADDR && !addr_in_range(ARADDR)) ? AXI_RESP_DECERR : AXI_RESP_OKAY;
        ar_pool.push_back(tmp);
      end

      case (r_state)
        R_IDLE: begin
          RVALID <= 1'b0; RLAST <= 1'b0;
          
          if (ar_pool.size() > 0) begin
             int idx;
             logic [`AXI_ID_WIDTH-1:0] target_id; // FIX: Declare variable first

             idx = $urandom_range(0, ar_pool.size()-1);
             target_id = ar_pool[idx].id;         // FIX: Assign after declaration
             
             foreach(ar_pool[i]) begin
                if (ar_pool[i].id == target_id) begin
                   idx = i;
                   break;
                end
             end

             r_cur = ar_pool[idx];
             ar_pool.delete(idx);

             r_beats_total <= int'(r_cur.len) + 1;
             r_beat_idx    <= 0;
             r_lat_cnt     <= 0;
             r_state       <= (RD_LATENCY == 0) ? R_SEND : R_WAIT;
          end
        end

        R_WAIT: begin
          if (r_lat_cnt + 1 >= RD_LATENCY) r_state <= R_SEND;
          else r_lat_cnt <= r_lat_cnt + 1;
        end

        R_SEND: begin
          bit beat_hs;
          int unsigned next_idx;
          logic [`AXI_ADDR_WIDTH-1:0] beat_addr;
          bit is_last_val;

          beat_hs = RVALID && RREADY;

          if (beat_hs && (r_beat_idx == r_beats_total - 1)) begin
             RVALID  <= 1'b0;
             RLAST   <= 1'b0;
             r_state <= R_IDLE;
          end
          else if (!RVALID || beat_hs) begin
             next_idx = (RVALID) ? (r_beat_idx + 1) : r_beat_idx;
             beat_addr   = r_cur.addr + (next_idx * r_cur.bytes);
             is_last_val = (next_idx == r_beats_total - 1);

             RID   <= r_cur.id;
             RDATA <= read_beat(beat_addr, r_cur.bytes);

             if (r_cur.base_resp != AXI_RESP_OKAY)       RRESP <= r_cur.base_resp;
             else if (r_cur.range_resp != AXI_RESP_OKAY) RRESP <= r_cur.range_resp;
             else                                        RRESP <= AXI_RESP_OKAY;

             RLAST <= is_last_val;
             RVALID<= 1'b1;

             if (beat_hs) r_beat_idx <= r_beat_idx + 1;
          end
        end
        default: r_state <= R_IDLE;
      endcase
    end
  end

endmodule
`endif // _AXI_MEM_SLAVE_SV_