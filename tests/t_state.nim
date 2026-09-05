## `t_state` - the snapshot block of `mcf5307/state`.
##
##   1. THE EXPECTED FIELD LIST IS WRITTEN BY HAND AND `stateLayout` DERIVES
##      THE OTHER SIDE FROM `MCF5307Ctx`. Holding a hand-written list against a
##      derived one is what makes a field ENTERING THE SNAPSHOT a decision
##      somebody takes, alongside the version word that moves with it.
##
##   2. THE COMPARISON IS PER FIELD AND THE DESTINATION IS PRE-LOADED.
##
## Nothing here is a fact about Motorola silicon.

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
  ## `tests/case_sites.cmake` states the rules the driver applies.
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
# a context field arriving in the snapshot visible.

const expectedLayout = @[
  ("pc", 4), ("sp", 4), ("sr", 4),
  ("dRegs", 32), ("aRegs", 28),
  ("halted", 1), ("fault", 1),
  ("irqLevel", 4), ("irqVector", 1), ("irqAutovector", 1),
  ("irq7Armed", 1), ("irq7Vector", 1), ("irq7Autovector", 1),
  ("atHandlerEntry", 1),
  ("pendingWriteFault", 1), ("pendingFaultStatus", 4),
  ("pendingStackedSr", 4), ("pendingStackedPc", 4)]

# EVERY MEASURED VALUE IS TAKEN ONCE INTO A `let` AND THE CASE READS THE `let`.
# `check` is a TEMPLATE, so an expression written into it is evaluated once for
# the verdict and again for the report. A case whose subject is the call itself -
# a load, say - would then run the operation twice and compare the second run's
# world against the first run's verdict.

let measuredLayout = stateLayout()
check(measuredLayout == expectedLayout,
      "layout: the snapshot carries these context fields at these widths",
      $measuredLayout, $expectedLayout)

let measuredSize = int(mcf5307_state_size())
check(measuredSize == 113,
      "size: header, payload and checksum",
      $measuredSize, "113")

# ---------------------------------------------------------------------------
# BLOCK 2. The header words, and the buffer every save in this file writes into.
#
# The bytes the save does NOT touch are adjudicated once, at the foot of this
# file, over every save any block here performs. `savedBlock` below is what
# surrounds each destination with filler, and BLOCK 8 states why the verdict is
# one case there rather than a result returned to each caller.

const
  blockBytes = 113
  guardBytes = 8
  filler = 0xEE'u8

proc freshContext(): MCF5307Ctx =
  new(result)

var everySaveStayedInBounds = true

proc savedBlock(ctx: MCF5307Ctx): seq[uint8] =
  ## The saved block, out of a buffer whose surrounding bytes carry filler.
  ##
  ## WHETHER THE SAVE STAYED INSIDE THE BUFFER IS ACCUMULATED INTO ONE FLAG AND
  ## NOT RETURNED TO THE CALLER. A returned flag is one a call site can drop -
  ## `let (bytes, _) = ...` reads as ordinary Nim and silently costs the whole
  ## check - and an overrun is not a property of whichever context happened to
  ## be saved at the site that remembered to read it. The verdict on the
  ## accumulated flag is at the foot of this file, after every save has run.
  var raw: array[guardBytes + blockBytes + guardBytes, uint8]
  for index in 0 ..< raw.len:
    raw[index] = filler
  mcf5307_state_save(ctx, addr raw[guardBytes])
  result = newSeq[uint8](blockBytes)
  for index in 0 ..< blockBytes:
    result[index] = raw[guardBytes + index]
  for index in 0 ..< guardBytes:
    if raw[index] != filler:
      everySaveStayedInBounds = false
    if raw[guardBytes + blockBytes + index] != filler:
      everySaveStayedInBounds = false

proc be32(bytes: seq[uint8]; at: int): uint32 =
  (uint32(bytes[at]) shl 24) or (uint32(bytes[at + 1]) shl 16) or
    (uint32(bytes[at + 2]) shl 8) or uint32(bytes[at + 3])

# THE EXPECTED HEADER IS WRITTEN OUT AND NOT READ BACK OUT OF `state`. A header
# built from `stateMagic` and `stateVersion` and compared against a header built
# from those same two names agrees with itself whatever they hold: the version
# word could move without the layout moving, and two builds would then refuse
# each other's blocks while carrying one version number. These literals are the
# format; the module is an implementation of it.
let headerProbe = savedBlock(freshContext())
let headerWords = (magic: be32(headerProbe, 0),
                   version: be32(headerProbe, 4),
                   payload: be32(headerProbe, 8))
let wantHeaderWords = (magic: 0x4D435335'u32, version: 2'u32,
                       payload: 97'u32)

check(headerWords == wantHeaderWords,
      "header: the magic, the version word and the payload width",
      $headerWords, $wantHeaderWords)

# ---------------------------------------------------------------------------
# BLOCK 3. One field at a time, through a save and a load.
#
# THE STAMP WALKS `MCF5307Ctx` RATHER THAN A LIST, so a field added to the
# context is stamped, compared and counted with no edit here. THE BOOLEANS
# ALTERNATE rather than all reading true, because a uniform stamp cannot
# separate two boolean fields from each other.
#
# THE DESTINATION IS STAMPED WITH THE OTHER SALT AND NOT LEFT FRESH. The two
# salts differ by an ODD number, so every boolean flips and
# every number moves, and no field starts the comparison already equal. THAT
# LAST SENTENCE IS A CASE BELOW AND NOT A PROMISE: a field the two stamps left
# equal would make its own round-trip case pass on `0 == 0`, whatever the module
# did with it, and reading the sentence is no way to find out that it has.
#
# THE FINAL `else` STOPS THE COMPILE, MIRRORING THE WALK. A field of a type the
# stamp has no arm for would otherwise be left at its default under BOTH salts,
# and the case comparing it would then read one default against the other.

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
    else:
      {.error: "t_state: stampContext cannot stamp this field type".}

let stamped = freshContext()
stampContext(stamped, 0'u32)
let stampedBytes = savedBlock(stamped)

let restored = freshContext()
stampContext(restored, 1'u32)

# The two stamped contexts, held against each other BEFORE any block moves
# between them. A field named here is one whose round-trip case below cannot
# fail.
var equalUnderBothSalts: seq[string]
for name, zeroValue, oneValue in fieldPairs(stamped[], restored[]):
  when zeroValue is pointer:
    discard
  elif zeroValue is Mcf5307ReadFn or zeroValue is Mcf5307WriteFn or
       zeroValue is Mcf5307IackFn:
    discard
  elif zeroValue is array:
    for index in low(zeroValue) .. high(zeroValue):
      if zeroValue[index] == oneValue[index]:
        equalUnderBothSalts.add(name & "[" & $index & "]")
  else:
    if zeroValue == oneValue:
      equalUnderBothSalts.add(name)

let noFieldEqual = newSeq[string]()
check(equalUnderBothSalts == noFieldEqual,
      "round trip: the two salts leave no field equal before the load",
      $equalUnderBothSalts, $noFieldEqual)

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
# BLOCK 3A. The byte stream itself, written out.
#
# EVERY CASE ABOVE COMPARES THE BLOCK AGAINST SOMETHING THE SAME MODULE
# PRODUCED, so all of them agree with each other under an encoding that changed
# whole. A save that switched to little-endian, reordered the payload or seeded
# its checksum differently still round-trips against itself, and a reader on
# another machine or another build gets a block it refuses while the version
# word says the format did not move.
#
# THE VECTOR IS DATA A CHECK READS, WHICH IS THE ONE GROUND ON WHICH WRITING IT
# DOWN IS ALLOWED HERE. It is the specification of the byte stream, not a record
# of a run: every byte was rebuilt from the magic string, the version, the
# payload width, the stamp rule above and a SEPARATE FNV-1a implementation, and
# only then pinned. A vector copied out of this module's own output would agree
# with whatever that output became, which is the defect this block exists to
# close and not a cheaper way to close it.
#
# THE LAST FOUR BYTES ARE WHY IT REACHES FURTHER THAN A LAYOUT ASSERTION. The
# checksum's SEED and PRIME are inside them, and nothing else in this file reads
# a checksum it did not also compute with the same constants.

const goldenStampedBlock = @[
  0x4D'u8, 0x43'u8, 0x53'u8, 0x35'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x02'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x61'u8, 0xA5'u8, 0xA5'u8, 0x00'u8, 0x01'u8,
  0xA5'u8, 0xA5'u8, 0x00'u8, 0x02'u8, 0xA5'u8, 0xA5'u8, 0x00'u8, 0x03'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x04'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x05'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x06'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x07'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x08'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x09'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x0A'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x0B'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x0C'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x0D'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x0E'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x0F'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x10'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x11'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x12'u8, 0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x01'u8, 0x15'u8, 0x56'u8, 0x01'u8, 0x00'u8, 0x59'u8, 0x00'u8, 0x01'u8,
  0x00'u8, 0xA5'u8, 0xA5'u8, 0x00'u8, 0x1D'u8, 0xA5'u8, 0xA5'u8, 0x00'u8,
  0x1E'u8, 0xA5'u8, 0xA5'u8, 0x00'u8, 0x1F'u8, 0xC1'u8, 0xED'u8, 0x85'u8,
  0x97'u8]

check(stampedBytes == goldenStampedBlock,
      "wire format: the salt-0 context saves these exact bytes",
      $stampedBytes, $goldenStampedBlock)

# ---------------------------------------------------------------------------
# BLOCK 4. A damaged block is refused, at every offset and by name.
#
# THE STATUSES ARE ASSERTED BY NAME AND NOT MERELY AS `not stateOk`. A caller
# that cannot tell a wrong version from a corrupted payload cannot tell an
# upgrade from a fault.

proc renderContext(ctx: MCF5307Ctx): string =
  ## Every field of the context, as one string.
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
                     checksum: statusAfterDamage(110))
let wantNamedStatuses = (magic: stateBadMagic,
                         version: stateBadVersion,
                         width: stateBadWidth,
                         payload: stateBadChecksum,
                         checksum: stateBadChecksum)

check(namedStatuses == wantNamedStatuses,
      "damage: each region of the block is refused under its own name",
      $namedStatuses, $wantNamedStatuses)

# The C entry point has no way to report a refusal, so a caller that ignores
# the missing channel must be left holding the state it had.
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
# BLOCK 4A. A VERSION-1 BLOCK IS REFUSED BY NAME AND IS NEVER READ.
#
# THIS IS THE CASE THE VERSION WORD EXISTS FOR, AND EVERY OTHER CASE IN THIS
# FILE IS BLIND TO IT. Version 1's payload is the same 84 bytes version 2 opens
# with: the four `pending*` fields were APPENDED, so every version-1 field sits
# at the offset version 2 reads it from. A reader that skipped the version word
# would therefore load all fourteen of the older fields CORRECTLY and take the
# four new ones from the checksum and from whatever followed the shorter block.
# There is no corruption for a checksum to notice, because the checksum of a
# version-1 block is honest - of a version-1 block.
#
# SO THE BLOCK BELOW IS A WHOLE, VALID VERSION-1 BLOCK and not a damaged version
# -2 one: 100 bytes, its own 84-byte payload width, and its own correct FNV-1a.
# It is the golden vector of the version that shipped before this one, and it
# shares its stamped register rows with `goldenStampedBlock` - which is the
# point. Only the version word and the payload width separate the two, and
# only the version word is checked before the payload is decoded.
#
# THE REFUSAL MUST BE `stateBadVersion` AND NOT `stateBadWidth`. Both are true
# of this block and `stateLoad` tests the version first, deliberately: a caller
# that is told the width is wrong learns that its block is malformed, and a
# caller that is told the version is wrong learns that its block is from an
# older build. The second is the actionable one and it is the one the reader is
# ordered to report.

const goldenVersion1Block = @[
  0x4D'u8, 0x43'u8, 0x53'u8, 0x35'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8,
  0x00'u8, 0x00'u8, 0x00'u8, 0x54'u8, 0xA5'u8, 0xA5'u8, 0x00'u8, 0x01'u8,
  0xA5'u8, 0xA5'u8, 0x00'u8, 0x02'u8, 0xA5'u8, 0xA5'u8, 0x00'u8, 0x03'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x04'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x05'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x06'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x07'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x08'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x09'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x0A'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x0B'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x0C'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x0D'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x0E'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x0F'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x10'u8, 0xC3'u8, 0xC3'u8, 0x00'u8, 0x11'u8,
  0xC3'u8, 0xC3'u8, 0x00'u8, 0x12'u8, 0x01'u8, 0x00'u8, 0x00'u8, 0x00'u8,
  0x01'u8, 0x15'u8, 0x56'u8, 0x01'u8, 0x00'u8, 0x59'u8, 0x00'u8, 0x01'u8,
  0x18'u8, 0x07'u8, 0xEA'u8, 0x85'u8]

# THE CONTEXT IS STAMPED WITH THE OTHER SALT FIRST, so that "no field moved" is
# a claim about a refusal and not about two defaults agreeing. Every field of
# this context differs from the value the version-1 block carries for it - the
# case above the round trip establishes exactly that of these two salts.
let versionVictim = freshContext()
stampContext(versionVictim, 1'u32)
let beforeVersionRefusal = renderContext(versionVictim)
let versionStatus = stateLoad(versionVictim, unsafeAddr goldenVersion1Block[0])
let afterVersionRefusal = renderContext(versionVictim)

check((status: versionStatus, state: afterVersionRefusal) ==
        (status: stateBadVersion, state: beforeVersionRefusal),
      "version: a whole version-1 block is refused by name and decoded nowhere",
      $(status: versionStatus, state: afterVersionRefusal),
      $(status: stateBadVersion, state: beforeVersionRefusal))

# THE SAVE HAS THE SAME TWO NIL ARGUMENTS AND NO STATUS TO REPORT THEM WITH, so
# what each case reads is the memory the call was pointed at.
#
# THE TWO CASES DO NOT READ THE SAME THING, and that is why there are two.
# Against a NIL CONTEXT the destination is real: the header words are written
# before the walk reaches the context at all, so a save that ran would leave
# them in the buffer and the filler below would be gone. Against a NIL
# DESTINATION there is no buffer to inspect and the content of the case is that
# it was REACHED: the alternative to the guard's `return` is a write through a
# null pointer, which ends the run rather than failing a comparison.

proc bufferAfterSave(ctx: MCF5307Ctx; toNilDestination: bool): seq[uint8] =
  var raw: array[guardBytes + blockBytes + guardBytes, uint8]
  for index in 0 ..< raw.len:
    raw[index] = filler
  if toNilDestination:
    mcf5307_state_save(ctx, nil)
  else:
    mcf5307_state_save(ctx, addr raw[guardBytes])
  result = newSeq[uint8](raw.len)
  for index in 0 ..< raw.len:
    result[index] = raw[index]

var untouchedBuffer = newSeq[uint8](guardBytes + blockBytes + guardBytes)
for index in 0 ..< untouchedBuffer.len:
  untouchedBuffer[index] = filler

let afterNilContext = bufferAfterSave(nil, false)
check(afterNilContext == untouchedBuffer,
      "damage: mcf5307_state_save writes nothing when the context is nil",
      $afterNilContext, $untouchedBuffer)

let afterNilDestination = bufferAfterSave(freshContext(), true)
check(afterNilDestination == untouchedBuffer,
      "damage: mcf5307_state_save returns when the destination is nil",
      $afterNilDestination, $untouchedBuffer)

# ---------------------------------------------------------------------------
# BLOCK 5. The block holds no pointer.
#
# A snapshot carrying an address is one that cannot be restored in another
# process.

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

let bytesA = savedBlock(withPointersA)
let bytesB = savedBlock(withPointersB)

check(bytesA == bytesB,
      "pointers: two boards with one state save the same bytes",
      $bytesA, $bytesB)

# ---------------------------------------------------------------------------
# BLOCK 6. The core itself: run, save, run on, load, run the same on again.
#
# THE INTERRUPT PRESENTATION IS MASKED AND IS THERE ON PURPOSE. Reset leaves
# the status register at 0x2700, whose interrupt priority mask is 7, so a
# level-3 presentation stays pending for the whole run and never perturbs it.

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
let snapshot = savedBlock(core)

runInstructions(core, runAfterSave)
let firstContinuation = renderContext(core)

let coreReloadStatus = stateLoad(core, unsafeAddr snapshot[0])
check(coreReloadStatus == stateOk,
      "core: the snapshot of a running core loads back into it",
      $coreReloadStatus, $stateOk)

let reloaded = savedBlock(core)

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
# BLOCK 7. The published C entry points that carry no failure channel.
#
# `mcf5307_state_load` IS DECLARED `void` IN `include/mcf5307.h`, so a C caller
# is told nothing about a refusal. The only channel left is the state of its
# own core, so that is what is read here.

let cCaller = freshCore()
runInstructions(cCaller, runBeforeSave)
let cSnapshot = savedBlock(cCaller)
let cSaved = renderContext(cCaller)

runInstructions(cCaller, runAfterSave)
mcf5307_state_load(cCaller, unsafeAddr cSnapshot[0])
let cAfterLoad = renderContext(cCaller)

check(cAfterLoad == cSaved,
      "C ABI: mcf5307_state_load restores the state the block carries",
      cAfterLoad, cSaved)

let cDamaged = perturbed(cSnapshot, 20)
runInstructions(cCaller, runAfterSave)
let cBeforeRefusal = renderContext(cCaller)
mcf5307_state_load(cCaller, unsafeAddr cDamaged[0])
let cAfterRefusal = renderContext(cCaller)

check(cAfterRefusal == cBeforeRefusal,
      "C ABI: mcf5307_state_load leaves the core alone when it refuses",
      cAfterRefusal, cBeforeRefusal)

mcf5307_destroy(cCaller)

# ---------------------------------------------------------------------------
# BLOCK 8. Every save in this file stayed inside the buffer it was given.
#
# THE PUBLISHED CALL HANDS THE CORE A RAW POINTER AND NO LENGTH, so a save that
# wrote one byte past the size it reported would be an overrun in the caller's
# memory with nothing in the C ABI able to say so. `savedBlock` surrounds every
# destination with filler and lowers the flag below when any of it moves.
#
# IT IS ONE CASE AT THE FOOT AND NOT A RESULT EACH CALLER READS, for the reason
# `savedBlock` gives: a returned flag is one a call site can drop, and the
# contexts saved in this file differ from each other in exactly the way that
# decides whether an overrun happens at all.

check(everySaveStayedInBounds,
      "bounds: every save wrote inside mcf5307_state_size and nowhere else",
      $everySaveStayedInBounds, "true")

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this
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
