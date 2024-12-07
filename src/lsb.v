`ifndef LOAD_STORE_BUFFER_V
`define LOAD_STORE_BUFFER_V
`include "const.v"
module LoadStoreBuffer (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low


    // from instruction unit
    input wire                      inst_req,
    input wire [     `TYPE_BIT-1:0] inst_type,
    input wire [              31:0] inst_imm,
    input wire [               4:0] inst_rd,
    input wire [`ROB_INDEX_BIT-1:0] inst_rob_id,

    // from rf
    input wire [31:0] inst_val1,
    input wire [`ROB_INDEX_BIT-1:0] inst_dep1,
    input wire inst_has_dep1,
    input wire [31:0] inst_val2,
    input wire [`ROB_INDEX_BIT-1:0] inst_dep2,
    input wire inst_has_dep2,

    // cdb, from rob
    input wire                      cdb_req,
    input wire [              31:0] cdb_val,
    input wire [`ROB_INDEX_BIT-1:0] cdb_rob_id,
    input wire [`ROB_INDEX_BIT-1:0] rob_head,

    input wire clear,

    // from memory unit
    input wire                    mem_finished,
    input wire [            31:0] mem_val,
    input wire [`LSB_CAP_BIT-1:0] mem_pos,
    input wire                    mem_busy,

    output reg full,

    // to memory unit
    output wire                    req_out,
    output wire [`LSB_CAP_BIT-1:0] pos_out,
    output wire                    ls_out,    // i.e. data_we
    output wire [             1:0] len_out,
    output wire [            31:0] addr_out,
    output wire [            31:0] val_out,

    // to rob, for write back
    output reg                      ready,
    output reg [`ROB_INDEX_BIT-1:0] rob_id_out,
    output reg [              31:0] result
);
  reg busy[0 : `LSB_CAP-1];
  reg ls[0 : `LSB_CAP-1];  // 0: load, 1: store
  reg [2:0] len[0 : `LSB_CAP-1];  // x00: byte, x01: half word, x10: word. 0xx:unsigned, 1xx:signed.
  reg [31:0] imm[0 : `LSB_CAP-1];
  reg [31:0] val1[0 : `LSB_CAP-1];
  reg [31:0] val2[0 : `LSB_CAP-1];
  reg [`ROB_INDEX_BIT-1:0] dep1[0 : `LSB_CAP-1];
  reg [`ROB_INDEX_BIT-1:0] dep2[0 : `LSB_CAP-1];
  reg has_dep1[0 : `LSB_CAP-1];
  reg has_dep2[0 : `LSB_CAP-1];
  reg [`ROB_INDEX_BIT-1:0] rob_id[0 : `LSB_CAP-1];
  reg complete[0 : `LSB_CAP-1];
  reg [31:0] res[0 : `LSB_CAP-1];
  reg [`LSB_CAP_BIT-1:0] head, tail;
  reg [31:0] size;
  reg sent[0 : `LSB_CAP-1];  // for store inst. to prevent write same data twice.


  wire [`LSB_CAP_BIT-1:0] next_head = complete[head] ? (head + 1) % `LSB_CAP : head;
  wire [`LSB_CAP_BIT-1:0] next_tail = inst_req ? (tail + 1) % `LSB_CAP : tail;
  wire [31:0] next_size = inst_req ? (complete[head] ? size : size + 1) : (complete[head] ? size - 1 : size);
  wire next_full = next_size >= `LSB_CAP - 2;

  wire head_store_exec = busy[head] && ls[head] && !complete[head] && !has_dep1[head] && !has_dep2[head] && rob_head == rob_id[head] && !sent[head];
  wire dbg_complete_head = complete[head];
  wire dbg_has_dep1_head = has_dep1[head];
  wire dbg_has_dep2_head = has_dep2[head];
  wire [`ROB_INDEX_BIT-1:0] rob_id_head = rob_id[head];
  wire sent_head = sent[head];

  // segment tree to find the first executable load instruction
  wire executable[0 : `LSB_CAP-1];
  wire [`LSB_CAP_BIT-1:0] exec_pos;
  genvar i;
  generate
    wire has_exec[0 : `LSB_CAP * 2 - 1];
    wire [`LSB_CAP_BIT-1:0] first_exec[0 : `LSB_CAP * 2 - 1];
    for (i = 0; i < `LSB_CAP; i = i + 1) begin : lsb
      assign executable[i] = busy[i] && !complete[i] && !ls[i] && !has_dep1[i] && !has_dep2[i] && !sent[i];
      assign has_exec[i+`LSB_CAP] = executable[i];
      assign first_exec[i+`LSB_CAP] = i;
    end
    for (i = 1; i < `LSB_CAP; i = i + 1) begin : seg
      assign has_exec[i]   = has_exec[i<<1] | has_exec[i<<1|1];
      assign first_exec[i] = has_exec[i<<1] ? first_exec[i<<1] : first_exec[i<<1|1];
    end
    assign exec_pos = head_store_exec ? head : first_exec[1];  // first executable load instruction
  endgenerate

  wire [31:0] addr[0 : `LSB_CAP-1];
  wire [31:0] addr_end[0 : `LSB_CAP-1];
  generate
    for (i = 0; i < `LSB_CAP; i = i + 1) begin : addr_gen
      assign addr[i] = imm[i] + val1[i];
      assign addr_end[i] = addr[i] + len[i][1:0] - 1;
    end
  endgenerate

  wire req = head_store_exec || has_exec[1]; // If true, send request to memory unit if it is not busy.
  // if memory unit is not busy, find an instruction that operands have been ready. send it to memory.
  assign req_out  = !rst_in && !clear && rdy_in && !mem_busy && req;
  assign pos_out  = exec_pos;
  assign ls_out   = ls[exec_pos];
  assign len_out  = len[exec_pos][1:0];
  assign addr_out = imm[exec_pos] + val1[exec_pos];
  assign val_out  = val2[exec_pos];

  integer file_id;
  reg [31:0] cnt;
  initial begin
    file_id = $fopen("lsb.txt", "w");
    cnt = 0;
  end

  always @(posedge clk_in) begin : LoadStoreBuffer
    integer i;
    cnt <= cnt + 1;
    $fwrite(file_id, "cycle: %d\n", cnt);
    for (i = 0; i < `LSB_CAP; i = i + 1) begin
      $fwrite(
          file_id,
          "lsb[%d]: busy: %d, ls: %d, len: %d, imm: %d, val1: %d, val2: %d, dep1: %d, dep2: %d, has_dep1: %d, has_dep2: %d, rob_id: %d, complete: %d, res: %d, sent: %d\n",
          i, busy[i], ls[i], len[i], imm[i], val1[i], val2[i], dep1[i], dep2[i], has_dep1[i],
          has_dep2[i], rob_id[i], complete[i], res[i], sent[i]);
    end
    $fwrite(file_id, "\n");
    if (rst_in || clear) begin
      // reset
      for (i = 0; i < `LSB_CAP; i = i + 1) begin
        busy[i] <= 0;
        ls[i] <= 0;
        len[i] <= 3'b000;
        imm[i] <= 0;
        val1[i] <= 0;
        val2[i] <= 0;
        dep1[i] <= 0;
        dep2[i] <= 0;
        has_dep1[i] <= 0;
        has_dep2[i] <= 0;
        rob_id[i] <= 0;
        complete[i] <= 0;
        res[i] <= 0;
        sent[i] <= 0;
      end
      head <= 0;
      tail <= 0;
      size <= 0;
      full <= 0;
      ready <= 0;
      rob_id_out <= 0;
      result <= 0;
    end else if (!rdy_in) begin
      // do nothing
    end else begin
      // insert an instruction
      if (inst_req) begin
        busy[tail] <= 1;
        imm[tail]  <= inst_imm;
        sent[tail] <= 0;

        // Note that load inst has no rs2.
        if (cdb_req && inst_has_dep1 && inst_dep1 == cdb_rob_id) begin
          val1[tail] <= cdb_val;
          has_dep1[tail] <= 0;
        end else begin
          val1[tail] <= inst_val1;
          dep1[tail] <= inst_dep1;
          has_dep1[tail] <= inst_has_dep1;
        end
        if (inst_type == `SB || inst_type == `SH || inst_type == `SW) begin
          if (cdb_req && inst_has_dep2 && inst_dep2 == cdb_rob_id) begin
            val2[tail] <= cdb_val;
            has_dep2[tail] <= 0;
          end else begin
            val2[tail] <= inst_val2;
            dep2[tail] <= inst_dep2;
            has_dep2[tail] <= inst_has_dep2;
          end
        end else begin
          has_dep2[tail] <= 0;
        end

        rob_id[tail]   <= inst_rob_id;
        complete[tail] <= 0;
        case (inst_type)
          `LB: begin
            ls[tail]  <= 0;
            len[tail] <= 3'b000;
          end
          `LH: begin
            ls[tail]  <= 0;
            len[tail] <= 3'b001;
          end
          `LW: begin
            ls[tail]  <= 0;
            len[tail] <= 3'b010;
          end
          `LBU: begin
            ls[tail]  <= 0;
            len[tail] <= 3'b100;
          end
          `LHU: begin
            ls[tail]  <= 0;
            len[tail] <= 3'b101;
          end
          `SB: begin
            ls[tail]  <= 1;
            len[tail] <= 3'b000;
          end
          `SH: begin
            ls[tail]  <= 1;
            len[tail] <= 3'b001;
          end
          `SW: begin
            ls[tail]  <= 1;
            len[tail] <= 3'b010;
          end
        endcase
      end

      // monitor the cdb. modify the dep and value of the instructions accordingly
      if (cdb_req) begin
        for (i = 0; i < `LSB_CAP; i = i + 1) begin
          if (busy[i]) begin
            if (has_dep1[i] && dep1[i] == cdb_rob_id) begin
              has_dep1[i] <= 0;
              val1[i] <= cdb_val;
            end
            if (has_dep2[i] && dep2[i] == cdb_rob_id) begin
              has_dep2[i] <= 0;
              val2[i] <= cdb_val;
            end
          end
        end
      end

      // receive message for load finish came from memory unit
      if (mem_finished) begin
        complete[mem_pos] <= 1;
        case (len[mem_pos])
          3'b000: res[mem_pos] <= $unsigned(mem_val[7:0]);
          3'b001: res[mem_pos] <= $unsigned(mem_val[15:0]);
          3'b010: res[mem_pos] <= $unsigned(mem_val[31:0]);
          3'b100: res[mem_pos] <= $signed(mem_val[7:0]);
          3'b101: res[mem_pos] <= $signed(mem_val[15:0]);
        endcase
      end

      if (!mem_busy && req) begin
        sent[exec_pos] <= 1;
      end

      // check if the head is complete. if so, commit it.
      if (busy[head] && complete[head]) begin
        ready <= 1;
        rob_id_out <= rob_id[head];
        result <= res[head];
        busy[head] <= 0;
        complete[head] <= 0;
        // If the head is a store instruction, check if there is some following load instructions have been complete.
        // If there are some, mark them incomplete.
        if (ls[head]) begin
          for (i = 0; i < `LSB_CAP; i = i + 1) begin
            if (busy[i] && complete[i] && !ls[i] && addr[head] <= addr_end[i] && addr_end[head] >= addr[i]) begin
              complete[i] <= 0;
              sent[i] <= 0;
            end
          end
        end
      end else begin
        ready <= 0;
      end

      size <= next_size;
      full <= next_full;
      head <= next_head;
      tail <= next_tail;
    end
  end
endmodule
`endif
