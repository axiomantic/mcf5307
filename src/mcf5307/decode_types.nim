## Shared types for the mcf5307 instruction-group modules.
##
## THIS MODULE IS THE BOTTOM OF THE CORE, above `ea` alone. It holds the
## types that the decoder (`decode.nim`) and every instruction-group executor
## (`move.nim`, and later `alu.nim`, `logic.nim`, `control.nim`) both need.
## Those modules are siblings and neither imports the other; each one reads
## its types from here. `cpu.nim` sits above them and owns `step`.
##
## CPU-7 created this file. There was a module cycle before it: `decode.nim`
## held `step`, so it needed the executor entry points, and the executors
## needed the types `decode.nim` defined. Moving the shared types here broke
## the cycle, and moving `step` up into `cpu.nim` removed the
## decoder-to-executor edge that made the cycle possible.
##
## The effective-address legality table lives here for the same reason. The
## executor modules ask whether an operand is legal before they run an
## instruction. The table reads an `Operation` and an `EA` and it reads no
## decoder state, so it belongs beside the types and not beside the decoder.
##
## NO MODULE RE-EXPORTS THIS ONE. A caller that needs `Operation`, `Decoded`,
## `MCF5307Ctx`, the board callback types or `eaIsLegalFor` imports
## `mcf5307/decode_types` by name. `decode.nim` re-exported it for a time,
## which hid which layer each name came from.

import mcf5307/ea

type
  Operation* {.pure.} = enum
    opNop
    opMove, opMovea, opMoveq, opMovem
    opLea, opPea
    opLink, opUnlk
    opAddq, opSubq
    opAdd, opSub, opAdda, opSuba
    opAddi, opSubi
    opClr, opExt, opNeg
    opMulu, opMuls, opDivu, opDivs
    opAnd, opOr, opExg
    opNot, opSwap, opTst
    opBtst, opBchg, opBclr, opBset
    opTas, opNbcd
    opScc
    opBcc, opBra
    # CPU-8 appends here, IMMEDIATELY BEFORE `opIllegal` and nowhere else.
    # `opNop` must stay at ordinal 0, because a zero-initialised `Decoded`
    # reads as `opNop`, and `opIllegal` must stay last. Appending here moves
    # no ordinal that anything depends on.
    opAddx, opSubx, opNegx, opExtb
    # CPU-9 appends here, under the same rule CPU-8 followed: immediately
    # before `opIllegal` and nowhere else. `opAnd`, `opOr`, `opNot` and the
    # four bit operations were already named above; these are the members the
    # logic group needed that no earlier task had a use for.
    opEor, opAndi, opOri, opEori
    opAsl, opAsr, opLsl, opLsr
    opIllegal

  Decoded* = ref object
    op*: Operation
    ea*: EA
    size*: uint8
    destReg*: uint8
    destMode*: uint8
    memDir*: bool
    dirToEa*: bool   ## ADD/SUB direction: false is `<ea> op Dn -> Dn`,
                     ## true is `Dn op <ea> -> <ea>`.
    imm*: uint8      ## the quick immediate of ADDQ and SUBQ, and the shift
                     ## count of an immediate-count shift, already resolved:
                     ## the encoded data field 000 means eight in both.
    regOperand*: bool
                     ## the instruction's SECOND operand lives in the data
                     ## register `destReg` rather than in the instruction
                     ## stream. It is the i/r bit of a shift (a count in Dn
                     ## rather than in the opcode word) and bit 8 of a bit
                     ## operation (the dynamic form, whose bit number is in
                     ## Dn, rather than the static form, whose bit number is
                     ## the extension word). ONE FIELD AND NOT TWO: the two
                     ## encodings ask the same question, and a second flag
                     ## would let a decoder set one and an executor read the
                     ## other.

  # ---------------------------------------------------------------------------
  # The bus-status values and the board callbacks, matching `include/mcf5307.h`
  # exactly. `Mcf5307BusStatus` has the width of a C `int` so that the
  # out-parameter the board writes has the ABI the header declares.

  Mcf5307BusStatus* {.size: sizeof(cint), pure.} = enum
    busOk          = 0  ## the access completed
    busUnmapped    = 1  ## no device answers at this address
    busSizeIllegal = 2  ## the width is not one the device accepts
    busFault       = 3  ## the device answers and reports a fault of its own

  Mcf5307ReadFn* = proc(user: pointer; address: uint32; size: cint;
                        status: ptr Mcf5307BusStatus): uint32 {.cdecl.}
  Mcf5307WriteFn* = proc(user: pointer; address: uint32; size: cint;
                         value: uint32; status: ptr Mcf5307BusStatus) {.cdecl.}
  Mcf5307IackFn* = proc(user: pointer; level: cint; vector: uint8) {.cdecl.}

  MCF5307Ctx* = ref object
    user*: pointer
    readFn*: Mcf5307ReadFn 
    writeFn*: Mcf5307WriteFn 
    iackFn*: Mcf5307IackFn 
    pc*: uint32
    sp*: uint32
    sr*: uint32
    dRegs*: array[8, uint32]
    aRegs*: array[7, uint32]
    halted*: bool
    fault*: bool

# ---------------------------------------------------------------------------
# The effective-address legality table.

const eaMemoryAlterable* = EaLegality(modes: eaMemAlterableModes,
                                      ea7: eaMemAlterable7)
  ## The destination mask of the `Dn op <ea> -> <ea>` direction of ADD and
  ## SUB. It is not reachable through `eaLegalityFor`, because that table is
  ## keyed on the operation alone and this direction is a property of the
  ## instruction WORD, not of the operation. `alu.nim` names it directly.

const eaDataAddressing* = EaLegality(modes: eaDataAlterableModes,
                                     ea7: eaData7)
  ## THE MANUAL'S `DATA` CLASS, WHICH DOES NOT INCLUDE `An`. The MCF5307
  ## User's Manual Table 3-5 marks every mode but address-register direct as
  ## DATA, and `m68k-elf-as -mcpu=5307` agrees: it rejects `and.l %a0,%d1` and
  ## accepts every other source this mask names, `(4,%pc)` and `#imm`
  ## included.
  ##
  ## IT IS NOT `eaDataModes`. That constant in `ea.nim` is the wider "every
  ## addressing mode" set, which is what a MOVE source needs and what this
  ## class is not; CPU-9 left it alone rather than narrow a mask four earlier
  ## opcodes read.
  ##
  ## The MODE list is the same list `eaDataAlterableModes` holds, because on
  ## this part DATA and DATA ALTERABLE differ only in the mode-7 sub-variants
  ## - the PC-relative pair and the immediate, which are readable and not
  ## writable. The `ea7` set is what separates them and it is spelled out
  ## above.

const eaBitDynamic* = EaLegality(modes: eaDataAlterableModes,
                                 ea7: eaData7 - {ea7Imm})
  ## THE OPERAND OF A DYNAMIC BIT TEST: the manual's DATA class WITHOUT the
  ## immediate. It is `eaDataAddressing` minus one sub-variant, and the whole
  ## of the difference between them is this paragraph.
  ##
  ## THE MANUAL PUTS THE IMMEDIATE OUT. MCF5307 User's Manual Table 3-13,
  ## "Two Operand Instruction Execution Times", page 3-28: the row
  ## `btst | Dy,<ea>` reads `Rn 1(0/0)`, `(An) 4(1/0)`, `(An)+ 4(1/0)`,
  ## `-(An) 4(1/0)`, `(d16,An)/(d16,PC) 4(1/0)`,
  ## `(d8,An,Xi*SF)/(d8,PC,Xi*SF) 5(1/0)`, `xxx.wl 4(1/0)` and, in the last
  ## column, `#xxx` - A DASH.
  ##
  ## THE DASH IS THE TABLE'S MARK FOR A FORM THIS PART DOES NOT HAVE, and not
  ## a gap in the timing data. Two rows settle that on their own:
  ##
  ##   - Table 3-12, page 3-27, gives `tst.l <ea>` a `#xxx` of `1(0/0)`.
  ##     `tst.l #5` computes nothing a compiler could want, and the manual
  ##     times it anyway. A read-only operand does not lose its row for being
  ##     useless, so `btst Dy,<ea>`'s missing one is not that.
  ##
  ##   - Table 3-13 uses the dash for restrictions that are demonstrably real.
  ##     The `btst | #imm,<ea>` row dashes `(d8,An,Xi*SF)`, `xxx.wl` and
  ##     `#xxx` and keeps the other five, which is `eaBitStatic` mode for
  ##     mode; the `divs.l`, `divu.l`, `muls.l` and `mulu.l` rows dash the
  ##     same indexed, absolute and immediate columns; `and.l Dy,<ea>` dashes
  ##     `Rn`. Every one of those was offered to `m68k-elf-as -mcpu=5307` and
  ##     REJECTED, and `and.l Dy,<ea>` with `Rn` - the word `c380` -
  ##     disassembles as `.short 0xc380` on `-m m68k:5307`. Fifteen dashes
  ##     checked, fifteen illegal; and every column that carries a time
  ##     (`and.l <ea>,Rx` with `#xxx`, whose word `c0bc` DOES disassemble as
  ##     `andl`) is accepted.
  ##
  ## THE ASSEMBLER IS THE ONE SOURCE THAT DISAGREES, AND IT IS NOT SPEAKING
  ## ABOUT THIS PART. `m68k-elf-as -mcpu=5307` assembles `btst %d1,#5` to
  ## `033c 0005`. Measured on the same binutils: that form is accepted
  ## IDENTICALLY under `-m68000` and under `-mcpu=5307`, while
  ## `btst #3,0x12345678` is accepted under `-m68000` and REJECTED under
  ## `-mcpu=5307`. The ColdFire tables were narrowed for the static form and
  ## left alone for this one, so the acceptance carries the 68000 rule
  ## forward rather than asserting anything about a 5307. The 68000 does
  ## permit it - BTST is that architecture's one bit operation that reads an
  ## immediate - which is exactly the rule an untouched entry would keep.
  ##
  ## `bset %d1,#5`, `bclr %d1,#5` and `bchg %d1,#5` are rejected under BOTH,
  ## so that rejection distinguishes nothing either.
  ##
  ## WHAT WOULD OVERTURN THIS is the ColdFire Family Programmer's Reference
  ## Manual, whose per-instruction operand table names the modes directly. It
  ## is not on this machine (AGENTS.md section 11) and the network is closed.
  ## Uncertainty 4 in the `logic.nim` header is this one.
  ##
  ## IT IS A CONSTANT OF ITS OWN AND NOT A NARROWED `eaDataAddressing`,
  ## because AND and OR keep the immediate: Table 3-13's `and.l <ea>,Rx` and
  ## `or.l <ea>,Rx` rows both give `#xxx` a time of `1(0/0)`.

const eaBitStatic* = EaLegality(
  modes: {eaDn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp}, ea7: {})
  ## THE OPERAND OF A STATIC BIT OPERATION, WHICH IS NARROWER THAN THE
  ## DYNAMIC ONE. `0000 1000 tt <ea>` takes a data register or one of four
  ## address-register indirect modes and NOTHING ELSE on this part.
  ##
  ## THE MANUAL PRINTS THIS MASK, MODE FOR MODE. MCF5307 User's Manual
  ## Table 3-13, "Two Operand Instruction Execution Times", page 3-28. Four
  ## rows read `#imm,<ea>` in the `<EA>` column - `bchg`, `bclr`, `bset` and
  ## `btst` - and all four carry a time under exactly five columns and a dash
  ## under the rest:
  ##
  ##            Rn      (An)    (An)+   -(An)   (d16,An) (d8,An,Xi*SF) xxx.wl #xxx
  ##   bchg   2(0/0)  5(1/1)  5(1/1)  5(1/1)  5(1/1)         -            -     -
  ##   bclr   2(0/0)  5(1/1)  5(1/1)  5(1/1)  5(1/1)         -            -     -
  ##   bset   2(0/0)  5(1/1)  5(1/1)  5(1/1)  5(1/1)         -            -     -
  ##   btst   1(0/0)  4(1/0)  4(1/0)  4(1/0)  4(1/0)         -            -     -
  ##
  ## The five timed columns are `{eaDn, eaAnInd, eaAnPost, eaAnPre,
  ## eaAnDisp}`, which is this constant. The `Dy,<ea>` rows of the same four
  ## operations, two lines above each of these, DO carry times under
  ## `(d8,An,Xi*SF)` and `xxx.wl` - so the dashes separate the static form
  ## from the dynamic one and are not a property of the bit operations as a
  ## family.
  ##
  ## AN EARLIER REVISION SAID THE MANUAL'S TABLE DOES NOT SHOW THESE
  ## RESTRICTIONS AND THAT ONLY BINUTILS ENFORCED THEM. It shows every one of
  ## them, in the rows printed above. The assembler measurement stands as
  ## CORROBORATION and no longer as the authority: `m68k-elf-as -mcpu=5307`
  ## rejects `btst #3,(4,%a0,%d2)`, `btst #3,0x12345678`, `btst #3,0x1234.w`
  ## and `btst #3,(4,%pc)`, and `m68k-elf-objdump -m m68k:5307` decodes none
  ## of `0830`, `0838`, `0839`, `083a`, `08f8` or `08f9` as an instruction.
  ##
  ## The DYNAMIC form is wider in the two columns above and in the
  ## PC-relative pair folded into the `(d16,An)` and `(d8,An,Xi*SF)` headings:
  ## `btst %d1,0x12345678` and `btst %d1,(4,%pc)` both assemble. It reads
  ## `eaBitDynamic` (for BTST) or the data-alterable mask (for BCHG, BCLR and
  ## BSET) through `eaLegalityFor` instead. It is NOT wider in the `#xxx`
  ## column - see `eaBitDynamic`.
  ##
  ## IT IS A CONSTANT AND NOT A TABLE ENTRY for the reason `eaMemoryAlterable`
  ## gives above: static and dynamic are the same four operations and the
  ## table is keyed on the operation alone.

proc eaLegalityFor*(op: Operation): EaLegality =
  ## The legality mask the opcode carries. An opcode with no effective
  ## address carries the empty mask.
  case op
  of opMove, opMovea:
    # These take data addressing, which admits every mode including the
    # mode-7 sub-variants. The reserved and invalid mode-7 encodings stay
    # out of the mask, so they trap.
    EaLegality(modes: eaDataModes, ea7: eaData7)
  of opAdd, opSub, opAdda, opSuba:
    # The `<ea>` operand of the register direction, and the source of ADDA
    # and SUBA: data addressing, PC-relative and immediate included.
    EaLegality(modes: eaDataModes, ea7: eaData7)
  of opAddq, opSubq:
    # ALTERABLE, WHICH IS NARROWER THAN THE DATA ADDRESSING THIS ENTRY USED
    # TO NAME. An ADDQ destination is written, so it cannot be PC-relative
    # and it cannot be an immediate; `m68k-elf-as -mcpu=5307` rejects
    # `addq.l #1,(4,%pc)`. An address register IS allowed, which is why this
    # is `alterable` and not `data alterable`.
    EaLegality(modes: eaAlterableModes, ea7: eaAlterable7)
  of opClr, opMulu, opMuls, opDivu, opDivs:
    # Data alterable: no An, no PC-relative, no immediate.
    EaLegality(modes: eaDataAlterableModes, ea7: eaDataAlterable7)
  of opAnd, opOr:
    # THE SOURCE OF THE `<ea> op Dn -> Dn` DIRECTION of AND and OR. It reads
    # and does not write, so the class is DATA addressing: no An, and the
    # PC-relative pair and the immediate are in. MCF5307 User's Manual
    # Table 3-13, page 3-28: the `and.l <ea>,Rx` and `or.l <ea>,Rx` rows both
    # give `#xxx` a time of `1(0/0)`, and `c0bc 0000 0005` disassembles as
    # `andl #5,%d0` on `m68k-elf-objdump -m m68k:5307`.
    #
    # The OTHER direction of AND and OR writes memory and carries
    # `eaMemoryAlterable`, which this table cannot hold because the direction
    # is a property of the instruction word. `logic.nim` names it directly,
    # exactly as `alu.nim` does for ADD and SUB.
    eaDataAddressing
  of opBtst:
    # A DYNAMIC BTST READS AND DOES NOT WRITE, SO ITS CLASS IS ALSO A READING
    # ONE - BUT IT STOPS SHORT OF THE IMMEDIATE. The manual rows and the
    # toolchain measurements behind that difference are on `eaBitDynamic`.
    eaBitDynamic
  of opEor, opBchg, opBclr, opBset:
    # EOR HAS ONE DIRECTION on this part - `Dn ^ <ea> -> <ea>` - and the three
    # bit operations that WRITE their operand share its class: data alterable.
    # A data register is in, an address register is not, and neither is a
    # PC-relative operand or an immediate. Measured: `m68k-elf-as -mcpu=5307`
    # rejects `eor.l (%a0),%d1` (there is no other direction to decode),
    # `bset #3,%a0` and `bset #3,(4,%pc)`, and objdump decodes neither `b3bc`
    # nor `03fa`.
    EaLegality(modes: eaDataAlterableModes, ea7: eaDataAlterable7)
  of opNot, opAndi, opOri, opEori, opAsl, opAsr, opLsl, opLsr:
    # A DATA REGISTER AND NOTHING ELSE, AND THE MANUAL'S TIMING TABLES SAY SO
    # ROW BY ROW. All eight rows carry `Dx` or `#imm,Dx` in the `<EA>` column,
    # a time under `Rn`, and a DASH under every memory column:
    #
    #   - MCF5307 User's Manual Table 3-12, page 3-27: `not.l | Dx |
    #     Rn 1(0/0)` and a dash under `(An)`, `(An)+`, `-(An)`, `(d16,An)`,
    #     `(d8,An,Xi*SF)`, `xxx.wl` and `#xxx`. The `clr.l` row above it and
    #     the `tst.l` row below it carry times in those columns, so the
    #     dashes belong to this row.
    #   - Table 3-13, page 3-28: `andi.l | #imm,Dx`, `ori.l | #imm,Dx` and
    #     `eori.l | #imm,Dx` each read `1(0/0)` under `Rn` and a dash
    #     everywhere else, `#xxx` included.
    #   - Table 3-13 again: `asl.l`, `asr.l`, `lsl.l` and `lsr.l` all read
    #     `<ea>,Dx` with `1(0/0)` under `Rn` AND under `#xxx` - the immediate
    #     COUNT - and a dash under all six memory columns.
    #
    # `m68k-elf-as -mcpu=5307` corroborates every one: it rejects
    # `andi.l #5,(%a0)`, `ori.l #5,(%a0)`, `eori.l #5,(%a0)`, `not.l (%a0)`
    # and `lsr.l (%a0)`.
    #
    # TWO OBJDUMP CITATIONS WERE REMOVED FROM THIS COMMENT AND NEITHER IS
    # MISSED. `4690` DOES decode on `-m m68k:5307`, as `notl %d0` - a laxity
    # of the disassembler, since the word's low six bits are mode 010 and
    # `-m m68k:68000` prints `notl %a0@`. `e0c0` decodes on NEITHER
    # architecture, because its low six bits are a data register and so it is
    # not a well-formed memory shift anywhere; the memory-shift witness that
    # does work is `e2d0`, `lsrw %a0@` on 68000 and `.short` on 5307. See
    # `logic.nim`'s header. The memory shift's negative case is CPU-13's;
    # this mask is the mechanism it asserts through.
    EaLegality(modes: {eaDn}, ea7: {})
  of opAddi, opSubi, opNeg, opNegx, opExt, opExtb, opAddx, opSubx:
    # A DATA REGISTER AND NOTHING ELSE on this part. The 68000 forms that
    # reach memory (`addi.l #7,(%a0)`, `neg.l (%a0)`) and the memory form of
    # ADDX are all rejected by `m68k-elf-as -mcpu=5307`.
    EaLegality(modes: {eaDn}, ea7: {})
  of opLea, opMovem, opPea:
    # These take control addressing only: (An), (d16,An), (d8,An,Xn),
    # (xxx).L, (d16,PC), (d8,PC,Xn). A data register direct (mode 0), an
    # immediate (mode 7, sub 4), a postincrement or a predecrement are
    # illegal and must trap. `MOVEM -(An)` is the CPU-13 negative case.
    EaLegality(modes: eaControlModes, ea7: eaControl7)
  else:
    EaLegality(modes: {}, ea7: {})

proc eaIsLegalFor*(op: Operation; ea: EA): bool =
  ## True when `ea` is inside the opcode's legality mask. An opcode with no
  ## effective address carries the empty mask and no mode is inside it.
  ##
  ## THE EMPTY MASK IS THE TEST, and it used to be a second list of the
  ## operations `eaLegalityFor` names. Two lists drift: an operation added to
  ## the table above and forgotten here would have had every effective
  ## address rejected, which reads as "the opcode is strict" and is really
  ## "the opcode is unreachable".
  let legality = eaLegalityFor(op)
  result = legality.modes != {} and isEaLegal(legality, ea)
