## `t_isp1181` - the ISP1181 model driven by synthetic transactions.
##
## Every opcode and every log line below is a hand-written literal. A suite that
## asked the model which opcodes it implements, or that built an expected log
## line by calling the code that writes it, would pass against any table and any
## wording at all.
##
## EVERY OPCODE AND EVERY LOG LINE BELOW IS A HAND-WRITTEN LITERAL. A suite
## that asked the model which opcodes it implements, or that built an expected
## log line by calling the code that writes it, would pass against any table
## and any wording at all.
##
## The interrupt register is driven as far as it is assigned and no further.
## The endpoint-completion bits are assigned and are asserted here by the event
## that sets each one; the bus bits, the transfer bits and the endpoints this
## model does not carry are not assigned, and there is no event whose bit this
## suite could assert. What is assertable of the register itself is its
## width, its byte order, that a clear is per bit, and that no command byte
## lights a bit. The last of those is written as a sweep with a positive
## control beside it: a model whose register were stuck at zero would satisfy
## the sweep and fails the control.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Nothing here
## is copied from a Philips or NXP document.

import std/strutils

import isp1181/isp1181
import isp1181/fifo

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
  ## The call site is recorded at compile time into `declaredSites` and at run
  ## time into `executedSites`. `tests/case_sites.nim` states what the pair is
  ## for.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, ok, label, got, want)

# ---------------------------------------------------------------------------
# The window.

const
  dataPort = 0x13000000'u32
  commandPort = 0x13000010'u32
  benign = 0x00'u8

var hostToken = 0xC0FFEE

proc ignoreIrq(user: pointer; asserted: cint) {.cdecl.} = discard
proc ignoreTx(user: pointer; endpoint: cint; data: ptr uint8;
              length: csize_t) {.cdecl.} = discard

proc fresh(): ISP1181 =
  newISP1181(addr hostToken, ignoreIrq, ignoreTx)

proc writeVia(m: ISP1181; opcode: uint8; bytes: openArray[uint8]) =
  m.portWrite(commandPort, opcode)
  for value in bytes:
    m.portWrite(dataPort, value)

proc readVia(m: ISP1181; opcode: uint8; width: int): seq[uint8] =
  m.portWrite(commandPort, opcode)
  for _ in 0 ..< width:
    result.add(m.portRead(dataPort))

# ---------------------------------------------------------------------------
# Block 1. What a command byte does to the transfer already in flight.

# An operand that never completed commits nothing. The firmware writes a
# command and then its operand bytes as separate bus accesses, so a command
# that arrives between the two is an ordinary interleaving and not a fault. A
# model that committed the half-built operand would hand back a register value
# the firmware never wrote, and would hand it back without complaint.
type Abandoned = tuple[hw: seq[uint8], mode: seq[uint8], log: seq[string]]

proc abandonedOperand(): Abandoned =
  let m = fresh()
  m.portWrite(commandPort, 0xBA'u8)
  m.portWrite(dataPort, 0xFF'u8)
  m.writeVia(0xB8'u8, [0x01'u8])
  result = (hw: m.readVia(0xBB'u8, 2), mode: m.readVia(0xB9'u8, 1),
            log: m.logLines)

let abandoned = abandonedOperand()
let wantAbandoned: Abandoned = (hw: @[0x00'u8, 0x00'u8], mode: @[0x01'u8],
                                log: @[])
check(abandoned == wantAbandoned,
      "state machine: an operand cut short by a new command commits nothing",
      $abandoned, $wantAbandoned)

# A re-issued command starts its operand from zero. The operand is built by
# OR-ing each byte into a latch, so a latch carried over from the abandoned
# attempt would leave the bits of a byte the firmware wrote once and then
# replaced. The two writes here are the same command with different operands,
# which is the arrangement that separates a reset latch from a kept one.
type Reissued = tuple[hw: seq[uint8], log: seq[string]]

proc reissuedCommand(): Reissued =
  let m = fresh()
  m.portWrite(commandPort, 0xBA'u8)
  m.portWrite(dataPort, 0xFF'u8)
  m.writeVia(0xBA'u8, [0x00'u8, 0x23'u8])
  result = (hw: m.readVia(0xBB'u8, 2), log: m.logLines)

let reissued = reissuedCommand()
let wantReissued: Reissued = (hw: @[0x00'u8, 0x23'u8], log: @[])
check(reissued == wantReissued,
      "state machine: a re-issued command builds its operand from zero",
      $reissued, $wantReissued)

# A refused command abandons the transfer in progress. Both refusing classes
# are driven into the middle of a live two-byte register write: the command the
# documents name and do not implement, and the byte no document numbers at all.
# The transfer must not complete across them. ISP1362 Rev. 06 p.14 calls the
# command "the index of a register" that informs the part which register the
# data phase reaches, and section 15 p.104 makes the command phase an
# unconditional read of the bus as a command code, so the operand byte written
# after the refusals belongs to the last command written and that command is
# `0x9C`. A model that charged it to `0xBA` would complete a register write the
# firmware never finished, and would report every following byte against the
# wrong command.
#
# The two refusals still say different things - a reader who meets the second
# has found a gap in the specification rather than a decision somebody took,
# and a single shared line would hide which one it is.
type Inert = tuple[hw: seq[uint8], log: seq[string]]

proc refusalMidTransfer(): Inert =
  let m = fresh()
  m.portWrite(commandPort, 0xBA'u8)
  m.portWrite(dataPort, 0x00'u8)
  m.portWrite(commandPort, 0xB5'u8)
  m.portWrite(commandPort, 0x9C'u8)
  m.portWrite(dataPort, 0x23'u8)
  result = (hw: m.readVia(0xBB'u8, 2), log: m.logLines)

let inert = refusalMidTransfer()
let wantInert: Inert = (hw: @[0x00'u8, 0x00'u8],
    log: @["isp1181: command 0xB5 (chip identifier) is not implemented; the " &
           "read answers 0x00",
           "isp1181: command 0x9C is not in the specified command set; the " &
           "read answers 0x00",
           "isp1181: command 0x9C (not in the specified command set) was " &
           "refused and takes no operand; the byte is discarded"])
check(inert == wantInert,
      "state machine: a refused command abandons the transfer and the operand " &
        "that follows is charged to the refusal",
      $inert, $wantInert)

# A command that takes no operand leaves the data port with nothing to carry,
# and that is a different state from the one a model has before any command at
# all. The command is recorded here, so a data port that answered from the
# latch would be answering with the previous command's operand.
type NoOperand = tuple[value: uint8, last: int, log: seq[string]]

proc noOperandPort(): NoOperand =
  let m = fresh()
  m.portWrite(commandPort, 0xF4'u8)
  m.portWrite(dataPort, 0xAB'u8)
  result = (value: m.portRead(dataPort), last: m.lastCommand, log: m.logLines)

let noOperand = noOperandPort()
let wantNoOperand: NoOperand = (value: benign, last: 0xF4,
    log: @["isp1181: a data port write of 0xAB arrived with no command " &
           "pending; the byte is discarded",
           "isp1181: a data port read arrived with no command pending; the " &
           "read answers 0x00"])
check(noOperand == wantNoOperand,
      "state machine: a command taking no operand carries nothing on the data port",
      $noOperand, $wantNoOperand)

# The port split is one address bit and not an address. The chip's A0 is wired
# to CPU A4, so bit 4 selects command from data and
# every coarser bit belongs to the board's CS3 decode. A model that compared
# whole addresses would answer the two the firmware happens to use and would
# refuse every other access in the window with no way to see it here.
type Aliased = tuple[canonical: seq[uint8], aliased: seq[uint8], logged: int]

proc aliasedPorts(): Aliased =
  let plain = fresh()
  plain.writeVia(0xB6'u8, [0x35'u8])
  let alias = fresh()
  alias.portWrite(0x13000030'u32, 0xB6'u8)
  alias.portWrite(0x13000020'u32, 0x35'u8)
  alias.portWrite(0x13000090'u32, 0xB7'u8)
  result = (canonical: plain.readVia(0xB7'u8, 1),
            aliased: @[alias.portRead(0x13000004'u32)],
            logged: plain.logLines.len + alias.logLines.len)

let aliased = aliasedPorts()
let wantAliased: Aliased = (canonical: @[0x35'u8], aliased: @[0x35'u8],
                            logged: 0)
check(aliased == wantAliased,
      "state machine: bit 4 alone selects the command port from the data port",
      $aliased, $wantAliased)

# ---------------------------------------------------------------------------
# Block 2. The five FIFOs.

# Which buffer a packet lands in is asserted by its content and not by a count.
# A distinct first byte goes to each endpoint and is read back through the
# selector the authority gives this model, so a mapping that put two endpoints
# in one buffer is separated from one that is correct. The endpoint 0 IN buffer
# takes no delivery at all: a delivery is an OUT transfer, and a model that let
# one land there would show the firmware a packet it never sent.
type Mapping = tuple[accepted: seq[bool], peeked: seq[uint8],
                     pending: seq[int]]

const outSlotOfEndpoint: array[4, int] = [0, 2, 3, 4]
  ## The configuration slot that selects each endpoint's OUT buffer, written
  ## out by hand from ISP1362 Rev. 06 section 15.1.1: the sixteen slots are
  ## control OUT, control IN, then endpoints 1 to 14, so endpoint 0's OUT
  ## buffer is slot 0 and endpoint n's is slot n + 1. Slot 1 is endpoint 0's IN
  ## buffer and appears here for no endpoint, which is why the peek below never
  ## reaches it.

proc endpointMapping(): Mapping =
  let m = fresh()
  for endpoint in 0 .. 3:
    result.accepted.add(m.deliver(endpoint, [uint8(0xE0 + endpoint), 0x00'u8]))
  for endpoint in 0 .. 3:
    m.portWrite(commandPort, uint8(0x20 + outSlotOfEndpoint[endpoint]))
    m.portWrite(commandPort, 0xD2'u8)
    result.peeked.add(m.portRead(dataPort))
  for index in 0 ..< fifoCount:
    result.pending.add(fifoAt(m, index).pending)

let mapping = endpointMapping()
let wantMapping: Mapping = (accepted: @[true, true, true, true],
    peeked: @[0xE0'u8, 0xE1'u8, 0xE2'u8, 0xE3'u8],
    pending: @[1, 0, 1, 1, 1])
check(mapping == wantMapping,
      "fifos: each endpoint's packet lands in its own buffer and none in EP0 IN",
      $mapping, $wantMapping)

# A configuration slot with no buffer behind it is selected and says so. Every
# one of section 15.1.1's sixteen slots is accepted, and eleven of them
# configure buffer memory this model does not carry, so the selection a peek
# reads can now name a slot with no FIFO. `0x25` selects slot 5 after `0x22`
# selected slot 2, which holds a delivered byte: a model that indexed its FIFO
# array by the slot would read out of bounds, and one that quietly kept the
# previous selection would answer `0xA1` and call it endpoint 4's.
type Selection = tuple[peeked: uint8, log: seq[string]]

proc refusedSelection(): Selection =
  let m = fresh()
  discard m.deliver(0, [0xA0'u8])
  discard m.deliver(1, [0xA1'u8])
  m.portWrite(commandPort, 0x22'u8)
  m.portWrite(commandPort, 0x25'u8)
  m.portWrite(commandPort, 0xD2'u8)
  result = (peeked: m.portRead(dataPort), log: m.logLines)

let selection = refusedSelection()
let wantSelection: Selection = (peeked: benign,
    log: @["isp1181: peek follows the configuration of slot 5, which this " &
           "model carries no buffer for; the read answers 0x00"])
check(selection == wantSelection,
      "fifos: a peek after the configuration of a slot with no buffer names " &
        "the slot and answers benignly",
      $selection, $wantSelection)

# The buffer's own size is accepted and one byte more is not. A refusal at the
# exact capacity and a refusal one byte past it are the same outcome from the
# firmware's side, so only driving both separates the boundary this model
# carries from one placed a byte early.
type Boundary = tuple[atCapacity: seq[bool], overCapacity: seq[bool],
                      pending: seq[int]]

proc capacityBoundary(): Boundary =
  for row in [(endpoint: 1, index: 2, capacity: 16),
              (endpoint: 2, index: 3, capacity: 64)]:
    var exact: seq[uint8]
    for i in 0 ..< row.capacity:
      exact.add(uint8(i))
    var over = exact
    over.add(0xFF'u8)
    let fits = fresh()
    result.atCapacity.add(fits.deliver(row.endpoint, exact))
    result.pending.add(fifoAt(fits, row.index).pending)
    let spills = fresh()
    result.overCapacity.add(spills.deliver(row.endpoint, over))
    result.pending.add(fifoAt(spills, row.index).pending)

let boundary = capacityBoundary()
let wantBoundary: Boundary = (atCapacity: @[true, true],
                              overCapacity: @[false, false],
                              pending: @[1, 0, 1, 0])
check(boundary == wantBoundary,
      "fifos: a packet of exactly the buffer's size fits and one byte more does not",
      $boundary, $wantBoundary)

# THE TWO REFUSALS EACH SAY WHICH ONE THEY ARE, IN WORDS AND IN FIGURES. A full
# buffer is ordinary flow control and an oversized packet is a fault in whatever
# produced it. They shared one sentence until 2026-08-28 and were separated only
# by the packet's size against the buffer's occupancy, so the line could be read
# only by a reader who already knew `fifoShape` - which is the reader who does
# not need the line. The figures are still asserted here; the CAUSE is asserted
# with them. The full-buffer refusal is driven on endpoint 3, which holds ONE
# packet. A buffer too many would accept the second packet, so the refusal is
# the assertion and the count is not.
type Refusals = tuple[full: seq[string], oversize: seq[string]]

proc refusalLines(): Refusals =
  let full = fresh()
  discard full.deliver(3, [0x01'u8, 0x02'u8])
  discard full.deliver(3, [0x03'u8, 0x04'u8])
  result.full = full.logLines
  let spills = fresh()
  var big: seq[uint8]
  for i in 0 ..< 17:
    big.add(uint8(i))
  discard spills.deliver(1, big)
  result.oversize = spills.logLines

let refusals = refusalLines()
let wantRefusals: Refusals = (
    full: @["isp1181: endpoint 3 refused a packet of 2 bytes because its " &
            "buffer is FULL; it holds 1 of 1 and nothing has taken the " &
            "packet already there"],
    oversize: @["isp1181: endpoint 1 refused a packet of 17 bytes because " &
                "the buffer is 16 bytes LONG; it holds 0 of 2"])
check(refusals == wantRefusals,
      "fifos: a full buffer and an oversized packet each name their own " &
        "cause, and carry the figures too",
      $refusals, $wantRefusals)

# A delivery to an endpoint this model does not carry is dropped and said so.
# The endpoints beyond the five buffers are the ones the documents place in the
# not-needed list, and a negative endpoint is what a caller's own arithmetic
# produces when it goes wrong. Both answer the same way and neither is silent.
type Unimplemented = tuple[accepted: seq[bool], pending: seq[int],
                           log: seq[string]]

proc unimplementedEndpoint(): Unimplemented =
  let m = fresh()
  for endpoint in [4, 14, -1]:
    result.accepted.add(m.deliver(endpoint, [0x77'u8]))
  for index in 0 ..< fifoCount:
    result.pending.add(fifoAt(m, index).pending)
  result.log = m.logLines

let unimplemented = unimplementedEndpoint()
let wantUnimplemented: Unimplemented = (accepted: @[false, false, false],
    pending: @[0, 0, 0, 0, 0],
    log: @["isp1181: a packet reached endpoint 4, which this model does not " &
           "implement; the packet is dropped",
           "isp1181: a packet reached endpoint 14, which this model does not " &
           "implement; the packet is dropped",
           "isp1181: a packet reached endpoint -1, which this model does not " &
           "implement; the packet is dropped"])
check(unimplemented == wantUnimplemented,
      "fifos: a delivery to an endpoint this model does not carry is dropped and logged",
      $unimplemented, $wantUnimplemented)

# ---------------------------------------------------------------------------
# Block 3. The interrupt register.

# The register is thirty-two bits and it reads least significant byte first.
# The two bits driven are the lowest and the highest, so a register narrowed to
# any smaller width drops one of them, and a byte order reversed at the port
# swaps them. The line stays low throughout because the enable is zero, which
# is what separates the register from the line it feeds.
type Register = tuple[readBack: seq[uint8], asserted: bool, log: seq[string]]

proc wideRegister(): Register =
  let m = fresh()
  m.raiseInterrupt(0x8000_0001'u32)
  result = (readBack: m.readVia(0xC0'u8, 4), asserted: m.irqAsserted,
            log: m.logLines)

let register = wideRegister()
let wantRegister: Register = (
    readBack: @[0x01'u8, 0x00'u8, 0x00'u8, 0x80'u8], asserted: false, log: @[])
check(register == wantRegister,
      "interrupt register: thirty-two bits, read least significant byte first",
      $register, $wantRegister)

# A clear takes the bits of its mask and leaves the rest. A clear that emptied
# the register would satisfy any case that cleared its only set bit, so two
# bits are set and taken away one at a time.
type Cleared = tuple[before: seq[uint8], after: seq[uint8],
                     emptied: seq[uint8]]

proc perBitClear(): Cleared =
  let m = fresh()
  m.raiseInterrupt(0x8000_0001'u32)
  result.before = m.readVia(0xC0'u8, 4)
  m.clearInterrupt(0x0000_0001'u32)
  result.after = m.readVia(0xC0'u8, 4)
  m.clearInterrupt(0x8000_0000'u32)
  result.emptied = m.readVia(0xC0'u8, 4)

let cleared = perBitClear()
let wantCleared: Cleared = (before: @[0x01'u8, 0x00'u8, 0x00'u8, 0x80'u8],
                            after: @[0x00'u8, 0x00'u8, 0x00'u8, 0x80'u8],
                            emptied: @[0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8])
check(cleared == wantCleared,
      "interrupt register: a clear takes its mask's bits and leaves the others",
      $cleared, $wantCleared)

# No command byte lights a bit of the interrupt register. No source on this
# machine assigns a bit to an event, so a bit that appeared would be a number
# somebody picked, and the firmware would obey it. Every command byte is driven
# and the register is read after each.
#
# The control is in the same case because the sweep alone cannot fail for the
# right reason. A register that could never hold anything satisfies a sweep
# looking for zero, so the control raises a bit and reads it back: without it
# this case passes against a model that does nothing at all.
type Quiet = tuple[firstBad: string, driven: int, control: seq[uint8]]

proc noCommandRaises(): Quiet =
  result = (firstBad: "", driven: 0, control: @[])
  for value in 0 .. 255:
    let m = fresh()
    m.portWrite(commandPort, uint8(value))
    inc result.driven
    let readBack = m.readVia(0xC0'u8, 4)
    if result.firstBad.len == 0 and
        readBack != @[0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8]:
      result.firstBad = "0x" & toHex(uint8(value)) & " left the register " &
        $readBack
  let control = fresh()
  control.raiseInterrupt(0x0000_0040'u32)
  result.control = control.readVia(0xC0'u8, 4)

let quiet = noCommandRaises()
let wantQuiet: Quiet = (firstBad: "", driven: 256,
                        control: @[0x40'u8, 0x00'u8, 0x00'u8, 0x00'u8])
check(quiet == wantQuiet,
      "interrupt register: no command byte lights a bit, and a bit can be lit",
      $quiet, $wantQuiet)

# A delivery lights the bit its own endpoint owns, and it lights the line. The
# interrupt enable is driven to `0x1F07` first, so every bit the firmware arms
# is armed while the packets arrive. Every endpoint is driven in one case
# because a single shared bit would pass any case that drove one endpoint. The
# expected register is written as one hand-typed literal per byte: bit 8 for
# endpoint 0 OUT and bits 10, 11 and 12 for endpoints 1 to 3, which is
# `0x0000_1D00` and reads back least significant byte first.
type Deliveries = tuple[accepted: seq[bool], interrupt: seq[uint8],
                        asserted: bool, log: seq[string]]

proc deliverEverywhere(): Deliveries =
  let m = fresh()
  m.writeVia(0xC2'u8, [0x07'u8, 0x1F'u8, 0x00'u8, 0x00'u8])
  for endpoint in 0 .. 3:
    result.accepted.add(m.deliver(endpoint, [0x5E'u8]))
  result.interrupt = m.readVia(0xC0'u8, 4)
  result.asserted = m.irqAsserted
  result.log = m.logLines

let deliveries = deliverEverywhere()
let wantDeliveries: Deliveries = (accepted: @[true, true, true, true],
    interrupt: @[0x00'u8, 0x1D'u8, 0x00'u8, 0x00'u8], asserted: true,
    log: @[])
check(deliveries == wantDeliveries,
      "interrupt register: a delivery lights its own endpoint's bit and the line",
      $deliveries, $wantDeliveries)

# A delivery the model refuses lights nothing, and the proof is on the handle
# whose endpoint 3 just answered. A zero register after a refusal proves
# nothing on its own - a model that had never assigned a bit would answer zero
# too - so the known positive and the two known negatives run through the same
# handle, the same enable and the same entry point. Endpoint 3 is
# single-buffered, so its second packet is refused by a buffer that exists;
# endpoint 4 is refused by a model that does not carry it.
type Refused = tuple[first: bool, afterFirst: seq[uint8], second: bool,
                     afterSecond: seq[uint8], fourth: bool,
                     afterFourth: seq[uint8], asserted: bool,
                     log: seq[string]]

proc refusedDelivery(): Refused =
  let m = fresh()
  m.writeVia(0xC2'u8, [0x07'u8, 0x1F'u8, 0x00'u8, 0x00'u8])
  result.first = m.deliver(3, [0x01'u8])
  result.afterFirst = m.readVia(0xC0'u8, 4)
  m.clearInterrupt(0xFFFF_FFFF'u32)
  result.second = m.deliver(3, [0x02'u8])
  result.afterSecond = m.readVia(0xC0'u8, 4)
  result.fourth = m.deliver(4, [0x03'u8])
  result.afterFourth = m.readVia(0xC0'u8, 4)
  result.asserted = m.irqAsserted
  result.log = m.logLines

let refused = refusedDelivery()
let wantRefused: Refused = (
    first: true, afterFirst: @[0x00'u8, 0x10'u8, 0x00'u8, 0x00'u8],
    second: false, afterSecond: @[0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8],
    fourth: false, afterFourth: @[0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8],
    asserted: false,
    log: @["isp1181: endpoint 3 refused a packet of 1 bytes because its " &
           "buffer is FULL; it holds 1 of 1 and nothing has taken the " &
           "packet already there",
           "isp1181: a packet reached endpoint 4, which this model does not " &
           "implement; the packet is dropped"])
check(refused == wantRefused,
      "interrupt register: a refused delivery lights nothing, beside one that does",
      $refused, $wantRefused)

# Reading an endpoint's status takes that endpoint's bit and leaves the rest.
# This is the route that keeps the firmware out of its own handler. The
# interrupt register does not clear on a `0xC0` read - the case above this
# block pins that - and the firmware's service routine never writes it back,
# so a bit that only a Nim-side caller could clear would leave the emulated
# firmware spinning. `0x50+n` is the route, and it is inherited from ISP1362
# Rev. 06 p.53 rather than read from an ISP1181 document.
#
# Two bits are lit and taken away one at a time, so a status read that emptied
# the register is separated from one that takes its own endpoint's bit.
type StatusClear = tuple[before: seq[uint8], status: seq[uint8],
                         afterOne: seq[uint8], afterBoth: seq[uint8],
                         asserted: seq[bool], log: seq[string]]

proc statusReadClears(): StatusClear =
  let m = fresh()
  m.writeVia(0xC2'u8, [0x07'u8, 0x1F'u8, 0x00'u8, 0x00'u8])
  discard m.deliver(0, [0x11'u8])
  discard m.deliver(1, [0x22'u8])
  result.before = m.readVia(0xC0'u8, 4)
  result.asserted.add(m.irqAsserted)
  result.status = m.readVia(0x52'u8, 1)
  result.afterOne = m.readVia(0xC0'u8, 4)
  result.asserted.add(m.irqAsserted)
  discard m.readVia(0x50'u8, 1)
  result.afterBoth = m.readVia(0xC0'u8, 4)
  result.asserted.add(m.irqAsserted)
  result.log = m.logLines

let statusClear = statusReadClears()
let wantStatusClear: StatusClear = (
    before: @[0x00'u8, 0x05'u8, 0x00'u8, 0x00'u8], status: @[0x20'u8],
    afterOne: @[0x00'u8, 0x01'u8, 0x00'u8, 0x00'u8],
    afterBoth: @[0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8],
    asserted: @[true, true, false], log: @[])
check(statusClear == wantStatusClear,
      "interrupt register: a status read takes its own endpoint's bit and drops the line",
      $statusClear, $wantStatusClear)

# The host collecting the packet is what lights endpoint 0 IN, and the
# validate is not. A validate is the firmware saying the buffer is now the
# host's; the transfer has not happened yet, and a model that raised the
# interrupt there would tell the firmware a packet was delivered to a host
# that had not asked for it. The register is read between the two so that the
# silence at the validate is asserted rather than assumed.
type InInterrupt = tuple[afterValidate: seq[uint8], sent: bool,
                         afterToken: seq[uint8], asserted: bool,
                         log: seq[string]]

proc hostCollectLights(): InInterrupt =
  let m = fresh()
  m.writeVia(0xC2'u8, [0x07'u8, 0x1F'u8, 0x00'u8, 0x00'u8])
  m.writeVia(0x01'u8, [0x02'u8, 0x00'u8, 0xAB'u8, 0xCD'u8])
  m.portWrite(commandPort, 0x61'u8)
  result.afterValidate = m.readVia(0xC0'u8, 4)
  result.sent = m.transmit(0)
  result.afterToken = m.readVia(0xC0'u8, 4)
  result.asserted = m.irqAsserted
  result.log = m.logLines

let inInterrupt = hostCollectLights()
let wantInInterrupt: InInterrupt = (
    afterValidate: @[0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8], sent: true,
    afterToken: @[0x00'u8, 0x02'u8, 0x00'u8, 0x00'u8], asserted: true,
    log: @[])
check(inInterrupt == wantInInterrupt,
      "interrupt register: the host collecting endpoint 0 IN lights bit 9, and the validate does not",
      $inInterrupt, $wantInInterrupt)

# ---------------------------------------------------------------------------
# Block 4. The SOFTCT bit.

# SOFTCT IS BIT 0 OF THE MODE BYTE AND NOTHING ELSE. The rows that matter are
# the ones where the bit
# and the byte disagree: `0xFE` is every other bit set with SOFTCT clear, and
# `0x80` is a single unrelated bit. A model reading the byte's truth rather
# than the bit's answers both of those wrongly and answers `0x00` and `0x01`
# correctly.
type SoftctRow = tuple[written: uint8, readBack: uint8, on: bool]
type Softct = tuple[rows: seq[SoftctRow], afterReset: bool]

proc softctTable(): Softct =
  for written in [0x00'u8, 0x01'u8, 0xFE'u8, 0xFF'u8, 0x80'u8]:
    let m = fresh()
    m.writeVia(0xB8'u8, [written])
    result.rows.add((written: written, readBack: m.readVia(0xB9'u8, 1)[0],
                     on: m.softct))
  let m = fresh()
  m.writeVia(0xB8'u8, [0xFF'u8])
  m.portWrite(commandPort, 0xF6'u8)
  result.afterReset = m.softct

let softctCase = softctTable()
let wantSoftct: Softct = (rows: @[
    (written: 0x00'u8, readBack: 0x00'u8, on: false),
    (written: 0x01'u8, readBack: 0x01'u8, on: true),
    (written: 0xFE'u8, readBack: 0xFE'u8, on: false),
    (written: 0xFF'u8, readBack: 0xFF'u8, on: true),
    (written: 0x80'u8, readBack: 0x80'u8, on: false)], afterReset: false)
check(softctCase == wantSoftct,
      "softct: the bit follows bit 0 of the mode byte and a reset clears it",
      $softctCase, $wantSoftct)

# ---------------------------------------------------------------------------
# Block 5. The negative case.

# A command this model does not implement answers benignly, writes one line,
# and changes nothing. The model is driven into a state where every field it
# carries holds something other than its reset value first, so that "changes
# nothing" is an assertion about a live model rather than a restatement of what
# a fresh one reads. The read that follows the refusal reports itself too: a
# read that answered zero in silence is the one outcome that would let the
# firmware take the benign value for an answer.
#
# The command left pending is the refused one: the refusal takes the command
# port's latch, and the data-port read that follows is reported against the
# byte the firmware actually wrote rather than against a command it had
# finished with.
type Negative = tuple[refusal: seq[string], value: uint8, port: uint8,
                      last: int, afterRead: seq[string], hw: seq[uint8],
                      mode: seq[uint8], interrupt: seq[uint8],
                      pending: seq[int]]

proc unimplementedCommand(): Negative =
  let m = fresh()
  m.writeVia(0xBA'u8, [0x00'u8, 0x23'u8])
  m.writeVia(0xB8'u8, [0x01'u8])
  m.raiseInterrupt(0x0000_0004'u32)
  discard m.deliver(2, [0x6D'u8])
  let before = m.logLines.len
  m.portWrite(commandPort, 0xB5'u8)
  result.refusal = m.logLines[before .. ^1]
  result.value = m.portRead(dataPort)
  result.port = m.portRead(commandPort)
  result.last = m.lastCommand
  result.afterRead = m.logLines[before .. ^1]
  result.hw = m.readVia(0xBB'u8, 2)
  result.mode = m.readVia(0xB9'u8, 1)
  result.interrupt = m.readVia(0xC0'u8, 4)
  for index in 0 ..< fifoCount:
    result.pending.add(fifoAt(m, index).pending)

let negative = unimplementedCommand()
let wantNegative: Negative = (
    refusal: @["isp1181: command 0xB5 (chip identifier) is not implemented; " &
               "the read answers 0x00"],
    value: benign, port: benign, last: 0xB5,
    afterRead: @["isp1181: command 0xB5 (chip identifier) is not " &
                 "implemented; the read answers 0x00",
                 "isp1181: command 0xB5 (chip identifier) was refused; the " &
                 "read answers 0x00"],
    hw: @[0x00'u8, 0x23'u8], mode: @[0x01'u8],
    interrupt: @[0x04'u8, 0x08'u8, 0x00'u8, 0x00'u8],
    pending: @[0, 0, 0, 1, 0])
check(negative == wantNegative,
      "negative: an unimplemented command answers benignly, logs, and changes nothing",
      $negative, $wantNegative)

# ---------------------------------------------------------------------------
# The device-to-host path and the callback it owes.
#
# THE HOST INSTALLS A TRANSMIT CALLBACK AT CONSTRUCTION AND IT IS THE ONLY WAY
# A BYTE LEAVES THIS MODEL. A model that stored the callback and never called
# it looks exactly like one whose device had nothing to send, from the host's
# side and from the log's, so the case below drives a packet into the IN buffer
# and asserts the CALL - its endpoint, its length and every byte of it.
#
# EVERY BYTE AND EVERY LOG LINE BELOW IS A HAND-WRITTEN LITERAL.
#
# The queue is driven directly here on purpose. `queueIn` and `transmit` are
# the mechanism, and this block takes them as the subject; the block below
# drives the same mechanism from the firmware's own command bytes, and
# `t_isp1181_stub` drives it from the published C entry points. A case that
# went through the ports here would be asserting the decode twice and the
# callback once.

type TxRecord = tuple[calls: int, endpoint: int, bytes: seq[uint8],
                      length: int]

var txSeen: TxRecord = (calls: 0, endpoint: -1, bytes: @[], length: -1)

proc recordTx(user: pointer; endpoint: cint; data: ptr uint8;
              length: csize_t) {.cdecl.} =
  inc txSeen.calls
  txSeen.endpoint = int(endpoint)
  txSeen.length = int(length)
  txSeen.bytes = @[]
  if not data.isNil:
    let raw = cast[ptr UncheckedArray[uint8]](data)
    for index in 0 ..< int(length):
      txSeen.bytes.add(raw[index])

proc recording(): ISP1181 =
  newISP1181(addr hostToken, ignoreIrq, recordTx)

const inPacket: array[4, uint8] = [0xDE'u8, 0xAD'u8, 0xBE'u8, 0xEF'u8]

# A queued packet reaches the host once and the buffer is then empty. The
# second transmit is what separates a buffer that was consumed from one that
# was copied: a model that left the packet in place would call the host twice
# with the same bytes and the firmware would never learn the transfer ended.
type TxWalk = tuple[queued: bool, sent: bool, seen: TxRecord, again: bool,
                    callsAfter: int, log: seq[string]]

proc driveTransmit(): TxWalk =
  txSeen = (calls: 0, endpoint: -1, bytes: @[], length: -1)
  let m = recording()
  let queued = m.queueIn(0, inPacket)
  let sent = m.transmit(0)
  let seen = txSeen
  let again = m.transmit(0)
  (queued: queued, sent: sent, seen: seen, again: again,
   callsAfter: txSeen.calls, log: m.logLines)

let txWalk = driveTransmit()
let wantTxWalk: TxWalk = (
    queued: true, sent: true,
    seen: (calls: 1, endpoint: 0,
           bytes: @[0xDE'u8, 0xAD'u8, 0xBE'u8, 0xEF'u8], length: 4),
    again: false, callsAfter: 1,
    log: @["isp1181: endpoint 0 IN has no packet to send; the host is not " &
           "called"])
check(txWalk == wantTxWalk,
      "transmit: a queued packet reaches the host callback once, whole, and " &
        "leaves the buffer empty",
      $txWalk, $wantTxWalk)

# The refusals each name their own reason. An endpoint this model does not
# implement, an endpoint whose single buffer the firmware has left facing OUT,
# and an empty packet are three different findings, and a model that answered
# all three the same way would hide which one a reader met. Endpoint 1 is
# driven on a handle no configuration byte has reached, and Table 110 gives
# every bit of that register a reset value of 0, so EPDIR reads OUT.
type TxRefusal = tuple[queued: seq[bool], calls: int, log: seq[string]]

proc driveTxRefusals(): TxRefusal =
  txSeen = (calls: 0, endpoint: -1, bytes: @[], length: -1)
  let m = recording()
  var queued: seq[bool]
  for endpoint in [1, 4, -1]:
    queued.add(m.queueIn(endpoint, inPacket))
  queued.add(m.queueIn(0, newSeq[uint8](0)))
  (queued: queued, calls: txSeen.calls, log: m.logLines)

let txRefusal = driveTxRefusals()
let wantTxRefusal: TxRefusal = (
    queued: @[false, false, false, false], calls: 0,
    log: @["isp1181: endpoint 1 is configured OUT - EPDIR is 0 in its " &
           "DcEndpointConfiguration - so it has no IN buffer; nothing is " &
           "queued",
           "isp1181: a transmit was queued for endpoint 4, which this model " &
           "does not implement; nothing is queued",
           "isp1181: a transmit was queued for endpoint -1, which this " &
           "model does not implement; nothing is queued",
           "isp1181: an empty packet was queued for endpoint 0 IN and no " &
           "source on this machine states what a zero-length IN packet " &
           "carries; nothing is queued"])
check(txRefusal == wantTxRefusal,
      "transmit: a queue this model cannot honour is refused, names its " &
        "reason and calls no host",
      $txRefusal, $wantTxRefusal)

# EPDIR decides which endpoint may transmit, and the two outcomes are driven on
# one handle. ISP1362 Rev. 06 Table 110 puts EPDIR at bit 6 of
# DcEndpointConfiguration and Table 111 gives it as 0 = OUT, 1 = IN; section
# 15.1.1 orders the sixteen configuration slots control OUT, control IN, then
# endpoints 1 to 14, so `0x22` carries endpoint 1's byte and `0x23` carries
# endpoint 2's. `0xC1 xor 0x81` is `0x40`, so the positive and the negative
# differ in that ONE bit and in nothing else.
#
# FFOSZ is held equal across the pair and is not a size claim here. Giving each
# endpoint the FFOSZ its own buffer would encode varies a second field of the
# byte, and a pair that varies two fields isolates neither. This model reads a
# buffer's shape out of `fifoShape` in `src/isp1181/isp1181.nim`; it reads no
# size out of DcEndpointConfiguration at all.
type Epdir = tuple[queuedIn: bool, sentIn: bool, seen: TxRecord,
                   queuedOut: bool, interruptRegister: seq[uint8],
                   log: seq[string]]

proc driveEpdir(): Epdir =
  txSeen = (calls: 0, endpoint: -1, bytes: @[], length: -1)
  let m = recording()
  m.writeVia(0x22'u8, [0xC1'u8])
  m.writeVia(0x23'u8, [0x81'u8])
  let queuedIn = m.queueIn(1, inPacket)
  let sentIn = m.transmit(1)
  let queuedOut = m.queueIn(2, inPacket)
  (queuedIn: queuedIn, sentIn: sentIn, seen: txSeen, queuedOut: queuedOut,
   interruptRegister: m.readVia(0xC0'u8, 4), log: m.logLines)

let epdir = driveEpdir()
let wantEpdir: Epdir = (
    queuedIn: true, sentIn: true,
    seen: (calls: 1, endpoint: 1,
           bytes: @[0xDE'u8, 0xAD'u8, 0xBE'u8, 0xEF'u8], length: 4),
    queuedOut: false,
    interruptRegister: @[0x00'u8, 0x04'u8, 0x00'u8, 0x00'u8],
    log: @["isp1181: endpoint 2 is configured OUT - EPDIR is 0 in its " &
           "DcEndpointConfiguration - so it has no IN buffer; nothing is " &
           "queued"])
check(epdir == wantEpdir,
      "EPDIR: an endpoint configured IN transmits and raises its own bit, " &
        "and one configured OUT is refused by name",
      $epdir, $wantEpdir)

# EPDIR refuses in both directions, and the negative half is driven here. A
# single endpoint buffer faces ONE way, so a host packet arriving at an
# endpoint the firmware configured IN has nowhere to land, and a model that
# accepted it would raise that endpoint's interrupt and show the firmware an
# OUT packet on a buffer it had declared for transmission. The endpoint
# configured OUT in the same run is the control: `0xC1 xor 0x81` is `0x40`, so
# the two differ in EPDIR and in nothing else.
type DeliverEpdir = tuple[intoIn: bool, intoOut: bool, pending: seq[int],
                          log: seq[string]]

proc driveDeliverEpdir(): DeliverEpdir =
  let m = fresh()
  m.writeVia(0x22'u8, [0xC1'u8])
  m.writeVia(0x23'u8, [0x81'u8])
  let intoIn = m.deliver(1, [0x11'u8])
  let intoOut = m.deliver(2, [0x22'u8])
  var pending: seq[int]
  for index in 0 ..< fifoCount:
    pending.add(fifoAt(m, index).pending)
  (intoIn: intoIn, intoOut: intoOut, pending: pending, log: m.logLines)

let deliverEpdir = driveDeliverEpdir()
let wantDeliverEpdir: DeliverEpdir = (
    intoIn: false, intoOut: true, pending: @[0, 0, 0, 1, 0],
    log: @["isp1181: endpoint 1 is configured IN - EPDIR is 1 in its " &
           "DcEndpointConfiguration - so it has no OUT buffer; the packet " &
           "is dropped"])
check(deliverEpdir == wantDeliverEpdir,
      "EPDIR: a host packet for an endpoint configured IN is refused by " &
        "name and one configured OUT is taken",
      $deliverEpdir, $wantDeliverEpdir)

# A host that installed no callback keeps its packet. Dropping the packet on
# the floor would leave the firmware with a buffer that emptied itself and a
# transfer that never happened.
type NilTx = tuple[queued: bool, sent: bool, stillThere: int,
                   log: seq[string]]

proc driveNilTx(): NilTx =
  let m = newISP1181(addr hostToken, ignoreIrq, nil)
  let queued = m.queueIn(0, inPacket)
  let sent = m.transmit(0)
  (queued: queued, sent: sent, stillThere: fifoAt(m, 1).pending,
   log: m.logLines)

let nilTx = driveNilTx()
let wantNilTx: NilTx = (
    queued: true, sent: false, stillThere: 1,
    log: @["isp1181: endpoint 0 IN holds a packet and the host installed no " &
           "transmit callback; the packet is kept"])
check(nilTx == wantNilTx,
      "transmit: a model with no host callback keeps the packet and says so",
      $nilTx, $wantNilTx)

# ---------------------------------------------------------------------------
# The data-flow commands.
#
# The check that matters is a round trip through the ports and not a call of
# `fifoAt`. A packet the host delivered has to leave the model through the same
# command/data ports the firmware drives, or the model has an OUT FIFO nothing
# can dequeue.
#
# The length prefix is in band. The authority puts the packet length in the
# first two bytes of the endpoint buffer, lower byte first, so a read of an
# N-byte packet yields N + 2 bytes. A model that answered the payload alone
# would hand the firmware a packet two bytes short of what it was told to
# expect, and nothing in the payload would mark it short.

const outPacket = [0xDE'u8, 0xAD'u8, 0xBE'u8, 0xEF'u8]

type ReadOut = tuple[delivered: bool, readBack: seq[uint8],
                     pendingAfterRead: int, pendingAfterClear: int,
                     log: seq[string]]

proc driveReadOut(): ReadOut =
  let m = fresh()
  let delivered = m.deliver(0, outPacket)
  let readBack = m.readVia(0x10'u8, 2 + outPacket.len)
  let pendingAfterRead = fifoAt(m, 0).pending
  m.portWrite(commandPort, 0x70'u8)
  (delivered: delivered, readBack: readBack,
   pendingAfterRead: pendingAfterRead,
   pendingAfterClear: fifoAt(m, 0).pending, log: m.logLines)

let readOut = driveReadOut()
let wantReadOut: ReadOut = (
    delivered: true,
    readBack: @[0x04'u8, 0x00'u8, 0xDE'u8, 0xAD'u8, 0xBE'u8, 0xEF'u8],
    pendingAfterRead: 1, pendingAfterClear: 0, log: @[])
check(readOut == wantReadOut,
      "data flow: a delivered packet is read out whole behind its length " &
        "prefix, survives the read and is consumed by the clear",
      $readOut, $wantReadOut)

# The control comes from the same population and the same handle. A zero read
# from an endpoint the model does not carry proves nothing on its own: an
# implementation that refused EVERY read buffer command would produce it too.
# `0x16` is read endpoint 5 buffer - numbered by the authority, outside this
# model's four endpoints - and it is driven on the handle the positive case
# just succeeded on, through the same `readVia`.
type ReadOutControl = tuple[readBack: seq[uint8], log: seq[string]]

proc driveReadOutControl(): ReadOutControl =
  let m = fresh()
  discard m.deliver(0, outPacket)
  discard m.readVia(0x10'u8, 2 + outPacket.len)
  let before = m.logLines.len
  let readBack = m.readVia(0x16'u8, 2 + outPacket.len)
  (readBack: readBack, log: m.logLines[before .. ^1])

let readOutControl = driveReadOutControl()
# Every trailing line names the refused command and not the one before it. The
# refused `0x16` takes the command port's latch, so the six reads that follow
# are reported against `0x16`. A model that left `0x10` pending would answer the
# same six benign bytes and tell a reader that an exhausted control-OUT read was
# being over-read, which names the wrong endpoint and the wrong fault.
let wantReadOutControl: ReadOutControl = (
    readBack: @[benign, benign, benign, benign, benign, benign],
    log: @["isp1181: command 0x16 (endpoint 5 buffer read) is not " &
           "implemented; the read answers 0x00",
           "isp1181: command 0x16 (endpoint 5 buffer read) was refused; the " &
           "read answers 0x00",
           "isp1181: command 0x16 (endpoint 5 buffer read) was refused; the " &
           "read answers 0x00",
           "isp1181: command 0x16 (endpoint 5 buffer read) was refused; the " &
           "read answers 0x00",
           "isp1181: command 0x16 (endpoint 5 buffer read) was refused; the " &
           "read answers 0x00",
           "isp1181: command 0x16 (endpoint 5 buffer read) was refused; the " &
           "read answers 0x00",
           "isp1181: command 0x16 (endpoint 5 buffer read) was refused; the " &
           "read answers 0x00"])
check(readOutControl == wantReadOutControl,
      "data flow: a read buffer command for an endpoint outside this model " &
        "is refused on the same handle that just answered one",
      $readOutControl, $wantReadOutControl)

# Write control IN buffer stages the bytes and Validate commits them; only
# after the validate can `transmit` hand them to the host.
type WriteIn = tuple[pendingBeforeValidate: int, pendingAfterValidate: int,
                     sent: bool, seen: TxRecord, log: seq[string]]

proc driveWriteIn(): WriteIn =
  txSeen = (calls: 0, endpoint: -1, bytes: @[], length: -1)
  let m = recording()
  m.writeVia(0x01'u8, [0x02'u8, 0x00'u8, 0x55'u8, 0xAA'u8])
  let before = fifoAt(m, 1).pending
  m.portWrite(commandPort, 0x61'u8)
  let after = fifoAt(m, 1).pending
  let sent = m.transmit(0)
  (pendingBeforeValidate: before, pendingAfterValidate: after,
   sent: sent, seen: txSeen, log: m.logLines)

let writeIn = driveWriteIn()
let wantWriteIn: WriteIn = (
    pendingBeforeValidate: 0, pendingAfterValidate: 1, sent: true,
    seen: (calls: 1, endpoint: 0, bytes: @[0x55'u8, 0xAA'u8], length: 2),
    log: @[])
check(writeIn == wantWriteIn,
      "data flow: write control IN buffer stages a packet, validate commits " &
        "it and only then does it reach the host",
      $writeIn, $wantWriteIn)

# The illegal codes are refusals and not no-ops. The authority parenthesises
# `00`, `11`, `60` and `71` as illegal, and documents validating an OUT buffer
# and clearing an IN buffer as unpredictable. A model that accepted them and
# did nothing would be answering a command the hardware does not have.
type Illegal = tuple[log: seq[string], pending: seq[int]]

proc driveIllegal(): Illegal =
  let m = fresh()
  discard m.deliver(0, outPacket)
  let before = m.logLines.len
  for opcode in [0x00'u8, 0x11'u8, 0x60'u8, 0x71'u8]:
    m.portWrite(commandPort, opcode)
  (log: m.logLines[before .. ^1],
   pending: @[fifoAt(m, 0).pending, fifoAt(m, 1).pending])

let illegal = driveIllegal()
let wantIllegal: Illegal = (
    log: @["isp1181: command 0x00 (write control OUT buffer) is illegal - " &
           "the endpoint is read-only; nothing is done",
           "isp1181: command 0x11 (read control IN buffer) is illegal - the " &
           "endpoint is write-only; nothing is done",
           "isp1181: command 0x60 (validate control OUT buffer) is illegal - " &
           "validating an OUT buffer is unpredictable; nothing is done",
           "isp1181: command 0x71 (clear control IN buffer) is illegal - " &
           "clearing an IN buffer is unpredictable; nothing is done"],
    pending: @[1, 0])
check(illegal == wantIllegal,
      "data flow: the four illegal buffer codes are refused by name and " &
        "leave every buffer as it was",
      $illegal, $wantIllegal)

# ---------------------------------------------------------------------------
# BLOCK 7. The set-up packet and the interlock it arms.
#
# SETUPT is bit 2 of DcEndpointStatus and that position is read, not inferred.
# ISP1362 Rev. 06, Table 126 ("DcEndpointStatus register: bit allocation",
# p.114) places the symbols EPSTAL, EPFULL1, EPFULL0, DATA_PID, OVERWRITE,
# SETUPT, CPUBUF at bits 7 down to 1, and Table 127 (p.115) gives bit 2 as
# "SETUPT   Logic 1 indicates that the buffer contains a set-up packet."
#
# The one-bit pair is the point of the first case. The same four bytes reach
# the same buffer by the two routes this model has, and the two status bytes
# differ in exactly bit 2. A model that set the bit for every OUT packet would
# pass a positive-only check and fails this one.

const setupPacket = [0x80'u8, 0x06'u8, 0x00'u8, 0x01'u8]

type SetupBit = tuple[ordinaryStatus: uint8, setupStatus: uint8,
                      difference: uint8, ordinaryPending: int,
                      setupPending: int]

proc driveSetupBit(): SetupBit =
  let ordinary = fresh()
  discard ordinary.deliver(0, setupPacket)
  let ordinaryStatus = ordinary.readVia(0x50'u8, 1)[0]

  let setup = fresh()
  discard setup.deliverSetup(setupPacket)
  let setupStatus = setup.readVia(0x50'u8, 1)[0]

  (ordinaryStatus: ordinaryStatus, setupStatus: setupStatus,
   difference: ordinaryStatus xor setupStatus,
   ordinaryPending: fifoAt(ordinary, 0).pending,
   setupPending: fifoAt(setup, 0).pending)

let setupBit = driveSetupBit()
let wantSetupBit: SetupBit = (
    ordinaryStatus: 0x20'u8, setupStatus: 0x24'u8, difference: 0x04'u8,
    ordinaryPending: 1, setupPending: 1)
check(setupBit == wantSetupBit,
      "set-up: the same bytes by the ordinary route and the set-up route " &
        "land in the same buffer and their status bytes differ in EXACTLY " &
        "SETUPT, bit 2",
      $setupBit, $wantSetupBit)

# SETUPT is not cleared by reading the status register, and the contrast is
# the authority's own. Table 127 says of bit 3 OVERWRITE "a read back of this
# register clears this bit" and says no such thing of bit 2. The datasheet
# knows how to spell a read-to-clear bit and does not spell one here, so a
# read leaves SETUPT standing. What takes it away is the buffer ceasing to
# hold the set-up packet - bit 2's own wording is about buffer content - which
# is the Clear Buffer command. That last step is an inference from the wording
# and not a sentence in the document.

type SetupClear = tuple[afterSetup: uint8, afterSecondRead: uint8,
                        afterAcknowledge: uint8, afterClear: uint8]

proc driveSetupClear(): SetupClear =
  let m = fresh()
  discard m.deliverSetup(setupPacket)
  let afterSetup = m.readVia(0x50'u8, 1)[0]
  let afterSecondRead = m.readVia(0x50'u8, 1)[0]
  m.portWrite(commandPort, 0xF4'u8)
  let afterAcknowledge = m.readVia(0x50'u8, 1)[0]
  m.portWrite(commandPort, 0x70'u8)
  (afterSetup: afterSetup, afterSecondRead: afterSecondRead,
   afterAcknowledge: afterAcknowledge, afterClear: m.readVia(0x50'u8, 1)[0])

let setupClear = driveSetupClear()
let wantSetupClear: SetupClear = (
    afterSetup: 0x24'u8, afterSecondRead: 0x24'u8,
    afterAcknowledge: 0x24'u8, afterClear: 0x00'u8)
check(setupClear == wantSetupClear,
      "set-up: SETUPT survives a status read and an acknowledge and is taken " &
        "away by the clear that empties the buffer",
      $setupClear, $wantSetupClear)

# The interlock. ISP1362 Rev. 06 section 12.3.6 (p.53): "The arrival of a
# set-up packet flushes the IN buffer, and disables the Validate Buffer and
# Clear Buffer commands for the control IN and OUT endpoints. The
# microprocessor must re-enable these commands by sending an acknowledge
# set-up command to both the control endpoints."
#
# The refusal is a log line and not a silent no-op: a command that did nothing
# and said nothing would tell the firmware the buffer was cleared when it was
# not.

type Interlock = tuple[clearRefusedLog: seq[string], pendingAfterRefused: int,
                       validateRefusedPending: int, pendingAfterAllowed: int,
                       validateAllowedPending: int]

proc driveInterlock(): Interlock =
  let m = fresh()
  m.writeVia(0x01'u8, [0x02'u8, 0x00'u8, 0x55'u8, 0xAA'u8])
  discard m.deliverSetup(setupPacket)
  let before = m.logLines.len
  m.portWrite(commandPort, 0x70'u8)
  m.portWrite(commandPort, 0x61'u8)
  let refusedLog = m.logLines[before .. ^1]
  let pendingAfterRefused = fifoAt(m, 0).pending
  let validateRefusedPending = fifoAt(m, 1).pending
  m.portWrite(commandPort, 0xF4'u8)
  m.writeVia(0x01'u8, [0x02'u8, 0x00'u8, 0x55'u8, 0xAA'u8])
  m.portWrite(commandPort, 0x61'u8)
  let validateAllowedPending = fifoAt(m, 1).pending
  m.portWrite(commandPort, 0x70'u8)
  (clearRefusedLog: refusedLog, pendingAfterRefused: pendingAfterRefused,
   validateRefusedPending: validateRefusedPending,
   pendingAfterAllowed: fifoAt(m, 0).pending,
   validateAllowedPending: validateAllowedPending)

let interlock = driveInterlock()
let wantInterlock: Interlock = (
    clearRefusedLog: @[
      "isp1181: command 0x70 (control OUT buffer clear) is disabled until " &
      "the set-up packet is acknowledged with 0xF4; nothing is done",
      "isp1181: command 0x61 (control IN buffer validate) is disabled until " &
      "the set-up packet is acknowledged with 0xF4; nothing is done"],
    pendingAfterRefused: 1, validateRefusedPending: 0,
    pendingAfterAllowed: 0, validateAllowedPending: 1)
check(interlock == wantInterlock,
      "set-up: the interlock refuses clear and validate on both control " &
        "endpoints by name until 0xF4, and both work after it",
      $interlock, $wantInterlock)

# The arrival flushes the IN buffer and unstalls both control endpoints.
# Section 12.3.6 states the flush. Table 127's bit 7 and section 15.2.3 state
# the unstall: "The endpoint is automatically unstalled on receiving a set-up
# token", "regardless of the packet content".

type SetupArrival = tuple[inPendingBefore: int, inPendingAfter: int,
                          stallBefore: seq[uint8], stallAfter: seq[uint8]]

proc driveSetupArrival(): SetupArrival =
  let m = fresh()
  m.writeVia(0x01'u8, [0x02'u8, 0x00'u8, 0x55'u8, 0xAA'u8])
  m.portWrite(commandPort, 0x61'u8)
  let inPendingBefore = fifoAt(m, 1).pending
  m.portWrite(commandPort, 0x40'u8)
  m.portWrite(commandPort, 0x41'u8)
  let stallBefore = @[m.readVia(0x50'u8, 1)[0], m.readVia(0x51'u8, 1)[0]]
  discard m.deliverSetup(setupPacket)
  (inPendingBefore: inPendingBefore, inPendingAfter: fifoAt(m, 1).pending,
   stallBefore: stallBefore,
   stallAfter: @[m.readVia(0x50'u8, 1)[0], m.readVia(0x51'u8, 1)[0]])

let setupArrival = driveSetupArrival()
let wantSetupArrival: SetupArrival = (
    inPendingBefore: 1, inPendingAfter: 0,
    stallBefore: @[0x80'u8, 0xA0'u8], stallAfter: @[0x24'u8, 0x00'u8])
check(setupArrival == wantSetupArrival,
      "set-up: the arrival flushes the control IN buffer and unstalls both " &
        "control endpoints",
      $setupArrival, $wantSetupArrival)

# The whole initialization sequence is driven, in the order the authority puts
# it in. ISP1362 Rev. 06 section 15.1.1 p.107 states that buffer memory is
# allocated "only after all 16 endpoints have been configured in sequence (from
# endpoint 0 OUT to endpoint 14)", so the firmware writes `0x20` to `0x2F` with
# one operand byte each and the model must take all sixteen. What it cannot take
# is the buffer behind a slot it carries no FIFO for, and the pair below
# separates the two halves: the same sixteen writes are driven twice, differing
# only in FIFOEN - bit 7, ISP1362 Rev. 06 Table 110 and Table 111 p.107 - on the
# eleven slots with no buffer.
#
# The disabled pass is the negative control and it comes from the same
# population. A model that wrote a line for every unbuffered slot regardless of
# the byte would satisfy the enabled pass on its own.
type ConfigSequence = tuple[quiet: seq[string], loud: seq[string]]

proc driveConfigSequence(): ConfigSequence =
  for enabled in [false, true]:
    let m = fresh()
    for slot in 0 .. 15:
      # Slots 0 to 4 are the ones this model buffers and are enabled in both
      # passes, so neither pass is a sweep over a uniformly disabled register.
      let byte = (if slot < 5 or enabled: 0x80'u8 else: 0x00'u8)
      m.writeVia(uint8(0x20 + slot), [byte])
    if enabled:
      result.loud = m.logLines
    else:
      result.quiet = m.logLines

let configSequence = driveConfigSequence()
var wantConfigSequence: ConfigSequence = (quiet: @[], loud: @[])
for slot in 5 .. 15:
  wantConfigSequence.loud.add("isp1181: configuration slot " & $slot &
      " was enabled with 0x80 and this model carries no buffer for it; the " &
      "register is recorded and no buffer memory is allocated")
check(configSequence == wantConfigSequence,
      "configuration: the sixteen-slot sequence is taken whole, and only a " &
        "slot this model cannot buffer AND the firmware enables writes a line",
      $configSequence, $wantConfigSequence)

# ---------------------------------------------------------------------------
# THE IN PATH ON AN ENDPOINT THAT IS NOT ENDPOINT 0. `0x03` then `0x63` is the
# sequence the emulated firmware drives and the model refused whole until
# 2026-08-28: ISP1362 Rev. 06 Table 109 p.105-106 numbers Write endpoint n
# buffer `02` to `0F` and Validate endpoint n buffer `62` to `6F` for n = 1 to
# 14, and this model implements them for the endpoints it carries buffers for.
#
# THE PACKET IS FOLLOWED ALL THE WAY OUT, and each step is asserted apart from
# the next. A model that queued at the WRITE would make the validate a no-op; a
# model that queued on endpoint 0 whatever the opcode said would still transmit
# something, so the endpoint the host callback reports is asserted and not only
# the bytes. `0xC1` is FIFOEN, EPDIR and FFOSZ = 1; only bit 6 is read here.
type InPath = tuple[pendingAfterWrite: int, pendingAfterValidate: int,
                    sent: bool, seen: TxRecord, log: seq[string]]

proc driveEndpointInPath(): InPath =
  txSeen = (calls: 0, endpoint: -1, bytes: @[], length: -1)
  let m = recording()
  m.writeVia(0x23'u8, [0xC1'u8])
  m.writeVia(0x03'u8, [0x03'u8, 0x00'u8, 0x11'u8, 0x22'u8, 0x33'u8])
  let afterWrite = fifoAt(m, 3).pending
  m.portWrite(commandPort, 0x63'u8)
  let afterValidate = fifoAt(m, 3).pending
  let sent = m.transmit(2)
  (pendingAfterWrite: afterWrite, pendingAfterValidate: afterValidate,
   sent: sent, seen: txSeen, log: m.logLines)

let inPath = driveEndpointInPath()
let wantInPath: InPath = (
    pendingAfterWrite: 0, pendingAfterValidate: 1, sent: true,
    seen: (calls: 1, endpoint: 2, bytes: @[0x11'u8, 0x22'u8, 0x33'u8],
           length: 3),
    log: @[])
check(inPath == wantInPath,
      "data flow: write and validate on endpoint 2 stage a packet, commit " &
        "it to THAT endpoint's buffer and hand it to the host",
      $inPath, $wantInPath)

# THE DIRECTION GUARD REFUSES IN BOTH DIRECTIONS, ON ONE HANDLE, AND THE TWO
# ENDPOINTS DIFFER IN ONE BIT. `0xC1 xor 0x81` is `0x40`, which is EPDIR alone.
# Endpoint 1 is configured IN and is driven with the OUT commands `0x12` and
# `0x72`; endpoint 2 is configured OUT and is driven with the IN commands `0x03`
# and `0x63`. ISP1362 Rev. 06 section 15.2.1 p.114 states that
# the part has no protection here, and Table 109 notes [4] and [5] p.106 give
# the validate and clear forms as unpredictable, so the model refuses rather
# than picking one of the outcomes the document declines to name.
#
# THE KNOWN POSITIVE IS IN THE SAME RUN: each endpoint is also driven with the
# command that MATCHES its direction, and none of those four is refused. A run
# in which every command refused would satisfy the refusal half alone.
#
# ONE OF THE FOUR SPEAKS AND ITS LINE IS ASSERTED RATHER THAN COUNTED, AND THE
# LINE IT SPEAKS PROVES BOTH HALVES. `0x02` and `0x62` both address endpoint 1,
# which IS configured IN, so the guard lets both through; `0x02` then stages
# nothing because no operand byte follows it, and `0x62` reports a staged buffer
# that is shorter than the two-byte length prefix. That report names a buffer
# write it FOUND, so it is evidence that `0x02` reached `beginBufferWrite` and
# not merely that it was silent. A count of lines cannot tell "passed the guard
# and reported a staging fault" from "was refused by the guard".
type Guard = tuple[log: seq[string], matching: seq[string]]

proc driveDirectionGuard(): Guard =
  let m = fresh()
  m.writeVia(0x22'u8, [0xC1'u8])          # endpoint 1: EPDIR = 1, IN
  m.writeVia(0x23'u8, [0x81'u8])          # endpoint 2: EPDIR = 0, OUT
  let before = m.logLines.len
  for opcode in [0x12'u8, 0x72'u8, 0x03'u8, 0x63'u8]:
    m.portWrite(commandPort, opcode)
  let refusals = m.logLines[before .. ^1]
  let mark = m.logLines.len
  for opcode in [0x02'u8, 0x62'u8, 0x13'u8, 0x73'u8]:
    m.portWrite(commandPort, opcode)
  (log: refusals, matching: m.logLines[mark .. ^1])

let guard = driveDirectionGuard()
let wantGuard: Guard = (
    log: @["isp1181: command 0x12 (endpoint 1 buffer read) addresses the OUT " &
           "buffer of endpoint 1, and EPDIR is 1 in its " &
           "DcEndpointConfiguration - the endpoint is configured IN; the " &
           "authority documents this access as unprotected and its result as " &
           "unpredictable, so nothing is done",
           "isp1181: command 0x72 (endpoint 1 buffer clear) addresses the " &
           "OUT buffer of endpoint 1, and EPDIR is 1 in its " &
           "DcEndpointConfiguration - the endpoint is configured IN; the " &
           "authority documents this access as unprotected and its result as " &
           "unpredictable, so nothing is done",
           "isp1181: command 0x03 (endpoint 2 buffer write) addresses the IN " &
           "buffer of endpoint 2, and EPDIR is 0 in its " &
           "DcEndpointConfiguration - the endpoint is configured OUT; the " &
           "authority documents this access as unprotected and its result as " &
           "unpredictable, so nothing is done",
           "isp1181: command 0x63 (endpoint 2 buffer validate) addresses the " &
           "IN buffer of endpoint 2, and EPDIR is 0 in its " &
           "DcEndpointConfiguration - the endpoint is configured OUT; the " &
           "authority documents this access as unprotected and its result as " &
           "unpredictable, so nothing is done"],
    matching: @["isp1181: a validate for endpoint 1 found 0 staged bytes " &
                "and the length prefix alone is 2; nothing is validated"])
check(guard == wantGuard,
      "EPDIR: a buffer command aimed at the direction an endpoint is not " &
        "configured for is refused by name, and the matching command is not",
      $guard, $wantGuard)

# THE SET-UP INTERLOCK BELONGS TO THE CONTROL ENDPOINTS AND TO NO OTHER.
# ISP1362 Rev. 06 section 12.3.6 p.53 disables Validate Buffer and Clear Buffer
# "for the control IN and OUT endpoints" until `0xF4` acknowledges the set-up
# packet, and names no other endpoint. The two halves run on ONE handle in ONE
# set-up state, so the difference between them is the endpoint and nothing else.
type Interlock2 = tuple[controlLog: seq[string], endpointPending: int,
                        endpointLog: seq[string]]

proc driveInterlockScope(): Interlock2 =
  let m = fresh()
  m.writeVia(0x23'u8, [0xC1'u8])
  discard m.deliverSetup([0x80'u8, 0x06'u8, 0x00'u8, 0x01'u8,
                          0x00'u8, 0x00'u8, 0x40'u8, 0x00'u8])
  let before = m.logLines.len
  m.writeVia(0x01'u8, [0x01'u8, 0x00'u8, 0x5A'u8])
  m.portWrite(commandPort, 0x61'u8)
  let controlLog = m.logLines[before .. ^1]
  let mark = m.logLines.len
  m.writeVia(0x03'u8, [0x01'u8, 0x00'u8, 0xA5'u8])
  m.portWrite(commandPort, 0x63'u8)
  (controlLog: controlLog, endpointPending: fifoAt(m, 3).pending,
   endpointLog: m.logLines[mark .. ^1])

let interlockScope = driveInterlockScope()
let wantInterlockScope: Interlock2 = (
    controlLog: @["isp1181: command 0x61 (control IN buffer validate) is " &
                  "disabled until the set-up packet is acknowledged with " &
                  "0xF4; nothing is done"],
    endpointPending: 1, endpointLog: @[])
check(interlockScope == wantInterlockScope,
      "set-up interlock: an unacknowledged set-up packet stops the control " &
        "IN validate and leaves endpoint 2's alone",
      $interlockScope, $wantInterlockScope)

# A BUFFER HOLDING A ZERO-LENGTH PACKET IS NOT HANDED TO THE HOST, AND THE
# ROUTE THAT PUTS ONE THERE IS DRIVEN RATHER THAN DESCRIBED. `Fifo.accept`
# takes a packet of zero bytes, `deliver` reaches it on an endpoint configured
# OUT, and endpoints 1 to 3 carry ONE buffer, so the EPDIR write that follows
# turns that same buffer IN and `transmit` finds the empty packet in it. The
# transmit used to take `addr packet[0]` of it, which reads out of bounds, and
# `-d:release` removes the check that would have said so.
#
# THE PACKET IS KEPT AND THE REFUSAL IS THE ASSERTION. A model that dropped it
# would leave the firmware with a buffer that emptied itself and a transfer that
# never happened, which is what the nil-callback case above refuses too.
type EmptyIn = tuple[delivered: bool, sent: bool, stillThere: int,
                     calls: int, log: seq[string]]

proc driveEmptyIn(): EmptyIn =
  txSeen = (calls: 0, endpoint: -1, bytes: @[], length: -1)
  let m = recording()
  let delivered = m.deliver(2, newSeq[uint8](0))
  m.writeVia(0x23'u8, [0xC1'u8])
  let sent = m.transmit(2)
  (delivered: delivered, sent: sent, stillThere: fifoAt(m, 3).pending,
   calls: txSeen.calls, log: m.logLines)

let emptyIn = driveEmptyIn()
let wantEmptyIn: EmptyIn = (
    delivered: true, sent: false, stillThere: 1, calls: 0,
    log: @["isp1181: endpoint 2 holds a packet of zero bytes and no source " &
           "on this machine states what a zero-length IN packet carries; " &
           "the host is not called and the packet is kept"])
check(emptyIn == wantEmptyIn,
      "transmit: a buffer holding a zero-length packet is refused by name " &
        "and never indexed",
      $emptyIn, $wantEmptyIn)

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_isp1181", declaredCaseSites)
echo caseSiteLine("executed", "t_isp1181", executedSites)
echo caseSiteLine("off-green-path", "t_isp1181", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_isp1181: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_isp1181: ", passCount, " cases passed"
