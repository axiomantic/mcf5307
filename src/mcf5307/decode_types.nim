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
    # CPU-10 appends here, under the same rule CPU-8 and CPU-9 followed:
    # immediately before `opIllegal` and nowhere else. `opNop`, `opScc`,
    # `opBcc`, `opBra` and `opTst` were already named above; these are the
    # members the control-flow and comparison group needed that no earlier
    # task had a use for. `opBsr` is one of them AND IT IS NOT `opBcc` WITH A
    # CONDITION OF 1: `0110 0001 dddddddd` pushes a return address, so an
    # executor that folded it into the conditional arm would branch and never
    # push.
    opBsr
    opJmp, opJsr, opRts, opRte, opTrap
    opCmp, opCmpa, opCmpi
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
  ## THE SECOND TABLE OF THE SAME MANUAL READS THE OTHER WAY, AND IT IS NAMED
  ## HERE so that the disagreement is checkable. MCF5307 User's Manual
  ## Table 3-5, "Effective Addressing Modes and Categories", page 3-21, marks
  ## Immediate `#<xxx>` with an `x` in the DATA column. A dynamic BTST READS
  ## its operand, so DATA is its class, and that column RESTORES the immediate
  ## Table 3-13 dashes. That reading, and not the assembler, is what a future
  ## reader would reverse this constant on.
  ##
  ## CUTTING THE OTHER WAY, Table 3-7 on page 3-23 gives BTST's operand syntax
  ## as `Dy,<ea>x`. The `x` suffix is the manual's DESTINATION mark - `CLR`
  ## reads `<ea>x` with the operation "0 -> Destination", and `CMP` reads
  ## `<ea>y,Dx` with "Destination - Source" - and an immediate is not a
  ## destination. The manual is loose here, because BTST writes nothing, but
  ## the notation it chose is the destination one.
  ##
  ## WHAT WOULD OVERTURN THIS is the ColdFire Family Programmer's Reference
  ## Manual, whose per-instruction operand table names the modes directly. It
  ## is not on this machine (AGENTS.md section 11) and the network is closed.
  ## Uncertainty 4 in the `logic.nim` header is this one.
  ##
  ## IT IS A CONSTANT OF ITS OWN AND NOT A NARROWED `eaDataAddressing`,
  ## because AND and OR keep the immediate: Table 3-13's `and.l <ea>,Rx` row
  ## on page 3-28 and its `or.l <ea>,Rx` row on the CONTINUATION PAGE 3-29
  ## both give `#xxx` a time of `1(0/0)`.

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

const eaJumpTarget* = EaLegality(
  modes: eaControlModes, ea7: eaControl7 + {ea7AbsW})
  ## THE OPERAND OF `JMP` AND `JSR`: control addressing INCLUDING the absolute
  ## SHORT form. CPU-10 added it.
  ##
  ## THE MANUAL GIVES THE CLASS TWICE AND BOTH READINGS INCLUDE `(xxx).W`.
  ##
  ##   - MCF5307 User's Manual Table 3-15, "General Branch Instruction
  ##     Execution Times", page 3-30. The `jmp <ea>` row carries a time under
  ##     `(An)` (5(0/0)), under the merged `(d16,An)/(d16,PC)` column
  ##     (5(0/0)), under `(d8,An,Xi*SF)/(d8,PC,Xi*SF)` (6(0/0)) and under
  ##     `xxx.wl` (1(0/0)), and A DASH under `Rn`, `(An)+`, `-(An)` and
  ##     `#xxx`. The `jsr <ea>` row directly below it dashes and times exactly
  ##     the same columns. Page 3-26 states what the column heading means:
  ##     'The nomenclature "xxx.wl" refers to both forms of absolute
  ##     addressing, xxx.w and xxx.l.'
  ##
  ##   - Table 3-5, "Effective Addressing Modes and Categories", page 3-21.
  ##     The CONTROL column carries an `x` on `(An)`, `(d16,An)`,
  ##     `(d8,An,Xi)`, `(d16,PC)`, `(d8,PC,Xi)`, `(xxx).W` AND `(xxx).L`, and
  ##     nothing on `Dn`, `An`, `(An)+`, `-(An)` and `#<xxx>`.
  ##
  ## `m68k-elf-as -mcpu=5307` corroborates both halves: it emits `4ed0`,
  ## `4ee8 0004`, `4ef0 2804`, `4ef8 1234`, `4ef9 0005 4320` and `4efa 0020`
  ## for the six legal modes, and it REJECTS `jmp %d0`, `jmp %a0`,
  ## `jmp (%a0)+`, `jmp -(%a0)` and `jmp #4`. `m68k-elf-objdump` decodes
  ## `4ec0` and `4ec8` as an instruction on NEITHER `-m m68k:5307` nor
  ## `-m m68k:68020`.
  ##
  ## IT IS A CONSTANT OF ITS OWN AND NOT `eaControl7`, AND THE TWO CANNOT BE
  ## MERGED. `eaControl7` in `ea.nim` is `{ea7AbsL, ea7PCDisp, ea7PCIndex}` -
  ## no `(xxx).W` - and LEA, PEA and MOVEM read it through the entry below.
  ## Measured on the pinned assembler: `lea 0x1234.w,%a0` (`41f8 1234`) and
  ## `pea 0x1234.w` (`4878 1234`) ARE accepted, and
  ## `movem.l %d0-%d1,0x1234.w` is REJECTED. So MOVEM's exclusion is right and
  ## LEA's and PEA's are not, one constant cannot serve all four, and
  ## WIDENING `eaControl7` WOULD BREAK MOVEM. LEA's and PEA's repair is
  ## CPU-7's and is `eaLeaPeaTarget` below; `tests/t_control.nim` records the
  ## measurement so the next reader does not have to take it again.

const eaLeaPeaTarget* = EaLegality(
  modes: eaControlModes, ea7: eaControl7 + {ea7AbsW})
  ## THE OPERAND OF `LEA` AND `PEA`: control addressing INCLUDING the absolute
  ## SHORT form. CPU-7 added it, and the entry above states why it could not
  ## simply widen `eaControl7`.
  ##
  ## IT IS A THIRD CONSTANT AND NOT A REUSE OF `eaJumpTarget`, WHICH IT
  ## CURRENTLY EQUALS. The two are equal by measurement rather than by
  ## definition: `eaJumpTarget` is the class of a BRANCH TARGET and this is
  ## the class of an ADDRESS an instruction computes. Folding them together
  ## would mean a later correction to one silently moving the other, and the
  ## entry above already records that this family has drifted once.
  ##
  ## THE MANUAL TIMES BOTH INSTRUCTIONS UNDER THE ABSOLUTE COLUMN, AND EACH
  ## HAS ITS OWN ROW. Read as RENDERED IMAGES - the `SWAP` row of Table 3-7
  ## does not survive `pdftotext` and neither do these:
  ##
  ##   - MCF5307 User's Manual Table 3-13, "Two Operand Instruction Execution
  ##     Times", page 3-28. The `lea | <ea>,Ax` row is timed `1(0/0)` under
  ##     `xxx.wl`, `1(0/0)` under `(An)` and under the merged
  ##     `(d16,An)/(d16,PC)` column, `2(0/0)` under
  ##     `(d8,An,Xi*SF)/(d8,PC,Xi*SF)`, and DASHED under `Rn`, `(An)+`,
  ##     `-(An)` and `#xxx`.
  ##
  ##   - Table 3-14, "Miscellaneous Instruction Execution Times", page 3-29.
  ##     The `pea | <ea>` row is timed `2(0/1)` under `xxx.wl`, `2(0/1)` under
  ##     `(An)` and `(d16,An)`, `3(0/1)` under `(d8,An,Xi*SF)`, and DASHED
  ##     under `Rn`, `(An)+`, `-(An)` and `#xxx`. PEA IS NOT BORROWING LEA'S
  ##     ROW: it has its own, in its own table, and the two agree.
  ##
  ##   - Page 3-26 defines the column heading: 'The nomenclature "xxx.wl"
  ##     refers to both forms of absolute addressing, xxx.w and xxx.l.' So a
  ##     time under `xxx.wl` is a time under `(xxx).W`.
  ##
  ##   - Table 3-5, "Effective Addressing Modes and Categories", page 3-21,
  ##     carries an `x` for "Absolute Data Addressing / Short" `(xxx).W` in
  ##     the CONTROL column, beside `(xxx).L`.
  ##
  ## `m68k-elf-as -mcpu=5307` (GNU Binutils 2.47.20260726, the pin in
  ## `docs/toolchain.md`) corroborates: `lea 0x1234.w,%a0` assembles to
  ## `41f8 1234`, `lea 0x8000.w,%a0` to `41f8 8000`, `lea 0x1234.w,%a3` to
  ## `47f8 1234`, `pea 0x1234.w` to `4878 1234` and `pea 0x8000.w` to
  ## `4878 8000`.
  ##
  ## `MOVEM` DOES NOT READ THIS AND MUST NOT. Table 3-14's two `movem.l` rows
  ## are timed under `(An)` and `(d16,An)` ONLY and are DASHED under
  ## `xxx.wl`, and the assembler rejects `movem.l %d0-%d1,0x1234.w` with
  ## "operands mismatch". `tests/t_move.nim` asserts that MOVEM still traps
  ## there, which is the case that fails if this constant is ever wired to
  ## the MOVEM arm of `eaLegalityFor`.

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
    # Table 3-13: the `and.l <ea>,Rx` row on page 3-28 and the `or.l <ea>,Rx`
    # row on the CONTINUATION PAGE 3-29 both give `#xxx` a time of `1(0/0)`,
    # and `c0bc 0000 0005` disassembles as `andl #5,%d0` on
    # `m68k-elf-objdump -m m68k:5307`.
    #
    # THE TABLE SPANS TWO PAGES AND AN EARLIER REVISION PUT BOTH ROWS ON THE
    # FIRST. Page 3-28 ends after the `mulu.l` row; `or.l`, `ori.l`, `sub.l`,
    # `subi.l`, `subq.l` and `subx.l` are on 3-29.
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
    #   - Table 3-13: `andi.l | #imm,Dx` and `eori.l | #imm,Dx` on page 3-28,
    #     and `ori.l | #imm,Dx` on the continuation page 3-29, each read
    #     `1(0/0)` under `Rn` and a dash everywhere else, `#xxx` included. An
    #     earlier revision of this line put all three on 3-28.
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
  of opJmp, opJsr:
    # Control addressing, absolute short included. The manual rows and the
    # toolchain measurements are on `eaJumpTarget` above.
    eaJumpTarget
  of opTst, opCmp, opCmpa:
    # THESE THREE READ AND WRITE NOTHING, AND THEIR CLASS IS THE WIDEST ONE.
    # Every column of Table 3-12's three `tst` rows on page 3-27 - `Rn`,
    # `(An)`, `(An)+`, `-(An)`, `(d16,An)`, `(d8,An,Xi*SF)`, `xxx.wl` and
    # `#xxx` - carries a time, and so does every column of Table 3-13's
    # `cmp.l <ea>,Rx` row on page 3-28. There is NO DASH in any of the four
    # rows, which is the same mark that puts `and.l Dy,<ea>`'s `Rn` and
    # `btst #imm,<ea>`'s `xxx.wl` out.
    #
    # THAT IS THE `eaDataModes` SET AND NOT `eaDataAddressing`, because these
    # three admit an ADDRESS REGISTER: `m68k-elf-as -mcpu=5307` emits `4a88`
    # for `tst.l %a0`, `b288` for `cmp.l %a0,%d1` and `b3c8` for
    # `cmpa.l %a0,%a1`. `eaDataAddressing` is the manual's DATA class, which
    # excludes `An`, and it is the mask AND and OR read.
    #
    # A BYTE OPERAND MAY STILL NOT BE AN ADDRESS REGISTER, and that rule is
    # about the SIZE rather than the mode: the assembler accepts `tst.w %a0`
    # and `tst.l %a0` and REJECTS `tst.b %a0`. `control.nim`'s `execTst`
    # carries it, because this table is keyed on the operation alone and the
    # size is not part of the key - the same reason `eaMemoryAlterable` is not
    # in it.
    EaLegality(modes: eaDataModes, ea7: eaData7)
  of opScc, opCmpi:
    # A DATA REGISTER AND NOTHING ELSE, AND THE MANUAL'S TIMING TABLES SAY SO
    # ROW BY ROW.
    #
    #   - Table 3-12, "One Operand Instruction Execution Times", page 3-27:
    #     the `scc Dx` row reads `1(0/0)` under `Rn` and A DASH under `(An)`,
    #     `(An)+`, `-(An)`, `(d16,An)`, `(d8,An,Xi*SF)`, `xxx.wl` and `#xxx`.
    #     The `clr.b` rows above it and the `tst.b` rows below it carry times
    #     in those same columns, so the dashes belong to this row.
    #   - Table 3-13, page 3-28: the `cmpi.l #imm,Dx` row reads `1(0/0)` under
    #     `Rn` and a dash everywhere else, `#xxx` included - the same shape as
    #     `andi.l`, `eori.l` and `subi.l`.
    #
    # `m68k-elf-as -mcpu=5307` corroborates both: it rejects `scc (%a0)`,
    # `scc %a0`, `scc 0x1234.w`, `cmpi.l #5,(%a0)` and `cmpi.l #5,%a0`.
    #
    # THIS MASK IS ALSO WHAT REFUSES THE 68000 `DBcc` WORD.
    # `0101 cccc 11 001 rrr` is `DBcc Dn,<label>` on a 68000; here it is an Scc
    # word whose operand is an ADDRESS REGISTER, and no DBcc at all, because
    # manual section 3.9, which begins on page 3-21, lists "decrement and
    # branch" among the removed instructions, and `m68k-elf-as -mcpu=5307`
    # rejects `dbra %d0,.` and `dbf %d0,.`. CPU-13 owns the negative case and
    # this mask is the mechanism it asserts through.
    EaLegality(modes: {eaDn}, ea7: {})
  of opLea, opPea:
    # CONTROL ADDRESSING INCLUDING `(xxx).W`. This arm USED TO BE SHARED WITH
    # `opMovem` on `eaControl7`, and that was a live defect: `eaControl7`
    # excludes `(xxx).W`, so `lea 0x1234.w,%a0` and `pea 0x1234.w` - two
    # forms the pinned assembler emits - trapped. `eaLeaPeaTarget` carries
    # the manual rows and the measurements.
    eaLeaPeaTarget
  of opMovem:
    # MOVEM KEEPS `eaControl7`, AND ITS EXCLUSION OF `(xxx).W` IS CORRECT.
    # Table 3-14, page 3-29, dashes both `movem.l` rows under `xxx.wl`, and
    # `m68k-elf-as -mcpu=5307` rejects `movem.l %d0-%d1,0x1234.w`. This is
    # why LEA and PEA needed a constant of their own rather than a wider
    # `eaControl7`. A data register direct (mode 0), an immediate (mode 7,
    # sub 4), a postincrement or a predecrement are illegal and must trap.
    # `MOVEM -(An)` is the CPU-13 negative case.
    EaLegality(modes: eaControlModes, ea7: eaControl7)
  of opSwap:
    # A DATA REGISTER AND NOTHING ELSE. Table 3-7, page 3-25, gives the
    # operand syntax as `Dn`, and Table 3-12, page 3-27, times `swap Dx`
    # at 1(0/0) under `Rn` with a DASH in all seven other columns - the
    # same shape as `ext`, `extb`, `neg`, `negx` and `not` in that table.
    EaLegality(modes: {eaDn}, ea7: {})
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
