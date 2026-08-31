## `t_isp1181_command_set` - the command set of the full ISP1181 model.
##
## The opcode lists below are hand-written literals, and never a second call of
## the table under test. A suite that asked `commands.nim` which opcodes it
## implements and then asserted that it implements them would pass against any
## table at all.
##
## The third class is not an invention of this suite, it is a gap in the
## authority, which names buffer write, buffer read, stall, status, validate and
## clear and gives an opcode for none of them. No ISP1181 datasheet and no
## ISP1362 driver header exists on this machine. So the model carries no opcode
## for those six, and every opcode the authority does not number answers
## benignly and says so.

import std/strutils

import isp1181/isp1181
import isp1181/commands
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
  ## The call site is recorded at COMPILE TIME into `declaredSites` and at RUN
  ## TIME into `executedSites`. `tests/case_sites.nim` states what the pair is
  ## for.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, ok, label, got, want)

# ---------------------------------------------------------------------------
# The window, from design section 9.2's table.

const
  dataPort = 0x13000000'u32
  commandPort = 0x13000010'u32
  benign = 0x00'u8

# THE IMPLEMENTED LIST, HAND-WRITTEN. Every entry is an opcode the plan or the
# design document spells out. The six commands those documents name WITHOUT an
# opcode are not here and cannot be: an opcode chosen by this suite would be
# asserting its own guess.
const implementedOpcodes: array[16, uint8] = [
  0xF6'u8,                                    # reset
  0xBA'u8, 0xBB'u8,                           # hardware configuration
  0xB8'u8, 0xB9'u8,                           # mode
  0xB6'u8, 0xB7'u8,                           # device address
  0x20'u8, 0x21'u8, 0x22'u8, 0x23'u8,         # endpoint configuration 0 to 3
  0xD2'u8,                                    # peek
  0xC0'u8,                                    # interrupt register
  0xC2'u8, 0xC3'u8,                           # interrupt enable
  0xF4'u8]                                    # acknowledge setup

# The not-implemented list, hand-written, with the name each document gives it.
# `scratch`, `unlock` and `isochronous` are named by the documents without an
# opcode and so cannot appear here either - and they cost nothing, because an
# opcode the authority does not number falls to the unspecified class below,
# which answers benignly and logs. The gap is only expensive on the
# implemented side.
const notImplemented: array[17, tuple[opcode: uint8, name: string]] = [
  (0xF0'u8, "DMA"), (0xF1'u8, "DMA"), (0xF2'u8, "DMA"), (0xF3'u8, "DMA"),
  (0xB5'u8, "chip identifier"),
  (0xB4'u8, "frame number"),
  (0x24'u8, "endpoint 4 configuration"),
  (0x25'u8, "endpoint 5 configuration"),
  (0x26'u8, "endpoint 6 configuration"),
  (0x27'u8, "endpoint 7 configuration"),
  (0x28'u8, "endpoint 8 configuration"),
  (0x29'u8, "endpoint 9 configuration"),
  (0x2A'u8, "endpoint 10 configuration"),
  (0x2B'u8, "endpoint 11 configuration"),
  (0x2C'u8, "endpoint 12 configuration"),
  (0x2D'u8, "endpoint 13 configuration"),
  (0x2E'u8, "endpoint 14 configuration")]

var hostToken = 0xC0FFEE

proc ignoreIrq(user: pointer; asserted: cint) {.cdecl.} = discard
proc ignoreTx(user: pointer; endpoint: cint; data: ptr uint8;
              length: csize_t) {.cdecl.} = discard

proc fresh(): ISP1181 =
  newISP1181(addr hostToken, ignoreIrq, ignoreTx)

# ---------------------------------------------------------------------------
# Block 1. Every command in the implemented list is accepted.
#
# Accepted is defined as an observable: the model records the opcode as its last
# accepted command, and it writes no log line. The two
# halves are asserted together because either alone passes a model that does
# the wrong one - a model that logged every command would still record it, and
# a model that recorded nothing would still be silent.

type Accepted = tuple[firstBad: string, driven: int]

proc driveImplemented(): Accepted =
  result = (firstBad: "", driven: 0)
  for opcode in implementedOpcodes:
    let m = fresh()
    m.portWrite(commandPort, opcode)
    inc result.driven
    if result.firstBad.len > 0:
      continue
    if m.lastCommand != int(opcode):
      result.firstBad = "0x" & toHex(opcode) & " not recorded, lastCommand=" &
        $m.lastCommand
    elif m.logLines.len != 0:
      result.firstBad = "0x" & toHex(opcode) & " logged: " & m.logLines[0]

const wantAccepted: Accepted = (firstBad: "", driven: 16)

let accepted = driveImplemented()
check(accepted == wantAccepted,
      "implemented: every command in the list is accepted and logs nothing",
      $accepted, $wantAccepted)

# ---------------------------------------------------------------------------
# Block 2. Every command in the not-implemented list answers benignly and
# writes one log line.
#
# The line's text is asserted and not only its count. A model that logged the
# wrong opcode, or logged a line that named no opcode at all, would satisfy a
# count and would leave a reader unable to tell which command was refused.

type Refused = tuple[firstBad: string, driven: int]

proc driveRefused(rows: openArray[tuple[opcode: uint8, want: string]]): Refused =
  result = (firstBad: "", driven: 0)
  for row in rows:
    let m = fresh()
    m.portWrite(commandPort, row.opcode)
    inc result.driven
    if result.firstBad.len > 0:
      continue
    let want = row.want
    let lines = m.logLines
    if lines.len != 1:
      result.firstBad = "0x" & toHex(row.opcode) & " wrote " & $lines.len &
        " log lines"
    elif lines[0] != want:
      result.firstBad = "0x" & toHex(row.opcode) & " logged `" & lines[0] &
        "` want `" & want & "`"
    elif m.portRead(dataPort) != benign:
      result.firstBad = "0x" & toHex(row.opcode) & " data port answered 0x" &
        toHex(m.portRead(dataPort))
    elif m.portRead(commandPort) != benign:
      result.firstBad = "0x" & toHex(row.opcode) & " command port answered 0x" &
        toHex(m.portRead(commandPort))
    elif m.lastCommand != -1:
      result.firstBad = "0x" & toHex(row.opcode) & " became the pending command"

# The command's name is part of the asserted line. A log that named only the
# opcode would leave a reader with a number and no way to tell a refused DMA
# transfer from a refused chip-identifier read.
var notImplementedRows: seq[tuple[opcode: uint8, want: string]]
for row in notImplemented:
  notImplementedRows.add((opcode: row.opcode,
      want: "isp1181: command 0x" & toHex(row.opcode) & " (" & row.name &
            ") is not implemented; the read answers 0x00"))

let refused = driveRefused(notImplementedRows)
const wantRefused: Refused = (firstBad: "", driven: 17)
check(refused == wantRefused,
      "not implemented: every command answers benignly and logs one line",
      $refused, $wantRefused)

# ---------------------------------------------------------------------------
# Block 3. Every opcode the authority does not number at all.
#
# The set is derived as the complement of the two hand-written lists, so it
# needs no third list to maintain and it cannot disagree with them. It is the
# class that carries the six commands the authority names without an opcode,
# and its log line says a different thing from block 2's on purpose: a reader
# who hits it has found a gap in the specification and not a decision.

var unspecifiedRows: seq[tuple[opcode: uint8, want: string]]
for value in 0 .. 255:
  let opcode = uint8(value)
  if opcode in implementedOpcodes:
    continue
  var numbered = false
  for row in notImplemented:
    if row.opcode == opcode:
      numbered = true
  if not numbered:
    unspecifiedRows.add((opcode: opcode,
        want: "isp1181: command 0x" & toHex(opcode) &
              " is not in the specified command set; the read answers 0x00"))

let unspecified = driveRefused(unspecifiedRows)
const wantUnspecified: Refused = (firstBad: "", driven: 223)
check(unspecified == wantUnspecified,
      "unspecified: every unnumbered opcode answers benignly and logs one line",
      $unspecified, $wantUnspecified)

# The three classes partition the byte. Without this the three sweeps above
# could each be green over a set that left opcodes untouched.
type Partition = tuple[implemented: int, refused: int, unspecified: int,
                       total: int]
let partition: Partition = (implemented: accepted.driven,
                            refused: refused.driven,
                            unspecified: unspecified.driven,
                            total: accepted.driven + refused.driven +
                                   unspecified.driven)
const wantPartition: Partition = (implemented: 16, refused: 17,
                                  unspecified: 223, total: 256)
check(partition == wantPartition,
      "partition: the three classes cover all 256 opcodes and none twice",
      $partition, $wantPartition)

# The six commands the authority names without an opcode are recorded in the
# model rather than left in a comment, so that the day a datasheet arrives the
# list to close is a list and not a paragraph.
const wantUnnumbered = @["buffer write", "buffer read", "stall", "status",
                         "validate", "clear"]
check(@unnumberedCommands == wantUnnumbered,
      "gap: the six commands named without an opcode are recorded by name",
      $(@unnumberedCommands), $wantUnnumbered)

# ---------------------------------------------------------------------------
# Block 4. Accepted has to mean something, so the paired commands are driven
# through the data port and read back.
#
# Multi-byte registers are least significant byte first. Every expected sequence
# below is written out in that order by hand.
#
# The two known firmware values are the ones driven - HwConfig `0x2300` and
# Interrupt Enable `0x1F07` - because a round trip that used a value the
# firmware never writes would leave the one case that matters untested.

proc writeVia(m: ISP1181; opcode: uint8; bytes: openArray[uint8]) =
  m.portWrite(commandPort, opcode)
  for value in bytes:
    m.portWrite(dataPort, value)

proc readVia(m: ISP1181; opcode: uint8; width: int): seq[uint8] =
  m.portWrite(commandPort, opcode)
  for _ in 0 ..< width:
    result.add(m.portRead(dataPort))

type RoundTrip = tuple[readBack: seq[uint8], logged: int]

proc roundTrip(writeOp: uint8; bytes: openArray[uint8];
               readOp: uint8; width: int): RoundTrip =
  let m = fresh()
  m.writeVia(writeOp, bytes)
  result = (readBack: m.readVia(readOp, width), logged: m.logLines.len)

let hwConfig = roundTrip(0xBA'u8, [0x00'u8, 0x23'u8], 0xBB'u8, 2)
let wantHwConfig: RoundTrip = (readBack: @[0x00'u8, 0x23'u8], logged: 0)
check(hwConfig == wantHwConfig,
      "hardware configuration: 0x2300 round trips least significant byte first",
      $hwConfig, $wantHwConfig)

# The SOFTCT bit is named state and not merely a value inside the mode byte,
# so the case drives it on and off and reads the model's own answer for it.
type ModeCase = tuple[readBack: seq[uint8], logged: int, onWhenSet: bool,
                      onWhenClear: bool]

proc modeCase(): ModeCase =
  let m = fresh()
  m.writeVia(0xB8'u8, [0x01'u8])
  result.readBack = m.readVia(0xB9'u8, 1)
  result.onWhenSet = m.softct
  m.writeVia(0xB8'u8, [0x00'u8])
  result.onWhenClear = m.softct
  result.logged = m.logLines.len

let mode = modeCase()
let wantMode: ModeCase = (readBack: @[0x01'u8], logged: 0, onWhenSet: true,
                          onWhenClear: false)
check(mode == wantMode,
      "mode: the SOFTCT bit round trips and the model reports it",
      $mode, $wantMode)

let address = roundTrip(0xB6'u8, [0x35'u8], 0xB7'u8, 1)
let wantAddress: RoundTrip = (readBack: @[0x35'u8], logged: 0)
check(address == wantAddress,
      "device address: the address round trips",
      $address, $wantAddress)

let enable = roundTrip(0xC2'u8, [0x07'u8, 0x1F'u8, 0x00'u8, 0x00'u8],
                       0xC3'u8, 4)
let wantEnable: RoundTrip = (readBack: @[0x07'u8, 0x1F'u8, 0x00'u8, 0x00'u8],
                             logged: 0)
check(enable == wantEnable,
      "interrupt enable: 0x1F07 round trips across four bytes",
      $enable, $wantEnable)

# The interrupt register reads zero on a fresh model, and that is asserted
# rather than assumed: zero is the benign answer, so
# a register that came up holding anything else would change what a boot reads.
let freshInterrupt = fresh().readVia(0xC0'u8, 4)
let wantFreshInterrupt = @[0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8]
check(freshInterrupt == wantFreshInterrupt,
      "interrupt register: a fresh model reads four zero bytes",
      $freshInterrupt, $wantFreshInterrupt)

# Reset clears the registers and is driven after they are all non-zero, so a
# reset that cleared only the register a narrower case looked at is separated
# from one that clears them all.
type AfterReset = tuple[hw: seq[uint8], mode: seq[uint8], address: seq[uint8],
                        enable: seq[uint8], interrupt: seq[uint8]]

proc afterReset(): AfterReset =
  let m = fresh()
  m.writeVia(0xBA'u8, [0x00'u8, 0x23'u8])
  m.writeVia(0xB8'u8, [0x01'u8])
  m.writeVia(0xB6'u8, [0x35'u8])
  m.writeVia(0xC2'u8, [0x07'u8, 0x1F'u8, 0x00'u8, 0x00'u8])
  m.raiseInterrupt(0x0000_0001'u32)
  m.portWrite(commandPort, 0xF6'u8)
  result = (hw: m.readVia(0xBB'u8, 2), mode: m.readVia(0xB9'u8, 1),
            address: m.readVia(0xB7'u8, 1), enable: m.readVia(0xC3'u8, 4),
            interrupt: m.readVia(0xC0'u8, 4))

let reset = afterReset()
let wantReset: AfterReset = (hw: @[0x00'u8, 0x00'u8], mode: @[0x00'u8],
                             address: @[0x00'u8],
                             enable: @[0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8],
                             interrupt: @[0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8])
check(reset == wantReset,
      "reset: 0xF6 clears every register this model carries",
      $reset, $wantReset)

# `0xF4` acknowledge setup is accepted and changes nothing, and the case exists
# because the authority gives the command an opcode and no effect. A model that
# invented one would go red here: an effect that appears without a source is a
# silent invention.
type AfterAck = tuple[interrupt: seq[uint8], mode: seq[uint8], logged: int]

proc afterAck(): AfterAck =
  let m = fresh()
  m.writeVia(0xB8'u8, [0x01'u8])
  m.portWrite(commandPort, 0xF4'u8)
  result = (interrupt: m.readVia(0xC0'u8, 4), mode: m.readVia(0xB9'u8, 1),
            logged: m.logLines.len)

let ack = afterAck()
let wantAck: AfterAck = (interrupt: @[0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8],
                         mode: @[0x01'u8], logged: 0)
check(ack == wantAck,
      "acknowledge setup: 0xF4 is accepted and invents no effect",
      $ack, $wantAck)

# ---------------------------------------------------------------------------
# Block 5. The data port says so when it has nothing true to carry.
#
# Each of these could be made silent and plausible, which is why they are
# cases. An over-long transfer that wrapped would corrupt a register the
# firmware then reads back; an un-commanded access that answered zero would be
# indistinguishable from the stub.

type PortNote = tuple[value: uint8, log: seq[string], readBack: seq[uint8]]

proc overlongWrite(): PortNote =
  let m = fresh()
  m.writeVia(0xB8'u8, [0x01'u8, 0x02'u8])
  result = (value: benign, log: m.logLines, readBack: m.readVia(0xB9'u8, 1))

let longWrite = overlongWrite()
let wantLongWrite: PortNote = (value: benign,
    log: @["isp1181: command 0xB8 (write mode) takes 1 byte and a 2nd was " &
           "written; the byte is discarded"],
    readBack: @[0x01'u8])
check(longWrite == wantLongWrite,
      "data port: a byte past the register's width is refused and logged",
      $longWrite, $wantLongWrite)

proc overlongRead(): PortNote =
  let m = fresh()
  m.writeVia(0xB6'u8, [0x35'u8])
  m.portWrite(commandPort, 0xB7'u8)
  let first = m.portRead(dataPort)
  let second = m.portRead(dataPort)
  result = (value: second, log: m.logLines, readBack: @[first])

let longRead = overlongRead()
let wantLongRead: PortNote = (value: benign,
    log: @["isp1181: command 0xB7 (read device address) yields 1 byte and a " &
           "2nd was read; the read answers 0x00"],
    readBack: @[0x35'u8])
check(longRead == wantLongRead,
      "data port: a read past the register's width answers benignly and logs",
      $longRead, $wantLongRead)

proc uncommandedWrite(): PortNote =
  let m = fresh()
  m.portWrite(dataPort, 0xAB'u8)
  result = (value: benign, log: m.logLines, readBack: @[])

let strayWrite = uncommandedWrite()
let wantStrayWrite: PortNote = (value: benign,
    log: @["isp1181: a data port write of 0xAB arrived with no command " &
           "pending; the byte is discarded"],
    readBack: @[])
check(strayWrite == wantStrayWrite,
      "data port: a write with no command pending is discarded and logged",
      $strayWrite, $wantStrayWrite)

proc uncommandedRead(): PortNote =
  let m = fresh()
  let value = m.portRead(dataPort)
  result = (value: value, log: m.logLines, readBack: @[])

let strayRead = uncommandedRead()
let wantStrayRead: PortNote = (value: benign,
    log: @["isp1181: a data port read arrived with no command pending; the " &
           "read answers 0x00"],
    readBack: @[])
check(strayRead == wantStrayRead,
      "data port: a read with no command pending answers benignly and logs",
      $strayRead, $wantStrayRead)

# ---------------------------------------------------------------------------
# Block 6. The five FIFOs.
#
# The geometry table is the case that pins the EP3 correction. The design
# document's "double" for endpoint 3 is wrong: the endpoint table marks
# double-buffering where it exists and leaves EP3 unmarked. A model with one
# buffer too many accepts a
# second packet the hardware would have NAKed, so the row below is a behaviour
# and not a size.

type Geometry = tuple[name: string, capacity: int, buffers: int]

var geometry: seq[Geometry]
for index in 0 ..< fifoCount:
  let f = fifoAt(fresh(), index)
  geometry.add((name: fifoName(index), capacity: f.capacity,
                buffers: f.buffers))

let wantGeometry: seq[Geometry] = @[
  (name: "endpoint 0 OUT", capacity: 64, buffers: 1),
  (name: "endpoint 0 IN", capacity: 64, buffers: 1),
  (name: "endpoint 1", capacity: 16, buffers: 2),
  (name: "endpoint 2", capacity: 64, buffers: 2),
  (name: "endpoint 3", capacity: 64, buffers: 1)]
check(geometry == wantGeometry,
      "fifos: the five buffers carry design section 9.2's sizes, EP3 single",
      $geometry, $wantGeometry)

# The second packet is the whole point of the buffer count, so it is driven on
# a single-buffered endpoint and on a double-buffered one in the same case.
type SecondPacket = tuple[ep1First: bool, ep1Second: bool, ep1Pending: int,
                          ep3First: bool, ep3Second: bool, ep3Pending: int]

proc secondPacket(): SecondPacket =
  let m = fresh()
  let payload = [0x11'u8, 0x22'u8]
  result.ep1First = m.deliver(1, payload)
  result.ep1Second = m.deliver(1, payload)
  result.ep1Pending = fifoAt(m, 2).pending
  result.ep3First = m.deliver(3, payload)
  result.ep3Second = m.deliver(3, payload)
  result.ep3Pending = fifoAt(m, 4).pending

let second = secondPacket()
let wantSecond: SecondPacket = (ep1First: true, ep1Second: true,
                                ep1Pending: 2, ep3First: true,
                                ep3Second: false, ep3Pending: 1)
check(second == wantSecond,
      "fifos: endpoint 1 takes a second packet and endpoint 3 NAKs it",
      $second, $wantSecond)

# A packet larger than the buffer is refused whole and never truncated. A
# model that stored the first 16 bytes would present the firmware with a short
# packet it has no way to recognise as short.
type Oversize = tuple[accepted: bool, pending: int]

proc oversize(): Oversize =
  let m = fresh()
  var payload: seq[uint8]
  for i in 0 ..< 17:
    payload.add(uint8(i))
  result = (accepted: m.deliver(1, payload), pending: fifoAt(m, 2).pending)

let big = oversize()
let wantBig: Oversize = (accepted: false, pending: 0)
check(big == wantBig,
      "fifos: a packet larger than the buffer is refused and not truncated",
      $big, $wantBig)

# Peek reads and does not consume, which is the whole difference between it and
# a buffer read. The endpoint it reads is the one the last accepted
# `0x20+idx` selected, because that is the only endpoint selector the authority
# gives this model.
type Peek = tuple[first: uint8, second: uint8, pending: int, logged: int]

proc peekTwice(): Peek =
  let m = fresh()
  discard m.deliver(2, [0x5A'u8, 0x5B'u8])
  m.portWrite(commandPort, 0x22'u8)
  m.portWrite(commandPort, 0xD2'u8)
  let first = m.portRead(dataPort)
  m.portWrite(commandPort, 0xD2'u8)
  let secondByte = m.portRead(dataPort)
  result = (first: first, second: secondByte, pending: fifoAt(m, 3).pending,
            logged: m.logLines.len)

let peeked = peekTwice()
let wantPeeked: Peek = (first: 0x5A'u8, second: 0x5A'u8, pending: 1,
                        logged: 1)
check(peeked == wantPeeked,
      "peek: 0xD2 reads the selected endpoint's head byte and consumes none",
      $peeked, $wantPeeked)

# Peeking an empty buffer answers benignly and says so. A zero returned in
# silence is the answer a full buffer holding a zero byte would give.
type EmptyPeek = tuple[value: uint8, log: seq[string]]

proc peekEmpty(): EmptyPeek =
  let m = fresh()
  m.portWrite(commandPort, 0xD2'u8)
  result = (value: m.portRead(dataPort), log: m.logLines)

let emptyPeek = peekEmpty()
let wantEmptyPeek: EmptyPeek = (value: benign,
    log: @["isp1181: peek on endpoint 0 OUT found no packet; the read " &
           "answers 0x00"])
check(emptyPeek == wantEmptyPeek,
      "peek: an empty buffer answers benignly and logs",
      $emptyPeek, $wantEmptyPeek)

# Reset empties the buffers too, and the case drives a packet into every one of
# the five first so that a reset which cleared a subset is separated from one
# that clears them all.
type ResetFifos = tuple[before: seq[int], after: seq[int]]

proc resetFifos(): ResetFifos =
  let m = fresh()
  for endpoint in 0 .. 3:
    discard m.deliver(endpoint, [0x01'u8])
  discard m.deliver(0, [0x01'u8])
  for index in 0 ..< fifoCount:
    result.before.add(fifoAt(m, index).pending)
  m.portWrite(commandPort, 0xF6'u8)
  for index in 0 ..< fifoCount:
    result.after.add(fifoAt(m, index).pending)

let fifoReset = resetFifos()
let wantFifoReset: ResetFifos = (before: @[1, 0, 1, 1, 1],
                                 after: @[0, 0, 0, 0, 0])
check(fifoReset == wantFifoReset,
      "reset: 0xF6 empties every buffer that holds a packet",
      $fifoReset, $wantFifoReset)

# ---------------------------------------------------------------------------
# Block 7. The IRQ3 line.
#
# No source on this machine assigns an interrupt-register bit to an event, so
# the model assigns none and says so once per delivery. That silence is what the
# case pins: a model whose interrupt simply never fired would be
# indistinguishable from the stub, and this suite has to be able to tell them
# apart.

type Delivery = tuple[accepted: bool, pending: int, interrupt: seq[uint8],
                      asserted: bool, log: seq[string]]

proc deliverOnce(): Delivery =
  let m = fresh()
  m.writeVia(0xC2'u8, [0x07'u8, 0x1F'u8, 0x00'u8, 0x00'u8])
  let accepted = m.deliver(1, [0x99'u8])
  result = (accepted: accepted, pending: fifoAt(m, 2).pending,
            interrupt: m.readVia(0xC0'u8, 4), asserted: m.irqAsserted,
            log: m.logLines)

let delivered = deliverOnce()
let wantDelivered: Delivery = (accepted: true, pending: 1,
    interrupt: @[0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8], asserted: false,
    log: @["isp1181: a packet reached endpoint 1 and no source names the " &
           "interrupt register bit for it; no interrupt is raised"])
check(delivered == wantDelivered,
      "irq: a delivery raises no interrupt and names the missing assignment",
      $delivered, $wantDelivered)

# The derivation itself is tested with a mask this suite chooses, so that the
# level-triggered rule is exercised without any claim about which event owns
# which bit. The line is level-triggered and the callback carries the logical
# state, so the board's inversion is not this model's.

var irqTrace: seq[int]

proc traceIrq(user: pointer; asserted: cint) {.cdecl.} =
  irqTrace.add(int(asserted))

type IrqRun = tuple[trace: seq[int], asserted: bool]

proc driveIrq(): IrqRun =
  irqTrace = @[]
  let m = newISP1181(addr hostToken, traceIrq, ignoreTx)
  m.writeVia(0xC2'u8, [0x07'u8, 0x1F'u8, 0x00'u8, 0x00'u8])
  m.raiseInterrupt(0x0000_0008'u32)   # enabled by no bit of 0x1F07
  m.raiseInterrupt(0x0000_0001'u32)   # enabled
  m.raiseInterrupt(0x0000_0002'u32)   # already asserted, no second edge
  m.clearInterrupt(0x0000_0001'u32)
  m.clearInterrupt(0x0000_0002'u32)
  result = (trace: irqTrace, asserted: m.irqAsserted)

let irqRun = driveIrq()
let wantIrqRun: IrqRun = (trace: @[1, 0], asserted: false)
check(irqRun == wantIrqRun,
      "irq: the line follows the enabled bits and reports each change once",
      $irqRun, $wantIrqRun)

# The registry lines. They are data and not a verdict.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_isp1181_command_set", declaredCaseSites)
echo caseSiteLine("executed", "t_isp1181_command_set", executedSites)
echo caseSiteLine("off-green-path", "t_isp1181_command_set",
                  declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_isp1181_command_set: ", failures.len, " of ",
      failures.len + passCount, " cases failed"
  quit(1)
else:
  echo ""
  echo "t_isp1181_command_set: ", passCount, " cases passed"
