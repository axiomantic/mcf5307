## `t_state` - the snapshot block of `mcf5307/state`. Task CPU-18. Design
## section 5.3.
##
## THREE CHOICES THIS FILE MAKES, AND WHY EACH ONE RATHER THAN THE OBVIOUS
## ALTERNATIVE.
##
##   1. THE EXPECTED FIELD LIST IS WRITTEN BY HAND AND `stateLayout` DERIVES
##      THE OTHER SIDE FROM `MCF5307Ctx`. A file that derived both sides would
##      agree with any walk at all. Holding a hand-written list against a
##      derived one is what makes a field ENTERING THE SNAPSHOT a decision
##      somebody takes, alongside the version word that moves with it.
##
##   2. THE COMPARISON IS PER FIELD AND THE DESTINATION IS PRE-LOADED. Save,
##      load and compare the whole context agrees with itself when BOTH
##      directions drop one field, and a destination left fresh agrees with the
##      source wherever the source happens to hold a default.
##
##   3. EVERY BYTE OFFSET IS WALKED AND NONE IS SAMPLED. A sample says nothing
##      about the offsets it did not choose, and the offsets it did not choose
##      are where an unguarded field sits.
##
## THE DOCUMENT THIS FILE CITES IS OUTSIDE THIS REPOSITORY. DESIGN SECTION 5.3
## is "State save and load" of the NMG2 emulator DESIGN DOCUMENT
## (`2026-08-04-nmg2-emulator-design.md`).
##
## MIT licensed. Nothing here is a fact about Motorola silicon.

import mcf5307/cpu
import mcf5307/decode_types
import mcf5307/irq
import mcf5307/state

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
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the five rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, ok, label, got, want)

# ---------------------------------------------------------------------------
# BLOCK 1. The field list and the size, written out.
#
# THE EXPECTED LIST IS WRITTEN BY HAND AND THE MEASURED ONE IS DERIVED FROM
# `MCF5307Ctx`. Holding a hand-written list against a derived one is what makes
# a context field arriving in the snapshot visible; a test that derived both
# sides would agree with any walk at all.

const expectedLayout = @[
  ("pc", 4), ("sp", 4), ("sr", 4),
  ("dRegs", 32), ("aRegs", 28),
  ("halted", 1), ("fault", 1),
  ("irqLevel", 4), ("irqVector", 1), ("irqAutovector", 1),
  ("irq7Armed", 1), ("irq7Vector", 1), ("irq7Autovector", 1),
  ("atHandlerEntry", 1)]

check(stateLayout() == expectedLayout,
      "layout: the snapshot carries these context fields at these widths",
      $stateLayout(), $expectedLayout)

check(int(mcf5307_state_size()) == 100,
      "size: header, payload and checksum",
      $int(mcf5307_state_size()), "100")

# ---------------------------------------------------------------------------
# BLOCK 2. The header words, and the bytes the save does not touch.
#
# THE GUARD BYTES ARE THE ASSERTION THAT `mcf5307_state_size` BOUNDS THE SAVE.
# The published call hands the core a raw pointer and no length, so a save that
# wrote one byte past the size it reported would be a buffer overrun in the
# caller's memory with nothing in the C ABI able to say so.

const
  blockBytes = 100
  guardBytes = 8

proc freshContext(): MCF5307Ctx =
  new(result)

proc saveWithGuards(ctx: MCF5307Ctx): (seq[uint8], bool) =
  ## The saved block, and whether every byte outside it kept its filler.
  var raw: array[guardBytes + blockBytes + guardBytes, uint8]
  for index in 0 ..< raw.len:
    raw[index] = 0xEE'u8
  mcf5307_state_save(ctx, addr raw[guardBytes])
  var saved = newSeq[uint8](blockBytes)
  for index in 0 ..< blockBytes:
    saved[index] = raw[guardBytes + index]
  var intact = true
  for index in 0 ..< guardBytes:
    if raw[index] != 0xEE'u8:
      intact = false
    if raw[guardBytes + blockBytes + index] != 0xEE'u8:
      intact = false
  (saved, intact)

proc be32(bytes: seq[uint8]; at: int): uint32 =
  (uint32(bytes[at]) shl 24) or (uint32(bytes[at + 1]) shl 16) or
    (uint32(bytes[at + 2]) shl 8) or uint32(bytes[at + 3])

let (headerProbe, headerGuardsIntact) = saveWithGuards(freshContext())
let headerWords = (magic: be32(headerProbe, 0),
                   version: be32(headerProbe, 4),
                   payload: be32(headerProbe, 8))
let wantHeaderWords = (magic: stateMagic, version: stateVersion,
                       payload: 84'u32)

check(headerWords == wantHeaderWords,
      "header: the magic, the version word and the payload width",
      $headerWords, $wantHeaderWords)

check(headerGuardsIntact,
      "header: the save writes inside mcf5307_state_size and nowhere else",
      $headerGuardsIntact, "true")

# ---------------------------------------------------------------------------
# BLOCK 3. One field at a time, through a save and a load.
#
# WHY A WHOLE-CONTEXT ROUND TRIP IS NOT ENOUGH ON ITS OWN. Save, load, save
# again and compare the two blocks agrees with itself whenever BOTH directions
# drop the same field, which is the single most likely way to get this wrong.
# So the stamp below writes a value of its OWN into every field, the load goes
# into a context that has never held any of them, and the comparison is per
# field.
#
# THE STAMP WALKS `MCF5307Ctx` RATHER THAN A LIST, so a field added to the
# context is stamped, compared and counted with no edit here. THE BOOLEANS
# ALTERNATE rather than all reading true, because a uniform stamp cannot
# separate two boolean fields from each other.
#
# THE DESTINATION IS STAMPED WITH THE OTHER SALT AND NOT LEFT FRESH. A fresh
# context holds every field at its default, so a field the stamp happens to
# leave at ITS default already agrees before the load and can say nothing
# about it. The two salts differ by an ODD number, so every boolean flips and
# every number moves, and no field starts the comparison already equal.

proc stampContext(ctx: MCF5307Ctx; salt: uint32) =
  var seed = 1'u32 + salt
  for name, value in fieldPairs(ctx[]):
    when value is pointer:
      discard
    elif value is Mcf5307ReadFn or value is Mcf5307WriteFn or
         value is Mcf5307IackFn:
      discard
    elif value is bool:
      value = (seed and 1'u32) == 1'u32
      seed += 1'u32
    elif value is uint8:
      value = uint8(0x40'u32 + seed)
      seed += 1'u32
    elif value is uint32:
      value = 0xA5A5_0000'u32 + seed
      seed += 1'u32
    elif value is cint:
      value = cint(0x0100'u32 + seed)
      seed += 1'u32
    elif value is array:
      for index in low(value) .. high(value):
        value[index] = 0xC3C3_0000'u32 + seed
        seed += 1'u32

let stamped = freshContext()
stampContext(stamped, 0'u32)
let (stampedBytes, _) = saveWithGuards(stamped)

let restored = freshContext()
stampContext(restored, 1'u32)
let restoreStatus = stateLoad(restored, unsafeAddr stampedBytes[0])

check(restoreStatus == stateOk,
      "round trip: an honest block loads",
      $restoreStatus, $stateOk)

for name, wantValue, gotValue in fieldPairs(stamped[], restored[]):
  when wantValue is pointer:
    discard
  elif wantValue is Mcf5307ReadFn or wantValue is Mcf5307WriteFn or
       wantValue is Mcf5307IackFn:
    discard
  else:
    check(gotValue == wantValue, "round trip: " & name,
          $gotValue, $wantValue)

# ---------------------------------------------------------------------------
# BLOCK 4. A damaged block is refused, at every offset and by name.
#
# EVERY OFFSET IS WALKED AND NOT ONE SAMPLED. A check that perturbed a byte it
# chose would say nothing about the offsets it did not choose, and the offsets
# it did not choose are exactly where an unchecked field would sit. The case
# below reports the offsets that were ACCEPTED, so a failure names them.
#
# THE STATUSES ARE ASSERTED BY NAME AND NOT MERELY AS `not stateOk`. The five
# regions fail for five different reasons and a caller that cannot tell a wrong
# version from a corrupted payload cannot tell an upgrade from a fault.

proc renderContext(ctx: MCF5307Ctx): string =
  ## Every field of the context, as one string. It is compared whole, so a
  ## refusal that touched ANY field is a failure and not a near miss.
  for name, value in fieldPairs(ctx[]):
    when value is pointer:
      discard
    elif value is Mcf5307ReadFn or value is Mcf5307WriteFn or
         value is Mcf5307IackFn:
      discard
    else:
      result.add(name & "=" & $value & " ")

proc perturbed(source: seq[uint8]; at: int): seq[uint8] =
  result = source
  result[at] = result[at] xor 0xFF'u8

var acceptedOffsets: seq[int]
var offsetsTried = 0
for at in 0 ..< blockBytes:
  let damaged = perturbed(stampedBytes, at)
  let victim = freshContext()
  if stateLoad(victim, unsafeAddr damaged[0]) == stateOk:
    acceptedOffsets.add(at)
  offsetsTried += 1

check((tried: offsetsTried, accepted: acceptedOffsets) ==
        (tried: blockBytes, accepted: newSeq[int]()),
      "damage: a perturbed byte is refused at every offset of the block",
      $(tried: offsetsTried, accepted: acceptedOffsets),
      $(tried: blockBytes, accepted: newSeq[int]()))

proc statusAfterDamage(at: int): StateStatus =
  let damaged = perturbed(stampedBytes, at)
  stateLoad(freshContext(), unsafeAddr damaged[0])

let namedStatuses = (magic: statusAfterDamage(1),
                     version: statusAfterDamage(5),
                     width: statusAfterDamage(9),
                     payload: statusAfterDamage(20),
                     checksum: statusAfterDamage(97))
let wantNamedStatuses = (magic: stateBadMagic,
                         version: stateBadVersion,
                         width: stateBadWidth,
                         payload: stateBadChecksum,
                         checksum: stateBadChecksum)

check(namedStatuses == wantNamedStatuses,
      "damage: each region of the block is refused under its own name",
      $namedStatuses, $wantNamedStatuses)

# THE REFUSAL LEAVES THE CONTEXT ALONE. The C entry point has no way to report
# a refusal, so a caller that ignores the missing channel must be left holding
# the state it had. A load that decoded first and validated afterwards would
# leave a half-loaded core behind every refusal.
let survivor = freshContext()
stampContext(survivor, 1'u32)
let beforeRefusal = renderContext(survivor)
let damagedPayload = perturbed(stampedBytes, 20)
let refusedStatus = stateLoad(survivor, unsafeAddr damagedPayload[0])
let afterRefusal = renderContext(survivor)

check((status: refusedStatus, state: afterRefusal) ==
        (status: stateBadChecksum, state: beforeRefusal),
      "damage: a refused load changes no field of the context",
      $(status: refusedStatus, state: afterRefusal),
      $(status: stateBadChecksum, state: beforeRefusal))

let nilStatuses = (noContext: stateLoad(nil, unsafeAddr stampedBytes[0]),
                   noSource: stateLoad(freshContext(), nil))
let wantNilStatuses = (noContext: stateNilArgument, noSource: stateNilArgument)

check(nilStatuses == wantNilStatuses,
      "damage: a nil context and a nil source are refused by name",
      $nilStatuses, $wantNilStatuses)

# ---------------------------------------------------------------------------
# BLOCK 5. The block holds no pointer.
#
# THE ASSERTION IS THAT THE POINTERS CANNOT REACH THE BYTES. Two contexts are
# given the same serialised state and DIFFERENT board cookies and DIFFERENT
# callbacks, and their blocks are compared byte for byte. A block that carried
# any of the four would differ, and a snapshot carrying an address is one that
# cannot be restored in another process.

proc boardReadA(user: pointer; address: uint32; size: cint;
                status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  status[] = Mcf5307BusStatus.busOk
  0'u32

proc boardReadB(user: pointer; address: uint32; size: cint;
                status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  status[] = Mcf5307BusStatus.busOk
  1'u32

proc boardWriteFn(user: pointer; address: uint32; size: cint; value: uint32;
                  status: ptr Mcf5307BusStatus) {.cdecl.} =
  status[] = Mcf5307BusStatus.busOk

proc boardIackA(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

proc boardIackB(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

var cookieA = 0x11223344'u32
var cookieB = 0x55667788'u32

let withPointersA = freshContext()
stampContext(withPointersA, 0'u32)
withPointersA.user = addr cookieA
withPointersA.readFn = boardReadA
withPointersA.writeFn = boardWriteFn
withPointersA.iackFn = boardIackA

let withPointersB = freshContext()
stampContext(withPointersB, 0'u32)
withPointersB.user = addr cookieB
withPointersB.readFn = boardReadB
withPointersB.writeFn = boardWriteFn
withPointersB.iackFn = boardIackB

let (bytesA, _) = saveWithGuards(withPointersA)
let (bytesB, _) = saveWithGuards(withPointersB)

check(bytesA == bytesB,
      "pointers: two boards with one state save the same bytes",
      $bytesA, $bytesB)

# ---------------------------------------------------------------------------
# BLOCK 6. The core itself: run, save, run on, load, run the same on again.
#
# THIS IS THE SCENARIO DESIGN SECTION 5.3 NAMES, and the two runs after the
# save are what make it bite. A snapshot that restored the registers and lost
# the program counter passes a comparison taken at the moment of the load and
# fails here at the first instruction that follows it.
#
# THE INTERRUPT PRESENTATION IS MASKED AND IS THERE ON PURPOSE. Reset leaves
# the status register at 0x2700, whose interrupt priority mask is 7, so a
# level-3 presentation stays pending for the whole run and never perturbs it -
# and the three presented fields carry values through the save that a core
# ignoring them would lose.
#
# THE COMPARISON IS THE WHOLE CONTEXT AND NOT THE REGISTERS. `renderContext`
# walks `MCF5307Ctx`, so a field this file never names is still compared.

const
  memSize = 0x1000
  execBase = 0x400'u32
  opAddqD1 = 0x5281'u16     ## `addq.l #1,%d1`, m68k-elf-as -mcpu=5307
  runBeforeSave = 4
  runAfterSave = 3

type CoreBoard = object
  bytes: array[memSize, uint8]

var coreBoard: CoreBoard

proc coreRead(user: pointer; address: uint32; size: cint;
              status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  let board = cast[ptr CoreBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return 0'u32
  status[] = Mcf5307BusStatus.busOk
  for offset in 0 ..< int(size):
    result = (result shl 8) or uint32(board.bytes[int(address) + offset])

proc coreWrite(user: pointer; address: uint32; size: cint; value: uint32;
               status: ptr Mcf5307BusStatus) {.cdecl.} =
  let board = cast[ptr CoreBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return
  status[] = Mcf5307BusStatus.busOk
  for offset in 0 ..< int(size):
    board.bytes[int(address) + offset] =
      uint8((value shr ((int(size) - 1 - offset) * 8)) and 0xFF'u32)

proc coreIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

proc freshCore(): MCF5307Ctx =
  for index in 0 ..< memSize:
    coreBoard.bytes[index] = 0'u8
  var at = int(execBase)
  while at + 1 < memSize:
    coreBoard.bytes[at] = uint8(opAddqD1 shr 8)
    coreBoard.bytes[at + 1] = uint8(opAddqD1 and 0xFF'u16)
    at += 2
  result = mcf5307_create(addr coreBoard, coreRead, coreWrite, coreIack)
  mcf5307_reset(result, 0x800'u32, execBase)
  mcf5307_set_irq(result, 3.cint, 0x45'u8, 0.cint)

proc runInstructions(ctx: MCF5307Ctx; count: int) =
  for step in 0 ..< count:
    discard mcf5307_exec(ctx, 1'u32)

let core = freshCore()
runInstructions(core, runBeforeSave)
let (snapshot, _) = saveWithGuards(core)

runInstructions(core, runAfterSave)
let firstContinuation = renderContext(core)

check(stateLoad(core, unsafeAddr snapshot[0]) == stateOk,
      "core: the snapshot of a running core loads back into it",
      $stateLoad(core, unsafeAddr snapshot[0]), $stateOk)

let (reloaded, _) = saveWithGuards(core)

check(reloaded == snapshot,
      "core: a save taken straight after the load is the block that was loaded",
      $reloaded, $snapshot)

runInstructions(core, runAfterSave)
let secondContinuation = renderContext(core)

check(secondContinuation == firstContinuation,
      "core: the same instructions after the load reach the same state",
      secondContinuation, firstContinuation)

mcf5307_destroy(core)

# ---------------------------------------------------------------------------
# BLOCK 7. The two published C entry points that carry no failure channel.
#
# `mcf5307_state_load` IS DECLARED `void` IN `include/mcf5307.h`, so a C caller
# is told nothing about a refusal. The only channel left is the state of its
# own core, so that is what is read here: after an honest block the core is
# what the block carried, and after a damaged one it is what it already was.

let cCaller = freshCore()
runInstructions(cCaller, runBeforeSave)
let (cSnapshot, _) = saveWithGuards(cCaller)
let cSaved = renderContext(cCaller)

runInstructions(cCaller, runAfterSave)
mcf5307_state_load(cCaller, unsafeAddr cSnapshot[0])

check(renderContext(cCaller) == cSaved,
      "C ABI: mcf5307_state_load restores the state the block carries",
      renderContext(cCaller), cSaved)

let cDamaged = perturbed(cSnapshot, 20)
runInstructions(cCaller, runAfterSave)
let cBeforeRefusal = renderContext(cCaller)
mcf5307_state_load(cCaller, unsafeAddr cDamaged[0])

check(renderContext(cCaller) == cBeforeRefusal,
      "C ABI: mcf5307_state_load leaves the core alone when it refuses",
      renderContext(cCaller), cBeforeRefusal)

mcf5307_destroy(cCaller)

# THE THREE REGISTRY LINES. They are DATA AND NOT A VERDICT: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_state", declaredCaseSites)
echo caseSiteLine("executed", "t_state", executedSites)
echo caseSiteLine("off-green-path", "t_state", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_state: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_state: ", passCount, " cases passed"
