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

import std/envvars
import std/os
import std/strutils

import isp1181/stub
from isp1181/isp1181 import logCapacity, configSlotCount, fifoEnableBit
from isp1181/report import reportBegins, reportEnds

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

let nilCtxProbe: ISP1181Ctx = nil

var rxCalls = 0
for endpoint in endpoints:
  for length in lengths:
    discard isp1181_rx(ctx, cint(endpoint), addr payload[0], csize_t(length))
    inc rxCalls
discard isp1181_rx(ctx, cint(0), nil, csize_t(0))
inc rxCalls

type RxOutcome = tuple[calls: int, window: Sweep]

let rxOutcome: RxOutcome = (calls: rxCalls, window: sweepWindow(ctx))
const wantRx: RxOutcome = (calls: 22, window: wantWindow)
check(rxOutcome == wantRx,
      "rx: traffic on every endpoint is accepted and reaches no register",
      $rxOutcome, $wantRx)

# The set-up entry point is inert on the stub too, and it answers rather than
# staying silent: `isp1181_setup` returns an int, so the stub's "nothing to
# say" has a value and the suite can assert it. A stub that reached the model
# here would arm the set-up interlock inside a handle the caller never moved.

type SetupOutcome = tuple[accepted: int, nilData: int, nilHandle: int,
                          window: Sweep]

var setupAccepted = 0
for length in lengths:
  setupAccepted = setupAccepted or
    int(isp1181_setup(ctx, addr payload[0], csize_t(length)))

let setupOutcome: SetupOutcome = (
    accepted: setupAccepted,
    nilData: int(isp1181_setup(ctx, nil, csize_t(0))),
    nilHandle: int(isp1181_setup(nilCtxProbe, addr payload[0], csize_t(8))),
    window: sweepWindow(ctx))
const wantSetup: SetupOutcome = (accepted: 0, nilData: 0, nilHandle: 0,
                                 window: wantWindow)
check(setupOutcome == wantSetup,
      "set-up: the stub answers 0 for a packet, for nil data and for a nil " &
        "handle, and reaches no register",
      $setupOutcome, $wantSetup)

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
discard isp1181_rx(nilCtx, cint(1), addr payload[0], csize_t(64))
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
# A first-mismatch assertion is not enough on its own: a counter that never
# advanced reads 0, and so does one that completed a full cycle.

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
  # A caller with nothing to deliver must not occupy a buffer, and endpoint 0
  # OUT is single-buffered.
  discard isp1181_rx(handle, cint(0), nil, csize_t(0))
  var packet = packetBytes
  discard isp1181_rx(handle, cint(0), addr packet[0], csize_t(packet.len))
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
  discard isp1181_rx(handle, cint(0), addr packet[0], csize_t(packet.len))
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

# ---------------------------------------------------------------------------
# The selector C can reach.
#
# The two values below are hand-written literals and not the module's
# constants. They are the numbers `include/mcf5307.h` publishes as
# `MCF5307_ISP1181_BACKEND_STUB` and `MCF5307_ISP1181_BACKEND_FULL_MODEL`, and
# a suite that imported them would agree with any renumbering at all - which
# is exactly the change that would silently repoint every existing C caller.

const
  backendStubValue = 0'i32
  backendFullModelValue = 1'i32

type CSelect = tuple[atCreate: string, accepted: cint, afterSet: string,
                     peeked: string]

proc driveCSelect(): CSelect =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  let atCreate = $backend(handle)
  let accepted = isp1181_set_backend(handle, cint(backendFullModelValue))
  let afterSet = $backend(handle)
  var packet = packetBytes
  discard isp1181_rx(handle, cint(0), addr packet[0], csize_t(packet.len))
  let seen = peekEndpoint0(handle)
  isp1181_destroy(handle)
  (atCreate: atCreate, accepted: accepted, afterSet: afterSet,
   peeked: "0x" & toHex(seen))

const wantCSelect: CSelect = (atCreate: "Stub", accepted: cint(1),
                              afterSet: "FullModel", peeked: "0xA5")

let cSelect = driveCSelect()
check(cSelect == wantCSelect,
      "selector: the published setter moves a handle to the full model and " &
        "a delivery through the C entry point then reaches its buffer",
      $cSelect, $wantCSelect)

# A value the contract does not name is refused and changes nothing. A setter
# that fell through to a default would repoint the handle on a caller's typo,
# and the caller would read a success it never got.
type CRefuse = tuple[toStub: cint, afterStub: string, refused: cint,
                     afterRefusal: string, nilHandle: cint]

proc driveCRefuse(): CRefuse =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  discard isp1181_set_backend(handle, cint(backendFullModelValue))
  let toStub = isp1181_set_backend(handle, cint(backendStubValue))
  let afterStub = $backend(handle)
  discard isp1181_set_backend(handle, cint(backendFullModelValue))
  let refused = isp1181_set_backend(handle, cint(7))
  let afterRefusal = $backend(handle)
  isp1181_destroy(handle)
  let absent: ISP1181Ctx = nil
  (toStub: toStub, afterStub: afterStub, refused: refused,
   afterRefusal: afterRefusal,
   nilHandle: isp1181_set_backend(absent, cint(backendFullModelValue)))

const wantCRefuse: CRefuse = (toStub: cint(1), afterStub: "Stub",
                              refused: cint(0), afterRefusal: "FullModel",
                              nilHandle: cint(0))

let cRefuse = driveCRefuse()
check(cRefuse == wantCRefuse,
      "selector: the setter moves back to the stub, refuses an unnamed " &
        "value and refuses a nil handle, and neither refusal moves anything",
      $cRefuse, $wantCRefuse)

# ---------------------------------------------------------------------------
# BLOCK 12. The device-to-host route a C caller can drive.
#
# `isp1181_rx` is the host handing a packet to the device, and this is its
# other half: the host asking the device for one, which is what an IN token
# is on the bus. A transmit callback the constructor stores and nothing ever
# calls looks, from the host's side, exactly like a device that never had
# anything to send - so the case below drives the firmware's own command bytes
# through `isp1181_write` and asserts the call, its endpoint, its length and
# every byte of it.
#
# Every byte below is a hand-written literal. `0x01` is write control IN
# buffer and `0x61` is validate control IN buffer, and the two bytes between
# them are the in-band length prefix, lower byte first.

var inTxCalls = 0
var inTxLog: seq[string]

proc recordInTx(user: pointer; endpoint: cint; data: ptr uint8;
                length: csize_t) {.cdecl.} =
  ## The transcript carries `user`, which is the argument a consumer casts
  ## back to its own object. An entry point that reached the callback with a
  ## null or a foreign `user` would satisfy every byte-level assertion here
  ## and would fault inside the host on the first packet.
  inc inTxCalls
  var bytes: seq[string]
  if not data.isNil:
    let raw = cast[ptr UncheckedArray[uint8]](data)
    for index in 0 ..< int(length):
      bytes.add("0x" & toHex(raw[index]))
  inTxLog.add("user=" & (if user == addr hostToken: "host" else: "OTHER") &
              " endpoint=" & $int(endpoint) & " len=" & $int(length) &
              " bytes=" & bytes.join(" "))

const
  bufferWriteControlIn = 0x01'u8
  validateControlIn = 0x61'u8
  inPayload: array[4, uint8] = [0xDE'u8, 0xAD'u8, 0xBE'u8, 0xEF'u8]

proc firmwareValidates(handle: ISP1181Ctx) =
  isp1181_write(handle, commandPort, bufferWriteControlIn)
  isp1181_write(handle, dataPort, uint8(inPayload.len))
  isp1181_write(handle, dataPort, 0x00'u8)
  for value in inPayload:
    isp1181_write(handle, dataPort, value)
  isp1181_write(handle, commandPort, validateControlIn)

type InToken = tuple[first: cint, second: cint, calls: int, log: seq[string]]

proc driveInToken(select: ISP1181Backend): InToken =
  inTxCalls = 0
  inTxLog = @[]
  let handle = isp1181_create(addr hostToken, recordIrq, recordInTx)
  setBackend(handle, select)
  firmwareValidates(handle)
  let first = isp1181_in_token(handle, cint(0))
  let second = isp1181_in_token(handle, cint(0))
  isp1181_destroy(handle)
  (first: first, second: second, calls: inTxCalls, log: inTxLog)

# The second token is what separates a buffer that was consumed from one that
# was copied. A model that left the packet in place would answer every token
# with the same bytes and the firmware would never learn the transfer ended.
let inTokenModel = driveInToken(FullModel)
const wantInTokenModel: InToken = (
    first: cint(1), second: cint(0), calls: 1,
    log: @["user=host endpoint=0 len=4 bytes=0xDE 0xAD 0xBE 0xEF"])
check(inTokenModel == wantInTokenModel,
      "in token: a packet the firmware validated through the C write port " &
        "reaches the host callback once, whole, and the buffer is then empty",
      $inTokenModel, $wantInTokenModel)

# The control comes from the same population and the same handle. A zero from
# `isp1181_in_token` proves nothing on its own: an entry point that refused
# every endpoint would answer zero too. Endpoint 1 is an endpoint this model
# refuses to transmit for, and it is driven on the handle whose endpoint 0
# just answered, through the same entry point, with a packet staged the same
# way.
type InTokenControl = tuple[endpoint0: cint, endpoint1: cint, calls: int,
                            log: seq[string]]

proc driveInTokenControl(): InTokenControl =
  inTxCalls = 0
  inTxLog = @[]
  let handle = isp1181_create(addr hostToken, recordIrq, recordInTx)
  setBackend(handle, FullModel)
  firmwareValidates(handle)
  let good = isp1181_in_token(handle, cint(0))
  firmwareValidates(handle)
  let refused = isp1181_in_token(handle, cint(1))
  isp1181_destroy(handle)
  (endpoint0: good, endpoint1: refused, calls: inTxCalls, log: inTxLog)

let inTokenControl = driveInTokenControl()
const wantInTokenControl: InTokenControl = (
    endpoint0: cint(1), endpoint1: cint(0), calls: 1,
    log: @["user=host endpoint=0 len=4 bytes=0xDE 0xAD 0xBE 0xEF"])
check(inTokenControl == wantInTokenControl,
      "in token: an endpoint this model will not transmit for answers zero " &
        "and calls no host, on the handle whose endpoint 0 just answered",
      $inTokenControl, $wantInTokenControl)

# The stub is inert here too, and a nil handle is answered rather than
# aborted. The stub is a device that is present and has nothing to say; a nil
# handle reaching an abort would destroy a plugin session that has nothing to
# do with this model.
type InTokenInert = tuple[stub: InToken, nilHandle: cint]

let absentHandle: ISP1181Ctx = nil
let inTokenInert: InTokenInert = (
    stub: driveInToken(Stub),
    nilHandle: isp1181_in_token(absentHandle, cint(0)))
const wantInTokenInert: InTokenInert = (
    stub: (first: cint(0), second: cint(0), calls: 0, log: @[]),
    nilHandle: cint(0))
check(inTokenInert == wantInTokenInert,
      "in token: the stub answers zero and calls no host, and a nil handle " &
        "answers zero rather than aborting",
      $inTokenInert, $wantInTokenInert)

# ---------------------------------------------------------------------------
# BLOCK 13. The IRQ line a C caller can see.
#
# Every step below goes through a published entry point. The enable is written
# with `isp1181_write` as the firmware writes it, the packet arrives through
# `isp1181_rx` as the bus delivers it, and what the case asserts is the
# argument the C caller's own `isp1181_irq_fn` received. A model that set the
# bit and never reached the callback would satisfy every Nim-side case in
# `t_isp1181` and would leave IRQ3 dead in the consumer.
#
# Every byte is a hand-written literal. `0xC2` is write interrupt enable and
# `0x07 0x1F 0x00 0x00` is `0x00001F07` lower byte first, which is the value
# the emulated firmware writes. `0x50` is read control OUT endpoint status.

var lineTrace: seq[string]

proc recordLine(user: pointer; asserted: cint) {.cdecl.} =
  lineTrace.add("user=" & (if user == addr hostToken: "host" else: "OTHER") &
                " asserted=" & $int(asserted))

const
  writeInterruptEnable = 0xC2'u8
  readControlOutStatus = 0x50'u8

type Line = tuple[trace: seq[string], refusedTrace: seq[string],
                  clearedTrace: seq[string]]

proc driveLine(): Line =
  lineTrace = @[]
  let handle = isp1181_create(addr hostToken, recordLine, recordTx)
  setBackend(handle, FullModel)
  isp1181_write(handle, commandPort, writeInterruptEnable)
  for value in [0x07'u8, 0x1F'u8, 0x00'u8, 0x00'u8]:
    isp1181_write(handle, dataPort, value)
  discard isp1181_rx(handle, cint(0), addr payload[0], csize_t(1))
  result.trace = lineTrace
  discard isp1181_rx(handle, cint(4), addr payload[0], csize_t(1))
  result.refusedTrace = lineTrace
  isp1181_write(handle, commandPort, readControlOutStatus)
  discard isp1181_read(handle, dataPort)
  result.clearedTrace = lineTrace
  isp1181_destroy(handle)

# The known negative is on the same handle, through the same entry point.
# Endpoint 4 is an endpoint this model does not carry, and it is delivered to
# after endpoint 0 has already lit the line: a callback that fired on any
# delivery at all would add a second entry here, and one that never fired
# would leave the first list empty.
let line = driveLine()
let wantLine: Line = (
    trace: @["user=host asserted=1"],
    refusedTrace: @["user=host asserted=1"],
    clearedTrace: @["user=host asserted=1", "user=host asserted=0"])
check(line == wantLine,
      "irq: a delivery through isp1181_rx reaches the C caller's callback, " &
        "a refused one does not, and a status read drops the line",
      $line, $wantLine)

# ---------------------------------------------------------------------------
# The model's own account, read through the C door.
#
# These cases drive an acceptance and a refusal through the same entry point on
# the same handle and assert that the two are told apart at the ABI - in the
# return, and in the log the return points at.

type RxAnswer = tuple[accepted: cint, refused: cint, stub: cint, nilHandle: cint]

proc driveRxAnswer(): RxAnswer =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  var packet = packetBytes
  # Endpoint 0 OUT is single-buffered and empty here, so it takes the packet.
  # Endpoint 4 is one this model does not carry, so it cannot.
  result.accepted = isp1181_rx(handle, cint(0), addr packet[0],
                               csize_t(packet.len))
  result.refused = isp1181_rx(handle, cint(4), addr packet[0],
                              csize_t(packet.len))
  isp1181_destroy(handle)
  let stubHandle = isp1181_create(addr hostToken, recordIrq, recordTx)
  result.stub = isp1181_rx(stubHandle, cint(0), addr packet[0],
                           csize_t(packet.len))
  isp1181_destroy(stubHandle)
  result.nilHandle = isp1181_rx(nilCtx, cint(0), addr packet[0],
                                csize_t(packet.len))

let rxAnswer = driveRxAnswer()
const wantRxAnswer: RxAnswer = (accepted: cint(1), refused: cint(0),
                                stub: cint(0), nilHandle: cint(0))
check(rxAnswer == wantRxAnswer,
      "log: isp1181_rx answers 1 for a packet a buffer holds and 0 for one " &
        "the device dropped, on the model, on the stub and on a nil handle",
      $rxAnswer, $wantRxAnswer)

proc readLogLine(handle: ISP1181Ctx; index: int): string =
  let needed = isp1181_log_line(handle, csize_t(index), nil, csize_t(0))
  if needed == 0:
    return ""
  var buffer = newString(int(needed))
  let again = isp1181_log_line(handle, csize_t(index), cast[ptr cchar](addr buffer[0]),
                               csize_t(buffer.len))
  if again != needed:
    return "SIZE-MOVED"
  buffer.setLen(int(needed) - 1)
  buffer

type LogWalk = tuple[writtenBefore: uint, writtenAfter: uint,
                     retainedAfter: uint, firstLine: string,
                     pastEnd: uint, shortestLine: uint]

proc driveLog(): LogWalk =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  var packet = packetBytes
  result.writtenBefore = uint(isp1181_log_written(handle))
  discard isp1181_rx(handle, cint(0), addr packet[0], csize_t(packet.len))
  discard isp1181_rx(handle, cint(4), addr packet[0], csize_t(packet.len))
  result.writtenAfter = uint(isp1181_log_written(handle))
  result.retainedAfter = uint(isp1181_log_retained(handle))
  result.firstLine = readLogLine(handle, 0)
  result.pastEnd = uint(isp1181_log_line(handle, csize_t(result.retainedAfter),
                                         nil, csize_t(0)))
  # No retained line is empty, so the smallest answer for a real line is 2 and
  # the 0 above is unambiguous.
  var shortest = high(uint)
  for i in 0 ..< int(result.retainedAfter):
    let needed = uint(isp1181_log_line(handle, csize_t(i), nil, csize_t(0)))
    if needed < shortest:
      shortest = needed
  result.shortestLine = shortest
  isp1181_destroy(handle)

let logWalk = driveLog()
let wantLogWalk: LogWalk = (
    writtenBefore: 0'u, writtenAfter: 1'u, retainedAfter: 1'u,
    firstLine: "isp1181: a packet reached endpoint 4, which this model does " &
      "not implement; the packet is dropped",
    pastEnd: 0'u, shortestLine: 2'u)
check(logWalk.writtenBefore == wantLogWalk.writtenBefore and
      logWalk.writtenAfter == wantLogWalk.writtenAfter and
      logWalk.retainedAfter == wantLogWalk.retainedAfter and
      logWalk.firstLine == wantLogWalk.firstLine and
      logWalk.pastEnd == wantLogWalk.pastEnd and
      logWalk.shortestLine >= wantLogWalk.shortestLine,
      "log: the accepted delivery writes no line, the refused one writes the " &
        "line that names endpoint 4, an index past the end answers 0, and no " &
        "retained line is empty",
      $logWalk, $wantLogWalk)

type Truncation = tuple[needed: uint, short: uint, kept: string, tail: char]

proc driveTruncation(): Truncation =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  var packet = packetBytes
  discard isp1181_rx(handle, cint(4), addr packet[0], csize_t(packet.len))
  result.needed = uint(isp1181_log_line(handle, csize_t(0), nil, csize_t(0)))
  # A buffer that cannot hold the line. The sentinel byte past the capacity is
  # what proves the call wrote nothing beyond what it was given: a copy that
  # overran would replace it.
  const capacity = 8
  var buffer = newString(capacity + 1)
  for i in 0 .. capacity:
    buffer[i] = '#'
  result.short = uint(isp1181_log_line(handle, csize_t(0),
                                       cast[ptr cchar](addr buffer[0]),
                                       csize_t(capacity)))
  result.kept = buffer[0 ..< capacity - 1]
  result.tail = buffer[capacity]
  isp1181_destroy(handle)

let truncation = driveTruncation()
let wantTruncation: Truncation = (needed: uint(logWalk.firstLine.len + 1),
                                  short: uint(logWalk.firstLine.len + 1),
                                  kept: "isp1181", tail: '#')
check(truncation == wantTruncation and truncation.short > 8'u,
      "log: a buffer too small for the line still gets the SIZE THE LINE " &
        "NEEDS back, so the truncation is visible, and nothing is written " &
        "past the capacity",
      $truncation, $wantTruncation)

# The loop drives one refusal past the retention bound and asserts that
# `written` kept counting while `retained` stopped: their difference is exactly
# the number of lines the reader cannot see.
type Overflow = tuple[written: uint, retained: uint, dropped: uint,
                      lastRetained: uint, firstDropped: uint]

proc driveOverflow(): Overflow =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  var packet = packetBytes
  for _ in 0 .. logCapacity:
    discard isp1181_rx(handle, cint(4), addr packet[0], csize_t(packet.len))
  result.written = uint(isp1181_log_written(handle))
  result.retained = uint(isp1181_log_retained(handle))
  result.dropped = result.written - result.retained
  result.lastRetained = uint(isp1181_log_line(handle,
      csize_t(result.retained - 1), nil, csize_t(0)))
  result.firstDropped = uint(isp1181_log_line(handle, csize_t(result.retained),
      nil, csize_t(0)))
  isp1181_destroy(handle)

let overflow = driveOverflow()
let wantOverflow: Overflow = (written: uint(logCapacity) + 1,
                              retained: uint(logCapacity), dropped: 1'u,
                              lastRetained: uint(logWalk.firstLine.len + 1),
                              firstDropped: 0'u)
check(overflow == wantOverflow,
      "log: the account stops retaining at its bound and does not stop " &
        "counting, so a reader learns how many lines it cannot see",
      $overflow, $wantOverflow)

# ---------------------------------------------------------------------------
# The configuration door and the report door.
#
# The three calls below are what a consumer reads the model's account through
# without editing its own source.

const configSentinel = 0xA5'u8
  ## A byte no case below writes into a slot. It is what proves that
  ## `isp1181_config_slot` left `value` alone: a call that stored the reset
  ## value would replace it with `0x00`.

proc configSlotAt(handle: ISP1181Ctx; slot: int): tuple[rc: int, value: uint8] =
  var seen = configSentinel
  let rc = isp1181_config_slot(handle, csize_t(slot), addr seen)
  (rc: int(rc), value: seen)

proc writeConfigSlot(handle: ISP1181Ctx; slot: int; value: uint8) =
  isp1181_write(handle, commandPort, uint8(0x20 + slot))
  isp1181_write(handle, dataPort, value)

proc readReport(handle: ISP1181Ctx): string =
  ## The two-call form, sized from the call's own answer.
  let needed = isp1181_report(handle, nil, csize_t(0))
  if needed == 0:
    return ""
  var buffer = newString(int(needed))
  let again = isp1181_report(handle, cast[ptr cchar](addr buffer[0]),
                             csize_t(buffer.len))
  if again != needed:
    return "SIZE-MOVED"
  buffer.setLen(int(needed) - 1)
  buffer

# The slot count is a call and not a macro, so nothing can hold a second copy
# of it that goes stale. This case holds the published figure against the
# model's own.
check(int(isp1181_config_slots()) == 16 and
      int(isp1181_config_slots()) == configSlotCount,
      "configuration: the published slot count is sixteen and is the model's " &
        "own figure rather than a second copy of it",
      $int(isp1181_config_slots()), $configSlotCount)

# The three answers, and the one the byte could not give. Slot 3 is written
# with `0x00` and slot 4 is left alone, so both registers hold `0x00` and a
# door that reported only the byte would answer both the same way. The return
# separates them, and the sentinel proves `value` was not touched on the slot
# that was never written.
type ConfigDoor = tuple[writtenRc: int, writtenValue: uint8,
                        untouchedRc: int, untouchedValue: uint8,
                        epdirRc: int, epdirValue: uint8]

proc driveConfigDoor(): ConfigDoor =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  handle.writeConfigSlot(3, 0x00'u8)
  handle.writeConfigSlot(2, 0xC1'u8)
  let written = handle.configSlotAt(3)
  let untouched = handle.configSlotAt(4)
  let epdir = handle.configSlotAt(2)
  isp1181_destroy(handle)
  (writtenRc: written.rc, writtenValue: written.value,
   untouchedRc: untouched.rc, untouchedValue: untouched.value,
   epdirRc: epdir.rc, epdirValue: epdir.value)

let configDoor = driveConfigDoor()
# `0xC1` is FIFOEN, EPDIR and FFOSZ = 1. EPDIR is bit 6, mask `0x40`, ISP1362
# Rev. 06 Table 110 and Table 111 p.107, and only that bit is read here.
let wantConfigDoor: ConfigDoor = (writtenRc: 1, writtenValue: 0x00'u8,
                                  untouchedRc: 0,
                                  untouchedValue: configSentinel,
                                  epdirRc: 1, epdirValue: 0xC1'u8)
check(configDoor == wantConfigDoor and
      (configDoor.epdirValue and 0x40'u8) != 0'u8 and
      (configDoor.writtenValue and 0x40'u8) == 0'u8,
      "configuration: a slot written with 0x00 answers 1 and a slot never " &
        "written answers 0 and leaves the caller's byte alone, and EPDIR " &
        "reads out of the raw byte",
      $configDoor, $wantConfigDoor)

# The third answer. No such slot and no handle are neither "written" nor "not
# written", and folding them into 0 would report a real slot the firmware never
# reached and a typo with one word.
type ConfigRefusal = tuple[pastEnd: int, pastEndValue: uint8,
                           nilRc: int, nilValue: uint8, lastRc: int]

proc driveConfigRefusal(): ConfigRefusal =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  handle.writeConfigSlot(15, 0x00'u8)
  let past = handle.configSlotAt(configSlotCount)
  let last = handle.configSlotAt(15)
  isp1181_destroy(handle)
  let refused = nilCtx.configSlotAt(0)
  (pastEnd: past.rc, pastEndValue: past.value, nilRc: refused.rc,
   nilValue: refused.value, lastRc: last.rc)

let configRefusal = driveConfigRefusal()
let wantConfigRefusal: ConfigRefusal = (pastEnd: -1,
                                        pastEndValue: configSentinel,
                                        nilRc: -1, nilValue: configSentinel,
                                        lastRc: 1)
check(configRefusal == wantConfigRefusal,
      "configuration: a slot past the sixteenth and a nil handle answer -1 " &
        "and leave the caller's byte alone, and the sixteenth slot itself " &
        "is inside the range",
      $configRefusal, $wantConfigRefusal)

# ---------------------------------------------------------------------------
# The buffer-geometry door. What an endpoint will accept, asked rather than
# assumed.

const sizeSentinel = csize_t(0xDEAD)
  ## A figure no legal answer can be. ISP1362 Rev. 06 Table 16 p.52 gives the
  ## non-isochronous sizes as 8, 16, 32 and 64 and reserves the rest, and no
  ## buffer count in this model is anywhere near it. It is what proves an
  ## answer of 0 or -1 left both out-parameters alone.

proc slotBufferAt(handle: ISP1181Ctx;
                  slot: int): tuple[rc: int, bytes: uint, buffers: uint] =
  var seenBytes = sizeSentinel
  var seenBuffers = sizeSentinel
  let rc = isp1181_slot_buffer(handle, csize_t(slot), addr seenBytes,
                               addr seenBuffers)
  (rc: int(rc), bytes: uint(seenBytes), buffers: uint(seenBuffers))

# THE ANSWER IS PER ENDPOINT AND NOT ONE NUMBER FOR THE DEVICE. Slot 0 is
# endpoint 0 OUT, whose 64 bytes ISP1362 Rev. 06 Table 15 p.51 fixes, and slot 2
# is endpoint 1, configured here with the byte the G2 firmware writes - `0xE1`,
# whose `FFOSZ` is `0001` for 16 bytes and whose `DBLBUF` is set. They differ in
# both figures, so a door that answered a single global maximum would pass every
# other case here and fail this one. Both expectations are hand-written literals
# decoded from Table 15 and Table 16 p.52, never a second call of the procedure
# under test.
type BufferShapes = tuple[ep0Out: tuple[rc: int, bytes: uint, buffers: uint],
                          ep1: tuple[rc: int, bytes: uint, buffers: uint]]

proc driveBufferShapes(): BufferShapes =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  handle.writeConfigSlot(2, 0xE1'u8)
  result.ep0Out = handle.slotBufferAt(0)
  result.ep1 = handle.slotBufferAt(2)
  isp1181_destroy(handle)

let bufferShapes = driveBufferShapes()
let wantBufferShapes: BufferShapes = (
  ep0Out: (rc: 1, bytes: 64'u, buffers: 1'u),
  ep1: (rc: 1, bytes: 16'u, buffers: 2'u))
check(bufferShapes == wantBufferShapes and
      bufferShapes.ep0Out.bytes != bufferShapes.ep1.bytes,
      "buffer geometry: each endpoint answers ITS OWN size and depth - " &
        "endpoint 0 OUT is 64 bytes single-buffered and endpoint 1 configured " &
        "with 0xE1 is 16 bytes double-buffered - so no single device-wide " &
        "maximum can satisfy this",
      $bufferShapes, $wantBufferShapes)

# The size is read out of the configuration byte and is not a constant. Slot 3
# is endpoint 2, the slot whose reset buffer allocation in this model is 64
# bytes and two deep and whose measured firmware byte selects exactly that.
# Configure it instead with `0x81` - FIFOEN set, `DBLBUF` clear, `FFOSZ` =
# `0001` - and ISP1362 Rev. 06 Table 16 p.52 makes the answer 16 bytes one deep.
# A call that still published the allocation table would answer 64 and 2 here
# and pass every other case in this file, so this pair of figures is the whole
# evidence that the read-back happened.
type ConfiguredSize = tuple[asWritten: tuple[rc: int, bytes: uint,
                                             buffers: uint],
                            afterRewrite: tuple[rc: int, bytes: uint,
                                                buffers: uint]]

proc driveConfiguredSize(): ConfiguredSize =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  handle.writeConfigSlot(3, 0xE3'u8)
  result.asWritten = handle.slotBufferAt(3)
  handle.writeConfigSlot(3, 0x81'u8)
  result.afterRewrite = handle.slotBufferAt(3)
  isp1181_destroy(handle)

let configuredSize = driveConfiguredSize()
let wantConfiguredSize: ConfiguredSize = (
  asWritten: (rc: 1, bytes: 64'u, buffers: 2'u),
  afterRewrite: (rc: 1, bytes: 16'u, buffers: 1'u))
check(configuredSize == wantConfiguredSize,
      "buffer geometry: one slot answers 64 bytes two deep for 0xE3 and 16 " &
        "bytes one deep for 0x81, so the size and the depth are DECODED from " &
        "the configuration byte and not published from a table",
      $configuredSize, $wantConfiguredSize)

# Each non-isochronous code, driven. Table 16 p.52 gives `0000` to `0011` as 8,
# 16, 32 and 64 bytes, and a decode that got one row wrong would still satisfy
# the case above. The sweep aggregates into one case; the length of the answer
# is part of the expected value, so a table that stopped iterating is red here
# rather than silently shorter.
proc driveSizeCodes(): seq[uint] =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  for code in 0'u8 .. 3'u8:
    handle.writeConfigSlot(4, fifoEnableBit or code)
    result.add(handle.slotBufferAt(4).bytes)
  isp1181_destroy(handle)

let sizeCodes = driveSizeCodes()
let wantSizeCodes = @[8'u, 16'u, 32'u, 64'u]
check(sizeCodes == wantSizeCodes,
      "buffer geometry: FFOSZ 0000, 0001, 0010 and 0011 answer 8, 16, 32 and " &
        "64 bytes, which is Table 16's non-isochronous column driven row by " &
        "row rather than spot-checked at one value",
      $sizeCodes, $wantSizeCodes)

# A SLOT WITH NO BUFFER IN THIS MODEL IS 0, AND 0 IS NOT A SIZE OF ZERO. Slot 5
# is a real configuration slot - the firmware writes it below and
# `isp1181_config_slot` answers 1 for it - and this model carries no buffer
# behind it. Both a 0 and a plausible 64 would be inventions a producer would
# size its packets to.
type NoBuffer = tuple[configRc: int, bufferRc: int, bytes: uint, buffers: uint]

proc driveNoBuffer(): NoBuffer =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  handle.writeConfigSlot(5, 0xC3'u8)
  let config = handle.configSlotAt(5)
  let buffer = handle.slotBufferAt(5)
  isp1181_destroy(handle)
  (configRc: config.rc, bufferRc: buffer.rc, bytes: buffer.bytes,
   buffers: buffer.buffers)

let noBuffer = driveNoBuffer()
let wantNoBuffer: NoBuffer = (configRc: 1, bufferRc: 0,
                              bytes: uint(sizeSentinel),
                              buffers: uint(sizeSentinel))
check(noBuffer == wantNoBuffer,
      "buffer geometry: a slot the firmware configured that this model " &
        "carries no buffer for answers 0 and leaves both of the caller's " &
        "figures alone, so no invented size reaches a producer",
      $noBuffer, $wantNoBuffer)

# A slot the firmware never wrote must not answer 8 bytes, and 8 is what its
# bits say. Table 110 p.107 resets the whole byte to 0 and Table 16 p.52 reads
# `FFOSZ` = `0000` as 8 bytes, so a decode that skipped the "was it written"
# question would answer a legal, plausible, smallest size for an endpoint the
# firmware never configured - and a producer would split every frame to it and
# see no error. Slot 4 is endpoint 3, a slot this model DOES carry buffer memory
# for, so nothing but the write record separates the two answers below.
type NeverWritten = tuple[before: tuple[rc: int, bytes: uint, buffers: uint],
                          after: tuple[rc: int, bytes: uint, buffers: uint],
                          configBefore: int]

proc driveNeverWritten(): NeverWritten =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  result.before = handle.slotBufferAt(4)
  result.configBefore = handle.configSlotAt(4).rc
  handle.writeConfigSlot(4, 0x83'u8)
  result.after = handle.slotBufferAt(4)
  isp1181_destroy(handle)

let neverWritten = driveNeverWritten()
let wantNeverWritten: NeverWritten = (
  before: (rc: 0, bytes: uint(sizeSentinel), buffers: uint(sizeSentinel)),
  after: (rc: 1, bytes: 64'u, buffers: 1'u),
  configBefore: 0)
check(neverWritten == wantNeverWritten and neverWritten.before.bytes != 8'u,
      "buffer geometry: a buffered slot the firmware never wrote answers 0 " &
        "and NOT the 8 bytes its reset FFOSZ decodes to, and the same slot " &
        "answers 64 bytes one deep once 0x83 is written to it",
      $neverWritten, $wantNeverWritten)

# A configuration that names no size is refused, and the refusal is -1. Table 16
# p.52 marks `0100` to `1111` reserved in the non-isochronous column, and gives
# the isochronous column sizes reaching 1023 bytes that no buffer in this model
# carries. Neither is a size to report. The caller separates this -1 from the
# out-of-range one by the slot being in range and configured, which is what the
# third figure in each row records.
type Unnameable = tuple[reserved: tuple[rc: int, bytes: uint, cfg: int],
                        isochronous: tuple[rc: int, bytes: uint, cfg: int]]

proc driveUnnameable(): Unnameable =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  handle.writeConfigSlot(3, 0x84'u8)
  let onReserved = handle.slotBufferAt(3)
  result.reserved = (rc: onReserved.rc, bytes: onReserved.bytes,
                     cfg: handle.configSlotAt(3).rc)
  handle.writeConfigSlot(4, 0x93'u8)
  let onIso = handle.slotBufferAt(4)
  result.isochronous = (rc: onIso.rc, bytes: onIso.bytes,
                        cfg: handle.configSlotAt(4).rc)
  isp1181_destroy(handle)

let unnameable = driveUnnameable()
let wantUnnameable: Unnameable = (
  reserved: (rc: -1, bytes: uint(sizeSentinel), cfg: 1),
  isochronous: (rc: -1, bytes: uint(sizeSentinel), cfg: 1))
check(unnameable == wantUnnameable,
      "buffer geometry: a reserved FFOSZ code and an isochronous endpoint " &
        "both answer -1 on a slot that is in range and configured, and " &
        "neither leaves a size behind, so no reserved code becomes a default",
      $unnameable, $wantUnnameable)

# A disabled endpoint has no buffer.
# Section 12.3.3 p.51: "Only enabled endpoints are allocated space in the shared
# buffer memory storage, disabled endpoints have zero bytes." So `0x03` - FIFOEN
# clear, `FFOSZ` = `0011` - is a slot the firmware configured with a size field
# that means nothing, and the answer is 0 rather than the 64 that field would
# decode to. The control slot beside it is the contrast: Table 15 p.51 fixes
# endpoint 0 at 64 bytes, so the same disabling byte leaves it unmoved.
type Disabled = tuple[endpoint: tuple[rc: int, bytes: uint], cfg: int,
                      control: tuple[rc: int, bytes: uint, buffers: uint]]

proc driveDisabled(): Disabled =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  handle.writeConfigSlot(4, 0x03'u8)
  let off = handle.slotBufferAt(4)
  result.endpoint = (rc: off.rc, bytes: off.bytes)
  result.cfg = handle.configSlotAt(4).rc
  handle.writeConfigSlot(1, 0x03'u8)
  result.control = handle.slotBufferAt(1)
  isp1181_destroy(handle)

let disabled = driveDisabled()
let wantDisabled: Disabled = (endpoint: (rc: 0, bytes: uint(sizeSentinel)),
                              cfg: 1,
                              control: (rc: 1, bytes: 64'u, buffers: 1'u))
check(disabled == wantDisabled,
      "buffer geometry: FIFOEN clear answers 0 for endpoint 3 rather than " &
        "the 64 its FFOSZ field still spells, while control IN under the " &
        "same byte holds the 64 bytes Table 15 fixes for it",
      $disabled, $wantDisabled)

# The reported size is the size the buffer enforces, for the image this model
# was measured against. The figure this call reports is decoded from the
# configuration byte; the buffer a packet actually meets is allocated at reset
# from a separate table, and the two are different mechanisms that happen to
# agree for the measured firmware. Slot 4 gets `0x83`, the byte the G2 firmware
# writes for endpoint 3, the call is asked for the size, and the answer is then
# handed to the device as a packet of exactly that many bytes and as one byte
# more. Accepted then refused is the only pair of outcomes that means the
# reported figure is the boundary.
type SizeIsEnforced = tuple[reported: uint, atSize: int, overSize: int]

proc driveSizeIsEnforced(): SizeIsEnforced =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  handle.writeConfigSlot(4, 0x83'u8)
  let shape = handle.slotBufferAt(4)
  result.reported = shape.bytes
  var atSize = newSeq[uint8](int(shape.bytes))
  result.atSize = int(isp1181_rx(handle, cint(3), addr atSize[0],
                                 csize_t(atSize.len)))
  var overSize = newSeq[uint8](int(shape.bytes) + 1)
  result.overSize = int(isp1181_rx(handle, cint(3), addr overSize[0],
                                   csize_t(overSize.len)))
  isp1181_destroy(handle)

let sizeIsEnforced = driveSizeIsEnforced()
let wantSizeIsEnforced: SizeIsEnforced = (reported: 64'u, atSize: 1,
                                          overSize: 0)
check(sizeIsEnforced == wantSizeIsEnforced,
      "buffer geometry: a packet of exactly the reported size is accepted " &
        "and one byte more is refused, so the figure this call decodes out " &
        "of the configuration byte is the boundary the buffer enforces",
      $sizeIsEnforced, $wantSizeIsEnforced)

# THE THREE STATES STAY APART, AND NEITHER CALL ALONE KEEPS THEM APART. The
# pairs below are the table `include/mcf5307.h` prints beside this call, driven
# rather than quoted. Slot 0 is written and its geometry is known, slot 5 is
# written with no buffer here, and slot 4 is never written - so `config_slot`
# alone cannot separate the first from the second and `slot_buffer` alone
# cannot separate the second from the third. Only the pair does, and this case
# also states that the three pairs are pairwise different.
type ThreeStates = tuple[configuredBuffered: tuple[cfg: int, buf: int],
                         configuredUnbuffered: tuple[cfg: int, buf: int],
                         neverWritten: tuple[cfg: int, buf: int]]

proc driveThreeStates(): ThreeStates =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  handle.writeConfigSlot(0, 0x83'u8)
  handle.writeConfigSlot(5, 0xC3'u8)
  # Slot 4 is deliberately left alone - it is endpoint 3, a slot this model
  # carries buffer memory for, so only the write record makes it different from
  # the configured-and-buffered row.
  result.configuredBuffered = (cfg: handle.configSlotAt(0).rc,
                               buf: handle.slotBufferAt(0).rc)
  result.configuredUnbuffered = (cfg: handle.configSlotAt(5).rc,
                                 buf: handle.slotBufferAt(5).rc)
  result.neverWritten = (cfg: handle.configSlotAt(4).rc,
                         buf: handle.slotBufferAt(4).rc)
  isp1181_destroy(handle)

let threeStates = driveThreeStates()
let wantThreeStates: ThreeStates = (configuredBuffered: (cfg: 1, buf: 1),
                                    configuredUnbuffered: (cfg: 1, buf: 0),
                                    neverWritten: (cfg: 0, buf: 0))
check(threeStates == wantThreeStates and
      threeStates.configuredBuffered != threeStates.configuredUnbuffered and
      threeStates.configuredBuffered != threeStates.neverWritten and
      threeStates.configuredUnbuffered != threeStates.neverWritten,
      "buffer geometry: configured-and-buffered, configured-with-no-buffer " &
        "and never-written are three DIFFERENT pairs of answers, and neither " &
        "call on its own separates all three",
      $threeStates, $wantThreeStates)

# The third answer, and the nil pointers. A slot past the sixteenth and a nil
# handle are not "no buffer", and folding them into 0 would report a real
# unbuffered endpoint and a typo with one word. The nil-pointer call is here
# because the contract says either pointer may be nil and the return is still
# the answer.
type BufferRefusal = tuple[pastEnd: int, pastEndBytes: uint,
                           nilRc: int, nilBytes: uint, nilPointers: int]

proc driveBufferRefusal(): BufferRefusal =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  let past = handle.slotBufferAt(configSlotCount)
  let bothNil = int(isp1181_slot_buffer(handle, csize_t(0), nil, nil))
  isp1181_destroy(handle)
  let refused = nilCtx.slotBufferAt(0)
  (pastEnd: past.rc, pastEndBytes: past.bytes, nilRc: refused.rc,
   nilBytes: refused.bytes, nilPointers: bothNil)

let bufferRefusal = driveBufferRefusal()
let wantBufferRefusal: BufferRefusal = (pastEnd: -1,
                                        pastEndBytes: uint(sizeSentinel),
                                        nilRc: -1,
                                        nilBytes: uint(sizeSentinel),
                                        nilPointers: 1)
check(bufferRefusal == wantBufferRefusal,
      "buffer geometry: a slot past the sixteenth and a nil handle answer " &
        "-1 and leave the caller's figures alone, and a call with both " &
        "pointers nil still returns the answer",
      $bufferRefusal, $wantBufferRefusal)

# The report sizes itself the way a log line does: a return that was the size
# COPIED would let a caller read a report that ends early and looks whole. The
# sentinel past the capacity proves nothing was written beyond what the call
# was given.
type ReportSize = tuple[needed: uint, short: uint, kept: string, tail: char,
                        nilHandle: uint]

proc driveReportSize(): ReportSize =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  result.needed = uint(isp1181_report(handle, nil, csize_t(0)))
  const capacity = 8
  var buffer = newString(capacity + 1)
  for i in 0 .. capacity:
    buffer[i] = '#'
  result.short = uint(isp1181_report(handle, cast[ptr cchar](addr buffer[0]),
                                     csize_t(capacity)))
  result.kept = buffer[0 ..< capacity - 1]
  result.tail = buffer[capacity]
  isp1181_destroy(handle)
  result.nilHandle = uint(isp1181_report(nilCtx, nil, csize_t(0)))

let reportSize = driveReportSize()
let wantReportSize: ReportSize = (needed: reportSize.needed, short: reportSize.needed,
                                  kept: "isp1181", tail: '#', nilHandle: 0'u)
check(reportSize == wantReportSize and reportSize.needed > 8'u,
      "report: a buffer too small for the report still gets the SIZE THE " &
        "REPORT NEEDS back, nothing is written past the capacity, and a nil " &
        "handle answers 0",
      $reportSize, $wantReportSize)

# What the report says about a configuration. Slot 2 is written with EPDIR set,
# slot 3 with `0x00`, and slot 4 is left alone. The three sentences are three
# different sentences, and the last of them names no byte at all.
type ReportConfig = tuple[fenced: bool, complete: bool, epdirIn: bool,
                          writtenZero: bool, neverWritten: bool,
                          slotLines: int]

proc driveReportConfig(): ReportConfig =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  handle.writeConfigSlot(2, 0xC1'u8)
  handle.writeConfigSlot(3, 0x00'u8)
  let text = handle.readReport()
  isp1181_destroy(handle)
  var slots = 0
  for line in text.splitLines():
    if line.startsWith("isp1181: config slot "):
      inc slots
  (fenced: text.startsWith(reportBegins) and
     text.strip(leading = false).endsWith(reportEnds),
   complete: text.contains("isp1181: log COMPLETE"),
   epdirIn: text.contains(
     "config slot 2 command 0x22 endpoint 1 buffer 2: written 0xC1 EPDIR=1 IN"),
   writtenZero: text.contains(
     "config slot 3 command 0x23 endpoint 2 buffer 3: written 0x00 EPDIR=0 OUT"),
   neverWritten: text.contains(
     "config slot 4 command 0x24 endpoint 3 buffer 4: NEVER WRITTEN"),
   slotLines: slots)

let reportConfig = driveReportConfig()
let wantReportConfig: ReportConfig = (fenced: true, complete: true,
                                      epdirIn: true, writtenZero: true,
                                      neverWritten: true, slotLines: 16)
check(reportConfig == wantReportConfig,
      "report: every one of the sixteen slots is named, a written byte is " &
        "reported with EPDIR decoded, and a slot the firmware never reached " &
        "is reported as never written and carries no byte",
      $reportConfig, $wantReportConfig)

# Truncation is visible in the report and not only in the arithmetic. The drive
# is the same one `driveOverflow` uses: one refusal past the retention bound.
# The report carries the three figures AND says in words that lines are
# missing. The first line retained is the first line written: a ring would have
# dropped it and kept the tail.
type ReportTruncation = tuple[counters: bool, truncated: bool,
                              saysFirst: bool, complete: bool,
                              firstLine: bool, lineCount: int]

proc driveReportTruncation(): ReportTruncation =
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  var packet = packetBytes
  for _ in 0 .. logCapacity:
    discard isp1181_rx(handle, cint(4), addr packet[0], csize_t(packet.len))
  let text = handle.readReport()
  isp1181_destroy(handle)
  var lines = 0
  for line in text.splitLines():
    if line.startsWith("isp1181: log["):
      inc lines
  (counters: text.contains("isp1181: log written=" & $(logCapacity + 1) &
     " retained=" & $logCapacity & " dropped=1"),
   truncated: text.contains("isp1181: log TRUNCATED - 1 lines"),
   saysFirst: text.contains("retained are the FIRST the model wrote and not " &
     "the last"),
   complete: text.contains("isp1181: log COMPLETE"),
   firstLine: text.contains("isp1181: log[0] event 1: " & logWalk.firstLine),
   lineCount: lines)

let reportTruncation = driveReportTruncation()
let wantReportTruncation: ReportTruncation = (counters: true, truncated: true,
                                              saysFirst: true, complete: false,
                                              firstLine: true,
                                              lineCount: logCapacity)
check(reportTruncation == wantReportTruncation,
      "report: an account that lost lines carries all three counters, says " &
        "in words that it is truncated and that the lines it kept are the " &
        "FIRST ones, and never says it is complete",
      $reportTruncation, $wantReportTruncation)

# ---------------------------------------------------------------------------
# The teardown hook, and the control that says it costs nothing when it is not
# asked for.
#
# The two drives below are the same drive. The only difference between them is
# whether `MCF5307_ISP1181_REPORT` is set, and every observable of the handle
# is captured and compared across the pair, so the unset case is measured and
# not assumed.

const teardownPath = "mcf5307-isp1181-teardown-report.txt"

type Teardown = tuple[report: string, written: uint, retained: uint,
                      irq: int, tx: int]

proc driveForTeardown(): Teardown =
  ## The drive. It is called twice and it does not read the environment.
  let irqBefore = irqCalls
  let txBefore = txCalls
  let handle = isp1181_create(addr hostToken, recordIrq, recordTx)
  setBackend(handle, FullModel)
  handle.writeConfigSlot(2, 0xC1'u8)
  var packet = packetBytes
  discard isp1181_rx(handle, cint(4), addr packet[0], csize_t(packet.len))
  result = (report: handle.readReport(),
            written: uint(isp1181_log_written(handle)),
            retained: uint(isp1181_log_retained(handle)),
            irq: irqCalls - irqBefore, tx: txCalls - txBefore)
  isp1181_destroy(handle)

type TeardownWalk = tuple[unsetSame: bool, unsetWroteNothing: bool,
                          setWroteReport: bool, appended: int,
                          emptyWroteNothing: bool]

proc driveTeardown(): TeardownWalk =
  let dir = getTempDir()
  let target = dir / teardownPath
  removeFile(target)

  # Unset: nothing may be created anywhere and the drive must be unchanged.
  delEnv(reportEnvVar)
  let quiet = driveForTeardown()
  result.unsetWroteNothing = not fileExists(target)

  # Empty is the same as unset: an empty value is a variable the caller
  # cleared, not a request for a report at a path spelled "".
  putEnv(reportEnvVar, "")
  discard driveForTeardown()
  result.emptyWroteNothing = not fileExists(target)

  # Set: two handles are destroyed, and the file has to hold BOTH accounts.
  # A truncating open would leave only the second.
  putEnv(reportEnvVar, target)
  let loud = driveForTeardown()
  discard driveForTeardown()
  delEnv(reportEnvVar)

  result.unsetSame = quiet == loud
  if fileExists(target):
    let body = readFile(target)
    result.setWroteReport = body.contains(loud.report)
    for line in body.splitLines():
      if line == reportBegins:
        inc result.appended
    removeFile(target)

let teardown = driveTeardown()
let wantTeardown: TeardownWalk = (unsetSame: true, unsetWroteNothing: true,
                                  setWroteReport: true, appended: 2,
                                  emptyWroteNothing: true)
check(teardown == wantTeardown,
      "teardown: the variable unset and the variable empty both leave the " &
        "run byte-for-byte as it was and create no file, and the variable " &
        "set appends the whole report once per destroyed handle",
      $teardown, $wantTeardown)

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
