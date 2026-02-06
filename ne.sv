task axi_monitor::collect_write();
  forever begin
    int unsigned aw_stall;
    int unsigned b_stall;

    // ★所有宣告搬到這裡（statement 之前）
    axi_req_evt  req;
    axi_rsp_evt  rsp;
    int unsigned id_key;
    int unsigned tag;

    aw_stall = 0;
    ...
    // 後面你原本的 req = create / req.kind = ... / req_ap.write(req) 都可以照舊
  end
endtask
