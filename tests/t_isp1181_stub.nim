## `t_isp1181_stub` - the CS3 stub of the ISP1181 USB device controller. Task
## CPU-21 owns this file. Design section 9.1.
##
## DESIGN SECTION 9.1 is "Stub first" of the NMG2 emulator DESIGN DOCUMENT
## (`2026-08-04-nmg2-emulator-design.md`), and its three sentences are the
## whole specification these cases assert: the stub "accepts every write,
## returns a benign value on every read, and never raises IRQ3".
##
## THE CS3 WINDOW IS DESIGN SECTION 9.2's TABLE: base `0x13000000`, 64 KiB,
## with the data port at the base and the command port at `0x13000010`.
##
## THE STUB ANSWERS AT EVERY ADDRESS AND DECODES NOTHING. Design section 5.2.1
## gives the CS3 decode to the board - "the board returns `MCF5307_BUS_OK` for
## the whole window and the device model needs no channel" - so an address is
## an argument this model does not judge, and the cases below hold it to that
## at addresses inside the window and outside it alike.
##
## EVERY EXPECTED VALUE BELOW IS A HAND-WRITTEN LITERAL and never a second call
## of the procedure under test.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import std/strutils

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
  ## THE CALL SITE IS RECORDED TWICE - once at COMPILE TIME into
  ## `declaredSites` by the `static` below, and once at RUN TIME into
  ## `executedSites`. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies. The template
  ## exists for `instantiationInfo`: a proc cannot see where it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, ok, label, got, want)

# ---------------------------------------------------------------------------
# The window, from design section 9.2's table.

const
  cs3Base = 0x13000000'u32
  windowBytes = 0x10000        ## 64 KiB
  dataPort = 0x13000000'u32
  commandPort = 0x13000010'u32
  benignRead = 0x00'u8

# The host side. THE TWO COUNTERS AND THE TWO TRANSCRIPTS ARE THE ASSERTION
# THAT THE STUB NEVER CALLS BACK: a count alone cannot say what a call carried,
# and a stub that raised IRQ3 once would otherwise be reported as a number.

var irqCalls = 0
var irqFirst = ""
var txCalls = 0
var txFirst = ""

proc recordIrq(user: pointer; asserted: cint) {.cdecl.} =
  if irqCalls == 0:
    irqFirst = "asserted=" & $int(asserted)
  inc irqCalls

proc recordTx(user: pointer; endpoint: cint; data: ptr uint8;
              length: csize_t) {.cdecl.} =
  if txCalls == 0:
    txFirst = "endpoint=" & $int(endpoint) & " len=" & $int(length)
  inc txCalls

var hostToken = 0xC0FFEE

# ---------------------------------------------------------------------------
# BLOCK 1. The handle.
#
# A CONSTRUCTOR THAT RETURNS NOTHING IS THE SHAPE OF A LINK STUB and not of a
# device model, so the handle is asserted before anything is driven through it.

let ctx = isp1181_create(addr hostToken, recordIrq, recordTx)

check(not ctx.isNil,
      "create: the constructor returns a handle",
      $ctx.isNil, "false")

let second = isp1181_create(addr hostToken, recordIrq, recordTx)
check(not (ctx == second),
      "create: a second call returns a different handle",
      $(ctx == second), "false")
isp1181_destroy(second)

# ---------------------------------------------------------------------------
# BLOCK 2. Every read returns the benign value.
#
# THE SWEEP REPORTS THE FIRST ADDRESS THAT DISAGREED AND THE NUMBER OF READS IT
# PERFORMED, and both are asserted. The address is what separates a wrong value
# from no value; the count is what separates a clean sweep from a loop that did
# not run.

type Sweep = tuple[firstBad: string, reads: int]

proc sweepWindow(handle: ISP1181Ctx): Sweep =
  result = (firstBad: "", reads: 0)
  for offset in 0 ..< windowBytes:
    let address = cs3Base + uint32(offset)
    let value = isp1181_read(handle, address)
    inc result.reads
    if value != benignRead and result.firstBad.len == 0:
      result.firstBad = "0x" & toHex(address) & " -> 0x" & toHex(value)

const wantWindow: Sweep = (firstBad: "", reads: 65536)

let firstSweep = sweepWindow(ctx)
check(firstSweep == wantWindow,
      "read: every offset of the CS3 window answers with the benign value",
      $firstSweep, $wantWindow)

# ADDRESSES OUTSIDE THE WINDOW ARE ANSWERED TOO, which is design section
# 5.2.1's division of labour asserted rather than described: a model that
# refused them would be deciding a decode the board owns.
const outside: array[5, uint32] = [
  0x00000000'u32, 0x0000FFFF'u32, 0x12FFFFFF'u32, 0x13010000'u32,
  0xFFFFFFFF'u32]

var outsideSweep: Sweep = (firstBad: "", reads: 0)
for address in outside:
  let value = isp1181_read(ctx, address)
  inc outsideSweep.reads
  if value != benignRead and outsideSweep.firstBad.len == 0:
    outsideSweep.firstBad = "0x" & toHex(address) & " -> 0x" & toHex(value)

const wantOutside: Sweep = (firstBad: "", reads: 5)
check(outsideSweep == wantOutside,
      "read: an address outside the window answers with the benign value",
      $outsideSweep, $wantOutside)

# ---------------------------------------------------------------------------
# BLOCK 3. Every write is accepted and none of them becomes readable state.
#
# THE READ-BACK IS THE CASE AND NOT THE WRITE. A stub that stored what it was
# given and replayed it would accept every write and would present a working
# register file to the firmware, which is the plausible answer design section
# 9.1 does not authorise. Each value is written and the same address is read
# immediately afterwards.

proc sweepPort(handle: ISP1181Ctx; port: uint32): Sweep =
  result = (firstBad: "", reads: 0)
  for value in 0 .. 255:
    isp1181_write(handle, port, uint8(value))
    let seen = isp1181_read(handle, port)
    inc result.reads
    if seen != benignRead and result.firstBad.len == 0:
      result.firstBad = "wrote 0x" & toHex(uint8(value)) & " read 0x" &
        toHex(seen)

const wantPort: Sweep = (firstBad: "", reads: 256)

let commandSweep = sweepPort(ctx, commandPort)
check(commandSweep == wantPort,
      "write: every value through the command port leaves the port benign",
      $commandSweep, $wantPort)

let dataSweep = sweepPort(ctx, dataPort)
check(dataSweep == wantPort,
      "write: every value through the data port leaves the port benign",
      $dataSweep, $wantPort)

# THE WHOLE WINDOW IS WRITTEN AND THE WHOLE WINDOW IS RE-READ, so a stub that
# stored per address rather than per port is separated from one that stores
# nothing.
for offset in 0 ..< windowBytes:
  isp1181_write(ctx, cs3Base + uint32(offset), 0xFF'u8)

let afterWrites = sweepWindow(ctx)
check(afterWrites == wantWindow,
      "write: 0xFF into every offset leaves the whole window benign",
      $afterWrites, $wantWindow)

# ---------------------------------------------------------------------------
# BLOCK 4. Host traffic is accepted and produces nothing.
#
# THE ENDPOINT NUMBERS ARE DESIGN SECTION 9.3's - interrupt IN `0x81`, bulk IN
# `0x82`, bulk OUT `0x03` - together with the low endpoint numbers and one
# beyond the range the full model implements. A zero length and a nil buffer
# are driven because a caller with nothing to deliver has both.

const endpoints: array[7, int] = [0, 1, 2, 3, 15, 0x81, 0x82]
const lengths: array[3, int] = [0, 1, 64]

var payload: array[64, uint8]
for i in 0 ..< 64:
  payload[i] = uint8(i)

var rxCalls = 0
for endpoint in endpoints:
  for length in lengths:
    isp1181_rx(ctx, cint(endpoint), addr payload[0], csize_t(length))
    inc rxCalls
isp1181_rx(ctx, cint(0), nil, csize_t(0))
inc rxCalls

type RxOutcome = tuple[calls: int, window: Sweep]

let rxOutcome: RxOutcome = (calls: rxCalls, window: sweepWindow(ctx))
const wantRx: RxOutcome = (calls: 22, window: wantWindow)
check(rxOutcome == wantRx,
      "rx: traffic on every endpoint is accepted and reaches no register",
      $rxOutcome, $wantRx)

# ---------------------------------------------------------------------------
# BLOCK 5. The stub never calls the host back.
#
# "NEVER RAISES IRQ3" IS DESIGN SECTION 9.1'S OWN CLAUSE, and it is asserted
# after every access above has been driven rather than after a single one: a
# stub that raised the line on one command byte would pass a narrower drive.
# The transmit callback is held to the same rule, because a stub that invented
# a packet would be answering plausibly on a channel section 9.1 gives it no
# licence to use.

type Callback = tuple[calls: int, first: string]

let irqSeen: Callback = (calls: irqCalls, first: irqFirst)
const wantIrq: Callback = (calls: 0, first: "")
check(irqSeen == wantIrq,
      "irq: the interrupt callback did not fire on any access",
      $irqSeen, $wantIrq)

let txSeen: Callback = (calls: txCalls, first: txFirst)
const wantTx: Callback = (calls: 0, first: "")
check(txSeen == wantTx,
      "tx: the transmit callback did not fire on any access",
      $txSeen, $wantTx)

# ---------------------------------------------------------------------------
# BLOCK 6. A nil handle is answered and is not an abort.
#
# THE CALLER OF THESE ENTRY POINTS IS A PLUGIN'S HOST. Design section 5.6
# refuses an abort inside a plugin, because it destroys a session that has
# nothing to do with this model, so a nil handle has to have an answer.

let nilCtx: ISP1181Ctx = nil

check(isp1181_read(nilCtx, commandPort) == benignRead,
      "nil handle: a read answers with the benign value",
      "0x" & toHex(isp1181_read(nilCtx, commandPort)),
      "0x" & toHex(benignRead))

isp1181_write(nilCtx, commandPort, 0xF6'u8)
isp1181_rx(nilCtx, cint(1), addr payload[0], csize_t(64))
isp1181_destroy(nilCtx)

type NilOutcome = tuple[value: uint8, irq: int, tx: int]
let nilOutcome: NilOutcome = (value: isp1181_read(nilCtx, dataPort),
                              irq: irqCalls, tx: txCalls)
const wantNil: NilOutcome = (value: 0x00'u8, irq: 0, tx: 0)
check(nilOutcome == wantNil,
      "nil handle: a write, a delivery and a destroy return and change nothing",
      $nilOutcome, $wantNil)

isp1181_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 7. The three-item field specification of task CPU-21.
#
# THE FIELD SET IS ASSERTED AS A WHOLE AND NEVER FIELD BY FIELD. Item 3 of the
# specification is a NEGATIVE - no SOFTCT timer field - and a negative is only
# checkable against a CLOSED set. A per-field assertion passes with a timer
# field sitting beside the two that were asked for, which is the one outcome
# item 3 exists to refuse.
#
# SOFTCT IS A BIT AND THE BIT LIVES IN THE FULL MODEL's MODE BYTE. Nothing on
# this context advances it and nothing here is a timer.

type BackendShape = tuple[names: string, count: int]

proc backendShape(): BackendShape =
  var names = ""
  var count = 0
  for value in ISP1181Backend:
    if names.len > 0:
      names.add(" ")
    names.add($value)
    inc count
  (names: names, count: count)

const wantBackendShape: BackendShape = (names: "Stub FullModel", count: 2)

let backendSeen = backendShape()
check(backendSeen == wantBackendShape,
      "backend: the enum carries exactly Stub and FullModel, in that order",
      $backendSeen, $wantBackendShape)

let selector = isp1181_create(addr hostToken, recordIrq, recordTx)

type SelectorWalk = tuple[atCreate: string, atSet: string, atSetBack: string]

proc walkSelector(handle: ISP1181Ctx): SelectorWalk =
  # THE WALK MOVES THE SELECTOR AND MOVES IT BACK. A setter that ignored its
  # argument and a setter that latched on the first call are different defects,
  # and only the return leg separates them.
  let atCreate = $backend(handle)
  setBackend(handle, FullModel)
  let atSet = $backend(handle)
  setBackend(handle, Stub)
  (atCreate: atCreate, atSet: atSet, atSetBack: $backend(handle))

const wantSelector: SelectorWalk = (atCreate: "Stub", atSet: "FullModel",
                                    atSetBack: "Stub")

let selectorWalk = walkSelector(selector)
check(selectorWalk == wantSelector,
      "backend: a fresh handle selects the stub and the setter moves it back " &
        "and forth",
      $selectorWalk, $wantSelector)

proc ctxFieldNames(handle: ISP1181Ctx): string =
  var names: seq[string]
  for name, _ in handle[].fieldPairs:
    names.add(name)
  names.join(" ")

const wantCtxFields = "backend frameNumber model"

let ctxFields = ctxFieldNames(selector)
check(ctxFields == wantCtxFields,
      "fields: ISP1181Ctx carries exactly the declared set and no SOFTCT timer",
      ctxFields, wantCtxFields)

# ---------------------------------------------------------------------------
# BLOCK 8. The USB frame counter: 11 bits, wrapping at 2048.
#
# THE MODULUS BELOW IS THIS FILE'S OWN HAND-WRITTEN LITERAL and never the
# module's constant. A test that imported the constant would move with it under
# mutation and would assert that the code agrees with itself.
#
# THE WIDTH IS THE USB SPECIFICATION'S FRAME-NUMBER FIELD AND NOT A MEASURED
# DEVICE FACT. No ISP1181 datasheet exists on this machine.
#
# THE COUNTER'S NO-OP VALUE IS ZERO, WHICH IS WHY A FIRST-MISMATCH ASSERTION IS
# NOT ENOUGH ON ITS OWN. A counter that never advanced reads 0, and so does one
# that completed a full cycle. The cycle case therefore asserts the value at
# EVERY tick against the tick index, the highest value seen, and the number of
# ticks taken - so a counter that stood still, one that stopped early and one
# that ran past its width are three different reds.

const frameModulus = 2048       ## Hand-written. Not the module's constant.

type FrameWalk = tuple[start: uint16, firstMismatch: string, ticks: int,
                       maxSeen: uint16, final: uint16]

proc walkFrames(handle: ISP1181Ctx; ticks: int): FrameWalk =
  let start = frameNumber(handle)
  var firstMismatch = ""
  var maxSeen = start
  var taken = 0
  for step in 1 .. ticks:
    advanceFrames(handle, 1)
    let seen = frameNumber(handle)
    inc taken
    if seen > maxSeen:
      maxSeen = seen
    let want = uint16((int(start) + step) mod frameModulus)
    if seen != want and firstMismatch.len == 0:
      firstMismatch = "tick " & $step & " read " & $seen & ", want " & $want
  (start: start, firstMismatch: firstMismatch, ticks: taken, maxSeen: maxSeen,
   final: frameNumber(handle))

let counter = isp1181_create(addr hostToken, recordIrq, recordTx)
let cycle = walkFrames(counter, frameModulus)
const wantCycle: FrameWalk = (start: 0'u16, firstMismatch: "", ticks: 2048,
                              maxSeen: 2047'u16, final: 0'u16)
check(cycle == wantCycle,
      "frames: a fresh handle starts at 0 and one full cycle advances by " &
        "exactly one per tick and ends where it began",
      $cycle, $wantCycle)

# THE WRAP ON ITS OWN, because the cycle case above passes its own start and
# end value through the same wrap and a reader should not have to take the
# discriminating step on trust.
let wrapping = isp1181_create(addr hostToken, recordIrq, recordTx)
advanceFrames(wrapping, 2047)

type Wrap = tuple[before: uint16, after: uint16]

let wrapBefore = frameNumber(wrapping)
advanceFrames(wrapping, 1)
let wrapSeen: Wrap = (before: wrapBefore, after: frameNumber(wrapping))
const wantWrap: Wrap = (before: 2047'u16, after: 0'u16)
check(wrapSeen == wantWrap,
      "frames: a counter at 2047 advanced by one reads 0",
      $wrapSeen, $wantWrap)

# THE COUNT FORM AND THE REPEATED FORM AGREE, which is the property a state
# restore and a fast-forward both need. EVERY `want` BELOW IS HAND-WRITTEN:
# comparing the two forms alone would pass for any modulus they shared.
type BulkRow = tuple[start: int, frames: int, want: uint16]

const bulkRows: array[6, BulkRow] = [
  (start: 0, frames: 5, want: 5'u16),
  (start: 2045, frames: 5, want: 2'u16),
  (start: 0, frames: 2048, want: 0'u16),
  (start: 0, frames: 2049, want: 1'u16),
  (start: 2000, frames: 100, want: 52'u16),
  (start: 1, frames: 4095, want: 0'u16)]

type BulkOutcome = tuple[rows: int, firstBad: string]

proc runBulk(): BulkOutcome =
  var firstBad = ""
  var rows = 0
  for row in bulkRows:
    let bulkCtx = isp1181_create(addr hostToken, recordIrq, recordTx)
    advanceFrames(bulkCtx, row.start)
    advanceFrames(bulkCtx, row.frames)
    let bulk = frameNumber(bulkCtx)

    let singleCtx = isp1181_create(addr hostToken, recordIrq, recordTx)
    advanceFrames(singleCtx, row.start)
    for _ in 1 .. row.frames:
      advanceFrames(singleCtx, 1)
    let singles = frameNumber(singleCtx)

    inc rows
    if (bulk != row.want or singles != row.want) and firstBad.len == 0:
      firstBad = "start " & $row.start & " + " & $row.frames & " -> bulk " &
        $bulk & ", singles " & $singles & ", want " & $row.want
    isp1181_destroy(bulkCtx)
    isp1181_destroy(singleCtx)
  (rows: rows, firstBad: firstBad)

const wantBulk: BulkOutcome = (rows: 6, firstBad: "")
let bulkOutcome = runBulk()
check(bulkOutcome == wantBulk,
      "frames: one call of N frames equals N calls of one, at and across the " &
        "wrap",
      $bulkOutcome, $wantBulk)

# ---------------------------------------------------------------------------
# BLOCK 9. The four entry points BRANCH on the selector and REACH the backend.
#
# EACH CASE DRIVES THE SAME BYTES THROUGH BOTH BACKENDS AND ASSERTS THE PAIR.
# THE PAIR IS THE ASSERTION AND A SINGLE SIDE IS NOT. A branch that was written
# and never taken answers with the stub on both sides; a branch that lost the
# stub answers with the model on both. Only the pair separates either from a
# selector that works - which is the same reason an empty function body links
# and satisfies a symbol check.
#
# THE COMMAND BYTES ARE DESIGN SECTION 9.2's: `0xBA` writes the hardware
# configuration, `0xBB` reads it back, `0x20` configures endpoint 0 and `0xD2`
# peeks the buffer that endpoint's deliveries land in. `0x2300` is the firmware
# value that section records.

const
  hwConfigWrite = 0xBA'u8
  hwConfigRead = 0xBB'u8
  endpointConfig0 = 0x20'u8
  peekByte = 0xD2'u8

type Pair = tuple[stub: string, model: string]

proc driveHwConfig(select: ISP1181Backend): string =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, select)
  isp1181_write(handle, commandPort, hwConfigWrite)
  isp1181_write(handle, dataPort, 0x00'u8)
  isp1181_write(handle, dataPort, 0x23'u8)
  isp1181_write(handle, commandPort, hwConfigRead)
  let low = isp1181_read(handle, dataPort)
  let high = isp1181_read(handle, dataPort)
  isp1181_destroy(handle)
  "0x" & toHex(low) & " 0x" & toHex(high)

let hwPair: Pair = (stub: driveHwConfig(Stub), model: driveHwConfig(FullModel))
const wantHwPair: Pair = (stub: "0x00 0x00", model: "0x00 0x23")
check(hwPair == wantHwPair,
      "branch: a write and a read reach the stub or the full model as the " &
        "selector says",
      $hwPair, $wantHwPair)

const packetBytes: array[4, uint8] = [0xA5'u8, 0x5A'u8, 0x3C'u8, 0xC3'u8]

proc peekEndpoint0(handle: ISP1181Ctx): uint8 =
  isp1181_write(handle, commandPort, endpointConfig0)
  isp1181_write(handle, dataPort, 0x00'u8)
  isp1181_write(handle, commandPort, peekByte)
  isp1181_read(handle, dataPort)

proc driveRx(select: ISP1181Backend): string =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, select)
  # A CALLER WITH NOTHING TO DELIVER MUST NOT OCCUPY A BUFFER, and endpoint 0
  # OUT is SINGLE-buffered. An empty delivery that took the slot would make the
  # real packet below a NAK, and the peek would then answer absent - so this
  # line is what separates "nothing was delivered" from "an empty packet was".
  isp1181_rx(handle, cint(0), nil, csize_t(0))
  var packet = packetBytes
  isp1181_rx(handle, cint(0), addr packet[0], csize_t(packet.len))
  let seen = peekEndpoint0(handle)
  isp1181_destroy(handle)
  "0x" & toHex(seen)

let rxPair: Pair = (stub: driveRx(Stub), model: driveRx(FullModel))
const wantRxPair: Pair = (stub: "0x00", model: "0xA5")
check(rxPair == wantRxPair,
      "branch: a delivery reaches the stub or the full model as the selector " &
        "says",
      $rxPair, $wantRxPair)

# DESTROY RELEASES THE SELECTED BACKEND, and the read after it is the only
# thing that can tell a release from a branch that did nothing. A destroyed
# handle answers benignly rather than aborting, which is the posture design
# section 5.6 already requires of a nil handle.
type DestroyWalk = tuple[before: string, after: string]

proc driveDestroy(select: ISP1181Backend): DestroyWalk =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, select)
  var packet = packetBytes
  isp1181_rx(handle, cint(0), addr packet[0], csize_t(packet.len))
  let before = peekEndpoint0(handle)
  isp1181_destroy(handle)
  let after = peekEndpoint0(handle)
  (before: "0x" & toHex(before), after: "0x" & toHex(after))

type DestroyPair = tuple[stub: DestroyWalk, model: DestroyWalk]

let destroyPair: DestroyPair = (stub: driveDestroy(Stub),
                                model: driveDestroy(FullModel))
const wantDestroyPair: DestroyPair = (
  stub: (before: "0x00", after: "0x00"),
  model: (before: "0xA5", after: "0x00"))
check(destroyPair == wantDestroyPair,
      "branch: destroy releases the full model and leaves the stub with " &
        "nothing to release",
      $destroyPair, $wantDestroyPair)

# THE HOST IS STILL SILENT AFTER THE FULL MODEL HAS BEEN DRIVEN. Block 5
# asserted this over the stub alone, and the selector adds a path that block
# could not reach.
type Callbacks = tuple[irq: Callback, tx: Callback]

let callbacksAfter: Callbacks = (irq: (calls: irqCalls, first: irqFirst),
                                 tx: (calls: txCalls, first: txFirst))
const wantCallbacksAfter: Callbacks = (irq: (calls: 0, first: ""),
                                       tx: (calls: 0, first: ""))
check(callbacksAfter == wantCallbacksAfter,
      "branch: neither callback fired on any access through either backend",
      $callbacksAfter, $wantCallbacksAfter)

# ---------------------------------------------------------------------------
# BLOCK 10. The Nim-side accessors answer a nil handle.
#
# The five C entry points already do, for design section 5.6's reason, and the
# accessors this task adds are reachable from the same plugin host through
# CPU-24's state entry points.

type NilAccess = tuple[atStart: string, frame: uint16, afterAdvance: uint16,
                       afterSet: string]

proc driveNilAccess(): NilAccess =
  let handle: ISP1181Ctx = nil
  let atStart = $backend(handle)
  let frame = frameNumber(handle)
  advanceFrames(handle, 5)
  let afterAdvance = frameNumber(handle)
  setBackend(handle, FullModel)
  (atStart: atStart, frame: frame, afterAdvance: afterAdvance,
   afterSet: $backend(handle))

let nilAccess = driveNilAccess()
const wantNilAccess: NilAccess = (atStart: "Stub", frame: 0'u16,
                                  afterAdvance: 0'u16, afterSet: "Stub")
check(nilAccess == wantNilAccess,
      "nil handle: the selector, the counter and their setters answer and " &
        "change nothing",
      $nilAccess, $wantNilAccess)

isp1181_destroy(selector)
isp1181_destroy(counter)
isp1181_destroy(wrapping)

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this program reports
# what its text declares and what its run adjudicated, and the registered
# test's driver is what compares them.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_isp1181_stub", declaredCaseSites)
echo caseSiteLine("executed", "t_isp1181_stub", executedSites)
echo caseSiteLine("off-green-path", "t_isp1181_stub", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_isp1181_stub: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_isp1181_stub: ", passCount, " cases passed"
