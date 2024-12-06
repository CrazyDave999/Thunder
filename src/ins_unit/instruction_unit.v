`ifndef INSTRUCTION_UNIT_V
`define INSTRUCTION_UNIT_V

`include "const.v"
`include "ins_unit/decoder.v"
`include "ins_unit/predictor.v"

module InstructionUnit (
    input wire clk_in, // clock signal
    input wire rst_in, // reset signal when high
    input wire rdy_in, // ready signal, pause cpu when low

    // from rob
    input wire [`ROB_INDEX_BIT-1:0] rob_tail,
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
    output wire to_rs,
    output wire to_lsb,
    output wire [`TYPE_BIT-1:0] issue_type,
    output wire [4:0] issue_rd,
    output wire [4:0] issue_rs1,
    output wire [4:0] issue_rs2,
    output wire [31:0] issue_addr, // for branch and jalr only
    output wire [31:0] issue_pred, 
    output wire [`PRED_TABLE_BIT-1:0] issue_g_ind,
    output wire [`PRED_TABLE_BIT-1:0] issue_l_ind,
    output wire [31:0] issue_imm, // for load/store and branch only

    // to rf
    output wire [4:0] set_dep_id_out,
    output wire [`ROB_INDEX_BIT-1:0] set_dep_out,
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
    wire dec_ready;

    // If an instruciton modifies pc, then the current pc value is wrong, which is the result of +4 operation last cycle. 
    // To fix this, if the inst this cycle modifies pc, then this inst should not be decoded.
    wire is_br = type == `BEQ || type == `BNE || type == `BLT || type == `BGE || type == `BLTU || type == `BGEU;
    wire modify_pc = type == `JAL || (is_br && pred);

    Decoder decoder (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),
        .inst_req(inst_ready && !modify_pc && !stall),
        .inst(inst),
        .ready_out(dec_ready),
        .type_out(type),
        .rs1_out(rs1),
        .rs2_out(rs2),
        .rd_out(rd),
        .imm_out(imm)
    );
    wire [31:0] dec_addr = pc - 4; // the address of the instruction decoder return in this cycle

    // from predictor
    wire [31:0] pred;
    wire [`PRED_TABLE_BIT-1:0] g_ind, l_ind;
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

    assign inst_req = !stall && !mem_busy;
    // if the inst of this cycle's pc is not in icache, should not +4, otherwise it will be missed
    wire [31:0] step = inst_ready ? 4 : 0;
    wire will_issue = !rob_full && !rs_full && !lsb_full && dec_ready && !stall;
    wire is_lsb_type = type == `LB || type == `LH || type == `LW || type == `LBU || type == `LHU || type == `SB || type == `SH || type == `SW;
    assign to_rs = will_issue && !is_lsb_type;
    assign to_lsb = will_issue && is_lsb_type;
    assign issue_type = type;
    assign issue_rd = rd;
    assign issue_rs1 = rs1;
    assign issue_rs2 = rs2;
    assign issue_addr = dec_addr;
    assign issue_pred = pred;
    assign issue_g_ind = g_ind;
    assign issue_l_ind = l_ind;
    assign issue_imm = imm;

    assign set_dep_id_out = will_issue ? rd : 0;
    assign set_dep_out = will_issue ? rob_tail : 0;

    always @(posedge clk_in) begin
        if (rst_in || clear) begin
            // reset
            if (clear) begin
                pc <= clear_pc;
            end else begin
                pc <= 0;
            end
            stall <= 0;
        end
        else if (!rdy_in) begin
            // do nothing
        end 
        else if (!stall) begin
            // issue
            if (will_issue) begin
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
                            pc <= pc + imm;
                        end else begin
                            pc <= pc + step;
                        end
                    end
                endcase
            end else begin
                pc <= pc + step;
            end
        end else begin
            if (stall_end) begin
                stall <= 0;
                pc <= jalr_addr;
            end
        end
    end
endmodule
`endif