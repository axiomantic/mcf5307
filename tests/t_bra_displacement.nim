## `t_bra_displacement` - `BRA` over EVERY value its displacement byte can
## carry, executed rather than decoded.
##
## WHAT THE REST OF THE TREE PINS, AND WHY IT IS NOT THIS. Four byte
## displacements are executed anywhere in this repository: `0x06` and `0xf8` in
## the generated control corpus, `0xfe` in `t_control` block 5, and `0x00` in
## the same block as the 16-bit marker. `0xff` is refused there as the 32-bit
## marker. Every other value of the field is decoded by `t_control` block 3 and
## RUN by nothing. A displacement is one signed byte added to one base, so the
## whole field is 256 executions - small enough to run exhaustively, which is
## what this file does.
##
## THE EXPECTED PROGRAM COUNTER IS COMPUTED FROM THE MANUAL'S RULE AND IS NOT A
## TABLE OF WHAT THIS CORE DOES. "The PC contains the address of the instruction
## word of the BRA instruction plus two. The displacement is a two's complement
## integer that represents the relative distance in bytes from the current PC to
## the destination PC. If the 8-bit displacement field in the instruction word
## is 0, a 16-bit displacement (the word immediately following the instruction)
## is used. If the 8-bit displacement field in the instruction word is all ones
## (0xFF), the 32-bit displacement (longword immediately following the
## instruction) is used" - ColdFire Family Programmer's Reference Manual, Rev.
## 3, printed page 4-20. The longword form first appeared in ISA_B and this part
## implements ISA_A, so `0xff` is refused.
##
## THE SIGN EXTENSION IS WRITTEN OUT HERE AND NOT IMPORTED FROM THE CORE. `s8`
## and `s16` live in `mcf5307/machine`, and a sweep that reached for them would
## compare the core against itself and agree with any sign convention it had.
##
## THE ODD TARGETS ARE HALF OF THE SWEEP AND THEY ARE NOT AN ASIDE. The base is
## even, so the target's parity is the displacement's, and 127 of the 254 byte
## displacements transfer control to an odd address - which is an address error
## and not a branch. A fixture whose displacements are all even never reaches
## that half. `tests/t_control.nim` block 11 is where the address error's frame
## is pinned field by field; this file pins only that the odd rows take it.
##
## THIS FILE LANDED GREEN, WHICH IS WEAKER THAN A TEST THAT WAS WATCHED FAILING,
## SO IT IS PINNED BY MUTATION INSTEAD. `tests/t_claims.cmake` registers two
## wrong cores against it, and each was measured on this tree rather than
## reasoned about.
##
## `bra_base_suite_t_bra_displacement` moves the branch base back onto the
## opcode's own address:
## that base reds TWO cases of this file.
##
## `bra_isab_suite_t_bra_displacement` takes the longword marker for an ordinary
## byte displacement:
## that marker reds TWO cases of this file.
##
## THE TWO COUNTS AGREE AND THE CASES DO NOT. Each mutation reds the sweep and
## one marker row, and the marker row it reds is the one the other leaves green.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The
## displacement rule, the two markers and the ISA revision that carries the
## longword form are facts about Motorola silicon, from the ColdFire Family
## Programmer's Reference Manual and the MCF5307 User's Manual.

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
  ## `executedSites`, by the implementation and only when it reaches a verdict.
  ## `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, ok, label, got, want)

# ---------------------------------------------------------------------------
# The board. One flat byte array, big-endian, as `t_control`'s and the
# conformance runner's. A read outside it reports `busUnmapped`.

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
# The placement.
#
# `execBase` IS EVEN AND SO IS THE BASE, which is what makes the target's
# parity the displacement's. Every byte displacement reaches
# `execBase + 2 - 128` at the low end and `execBase + 2 + 127` at the high end;
# both are inside the board and clear of the frame the stack pointer produces.

const
  execBase = 0x100'u32
  stackBase = 0x800'u32
  addressErrorVector = 0x00C'u32     ## 4 * 3
  addressErrorHandler = 0x600'u32
  srDirty = 0x2700'u32 or ccrN or ccrZ or ccrV or ccrC or ccrX
    ## The reset status register with every condition code set. BRA writes no
    ## flag, and the address error copies the word rather than changing it, so
    ## a row that came back with a clear code would be a defect. Starting from
    ## zero would assert nothing.
  wordDisplacement = 0x0010'u16
    ## The word after the opcode. It is read only when the displacement byte is
    ## `0x00`, and it is EVEN so that the 16-bit form lands on a legal address:
    ## an odd one would be an address error and would say nothing about the
    ## 16-bit path.

type Row = tuple[disp: int, pc: uint32, sp: uint32, sr: uint32,
                 fault: bool, halted: bool]

proc runDisplacement(disp: int): Row =
  ## One `BRA` whose displacement byte is `disp`, executed through the shipped
  ## entry points and reported whole.
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  boardWrite(board, addressErrorVector, 4, addressErrorHandler)
  boardWrite(board, execBase, 2, 0x6000'u32 or uint32(disp))
  boardWrite(board, execBase + 2'u32, 2, uint32(wordDisplacement))

  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, stackBase, execBase)
  discard mcf5307_set_reg(ctx, 16, srDirty)
  discard mcf5307_exec(ctx, 1'u32)
  result = (disp: disp,
            pc: mcf5307_get_reg(ctx, 17),
            sp: mcf5307_get_reg(ctx, 15),
            sr: mcf5307_get_reg(ctx, 16),
            fault: ctx.fault,
            halted: ctx.halted)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# The rule, written out from the manual.

proc signExtend8(value: int): int =
  ## A two's complement byte, as an int. `0x80` is -128 and `0xff` is -1.
  if (value and 0x80) != 0: value - 0x100 else: value

proc signExtend16(value: int): int =
  if (value and 0x8000) != 0: value - 0x10000 else: value

proc expectedRow(disp: int): Row =
  ## What the manual's rule requires for the displacement byte `disp`.
  const base = execBase + 2'u32
  if disp == 0xFF:
    # The 32-bit form. It first appeared in ISA_B; this part implements ISA_A,
    # so the core refuses the encoding. `step` has already advanced the program
    # counter past the opcode word when the refusal happens.
    return (disp: disp, pc: base, sp: stackBase, sr: srDirty,
            fault: true, halted: true)
  let offset =
    if disp == 0x00: signExtend16(int(wordDisplacement))
    else: signExtend8(disp)
  let target = uint32(int64(base) + int64(offset))
  if (target and 1'u32) != 0'u32:
    # "Any attempted execution transferring control to an odd instruction
    # address ... results in an address error exception" - MCF5307 User's
    # Manual, section 3.5.2. The frame is two longwords on a stack pointer that
    # was already 0-modulo-4.
    return (disp: disp, pc: addressErrorHandler, sp: stackBase - 8'u32,
            sr: srDirty, fault: false, halted: false)
  (disp: disp, pc: target, sp: stackBase, sr: srDirty,
   fault: false, halted: false)

proc firstDifference(got: seq[Row]; want: seq[Row]): string =
  ## The diagnostic string. The VERDICT is the whole-sequence comparison at the
  ## call site; this only names where to look when that comparison is false.
  if got.len != want.len:
    return "lengths " & $got.len & " and " & $want.len
  for i in 0 ..< got.len:
    if got[i] != want[i]:
      return "row " & $i & " " & $got[i]
  "no differing row"

# ---------------------------------------------------------------------------
# THE SWEEP. Every value the displacement byte can hold, in one pass.
#
# THE TWO SEQUENCES ARE BUILT BY TWO SEPARATE LOOPS over the same literal
# range, one running the core and one applying the rule. A pass that produced
# nothing would compare an empty sequence against a full one and red; a
# comparison against a table of observed values could not.

var observed: seq[Row]
for disp in 0 .. 0xFF:
  observed.add(runDisplacement(disp))

var required: seq[Row]
for disp in 0 .. 0xFF:
  required.add(expectedRow(disp))

check(observed == required,
  "every displacement byte lands where the manual's rule puts it",
  firstDifference(observed, required),
  firstDifference(required, observed))

# ---------------------------------------------------------------------------
# WHAT THE SWEEP WOULD STILL AGREE WITH, PINNED SEPARATELY.
#
# The comparison above is between two sequences this file builds. If BOTH loops
# ran zero times it would compare two empty sequences and pass. The rows are
# therefore counted against the range they were built from, and the two markers
# are named individually - a sweep that silently lost `0x00` and `0xff` would
# otherwise be indistinguishable from one that kept them.

check(observed.len == 0x100 and required.len == 0x100,
  "the sweep ran over the whole displacement byte",
  $observed.len & " observed, " & $required.len & " required",
  "256 observed, 256 required")

check(observed[0x00] == (disp: 0x00, pc: execBase + 2'u32 +
                           uint32(wordDisplacement),
                         sp: stackBase, sr: srDirty,
                         fault: false, halted: false),
  "a displacement byte of 0x00 takes the 16-bit form from the next word",
  $observed[0x00],
  $((disp: 0x00, pc: execBase + 2'u32 + uint32(wordDisplacement),
     sp: stackBase, sr: srDirty, fault: false, halted: false)))

check(observed[0xFF] == (disp: 0xFF, pc: execBase + 2'u32, sp: stackBase,
                         sr: srDirty, fault: true, halted: true),
  "a displacement byte of 0xff is the ISA_B longword form and is refused",
  $observed[0xFF],
  $((disp: 0xFF, pc: execBase + 2'u32, sp: stackBase, sr: srDirty,
     fault: true, halted: true)))

# ---------------------------------------------------------------------------

echo ""
# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this program reports
# what its text declares and what its run adjudicated, and the registered
# test's driver is what compares them.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_bra_displacement", declaredCaseSites)
echo caseSiteLine("executed", "t_bra_displacement", executedSites)
echo caseSiteLine("off-green-path", "t_bra_displacement",
                  declaredOffGreenPathSites)

if failures.len == 0:
  echo "t_bra_displacement: ", passCount, " cases passed"
  quit(0)
else:
  echo "t_bra_displacement: ", failures.len, " of ", passCount + failures.len,
       " cases failed"
  for f in failures:
    echo "  FAILED  ", f
  quit(1)
