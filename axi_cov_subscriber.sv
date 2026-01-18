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
