## `t_ea_masks` - the decoder and effective-address legality masks.
##
## The assertion groups:
##
##   (1) The first non-zero cycle return. The test
##       drives `mcf5307_create` with a board that returns `MCF5307_BUS_OK`
##       and a `NOP` for every fetch, `mcf5307_reset` with a synthetic stack
##       pointer and program counter, `mcf5307_exec` with a small cycle
##       budget, and `mcf5307_destroy`, and asserts the cycle count is above
##       zero. A core that returns zero cycles cannot loop at all, so this
##       separates "the decoder ran" from "the decoder is not wired in".
##
##   (2) EA legality, negative. Each opcode carries its own legality mask and
##       an illegal mode traps. For each opcode the decoder recognizes with an
##       effective address, at least one illegal mode must be rejected by
##       `isEaLegal`. A mask that accepts every mode would hide the firmware
##       fault the whole rule exists to expose.
##
##   (3) EA legality, positive control. For each such opcode at least one
##       legal mode must be accepted. Without this, a mask that rejects
##       everything would report (2) as a pass, and "the illegal mode is
##       rejected" would not be separable from "the opcode admits no mode".
##
##   (4) The extension-word order of absolute long addressing, with its own
##       control. `(xxx).L` carries the high half of the address in the first
##       extension word. No case in `conformance/corpus/` uses an absolute-long
##       operand at all, so nothing else in this project can see a core that
##       reads the two words the other way round. The block near the end of
##       this file says which manual section that is and why the control is
##       there.
##
## The test also decodes a representative word for every recognized opcode
## and checks the operation comes back, so that the legality assertions are
## attached to the decoder and not to a table the decoder never reads.
##
## There is no supervisor and user stack split on ISA_A; the context holds the
## single `sp`.

## The imports name the layer each symbol comes from. `decode` does not
## re-export `decode_types`, so each module below supplies exactly the names
## the test takes from it: `cpu` the lifecycle ABI (`mcf5307_create`,
## `mcf5307_reset`, `mcf5307_exec`, `mcf5307_destroy`), `decode` the decoder
## (`decodeWord`), `decode_types` the shared types and the legality table
## (`Operation`, `Mcf5307BusStatus`, `eaIsLegalFor`), `ea` the
## effective-address decoding (`EA`, `decodeEa`), and `machine` the register
## bridge the absolute-long case drives (`mcf5307_set_reg`,
## `mcf5307_get_reg`).

import std/[strutils]
import mcf5307/cpu
import mcf5307/decode
import mcf5307/decode_types
import mcf5307/ea
import mcf5307/machine

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

# ---------------------------------------------------------------------------
# (4) The extension-word order of absolute long addressing, and a control for
#     it.
#
# ColdFire Family Programmer's Reference Manual, Rev. 3, section 2.2.11 and
# Figure 2-13: `(xxx).L` occupies two extension words, and "the first
# extension word contains the high-order part of the address; the second
# contains the low-order part." A core that reads them the other way round
# assembles 0x00123456 as 0x34560012 and every absolute-long operand reads the
# wrong place.
#
# No corpus case reaches this. `conformance/corpus/` holds no `(xxx).L`
# operand in any group, so a swap is invisible to every registered conformance
# test. This case is what makes it visible.
#
# The case runs through the shipped C entry points and not through `eaAddr`
# reached around the back, so it asserts the path the corpus runner drives.
#
# The second assertion is the control. The board answers the swapped address
# with a different value rather than with a fault, so the first assertion
# fails on a wrong value and not on a bus error the core would have reported
# for any number of unrelated reasons. Asserting that the swapped address was
# never presented to the board is what separates "the address was assembled
# correctly" from "the read happened to land somewhere that answered".

const
  absLProgramBase = 0x100'u32
  absLTargetAddr = 0x00123456'u32
  absLSwappedAddr = 0x34560012'u32
  absLTargetValue = 0xCAFEBABE'u32
  absLDecoyValue = 0x0BADC0DE'u32

var absLSawSwapped = false

# `move.l (0x00123456).L,%d0`. Source mode 111 register 001 is absolute long;
# destination mode 000 register 000 is D0; bits 13..12 of 0b10 are the long
# size. Assembled by hand from the encoding in the manual, and the two
# extension words below are the manual's order: high first.
proc readAbsL(user: pointer; address: uint32; size: cint;
              status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  status[] = Mcf5307BusStatus.busOk
  if address == absLSwappedAddr:
    absLSawSwapped = true
    return absLDecoyValue
  case address
  of absLProgramBase: 0x2039'u32          # move.l (xxx).L,%d0
  of absLProgramBase + 2: 0x0012'u32      # first extension word:  high half
  of absLProgramBase + 4: 0x3456'u32      # second extension word: low half
  of absLTargetAddr: absLTargetValue
  else: 0'u32

block:
  let ctx = mcf5307_create(nil, readAbsL, writeNoop, iackNoop)
  discard mcf5307_set_reg(ctx, 0, 0'u32)
  mcf5307_reset(ctx, 0x4000000'u32, absLProgramBase)
  discard mcf5307_exec(ctx, 64'u32)
  let d0 = mcf5307_get_reg(ctx, 0)
  check(d0 == absLTargetValue,
    "move.l (0x00123456).L,%d0 reads the address whose HIGH half is the " &
    "first extension word (got 0x" & d0.toHex(8) & ")")
  check(not absLSawSwapped,
    "the word-swapped address 0x34560012 is never presented to the board")
  mcf5307_destroy(ctx)

if failures.len > 0:
  echo ""
  echo "t_ea_masks: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_ea_masks: ", passCount, " cases passed"
