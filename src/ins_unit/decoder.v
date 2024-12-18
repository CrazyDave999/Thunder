`ifndef DECODER_V
`define DECODER_V
`include "const.v"
module Decoder (
    input wire clk_in,  // clock signal
    input wire rst_in,  // reset signal when high
    input wire rdy_in,  // ready signal, pause cpu when low    

    // from instruction unit
    input wire [31:0] inst,

    output reg [`TYPE_BIT-1:0] type_out,
    output reg [4:0] rs1_out,
    output reg [4:0] rs2_out,
    output reg [4:0] rd_out,
    output reg [31:0] imm_out
);
  wire [6:0] opcode = inst[6:0];
  wire [2:0] funct3 = inst[14:12];
  wire [7:0] funct7 = inst[31:25];

  wire [4:0] rd = inst[11:7];
  wire [4:0] rs1 = inst[19:15];
  wire [4:0] rs2 = inst[24:20];
  wire [31:0] immU = {inst[31:12], 12'b0};
  wire [31:0] immJ = $signed({inst[31], inst[19:12], inst[20], inst[30:21], 1'b0});
  wire [31:0] immI = $signed(inst[31:20]);
  wire [31:0] immB = $signed({inst[31], inst[7], inst[30:25], inst[11:8], 1'b0});
  wire [31:0] immS = $signed({inst[31:25], inst[11:7]});
  wire [31:0] shamt = $unsigned(inst[24:20]);

  /*
    C extension
    `c.addi`，`c.jal`，`c.li`，`c.addi16sp`，`c.lui`，`c.srli`，`c.srai`，
    `c.andi`，`c.sub`，`c.xor`，`c.or`，`c.and`，`c.j`，`c.beqz`，`c.bnez`，
    `c.addi4spn`，`c.lw`，`c.sw`，`c.slli`，`c.jr`，`c.mv`，`c.jalr`，`c.add`，
    `c.lwsp`，`c.swsp`
  */
  wire [1:0] c_opcode = inst[1:0];
  wire [2:0] c_funct3 = inst[15:13];
  wire [3:0] c_funct4 = inst[15:12];

  wire [4:0] rs1_ = $unsigned(inst[9:7]) + 8; // i.e. rs1'+8/rd'+8
  wire [4:0] rs2_ = $unsigned(inst[4:2]) + 8; // i.e. rs2'+8

  // for c.addi, c.li, c.andi
  wire [31:0] immCI = $signed({inst[12], inst[6:2]});
  // for c.srli, c.srai, c.slli
  wire [31:0] uimmCI = $unsigned({inst[12], inst[6:2]});
  // for c.addi16sp
  wire [31:0] imm_c_addi16sp = $signed({inst[12], inst[4:3], inst[5], inst[2], inst[6], 4'b0});
  // for c.addi4spn
  wire [31:0] imm_c_addi4spn = $unsigned({inst[10:7], inst[12:11], inst[5], inst[6], 2'b0});
  // for c.lui
  wire [31:0] imm_c_lui = $signed({inst[12], inst[6:2], 12'b0});
  // for c.jal, c.j
  wire [31:0] immCJ = $signed(
      {inst[12], inst[8], inst[10:9], inst[6], inst[7], inst[2], inst[11], inst[5:3], 1'b0}
  );
  // for c.beqz, c.bnez
  wire [31:0] immCB = $signed({inst[12], inst[6:5], inst[2], inst[11:10], inst[4:3], 1'b0});
  // for c.lw, c.sw
  wire [31:0] immCL = $unsigned({inst[5], inst[12:10], inst[6], 2'b0});
  // for c.lwsp
  wire [31:0] imm_c_lwsp = $unsigned({inst[3:2], inst[12], inst[6:4], 2'b0});
  // for c.swsp
  wire [31:0] imm_c_swsp = $unsigned({inst[8:7], inst[12:9], 2'b0});

  wire is_c_addi = c_funct3 == 3'b000 && immCI != 0 && rd != 0 && c_opcode == 2'b01;
  wire is_c_jal = c_funct3 == 3'b001 && c_opcode == 2'b01;
  wire is_c_li = c_funct3 == 3'b010 && rd != 0 && c_opcode == 2'b01;
  wire is_c_addi16sp = c_funct3 == 3'b011 && imm_c_addi16sp != 0 && rd == 2 && c_opcode == 2'b01;
  wire is_c_lui = c_funct3 == 3'b011 && imm_c_lui != 0 && rd != 0 && rd != 2 && c_opcode == 2'b01;
  wire is_c_srli = c_funct3 == 3'b100 && uimmCI != 0 && inst[11:10] == 2'b00 && c_opcode == 2'b01;
  wire is_c_srai = c_funct3 == 3'b100 && uimmCI != 0 && inst[11:10] == 2'b01 && c_opcode == 2'b01;
  wire is_c_andi = c_funct3 == 3'b100 && inst[11:10] == 2'b10 && c_opcode == 2'b01;
  wire is_c_sub = c_funct4 == 4'b1000 && inst[11:10] == 2'b11 && inst[6:5] == 2'b00 && c_opcode == 2'b01;
  wire is_c_xor = c_funct4 == 4'b1000 && inst[11:10] == 2'b11 && inst[6:5] == 2'b01 && c_opcode == 2'b01;
  wire is_c_or = c_funct4 == 4'b1000 && inst[11:10] == 2'b11 && inst[6:5] == 2'b10 && c_opcode == 2'b01;
  wire is_c_and = c_funct4 == 4'b1000 && inst[11:10] == 2'b11 && inst[6:5] == 2'b11 && c_opcode == 2'b01;
  wire is_c_j = c_funct3 == 3'b101 && c_opcode == 2'b01;
  wire is_c_beqz = c_funct3 == 3'b110 && c_opcode == 2'b01;
  wire is_c_bnez = c_funct3 == 3'b111 && c_opcode == 2'b01;
  wire is_c_addi4spn = c_funct3 == 3'b000 && imm_c_addi4spn != 0 && c_opcode == 2'b00;
  wire is_c_lw = c_funct3 == 3'b010 && c_opcode == 2'b00;
  wire is_c_sw = c_funct3 == 3'b110 && c_opcode == 2'b00;
  wire is_c_slli = c_funct3 == 3'b000 && uimmCI != 0 && rd != 0 && c_opcode == 2'b10;
  wire is_c_lwsp = c_funct3 == 3'b010 && rd != 0 && c_opcode == 2'b10;
  wire is_c_jr = c_funct4 == 4'b1000 && inst[12] == 0 && rd != 0 && inst[6:2] == 0 && c_opcode == 2'b10; // for c.jr, rd means rs1
  wire is_c_mv = c_funct4 == 4'b1000 && inst[12] == 0 && rd != 0 && inst[6:2] != 0 && c_opcode == 2'b10;
  wire is_c_jalr = c_funct4 == 4'b1001 && rd != 0 && inst[6:2] == 0 && c_opcode == 2'b10; // for c.jalr, rd means rs1
  wire is_c_add = c_funct4 == 4'b1001 && rd != 0 && inst[6:2] != 0 && c_opcode == 2'b10;
  wire is_c_swsp = c_funct3 == 3'b110 && c_opcode == 2'b10;

  wire is_c_inst = !(inst[1:0] == 2'b11);

  always @(posedge clk_in) begin
    if (rst_in) begin
      type_out <= 0;
      rs1_out <= 0;
      rs2_out <= 0;
      rd_out <= 0;
      imm_out <= 0;
    end else if (!rdy_in) begin
      // do nothing
    end else begin
      if (is_c_inst) begin
        if (is_c_addi) begin
          type_out <= `ADDI;
          imm_out  <= immCI;
          rs1_out  <= rd;
          rd_out   <= rd;
        end else if (is_c_jal) begin
          type_out <= `JAL;
          imm_out  <= immCJ;
          rd_out   <= 1;
        end else if (is_c_li) begin
          type_out <= `ADDI;
          imm_out  <= immCI;
          rs1_out  <= 0;
          rd_out   <= rd;
        end else if (is_c_addi16sp) begin
          type_out <= `ADDI;
          imm_out  <= imm_c_addi16sp;
          rs1_out  <= 2;
          rd_out   <= 2;
        end else if (is_c_lui) begin
          type_out <= `LUI;
          imm_out  <= imm_c_lui;
          rd_out   <= rd;
        end else if (is_c_srli) begin
          type_out <= `SRLI;
          imm_out  <= uimmCI;
          rs1_out  <= rs1_;
          rd_out   <= rs1_;
        end else if (is_c_srai) begin
          type_out <= `SRAI;
          imm_out  <= uimmCI;
          rs1_out  <= rs1_;
          rd_out   <= rs1_;
        end else if (is_c_andi) begin
          type_out <= `ANDI;
          imm_out  <= immCI;
          rs1_out  <= rs1_;
          rd_out   <= rs1_;
        end else if (is_c_sub) begin
          type_out <= `SUB;
          rs1_out  <= rs1_;
          rs2_out  <= rs2_;
          rd_out   <= rs1_;
        end else if (is_c_xor) begin
          type_out <= `XOR;
          rs1_out  <= rs1_;
          rs2_out  <= rs2_;
          rd_out   <= rs1_;          
        end else if (is_c_or) begin
          type_out <= `OR;
          rs1_out  <= rs1_;
          rs2_out  <= rs2_;
          rd_out   <= rs1_;
        end else if (is_c_and) begin
          type_out <= `AND;
          rs1_out  <= rs1_;
          rs2_out  <= rs2_;
          rd_out   <= rs1_;          
        end else if (is_c_j) begin
          type_out <= `JAL;
          imm_out  <= immCJ;
          rd_out   <= 0;
        end else if (is_c_beqz) begin
          type_out <= `BEQ;
          imm_out  <= immCB;
          rs1_out  <= rs1_;
          rs2_out  <= 0;
          rd_out   <= 0;
        end else if (is_c_bnez) begin
          type_out <= `BNE;
          imm_out  <= immCB;
          rs1_out  <= rs1_;
          rs2_out  <= 0;
          rd_out   <= 0;
        end else if (is_c_addi4spn) begin
          type_out <= `ADDI;
          imm_out  <= imm_c_addi4spn;
          rs1_out  <= 2;
          rd_out   <= rs2_;
        end else if (is_c_lw) begin
          type_out <= `LW;
          imm_out  <= immCL;
          rs1_out <= rs1_;
          rd_out  <= rs2_;
        end else if (is_c_sw) begin
          type_out <= `SW;
          imm_out  <= immCL;
          rs1_out <= rs1_;
          rs2_out <= rs2_;
          rd_out  <= 0;
        end else if (is_c_slli) begin
          type_out <= `SLLI;
          imm_out  <= uimmCI;
          rs1_out  <= rd;
          rd_out   <= rd;
        end else if (is_c_lwsp) begin
          type_out <= `LW;
          imm_out  <= imm_c_lwsp;
          rs1_out <= 2;
          rd_out  <= rd;
        end else if (is_c_jr) begin
          type_out <= `JALR;
          imm_out  <= 0;
          rs1_out <= rd;
          rd_out  <= 0;
        end else if (is_c_mv) begin
          type_out <= `ADD;
          rs1_out <= 0;
          rs2_out <= inst[6:2];
          rd_out  <= rd;
        end else if (is_c_jalr) begin
          type_out <= `JALR;
          imm_out  <= 0;
          rs1_out <= rd;
          rd_out  <= 1;
        end else if (is_c_add) begin
          type_out <= `ADD;
          rs1_out <= rd;
          rs2_out <= inst[6:2];
          rd_out  <= rd;
        end else if (is_c_swsp) begin
          type_out <= `SW;
          imm_out  <= imm_c_swsp;
          rs1_out <= 2;
          rs2_out <= inst[6:2];
          rd_out  <= 0;
        end
      end else begin
        rs1_out <= rs1;
        rs2_out <= rs2;
        case (opcode)
          7'b0110111: begin
            type_out <= `LUI;
            imm_out  <= immU;
            rd_out   <= rd;
          end
          7'b0010111: begin
            type_out <= `AUIPC;
            imm_out  <= immU;
            rd_out   <= rd;
          end
          7'b1101111: begin
            type_out <= `JAL;
            imm_out  <= immJ;
            rd_out   <= rd;
          end
          7'b1100111: begin
            type_out <= `JALR;
            imm_out  <= immI;
            rd_out   <= rd;
          end
          7'b1100011: begin
            case (funct3)
              3'b000: begin
                type_out <= `BEQ;
                imm_out  <= immB;
                rd_out   <= 0;
              end
              3'b001: begin
                type_out <= `BNE;
                imm_out  <= immB;
                rd_out   <= 0;
              end
              3'b100: begin
                type_out <= `BLT;
                imm_out  <= immB;
                rd_out   <= 0;
              end
              3'b101: begin
                type_out <= `BGE;
                imm_out  <= immB;
                rd_out   <= 0;
              end
              3'b110: begin
                type_out <= `BLTU;
                imm_out  <= immB;
                rd_out   <= 0;
              end
              3'b111: begin
                type_out <= `BGEU;
                imm_out  <= immB;
                rd_out   <= 0;
              end
            endcase
          end
          7'b0000011: begin
            case (funct3)
              3'b000: begin
                type_out <= `LB;
                imm_out  <= immI;
                rd_out   <= rd;
              end
              3'b001: begin
                type_out <= `LH;
                imm_out  <= immI;
                rd_out   <= rd;
              end
              3'b010: begin
                type_out <= `LW;
                imm_out  <= immI;
                rd_out   <= rd;
              end
              3'b100: begin
                type_out <= `LBU;
                imm_out  <= immI;
                rd_out   <= rd;
              end
              3'b101: begin
                type_out <= `LHU;
                imm_out  <= immI;
                rd_out   <= rd;
              end
            endcase
          end
          7'b0100011: begin
            case (funct3)
              3'b000: begin
                type_out <= `SB;
                imm_out  <= immS;
                rd_out   <= 0;
              end
              3'b001: begin
                type_out <= `SH;
                imm_out  <= immS;
                rd_out   <= 0;
              end
              3'b010: begin
                type_out <= `SW;
                imm_out  <= immS;
                rd_out   <= 0;
              end
            endcase
          end
          7'b0010011: begin
            case (funct3)
              3'b000: begin
                type_out <= `ADDI;
                imm_out  <= immI;
                rd_out   <= rd;
              end
              3'b010: begin
                type_out <= `SLTI;
                imm_out  <= immI;
                rd_out   <= rd;
              end
              3'b011: begin
                type_out <= `SLTIU;
                imm_out  <= immI;
                rd_out   <= rd;
              end
              3'b100: begin
                type_out <= `XORI;
                imm_out  <= immI;
                rd_out   <= rd;
              end
              3'b110: begin
                type_out <= `ORI;
                imm_out  <= immI;
                rd_out   <= rd;
              end
              3'b111: begin
                type_out <= `ANDI;
                imm_out  <= immI;
                rd_out   <= rd;
              end
              3'b001: begin
                type_out <= `SLLI;
                imm_out  <= shamt;
                rd_out   <= rd;
              end
              3'b101: begin
                case (funct7)
                  7'b0000000: begin
                    type_out <= `SRLI;
                    imm_out  <= shamt;
                    rd_out   <= rd;
                  end
                  7'b0100000: begin
                    type_out <= `SRAI;
                    imm_out  <= shamt;
                    rd_out   <= rd;
                  end
                endcase
              end
            endcase
          end
          7'b0110011: begin
            case (funct3)
              3'b000: begin
                case (funct7)
                  7'b0000000: begin
                    type_out <= `ADD;
                    rd_out   <= rd;
                  end
                  7'b0100000: begin
                    type_out <= `SUB;
                    rd_out   <= rd;
                  end
                endcase
              end
              3'b001: begin
                type_out <= `SLL;
                rd_out   <= rd;
              end
              3'b010: begin
                type_out <= `SLT;
                rd_out   <= rd;
              end
              3'b011: begin
                type_out <= `SLTU;
                rd_out   <= rd;
              end
              3'b100: begin
                type_out <= `XOR;
                rd_out   <= rd;
              end
              3'b101: begin
                case (funct7)
                  7'b0000000: begin
                    type_out <= `SRL;
                    rd_out   <= rd;
                  end
                  7'b0100000: begin
                    type_out <= `SRA;
                    rd_out   <= rd;
                  end
                endcase
              end
              3'b110: begin
                type_out <= `OR;
                rd_out   <= rd;
              end
              3'b111: begin
                type_out <= `AND;
                rd_out   <= rd;
              end
            endcase
          end
        endcase
      end
    end
  end
endmodule
`endif
