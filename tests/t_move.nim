## `t_move` - the sized write to a data register in the data-movement group.
##
## This file exists beside `mcf5307_conformance_move` because it carries
## source-operand and zero-source variants the corpus does not, and it is the
## control that would catch a corpus regenerated wrongly.
##
## Every case below starts the destination at 0x12345678. That is the whole
## point of the file: the bytes outside the operand size carry a value that a
## replacing write destroys and a merging write keeps.
##
## The rule: `MOVE.B` and `MOVE.W` into `Dn` write the low 8 or the low 16
## bits and leave the rest of the register alone. `MOVE.L` writes all 32. The
## same rule governs `CLR.B` and `CLR.W`, which `t_alu` asserts, and the low
## half of `EXT.W`; a core that is right there and wrong here holds two
## versions of one rule.
##
## The cases run through the shipped C entry points - `mcf5307_create`,
## `mcf5307_reset`, `mcf5307_set_reg`, `mcf5307_exec`, `mcf5307_get_reg` - and
## not through an internal helper reached around the back, so a pass here is a
## pass of the path the corpus runner drives.
##
## Every case asserts a complete tuple (the register, the whole status
## register, `fault`), so a register that is right with a flag that is wrong
## fails, and a flag that is right with a register that is wrong fails.
##
## Instruction semantics, the condition-code rules and the encodings are taken
## from the ColdFire Family Programmer's Reference Manual and the MCF5307
## User's Manual, and from this project's own measurements. The encodings
## below were
## produced by the pinned `m68k-elf-as -mcpu=5307`:
##
##     0:  1200    moveb %d0,%d1
##     2:  3200    movew %d0,%d1
##     4:  2200    movel %d0,%d1

import mcf5307/cpu
import mcf5307/decode_types
import mcf5307/machine

var failures: seq[string]
var passCount = 0

proc check(ok: bool; label: string; got: string; want: string) =
  if ok:
    echo "PASSED  ", label
    inc passCount
  else:
    echo "FAILED  ", label
    echo "          got  ", got
    echo "          want ", want
    failures.add(label)

# ---------------------------------------------------------------------------
# The board. One flat byte array, big-endian, exactly as the conformance
# runner's board. A read outside it reports `busUnmapped` so that a runaway
# program faults instead of reading zeroes for ever.

const memSize = 0x1000

type TestBoard = object
  bytes: array[memSize, uint8]

var board: TestBoard

proc boardWrite(b: var TestBoard; address: uint32; size: int; value: uint32) =
  for i in 0 ..< size:
    b.bytes[int(address) + i] =
      uint8((value shr ((size - 1 - i) * 8)) and 0xFF'u32)

proc boardReadValue(b: TestBoard; address: uint32; size: int): uint32 =
  for i in 0 ..< size:
    result = (result shl 8) or uint32(b.bytes[int(address) + i])

proc bRead(user: pointer; address: uint32; size: cint;
           status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return 0'u32
  status[] = Mcf5307BusStatus.busOk
  boardReadValue(b[], address, int(size))

proc bWrite(user: pointer; address: uint32; size: cint; value: uint32;
            status: ptr Mcf5307BusStatus) {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return
  status[] = Mcf5307BusStatus.busOk
  boardWrite(b[], address, int(size), value)

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

# ---------------------------------------------------------------------------
# The runner. Identical in shape to `t_alu`'s, and one instruction per call for
# the reason that file gives: the memory after the encoding is zero, 0x0000 is
# not an instruction this part has, and a generous budget would fetch it and
# report a fault the case's own instruction did not cause.

const
  execBase = 0x100'u32     ## where the instruction words are placed
  stackBase = 0x800'u32
  srBase = 0x2700'u32      ## the reset status register, CCR all clear
  zero8: array[8, uint32] = [0'u32, 0, 0, 0, 0, 0, 0, 0]

type Outcome = object
  cycles: uint32
  fault: bool
  halted: bool
  d: array[8, uint32]
  a: array[8, uint32]      ## a[7] is the single A7 (the stack pointer)
  sr: uint32

proc runIns(words: openArray[uint16];
            d: array[8, uint32] = zero8;
            a: array[8, uint32] = zero8;
            sr: uint32 = srBase): Outcome =
  ## Place `words` at `execBase`, set the register file and the status
  ## register, run one `mcf5307_exec`, and report the whole machine state.
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  for i in 0 ..< words.len:
    boardWrite(board, execBase + 2'u32 * uint32(i), 2, uint32(words[i]))

  let sp = if a[7] == 0'u32: stackBase else: a[7]
  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, sp, execBase)
  for i in 0 .. 7:
    discard mcf5307_set_reg(ctx, cint(i), d[i])
  for i in 0 .. 6:
    discard mcf5307_set_reg(ctx, cint(8 + i), a[i])
  # The status register is set last: `mcf5307_reset` writes it, so an earlier
  # write would be overwritten.
  discard mcf5307_set_reg(ctx, 16, sr)

  result.cycles = mcf5307_exec(ctx, 1'u32)
  result.fault = ctx.fault
  result.halted = ctx.halted
  for i in 0 .. 7:
    result.d[i] = mcf5307_get_reg(ctx, cint(i))
    result.a[i] = mcf5307_get_reg(ctx, cint(8 + i))
  result.sr = mcf5307_get_reg(ctx, 16)
  mcf5307_destroy(ctx)

proc expectD(o: Outcome; n: int; want: uint32; wantSr: uint32; label: string) =
  let got = (reg: o.d[n], sr: o.sr, fault: o.fault)
  let wanted = (reg: want, sr: wantSr, fault: false)
  check(got == wanted, label, $got, $wanted)

# ---------------------------------------------------------------------------
# The destination starts non-zero in every case.

const dirtyDest = 0x12345678'u32

# ---------------------------------------------------------------------------
# MOVE.B %d0,%d1 = 1200. The low byte is written and the upper THREE bytes are
# kept.

block:
  # The reference case. 0xAA over the low byte of 0x12345678 is 0x123456AA;
  # a replacing write gives 0x000000AA. Bit 7 of the byte is set, so N is set.
  expectD(runIns([0x1200'u16], d = [0x000000AA'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x123456AA'u32, srBase or ccrN,
    "move.b d0,d1 writes the low byte and keeps the upper three")

  # A zero source byte is the starkest case of the rule. The written value and
  # the value a replacing write would leave behind are both zero in the low
  # byte, so the two cores differ in the upper three bytes alone: 0x12345600
  # against 0x00000000. Z is set and N is clear.
  expectD(runIns([0x1200'u16], d = [0'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x12345600'u32, srBase or ccrZ,
    "move.b d0,d1 of a zero byte clears the low byte alone and sets Z")

  # The other half of the merge. The source carries bits above the byte, and
  # they must not reach the destination. A merge that dropped the mask on the
  # incoming value gives 0xFFFFFFAA here and is right on both cases above.
  expectD(runIns([0x1200'u16], d = [0xFFFFFFAA'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x123456AA'u32, srBase or ccrN,
    "move.b d0,d1 takes the low byte of the source alone")

# ---------------------------------------------------------------------------
# MOVE.W %d0,%d1 = 3200. The low word is written and the upper word is kept.
# The word form is asserted separately from the byte form because the corpus
# case for each is degenerate in the same way, and a fix applied to one size
# does not prove the other.

block:
  # 0xBEEF over the low word of 0x12345678 is 0x1234BEEF; a replacing write
  # gives 0x0000BEEF. Bit 15 of the word is set, so N is set.
  expectD(runIns([0x3200'u16], d = [0x0000BEEF'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x1234BEEF'u32, srBase or ccrN,
    "move.w d0,d1 writes the low word and keeps the upper word")

  # The zero source word, for the reason the zero source byte is above: the two
  # cores differ in the upper word alone.
  expectD(runIns([0x3200'u16], d = [0'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x12340000'u32, srBase or ccrZ,
    "move.w d0,d1 of a zero word clears the low word alone and sets Z")

  # The source's upper word must not reach the destination. N is clear here:
  # bit 15 of 0x1234 is zero, and a core that took N from bit 31 of the whole
  # source would set it.
  expectD(runIns([0x3200'u16], d = [0xFFFF1234'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x12341234'u32, srBase,
    "move.w d0,d1 takes the low word of the source alone")

# ---------------------------------------------------------------------------
# MOVE.L %d0,%d1 = 2200. The control against an over-fix.
#
# A long write replaces the whole register, and it is the only one of the three
# that does. Without this case a core that preserved bytes at every size - one
# that masked with the byte width whatever the operand size - passes every case
# above. The destination starts non-zero here too, and none of it survives.

block:
  expectD(runIns([0x2200'u16],
                 d = [0xAABBCCDD'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0xAABBCCDD'u32, srBase or ccrN,
    "move.l d0,d1 replaces the whole register")

if failures.len > 0:
  echo ""
  echo "t_move: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_move: ", passCount, " cases passed"
