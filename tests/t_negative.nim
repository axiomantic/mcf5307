## `t_negative` - the negative corpus. Encodings the core must refuse, and the
## legal neighbours it must still execute.
##
##   The refused encodings: `DBRA`, `EXG`,
##   `ROL`, a memory shift, `MOVEM -(An)`, byte arithmetic, word arithmetic
##   apart from `MULS.W`, `MULU.W`, `DIVS.W` and `DIVU.W`, and `Bcc` with an
##   8-bit displacement of `0xFF`. Each is placed at the reset program counter
##   and run through the shipped path, and the whole machine state is compared
##   rather than the fault bit alone.
##
##   The legal neighbours, and why a negative corpus is worthless without
##   them. "This encoding is refused" is satisfied by a core that refuses
##   everything, so a corpus of refusals alone passes against a decoder that
##   is broadly broken, and passes in exactly the way it passes when the core
##   is right. Every refused encoding here therefore names a neighbour: a
##   legal encoding one field away from it, which the core must still execute.
##   A decoder that over-refuses reddens on the neighbour in the same run that
##   it stays green on the refusal.
##
##   The four 16-bit multiply and divide forms are neighbours of exactly this
##   kind: they are carved out of the same "word arithmetic must trap" clause
##   that puts `ADD.W` in the trap set, so they are the sharpest available
##   control on that clause. A negative case that asserts a trap for a legal
##   instruction pins a defect, and `MULS.W`, `MULU.W`, `DIVS.W` and `DIVU.W`
##   are where that standard bites.
##
##   The pairing and the oracle are themselves asserted, not left to
##   convention. A refusal added without a neighbour, and a case whose
##   recorded assembler evidence contradicts its own expected outcome, are
##   both adjudicated below. Without those two the corpus could drift back
##   into a list of refusals whose only oracle is what somebody believed.
##
## The expected values are not transcribed. Each
## encoding in `conformance/corpus/negative_00.json` was emitted by
## `m68k-elf-as`, not hand-assembled, and the same tool decides which class a
## case belongs to: every refused encoding assembles for `-m68000` (or, for
## the `0xFF` displacement, `-mcpu=68020`) and is rejected for `-mcpu=5307`,
## and every neighbour is accepted for `-mcpu=5307`. The partition is the
## assembler's and not this project's, which is what keeps the corpus from
## being a transcription of a belief about the part.
##
## What this suite does not assert, stated so its silence is not read as
## coverage. A neighbour is adjudicated on whether it was refused and never on
## what it computed. The arithmetic and the condition codes of these
## instructions belong to `t_alu`, `t_logic`, `t_move` and the positive
## corpora, and repeating them here would be a second home for a fact with an
## owner.
##
## How the ground is divided with `t_lines`: that suite owns the line-A and
## line-F opcode spaces, exhaustively - space this core declines to claim - and
## this suite is the removed 68000 instructions, which live in lines the core
## does claim and decode. No encoding here is in line A or line F.

import std/json
import std/strutils
import std/tables

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
  ## The call site is recorded twice - once at compile time into
  ## `declaredSites` by the `static` below, and once at run time into
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, got, want, label)

# ---------------------------------------------------------------------------
# The corpus.
#
# It is read at compile time and named in full. A glob resolved at run time
# that matched nothing would leave this suite adjudicating an empty table and
# reporting a pass, which is the one failure shape a negative corpus must not
# have. `staticRead` of a named path fails the compile when the file is
# absent, so the loud form is the one that costs nothing here.

const corpusText = staticRead("../conformance/corpus/negative_00.json")

let corpus = parseJson(corpusText)

check((format: corpus["format"].getInt, group: corpus["group"].getStr),
      (format: 1, group: "negative"),
      "the corpus file is the negative corpus, in the schema this suite reads")

type Case = object
  name: string
  instruction: string
  words: seq[uint16]
  isTrap: bool
  neighbour: string
  acceptedBy: seq[string]
  rejectedBy: seq[string]

proc loadCases(node: JsonNode): seq[Case] =
  for entry in node["cases"]:
    var c = Case(
      name: entry["name"].getStr,
      instruction: entry["instruction"].getStr,
      isTrap: entry["outcome"].getStr == "trap",
      neighbour: (if entry["neighbour"].kind == JNull: ""
                  else: entry["neighbour"].getStr))
    for word in entry["encoding"]:
      c.words.add(uint16(parseHexInt(word.getStr)))
    for arch in entry["oracle"]["accepted_by"]:
      c.acceptedBy.add(arch.getStr)
    for arch in entry["oracle"]["rejected_by"]:
      c.rejectedBy.add(arch.getStr)
    result.add(c)

let cases = loadCases(corpus)

let seedRegs = corpus["seed"]["regs"]

# ---------------------------------------------------------------------------
# The board. One flat byte array, big-endian, as `tests/t_lines.nim`'s and the
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
# The runner. It is `tests/t_lines.nim`'s, for the reason that file gives: a
# pass here has to be a pass of the shipped path - `mcf5307_reset`,
# `mcf5307_set_reg`, `mcf5307_exec`, `mcf5307_get_reg` - and not of an
# internal helper reached around the back.
#
# The address register points at real memory, and that is load-bearing rather
# than incidental. Two of the refused encodings take an operand through `(A0)`
# - the memory shift and the predecrement `MOVEM`. Seeded with an unmapped
# address, a core that wrongly executed either of them would take a bus fault,
# arrive at `fault` and `halted` by the wrong road, and satisfy the trap
# assertion. A mapped A0 removes that road, so the only way to reach the
# expected state is the refusal this suite is about.

let
  execBase = uint32(seedRegs["pc"].getInt)
  stackBase = uint32(seedRegs["a7"].getInt)
  seedD0 = uint32(seedRegs["d0"].getInt)
  seedD1 = uint32(seedRegs["d1"].getInt)
  seedA0 = uint32(seedRegs["a0"].getInt)
  srBase = uint32(seedRegs["sr"].getInt)

type Outcome = object
  cycles: uint32
  fault: bool
  halted: bool
  d0: uint32
  d1: uint32
  a0: uint32
  a7: uint32
  sr: uint32
  pc: uint32

proc runCase(c: Case): Outcome =
  ## Place one encoding at the reset program counter, seed the registers, and
  ## run one `mcf5307_exec`.
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  for index, word in c.words:
    boardWrite(board, execBase + uint32(index * 2), 2, uint32(word))

  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, stackBase, execBase)
  discard mcf5307_set_reg(ctx, 0, seedD0)
  discard mcf5307_set_reg(ctx, 1, seedD1)
  discard mcf5307_set_reg(ctx, 8, seedA0)
  # The status register is set last: `mcf5307_reset` writes it, so an earlier
  # write would be overwritten.
  discard mcf5307_set_reg(ctx, 16, srBase)

  result.cycles = mcf5307_exec(ctx, 1'u32)
  result.fault = ctx.fault
  result.halted = ctx.halted
  result.d0 = mcf5307_get_reg(ctx, 0)
  result.d1 = mcf5307_get_reg(ctx, 1)
  result.a0 = mcf5307_get_reg(ctx, 8)
  result.a7 = mcf5307_get_reg(ctx, 15)
  result.sr = mcf5307_get_reg(ctx, 16)
  result.pc = mcf5307_get_reg(ctx, 17)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# The decoder's answer, asked of the legal encodings only. The asymmetry is
# deliberate and it is the one place this suite declines to make a claim.
#
# Refusal in this core is not decided in one place, which is measured and not
# assumed. Of the refused encodings here, `decodeWord` returns
# `opIllegal` for one. The others reach an operation and are refused by
# an executor arm instead - `cpu.nim` documents that contract for each group,
# naming an illegal size, an illegal effective address and the 32-bit branch
# displacement - and two of them are refused under an alias, the encoding
# being read as a legal opcode at a size this part does not have. So "which
# layer refuses this encoding" is a fact about how the core is built, and a
# per-case expectation for it would be a transcription of the implementation
# rather than a requirement the part imposes. This suite asserts the
# requirement, which is that the encoding does not execute, and the machine
# runs below are where it does that.
#
# The converse is a requirement and is asserted. A legal encoding must reach
# an operation, whatever later does with it, and a decoder that answered
# `opIllegal` for one has refused it at the first layer and cannot execute it
# at any. That claim needs no knowledge of the core's internal division, so
# it is a second and independent detector of the over-refusal this suite
# exists to catch.

for c in cases:
  if not c.isTrap:
    check((name: c.name, reachesAnOperation: decodeWord(c.words[0]).op != opIllegal),
          (name: c.name, reachesAnOperation: true),
          "the decoder reaches an operation for " & c.instruction)

# The whole machine is compared for a refusal and not the fault bit. An
# encoding that executed would write a register, move the stack pointer or set
# a condition code, and those are the fields this tuple carries. The seeds are
# non-zero for the same reason: a register compared at zero against zero
# asserts nothing.
#
# The program counter is past the first word. The core advances it over the
# word it fetched before it decides what the word was, so a refused encoding
# leaves the machine pointing at the next word and halted, and never at a
# branch target - which is what separates a refused `DBRA` or `Bcc` from an
# executed one.

let wantTrap = (cycles: 0'u32, fault: true, halted: true,
                d0: seedD0, d1: seedD1, a0: seedA0, a7: stackBase,
                sr: srBase, pc: execBase + 2'u32)

for c in cases:
  if c.isTrap:
    let got = runCase(c)
    check((cycles: got.cycles, fault: got.fault, halted: got.halted,
           d0: got.d0, d1: got.d1, a0: got.a0, a7: got.a7, sr: got.sr,
           pc: got.pc),
          wantTrap,
          "the machine refuses " & c.instruction)

# The neighbour is adjudicated on refusal alone. `executed` is the cycle count
# having moved: a refusal spends none. The three fields together are the whole
# of the distinction between "the core ran this" and "the core declined it",
# which is the only question this suite asks of a legal encoding.

for c in cases:
  if not c.isTrap:
    let got = runCase(c)
    check((fault: got.fault, halted: got.halted, executed: got.cycles > 0'u32),
          (fault: false, halted: false, executed: true),
          "the machine executes the legal neighbour " & c.instruction)

# ---------------------------------------------------------------------------
# The pairing. Every refusal names a legal neighbour, and the neighbour is in
# this corpus and is itself adjudicated as executing.
#
# Without this the pairing is a convention and a convention decays silently. A
# refusal added with no neighbour leaves the corpus one control short and
# nothing else in this file would notice: its own case would pass, the case
# total would rise by one as an addition should, and the suite would report a
# clean run while the property the pairing exists to buy had weakened.

var byName = initTable[string, Case]()
for c in cases:
  byName[c.name] = c

var unpaired = 0
var dangling = 0
var paired = 0
for c in cases:
  if not c.isTrap:
    continue
  if c.neighbour.len == 0:
    inc unpaired
  elif not byName.hasKey(c.neighbour) or byName[c.neighbour].isTrap:
    inc dangling
  else:
    inc paired

check((unpaired: unpaired, dangling: dangling, paired: paired),
      (unpaired: 0, dangling: 0, paired: 8),
      "every refused encoding names a legal neighbour that this corpus runs")

# ---------------------------------------------------------------------------
# The oracle, held against the outcome each case claims.
#
# This is the check that refuses to pin a defect. A negative case that asserts
# a trap for a legal instruction is not a weak case, it is a case that pins a
# defect. The assembler's verdict is
# recorded per case, so the corpus can be held to that standard mechanically -
# an encoding `-mcpu=5307` accepts may not be labelled a refusal, and an
# encoding it rejects may not be labelled a neighbour. Relabelling `MULS.W` as
# a refusal is red here on its own evidence.

const part = "-mcpu=5307"

var oracleViolations = 0
var trapCount = 0
var executeCount = 0
for c in cases:
  if c.isTrap:
    inc trapCount
    if part notin c.rejectedBy or part in c.acceptedBy:
      inc oracleViolations
  else:
    inc executeCount
    if part notin c.acceptedBy or part in c.rejectedBy:
      inc oracleViolations

check((traps: trapCount, executes: executeCount, violations: oracleViolations),
      (traps: 8, executes: 11, violations: 0),
      "the assembler's verdict agrees with the outcome every case claims")

# The registry lines. They are data and not a verdict: this program reports
# what its text declares and what its run adjudicated, and the registered
# test's driver is what compares them - and what compares the declared count
# against the call sites in this file. A verdict printed here would be a
# self-assessment, and a run that stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_negative", declaredCaseSites)
echo caseSiteLine("executed", "t_negative", executedSites)
echo caseSiteLine("off-green-path", "t_negative", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_negative: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_negative: ", passCount, " cases passed"
