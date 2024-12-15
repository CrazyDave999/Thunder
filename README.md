# Thunder

This is RISCV32IC CPU implementation, a major project for the Computer System course in ACM2023 class.

## Architecture

Thunder is a RISCV32IC CPU implemneted by Tomasulo algorithm. Its architecture diagram is shown below.

![Architecture Diagram](/assets/arch.svg)

## C extension support

Thunder supports short instructions with RISCV C extension convention. The basic concept is still fetch $4$ bytes each time, but check the lower $2$ bytes to see whether they form a short instruction. Then convert the C instructions to corresponding I instructions. Also the PC is changed accordingly.

## ICache

Thunder contains a simple instruction cache for accelerating instruction fetch operation.

![ICache](/assets/icache.svg)

Commonly there should be $2^5 = 32$ bytes in one block of ICache since we set `offset = addr[4:0]`. However, to cope with the instruction misalignment problem(i.e. the case when addr point to offset $30$ in some block and it is a $4$-byte instruction), we add $2$ extra bytes in each block. Hence the actual block size is $2^5+2=34$ bytes.

## Predictor

In ins_unit we implemented a simple Tournament Predictor, which consists of $3$ major parts:

- Global Predictors
- Local Predictors
- Selector

Prediction result can be fetched immediately, no need to wait. And predictor inner state changes happen when branch instructions commit.

## IO management

Generally we just treat all IO-load instructions as store instructions (i.e. only actually perform load operations when the IO-load instruction becomes the head of ROB). This can avoid dependency problem, which caused by mistakenly performing IO-load when mispredition happens.

There is an alternative way. Since the correctness of IO-load only depend on the last branch instrution, we can allow the IO-load instructions to be executed as long as all previous branch instructions are commited. However, our LSB implementation is out-of-order, which means when a store instruction commit, some previous completed load instructions might be canceled. Hence I think it is unsafe to allow the IO-load instructions to be performed in advance. 

