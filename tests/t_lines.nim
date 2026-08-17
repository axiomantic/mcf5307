## `t_lines` - the line-A and line-F opcode spaces of `mcf5307/lines`, and the
## core's refusal to execute either of them. Task CPU-12. Design section 6.1.
##
## WHAT THIS SUITE ASSERTS, AND WHY EACH GROUP EXISTS.
##
##   THE TWO SPACES. `mcf5307/lines` is the one place that says which words
##   belong to the two unimplemented-line spaces. Each space is asserted at its
##   first word, at its last word, and at the word immediately outside each
##   end - line 9 and line B around line-A, line E around line-F. A mask
##   written one bit too wide claims a neighbouring line, and the neighbours
##   are lines other tasks own and execute.
##
##   THE FOUR NAMED ENCODINGS. The task's own row names MAC, EMAC and `MOV3Q`
##   as instructions this core must not decode, and calls line-F cache and
##   debug. Each of the encodings below is built from the bit diagram its
##   folio prints, and is asserted BOTH to be in the space this module claims
##   AND to reach no operation in the decoder. The two are separate claims:
##   one is about this module's classification and one is about the decoder's
##   answer, and neither implies the other.
##
##   THE SWEEP. Every word of the two spaces is decoded. The case asserts the
##   SIZE of the swept set beside the absence of an escape, because neither
##   field alone identifies the set: a predicate that claims nothing has no
##   escape, and a predicate that claims the right number of the wrong words
##   has the right size.
##
##   THE CORE PATH. A line-A word and a line-F word are each placed at the
##   reset program counter and run through `mcf5307_reset`, `mcf5307_set_reg`
##   and `mcf5307_exec`, which is the path a board takes. The whole machine
##   state is compared rather than the fault bit alone, because an instruction
##   that executed leaves its mark in the register file, the stack pointer and
##   the status register and not in that bit.
##
## WHERE THE EXPECTED VALUES COME FROM. The encodings are read from the
## ColdFire Family Programmer's Reference Manual, Rev. 3, as page images, at
## the folios named beside each one. The markdown transcription under
## `MCF5307UM-md/` is not a source for any value here.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import ./lines
import mcf5307/cpu
import mcf5307/decode
import mcf5307/decode_types
import mcf5307/machine

var failures: seq[string]
import ./case_sites

var passCount = 0

proc checkImpl[T](site: int; got: T; want: T; label: string) =
  if got == want:
    echo "PASSED  ", label, " = ", want
    inc passCount
    executedSites.add(site)
  else:
    echo "FAILED  ", label, ": expected ", want, ", got ", got
    failures.add(label)
    executedSites.add(site)

template check(got: untyped; want: untyped; label: string) =
  ## THE CALL SITE IS RECORDED TWICE - once at COMPILE TIME into
  ## `declaredSites` by the `static` below, and once at RUN TIME into
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, got, want, label)

# ---------------------------------------------------------------------------
# The two spaces, at each end and one word outside each end.
#
# THE NEIGHBOURS ARE NOT DECORATION. Line 9 is the SUB family, line B is CMP
# and EOR, and line E is the shifts; all three are decoded and executed by
# other tasks in this group. A predicate that reached one of them would take a
# working instruction away from the core, and the boundary words are the ones
# a mask written `0xE000` rather than `0xF000` classifies differently.

check(isLineA(0xA000'u16), true,  "0xA000 is the first word of line-A")
check(isLineA(0xAFFF'u16), true,  "0xAFFF is the last word of line-A")
check(isLineA(0x9FFF'u16), false, "0x9FFF is line 9 and not line-A")
check(isLineA(0xB000'u16), false, "0xB000 is line B and not line-A")

check(isLineF(0xF000'u16), true,  "0xF000 is the first word of line-F")
check(isLineF(0xFFFF'u16), true,  "0xFFFF is the last word of line-F")
check(isLineF(0xEFFF'u16), false, "0xEFFF is line E and not line-F")

check(isLineF(0xA000'u16), false, "line-A is not line-F")
check(isLineA(0xF000'u16), false, "line-F is not line-A")

# ---------------------------------------------------------------------------
# The named encodings. Each word is built from the `Instruction Format` bit
# diagram on the folio named beside it, and from nothing else.
#
#   MAC     CFPRM folio 5-2.  `1010 <Rx 11-9> 0 0 <Rx msb> 0 0 <Ry 3-0>`.
#           With Rx D0 and Ry D1 that is 0xA001.
#   MOV3Q   CFPRM folio 4-46. `1010 <data 11-9> 101 <ea 5-0>`. With data 001
#           and a destination of D0 that is 0xA340. The folio's own heading
#           reads `First appeared in ISA_B`, and this part is ISA_A.
#   CPUSHL  CFPRM folio 8-2.  `1111 0100 <cache 7-6> 101 <Ax 2-0>`. With the
#           data cache and A0 that is 0xF468.
#   WDEBUG  CFPRM folio 8-18. `1111 1011 11 <ea 5-0>`. With a source of (A0)
#           that is 0xFBD0.
#
# EMAC IS NAMED BY THE TASK ROW AND HAS NO ENCODING CASE, AND THE REASON IS
# THE PART RATHER THAN THIS SUITE. The MCF5307 User's Manual carries no EMAC
# anywhere, so there is no encoding of this part's for a case to be built from.

check(isLineA(0xA001'u16), true, "MAC is a line-A word")
check(decodeWord(0xA001'u16).op, opIllegal, "MAC reaches no operation")

check(isLineA(0xA340'u16), true, "MOV3Q is a line-A word")
check(decodeWord(0xA340'u16).op, opIllegal, "MOV3Q reaches no operation")

check(isLineF(0xF468'u16), true, "CPUSHL is a line-F word")
check(decodeWord(0xF468'u16).op, opIllegal, "CPUSHL reaches no operation")

check(isLineF(0xFBD0'u16), true, "WDEBUG is a line-F word")
check(decodeWord(0xFBD0'u16).op, opIllegal, "WDEBUG reaches no operation")

# ---------------------------------------------------------------------------
# The sweep. Every word of the whole 16-bit opcode space is offered to the two
# predicates, and every word either accepts is decoded.
#
# THE SIZE IS ASSERTED BESIDE THE ESCAPE AND THAT PAIRING IS THE POINT. The
# absence of an escape is satisfied by a predicate that claims nothing, and the
# size is satisfied by a predicate that claims as many of the wrong words.
# The size is two lines of 4096 words, which is what the two `Unimplemented
# line-a opcode` and `Unimplemented line-f opcode` rows of MCF5307 User's
# Manual Table 3-1, folio 3-13, and CFPRM Table 11-1, folio 11-2, are rows for.

var sweptWords = 0
var firstEscape = -1
for value in 0 .. 0xFFFF:
  let word = uint16(value)
  if isLineA(word) or isLineF(word):
    inc sweptWords
    if decodeWord(word).op != opIllegal and firstEscape < 0:
      firstEscape = value

check((swept: sweptWords, escape: firstEscape), (swept: 8192, escape: -1),
    "every word of line-A and line-F reaches no operation")

# ---------------------------------------------------------------------------
# The board. One flat byte array, big-endian, as `tests/t_control.nim`'s and
# the conformance runner's. A read outside it reports `busUnmapped`.

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
# The runner. It is `tests/t_control.nim`'s, for the reason that file gives: a
# pass here has to be a pass of the SHIPPED path - `mcf5307_reset`,
# `mcf5307_set_reg`, `mcf5307_exec`, `mcf5307_get_reg` - and not of an internal
# helper reached around the back.

const
  execBase = 0x100'u32
  stackBase = 0x800'u32
  srBase = 0x2700'u32       ## the reset status register, condition codes clear
  seedD0 = 0x12345678'u32
  seedA0 = 0x0BADC0DE'u32

type Outcome = object
  cycles: uint32
  fault: bool
  halted: bool
  d0: uint32
  a0: uint32
  a7: uint32
  sr: uint32
  pc: uint32

proc runWord(word: uint16): Outcome =
  ## Place one opcode word at the reset program counter, seed the registers,
  ## and run one `mcf5307_exec`.
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  boardWrite(board, execBase, 2, uint32(word))

  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, stackBase, execBase)
  discard mcf5307_set_reg(ctx, 0, seedD0)
  discard mcf5307_set_reg(ctx, 8, seedA0)
  # The status register is set LAST: `mcf5307_reset` writes it, so an earlier
  # write would be overwritten.
  discard mcf5307_set_reg(ctx, 16, srBase)

  result.cycles = mcf5307_exec(ctx, 1'u32)
  result.fault = ctx.fault
  result.halted = ctx.halted
  result.d0 = mcf5307_get_reg(ctx, 0)
  result.a0 = mcf5307_get_reg(ctx, 8)
  result.a7 = mcf5307_get_reg(ctx, 15)
  result.sr = mcf5307_get_reg(ctx, 16)
  result.pc = mcf5307_get_reg(ctx, 17)
  mcf5307_destroy(ctx)

# THE WHOLE MACHINE IS COMPARED AND NOT THE FAULT BIT. A line-A word decoded
# as some 68000 instruction would write a register, move the stack pointer or
# set a condition code, and those are the fields this tuple carries. The seeds
# are non-zero for the same reason: a register compared at zero against zero
# asserts nothing.
#
# THE PROGRAM COUNTER IS PAST THE OPCODE WORD. The core advances it over the
# word it fetched before it decides what the word was, so a refused word leaves
# the machine pointing at the next one and halted rather than at the word that
# refused.

let wantTrap = (cycles: 0'u32, fault: true, halted: true,
                d0: seedD0, a0: seedA0, a7: stackBase, sr: srBase,
                pc: execBase + 2'u32)

let lineAOutcome = runWord(0xA001'u16)
check((cycles: lineAOutcome.cycles, fault: lineAOutcome.fault,
       halted: lineAOutcome.halted, d0: lineAOutcome.d0, a0: lineAOutcome.a0,
       a7: lineAOutcome.a7, sr: lineAOutcome.sr, pc: lineAOutcome.pc),
      wantTrap, "a line-A word traps through mcf5307_exec")

let lineFOutcome = runWord(0xF468'u16)
check((cycles: lineFOutcome.cycles, fault: lineFOutcome.fault,
       halted: lineFOutcome.halted, d0: lineFOutcome.d0, a0: lineFOutcome.a0,
       a7: lineFOutcome.a7, sr: lineFOutcome.sr, pc: lineFOutcome.pc),
      wantTrap, "a line-F word traps through mcf5307_exec")

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this program reports
# what its text declares and what its run adjudicated, and the registered
# test's driver is what compares them - and what compares the declared count
# against the call sites in this file. A verdict printed here would be a
# self-assessment, and a run that stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_lines", declaredCaseSites)
echo caseSiteLine("executed", "t_lines", executedSites)
echo caseSiteLine("off-green-path", "t_lines", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_lines: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_lines: ", passCount, " cases passed"
