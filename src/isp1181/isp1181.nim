## The full model of the Philips ISP1181 USB device controller on CS3.
##
## THE PORT SPLIT IS THE ONE PIECE OF ADDRESS DECODING THIS MODEL DOES. The
## chip's A0 is wired to CPU A4, so bit 4 of the address is the chip's
## command/data select, the command port is `0x13000010` and the data port is
## `0x13000000`. Everything coarser than that bit belongs to the board, which
## owns the CS3 window decode, so this model refuses no address.
##
## EVERY ACCESS THIS MODEL CANNOT ANSWER TRUTHFULLY ANSWERS BENIGNLY AND SAYS
## SO. The refusal is the point. A device model that answered a command it does
## not implement, or that truncated a packet, or that wrapped a register at its
## width, hands the firmware a plausible value with nothing marking it wrong -
## and a wrong value returned without complaint is the one outcome this project
## refuses. Every such site here writes exactly one log line.
##
## MULTI-BYTE REGISTERS ARE LEAST SIGNIFICANT BYTE FIRST. The authority states
## the mode register's width and the interrupt register's; the hardware
## configuration register's follows from the firmware value `0x2300`. THE
## DEVICE ADDRESS AND THE INTERRUPT ENABLE ARE WIDTHS THIS FILE CHOSE: the
## authority gives the enable's value `0x1F07` and not its width, and an enable
## narrower than the register it masks could not mask it, so it is the
## register's width.
##
## THE ENDPOINT-COMPLETION BITS ARE ASSIGNED AND NOTHING ELSE IS. Two
## sources agree on them: the emulated firmware's own service routine, which
## dispatches bits 8 and 9 to fixed routines and bits 10 upwards to a table of
## per-endpoint function pointers, and the inherited ISP1362 Rev. 06 Table 143
## layout, in which bit 8 is EP0OUT, bit 9 is EP0IN and bits 10 upwards are
## EP1 and after. The firmware's own interrupt enable, `0x00001F07`, arms
## bits 8 to 12, one for each buffer this model carries.
## `interruptBitOfFifo` is the assignment - its length is `fifoCount`, so a
## buffer added without a bit does not compile - and `docs/sources.md` records
## what each half of the agreement is worth.
##
## THE BUS BITS 0 TO 2 AND THE TRANSFER BITS 3 TO 7 ARE STILL UNASSIGNED, and
## the two sources DISAGREE about two of them: the firmware dispatches bit 1 to
## suspend and bit 2 to resume, and the inherited table calls bit 1 RESUME and
## bit 2 SUSPND. Nothing here would set them either way - this model's API
## delivers an endpoint and bytes and carries no bus event at all - so they are
## left where the disagreement leaves them.
##
## THE INTERRUPT REGISTER DOES NOT CLEAR WHEN THE FIRMWARE READS IT. `0xC0`
## reports the register and leaves it, and the bit is taken away by a read of
## the owning endpoint's status register, `0x50+n`. THAT ROUTE IS INHERITED
## from ISP1362 Rev. 06 p.53 and not read from an ISP1181 document, and it is
## the piece that keeps the emulated firmware out of its own handler: the
## service routine reads four status bytes and never writes them back, so a bit
## with no route out of the register would spin the machine. `docs/sources.md`
## carries what is still owed on it.
##
## THE SEQUENCING RULES BELOW ARE THIS FILE'S AND NOT THE AUTHORITY'S, and they
## are named here because no document on this machine states either way.
## FIRST, a command this model refuses leaves a transfer already in progress
## LIVE, so a data byte written after a refusal lands in the earlier command's
## operand; hardware would more plausibly read any command-port write as a new
## command and abandon the previous one. SECOND, `peek` reads the FIFO of the
## endpoint an endpoint-CONFIGURATION command last selected, which couples
## selection to configuration where nothing here couples them. Both are
## recorded as choices rather than as findings, and settling either is an
## operator decision and not a repair.
##
## THE C ENTRY POINTS LIVE IN `src/isp1181/stub.nim` AND SELECT BETWEEN THE
## TWO IMPLEMENTATIONS. A fresh handle selects the stub and
## `isp1181_set_backend` moves it here; the default was left where it was so
## that no existing caller acquires a device that answers from a register file
## and can call back without an edit of its own. This file supplies the model
## and still selects nothing.
##
## THE DEVICE-TO-HOST PATH IS CONNECTED AT BOTH ENDS. `transmit` hands an
## endpoint's IN buffer to the transmit callback, `queueIn` fills that buffer,
## and the firmware now reaches `queueIn` through Write control IN buffer
## (`0x01`) followed by Validate control IN buffer (`0x61`). The OUT direction
## is Read Buffer (`0x10`, `0x12` to `0x14`) followed by Clear Buffer (`0x70`,
## `0x72` to `0x74`), which is the sequence the authority states.
##
## `transmit` IS CALLED BY THE HOST AND NOT BY THE VALIDATE. A validate is the
## firmware saying the buffer is now the host's; it is not the moment the host
## collects it. A model that transmitted there would push a packet at a host
## that had not asked, and would spend the packet on the one call it got. The
## host asks through `isp1181_in_token`, which is the bus's IN token and the
## other half of `isp1181_rx`. `src/isp1181/stub.nim` carries the entry point.
##
## THOSE OPCODES ARE INHERITED AND NOT READ FROM AN ISP1181 DOCUMENT. They come
## from Table 109 of the ISP1362 data sheet, Rev. 06, which states that it
## integrates the ISP1181B peripheral controller. THAT IS A CLAIM OF
## INTEGRATION AND NOT OF A BYTE-IDENTICAL COMMAND MAP, and the ISP1181B data
## sheet itself was not retrieved. `docs/sources.md` carries the limit in full.
##
## THE SET-UP INTERLOCK IS IMPLEMENTED AND `isp1181_setup` IS THE ROUTE THAT
## SETS IT. The authority states that a set-up packet flushes the IN buffer and
## disables Validate and Clear on both control endpoints until the firmware
## acknowledges with `0xF4`; ISP1362 Rev. 06 §12.3.6 p.53 and §15.2.7 p.117 are
## the two halves. This model once carried none of it, and the reason was a
## MISSING ROUTE and not a decision to skip: `isp1181_rx` carries an endpoint
## and bytes and no set-up flag, so the interlock would have been a latch that
## nothing ever sets. `deliverSetup` is that route, and `isp1181_setup` is its
## published entry point.
##
## SETUPT IS BIT 2 AND THE POSITION IS READ FROM THE DOCUMENT. ISP1362 Rev. 06
## Table 126 gives the DcEndpointStatus bit allocation and Table 127 gives bit 2
## as "Logic 1 indicates that the buffer contains a set-up packet". It is
## INHERITED exactly as the opcodes are and it is NOT a reading of firmware
## behaviour. WHEN THE BIT CLEARS is the part the document does not state, and
## `statusByte` and the Clear Buffer arm of `writeCommand` name the inference
## and its ground; `docs/sources.md` carries it as an Unverified row.
##
## OVERWRITE, BIT 3, IS THE ONE PART OF §12.3.6 STILL ABSENT. `deliverSetup`
## refuses a set-up packet arriving at a full control OUT buffer rather than
## overwriting one the firmware has not acknowledged, because the bit that
## would report the overwrite is not tracked.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Nothing here
## is copied from a Philips or NXP document.

import std/strutils

import ./commands
import ./fifo

const fifoCount* = 5
  ## THE BUFFERS THIS MODEL CARRIES, and the length of every per-buffer array
  ## below. They are `fifos`' own order - endpoint 0 OUT, endpoint 0 IN, then
  ## endpoints 1 to 3 - which is the order ISP1362 Rev. 06 section 15.1.1 gives
  ## the endpoint-configuration slots.

type
  Isp1181IrqFn* = proc (user: pointer; asserted: cint) {.cdecl.}
    ## The LOGICAL interrupt state and not the pin state, as
    ## `include/mcf5307.h` states it. The interrupt is active-low and
    ## level-triggered, and the BOARD owns the inversion. 1 means the device
    ## requests service.

  Isp1181TxFn* = proc (user: pointer; endpoint: cint; data: ptr uint8;
                       length: csize_t) {.cdecl.}

  Transfer = enum
    ## What the data port carries while a command is pending. `tfNone` is the
    ## state of a command that takes no operand, and a data-port access in that
    ## state is refused rather than guessed at.
    ##
    ## `tfAbsent` IS A READ WITH NOTHING BEHIND IT, and it is a state rather
    ## than a refusal at command time because the command WAS accepted: a peek
    ## of an empty buffer is a legal command whose answer does not exist. The
    ## report belongs to the read that asks for the byte, not to the command
    ## that set the read up.
    ##
    ## `tfBufferRead` AND `tfBufferWrite` ARE VARIABLE WIDTH, which is why they
    ## are states of their own and not `tfRead` and `tfWrite` with a wider
    ## latch. A register operand is at most four bytes and fits the latch; an
    ## endpoint buffer carries its own length in band, so its width is a
    ## property of the packet and not of the opcode.
    tfNone, tfWrite, tfRead, tfAbsent, tfBufferRead, tfBufferWrite

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
    endpointConfig: array[fifoCount, uint8]
      ## One DcEndpointConfiguration byte per buffer, INDEXED AS `fifos` IS.
      ## ISP1362 Rev. 06 section 15.1.1 orders the configuration slots control
      ## OUT, control IN, then endpoints 1 to 14, which is the order `fifos`
      ## is in, so a slot and the buffer it configures share one index.
    selected: int                ## The BUFFER the last 0x20+k selected.
    setupHeld: bool
      ## SETUPT for the CONTROL OUT buffer, and for that buffer alone. ISP1362
      ## Rev. 06 Table 127 gives bit 2 as "Logic 1 indicates that the buffer
      ## contains a set-up packet", and a set-up packet reaches no other buffer
      ## in this model, so a per-buffer array here would be four latches that
      ## nothing can ever set.
    setupUnacknowledged: bool
      ## The interlock section 12.3.6 arms: Validate Buffer and Clear Buffer
      ## are disabled on both control endpoints from the arrival of a set-up
      ## packet until `0xF4` acknowledges it.
    asserted: bool
    fifos: array[fifoCount, Fifo]
    stalled: array[fifoCount, bool]   ## EPSTAL, per buffer, set by 0x40-0x4F.
    stage: seq[uint8]            ## Bytes a buffer-write command has taken.
    stageFifo: int               ## Where a validate would commit `stage`.
    readBuf: seq[uint8]          ## The bytes a buffer-read command offers.
    log: seq[string]

const
  benignValue* = 0x00'u8
    ## The byte the model answers when it has nothing true to say. It is zero
    ## because the register the firmware reads most often is the interrupt
    ## register, whose zero means no interrupt is pending.
  epdirBit = 0x40'u8
    ## EPDIR in DcEndpointConfiguration. ISP1362 Rev. 06 Table 110 places it at
    ## bit 6 of the byte `0x20+n` writes, and Table 111 gives its meaning:
    ## "This bit defines the endpoint direction (0 = OUT, 1 = IN)". The same
    ## table places FIFOEN at bit 7, DBLBUF at bit 5, FFOISO at bit 4 and
    ## `FFOSZ[3:0]` in the low nibble.
    ##
    ## THE POSITION IS INHERITED AND NOT READ FROM AN ISP1181 DOCUMENT. ISP1362
    ## Rev. 06 states that it integrates the ISP1181B peripheral controller,
    ## which is a claim of INTEGRATION and not of a byte-identical register map,
    ## and the ISP1181B data sheet itself was not retrieved. `docs/sources.md`
    ## carries the limit in full.
  softctBit* = 0x01'u8
    ## The mode register bits. The rest - DISGLBL `0x02`, DBGMOD `0x04`,
    ## INTENA `0x08`, GOSUSP `0x20`, SNDRSU `0x40`, DMAWD `0x80` - live in the
    ## same byte and need no name here until something reads one.
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
  (64, 1)]   ## endpoint 3 - single-buffered.
  ##
  ## EVERY ROW OF THIS TABLE IS A FIRMWARE CONFIGURATION AND NOT A PROPERTY OF
  ## THE PART. ISP1362 Rev. 06 pp.51-53 put both numbers in the
  ## DcEndpointConfiguration register: the buffer size in `FFOSZ[3:0]`, where
  ## `0001` selects 16 bytes for a non-isochronous endpoint, and the buffering
  ## scheme in `DBLBUF`. So "endpoint 1 is 16 bytes" and "endpoint 3 is
  ## single-buffered" are facts about the image this model was measured
  ## against, and they would be different facts under a different image.
  ##
  ## THE OBSERVATION IS KEPT AND ONLY ITS LABEL MOVES. These are still the best
  ## evidence available for what the emulated firmware configures; they are
  ## simply not statements about silicon. `docs/sources.md` records the same
  ## correction, and nothing here reads `endpointConfig` back into this table -
  ## a model that did would be the repair, and it is not this change.

const outFifoOfEndpoint: array[4, int] = [0, 2, 3, 4]
  ## The buffer a packet from the host lands in. Endpoint 0 is the only
  ## endpoint with two, and a delivery is an OUT transfer, so it lands in
  ## index 0 and never in the IN buffer at index 1.

const interruptBitOfFifo: array[fifoCount, int] = [8, 9, 10, 11, 12]
  ## The interrupt-register bit each buffer owns, indexed as `fifos` is. The
  ## module head names the two sources that agree on this range and the two
  ## bits on which they do not.
  ##
  ## THE ARRAY STOPS WHERE THE BUFFERS DO AND THAT IS NOT A LIMIT OF THE
  ## ASSIGNMENT. Both sources carry per-endpoint bits past 12 - the firmware's
  ## pointer table reaches bit 16 - and this model carries no buffer for them,
  ## so there is no event here that could set one.

const outFifoOfEndpoint0 = 0
  ## The buffer a set-up packet lands in, named because the set-up path uses it
  ## as ITSELF and not as "whatever endpoint 0 decodes to". A SETUP token is
  ## defined only for a control endpoint, and control OUT is the one control
  ## endpoint this model can receive on.

const inFifoOfEndpoint0 = 1
  ## The buffer a packet for the host waits in. It is endpoint 0's SECOND
  ## buffer - the one `fifoShape` names IN - and it is the only buffer in this
  ## model that a delivery from the host never touches.

const inBufferOfEndpoint: array[4, int] = [inFifoOfEndpoint0, 2, 3, 4]
  ## The buffer that carries an endpoint's DEVICE-TO-HOST direction. Endpoint 0
  ## has two buffers and this is its IN one; endpoints 1 to 3 have one buffer
  ## each, and whether that buffer is the IN one is what EPDIR says.

type BufferDirection = enum
  ## Which way one buffer faces.
  bdOut
  bdIn

proc directionOfBuffer(m: ISP1181; index: int): BufferDirection =
  ## THE CONTROL ENDPOINT'S TWO BUFFERS DO NOT CONSULT EPDIR. ISP1362 Rev. 06
  ## section 15.1.1 states that control endpoints have fixed configurations and
  ## are included in the initialization sequence only to be given their default
  ## values, so their direction is a property of the endpoint and not of a byte
  ## the firmware may write differently.
  ##
  ## `endpointConfig` IS INDEXED AS THE CONFIGURATION SEQUENCE IS. Section
  ## 15.1.1 orders the sixteen slots control OUT, control IN, then endpoints 1
  ## to 14, and `fifos` is in that same order, so slot and buffer share one
  ## index.
  if index <= inFifoOfEndpoint0:
    return (if index == inFifoOfEndpoint0: bdIn else: bdOut)
  if (m.endpointConfig[index] and epdirBit) != 0: bdIn else: bdOut

proc fifoName*(index: int): string = fifoNames[index]

proc isCommandPort*(address: uint32): bool =
  (address and commandSelect) != 0

proc note(m: ISP1181; line: string) =
  m.log.add(line)

proc updateIrq(m: ISP1181) =
  ## THE LINE IS LEVEL-TRIGGERED AND THE CALLBACK REPORTS CHANGES. The line is
  ## level-triggered and active-low at the pin; the board owns the inversion,
  ## so what travels here is the logical state.
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
  m.stage = @[]
  m.stageFifo = -1
  m.readBuf = @[]
  for i in 0 ..< fifoCount:
    m.fifos[i].clear()
    m.stalled[i] = false
  m.setupHeld = false
  m.setupUnacknowledged = false
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
  ## The opcode of the last ACCEPTED command, or -1 when none has been
  ## accepted. A refused command never becomes this.
  if m.isNil: -1 else: m.pending

proc logLines*(m: ISP1181): seq[string] =
  if m.isNil: @[] else: m.log

proc irqAsserted*(m: ISP1181): bool =
  if m.isNil: false else: m.asserted

proc softct*(m: ISP1181): bool =
  ## The SOFTCT bit is state the model needs, so it is readable as itself and
  ## not only as a bit of the mode byte.
  (not m.isNil) and (m.mode and softctBit) != 0

proc fifoAt*(m: ISP1181; index: int): Fifo =
  m.fifos[index]

proc raiseInterrupt*(m: ISP1181; mask: uint32) =
  ## THE ONLY WAY A BIT OF THE INTERRUPT REGISTER IS EVER SET, and no command
  ## in the implemented set calls it: the authority names no event-to-bit
  ## assignment, so the model exposes the register and leaves the assignment to
  ## whichever task acquires a source for it.
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
  # EPDIR REFUSES A DELIVERY FOR THE SAME REASON IT REFUSES A QUEUE. Endpoints
  # 1 to 3 carry ONE buffer each and the bit says which way it faces, so a
  # packet from the host arriving at a buffer the firmware pointed IN has
  # nowhere to land. Taking it would raise that endpoint's own interrupt and
  # show the firmware an OUT transfer on a buffer it declared for transmission,
  # which is the plausible wrong outcome this file refuses everywhere else.
  if m.directionOfBuffer(index) == bdIn:
    m.note("isp1181: endpoint " & $endpoint & " is configured IN - EPDIR is " &
           "1 in its DcEndpointConfiguration - so it has no OUT buffer; the " &
           "packet is dropped")
    return false
  if not m.fifos[index].accept(data):
    m.note("isp1181: " & fifoNames[index] & " refused a packet of " &
           $data.len & " bytes; the buffer holds " &
           $m.fifos[index].pending & " of " & $m.fifos[index].buffers)
    return false
  m.raiseInterrupt(1'u32 shl interruptBitOfFifo[index])
  true

proc deliverSetup*(m: ISP1181; data: openArray[uint8]): bool =
  ## A SET-UP packet from the host. `false` is the refusal, and every refusal
  ## writes the line that says which one it is.
  ##
  ## THIS IS A SEPARATE ENTRY POINT AND NOT A FLAG ON `deliver`, and it carries
  ## NO ENDPOINT. A SETUP token is defined only for a control endpoint, this
  ## model has exactly one it can receive on, and an endpoint argument here
  ## would be a parameter with one legal value - a value a computed endpoint
  ## could miss, with nothing to catch it.
  ##
  ## WHAT THE ARRIVAL DOES IS ISP1362 Rev. 06 SECTION 12.3.6, p.53, READ AND
  ## NOT INFERRED: "The arrival of a set-up packet flushes the IN buffer, and
  ## disables the Validate Buffer and Clear Buffer commands for the control IN
  ## and OUT endpoints. The microprocessor must re-enable these commands by
  ## sending an acknowledge set-up command to both the control endpoints."
  ## Table 127's bit 7 and section 15.2.3 add the unstall: a control endpoint
  ## "is automatically unstalled on receiving a set-up token", "regardless of
  ## the packet content".
  ##
  ## OVERWRITE IS THE ONE PART OF SECTION 12.3.6 THIS MODEL DOES NOT CARRY. The
  ## authority gives bit 3 to a set-up packet that landed on an unacknowledged
  ## one, and the model tracks no such bit, so a set-up packet arriving at a
  ## full buffer is REFUSED BY NAME rather than silently overwriting: an
  ## overwrite with no bit to report it is the plausible wrong outcome this
  ## file refuses everywhere else.
  if m.isNil:
    return false
  if data.len == 0:
    m.note("isp1181: a set-up packet of zero bytes reached " &
           fifoNames[outFifoOfEndpoint0] &
           " and a SETUP transaction carries eight; nothing is delivered")
    return false
  if m.fifos[outFifoOfEndpoint0].isFull:
    m.note("isp1181: a set-up packet reached " &
           fifoNames[outFifoOfEndpoint0] &
           ", which already holds " & $m.fifos[outFifoOfEndpoint0].pending &
           " of " & $m.fifos[outFifoOfEndpoint0].buffers &
           "; the authority reports that case in OVERWRITE, which this model " &
           "does not track, so the packet is dropped rather than overwriting")
    return false
  if not m.fifos[outFifoOfEndpoint0].accept(data):
    m.note("isp1181: " & fifoNames[outFifoOfEndpoint0] &
           " refused a set-up packet of " & $data.len & " bytes; the buffer " &
           "holds " & $m.fifos[outFifoOfEndpoint0].pending & " of " &
           $m.fifos[outFifoOfEndpoint0].buffers)
    return false
  m.fifos[inFifoOfEndpoint0].clear()
  m.stalled[outFifoOfEndpoint0] = false
  m.stalled[inFifoOfEndpoint0] = false
  m.setupHeld = true
  m.setupUnacknowledged = true
  m.raiseInterrupt(1'u32 shl interruptBitOfFifo[outFifoOfEndpoint0])
  true

proc queueIn*(m: ISP1181; endpoint: int; data: openArray[uint8]): bool =
  ## The FIRMWARE side of a device-to-host transfer: bytes placed in the
  ## endpoint's IN buffer, waiting for the host to collect them. `false` is the
  ## refusal, and every refusal writes the line that says which one it is.
  ##
  ## THE FIRMWARE REACHES THIS THROUGH `0x01` THEN `0x61` - Write control IN
  ## buffer, then Validate control IN buffer. `commitValidate` is the caller.
  ## The two opcodes are inherited from ISP1362 Rev. 06 Table 109 and were not
  ## read from an ISP1181 document; the module head states the limit.
  ##
  ## WHICH ENDPOINT MAY BE QUEUED IS READ OUT OF ITS CONFIGURATION BYTE.
  ## Endpoints 1 to 3 carry ONE buffer each and EPDIR is which way it faces, so
  ## the question the model asks is not which endpoint this is but what the
  ## firmware configured it as. `directionOfBuffer` states where the bit and the
  ## slot ordering come from.
  if m.isNil:
    return false
  if endpoint < 0 or endpoint >= inBufferOfEndpoint.len:
    m.note("isp1181: a transmit was queued for endpoint " & $endpoint &
           ", which this model does not implement; nothing is queued")
    return false
  let index = inBufferOfEndpoint[endpoint]
  case m.directionOfBuffer(index)
  of bdIn: discard
  of bdOut:
    m.note("isp1181: endpoint " & $endpoint & " is configured OUT - EPDIR " &
           "is 0 in its DcEndpointConfiguration - so it has no IN buffer; " &
           "nothing is queued")
    return false
  if data.len == 0:
    m.note("isp1181: an empty packet was queued for " & fifoNames[index] &
           " and no source on this machine states what a zero-length IN " &
           "packet carries; nothing is queued")
    return false
  if not m.fifos[index].accept(data):
    m.note("isp1181: " & fifoNames[index] &
           " refused a packet of " & $data.len & " bytes; the buffer holds " &
           $m.fifos[index].pending & " of " &
           $m.fifos[index].buffers)
    return false
  true

proc transmit*(m: ISP1181; endpoint: int): bool =
  ## Hands the oldest packet in the endpoint's IN buffer to the host, through
  ## the transmit callback the host installed at construction. THIS IS THE ONLY
  ## PLACE A BYTE LEAVES THIS MODEL.
  ##
  ## THE PACKET IS CONSUMED ONLY WHEN THE HOST IS ACTUALLY CALLED. A model that
  ## emptied the buffer and then found no callback would leave the firmware
  ## with a transfer that completed and a host that never saw it, which is the
  ## plausible wrong outcome this file refuses everywhere else.
  ##
  ## THE INTERRUPT IS RAISED HERE AND NOT AT THE VALIDATE, for the same reason
  ## the packet leaves here: the validate is the firmware handing the buffer to
  ## the host, and this is the host taking it. A bit set at the validate would
  ## tell the firmware a transfer completed against a host that had not asked.
  if m.isNil:
    return false
  if endpoint < 0 or endpoint >= inBufferOfEndpoint.len:
    m.note("isp1181: a transmit was requested for endpoint " & $endpoint &
           ", which this model does not implement; nothing is transmitted")
    return false
  let index = inBufferOfEndpoint[endpoint]
  case m.directionOfBuffer(index)
  of bdIn: discard
  of bdOut:
    m.note("isp1181: endpoint " & $endpoint & " is configured OUT - EPDIR " &
           "is 0 in its DcEndpointConfiguration - so it has no IN buffer; " &
           "nothing is transmitted")
    return false
  if m.fifos[index].isEmpty:
    m.note("isp1181: " & fifoNames[index] & " has no packet to send; the " &
           "host is not called")
    return false
  if m.tx.isNil:
    m.note("isp1181: " & fifoNames[index] & " holds a packet and the host " &
           "installed no transmit callback; the packet is kept")
    return false
  var packet = m.fifos[index].take()
  m.tx(m.user, cint(endpoint), addr packet[0], csize_t(packet.len))
  m.raiseInterrupt(1'u32 shl interruptBitOfFifo[index])
  true


# ---------------------------------------------------------------------------
# THE DATA-FLOW COMMANDS. The opcode-to-buffer map is the one piece of decoding
# these families need, and it is written once here rather than in each of them.
#
# THE INHERITED OPCODES ARE NAMED AS INHERITED WHERE THEY ARE USED. Every
# opcode in this section comes from Table 109 of the ISP1362 data sheet, Rev.
# 06, which states that it integrates the ISP1181B peripheral controller. That
# is a claim of INTEGRATION and not a statement that the two command maps agree
# byte for byte, and no ISP1181B document was read. `src/isp1181/commands.nim`
# and `docs/sources.md` both carry the same limit.

const
  bufferWriteControlIn = 0x01'u8
  bufferReadControlOut = 0x10'u8
  bufferReadEndpointBase = 0x12'u8
  stallControlOut = 0x40'u8
  statusControlOut = 0x50'u8
  validateControlIn = 0x61'u8
  clearControlOut = 0x70'u8
  clearEndpointBase = 0x72'u8
  unstallControlOut = 0x80'u8
  lengthPrefixBytes = 2
    ## The authority puts the packet length in the first two bytes of the
    ## endpoint buffer, LOWER BYTE FIRST.

proc outFifoOf(m: ISP1181; opcode, controlBase, endpointBase: uint8): int =
  ## The OUT buffer a data-flow opcode names, or -1. `controlBase` is the
  ## control OUT form and `endpointBase` is endpoint 1's.
  if opcode == controlBase:
    return outFifoOfEndpoint[0]
  let endpoint = int(opcode) - int(endpointBase) + 1
  if endpoint >= 1 and endpoint < outFifoOfEndpoint.len:
    return outFifoOfEndpoint[endpoint]
  -1

proc noteInterlock(m: ISP1181; opcode: uint8; name: string) =
  ## THE INTERLOCK REFUSES OUT LOUD. A Validate or Clear that did nothing and
  ## said nothing would tell the firmware its buffer was cleared when it was
  ## not, which is the one outcome this model refuses everywhere. The refusal
  ## leaves the transfer in flight exactly as the two class refusals in
  ## `writeCommand` do, and for the same reason the head block gives.
  m.note("isp1181: command 0x" & toHex(opcode) & " (" & name &
         ") is disabled until the set-up packet is acknowledged with 0xF4; " &
         "nothing is done")

proc statusByte(m: ISP1181; index: int): uint8 =
  ## The DcEndpointStatus register as far as this model carries it: EPSTAL
  ## (bit 7), EPFULL1 (bit 6), EPFULL0 (bit 5) and SETUPT (bit 2).
  ##
  ## THE BIT POSITIONS ARE READ AND NOT INFERRED. ISP1362 Rev. 06, Table 126,
  ## "DcEndpointStatus register: bit allocation", places EPSTAL, EPFULL1,
  ## EPFULL0, DATA_PID, OVERWRITE, SETUPT and CPUBUF at bits 7 down to 1, with
  ## bit 0 reserved. Table 127 gives bit 2 as "SETUPT   Logic 1 indicates that
  ## the buffer contains a set-up packet". The position is INHERITED in exactly
  ## the sense the module head gives that word - ISP1362 states that it
  ## integrates the ISP1181B and the ISP1181B document was not retrieved - and
  ## it is not a reading of firmware behaviour.
  ##
  ## DATA_PID, OVERWRITE AND CPUBUF STILL READ ZERO AND THE MODEL DOES NOT
  ## TRACK THEM. That is a gap, and it is stated in the module head and in
  ## `docs/sources.md` rather than on every read, because a note per read would
  ## bury the notes that mark a refusal.
  let pending = m.fifos[index].pending
  result = 0'u8
  if m.stalled[index]:
    result = result or 0x80'u8
  if pending >= 2:
    result = result or 0x40'u8
  if pending >= 1:
    result = result or 0x20'u8
  if index == outFifoOfEndpoint0 and m.setupHeld:
    result = result or 0x04'u8

proc beginBufferRead(m: ISP1181; opcode: uint8; index: int) =
  ## THE PACKET IS NOT CONSUMED. The authority's OUT sequence is Read Buffer
  ## then Clear Buffer, so the read leaves the buffer as it found it and the
  ## clear is what empties it. A read that consumed would make the clear a
  ## no-op and would lose a packet the firmware retried.
  let head = m.fifos[index].peekPacket()
  var bytes = newSeq[uint8](lengthPrefixBytes)
  if head.ok:
    bytes[0] = uint8(head.packet.len and 0xFF)
    bytes[1] = uint8((head.packet.len shr 8) and 0xFF)
    for value in head.packet:
      bytes.add(value)
  # AN EMPTY BUFFER IS NOT AN ANOMALY AND WRITES NO LINE. The authority puts
  # the length in band, so a length of zero IS the truthful answer to a read of
  # an empty buffer, and firmware polls that buffer. `peek` logs its empty case
  # because it promises a BYTE and has none; a buffer read promises a LENGTH
  # and has one.
  m.readBuf = bytes
  m.pending = int(opcode)
  m.transfer = tfBufferRead
  m.width = bytes.len
  m.index = 0

proc beginBufferWrite(m: ISP1181; opcode: uint8; index: int) =
  ## The staging half of the authority's IN sequence: Write Buffer, then
  ## Validate Buffer. NOTHING REACHES A FIFO HERE. A write that committed on
  ## its own would make the validate a no-op, and the interlock the authority
  ## puts on the validate would then guard nothing.
  m.stage = @[]
  m.stageFifo = index
  m.pending = int(opcode)
  m.transfer = tfBufferWrite
  m.width = lengthPrefixBytes + m.fifos[index].capacity
  m.index = 0

proc commitValidate(m: ISP1181; index: int) =
  ## Validate: the staged bytes become a packet the host can collect.
  if m.stageFifo != index:
    m.note("isp1181: a validate for " & fifoNames[index] &
           " found no buffer write staged for it; nothing is validated")
    return
  if m.stage.len < lengthPrefixBytes:
    m.note("isp1181: a validate for " & fifoNames[index] & " found " &
           $m.stage.len & " staged byte" &
           (if m.stage.len == 1: "" else: "s") &
           " and the length prefix alone is " & $lengthPrefixBytes &
           "; nothing is validated")
    m.stage = @[]
    m.stageFifo = -1
    return
  let declared = int(m.stage[0]) or (int(m.stage[1]) shl 8)
  let payload = m.stage[lengthPrefixBytes .. ^1]
  m.stage = @[]
  m.stageFifo = -1
  if declared != payload.len:
    # THE DECLARED LENGTH IS NOT TRUSTED OVER THE BYTES. A model that sent
    # `declared` bytes out of a shorter buffer would read past the packet, and
    # one that silently sent the payload would hand the host a packet of a
    # length the firmware did not ask for.
    m.note("isp1181: a validate for " & fifoNames[index] & " declared " &
           $declared & " byte" & (if declared == 1: "" else: "s") & " and " &
           $payload.len & " followed; nothing is validated")
    return
  discard m.queueIn(0, payload)

proc beginTransfer(m: ISP1181; opcode: uint8; kind: Transfer; width: int;
                   value: uint32) =
  m.pending = int(opcode)
  m.transfer = kind
  m.width = width
  m.index = 0
  m.latch = value

proc writeCommand(m: ISP1181; opcode: uint8) =
  let command = classify(opcode)
  # BOTH REFUSALS BELOW RETURN WITHOUT TOUCHING `pending`, `transfer`, `width`
  # or `index`, so a transfer already in progress survives the refusal. That
  # sequencing is this file's choice where the authority is silent, and the
  # head block names it.
  case command.class
  of ccNotImplemented:
    m.note("isp1181: command 0x" & toHex(opcode) & " (" & command.name &
           ") is not implemented; the read answers 0x00")
    return
  of ccUnspecified:
    m.note("isp1181: command 0x" & toHex(opcode) &
           " is not in the specified command set; the read answers 0x00")
    return
  of ccIllegal:
    # THE AUTHORITY PARENTHESISES THESE FOUR AND FORBIDS THEM. Two of the four
    # it documents as UNPREDICTABLE, which is not the same as harmless, so the
    # model refuses rather than accepting and doing nothing: an accepted no-op
    # would tell the firmware the command exists.
    m.note("isp1181: command 0x" & toHex(opcode) & " (" & command.name &
           ") is illegal - " & command.detail & "; nothing is done")
    return
  of ccImplemented:
    discard

  # THE DATA-FLOW FAMILIES. Their opcodes are inherited from ISP1362 Rev. 06
  # Table 109; the head block and `commands.nim` both state that the ISP1181B
  # document itself was not read.
  block dataFlow:
    let readIndex = m.outFifoOf(opcode, bufferReadControlOut,
                                bufferReadEndpointBase)
    if readIndex >= 0:
      m.beginBufferRead(opcode, readIndex)
      return

    let clearIndex = m.outFifoOf(opcode, clearControlOut, clearEndpointBase)
    if clearIndex >= 0:
      if clearIndex == outFifoOfEndpoint0 and m.setupUnacknowledged:
        m.noteInterlock(opcode, command.name)
        return
      discard m.fifos[clearIndex].take()
      # SETUPT GOES AWAY WITH THE PACKET AND NOT WITH THE ACKNOWLEDGE, AND
      # THAT LAST STEP IS THIS FILE'S INFERENCE. Table 127 gives bit 2 as
      # "the buffer CONTAINS a set-up packet" - a statement about content -
      # and gives no clearing rule for it, where bit 3 OVERWRITE in the same
      # table is spelled out as cleared by "a read back of this register".
      # The authority knows how to write a read-to-clear bit and did not write
      # one here, so the read leaves it and the clear that empties the buffer
      # takes it. `docs/sources.md` records this as an inference from the
      # wording rather than as a sentence in the document.
      if clearIndex == outFifoOfEndpoint0:
        m.setupHeld = false
      m.beginTransfer(opcode, tfNone, 0, 0)
      return

    if opcode == bufferWriteControlIn:
      m.beginBufferWrite(opcode, inFifoOfEndpoint0)
      return
    if opcode == validateControlIn:
      if m.setupUnacknowledged:
        m.noteInterlock(opcode, command.name)
        return
      m.commitValidate(inFifoOfEndpoint0)
      m.beginTransfer(opcode, tfNone, 0, 0)
      return

    # THE IN HALF FOR ENDPOINTS 1 TO 3 NEVER REACHES HERE. `commands.nim`
    # classifies it `ccNotImplemented`, because this model carries no IN buffer
    # on those endpoints, and the class arm above has already refused it.

  block stallFamily:
    for (base, want) in [(stallControlOut, true), (unstallControlOut, false)]:
      if opcode >= base and int(opcode) < int(base) + 0x10:
        let offset = int(opcode) - int(base)
        let index = (if offset <= 1: offset else: outFifoOfEndpoint[offset - 1])
        m.stalled[index] = want
        m.beginTransfer(opcode, tfNone, 0, 0)
        return

  block statusFamily:
    if opcode >= statusControlOut and int(opcode) < int(statusControlOut) + 0x10:
      let offset = int(opcode) - int(statusControlOut)
      let index = (if offset <= 1: offset else: outFifoOfEndpoint[offset - 1])
      # THE STATUS READ IS THE ROUTE THE BIT LEAVES THE INTERRUPT REGISTER BY,
      # and it is taken at the COMMAND and not at the data-port read: ISP1362
      # Rev. 06 p.53 separates the clearing form from a non-clearing one by the
      # OPCODE, so it is the opcode that decides and not whether the byte was
      # collected. The module head states what the route is inherited from.
      m.clearInterrupt(1'u32 shl interruptBitOfFifo[index])
      m.beginTransfer(opcode, tfRead, 1, uint32(m.statusByte(index)))
      return

  if opcode >= epConfigBase and
      int(opcode) - int(epConfigBase) < m.endpointConfig.len:
    # THE SLOT INDEX IS THE BUFFER INDEX. `endpointConfig` states where that
    # comes from; accepting exactly the slots this model carries a byte for is
    # what keeps the two in step, and `classify` refuses the rest by name.
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
    # `m.selected` IS SET ONLY BY AN ENDPOINT-CONFIGURATION COMMAND, so this
    # couples the peek target to configuration. That coupling is this file's
    # choice where the authority is silent, and the head block names it. The
    # value is a BUFFER index and is used as one: it is the slot the
    # configuration command carried, and section 15.1.1's slot ordering is
    # `fifos`' own.
    let index = m.selected
    let head = m.fifos[index].peek()
    if head.ok:
      m.beginTransfer(opcode, tfRead, 1, uint32(head.value))
    else:
      m.absentNote = "isp1181: peek on " & fifoNames[index] &
        " found no packet; the read answers 0x00"
      m.beginTransfer(opcode, tfAbsent, 1, 0)
  else:
    # `0xF4` acknowledge set up. ISP1362 Rev. 06 section 15.2.7 and section
    # 12.3.6 give the effect: it RE-ENABLES the Validate Buffer and Clear
    # Buffer commands that the arrival of a set-up packet disabled on both
    # control endpoints. It does NOT take SETUPT away - section 12.3.6 says
    # the set-up packet "stays in the buffer" until acknowledged, and what
    # removes it from the buffer is the clear that the acknowledge just
    # re-enabled.
    m.setupUnacknowledged = false
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
  if m.transfer == tfBufferWrite:
    if m.stage.len >= m.width:
      let command = classify(uint8(m.pending))
      m.note("isp1181: command 0x" & toHex(uint8(m.pending)) & " (" &
             command.name & ") takes at most " & $m.width &
             " bytes and a further one was written; the byte is discarded")
      return
    m.stage.add(value)
    return
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
  if m.transfer notin {tfRead, tfAbsent, tfBufferRead}:
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
  if m.transfer == tfBufferRead:
    result = m.readBuf[m.index]
    inc m.index
    return
  result = uint8((m.latch shr (8 * m.index)) and 0xFF'u32)
  inc m.index

proc portWrite*(m: ISP1181; address: uint32; value: uint8) =
  ## A nil handle is answered rather than aborted: the caller is a plugin's
  ## host and an abort destroys a session that has nothing to do with this
  ## model.
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
    # THE COMMAND PORT ANSWERS BENIGNLY AND SILENTLY. It is write-only - the
    # firmware issues commands there and reads operands at the data port - and
    # a model that echoed the last command byte would be presenting a register
    # the chip does not have.
    return benignValue
  m.readData()
