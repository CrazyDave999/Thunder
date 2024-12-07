`ifndef RF_V
`define RF_V
`include "const.v"
/*
    Only two operations will modify rf.
    1. When ROB commit an instruction.
        Set the value of rd. If dep is still this inst, set has_dep to 0.
    2. When an instruction be issued.
        Set the dep of rd.
*/
module RegisterFile (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input clear,

    // from instrution unit
    input wire [4:0] req_id1,
    output wire [31:0] val1,
    output wire [`ROB_INDEX_BIT-1:0] dep1,
    output wire has_dep1,

    input wire [4:0] req_id2,
    output wire [31:0] val2,
    output wire [`ROB_INDEX_BIT-1:0] dep2,
    output wire has_dep2,

    input wire [4:0] set_dep_id,
    input wire [`ROB_INDEX_BIT-1:0] set_dep,  // the instruction issued this cycle

    // from rob
    input wire [4:0] set_value_id,
    input wire [31:0] set_value,
    input wire [`ROB_INDEX_BIT-1:0] set_value_rob_id, // the rob_id of instruction commited this cycle
    input wire dbg_commit,
    input wire [31:0] dbg_commit_addr
);
  reg [31 : 0] rf[0:31];
  reg [`ROB_INDEX_BIT-1:0] dep[0 : 31];
  reg has_dep[0 : 31];
  assign val1 = rf[req_id1];
  assign val2 = rf[req_id2];
  assign dep1 = dep[req_id1];
  assign dep2 = dep[req_id2];
  assign has_dep1 = has_dep[req_id1];
  assign has_dep2 = has_dep[req_id2];

  // wire [31:0] dbg_x0 = rf[0];
  // wire [31:0] dbg_x1 = rf[1];
  // wire [31:0] dbg_x2 = rf[2];
  // wire [31:0] dbg_x3 = rf[3];
  // wire [31:0] dbg_x4 = rf[4];
  // wire [31:0] dbg_x5 = rf[5];
  // wire [31:0] dbg_x6 = rf[6];
  // wire [31:0] dbg_x7 = rf[7];
  // wire [31:0] dbg_x8 = rf[8];
  // wire [31:0] dbg_x9 = rf[9];
  // wire [31:0] dbg_x10 = rf[10];
  // wire [31:0] dbg_x11 = rf[11];
  // wire [31:0] dbg_x12 = rf[12];
  // wire [31:0] dbg_x13 = rf[13];
  // wire [31:0] dbg_x14 = rf[14];
  // wire [31:0] dbg_x15 = rf[15];
  // wire [31:0] dbg_x16 = rf[16];
  // wire [31:0] dbg_x17 = rf[17];
  // wire [31:0] dbg_x18 = rf[18];
  // wire [31:0] dbg_x19 = rf[19];
  // wire [31:0] dbg_x20 = rf[20];
  // wire [31:0] dbg_x21 = rf[21];
  // wire [31:0] dbg_x22 = rf[22];
  // wire [31:0] dbg_x23 = rf[23];
  // wire [31:0] dbg_x24 = rf[24];
  // wire [31:0] dbg_x25 = rf[25];
  // wire [31:0] dbg_x26 = rf[26];
  // wire [31:0] dbg_x27 = rf[27];
  // wire [31:0] dbg_x28 = rf[28];
  // wire [31:0] dbg_x29 = rf[29];
  // wire [31:0] dbg_x30 = rf[30];
  // wire [31:0] dbg_x31 = rf[31];

  // wire dbg_has_dep_0 = has_dep[0];
  // wire dbg_has_dep_1 = has_dep[1];
  // wire dbg_has_dep_2 = has_dep[2];
  // wire dbg_has_dep_3 = has_dep[3];
  // wire dbg_has_dep_4 = has_dep[4];
  // wire dbg_has_dep_5 = has_dep[5];
  // wire dbg_has_dep_6 = has_dep[6];
  // wire dbg_has_dep_7 = has_dep[7];
  // wire dbg_has_dep_8 = has_dep[8];
  // wire dbg_has_dep_9 = has_dep[9];
  // wire dbg_has_dep_10 = has_dep[10];
  // wire dbg_has_dep_11 = has_dep[11];
  // wire dbg_has_dep_12 = has_dep[12];
  // wire dbg_has_dep_13 = has_dep[13];
  // wire dbg_has_dep_14 = has_dep[14];
  // wire dbg_has_dep_15 = has_dep[15];
  // wire dbg_has_dep_16 = has_dep[16];
  // wire dbg_has_dep_17 = has_dep[17];
  // wire dbg_has_dep_18 = has_dep[18];
  // wire dbg_has_dep_19 = has_dep[19];    
  // wire dbg_has_dep_20 = has_dep[20];
  // wire dbg_has_dep_21 = has_dep[21];
  // wire dbg_has_dep_22 = has_dep[22];
  // wire dbg_has_dep_23 = has_dep[23];
  // wire dbg_has_dep_24 = has_dep[24];
  // wire dbg_has_dep_25 = has_dep[25];
  // wire dbg_has_dep_26 = has_dep[26];
  // wire dbg_has_dep_27 = has_dep[27];
  // wire dbg_has_dep_28 = has_dep[28];
  // wire dbg_has_dep_29 = has_dep[29];
  // wire dbg_has_dep_30 = has_dep[30];
  // wire dbg_has_dep_31 = has_dep[31];

  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_0 = dep[0];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_1 = dep[1];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_2 = dep[2];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_3 = dep[3];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_4 = dep[4];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_5 = dep[5];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_6 = dep[6];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_7 = dep[7];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_8 = dep[8];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_9 = dep[9];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_10 = dep[10];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_11 = dep[11];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_12 = dep[12];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_13 = dep[13];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_14 = dep[14];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_15 = dep[15];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_16 = dep[16];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_17 = dep[17];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_18 = dep[18];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_19 = dep[19];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_20 = dep[20];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_21 = dep[21];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_22 = dep[22];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_23 = dep[23];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_24 = dep[24];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_25 = dep[25];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_26 = dep[26];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_27 = dep[27];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_28 = dep[28];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_29 = dep[29];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_30 = dep[30];
  // wire [`ROB_INDEX_BIT-1:0] dbg_dep_31 = dep[31];


  integer file_id;
  reg [31:0] cnt;
  initial begin
    cnt = 0;
    file_id = $fopen("rf.txt", "w");
  end

  always @(posedge clk_in) begin : RegisterFile
    integer i;
    cnt <= cnt + 1;
    if (dbg_commit) begin
        for (i = 0; i < 32; i = i + 1) begin
            $fwrite(file_id, "rf[%d]: %d\n", i, rf[i]);
        end
        $fwrite(file_id, "\ncommit addr: %h\n",dbg_commit_addr);
    end
    
    
    if (rst_in) begin
      for (i = 0; i < 32; i = i + 1) begin
        rf[i] <= 0;
        dep[i] <= 0;
        has_dep[i] <= 0;
      end
    end else if (!rdy_in) begin
      // do nothing
    end else if (clear) begin
      for (i = 0; i < 32; i = i + 1) begin
        dep[i] <= 0;
        has_dep[i] <= 0;
      end
    end else begin
      if (set_value_id > 0) begin
        rf[set_value_id] <= set_value;
        if (set_dep_id != set_value_id && has_dep[set_value_id] && dep[set_value_id] == set_value_rob_id) begin
          dep[set_value_id] <= 0;
          has_dep[set_value_id] <= 0;
        end
      end
      if (set_dep_id > 0) begin
        dep[set_dep_id] <= set_dep;
        has_dep[set_dep_id] <= 1;
      end
    end
  end
endmodule
`endif
