`ifndef RS_V
`define RS_V
`include "const.v"

module ReservationStation(
    input wire clk_in, // clock signal
    input wire rst_in, // reset signal when high
    input wire rdy_in, // ready signal, pause cpu when low

    // from instruction unit
    input wire inst_req,
    input wire inst_is_c,
    input wire [`TYPE_BIT-1:0] inst_type,
    input wire [31:0] inst_addr,
    input wire [31:0] inst_imm,
    input wire [`ROB_INDEX_BIT-1:0] inst_rob_id, // from rob

    // from rf
    input wire [31:0] inst_val1,
    input wire [`ROB_INDEX_BIT-1:0] inst_dep1,
    input wire inst_has_dep1,
    input wire [31:0] inst_val2,
    input wire [`ROB_INDEX_BIT-1:0] inst_dep2,
    input wire inst_has_dep2,

    // cdb, from rob, for commit
    input wire cdb_req,
    input wire [31:0] cdb_val,
    input wire [`ROB_INDEX_BIT-1:0] cdb_rob_id,

    input wire clear,

    output reg full,

    //  to rob, for write back
    output wire rs_ready,
    output wire [`ROB_INDEX_BIT-1:0] rs_rob_id,
    output wire [31:0] rs_result
);
    reg busy [0 : `RS_CAP-1];
    reg [`TYPE_BIT-1:0] type [0 : `RS_CAP-1];
    reg [`ROB_INDEX_BIT-1:0] rob_id [0 : `RS_CAP-1];
    reg [31:0] v1 [0 : `RS_CAP-1];
    reg [31:0] v2 [0 : `RS_CAP-1];
    reg has_dep1 [0 : `RS_CAP-1];
    reg has_dep2 [0 : `RS_CAP-1];
    reg [`ROB_INDEX_BIT-1:0] dep1 [0 : `RS_CAP-1];
    reg [`ROB_INDEX_BIT-1:0] dep2 [0 : `RS_CAP-1];
    reg [31:0] size;



    wire executable [0 : `RS_CAP-1];
    wire [`RS_CAP_BIT-1:0] exec_pos;
    wire [`RS_CAP_BIT-1:0] empty_pos;

    // segment tree to find the first executable slot and the first empty slot    
    genvar i;
    generate
        wire has_exec [0 : `RS_CAP * 2 - 1];
        wire [`RS_CAP_BIT-1:0] first_exec [0 : `RS_CAP * 2 - 1];
        wire has_empty [0 : `RS_CAP * 2 - 1];   
        wire [`RS_CAP_BIT-1:0] first_empty [0 : `RS_CAP * 2 - 1];
        for (i = 0; i < `RS_CAP; i = i + 1) begin: rs
            assign executable[i] = busy[i] && !has_dep1[i] && !has_dep2[i];
            assign has_exec[i+`RS_CAP] = executable[i];
            assign first_exec[i+`RS_CAP] = i;
            assign has_empty[i+`RS_CAP] = ~busy[i];
            assign first_empty[i+`RS_CAP] = i;
        end
        for (i = 1; i < `RS_CAP; i = i + 1) begin: seg
            assign has_exec[i] = has_exec[i<<1] | has_exec[i<<1|1];
            assign first_exec[i] = has_exec[i<<1] ? first_exec[i<<1] : first_exec[i<<1|1];
            assign has_empty[i] = has_empty[i<<1] | has_empty[i<<1|1];
            assign first_empty[i] = has_empty[i<<1] ? first_empty[i<<1] : first_empty[i<<1|1];
        end
        assign exec_pos = first_exec[1];
        assign empty_pos = first_empty[1];
    endgenerate


    // instantiate alu here since we can calculate the result immediately
    ArithmeticLogicUnit alu(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),
        .inst_type(type[exec_pos]),
        .req(executable[exec_pos] && !clear),
        .r1(v1[exec_pos]),
        .r2(v2[exec_pos]),
        .rob_id_in(rob_id[exec_pos]),
        .ready(rs_ready),
        .rob_id_out(rs_rob_id),
        .result(rs_result)
    );

    wire [31:0] next_size = inst_req ? (has_exec[1] ? size : size + 1) : (has_exec[1] ? size -1 : size);
    wire next_full = next_size >= `RS_CAP - 3;
    
    // integer file_id;
    // reg [31:0] cnt;
    // initial begin
    //     file_id = $fopen("rs.txt", "w");
    //     cnt = 0;
    // end

    always @(posedge clk_in) begin: ReservationStation
        integer i;

        // cnt <= cnt + 1;
        // $fwrite(file_id, "cycle: %d\n", cnt);
        // for (i = 0; i < `RS_CAP; i = i + 1) begin
        //     $fwrite(file_id, "rs[%d]: busy: %d, type: %d, rob_id: %d, v1: %d, v2: %d, has_dep1: %d, has_dep2: %d, dep1: %d, dep2: %d\n", i, busy[i], type[i], rob_id[i], v1[i], v2[i], has_dep1[i], has_dep2[i], dep1[i], dep2[i]);
        // end
        // $fwrite(file_id, "\n");

        if (rst_in || clear) begin
            // reset
            for (i = 0; i < `RS_CAP; i = i + 1) begin
                busy[i] <= 0;
                type[i] <= 0;
                rob_id[i] <= 0;
                v1[i] <= 0;
                v2[i] <= 0;
                has_dep1[i] <= 0;
                has_dep2[i] <= 0;
                dep1[i] <= 0;
                dep2[i] <= 0;
            end
            size <= 0;
            full <= 0;
        end else if (!rdy_in) begin
            // do nothing
        end else begin
            // insert a new instruction
            if (inst_req) begin
                busy[empty_pos] <= 1;
                rob_id[empty_pos] <= inst_rob_id;
                case (inst_type)
                    `JAL: begin
                        type[empty_pos] <= `ADD;
                        v1[empty_pos] <= 0;
                        v2[empty_pos] <= inst_addr + (inst_is_c ? 2 : 4);
                        has_dep1[empty_pos] <= 0;
                        has_dep2[empty_pos] <= 0;
                    end
                    `LUI: begin
                        type[empty_pos] <= `ADD;
                        v1[empty_pos] <= 0;
                        v2[empty_pos] <= inst_imm;
                        has_dep1[empty_pos] <= 0;
                        has_dep2[empty_pos] <= 0;
                    end
                    `AUIPC: begin
                        type[empty_pos] <= `ADD;
                        v1[empty_pos] <= 0;
                        v2[empty_pos] <= inst_addr + inst_imm;
                        has_dep1[empty_pos] <= 0;
                        has_dep2[empty_pos] <= 0;
                    end
                    `ADD, `SUB, `SLL, `SLT, `SLTU, `XOR, `SRL, `SRA, `OR, `AND, `BEQ, `BNE, `BLT, `BGE, `BLTU, `BGEU: begin
                        type[empty_pos] <= inst_type;
                        if (cdb_req && inst_has_dep1 && cdb_rob_id == inst_dep1) begin
                            v1[empty_pos] <= cdb_val;
                            has_dep1[empty_pos] <= 0;
                        end else begin
                            v1[empty_pos] <= inst_val1;
                            has_dep1[empty_pos] <= inst_has_dep1;
                            dep1[empty_pos] <= inst_dep1;
                        end
                        if (cdb_req && inst_has_dep2 && cdb_rob_id == inst_dep2) begin
                            v2[empty_pos] <= cdb_val;
                            has_dep2[empty_pos] <= 0;
                        end else begin
                            v2[empty_pos] <= inst_val2;
                            has_dep2[empty_pos] <= inst_has_dep2;
                            dep2[empty_pos] <= inst_dep2;
                        end
                    end
                    `ADDI, `SLTI, `SLTIU, `XORI, `ORI, `ANDI, `SLLI, `SRLI, `SRAI, `JALR: begin
                        case (inst_type)
                            `ADDI: type[empty_pos]<= `ADD;
                            `SLTI: type[empty_pos]<= `SLT;
                            `SLTIU: type[empty_pos]<= `SLTU;
                            `XORI: type[empty_pos]<= `XOR;
                            `ORI:  type[empty_pos]<= `OR;
                            `ANDI: type[empty_pos]<= `AND;
                            `SLLI: type[empty_pos]<= `SLL;
                            `SRLI: type[empty_pos]<= `SRL;
                            `SRAI: type[empty_pos]<= `SRA;
                            `JALR: type[empty_pos]<= `JALR;
                        endcase
                        if (cdb_req && inst_has_dep1 && cdb_rob_id == inst_dep1) begin
                            v1[empty_pos] <= cdb_val;
                            has_dep1[empty_pos] <= 0;
                        end else begin
                            v1[empty_pos] <= inst_val1;
                            has_dep1[empty_pos] <= inst_has_dep1;
                            dep1[empty_pos] <= inst_dep1;
                        end
                        v2[empty_pos] <= inst_imm;
                        has_dep2[empty_pos] <= 0;
                    end
                endcase
            end
            // udpate the dep and value
            if (cdb_req) begin
                for (i = 0; i < `RS_CAP; i = i + 1) begin
                    if (busy[i]) begin
                        if (has_dep1[i] && cdb_rob_id == dep1[i]) begin
                            has_dep1[i] <= 0;
                            v1[i] <= cdb_val;
                        end
                        if (has_dep2[i] && cdb_rob_id == dep2[i]) begin
                            has_dep2[i] <= 0;
                            v2[i] <= cdb_val;
                        end
                    end
                end
            end
            
            // execute an instruction
            if (has_exec[1]) begin
                busy[exec_pos] <= 0;
            end
            full <= next_full;
            size <= next_size;
        end
    end
endmodule
`endif