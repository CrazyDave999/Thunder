`ifndef INSTRUCTION_UNIT_V
`define INSTRUCTION_UNIT_V

`include "const.v"
/*
    pc/inst/inst_ready -> cur_inst/cur_inst_ready -> dec_ready/type -> issue
*/

module InstructionUnit (
    input wire clk_in, // clock signal
    input wire rst_in, // reset signal when high
    input wire rdy_in, // ready signal, pause cpu when low

    // from rob
    input wire rob_full,
    input wire stall_end, // i.e. jalr_ready
    input wire [31:0] jalr_addr,

    input wire br_req,
    input wire br_correct,
    input wire [31:0] br_res,
    input wire [`PRED_TABLE_BIT-1:0] br_g_ind,
    input wire [`PRED_TABLE_BIT-1:0] br_l_ind,

    input wire clear,
    input wire [31:0] clear_pc,

    // from rs
    input wire rs_full,

    // from lsb
    input wire lsb_full,

    // from memory_unit
    input wire inst_ready,
    input wire [31:0] inst,
    input wire mem_busy,

    output wire [31:0] pc_out,
    output wire stall_out,

    // to rob, rs, lsb, for issue
    output reg to_rs,
    output reg to_lsb,
    output reg issue_is_c_inst,
    output reg [`TYPE_BIT-1:0] issue_type,
    output reg [4:0] issue_rd,
    output reg [4:0] issue_rs1,
    output reg [4:0] issue_rs2,
    output reg [31:0] issue_addr, // for branch and jalr only
    output reg [31:0] issue_pred, 
    output reg [`PRED_TABLE_BIT-1:0] issue_g_ind,
    output reg [`PRED_TABLE_BIT-1:0] issue_l_ind,
    output reg [31:0] issue_imm, // for load/store and branch only

    // to rf
    output reg [4:0] set_dep_id_out,

    // to memory_unit
    output wire inst_req
);
    reg [31:0] pc;
    assign pc_out = pc;
    reg stall; // indicate if will issue inst in this cycle
    assign stall_out = stall;

    // from decoder
    wire [`TYPE_BIT-1:0] type;
    wire [4:0] rs1, rs2, rd;
    wire [31:0] imm;
    reg dec_ready;

    wire something_full = rob_full || rs_full || lsb_full;

    reg [31:0] dec_addr; // the address of the instruction decoder return in this cycle
    wire is_c_inst = inst[1:0] != 2'b11; // indicate if the inst with current pc is a compressed instruction
    reg dec_is_c_inst; // indicate if the inst decoder return is a compressed instruction

    // from predictor
    wire [31:0] pred;
    wire [`PRED_TABLE_BIT-1:0] g_ind, l_ind;

    // If an instruciton modifies pc, then the current pc value is wrong, which is the result of +4 operation last cycle. 
    // To fix this, if the inst this cycle modifies pc, then this inst should not be decoded.
    wire is_br = type == `BEQ || type == `BNE || type == `BLT || type == `BGE || type == `BLTU || type == `BGEU;
    wire modify_pc = dec_ready && (type == `JAL || (is_br && pred));

    // buffers, to reduce WNS
    reg [31:0] cur_inst;
    reg cur_inst_ready;
    reg [31:0] cur_pc;
    reg cur_is_c_inst;

    Decoder decoder (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .inst(cur_inst),

        .type_out(type),
        .rs1_out(rs1),
        .rs2_out(rs2),
        .rd_out(rd),
        .imm_out(imm)
    );

    Predictor predictor (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .inst_req(dec_ready),
        .inst_addr(dec_addr),

        .br_req(br_req),
        .br_correct(br_correct),
        .br_res(br_res),
        .br_g_ind(br_g_ind),
        .br_l_ind(br_l_ind),
        
        .pred_out(pred),
        .g_ind_out(g_ind),
        .l_ind_out(l_ind)
    );

    // if the inst of this cycle's pc is not in icache, should not +4, otherwise it will be missed
    wire [31:0] step = (inst_ready && !something_full) ? (is_c_inst ? 2 : 4) : 0;
    wire will_issue = dec_ready && !stall;
    wire is_lsb_type = type == `LB || type == `LH || type == `LW || type == `LBU || type == `LHU || type == `SB || type == `SH || type == `SW;

    reg cur_mem_busy; // to reduce WNS
    assign inst_req = !stall && !cur_mem_busy;

    always @(posedge clk_in) begin
        cur_mem_busy <= mem_busy;
        dec_addr <= cur_pc;
        dec_is_c_inst <= cur_is_c_inst;
        dec_ready <= cur_inst_ready && !modify_pc && !stall && !clear;
        if (rst_in || clear) begin
            // reset
            if (clear) begin
                pc <= clear_pc;
            end else begin
                pc <= 0;
            end
            stall <= 0;
            to_rs <= 0;
            to_lsb <= 0;
            set_dep_id_out <= 0;
            cur_inst <= 0;
            cur_inst_ready <= 0;
            cur_pc <= 0;
            cur_is_c_inst <= 0;
        end
        else if (!rdy_in) begin
            // do nothing
        end 
        else if (!stall) begin
            // issue
            cur_inst_ready <= inst_ready && !modify_pc && !something_full;
            cur_inst <= inst;
            cur_pc <= pc;
            cur_is_c_inst <= is_c_inst;
            if (will_issue) begin
                to_rs <= !is_lsb_type;
                to_lsb <= is_lsb_type;
                issue_is_c_inst <= dec_is_c_inst;
                issue_type <= type;
                issue_rd <= rd;
                issue_rs1 <= rs1;
                issue_rs2 <= rs2;
                issue_addr <= dec_addr;
                issue_pred <= pred;
                issue_g_ind <= g_ind;
                issue_l_ind <= l_ind;
                issue_imm <= imm;

                set_dep_id_out <= rd;

                case(type)
                    `JAL: begin
                        pc <= dec_addr + imm;
                    end
                    `LUI: begin
                        pc <= pc + step;
                    end
                    `AUIPC: begin
                        pc <= pc + step;
                    end
                    `LB, `LH, `LW, `LBU, `LHU, `SB, `SH, `SW: begin
                        pc <= pc + step;
                    end
                    `ADD, `SUB, `SLL, `SLT, `SLTU, `XOR, `SRL, `SRA, `OR, `AND: begin
                        pc <= pc + step;
                    end
                    `ADDI, `SLTI, `SLTIU, `XORI, `ORI, `ANDI, `SLLI, `SRLI, `SRAI, `JALR: begin
                        pc <= pc + step;
                        if (type == `JALR) begin
                            stall <= 1;
                        end
                    end
                    `BEQ, `BNE, `BLT, `BGE, `BLTU, `BGEU: begin
                        if (pred) begin
                            pc <= dec_addr + imm;
                        end else begin
                            pc <= pc + step;
                        end
                    end
                endcase
            end else begin
                // decoder res not ready
                // inst not in icache, or inst modifies pc, or something full
                to_rs <= 0;
                to_lsb <= 0;
                set_dep_id_out <= 0;
                pc <= pc + step;
            end
        end else begin
            to_rs <= 0;
            to_lsb <= 0;
            set_dep_id_out <= 0;
            cur_inst_ready <= 0;
            if (stall_end) begin
                stall <= 0;
                pc <= jalr_addr;
            end
        end
    end
endmodule
`endif