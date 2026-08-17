## `t_isp1181` - the ISP1181 model driven by synthetic transactions.
##
## Every opcode and every log line below is a hand-written literal. A suite that
## asked the model which opcodes it implements, or that built an expected log
## line by calling the code that writes it, would pass against any table and any
## wording at all.
##
## No source on this machine names the interrupt-register bit for any event, so
## there is no event whose bit this suite could assert. What is assertable is
## the register itself - its width, its byte order, that a clear is per bit,
## and that nothing in the model lights a bit on its own. The last of those is
## the one that would silently become false the day somebody picks a bit, so it
## is written as a sweep with a positive control beside it: a model whose
## register were stuck at zero would satisfy the sweep and fails the control.

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

# A refused command is inert and not half-accepted. Both refusing classes are
# driven into the middle of a live transfer: the command the documents name and
# do not implement, and the byte no document numbers at all. The transfer has
# to complete across both of them, and the two have to say different things - a
# reader who meets the second has found a gap in the specification rather than
# a decision somebody took, and a single shared line would hide which one it is.
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
let wantInert: Inert = (hw: @[0x00'u8, 0x23'u8],
    log: @["isp1181: command 0xB5 (chip identifier) is not implemented; the " &
           "read answers 0x00",
           "isp1181: command 0x9C is not in the specified command set; the " &
           "read answers 0x00"])
check(inert == wantInert,
      "state machine: a refused command disturbs no transfer and names its class",
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

proc endpointMapping(): Mapping =
  let m = fresh()
  for endpoint in 0 .. 3:
    result.accepted.add(m.deliver(endpoint, [uint8(0xE0 + endpoint), 0x00'u8]))
  for endpoint in 0 .. 3:
    m.portWrite(commandPort, uint8(0x20 + endpoint))
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

# A refused endpoint-configuration command moves no selection. The selector and
# the refusal share an opcode family, so a model that selected before it
# classified would take the endpoint number out of a command it had just
# refused - and the number is outside the range the model carries buffers for.
type Selection = tuple[peeked: uint8, log: seq[string]]

proc refusedSelection(): Selection =
  let m = fresh()
  discard m.deliver(0, [0xA0'u8])
  discard m.deliver(2, [0xA2'u8])
  m.portWrite(commandPort, 0x22'u8)
  m.portWrite(commandPort, 0x24'u8)
  m.portWrite(commandPort, 0xD2'u8)
  result = (peeked: m.portRead(dataPort), log: m.logLines)

let selection = refusedSelection()
let wantSelection: Selection = (peeked: 0xA2'u8,
    log: @["isp1181: a packet reached endpoint 0 and no source names the " &
           "interrupt register bit for it; no interrupt is raised",
           "isp1181: a packet reached endpoint 2 and no source names the " &
           "interrupt register bit for it; no interrupt is raised",
           "isp1181: command 0x24 (endpoint 4 configuration) is not " &
           "implemented; the read answers 0x00"])
check(selection == wantSelection,
      "fifos: a refused endpoint-configuration command leaves the selection alone",
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

# The two refusals are told apart by the figures the line carries. A full
# buffer is ordinary flow control and an oversized packet is a fault in
# whatever produced it, and a reader separates them by the packet's size and
# the buffer's occupancy rather than by two different sentences. The full-buffer
# refusal is driven on endpoint 3, which holds ONE packet. A buffer too many
# would accept the second packet, so the refusal is the assertion and the count
# is not.
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
    full: @["isp1181: a packet reached endpoint 3 and no source names the " &
            "interrupt register bit for it; no interrupt is raised",
            "isp1181: endpoint 3 refused a packet of 2 bytes; the buffer " &
            "holds 1 of 1"],
    oversize: @["isp1181: endpoint 1 refused a packet of 17 bytes; the " &
                "buffer holds 0 of 2"])
check(refusals == wantRefusals,
      "fifos: a full buffer and an oversized packet are separated by the figures",
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

# A delivery raises nothing at any endpoint and says why, and it says it under
# the enable the firmware actually writes. The interrupt enable is driven to
# `0x1F07` first, so every bit the firmware arms is armed while the packets
# arrive. A model that had picked a bit for a delivery would light the line
# here, which is the direction this case wants: the silence is the assertion.
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
    interrupt: @[0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8], asserted: false,
    log: @["isp1181: a packet reached endpoint 0 and no source names the " &
           "interrupt register bit for it; no interrupt is raised",
           "isp1181: a packet reached endpoint 1 and no source names the " &
           "interrupt register bit for it; no interrupt is raised",
           "isp1181: a packet reached endpoint 2 and no source names the " &
           "interrupt register bit for it; no interrupt is raised",
           "isp1181: a packet reached endpoint 3 and no source names the " &
           "interrupt register bit for it; no interrupt is raised"])
check(deliveries == wantDeliveries,
      "interrupt register: no delivery lights a bit under the firmware's enable",
      $deliveries, $wantDeliveries)

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
# The command left pending is the one accepted before the refusal, and that is
# the two-sided form of inertness: the refused byte does not become the pending
# command, and it does not take away the command that was.
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
    value: benign, port: benign, last: 0xB8,
    afterRead: @["isp1181: command 0xB5 (chip identifier) is not " &
                 "implemented; the read answers 0x00",
                 "isp1181: a data port read arrived with no command pending; " &
                 "the read answers 0x00"],
    hw: @[0x00'u8, 0x23'u8], mode: @[0x01'u8],
    interrupt: @[0x04'u8, 0x00'u8, 0x00'u8, 0x00'u8],
    pending: @[0, 0, 0, 1, 0])
check(negative == wantNegative,
      "negative: an unimplemented command answers benignly, logs, and changes nothing",
      $negative, $wantNegative)

# The registry lines. They are data and not a verdict.
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
