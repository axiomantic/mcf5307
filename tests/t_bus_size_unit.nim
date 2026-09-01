## `t_bus_size_unit` - the UNIT of the `size` argument the core hands the two
## board callbacks, pinned as a behaviour of the core rather than as a sentence
## in a header.
##
## WHAT IT EXISTS TO CATCH. `include/mcf5307.h` states that `size` is a COUNT OF
## BYTES. A sentence in a header cannot fail, so this suite is the mechanism
## that can: it installs recording callbacks through the PUBLISHED entry points
## and asserts the values the core actually presents to a board.
##
## THE DEFECT IT ANSWERS. The unit was never stated, and the core and its first
## real consumer read it differently - the core as a byte count, the consumer as
## a width in bits. Each side was internally consistent and each side's suite
## was green, because no test had ever let the core drive a real board: every
## board-side test supplied the width by hand. The interface between two tested
## subsystems was the one thing neither suite reached.
##
## IT DRIVES THE CALLBACKS A CONSUMER INSTALLS, AND THAT IS THE WHOLE POINT. The
## path is `mcf5307_create`, `mcf5307_reset`, `mcf5307_exec` - the three calls a
## board makes - so the values asserted are the values that cross the ABI. A
## suite that called `readMem` directly would assert the core's internal
## spelling of the argument and would have stayed green through exactly the
## defect above.
##
## EACH NAMED PROGRAM ASSERTS ITS WHOLE ACCESS SEQUENCE AND NOT ONE FIELD OF IT.
## The expected sequence carries the address and the size of every access the
## program makes, the instruction fetch included, so an access that appears, one
## that vanishes and one that changes width are three different failures rather
## than one silence.
##
## THE SWEEP IS WHAT TURNS THE SET CLAIM INTO A MEASUREMENT. The named programs
## show that a byte, a word and a longword access reach a board as 1, 2 and 4;
## they cannot show that NOTHING ELSE does. The sweep runs every one of the
## 65536 opcode words and collects every width any of them presents, so the
## claim is measured over the whole opcode space rather than over the encodings
## someone thought to write. `sizeField` in `src/mcf5307/decode.nim` reports the
## `11` size encoding as 0 and MOVE's own size decode has a 0 arm, so a value
## that is not a legal width EXISTS inside the decoder; the sweep is what
## establishes that no such value reaches a board.
##
## A VACUOUS PASS IS REFUSED. Each sweep set is asserted EQUAL to the byte
## widths, so a run that observed nothing at all reports an empty set and is
## red.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The MOVE
## encodings below are facts about Motorola silicon, from the ColdFire Family
## Programmer's Reference Manual and the MCF5307 User's Manual.

import std/algorithm
import std/strutils

import mcf5307/cpu
import mcf5307/decode_types
import mcf5307/machine

var failures: seq[string]
import ./case_sites

var passCount = 0

proc checkImpl(site: int; ok: bool; label: string; got: string; want: string) =
  if ok:
    echo "PASSED  ", label
    inc passCount
    executedSites.add(site)
  else:
    echo "FAILED  ", label
    echo "          got  ", got
    echo "          want ", want
    failures.add(label)
    executedSites.add(site)

template check(ok: bool; label: string; got: string; want: string) =
  ## THE CALL SITE IS RECORDED TWICE - once at COMPILE TIME into
  ## `declaredSites` by the `static` below, and once at RUN TIME into
  ## `executedSites`. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies. The template
  ## exists for `instantiationInfo`: a proc cannot see where it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, ok, label, got, want)

# ---------------------------------------------------------------------------
# THE RECORDING BOARD.
#
# It answers every access and refuses none, so that what the cases below assert
# is the width the CORE chose and never a width a board's decode rejected. An
# access outside the array reads as zero and writes nothing: the sweep reaches
# addresses this array does not cover, and a pair that indexed it anyway would
# end the process under `--panics:on`.

const
  memSize = 0x2000
  execBase = 0x400'u32   ## above the whole 1024-byte vector table
  dataBase = 0x900'u32   ## the operand, far from the instruction stream
  initialSp = 0x1000'u32

type
  Access = tuple[address: uint32, size: int]

  Board = object
    bytes: array[memSize, uint8]
    reads: seq[Access]
    writes: seq[Access]

var board: Board

proc recordingRead(user: pointer; address: uint32; size: cint;
                   status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr Board](user)
  b.reads.add((address: address, size: int(size)))
  if int(size) <= 0 or int(address) + int(size) > memSize:
    return 0'u32
  for i in 0 ..< int(size):
    result = (result shl 8) or uint32(b.bytes[int(address) + i])

proc recordingWrite(user: pointer; address: uint32; size: cint; value: uint32;
                    status: ptr Mcf5307BusStatus) {.cdecl.} =
  let b = cast[ptr Board](user)
  b.writes.add((address: address, size: int(size)))
  if int(size) <= 0 or int(address) + int(size) > memSize:
    return
  for i in 0 ..< int(size):
    b.bytes[int(address) + i] =
      uint8((value shr ((int(size) - 1 - i) * 8)) and 0xFF'u32)

proc recordingIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

proc freshBoard(opWord: uint16) =
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  board.reads = @[]
  board.writes = @[]
  # BIG-ENDIAN, which is the order the fetch reads it back in.
  board.bytes[int(execBase)] = uint8(opWord shr 8)
  board.bytes[int(execBase) + 1] = uint8(opWord and 0xFF'u16)

proc runOne(opWord: uint16) =
  ## One instruction at `execBase`, through the published entry points, with a0
  ## pointing at the operand. The budget of 1 cycle retires exactly one
  ## instruction: `step` charges at least the fetch, so the loop finds the
  ## budget spent when it next tests it and leaves after that instruction.
  freshBoard(opWord)
  let ctx = mcf5307_create(addr board, recordingRead, recordingWrite,
                           recordingIack)
  mcf5307_reset(ctx, initialSp, execBase)
  discard mcf5307_set_reg(ctx, 8, dataBase)   ## index 8 is a0
  discard mcf5307_exec(ctx, 1'u32)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# THE NAMED PROGRAMS.
#
# MOVE is the whole group used here because one family reaches a byte, a word
# and a longword on the read path and on the write path, with the size in the
# instruction word and no extension word to change the access sequence.
#
# The encodings are the MOVE shape `00 ss rrr mmm MMM RRR`: bits 13..12 are the
# size - 01 byte, 10 long, 11 word - bits 11..9 the destination register, bits
# 8..6 the destination mode, and the low six bits the source effective address.
# Mode 000 is `Dn` and mode 010 is `(An)`.

const
  opMoveBFromMem = 0x1010'u16   ## move.b (a0),d0
  opMoveWFromMem = 0x3010'u16   ## move.w (a0),d0
  opMoveLFromMem = 0x2010'u16   ## move.l (a0),d0
  opMoveBToMem   = 0x1080'u16   ## move.b d0,(a0)
  opMoveWToMem   = 0x3080'u16   ## move.w d0,(a0)
  opMoveLToMem   = 0x2080'u16   ## move.l d0,(a0)

# THE FETCH IS PART OF EVERY EXPECTED SEQUENCE AND IS NOT FILTERED OUT. It is
# itself an access whose unit this contract governs, and an instruction word is
# two BYTES and not sixteen bits. Filtering it would leave the one access every
# program makes unasserted.
const fetch: Access = (address: execBase, size: 2)

type Record = tuple[reads: seq[Access], writes: seq[Access]]

proc accessesOf(opWord: uint16): Record =
  ## THE WHOLE ACCESS RECORD OF ONE PROGRAM, both directions, so that an
  ## assertion below states everything the program did and not the half of it
  ## the case is named after. A read that appeared on a write program's path
  ## would otherwise go unmentioned.
  runOne(opWord)
  (reads: board.reads, writes: board.writes)

let moveBFromMem = accessesOf(opMoveBFromMem)
check(moveBFromMem == (reads: @[fetch, (address: dataBase, size: 1)],
                       writes: newSeq[Access]()),
      "move.b (a0),d0 reads the operand as 1 byte",
      $moveBFromMem,
      $((reads: @[fetch, (address: dataBase, size: 1)],
         writes: newSeq[Access]())))

let moveWFromMem = accessesOf(opMoveWFromMem)
check(moveWFromMem == (reads: @[fetch, (address: dataBase, size: 2)],
                       writes: newSeq[Access]()),
      "move.w (a0),d0 reads the operand as 2 bytes",
      $moveWFromMem,
      $((reads: @[fetch, (address: dataBase, size: 2)],
         writes: newSeq[Access]())))

# THE LONGWORD CASE IS THE ONE THAT SEPARATES THE TWO READINGS OF `size`. A
# byte access is 1 under a byte count and 8 under a width in bits, and a
# longword access is 4 against 32; this is the case whose expected value is the
# one a bit-width core could not produce.
let moveLFromMem = accessesOf(opMoveLFromMem)
check(moveLFromMem == (reads: @[fetch, (address: dataBase, size: 4)],
                       writes: newSeq[Access]()),
      "move.l (a0),d0 reads the operand as 4 bytes and not as 32 bits",
      $moveLFromMem,
      $((reads: @[fetch, (address: dataBase, size: 4)],
         writes: newSeq[Access]())))

let moveBToMem = accessesOf(opMoveBToMem)
check(moveBToMem == (reads: @[fetch],
                     writes: @[(address: dataBase, size: 1)]),
      "move.b d0,(a0) writes the operand as 1 byte",
      $moveBToMem,
      $((reads: @[fetch], writes: @[(address: dataBase, size: 1)])))

let moveWToMem = accessesOf(opMoveWToMem)
check(moveWToMem == (reads: @[fetch],
                     writes: @[(address: dataBase, size: 2)]),
      "move.w d0,(a0) writes the operand as 2 bytes",
      $moveWToMem,
      $((reads: @[fetch], writes: @[(address: dataBase, size: 2)])))

let moveLToMem = accessesOf(opMoveLToMem)
check(moveLToMem == (reads: @[fetch],
                     writes: @[(address: dataBase, size: 4)]),
      "move.l d0,(a0) writes the operand as 4 bytes and not as 32 bits",
      $moveLToMem,
      $((reads: @[fetch], writes: @[(address: dataBase, size: 4)])))

# ---------------------------------------------------------------------------
# THE SWEEP.
#
# Every opcode word, executed through the same published path, with every width
# any of them presents collected. This is what makes the contract a statement
# about the CORE and not about the encodings named above.
#
# THE REGISTERS AND MEMORY ARE THE RESET STATE, so an encoding whose behaviour
# depends on a register value is exercised at one value and not at all of them.
# What the sweep reaches is every DECODED SIZE, which is a property of the
# instruction word alone; it is not a claim about every address such an
# instruction could compute.

proc sweepSizes(): tuple[reads: seq[int], writes: seq[int]] =
  var seenRead: seq[int]
  var seenWrite: seq[int]
  for w in 0 .. 0xFFFF:
    runOne(uint16(w))
    for a in board.reads:
      if a.size notin seenRead:
        seenRead.add(a.size)
    for a in board.writes:
      if a.size notin seenWrite:
        seenWrite.add(a.size)
  seenRead.sort()
  seenWrite.sort()
  (reads: seenRead, writes: seenWrite)

let swept = sweepSizes()

check(swept.reads == @[1, 2, 4],
      "over every opcode word the read path presents only byte widths",
      $swept.reads, $(@[1, 2, 4]))

check(swept.writes == @[1, 2, 4],
      "over every opcode word the write path presents only byte widths",
      $swept.writes, $(@[1, 2, 4]))

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this program reports what
# its text declares and what its run adjudicated, and the registered test's
# driver is what compares them. A verdict printed here would be a
# self-assessment, and a run that stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_bus_size_unit", declaredCaseSites)
echo caseSiteLine("executed", "t_bus_size_unit", executedSites)
echo caseSiteLine("off-green-path", "t_bus_size_unit", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_bus_size_unit: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_bus_size_unit: ", passCount, " cases passed"
