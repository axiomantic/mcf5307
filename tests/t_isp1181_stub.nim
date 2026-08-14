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
