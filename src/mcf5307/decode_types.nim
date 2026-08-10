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
    imm*: uint8      ## the quick immediate of ADDQ and SUBQ, already
                     ## resolved: the encoded data field 000 means eight.

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
