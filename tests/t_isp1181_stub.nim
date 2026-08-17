## `t_isp1181_stub` - the CS3 stub of the ISP1181 USB device controller.
##
## The whole specification these cases assert: the stub accepts every write,
## returns a benign value on every read, and never raises IRQ3.
##
## THE STUB ANSWERS AT EVERY ADDRESS AND DECODES NOTHING. The board owns the
## CS3 decode, so an address is an argument this model does not judge.
##
## Every expected value below is a hand-written literal and never a second call
## of the procedure under test.

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
  ## The call site is recorded twice - once at compile time into
  ## `declaredSites` by the `static` below, and once at run time into
  ## `executedSites`. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies. The template
  ## exists for `instantiationInfo`: a proc cannot see where it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, ok, label, got, want)

# ---------------------------------------------------------------------------
# The window.

const
  cs3Base = 0x13000000'u32
  windowBytes = 0x10000        ## 64 KiB
  dataPort = 0x13000000'u32
  commandPort = 0x13000010'u32
  benignRead = 0x00'u8

# The host side. EACH COUNTER CARRIES A TRANSCRIPT BESIDE IT, because a count
# alone cannot say what a call carried.

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
# THE SWEEP CARRIES THE FIRST ADDRESS THAT DISAGREED AND THE NUMBER OF READS IT
# PERFORMED.

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

# Addresses outside the window are answered too: a model that refused them
# would be deciding a decode the board owns.
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
# Each value is written and the same address is read immediately afterwards.

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

for offset in 0 ..< windowBytes:
  isp1181_write(ctx, cs3Base + uint32(offset), 0xFF'u8)

let afterWrites = sweepWindow(ctx)
check(afterWrites == wantWindow,
      "write: 0xFF into every offset leaves the whole window benign",
      $afterWrites, $wantWindow)

# ---------------------------------------------------------------------------
# BLOCK 4. Host traffic is accepted and produces nothing.
#
# A zero length and a nil buffer are driven because a caller with nothing to
# deliver has both.

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
# The caller of these entry points is a plugin's host. An abort inside a plugin
# destroys a session that has nothing to do with this model, so a nil handle has
# to have an answer.

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
  # THE WALK MOVES THE SELECTOR AND MOVES IT BACK.
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
# The modulus below is this file's own hand-written literal and never the
# module's constant. A test that imported the constant would move with it under
# mutation and would assert that the code agrees with itself.
#
# THE COUNTER'S NO-OP VALUE IS ZERO, WHICH IS WHY A FIRST-MISMATCH ASSERTION IS
# NOT ENOUGH ON ITS OWN. A counter that never advanced reads 0, and so does one
# that completed a full cycle.

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

# The count form and the repeated form agree, which is the property a state
# restore and a fast-forward both need. Every `want` below is hand-written:
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
# Block 9. The four entry points branch on the selector and reach the backend.
#
# THE COMMAND BYTES: `0xBA` writes the hardware configuration, `0xBB` reads it
# back, `0x20` configures endpoint 0 and `0xD2` peeks the buffer that
# endpoint's deliveries land in.

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
  # OUT is SINGLE-buffered.
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

# DESTROY RELEASES THE SELECTED BACKEND. A destroyed handle answers benignly
# rather than aborting, as a nil handle does.
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

# THE HOST IS STILL SILENT AFTER THE FULL MODEL HAS BEEN DRIVEN.
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

# The registry lines. They are data and not a verdict: this program reports
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
