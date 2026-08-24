## Shared types for the mcf5307 instruction-group modules.
##
## THIS MODULE IS THE BOTTOM OF THE CORE, above `ea` alone. It holds the
## types that the decoder (`decode.nim`) and every instruction-group executor
## (`move.nim`, and later `alu.nim`, `logic.nim`, `control.nim`) both need.
## Those modules are siblings and neither imports the other; each one reads
## its types from here. `cpu.nim` sits above them and owns `step`.
##
## The effective-address legality table lives here for the same reason. The
## executor modules ask whether an operand is legal before they run an
## instruction. The table reads an `Operation` and an `EA` and it reads no
## decoder state, so it belongs beside the types and not beside the decoder.
##
## NO MODULE RE-EXPORTS THIS ONE. A caller that needs `Operation`, `Decoded`,
## `MCF5307Ctx`, the board callback types or `eaIsLegalFor` imports
## `mcf5307/decode_types` by name. A re-export hides which layer each name
## came from.

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
    # A NEW MEMBER IS APPENDED IMMEDIATELY BEFORE `opIllegal` AND NOWHERE
    # ELSE. `opNop` must stay at ordinal 0, because a zero-initialised
    # `Decoded` reads as `opNop`, and `opIllegal` must stay last. Appending
    # there moves no ordinal that anything depends on.
    opAddx, opSubx, opNegx, opExtb
    opEor, opAndi, opOri, opEori
    opAsl, opAsr, opLsl, opLsr
    # `opBsr` IS NOT `opBcc` WITH A CONDITION OF 1: `0110 0001 dddddddd`
    # pushes a return address, so an executor that folded it into the
    # conditional arm would branch and never push.
    opBsr
    opJmp, opJsr, opRts, opRte, opTrap
    opCmp, opCmpa, opCmpi
    # `MOVEC` IS A GROUP OF ONE: it shares no encoding shape, no size field
    # and no effective address with any member above, and
    # `src/mcf5307/movec.nim` is its executor.
    opMovec
    opMoveFromSr, opMoveFromCcr, opMoveToCcr, opMoveToSr
    opIllegal

  # A VALUE AND NOT A `ref`, WHICH IS THE OPPOSITE CHOICE FROM `MCF5307Ctx`
  # BELOW AND IS DELIBERATE. One of these is produced for each instruction
  # decoded and none of them outlives the dispatch that reads it, so a `ref`
  # would put an allocation and a free on the execute path, which is kept
  # clear of the allocator because the delivery form may enter it from a
  # real-time thread. This type carries no identity to share
  # and no state to mutate through, so a copy loses nothing a reader could
  # observe. The context below is the opposite on every count.
  #
  # THE ZERO VALUE IS A REACHABLE RESULT AND IT IS NOT A TRAP VALUE: it reads
  # as `opNop`, which the enum above pins at ordinal 0 for this reason. A `ref`
  # would answer nil there and fault on the first field read. So a decoder arm
  # that must refuse a word has to SAY SO with `opIllegal`; leaving a branch
  # without naming a result is silent under this declaration and loud under a
  # `ref`.
  Decoded* = object
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

    # THE VECTOR BASE REGISTER. `machine.nim`'s `takeException` is its ONLY
    # reader, and it reads it through `exception.nim`'s `vectorAddress`, which
    # is where the rule about the unimplemented low bits lives. The field
    # holds what was written to it and the mask is applied at the dispatch, so
    # a reader of this field sees the value the machine was given.
    #
    # A FIELD NO DISPATCH CONSULTED WOULD BE INDISTINGUISHABLE FROM NO FIELD
    # AT ALL, which is why the reader and not the field is what the exception
    # suite adjudicates.
    vbr*: uint32                ## the vector base register

    # The interrupt input. `mcf5307/irq` owns every rule about these fields;
    # they live here because the context type lives here and `irq.nim` is
    # above this module.
    #
    # THE SPLIT INTO A PRESENTED LEVEL AND AN ARMED LATCH IS THE WHOLE MODEL.
    # Interrupt levels 1 through 6 are level-sensitive only and level 7 is
    # both level sensitive and edge triggered, so the presented fields are the
    # board's CURRENT presentation and carry no history at all, and the armed
    # fields are the level-7 rising edge the core does latch.
    # A model with one group and not two either latches a level source, which
    # drops it at the acknowledge instead of at the device, or it re-recognizes
    # a held level 7.
    irqLevel*: cint             ## the presented level: 0 for none, or 1 to 7
    irqVector*: uint8           ## the presented vector, when not autovectored
    irqAutovector*: bool        ## the presented autovector flag
    irq7Armed*: bool            ## a rising edge to level 7 is latched
    irq7Vector*: uint8          ## the vector THAT EDGE presented
    irq7Autovector*: bool       ## the autovector flag THAT EDGE presented

    # THE PROGRAM COUNTER IS AT THE ENTRY OF AN EXCEPTION HANDLER WHOSE FIRST
    # INSTRUCTION HAS NOT RUN. Interrupt sampling is inhibited during the
    # first instruction of every exception handler.
    #
    # IT IS A FIELD AND NOT A LOCAL OF `mcf5307_exec` BECAUSE THE CALLER OWNS
    # THE BOUNDARY. A budget can expire on the instruction that takes the
    # exception, so the handler's entry and the handler's first instruction
    # can fall in two different calls; a local would forget the inhibition
    # between them and the interrupt would land at the entry after all.
    #
    # IT IS SET BY `takeException` IN `machine.nim`, which
    # is what makes the rule hold for EVERY exception rather than for the one
    # exception that happens to be implemented. A new exception path inherits
    # the rule by arriving there, and must not set this field itself.
    atHandlerEntry*: bool       ## the next instruction is a handler's first

# ---------------------------------------------------------------------------
# The width of one word of the instruction stream.
#
# One width and not two: on this ISA every word of the instruction stream is
# 16 bits, so the opcode word and each extension word are the same width by
# the encoding and not by coincidence. This is not `fetchCycles`, which shares
# the value 2 by arithmetic accident.

const insWordBytes* = 2'u32
  ## one word of the instruction stream, in bytes

# ---------------------------------------------------------------------------
# The effective-address legality table.

const eaMemoryAlterable* = EaLegality(modes: eaMemAlterableModes,
                                      ea7: eaMemAlterable7)
  ## The destination mask of the `Dn op <ea> -> <ea>` direction of ADD and
  ## SUB. It is not reachable through `eaLegalityFor`, because that table is
  ## keyed on the operation alone and this direction is a property of the
  ## instruction WORD, not of the operation. `alu.nim` names it directly.

const eaDataAddressing* = EaLegality(modes: eaDataAlterableModes,
                                     ea7: eaValid7)
  ## THE MANUAL'S `DATA` CLASS, WHICH DOES NOT INCLUDE `An`.
  ##
  ## IT IS NOT `eaAllModes`. That constant in `ea.nim` is the wider "every
  ## addressing mode" set, which is what a MOVE source needs and what this
  ## class is not.
  ##
  ## The MODE list is the same list `eaDataAlterableModes` holds, because on
  ## this part DATA and DATA ALTERABLE differ only in the mode-7 sub-variants
  ## - the PC-relative pair and the immediate, which are readable and not
  ## writable. The `ea7` set is what separates them and it is spelled out
  ## above.

const eaBitDynamic* = EaLegality(modes: eaDataAlterableModes,
                                 ea7: eaValid7 - {ea7Imm})
  ## THE OPERAND OF A DYNAMIC BIT TEST: the manual's DATA class WITHOUT the
  ## immediate. It is `eaDataAddressing` minus one sub-variant.
  ##
  ## IT IS A CONSTANT OF ITS OWN AND NOT A NARROWED `eaDataAddressing`,
  ## because AND and OR keep the immediate.

const eaBitStatic* = EaLegality(
  modes: {eaDn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp}, ea7: {})
  ## THE OPERAND OF A STATIC BIT OPERATION, WHICH IS NARROWER THAN THE
  ## DYNAMIC ONE. `0000 1000 tt <ea>` takes a data register or an
  ## address-register indirect mode and NOTHING ELSE on this part.
  ##
  ## The DYNAMIC form is wider: it also reaches the indexed and absolute
  ## modes and the PC-relative pair. It reads
  ## `eaBitDynamic` (for BTST) or the data-alterable mask (for BCHG, BCLR and
  ## BSET) through `eaLegalityFor` instead. It is NOT wider in the `#xxx`
  ## column - see `eaBitDynamic`.
  ##
  ## IT IS A CONSTANT AND NOT A TABLE ENTRY for the reason `eaMemoryAlterable`
  ## gives above: static and dynamic share their operations and the
  ## table is keyed on the operation alone.

const eaJumpTarget* = EaLegality(
  modes: eaControlModes, ea7: eaControl7)
  ## THE OPERAND OF `JMP` AND `JSR`: control addressing INCLUDING the absolute
  ## SHORT form.
  ##
  ## LEA AND PEA MUST NOT EXCLUDE THE ABSOLUTE SHORT FORM either;
  ## `eaLeaPeaTarget` below carries the same mode-7 class.
  ##
  ## MOVEM DOES NOT READ THIS CLASS. Its arm carries `{eaAnInd, eaAnDisp}`
  ## with an EMPTY `ea7`. A control-class mask is too wide for MOVEM, so
  ## widening `eaControl7` moves JMP, JSR, LEA and PEA together and must NOT
  ## be made to reach MOVEM.

const eaLeaPeaTarget* = EaLegality(
  modes: eaControlModes, ea7: eaControl7)
  ## THE OPERAND OF `LEA` AND `PEA`: control addressing INCLUDING the absolute
  ## SHORT form.
  ##
  ## IT IS A CONSTANT OF ITS OWN AND NOT A REUSE OF `eaJumpTarget`, WHICH IT
  ## EQUALS. The two are equal by measurement rather than by definition:
  ## `eaJumpTarget` is the class of a BRANCH TARGET and this is the class of an
  ## ADDRESS an instruction computes. Folding them together would mean a later
  ## correction to one silently moving the other.
  ##
  ## `MOVEM` DOES NOT READ THIS AND MUST NOT: its operand class is narrower
  ## still.

const table313LastRowOnPage328* = "mulu"
  ## The last opcode row Table 3-13 prints on page 3-28; the rest of the table
  ## is on the continuation page. `tests/t_ea_masks.nim` checks this value
  ## against its own copy.

proc eaLegalityFor*(op: Operation; size: uint8): EaLegality =
  ## The legality mask the opcode carries. An opcode with no effective
  ## address carries the empty mask.
  ##
  ## THE SIZE IS PART OF THE KEY FOR THE MULTIPLY AND DIVIDE ALONE. Every
  ## other operation on this part has one operand class across every size it
  ## has, and ignores the parameter.
  case op
  of opMove, opMovea:
    # These take data addressing, which admits every mode including the
    # mode-7 sub-variants. The reserved and invalid mode-7 encodings stay
    # out of the mask, so they trap.
    EaLegality(modes: eaAllModes, ea7: eaValid7)
  of opAdd, opSub, opAdda, opSuba:
    # The `<ea>` operand of the register direction, and the source of ADDA
    # and SUBA: data addressing, PC-relative and immediate included.
    EaLegality(modes: eaAllModes, ea7: eaValid7)
  of opAddq, opSubq:
    # ALTERABLE, AND NOT DATA ADDRESSING. An ADDQ destination is written, so
    # it cannot be PC-relative and it cannot be an immediate. An address
    # register IS allowed, which is why this is `alterable` and not `data
    # alterable`.
    EaLegality(modes: eaAllModes, ea7: eaAlterable7)
  of opClr:
    # Data alterable: no An, no PC-relative, no immediate.
    EaLegality(modes: eaDataAlterableModes, ea7: eaDataAlterable7)
  of opMulu, opMuls, opDivu, opDivs:
    # THE ONE ARM WHOSE MASK DEPENDS ON THE SIZE, AND IT DEPENDS ON IT IN BOTH
    # DIRECTIONS. The data-alterable mask above is too NARROW for the word
    # form and too WIDE for the long
    # one; no single class is right for both and the arm cannot be collapsed.
    #
    #   WORD  the manual's DATA class - but THE COMPOSITION BELOW NAMES NO SET
    #         CALLED "DATA", and reading it as one repeats this family's
    #         RECURRING DEFECT: taking a mask for the manual class its name
    #         suggests instead of for the value it holds. It pairs
    #         `eaDataAlterableModes`, which
    #         is every mode but `An`, with `eaValid7`, and it is that SECOND
    #         half that puts the PC-relative pair and the immediate back IN,
    #         because the word form only READS its source. The mode lists of
    #         DATA and DATA ALTERABLE are identical on this part and the two
    #         classes differ in the mode-7 sub-variants alone, so the
    #         alterable mode set is the correct half of a DATA mask rather
    #         than a near-miss. `eaDataAddressing` above is that same pair
    #         under a name and carries the manual rows behind it.
    #   LONG  narrower than data alterable: the indexed mode and the whole of
    #         mode 7 are out.
    #
    # THE SIZE REACHING HERE IS `Decoded.size`, which `decodeLogicLine` sets
    # to 2 for the single-word forms and `decodeWord` sets to 4 for the
    # two-word ones. A size this arm does not expect takes the LONG mask,
    # which refuses more than it allows.
    if size == 2'u8:
      EaLegality(modes: eaDataAlterableModes, ea7: eaValid7)
    else:
      EaLegality(modes: eaMulDivLongModes, ea7: eaMulDivLong7)
  of opAnd, opOr:
    # THE SOURCE OF THE `<ea> op Dn -> Dn` DIRECTION of AND and OR. It reads
    # and does not write, so the class is DATA addressing: no An, and the
    # PC-relative pair and the immediate are in.
    #
    # The OTHER direction of AND and OR writes memory and carries
    # `eaMemoryAlterable`, which this table cannot hold because the direction
    # is a property of the instruction word. `logic.nim` names it directly,
    # exactly as `alu.nim` does for ADD and SUB.
    eaDataAddressing
  of opBtst:
    # A DYNAMIC BTST READS AND DOES NOT WRITE, SO ITS CLASS IS ALSO A READING
    # ONE - BUT IT STOPS SHORT OF THE IMMEDIATE. `eaBitDynamic` carries the
    # difference.
    eaBitDynamic
  of opEor, opBchg, opBclr, opBset:
    # EOR HAS ONE DIRECTION on this part - `Dn ^ <ea> -> <ea>` - and the three
    # bit operations that WRITE their operand share its class: data alterable.
    # A data register is in, an address register is not, and neither is a
    # PC-relative operand or an immediate.
    EaLegality(modes: eaDataAlterableModes, ea7: eaDataAlterable7)
  of opNot, opAndi, opOri, opEori, opAsl, opAsr, opLsl, opLsr:
    # A DATA REGISTER AND NOTHING ELSE. An immediate COUNT is still legal for
    # the shifts, because the count is not the operand this mask governs.
    EaLegality(modes: {eaDn}, ea7: {})
  of opAddi, opSubi, opNeg, opNegx, opExt, opExtb, opAddx, opSubx:
    # A DATA REGISTER AND NOTHING ELSE on this part. The 68000 forms that
    # reach memory, and the memory form of ADDX, are not on it.
    EaLegality(modes: {eaDn}, ea7: {})
  of opJmp, opJsr:
    # Control addressing, absolute short included. `eaJumpTarget` above
    # carries the class.
    eaJumpTarget
  of opTst, opCmp, opCmpa:
    # THESE READ AND WRITE NOTHING, AND THEIR CLASS IS THE WIDEST ONE.
    #
    # THAT IS THE `eaAllModes` SET AND NOT `eaDataAddressing`, because they
    # admit an ADDRESS REGISTER. `eaDataAddressing` is the manual's DATA
    # class, which excludes `An`, and it is the mask AND and OR read.
    #
    # A BYTE OPERAND MAY STILL NOT BE AN ADDRESS REGISTER, and that rule is
    # about the SIZE rather than the mode. `control.nim`'s `execTst`
    # carries it, because this table is keyed on the operation alone and the
    # size is not part of the key - the same reason `eaMemoryAlterable` is not
    # in it.
    EaLegality(modes: eaAllModes, ea7: eaValid7)
  of opScc, opCmpi:
    # A DATA REGISTER AND NOTHING ELSE.
    #
    # THIS MASK IS ALSO WHAT REFUSES THE 68000 `DBcc` WORD.
    # `0101 cccc 11 001 rrr` is `DBcc Dn,<label>` on a 68000; here it is an Scc
    # word whose operand is an ADDRESS REGISTER, and no DBcc at all, because
    # DBcc is not on this part.
    EaLegality(modes: {eaDn}, ea7: {})
  of opLea, opPea:
    # CONTROL ADDRESSING INCLUDING `(xxx).W`. A mode-7 set that excludes
    # `(xxx).W` traps `lea 0x1234.w,%a0` and `pea 0x1234.w`, which are real
    # forms on this part. It is NOT shared with `opMovem`, whose class is
    # narrower still.
    eaLeaPeaTarget
  of opMovem:
    # `(An)` AND `(d16,An)`, AND NOTHING ELSE. MOVEM IS NOT A CONTROL-CLASS
    # OPERAND ON THIS PART.
    #
    # A CONTROL-CLASS MASK IS TOO WIDE HERE: it would add `(d8,An,Xi)` from
    # the mode set and `(xxx).L`, `(d16,PC)` and `(d8,PC,Xi)` from the mode-7
    # set. Under a mask that wide, `movem.l %d0-%d1,0x400.l` - `48f9 0003 0000
    # 0400` - reaches the executor and COMPLETES ITS STORE with `fault` false,
    # which is the permissive core this mask exists to prevent.
    #
    # THE `ea7` SET IS EMPTY AND THAT IS NOT WHAT REJECTS A MODE-7 OPERAND,
    # for the reason `eaMulDivLong7` states in `ea.nim`: `isEaLegal` returns
    # at `ea.mode notin leg.modes` before it reads `ea7`, and `eaMode7` is not
    # in the mode set above. The absent `eaMode7` is the rejection; the empty
    # set is unreachable through this mask and constrains nothing.
    EaLegality(modes: {eaAnInd, eaAnDisp}, ea7: {})
  of opSwap:
    # A DATA REGISTER AND NOTHING ELSE.
    EaLegality(modes: {eaDn}, ea7: {})
  else:
    EaLegality(modes: {}, ea7: {})

proc eaLegalityFor*(op: Operation): EaLegality =
  ## The legality mask of an operation whose class does not depend on the
  ## size. It answers the LONGWORD mask, which for the multiply and divide is
  ## the NARROWER of the two.
  ##
  ## THE NARROW MASK IS THE SAFE DEFAULT AND THE CHOICE IS DELIBERATE. A call
  ## site that should have passed a size and did not gets a mask that REFUSES
  ## operands the word form allows, so the instruction traps and the omission
  ## is loud. The opposite default would ACCEPT operands the long form
  ## forbids, and a permissive core executing an addressing mode the silicon
  ## rejects would be silent.
  eaLegalityFor(op, 4'u8)

proc eaIsLegalFor*(op: Operation; ea: EA; size: uint8): bool =
  ## True when `ea` is inside the opcode's legality mask at `size`. An opcode
  ## with no effective address carries the empty mask and no mode is inside
  ## it.
  ##
  ## THE EMPTY MASK IS THE TEST, AND NOT A SECOND LIST of the operations
  ## `eaLegalityFor` names. Two lists drift: an operation added to the table
  ## above and forgotten in a second list has every effective address
  ## rejected, which reads as "the opcode is strict" and is really "the opcode
  ## is unreachable".
  let legality = eaLegalityFor(op, size)
  result = legality.modes != {} and isEaLegal(legality, ea)

proc eaIsLegalFor*(op: Operation; ea: EA): bool =
  ## The size-less form, for the call sites whose operand class does not
  ## depend on the size. It FORWARDS rather than repeating the emptiness test
  ## above, for the reason that test's own comment gives: two copies drift,
  ## and a second copy of this one would drift SILENTLY, because a mask that
  ## wrongly answered "legal" here reads at the call site exactly like a mask
  ## that is right.
  eaIsLegalFor(op, ea, 4'u8)
