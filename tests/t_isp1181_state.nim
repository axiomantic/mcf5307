## `t_isp1181_state` - the SOF tick and the ISP1181 state block.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import std/algorithm
import std/strutils
import std/times

import isp1181/state
import isp1181/stub

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
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, ok, label, got, want)

# ---------------------------------------------------------------------------
# The host side. The state entry points must not call back into the host, and a
# count alone cannot say what a call carried.

var irqCalls = 0
var txCalls = 0

proc recordIrq(user: pointer; asserted: cint) {.cdecl.} =
  inc irqCalls

proc recordTx(user: pointer; endpoint: cint; data: ptr uint8;
              length: csize_t) {.cdecl.} =
  inc txCalls

var hostToken = 0xC0FFEE

proc fresh(): ISP1181Ctx =
  isp1181_create(addr hostToken, recordIrq, recordTx)

# THE MODULUS IS THIS FILE's OWN HAND-WRITTEN LITERAL and never the module's
# constant. A test that imported the constant would move with it under mutation
# and would assert that the code agrees with itself.
const frameModulus = 2048

# ---------------------------------------------------------------------------
# BLOCK 1. The tick advances the USB frame counter.
#
# THE COUNTER'S NO-OP VALUE IS ZERO, WHICH IS WHY A FIRST-MISMATCH ASSERTION IS
# NOT ENOUGH ON ITS OWN. A tick that never advanced reads 0, and so does one
# that completed a full cycle.

type FrameWalk = tuple[start: uint16, firstMismatch: string, ticks: int,
                       maxSeen: uint16, final: uint16]

proc walkTicks(handle: ISP1181Ctx; ticks: int): FrameWalk =
  let start = frameNumber(handle)
  var firstMismatch = ""
  var maxSeen = start
  var taken = 0
  for step in 1 .. ticks:
    isp1181_tick(handle, 1'u32)
    let seen = frameNumber(handle)
    inc taken
    if seen > maxSeen:
      maxSeen = seen
    let want = uint16((int(start) + step) mod frameModulus)
    if seen != want and firstMismatch.len == 0:
      firstMismatch = "tick " & $step & " read " & $seen & ", want " & $want
  (start: start, firstMismatch: firstMismatch, ticks: taken, maxSeen: maxSeen,
   final: frameNumber(handle))

let cycleCtx = fresh()
let cycle = walkTicks(cycleCtx, frameModulus)
const wantCycle: FrameWalk = (start: 0'u16, firstMismatch: "", ticks: 2048,
                              maxSeen: 2047'u16, final: 0'u16)
check(cycle == wantCycle,
      "tick: one full cycle of single-frame ticks advances by exactly one per " &
        "tick and ends where it began",
      $cycle, $wantCycle)

type Wrap = tuple[before: uint16, after: uint16]

let wrapCtx = fresh()
isp1181_tick(wrapCtx, 2047'u32)
let wrapBefore = frameNumber(wrapCtx)
isp1181_tick(wrapCtx, 1'u32)
let wrapSeen: Wrap = (before: wrapBefore, after: frameNumber(wrapCtx))
const wantWrap: Wrap = (before: 2047'u16, after: 0'u16)
check(wrapSeen == wantWrap,
      "tick: a counter at 2047 advanced by one frame reads 0",
      $wrapSeen, $wantWrap)

# THE COUNT FORM AND THE REPEATED FORM AGREE, which is the property a state
# restore and a fast-forward both need. EVERY `want` BELOW IS HAND-WRITTEN:
# comparing the two forms against each other alone would pass for any modulus
# they happened to share, including no modulus at all.
type BulkRow = tuple[start: uint32, frames: uint32, want: uint16]

const bulkRows: array[7, BulkRow] = [
  (start: 0'u32, frames: 5'u32, want: 5'u16),
  (start: 0'u32, frames: 0'u32, want: 0'u16),
  (start: 2045'u32, frames: 5'u32, want: 2'u16),
  (start: 0'u32, frames: 2048'u32, want: 0'u16),
  (start: 0'u32, frames: 2049'u32, want: 1'u16),
  (start: 2000'u32, frames: 100'u32, want: 52'u16),
  (start: 1'u32, frames: 4095'u32, want: 0'u16)]

type BulkOutcome = tuple[rows: int, firstBad: string]

proc runBulk(): BulkOutcome =
  var firstBad = ""
  var rows = 0
  for row in bulkRows:
    let bulkCtx = fresh()
    isp1181_tick(bulkCtx, row.start)
    isp1181_tick(bulkCtx, row.frames)
    let bulk = frameNumber(bulkCtx)

    let singleCtx = fresh()
    isp1181_tick(singleCtx, row.start)
    for _ in 1'u32 .. row.frames:
      isp1181_tick(singleCtx, 1'u32)
    let singles = frameNumber(singleCtx)

    inc rows
    if (bulk != row.want or singles != row.want) and firstBad.len == 0:
      firstBad = "start " & $row.start & " + " & $row.frames & " -> bulk " &
        $bulk & ", singles " & $singles & ", want " & $row.want
    isp1181_destroy(bulkCtx)
    isp1181_destroy(singleCtx)
  (rows: rows, firstBad: firstBad)

const wantBulk: BulkOutcome = (rows: 7, firstBad: "")
let bulkOutcome = runBulk()
check(bulkOutcome == wantBulk,
      "tick: one call of N frames equals N calls of one, at and across the wrap",
      $bulkOutcome, $wantBulk)

type WallClock = tuple[moved: bool, spun: bool, counter: uint16]

proc driveWallClock(): WallClock =
  let handle = fresh()
  isp1181_tick(handle, 7'u32)
  let started = epochTime()
  var calls = 0
  while epochTime() - started < 0.002:
    isp1181_tick(handle, 0'u32)
    inc calls
  result = (moved: epochTime() - started >= 0.002, spun: calls > 0,
            counter: frameNumber(handle))
  isp1181_destroy(handle)

let wallClockSeen = driveWallClock()
const wantWallClock: WallClock = (moved: true, spun: true, counter: 7'u16)
check(wallClockSeen == wantWallClock,
      "tick: zero frames over a measured wall-clock interval leaves the " &
        "counter where the frames left it",
      $wallClockSeen, $wantWallClock)

type NilTick = tuple[counter: uint16, irq: int, tx: int]

let nilHandle: ISP1181Ctx = nil
isp1181_tick(nilHandle, 5'u32)
let nilTick: NilTick = (counter: frameNumber(nilHandle), irq: irqCalls,
                        tx: txCalls)
const wantNilTick: NilTick = (counter: 0'u16, irq: 0, tx: 0)
check(nilTick == wantNilTick,
      "tick: a nil handle is answered and neither host callback fires",
      $nilTick, $wantNilTick)

# ---------------------------------------------------------------------------
# BLOCK 2. The block's size and its layout.

const headerBytes = 12
const checksumBytes = 4
const payloadBytes = 3

let sizeSeen = int(isp1181_state_size())
const wantSize = headerBytes + payloadBytes + checksumBytes
check(sizeSeen == wantSize,
      "size: the block is the header, the payload and the checksum",
      $sizeSeen, $wantSize)

let layoutSeen = isp1181StateLayout()
let wantLayout = @[("backend", 1), ("frameNumber", 2), ("model", 0)]
check(layoutSeen == wantLayout,
      "layout: the payload carries the declared fields at the declared widths",
      $layoutSeen, $wantLayout)

# ---------------------------------------------------------------------------
# BLOCK 3. The bytes the save writes.

proc blockHex(buf: openArray[uint8]): string =
  var parts: seq[string]
  for b in buf:
    parts.add(toHex(b))
  parts.join(" ")

proc fnv1a(buf: openArray[uint8]; upTo: int): uint32 =
  ## THIS FILE's OWN FNV-1a, written out here rather than imported. An
  ## independent implementation of a published algorithm is not the module
  ## agreeing with itself.
  result = 2166136261'u32
  for index in 0 ..< upTo:
    result = (result xor uint32(buf[index])) * 16777619'u32

proc saveOf(handle: ISP1181Ctx): seq[uint8] =
  result = newSeq[uint8](wantSize)
  isp1181_state_save(handle, addr result[0])

# `0x49 0x53 0x50 0x31` is `ISP1`, the block's own magic, written out byte by
# byte rather than as a word.
const magicBytes = @[0x49'u8, 0x53'u8, 0x50'u8, 0x31'u8]

let bytesCtx = fresh()
setBackend(bytesCtx, FullModel)
isp1181_tick(bytesCtx, 0x0234'u32)

var wantBlock = magicBytes &
  @[0x00'u8, 0x00'u8, 0x00'u8, 0x01'u8] &     # version
  @[0x00'u8, 0x00'u8, 0x00'u8, 0x03'u8] &     # payload width
  @[0x01'u8] &                                # backend: FullModel
  @[0x02'u8, 0x34'u8]                         # frame number, big-endian
let wantChecksum = fnv1a(wantBlock, wantBlock.len)
wantBlock.add([uint8((wantChecksum shr 24) and 0xFF'u32),
               uint8((wantChecksum shr 16) and 0xFF'u32),
               uint8((wantChecksum shr 8) and 0xFF'u32),
               uint8(wantChecksum and 0xFF'u32)])

let savedBlock = saveOf(bytesCtx)
check(blockHex(savedBlock) == blockHex(wantBlock),
      "save: the block is the magic, the version, the width, the payload and " &
        "the checksum, byte for byte",
      blockHex(savedBlock), blockHex(wantBlock))

# ---------------------------------------------------------------------------
# BLOCK 4. The round trip goes through the byte buffer and into a DIFFERENT
# handle.

type Restored = tuple[backend: string, counter: uint16, status: string]

proc roundTrip(sourceBackend: ISP1181Backend; frames: uint32;
               destBackend: ISP1181Backend; destFrames: uint32): Restored =
  let source = fresh()
  setBackend(source, sourceBackend)
  isp1181_tick(source, frames)
  let blockBytes = saveOf(source)

  let dest = fresh()
  setBackend(dest, destBackend)
  isp1181_tick(dest, destFrames)
  let status = isp1181Restore(dest, addr blockBytes[0])
  result = (backend: $backend(dest), counter: frameNumber(dest),
            status: $status)
  isp1181_destroy(source)
  isp1181_destroy(dest)

let tripSeen = roundTrip(FullModel, 1234'u32, Stub, 77'u32)
const wantTrip: Restored = (backend: "FullModel", counter: 1234'u16,
                            status: "isp1181StateOk")
check(tripSeen == wantTrip,
      "round trip: a block written by save restores the selector and the " &
        "counter into a different handle",
      $tripSeen, $wantTrip)

type TripRow = tuple[src: ISP1181Backend, frames: uint32, want: Restored]

const tripRows: array[4, TripRow] = [
  (src: Stub, frames: 0'u32,
   want: (backend: "Stub", counter: 0'u16, status: "isp1181StateOk")),
  (src: Stub, frames: 2047'u32,
   want: (backend: "Stub", counter: 2047'u16, status: "isp1181StateOk")),
  (src: FullModel, frames: 2048'u32,
   want: (backend: "FullModel", counter: 0'u16, status: "isp1181StateOk")),
  (src: FullModel, frames: 4095'u32,
   want: (backend: "FullModel", counter: 2047'u16, status: "isp1181StateOk"))]

type TripOutcome = tuple[rows: int, firstBad: string]

proc runTrips(): TripOutcome =
  var firstBad = ""
  var rows = 0
  for row in tripRows:
    # THE DESTINATION IS ALWAYS THE OTHER BACKEND AND A COUNTER THAT IS NOT
    # THE SOURCE'S.
    let dest = if row.src == Stub: FullModel else: Stub
    let seen = roundTrip(row.src, row.frames, dest, 999'u32)
    inc rows
    if seen != row.want and firstBad.len == 0:
      firstBad = $row.src & " + " & $row.frames & " -> " & $seen & ", want " &
        $row.want
  (rows: rows, firstBad: firstBad)

const wantTrips: TripOutcome = (rows: 4, firstBad: "")
let tripsOutcome = runTrips()
check(tripsOutcome == wantTrips,
      "round trip: the restore is exact for both selectors at and across the " &
        "wrap",
      $tripsOutcome, $wantTrips)

# ---------------------------------------------------------------------------
# BLOCK 5. A perturbed block is refused BY NAME and changes nothing.

type Perturbation = tuple[tried: int, accepted: int, touched: int,
                          statuses: string]

proc perturbEveryByte(): Perturbation =
  let source = fresh()
  setBackend(source, FullModel)
  isp1181_tick(source, 1000'u32)
  let clean = saveOf(source)

  var tried = 0
  var accepted = 0
  var touched = 0
  var seenStatuses: seq[string]
  for index in 0 ..< clean.len:
    var damaged = clean
    damaged[index] = damaged[index] xor 0xFF'u8

    let dest = fresh()
    isp1181_tick(dest, 55'u32)
    let status = isp1181Restore(dest, addr damaged[0])
    inc tried
    if status == isp1181StateOk:
      inc accepted
    if $backend(dest) != "Stub" or frameNumber(dest) != 55'u16:
      inc touched
    if not seenStatuses.contains($status):
      seenStatuses.add($status)
    isp1181_destroy(dest)
  isp1181_destroy(source)
  seenStatuses.sort()
  (tried: tried, accepted: accepted, touched: touched,
   statuses: seenStatuses.join(" "))

const wantPerturbation: Perturbation = (
  tried: 19, accepted: 0, touched: 0,
  statuses: "isp1181StateBadChecksum isp1181StateBadMagic " &
    "isp1181StateBadVersion isp1181StateBadWidth")
let perturbation = perturbEveryByte()
check(perturbation == wantPerturbation,
      "negative: every single-byte perturbation of the block is refused by " &
        "name and leaves the handle exactly as it was",
      $perturbation, $wantPerturbation)

# THE C ENTRY POINT DROPS THE NAME AND MUST STILL REFUSE. A `void` signature
# leaves a C caller with the state it already had, which is only true if the
# refusal precedes the decode.
type CRefusal = tuple[backend: string, counter: uint16]

proc driveCRefusal(): CRefusal =
  let source = fresh()
  setBackend(source, FullModel)
  isp1181_tick(source, 300'u32)
  var damaged = saveOf(source)
  damaged[0] = damaged[0] xor 0xFF'u8

  let dest = fresh()
  isp1181_tick(dest, 12'u32)
  isp1181_state_load(dest, addr damaged[0])
  result = (backend: $backend(dest), counter: frameNumber(dest))
  isp1181_destroy(source)
  isp1181_destroy(dest)

let cRefusal = driveCRefusal()
const wantCRefusal: CRefusal = (backend: "Stub", counter: 12'u16)
check(cRefusal == wantCRefusal,
      "negative: the C load entry point refuses a damaged block without " &
        "touching the handle",
      $cRefusal, $wantCRefusal)

# A BLOCK WHOSE VERSION IS A DIFFERENT WHOLE NUMBER IS REFUSED BY VERSION AND
# NOT BY CHECKSUM. The sweep above flips one byte and the checksum catches most
# of what it produces; this case rewrites the version AND repairs the checksum,
# so only the version check can refuse it.
proc driveWrongVersion(): string =
  let source = fresh()
  isp1181_tick(source, 8'u32)
  var block2 = saveOf(source)
  block2[7] = 0x02'u8
  let repaired = fnv1a(block2, headerBytes + payloadBytes)
  block2[15] = uint8((repaired shr 24) and 0xFF'u32)
  block2[16] = uint8((repaired shr 16) and 0xFF'u32)
  block2[17] = uint8((repaired shr 8) and 0xFF'u32)
  block2[18] = uint8(repaired and 0xFF'u32)

  let dest = fresh()
  result = $isp1181Restore(dest, addr block2[0])
  isp1181_destroy(source)
  isp1181_destroy(dest)

let wrongVersion = driveWrongVersion()
const wantWrongVersion = "isp1181StateBadVersion"
check(wrongVersion == wantWrongVersion,
      "negative: a block carrying another version with a repaired checksum " &
        "is refused by version",
      wrongVersion, wantWrongVersion)

proc driveBadBackend(): tuple[status: string, backend: string] =
  let source = fresh()
  isp1181_tick(source, 9'u32)
  var block3 = saveOf(source)
  block3[12] = 0x7F'u8
  let repaired = fnv1a(block3, headerBytes + payloadBytes)
  block3[15] = uint8((repaired shr 24) and 0xFF'u32)
  block3[16] = uint8((repaired shr 16) and 0xFF'u32)
  block3[17] = uint8((repaired shr 8) and 0xFF'u32)
  block3[18] = uint8(repaired and 0xFF'u32)

  let dest = fresh()
  let status = $isp1181Restore(dest, addr block3[0])
  result = (status: status, backend: $backend(dest))
  isp1181_destroy(source)
  isp1181_destroy(dest)

let badBackend = driveBadBackend()
const wantBadBackend = (status: "isp1181StateBadField", backend: "Stub")
check(badBackend == wantBadBackend,
      "negative: a payload byte naming no enumerator is refused before the " &
        "decode",
      $badBackend, $wantBadBackend)

# ---------------------------------------------------------------------------
# BLOCK 6. Nil arguments are answered and are not aborts.

type NilState = tuple[size: int, nilCtxStatus: string, nilSrcStatus: string,
                      irq: int, tx: int]

proc driveNilState(): NilState =
  let handle: ISP1181Ctx = nil
  var scratch = newSeq[uint8](wantSize)
  isp1181_state_save(handle, addr scratch[0])
  let live = fresh()
  isp1181_state_save(live, nil)
  isp1181_state_load(handle, nil)
  let outcome = (size: int(isp1181_state_size()),
                 nilCtxStatus: $isp1181Restore(handle, addr scratch[0]),
                 nilSrcStatus: $isp1181Restore(live, nil),
                 irq: irqCalls, tx: txCalls)
  isp1181_destroy(live)
  outcome

let nilState = driveNilState()
const wantNilState: NilState = (size: 19,
                                nilCtxStatus: "isp1181StateNilArgument",
                                nilSrcStatus: "isp1181StateNilArgument",
                                irq: 0, tx: 0)
check(nilState == wantNilState,
      "nil: the size answers, the save and the load refuse by name and " &
        "neither host callback fires",
      $nilState, $wantNilState)

isp1181_destroy(cycleCtx)
isp1181_destroy(wrapCtx)
isp1181_destroy(bytesCtx)

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this program reports what
# its text declares and what its run adjudicated, and the registered test's
# driver is what compares them.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_isp1181_state", declaredCaseSites)
echo caseSiteLine("executed", "t_isp1181_state", executedSites)
echo caseSiteLine("off-green-path", "t_isp1181_state", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_isp1181_state: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_isp1181_state: ", passCount, " cases passed"
