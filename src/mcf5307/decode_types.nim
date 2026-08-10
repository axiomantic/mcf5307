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
    opIllegal

  Decoded* = ref object
    op*: Operation
    ea*: EA
    size*: uint8
    destReg*: uint8
    destMode*: uint8
    memDir*: bool

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

proc eaLegalityFor*(op: Operation): EaLegality =
  ## The legality mask the opcode carries. Illegal for an opcode with no
  ## effective address is meaningless (the empty mask).
  case op
  of opMove, opMovea, opAddq, opSubq:
    # These take data addressing, which admits every mode including the
    # mode-7 sub-variants. The reserved and invalid mode-7 encodings stay
    # out of the mask, so they trap.
    EaLegality(modes: eaDataModes, ea7: eaData7)
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
  ## effective address has no mask and therefore no illegal mode.
  result = (op in {opMove, opMovea, opAddq, opSubq, opLea, opMovem, opPea}) and
    isEaLegal(eaLegalityFor(op), ea)
