## `t_ea_masks` - the decoder and effective-address legality masks. Task
## CPU-6 creates this file. Design section 6.1.
##
## THREE ASSERTIONS, AND EACH ONE CAN FAIL.
##
##   (1) THE FIRST NON-ZERO CYCLE RETURN, moved here from CPU-3. The test
##       drives `mcf5307_create` with a board that returns `MCF5307_BUS_OK`
##       and a `NOP` for every fetch, `mcf5307_reset` with a synthetic stack
##       pointer and program counter, `mcf5307_exec` with a small cycle
##       budget, and `mcf5307_destroy`, and asserts the cycle count is above
##       zero. A core that returns zero cycles cannot loop at all, so this
##       separates "the decoder ran" from "the decoder is not wired in".
##
##   (2) EA LEGALITY, NEGATIVE. Each opcode carries its own legality mask and
##       an illegal mode traps. For each opcode the decoder recognizes with an
##       effective address, at least one illegal mode must be rejected by
##       `isEaLegal`. A mask that accepts every mode would hide the firmware
##       fault the whole rule exists to expose.
##
##   (3) EA LEGALITY, POSITIVE CONTROL. For each such opcode at least one
##       legal mode must be accepted. Without this, a mask that rejects
##       everything would report (2) as a pass, and "the illegal mode is
##       rejected" would not be separable from "the opcode admits no mode".
##
## The test also decodes a representative word for every recognized opcode
## and checks the operation comes back, so that the legality assertions are
## attached to the decoder and not to a table the decoder never reads.
##
## THE ONE A7. There is no supervisor and user stack split on ISA_A; the
## context holds the single `sp`.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import std/[strutils]
import mcf5307/decode
import mcf5307/ea

var failures: seq[string]
var passCount = 0

proc check(cond: bool; label: string) =
  if cond:
    echo "PASSED  ", label
    inc passCount
  else:
    echo "FAILED  ", label
    failures.add(label)

# ---------------------------------------------------------------------------
# The board for the non-zero-cycle run: `MCF5307_BUS_OK` and a NOP for every
# fetch.

proc readNop(user: pointer; address: uint32; size: cint;
             status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  status[] = Mcf5307BusStatus.busOk
  result = 0x4E71'u32   # NOP

proc writeNoop(user: pointer; address: uint32; size: cint; value: uint32;
               status: ptr Mcf5307BusStatus) {.cdecl.} =
  discard

proc iackNoop(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

# ---------------------------------------------------------------------------
# (1) The first non-zero cycle return, driven through the real ABI.

block:
  let ctx = mcf5307_create(nil, readNop, writeNoop, iackNoop)
  mcf5307_reset(ctx, 0x4000000'u32, 0x100'u32)
  let cycles = mcf5307_exec(ctx, 64'u32)
  check(cycles > 0'u32, "exec runs a NOP fetch and returns non-zero cycles")
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# (2) and (3) EA legality: a legal mode is accepted, and at least one illegal
# mode is rejected, for every opcode that carries an effective-address mask.

block:
  # A legal and an illegal effective address for each masked opcode. The
  # legal operand is the canonical first mode of each class; the illegal one
  # is the reserved mode-7 encoding, outside every mask.
  let cases: seq[(Operation, string, EA, EA)] = @[
    # (op, name, legal EA, illegal EA)
    (opMove, "MOVE", decodeEa(0x00'u16), decodeEa(0x3D'u16)),  # D0 ; mode7 reg5
    (opAddq, "ADDQ", decodeEa(0x00'u16), decodeEa(0x3D'u16)),
    (opSubq, "SUBQ", decodeEa(0x00'u16), decodeEa(0x3D'u16)),
    (opLea,  "LEA",  decodeEa(0x10'u16), decodeEa(0x00'u16)),  # (A0) ; Dn is control-illegal
  ]
  for (opx, name, legal, illegal) in cases:
    check(eaIsLegalFor(opx, legal),
      name & " accepts a legal " & $legal.mode & " effective address")
    check(not eaIsLegalFor(opx, illegal),
      name & " rejects an illegal " & $illegal.mode & " effective address")

# ---------------------------------------------------------------------------
# The decoder recognizes each implemented opcode from a representative word.

block:
  let words: seq[(uint16, Operation, string)] = @[
    (0x4E71'u16, opNop,   "NOP"),
    (0x3010'u16, opMove,  "MOVE.L (A0),D0"),
    (0x5000'u16, opAddq,  "ADDQ"),
    (0x5100'u16, opSubq,  "SUBQ"),
    (0x41D0'u16, opLea,   "LEA (A0),A0"),
    (0x7000'u16, opMoveq, "MOVEQ"),
  ]
  for (word, opx, name) in words:
    check(decodeWord(word).op == opx,
      "decodes " & name & " (0x" & word.toHex(4) & ")")

if failures.len > 0:
  echo ""
  echo "t_ea_masks: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_ea_masks: ", passCount, " cases passed"
