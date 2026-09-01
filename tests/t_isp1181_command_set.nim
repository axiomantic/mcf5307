## `t_isp1181_command_set` - the command set of the full ISP1181 model.
##
## The opcode lists below are hand-written literals, and never a second call of
## the table under test. A suite that asked `commands.nim` which opcodes it
## implements and then asserted that it implements them would pass against any
## table at all.
##
## There are four classes and each names a different finding. `ccImplemented`
## and `ccNotImplemented` are decisions this project took. `ccIllegal` is a
## byte the authority numbers and forbids. `ccUnspecified` is a byte no source
## on this machine describes at all.
##
## The data-flow opcodes are inherited. They are typed here from Table 109 of
## the ISP1362 data sheet, Rev. 06, which states that it integrates the
## ISP1181B peripheral controller - a claim of integration, not of a
## byte-identical command map. The ISP1181B data sheet itself was not read.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

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
# The window.

const
  dataPort = 0x13000000'u32
  commandPort = 0x13000010'u32
  benign = 0x00'u8

# THE IMPLEMENTED LIST, HAND-WRITTEN. Every entry is an opcode the plan or the
# design document spells out. The six commands those documents name WITHOUT an
# opcode are not here and cannot be: an opcode chosen by this suite would be
# asserting its own guess.
const implementedOpcodes: array[42, uint8] = [
  0xF6'u8,                                    # reset
  0xBA'u8, 0xBB'u8,                           # hardware configuration
  0xB8'u8, 0xB9'u8,                           # mode
  0xB6'u8, 0xB7'u8,                           # device address
  0x20'u8, 0x21'u8,                           # control configuration, OUT then IN
  0x22'u8, 0x23'u8, 0x24'u8,                  # endpoint 1 to 3 configuration
  0xD2'u8,                                    # peek
  0xC0'u8,                                    # interrupt register
  0xC2'u8, 0xC3'u8,                           # interrupt enable
  0xF4'u8,                                    # acknowledge setup
  0x01'u8,                            # control IN buffer write
  0x10'u8,                            # control OUT buffer read
  0x12'u8,                            # endpoint 1 buffer read
  0x13'u8,                            # endpoint 2 buffer read
  0x14'u8,                            # endpoint 3 buffer read
  0x40'u8,                            # control OUT stall
  0x41'u8,                            # control IN stall
  0x42'u8,                            # endpoint 1 stall
  0x43'u8,                            # endpoint 2 stall
  0x44'u8,                            # endpoint 3 stall
  0x50'u8,                            # control OUT status
  0x51'u8,                            # control IN status
  0x52'u8,                            # endpoint 1 status
  0x53'u8,                            # endpoint 2 status
  0x54'u8,                            # endpoint 3 status
  0x61'u8,                            # control IN buffer validate
  0x70'u8,                            # control OUT buffer clear
  0x72'u8,                            # endpoint 1 buffer clear
  0x73'u8,                            # endpoint 2 buffer clear
  0x74'u8,                            # endpoint 3 buffer clear
  0x80'u8,                            # control OUT unstall
  0x81'u8,                            # control IN unstall
  0x82'u8,                            # endpoint 1 unstall
  0x83'u8,                            # endpoint 2 unstall
  0x84'u8]                            # endpoint 3 unstall

# The not-implemented list, hand-written, with the name each document gives it.
# `scratch`, `unlock` and `isochronous` are named by the documents without an
# opcode and so cannot appear here either - and they cost nothing, because an
# opcode the authority does not number falls to the unspecified class below,
# which answers benignly and logs. The gap is only expensive on the
# IMPLEMENTED side.
const notImplemented: array[100, tuple[opcode: uint8, name: string]] = [
  (0xF0'u8, "DMA"), (0xF1'u8, "DMA"), (0xF2'u8, "DMA"), (0xF3'u8, "DMA"),
  (0xB5'u8, "chip identifier"),
  (0xB4'u8, "frame number"),
  (0x25'u8, "endpoint 4 configuration"),
  (0x26'u8, "endpoint 5 configuration"),
  (0x27'u8, "endpoint 6 configuration"),
  (0x28'u8, "endpoint 7 configuration"),
  (0x29'u8, "endpoint 8 configuration"),
  (0x2A'u8, "endpoint 9 configuration"),
  (0x2B'u8, "endpoint 10 configuration"),
  (0x2C'u8, "endpoint 11 configuration"),
  (0x2D'u8, "endpoint 12 configuration"),
  (0x2E'u8, "endpoint 13 configuration"),
  (0x2F'u8, "endpoint 14 configuration"),
  (0x02'u8, "endpoint 1 buffer write"),
  (0x03'u8, "endpoint 2 buffer write"),
  (0x04'u8, "endpoint 3 buffer write"),
  (0x05'u8, "endpoint 4 buffer write"),
  (0x06'u8, "endpoint 5 buffer write"),
  (0x07'u8, "endpoint 6 buffer write"),
  (0x08'u8, "endpoint 7 buffer write"),
  (0x09'u8, "endpoint 8 buffer write"),
  (0x0A'u8, "endpoint 9 buffer write"),
  (0x0B'u8, "endpoint 10 buffer write"),
  (0x0C'u8, "endpoint 11 buffer write"),
  (0x0D'u8, "endpoint 12 buffer write"),
  (0x0E'u8, "endpoint 13 buffer write"),
  (0x0F'u8, "endpoint 14 buffer write"),
  (0x15'u8, "endpoint 4 buffer read"),
  (0x16'u8, "endpoint 5 buffer read"),
  (0x17'u8, "endpoint 6 buffer read"),
  (0x18'u8, "endpoint 7 buffer read"),
  (0x19'u8, "endpoint 8 buffer read"),
  (0x1A'u8, "endpoint 9 buffer read"),
  (0x1B'u8, "endpoint 10 buffer read"),
  (0x1C'u8, "endpoint 11 buffer read"),
  (0x1D'u8, "endpoint 12 buffer read"),
  (0x1E'u8, "endpoint 13 buffer read"),
  (0x1F'u8, "endpoint 14 buffer read"),
  (0x45'u8, "endpoint 4 stall"),
  (0x46'u8, "endpoint 5 stall"),
  (0x47'u8, "endpoint 6 stall"),
  (0x48'u8, "endpoint 7 stall"),
  (0x49'u8, "endpoint 8 stall"),
  (0x4A'u8, "endpoint 9 stall"),
  (0x4B'u8, "endpoint 10 stall"),
  (0x4C'u8, "endpoint 11 stall"),
  (0x4D'u8, "endpoint 12 stall"),
  (0x4E'u8, "endpoint 13 stall"),
  (0x4F'u8, "endpoint 14 stall"),
  (0x55'u8, "endpoint 4 status"),
  (0x56'u8, "endpoint 5 status"),
  (0x57'u8, "endpoint 6 status"),
  (0x58'u8, "endpoint 7 status"),
  (0x59'u8, "endpoint 8 status"),
  (0x5A'u8, "endpoint 9 status"),
  (0x5B'u8, "endpoint 10 status"),
  (0x5C'u8, "endpoint 11 status"),
  (0x5D'u8, "endpoint 12 status"),
  (0x5E'u8, "endpoint 13 status"),
  (0x5F'u8, "endpoint 14 status"),
  (0x62'u8, "endpoint 1 buffer validate"),
  (0x63'u8, "endpoint 2 buffer validate"),
  (0x64'u8, "endpoint 3 buffer validate"),
  (0x65'u8, "endpoint 4 buffer validate"),
  (0x66'u8, "endpoint 5 buffer validate"),
  (0x67'u8, "endpoint 6 buffer validate"),
  (0x68'u8, "endpoint 7 buffer validate"),
  (0x69'u8, "endpoint 8 buffer validate"),
  (0x6A'u8, "endpoint 9 buffer validate"),
  (0x6B'u8, "endpoint 10 buffer validate"),
  (0x6C'u8, "endpoint 11 buffer validate"),
  (0x6D'u8, "endpoint 12 buffer validate"),
  (0x6E'u8, "endpoint 13 buffer validate"),
  (0x6F'u8, "endpoint 14 buffer validate"),
  (0x75'u8, "endpoint 4 buffer clear"),
  (0x76'u8, "endpoint 5 buffer clear"),
  (0x77'u8, "endpoint 6 buffer clear"),
  (0x78'u8, "endpoint 7 buffer clear"),
  (0x79'u8, "endpoint 8 buffer clear"),
  (0x7A'u8, "endpoint 9 buffer clear"),
  (0x7B'u8, "endpoint 10 buffer clear"),
  (0x7C'u8, "endpoint 11 buffer clear"),
  (0x7D'u8, "endpoint 12 buffer clear"),
  (0x7E'u8, "endpoint 13 buffer clear"),
  (0x7F'u8, "endpoint 14 buffer clear"),
  (0x85'u8, "endpoint 4 unstall"),
  (0x86'u8, "endpoint 5 unstall"),
  (0x87'u8, "endpoint 6 unstall"),
  (0x88'u8, "endpoint 7 unstall"),
  (0x89'u8, "endpoint 8 unstall"),
  (0x8A'u8, "endpoint 9 unstall"),
  (0x8B'u8, "endpoint 10 unstall"),
  (0x8C'u8, "endpoint 11 unstall"),
  (0x8D'u8, "endpoint 12 unstall"),
  (0x8E'u8, "endpoint 13 unstall"),
  (0x8F'u8, "endpoint 14 unstall")]

# The illegal list, hand-written. The authority parenthesises these four codes
# and gives each a reason: two endpoints have a direction that forbids the
# access, and two operations it documents as unpredictable. They are numbered
# and forbidden, which is a different finding from unnumbered, so they get a
# list and a class of their own rather than falling to the unspecified sweep.
const illegalCommands: array[4, tuple[opcode: uint8, name: string,
                                      detail: string]] = [
  (0x00'u8, "write control OUT buffer", "the endpoint is read-only"),
  (0x11'u8, "read control IN buffer", "the endpoint is write-only"),
  (0x60'u8, "validate control OUT buffer",
   "validating an OUT buffer is unpredictable"),
  (0x71'u8, "clear control IN buffer",
   "clearing an IN buffer is unpredictable")]

# The implemented commands that speak on a fresh handle. Block 1 asserts that
# an accepted command is silent, and one accepted command is legitimately not:
# a validate with no buffer write staged for it is a firmware fault the model
# reports. It is listed here with its line rather than exempted, so the
# exception is asserted and not merely skipped.
const speaksOnFreshHandle: array[1, tuple[opcode: uint8, want: string]] = [
  (0x61'u8, "isp1181: a validate for endpoint 0 IN found no buffer write " &
            "staged for it; nothing is validated")]

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
    var speaks = false
    for row in speaksOnFreshHandle:
      if row.opcode == opcode:
        speaks = true
    if speaks:
      continue
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

const wantAccepted: Accepted = (firstBad: "", driven: 41)

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
const wantRefused: Refused = (firstBad: "", driven: 100)
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
  for row in illegalCommands:
    if row.opcode == opcode:
      numbered = true
  if not numbered:
    unspecifiedRows.add((opcode: opcode,
        want: "isp1181: command 0x" & toHex(opcode) &
              " is not in the specified command set; the read answers 0x00"))

let unspecified = driveRefused(unspecifiedRows)
const wantUnspecified: Refused = (firstBad: "", driven: 110)
check(unspecified == wantUnspecified,
      "unspecified: every unnumbered opcode answers benignly and logs one line",
      $unspecified, $wantUnspecified)

# The four illegal codes answer benignly and name the prohibition, which is a
# third thing: not "not implemented" (a decision this project took) and not
# "not in the specified command set" (a gap in the sources).
var illegalRows: seq[tuple[opcode: uint8, want: string]]
for row in illegalCommands:
  illegalRows.add((opcode: row.opcode,
      want: "isp1181: command 0x" & toHex(row.opcode) & " (" & row.name &
            ") is illegal - " & row.detail & "; nothing is done"))

let illegalDriven = driveRefused(illegalRows)
const wantIllegal: Refused = (firstBad: "", driven: 4)
check(illegalDriven == wantIllegal,
      "illegal: every code the authority forbids answers benignly and names " &
        "the prohibition",
      $illegalDriven, $wantIllegal)

# The one accepted command that speaks. It is driven here with its line
# asserted, so block 1's exemption costs no coverage.
let speaking = driveRefused(@speaksOnFreshHandle)
const wantSpeaking: Refused = (firstBad: "0x61 became the pending command",
                               driven: 1)
check(speaking == wantSpeaking,
      "accepted-and-speaking: a validate with nothing staged is accepted, " &
        "recorded as pending and reports the fault",
      $speaking, $wantSpeaking)

# The three classes partition the byte. Without this the three sweeps above
# could each be green over a set that left opcodes untouched.
type Partition = tuple[implemented: int, refused: int, illegal: int,
                       unspecified: int, total: int]
let partition: Partition = (implemented: accepted.driven +
                                         speaking.driven,
                            refused: refused.driven,
                            illegal: illegalDriven.driven,
                            unspecified: unspecified.driven,
                            total: accepted.driven + speaking.driven +
                                   refused.driven + illegalDriven.driven +
                                   unspecified.driven)
const wantPartition: Partition = (implemented: 42, refused: 100, illegal: 4,
                                  unspecified: 110, total: 256)
check(partition == wantPartition,
      "partition: the four classes cover all 256 opcodes and none twice",
      $partition, $wantPartition)

# The six commands the authority names without an opcode are recorded in the
# model rather than left in a comment, so that the day a datasheet arrives the
# list to close is a list and not a paragraph.
# The list is empty and the check is kept: asserting the empty case is what
# makes a future named-but-unnumbered command show up here as a change rather
# than as silence.
const wantUnnumbered: seq[string] = @[]
check(@unnumberedCommands == wantUnnumbered,
      "gap: no command is left named without an opcode",
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
# THE GEOMETRY TABLE IS THE CASE THAT PINS THE EP3 CORRECTION. The authority
# marks double-buffering where it exists and leaves EP3 unmarked, so the design
# document's "double" for endpoint 3 is wrong. A model with one buffer too many accepts a
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

# PEEK READS AND DOES NOT CONSUME, which is the whole difference between it and
# a buffer read. The buffer it reads is the one the last accepted
# `0x20+k` selected, because that is the only selector the authority gives this
# model - and `k` is a slot and not an endpoint number, so `0x22` selects
# endpoint 1 and not endpoint 2.
type Peek = tuple[first: uint8, second: uint8, pending: int, logged: int]

proc peekTwice(): Peek =
  let m = fresh()
  discard m.deliver(1, [0x5A'u8, 0x5B'u8])
  m.portWrite(commandPort, 0x22'u8)
  m.portWrite(commandPort, 0xD2'u8)
  let first = m.portRead(dataPort)
  m.portWrite(commandPort, 0xD2'u8)
  let secondByte = m.portRead(dataPort)
  result = (first: first, second: secondByte, pending: fifoAt(m, 2).pending,
            logged: m.logLines.len)

let peeked = peekTwice()
let wantPeeked: Peek = (first: 0x5A'u8, second: 0x5A'u8, pending: 1,
                        logged: 0)
check(peeked == wantPeeked,
      "peek: 0xD2 reads the selected endpoint's head byte and consumes none",
      $peeked, $wantPeeked)

# The control IN slot is the one that separates the two readings. Under the
# slot ordering `0x21` selects endpoint 0's IN buffer; under a reading that
# takes `k` for an endpoint number it selects endpoint 1's. The buffer is empty
# either way, so the name in the line is the whole observation.
type SlotSelect = tuple[value: uint8, log: seq[string]]

proc peekAfterControlIn(): SlotSelect =
  let m = fresh()
  m.writeVia(0x21'u8, [0x00'u8])
  m.portWrite(commandPort, 0xD2'u8)
  result = (value: m.portRead(dataPort), log: m.logLines)

let slotSelect = peekAfterControlIn()
let wantSlotSelect: SlotSelect = (value: benign,
    log: @["isp1181: peek on endpoint 0 IN found no packet; the read " &
           "answers 0x00"])
check(slotSelect == wantSlotSelect,
      "peek: 0x21 selects endpoint 0's IN buffer, which is the slot the " &
        "authority puts second",
      $slotSelect, $wantSlotSelect)

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
# A delivery drives the whole path: the packet reaches the buffer, the bit its
# endpoint owns is set, the enable the firmware writes admits it, and the line
# follows. Endpoint 1's bit is `10`, so the register reads `0x0000_0400`.

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
    interrupt: @[0x00'u8, 0x04'u8, 0x00'u8, 0x00'u8], asserted: true,
    log: @[])
check(delivered == wantDelivered,
      "irq: a delivery raises the interrupt its own endpoint owns",
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

# ---------------------------------------------------------------------------
# BLOCK 3a. The endpoint-configuration family is numbered as the authority
# numbers it, and the sixteen names are written out here by hand.
#
# ISP1362 Rev. 06 section 15.1.1 states the write codes as "20 to 2F - write
# (control OUT, control IN, endpoints 1 to 14)" and states that the sixteen
# configurations are programmed in sequence from endpoint 0 OUT to endpoint 14.
# So the slot ordering is the same one the stall, status, buffer-read and
# buffer-clear families already use, whose endpoint 1 form is base + 2.
#
# The names are asserted and not only the classes. A model that classified
# every slot correctly and named `0x24` "endpoint 4 configuration" would refuse
# a firmware's endpoint 3 write in a line that sent its reader to the wrong
# endpoint, which is a wrong answer wearing a loud message.

const configurationNames: array[16, string] = [
  "control OUT configuration", "control IN configuration",
  "endpoint 1 configuration", "endpoint 2 configuration",
  "endpoint 3 configuration", "endpoint 4 configuration",
  "endpoint 5 configuration", "endpoint 6 configuration",
  "endpoint 7 configuration", "endpoint 8 configuration",
  "endpoint 9 configuration", "endpoint 10 configuration",
  "endpoint 11 configuration", "endpoint 12 configuration",
  "endpoint 13 configuration", "endpoint 14 configuration"]

type Naming = tuple[firstBad: string, checked: int]

proc configurationNaming(): Naming =
  result = (firstBad: "", checked: 0)
  for slot in 0 ..< configurationNames.len:
    let opcode = uint8(0x20 + slot)
    inc result.checked
    if result.firstBad.len > 0:
      continue
    let got = classify(opcode).name
    if got != configurationNames[slot]:
      result.firstBad = "0x" & toHex(opcode) & " named `" & got & "` want `" &
        configurationNames[slot] & "`"

let naming = configurationNaming()
const wantNaming: Naming = (firstBad: "", checked: 16)
check(naming == wantNaming,
      "configuration: the sixteen slots carry the authority's own names",
      $naming, $wantNaming)

# The endpoint-configuration family shares its ordering with the other
# families, and the assertion is made against those other families rather than
# against a second copy of the same list. A family that drifted alone would
# satisfy a list written beside it and would fail here.

type Ordering = tuple[firstBad: string, checked: int]

proc familyOrdering(): Ordering =
  result = (firstBad: "", checked: 0)
  for (base, noun) in [(0x10, "buffer read"), (0x40, "stall"),
                       (0x50, "status"), (0x70, "buffer clear"),
                       (0x80, "unstall"), (0x20, "configuration")]:
    for endpoint in 1 .. 14:
      inc result.checked
      if result.firstBad.len > 0:
        continue
      let opcode = uint8(base + 1 + endpoint)
      let want = "endpoint " & $endpoint & " " & noun
      let got = classify(opcode).name
      if got != want:
        result.firstBad = "0x" & toHex(opcode) & " named `" & got &
          "` want `" & want & "`"

let ordering = familyOrdering()
const wantOrdering: Ordering = (firstBad: "", checked: 84)
check(ordering == wantOrdering,
      "configuration: endpoint n sits at base + 1 + n in every family that " &
        "numbers endpoints",
      $ordering, $wantOrdering)

# No configuration write is silently dropped. Every one of the sixteen slots
# either becomes the pending command or writes exactly one log line naming
# itself, and the two outcomes are separated so that neither can stand in for
# the other. A slot that did neither would be a write the firmware issued and
# the model reported nowhere.

type Loudness = tuple[accepted: seq[int], loud: seq[int],
                      unaccounted: seq[int]]
  ## `unaccounted` is broader than silence on purpose. It holds a slot the
  ## model dropped without a word AND a slot whose one line names a different
  ## slot, because a reader sent to the wrong endpoint is no better served than
  ## a reader sent nowhere.

proc configurationLoudness(): Loudness =
  for slot in 0 ..< configurationNames.len:
    let opcode = uint8(0x20 + slot)
    let m = fresh()
    m.portWrite(commandPort, opcode)
    if m.lastCommand == int(opcode) and m.logLines.len == 0:
      result.accepted.add(slot)
    elif m.logLines.len == 1 and configurationNames[slot] in m.logLines[0]:
      result.loud.add(slot)
    else:
      result.unaccounted.add(slot)

let loudness = configurationLoudness()
const wantLoudness: Loudness = (accepted: @[0, 1, 2, 3, 4],
                                loud: @[5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
                                unaccounted: @[])
check(loudness == wantLoudness,
      "configuration: every slot is accepted or names itself in one line, " &
        "and none goes unaccounted for",
      $loudness, $wantLoudness)

# Endpoint 3 can be configured. Its slot is `0x24` under section 15.1.1's
# ordering, this model carries a buffer for it, and with EPDIR set the endpoint
# queues and transmits like endpoint 1 does.

type Endpoint3 = tuple[queued: bool, sent: bool, log: seq[string]]

var sent3 = 0

proc countTx(user: pointer; endpoint: cint; data: ptr uint8;
             length: csize_t) {.cdecl.} =
  inc sent3

proc driveEndpoint3(): Endpoint3 =
  sent3 = 0
  let m = newISP1181(addr hostToken, ignoreIrq, countTx)
  m.writeVia(0x24'u8, [0x40'u8])
  let queued = m.queueIn(3, [0xA5'u8])
  let sent = m.transmit(3)
  (queued: queued, sent: sent, log: m.logLines)

let endpoint3 = driveEndpoint3()
let wantEndpoint3: Endpoint3 = (queued: true, sent: true, log: @[])
check(endpoint3 == wantEndpoint3,
      "configuration: endpoint 3 is configured through 0x24 and an IN " &
        "EPDIR lets it queue and transmit",
      $endpoint3, $wantEndpoint3)

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
