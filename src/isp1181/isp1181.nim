## The full model of the Philips ISP1181 USB device controller on CS3.
##
## The port split is the one piece of address decoding this model does. The
## chip's A0 is wired to CPU A4, so bit 4 of the address is the chip's
## command/data select, the command port is `0x13000010` and the data port is
## `0x13000000`. Everything coarser than that bit belongs to the board, which
## owns the CS3 window decode, so this model refuses no address.
##
## Every access this model cannot answer truthfully answers benignly and says
## so. A device model that answered a command it does not implement, or that
## truncated a packet, or that wrapped a register at its width, hands the
## firmware a plausible value with nothing marking it wrong. Every such site
## here writes exactly one log line.
##
## Multi-byte registers are least significant byte first. The mode register is
## eight bits and the interrupt register thirty-two. The hardware configuration
## register's sixteen follow from the firmware value `0x2300`. The device
## address and the interrupt enable are widths this file chose: the authority
## gives the enable's value `0x1F07` and not its width, and an enable narrower
## than the register it masks could not mask it, so it is the register's width.
##
## No source on this machine assigns an interrupt-register bit to an event, so
## this model assigns none and says so on every delivery. The alternative was a
## bit chosen here, which the firmware would then obey.
##
## Two sequencing rules below are this file's and not the authority's, because
## no document on this machine states either way. First, a command this model
## refuses leaves a transfer already in progress live, so a data byte written
## after a refusal lands in the earlier command's operand; hardware would more
## plausibly read any command-port write as a new command and abandon the
## previous one. Second, `peek` reads the FIFO of the endpoint an
## endpoint-configuration command last selected, which couples selection to
## configuration where nothing here couples them.
##
## The model is not wired to the five C entry points. `src/isp1181/stub.nim`
## carries those and selects which implementation stands behind them.

import std/strutils

import ./commands
import ./fifo

type
  Isp1181IrqFn* = proc (user: pointer; asserted: cint) {.cdecl.}
    ## The logical interrupt state and not the pin state. The interrupt is
    ## active-low and level-triggered, and the board owns the inversion. 1 means
    ## the device requests service.

  Isp1181TxFn* = proc (user: pointer; endpoint: cint; data: ptr uint8;
                       length: csize_t) {.cdecl.}

  Transfer = enum
    ## What the data port carries while a command is pending. `tfNone` is the
    ## state of a command that takes no operand, and a data-port access in that
    ## state is refused rather than guessed at.
    ##
    ## `tfAbsent` is a read with nothing behind it. It is a state rather than a
    ## refusal at command time because the command was accepted: a peek of an
    ## empty buffer is a legal command whose answer does not exist. The report
    ## belongs to the read that asks for the byte, not to the command that set
    ## the read up.
    tfNone, tfWrite, tfRead, tfAbsent

  ISP1181* = ref object
    user: pointer
    irq: Isp1181IrqFn
    tx: Isp1181TxFn
    pending: int                 ## The accepted command, or -1 when none.
    transfer: Transfer
    width: int                   ## Operand bytes the pending command carries.
    index: int                   ## Operand bytes already moved.
    latch: uint32                ## The operand under construction or on offer.
    absentNote: string           ## What a `tfAbsent` read reports.
    hwConfig: uint16
    mode: uint8
    deviceAddress: uint8
    interruptEnable: uint32
    interruptRegister: uint32
    endpointConfig: array[4, uint8]
    selected: int                ## The endpoint the last 0x20+idx selected.
    asserted: bool
    fifos: array[5, Fifo]
    log: seq[string]

const
  benignValue* = 0x00'u8
    ## The byte the model answers when it has nothing true to say. It is zero
    ## because the register the firmware reads most often is the interrupt
    ## register, whose zero means no interrupt is pending.
  fifoCount* = 5
  softctBit* = 0x01'u8
    ## The mode register bits. The rest - DISGLBL `0x02`, DBGMOD `0x04`,
    ## INTENA `0x08`, GOSUSP `0x20`, SNDRSU `0x40`, DMAWD `0x80` - live in the
    ## same byte and need no name here until a caller reads one.
  commandSelect = 0x10'u32
  resetCommand = 0xF6'u8
  peekCommand = 0xD2'u8
  epConfigBase = 0x20'u8

const fifoNames: array[fifoCount, string] = [
  "endpoint 0 OUT", "endpoint 0 IN", "endpoint 1", "endpoint 2", "endpoint 3"]

const fifoShape: array[fifoCount, tuple[capacity: int, buffers: int]] = [
  (64, 1),   ## endpoint 0 OUT
  (64, 1),   ## endpoint 0 IN
  (16, 2),   ## endpoint 1
  (64, 2),   ## endpoint 2
  (64, 1)]   ## endpoint 3 - single, deliberately. The design document says
             ## "double" for this row and that is the error: the endpoint table
             ## marks double-buffering where it exists and leaves EP3 unmarked.

const outFifoOfEndpoint: array[4, int] = [0, 2, 3, 4]
  ## The buffer a packet from the host lands in. Endpoint 0 is the only
  ## endpoint with two, and a delivery is an OUT transfer, so it lands in
  ## index 0 and never in the IN buffer at index 1.

proc fifoName*(index: int): string = fifoNames[index]

proc isCommandPort*(address: uint32): bool =
  (address and commandSelect) != 0

proc note(m: ISP1181; line: string) =
  m.log.add(line)

proc updateIrq(m: ISP1181) =
  ## The line is level-triggered and active-low at the pin; the board owns the
  ## inversion, so what travels here is the logical state. The callback reports
  ## changes only.
  let want = (m.interruptRegister and m.interruptEnable) != 0
  if want == m.asserted:
    return
  m.asserted = want
  if not m.irq.isNil:
    m.irq(m.user, cint(if want: 1 else: 0))

proc clearState(m: ISP1181) =
  m.pending = -1
  m.transfer = tfNone
  m.width = 0
  m.index = 0
  m.latch = 0
  m.hwConfig = 0
  m.mode = 0
  m.deviceAddress = 0
  m.interruptEnable = 0
  m.interruptRegister = 0
  for i in 0 ..< m.endpointConfig.len:
    m.endpointConfig[i] = 0
  m.selected = 0
  for i in 0 ..< fifoCount:
    m.fifos[i].clear()
  m.updateIrq()

proc newISP1181*(user: pointer; irq: Isp1181IrqFn;
                 tx: Isp1181TxFn): ISP1181 =
  new(result)
  result.user = user
  result.irq = irq
  result.tx = tx
  for i in 0 ..< fifoCount:
    result.fifos[i] = initFifo(fifoShape[i].capacity, fifoShape[i].buffers)
  result.clearState()

proc lastCommand*(m: ISP1181): int =
  ## The opcode of the last accepted command, or -1 when none has been
  ## accepted. A refused command never becomes this.
  if m.isNil: -1 else: m.pending

proc logLines*(m: ISP1181): seq[string] =
  if m.isNil: @[] else: m.log

proc irqAsserted*(m: ISP1181): bool =
  if m.isNil: false else: m.asserted

proc softct*(m: ISP1181): bool =
  ## SOFTCT is state the model needs, so it is readable as itself and not only
  ## as a bit of the mode byte.
  (not m.isNil) and (m.mode and softctBit) != 0

proc fifoAt*(m: ISP1181; index: int): Fifo =
  m.fifos[index]

proc raiseInterrupt*(m: ISP1181; mask: uint32) =
  ## The only way a bit of the interrupt register is ever set, and no command in
  ## the implemented set calls it: the authority names no event-to-bit
  ## assignment, so the model exposes the register and assigns nothing.
  if m.isNil:
    return
  m.interruptRegister = m.interruptRegister or mask
  m.updateIrq()

proc clearInterrupt*(m: ISP1181; mask: uint32) =
  if m.isNil:
    return
  m.interruptRegister = m.interruptRegister and not mask
  m.updateIrq()

proc deliver*(m: ISP1181; endpoint: int; data: openArray[uint8]): bool =
  ## A packet from the host. `false` is the NAK.
  if m.isNil:
    return false
  if endpoint < 0 or endpoint >= outFifoOfEndpoint.len:
    m.note("isp1181: a packet reached endpoint " & $endpoint &
           ", which this model does not implement; the packet is dropped")
    return false
  let index = outFifoOfEndpoint[endpoint]
  if not m.fifos[index].accept(data):
    m.note("isp1181: " & fifoNames[index] & " refused a packet of " &
           $data.len & " bytes; the buffer holds " &
           $m.fifos[index].pending & " of " & $m.fifos[index].buffers)
    return false
  m.note("isp1181: a packet reached endpoint " & $endpoint &
         " and no source names the interrupt register bit for it; no " &
         "interrupt is raised")
  true

proc beginTransfer(m: ISP1181; opcode: uint8; kind: Transfer; width: int;
                   value: uint32) =
  m.pending = int(opcode)
  m.transfer = kind
  m.width = width
  m.index = 0
  m.latch = value

proc writeCommand(m: ISP1181; opcode: uint8) =
  let command = classify(opcode)
  # Both refusals below return without touching `pending`, `transfer`, `width`
  # or `index`, so a transfer already in progress survives the refusal. That
  # sequencing is this file's choice where the authority is silent.
  case command.class
  of ccNotImplemented:
    m.note("isp1181: command 0x" & toHex(opcode) & " (" & command.name &
           ") is not implemented; the read answers 0x00")
    return
  of ccUnspecified:
    m.note("isp1181: command 0x" & toHex(opcode) &
           " is not in the specified command set; the read answers 0x00")
    return
  of ccImplemented:
    discard

  if opcode >= epConfigBase and int(opcode) - int(epConfigBase) < 4:
    m.selected = int(opcode) - int(epConfigBase)
    m.beginTransfer(opcode, tfWrite, 1, 0)
    return

  case opcode
  of resetCommand:
    m.clearState()
    m.beginTransfer(opcode, tfNone, 0, 0)
  of 0xBA'u8: m.beginTransfer(opcode, tfWrite, 2, 0)
  of 0xBB'u8: m.beginTransfer(opcode, tfRead, 2, uint32(m.hwConfig))
  of 0xB8'u8: m.beginTransfer(opcode, tfWrite, 1, 0)
  of 0xB9'u8: m.beginTransfer(opcode, tfRead, 1, uint32(m.mode))
  of 0xB6'u8: m.beginTransfer(opcode, tfWrite, 1, 0)
  of 0xB7'u8: m.beginTransfer(opcode, tfRead, 1, uint32(m.deviceAddress))
  of 0xC2'u8: m.beginTransfer(opcode, tfWrite, 4, 0)
  of 0xC3'u8: m.beginTransfer(opcode, tfRead, 4, m.interruptEnable)
  of 0xC0'u8: m.beginTransfer(opcode, tfRead, 4, m.interruptRegister)
  of peekCommand:
    # `m.selected` is set only by an endpoint-configuration command, so this
    # couples the peek target to configuration. That coupling is this file's
    # choice where the authority is silent.
    let index = outFifoOfEndpoint[m.selected]
    let head = m.fifos[index].peek()
    if head.ok:
      m.beginTransfer(opcode, tfRead, 1, uint32(head.value))
    else:
      m.absentNote = "isp1181: peek on " & fifoNames[index] &
        " found no packet; the read answers 0x00"
      m.beginTransfer(opcode, tfAbsent, 1, 0)
  else:
    # `0xF4` acknowledge setup. The authority gives the opcode and no effect, so
    # the model accepts it and changes nothing.
    m.beginTransfer(opcode, tfNone, 0, 0)

proc commitOperand(m: ISP1181) =
  case m.pending
  of 0xBA: m.hwConfig = uint16(m.latch)
  of 0xB8: m.mode = uint8(m.latch)
  of 0xB6: m.deviceAddress = uint8(m.latch)
  of 0xC2:
    m.interruptEnable = m.latch
    m.updateIrq()
  else:
    if m.pending >= int(epConfigBase) and
        m.pending - int(epConfigBase) < m.endpointConfig.len:
      m.endpointConfig[m.pending - int(epConfigBase)] = uint8(m.latch)

proc writeData(m: ISP1181; value: uint8) =
  if m.transfer != tfWrite:
    m.note("isp1181: a data port write of 0x" & toHex(value) &
           " arrived with no command pending; the byte is discarded")
    return
  if m.index >= m.width:
    let command = classify(uint8(m.pending))
    m.note("isp1181: command 0x" & toHex(uint8(m.pending)) & " (" &
           command.name & ") takes " & $m.width & " byte" &
           (if m.width == 1: "" else: "s") & " and a " & $(m.index + 1) &
           (if m.index == 1: "nd" elif m.index == 2: "rd" else: "th") &
           " was written; the byte is discarded")
    inc m.index
    return
  m.latch = m.latch or (uint32(value) shl (8 * m.index))
  inc m.index
  if m.index == m.width:
    m.commitOperand()

proc readData(m: ISP1181): uint8 =
  if m.transfer == tfAbsent and m.index < m.width:
    m.note(m.absentNote)
    inc m.index
    return benignValue
  if m.transfer notin {tfRead, tfAbsent}:
    m.note("isp1181: a data port read arrived with no command pending; the " &
           "read answers 0x00")
    return benignValue
  if m.index >= m.width:
    let command = classify(uint8(m.pending))
    m.note("isp1181: command 0x" & toHex(uint8(m.pending)) & " (" &
           command.name & ") yields " & $m.width & " byte" &
           (if m.width == 1: "" else: "s") & " and a " & $(m.index + 1) &
           (if m.index == 1: "nd" elif m.index == 2: "rd" else: "th") &
           " was read; the read answers 0x00")
    inc m.index
    return benignValue
  result = uint8((m.latch shr (8 * m.index)) and 0xFF'u32)
  inc m.index

proc portWrite*(m: ISP1181; address: uint32; value: uint8) =
  ## A nil handle is answered rather than aborted: the caller is a plugin's host
  ## and an abort destroys a session that has nothing to do with this model.
  if m.isNil:
    return
  if isCommandPort(address):
    m.writeCommand(value)
  else:
    m.writeData(value)

proc portRead*(m: ISP1181; address: uint32): uint8 =
  if m.isNil:
    return benignValue
  if isCommandPort(address):
    # The command port answers benignly and silently. It is write-only - the
    # firmware issues commands there and reads operands at the data port - and a
    # model that echoed the last command byte would be presenting a register the
    # chip does not have.
    return benignValue
  m.readData()
