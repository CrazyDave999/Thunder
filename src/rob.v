`ifndef ROB_V
`define ROB_V
`include "const.v"
module ReorderBuffer(
    input wire clk_in, // clock signal
    input wire rst_in, // reset signal when high
    input wire rdy_in, // ready signal, pause cpu when low 

    // from instruction unit
    input wire inst_req,
    input wire [`TYPE_BIT-1:0] inst_type,
    input wire [31:0] inst_imm,
    input wire [4:0] inst_rd,
    input wire [31:0] inst_addr,
    input wire [31:0] inst_pred, // 0 or 1

    // cdb, from rs
    input wire rs_ready,
    input wire [`ROB_INDEX_BIT-1:0] rs_rob_id,
    input wire [31:0] rs_result,

    // cdb, from lsb
    input wire lsb_ready,
    input wire [`ROB_INDEX_BIT-1:0] lsb_rob_id,
    input wire [31:0] lsb_result,

    // from memory_unit
    input wire mem_busy,

    output wire full_out,
    output wire clear_out,
    output reg  [31:0] clear_pc,
    output wire [`ROB_INDEX_BIT-1:0] head_out,
    output wire [`ROB_INDEX_BIT-1:0] tail_out,

    // to rs and lsb
    output reg cdb_req_out, // indicate whether rs and lsb should receive

    output reg [31:0] cdb_val_out,
    output reg [`ROB_INDEX_BIT-1:0] cdb_rob_id_out,

    // to rf
    output reg [4:0] rd_out, // indicate whether rf should receive

    // to instruction unit
    output reg jalr_ready, // i.e. stall_end
    output reg [31:0] jalr_addr,
    
    output reg br_ready,
    output reg [31:0] br_res,
    output reg br_correct,
    output reg [`PRED_TABLE_BIT-1:0] br_g_ind,
    output reg [`PRED_TABLE_BIT-1:0] br_l_ind,

    output reg dbg_commit,
    output reg [31:0] dbg_commit_addr
);
    reg busy [0 : `ROB_CAP-1];
    reg [`TYPE_BIT-1:0] type [0 : `ROB_CAP-1];
    reg [`ROB_STAT_BIT-1: 0] stat [0 : `ROB_CAP-1]; // 0: issue, 1: write back, 2: commit
    reg [31:0] imm [0 : `ROB_CAP-1]; // only for branch
    reg [4:0] rd [0 : `ROB_CAP-1];
    reg [31:0] res [0 : `ROB_CAP-1];
    reg [31:0] addr [0 : `ROB_CAP-1];
    reg [31:0] pred [0 : `ROB_CAP-1]; // predict result of branch instruction
    reg [`PRED_TABLE_BIT - 1 :0] g_ind [0 : `ROB_CAP-1];
    reg [`PRED_TABLE_BIT - 1 :0] l_ind [0 : `ROB_CAP-1];

    reg full;
    reg [31:0] size;
    reg [`ROB_CAP-1:0] head, tail;
    
    wire [31:0] next_size = inst_req ? (stat[head]==1 ? size : size+1) : (stat[head]== 1 ? size-1 : size);
    wire [`ROB_INDEX_BIT-1:0] next_head = (stat[head] == 1) ? (head + 1) % `ROB_CAP : head;
    wire [`ROB_INDEX_BIT-1:0] next_tail = inst_req ? (tail + 1) % `ROB_CAP : tail;
    wire next_full = next_size >= `ROB_CAP - 2;
    assign head_out = head;
    assign tail_out = tail;
    assign full_out = full;

    reg clear; // for misprediction
    assign clear_out = clear;

    integer file_id;
    reg [31:0] cnt;
    initial begin
        cnt = 0;
        file_id = $fopen("rob.txt", "w");
    end
    always @(posedge clk_in) begin: rob
        integer i;
        cnt <= cnt + 1;
        $fwrite(file_id, "cycle: %d\n", cnt);
        for (i = 0; i < `ROB_CAP; i = i + 1) begin
            $fwrite(file_id, "rob[%d]: busy: %d, type: %d, stat: %d, imm: %d, rd: %d, res: %d, addr: %h\n", i, busy[i], type[i], stat[i], imm[i], rd[i], res[i], addr[i]);
        end
        $fwrite(file_id, "\n");
        if (rst_in || clear) begin
            // reset
            for (i = 0; i < `ROB_CAP; i = i + 1) begin
                busy[i] <= 0;
                type[i] <= 0;
                stat[i] <= 0;
                imm[i] <= 0;
                rd[i] <= 0;
                res[i] <= 0;
                addr[i] <= 0;
                pred[i] <= 0;
                g_ind[i] <= 0;
                l_ind[i] <= 0;
            end
            full <= 0;
            size <= 0;
            head <= 0;
            tail <= 0;
            cdb_req_out <= 0;
            cdb_val_out <= 0;
            cdb_rob_id_out <= 0;
            rd_out <= 0;
            jalr_ready <= 0;
            jalr_addr <= 0;
            br_ready <= 0;
            br_correct <= 0;
            br_g_ind <=0;
            br_l_ind <= 0;
            br_res <= 0;
            clear <= 0;
            clear_pc <= 0;

            dbg_commit <= 0;
            dbg_commit_addr <= 0;
        end else if (!rdy_in) begin
            // do nothing
        end else begin
            if (inst_req) begin
                busy[tail] <= 1;
                case(inst_type)
                    `JAL: type[tail] <= `ADD;
                    `LUI: type[tail] <= `ADD;
                    `AUIPC: type[tail] <= `ADD;
                    
                    `ADDI: type[tail]<= `ADD;
                    `SLTI: type[tail]<= `SLT;
                    `SLTIU:type[tail]<= `SLTU;
                    `XORI: type[tail]<= `XOR;
                    `ORI:  type[tail]<= `OR;
                    `ANDI: type[tail]<= `AND;
                    `SLLI: type[tail]<= `SLL;
                    `SRLI: type[tail]<= `SRL;
                    `SRAI: type[tail]<= `SRA;
                    default: type[tail] <= inst_type;
                endcase
                stat[tail] <= 0;
                imm[tail] <= inst_imm;
                rd[tail] <= inst_rd;
                addr[tail] <= inst_addr;
                pred[tail] <= inst_pred;
            end
            if (rs_ready) begin
                res[rs_rob_id] <= rs_result;
                stat[rs_rob_id] <= 1;
            end
            if (lsb_ready) begin
                res[lsb_rob_id] <= lsb_result;
                stat[lsb_rob_id] <= 1;
            end
            if (stat[head] == 1) begin
                dbg_commit_addr <= addr[head];
                dbg_commit <= 1;
                // commit
                stat[head] <= 2;
                busy[head] <= 0;
                case (type[head])
                    `LB, `LH, `LW, `LBU, `LHU, `ADD, `SUB, `SLL, `SLT, `SLTU, `XOR, `SRL, `SRA, `OR, `AND: begin
                        rd_out <= rd[head];

                        cdb_req_out <= 1;
                        cdb_val_out <= res[head];
                        cdb_rob_id_out <= head;

                        jalr_ready <= 0;
                        br_ready <= 0;
                    end
                    `SB, `SH, `SW: begin
                        rd_out <= 0;
                        cdb_req_out <= 0;
                        jalr_ready <= 0;
                        br_ready <= 0;
                    end
                    `BEQ, `BNE, `BLT, `BGE, `BLTU, `BGEU: begin
                        if (pred[head] != res[head]) begin
                            // predict failed. clean and correct the pc_.
                            // $display("misprediction", res[head], pred[head]);
                            clear <= 1;
                            if (res[head]) begin
                                clear_pc <= addr[head] + imm[head];
                            end else begin
                                clear_pc <= addr[head] + 4;
                            end
                        end
                        br_ready <= 1;
                        br_res <= res[head];
                        br_correct <= pred[head] == res[head];
                        br_g_ind <= g_ind[head];
                        br_l_ind <= l_ind[head];
                    end
                    `JALR: begin
                        rd_out <= rd[head];
                        cdb_val_out <= addr[head] + 4;
                        cdb_rob_id_out <= head;

                        cdb_req_out <= 0;
                        jalr_ready <= 1;
                        jalr_addr <= res[head];
                        br_ready <= 0;
                    end
                endcase

                $fwrite(file_id, "commit head: %d, addr: %h, res: %d\n\n", head, addr[head], res[head]);
                // $display("commit head: %d, addr: %d, res: %d", head, addr[head], res[head]);

            end else begin
                rd_out <= 0;
                cdb_req_out <= 0;
                jalr_ready <= 0;
                br_ready <= 0;

                dbg_commit <= 0;
            end
            size <= next_size;
            full <= next_full;
            head <= next_head;
            tail <= next_tail;
        end
    end
endmodule
`endif