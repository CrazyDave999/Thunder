`include "const.v"

// RISCV32I CPU top module
// port modification allowed for debugging purposes

module cpu (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input  wire [ 7:0] mem_din,   // data input bus
    output wire [ 7:0] mem_dout,  // data output bus
    output wire [31:0] mem_a,     // address bus (only 17:0 is used)
    output wire        mem_wr,    // write/read signal (1 for write)

    input wire io_buffer_full,  // 1 if uart buffer is full

    output wire [31:0] dbgreg_dout  // cpu register output (debugging demo)
);

  // implementation goes here

  // Specifications:
  // - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
  // - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
  // - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
  // - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)
  // - 0x30000 read: read a byte from input
  // - 0x30000 write: write a byte to output (write 0x00 is ignored)
  // - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)
  // - 0x30004 write: indicates program stop (will output '\0' through uart tx)

  // wires connected to insturction unit
  // from rob
  wire [`ROB_INDEX_BIT - 1 : 0] rob_tail;
  wire rob_full;
  wire stall_end;
  wire [31:0] jalr_addr;

  wire br_req;
  wire br_correct;
  wire [31:0] br_res;
  wire [`PRED_TABLE_BIT-1:0] br_g_ind;
  wire [`PRED_TABLE_BIT-1:0] br_l_ind;

  wire clear;
  wire [31:0] clear_pc;

  // from rs
  wire rs_full;

  // from lsb
  wire lsb_full;

  // from memory_unit
  wire inst_ready;
  wire [31:0] inst;
  wire mem_busy;

  wire [31:0] pc_;
  wire stall;

  // to rob, rs, lsb, for issue
  wire to_rs;
  wire to_lsb;
  wire issue_is_c_inst;
  wire [`TYPE_BIT-1:0] issue_type;
  wire [4:0] issue_rd;
  wire [4:0] issue_rs1;
  wire [4:0] issue_rs2;
  wire [31:0] issue_addr;
  wire [31:0] issue_pred;
  wire [`PRED_TABLE_BIT-1:0] issue_g_ind;
  wire [`PRED_TABLE_BIT-1:0] issue_l_ind;
  wire [31:0] issue_imm;

  wire [4:0] set_dep_id;
  wire [`ROB_INDEX_BIT-1:0] set_dep;

  // to memory_unit
  wire inst_req;

  InstructionUnit iu (
      .clk_in(clk_in),
      .rst_in(rst_in),
      .rdy_in(rdy_in),

      .rob_tail (rob_tail),
      .rob_full (rob_full),
      .stall_end(stall_end),
      .jalr_addr(jalr_addr),

      .br_req(br_req),
      .br_correct(br_correct),
      .br_res(br_res),
      .br_g_ind(br_g_ind),
      .br_l_ind(br_l_ind),

      .clear(clear),
      .clear_pc(clear_pc),

      .rs_full (rs_full),
      .lsb_full(lsb_full),

      .inst_ready(inst_ready),
      .inst(inst),
      .mem_busy(mem_busy),

      .pc_out(pc_),
      .stall_out(stall),

      .to_rs(to_rs),
      .to_lsb(to_lsb),
      .issue_type(issue_type),
      .issue_is_c_inst(issue_is_c_inst),
      .issue_rd(issue_rd),
      .issue_rs1(issue_rs1),
      .issue_rs2(issue_rs2),
      .issue_addr(issue_addr),
      .issue_pred(issue_pred),
      .issue_g_ind(issue_g_ind),
      .issue_l_ind(issue_l_ind),
      .issue_imm(issue_imm),

      .set_dep_id_out(set_dep_id),
      .set_dep_out(set_dep),

      .inst_req(inst_req)
  );

  // wires connected to memory unit
  // from lsb
  wire data_req;
  wire [`LSB_CAP_BIT-1:0] data_pos;
  wire data_we;
  wire [1:0] data_size;
  wire [31:0] data_addr;
  wire [31:0] data_in;

  wire data_ready;
  wire [31:0] data_out;
  wire [`LSB_CAP_BIT-1:0] data_pos_out;

  MemoryUnit mu (
      .clk_in(clk_in),
      .rst_in(rst_in),
      .rdy_in(rdy_in),

      .mem_din(mem_din),
      .mem_dout(mem_dout),
      .mem_a(mem_a),
      .mem_wr(mem_wr),

      .io_buffer_full(io_buffer_full),

      .pc(pc_),
      .inst_req(inst_req),
      .inst_ready(inst_ready),
      .inst_res(inst),

      .clear(clear),

      .data_req (data_req),
      .data_pos (data_pos),
      .data_we  (data_we),
      .data_size(data_size),
      .data_addr(data_addr),
      .data_in  (data_in),

      .data_ready(data_ready),
      .data_out(data_out),
      .data_pos_out(data_pos_out),

      .busy(mem_busy)
  );

  // wires connected to rf
  // from rob, for commit
  wire [4:0] set_value_id;

  // to rs, lsb
  wire [31:0] val1;
  wire [`ROB_INDEX_BIT-1:0] dep1;
  wire has_dep1;
  wire [31:0] val2;
  wire [`ROB_INDEX_BIT-1:0] dep2;
  wire has_dep2;

  wire [31:0] cdb_val;
  wire [`ROB_INDEX_BIT-1:0] cdb_rob_id;

  //   wire dbg_commit;
  //   wire [31:0] dbg_commit_addr;

  RegisterFile rf (
      .clk_in(clk_in),
      .rst_in(rst_in),
      .rdy_in(rdy_in),

      .clear(clear),

      .req_id1(issue_rs1),
      .val1(val1),
      .dep1(dep1),
      .has_dep1(has_dep1),

      .req_id2(issue_rs2),
      .val2(val2),
      .dep2(dep2),
      .has_dep2(has_dep2),

      .set_dep_id(set_dep_id),
      .set_dep(set_dep),

      .set_value_id(set_value_id),
      .set_value(cdb_val),
      .set_value_rob_id(cdb_rob_id)

      //   .dbg_commit(dbg_commit),
      //   .dbg_commit_addr(dbg_commit_addr)
  );

  // wires connected to rs
  // cdb, from rob, for commit
  wire cdb_req;


  // to rob, for write back
  wire rs_ready;
  wire [`ROB_INDEX_BIT-1:0] rs_rob_id;
  wire [31:0] rs_result;

  // from rob
  ReservationStation rs (
      .clk_in(clk_in),
      .rst_in(rst_in),
      .rdy_in(rdy_in),

      .inst_req(to_rs),
      .inst_is_c(issue_is_c_inst),
      .inst_type(issue_type),
      .inst_addr(issue_addr),
      .inst_imm(issue_imm),
      .inst_rob_id(rob_tail),

      .inst_val1(val1),
      .inst_dep1(dep1),
      .inst_has_dep1(has_dep1),
      .inst_val2(val2),
      .inst_dep2(dep2),
      .inst_has_dep2(has_dep2),

      .cdb_req(cdb_req),
      .cdb_val(cdb_val),
      .cdb_rob_id(cdb_rob_id),

      .clear(clear),

      .full(rs_full),

      .rs_ready (rs_ready),
      .rs_rob_id(rs_rob_id),
      .rs_result(rs_result)
  );

  // wires connected to lsb
  // from rob
  wire [`ROB_INDEX_BIT-1:0] rob_head;

  // to rob, for write back
  wire lsb_ready;
  wire [`ROB_INDEX_BIT-1:0] lsb_rob_id;
  wire [31:0] lsb_result;

  LoadStoreBuffer lsb (
      .clk_in(clk_in),
      .rst_in(rst_in),
      .rdy_in(rdy_in),

      .io_buffer_full(io_buffer_full),

      .inst_req(to_lsb),
      .inst_type(issue_type),
      .inst_imm(issue_imm),
      .inst_rob_id(rob_tail),

      .inst_val1(val1),
      .inst_dep1(dep1),
      .inst_has_dep1(has_dep1),
      .inst_val2(val2),
      .inst_dep2(dep2),
      .inst_has_dep2(has_dep2),

      .cdb_req(cdb_req),
      .cdb_val(cdb_val),
      .cdb_rob_id(cdb_rob_id),
      .rob_head(rob_head),

      .clear(clear),

      .mem_finished(data_ready),
      .mem_val(data_out),
      .mem_pos(data_pos_out),
      .mem_busy(mem_busy),

      .full(lsb_full),

      .req_out (data_req),
      .pos_out (data_pos),
      .ls_out  (data_we),
      .len_out (data_size),
      .addr_out(data_addr),
      .val_out (data_in),

      .ready(lsb_ready),
      .rob_id_out(lsb_rob_id),
      .result(lsb_result)
  );

  ReorderBuffer rob (
      .clk_in(clk_in),
      .rst_in(rst_in),
      .rdy_in(rdy_in),

      .inst_req (to_rs | to_lsb),
      .inst_is_c(issue_is_c_inst),
      .inst_type(issue_type),
      .inst_imm (issue_imm),
      .inst_rd  (issue_rd),
      .inst_addr(issue_addr),
      .inst_pred(issue_pred),

      .rs_ready (rs_ready),
      .rs_rob_id(rs_rob_id),
      .rs_result(rs_result),

      .lsb_ready (lsb_ready),
      .lsb_rob_id(lsb_rob_id),
      .lsb_result(lsb_result),

      .full_out (rob_full),
      .clear_out(clear),
      .clear_pc (clear_pc),
      .head_out (rob_head),
      .tail_out (rob_tail),

      .cdb_req_out(cdb_req),

      .cdb_val_out(cdb_val),
      .cdb_rob_id_out(cdb_rob_id),

      .rd_out(set_value_id),

      .jalr_ready(stall_end),
      .jalr_addr (jalr_addr),

      .br_ready(br_req),
      .br_res(br_res),
      .br_correct(br_correct),
      .br_g_ind(br_g_ind),
      .br_l_ind(br_l_ind)
      //   .dbg_commit(dbg_commit),
      //   .dbg_commit_addr(dbg_commit_addr)
  );
endmodule
