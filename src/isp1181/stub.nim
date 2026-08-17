## The CS3 stub standing in for the Philips ISP1181 USB device controller.
## Task CPU-21. Design section 9.1.
##
## It accepts every write, returns a benign value on every read, and never
## raises IRQ3. Design section 9.1 gives six independent lines of evidence that
## nothing on the boot path reads back anything this model would have to
## answer, and this file implements exactly that and nothing beside it.
##
## THIS FILE CARRIES THE FIVE C ENTRY POINTS OF THE DEVICE MODEL, and the full
## model is installed behind them rather than beside them. The entry points
## have to exist before either implementation can be chosen, so they live with
## the implementation that exists first.
##
## THE HOST'S THREE ARGUMENTS ARE HELD BY THE FULL MODEL AND BY NO STUB PATH.
## They used to be discarded here, which made the stub's two refusals -
## it raises no interrupt and it invents no packet - structural rather than
## maintained. THE FULL MODEL IS NOW A SELECTABLE BACKEND AND IT IS BUILT FROM
## THOSE THREE ARGUMENTS, so they are kept. The refusals are unchanged and are
## still not maintained by hand: every stub arm below calls nothing, so the
## stub path reaches neither callback whatever the model holds.
##
## THE BENIGN VALUE IS `0x00`. On this device the byte the firmware reads most
## often is the interrupt register, whose zero means no interrupt is pending,
## and that is the answer a model which never raises IRQ3 owes.
##
## THE ADDRESS IS NOT DECODED HERE. Design section 5.2.1 gives the CS3 decode
## to the board, which answers `MCF5307_BUS_OK` for the whole window, so this
## model has no address it may refuse and no bus status of its own.
##
## WHAT CPU-22 WROTE HERE, AND WHAT IT DELIBERATELY DID NOT. CPU-22 added the
## import below and moved the two host-callback types to the module it names.
## `cmake/Nim.cmake` compiles exactly ONE entry module and takes its `.c` files
## from the `compile` array of Nim's own JSON, so a module no import chain
## reaches is never compiled at all - and `src/mcf5307.nim` reaches this file
## and no other under `src/isp1181/`. The import is therefore what puts the
## full model in the library, and moving the two types makes it a dependency
## the compiler enforces rather than a line a later edit could drop in silence.
##
## WHICH IMPLEMENTATION ANSWERS IS A RUN-TIME SELECTION AND NEVER A BUILD FLAG,
## so a developer can switch back to the stub to isolate a fault and the
## milestone path is never blocked by USB work. Plan item W3-51 decided the
## shape on 2026-08-17: a field on this context, defaulting to the stub. The
## enum is NIM-SIDE ONLY AND MUST NEVER APPEAR IN `include/mcf5307.h` - the
## moment it does it is a growth of the published contract, and the three-file
## cost W3-51 measured for the shapes it refused applies again in full. C holds
## a pointer to `isp1181_ctx` and never sees a field, which is the whole reason
## this shape was available.
##
## NO C-REACHABLE SELECTOR EXISTS AND ITS ABSENCE IS DELIBERATE. The only
## caller that would need one is the host-visible USB component plan item W3-88
## records as unplanned, and a contract grown before its only consumer exists
## is the trade W3-51 refused.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import ./isp1181
export Isp1181IrqFn, Isp1181TxFn

type
  ISP1181Backend* = enum
    ## Which implementation stands behind the five C entry points. There are
    ## exactly these two and a third must not be added without amending plan
    ## item W3-51, which names them.
    Stub, FullModel

  ISP1181Ctx* = ref object
    ## Opaque to every caller: C sees `isp1181_ctx` and never its layout, so a
    ## field here is not a growth of the published contract.
    ##
    ## THE FIELDS ARE PRIVATE AND THE SETTERS BELOW ARE THE ONLY WRITERS. That
    ## is W3-51's "the only writer after construction is a Nim-side setter"
    ## expressed as a rule the compiler applies rather than one a reader keeps.
    backend: ISP1181Backend
    frameNumber: uint16
      ## THE USB FRAME NUMBER, 11 BITS, WRAPPING AT 2048.
      ##
      ## THE WIDTH COMES FROM THE USB SPECIFICATION'S FRAME-NUMBER FIELD AND
      ## NOT FROM ANY ISP1181 DATASHEET. NO ISP1181 DATASHEET EXISTS ON THIS
      ## MACHINE, so this is not a measured device fact and a later reader must
      ## not cite it as one. If the device turns out to expose a frame number
      ## of a different width at its register interface, that is a divergence
      ## to record against the device and not a correction to the USB frame
      ## number itself.
      ##
      ## THE STORED TYPE IS WIDER THAN THE FIELD IT MODELS, so the width is
      ## carried by `advanceFrames` below and by nothing else. A comment is not
      ## a width.
      ##
      ## THERE IS NO SOFTCT FIELD HERE AND ONE MUST NOT BE ADDED ON THE
      ## STRENGTH OF THE WORD "TIMER" APPEARING IN THIS PROJECT'S HISTORY.
      ## SOFTCT IS A BIT, it lives in the full model's mode byte as
      ## `softctBit`, and plan item W3-139 carries the ruling and the one
      ## question it leaves open.
    model: ISP1181
      ## The full model, built at construction because it is built from the
      ## three host arguments and nothing later supplies them again. It is
      ## reached only through the `FullModel` arms below.

const usbFrameCount = 2048
  ## The modulus of the frame number above. It is READ BY `advanceFrames` and
  ## is therefore a mechanism rather than a note: a change to it moves the
  ## behaviour, and `tests/t_isp1181_stub.nim` pins the behaviour against its
  ## own hand-written literal.

proc backend*(ctx: ISP1181Ctx): ISP1181Backend =
  ## A nil handle reports the default rather than aborting, for design section
  ## 5.6's reason: the caller is a plugin's host.
  if ctx.isNil: Stub else: ctx.backend

proc setBackend*(ctx: ISP1181Ctx; value: ISP1181Backend) =
  ## THE ONE WRITER OF THE SELECTOR AFTER CONSTRUCTION, reachable from Nim and
  ## not from C.
  if ctx.isNil:
    return
  ctx.backend = value

proc frameNumber*(ctx: ISP1181Ctx): uint16 =
  if ctx.isNil: 0'u16 else: ctx.frameNumber

proc advanceFrames*(ctx: ISP1181Ctx; frames: int) =
  ## Advance the USB frame number by `frames` Start-of-Frame frames of 1 ms
  ## each, wrapping at `usbFrameCount`. THE COUNT FORM IS THE ONLY FORM: one
  ## call of N frames leaves the counter exactly where N calls of one would,
  ## which is what a state restore and a fast-forward both need.
  ##
  ## THIS MODEL NEVER READS A WALL CLOCK. The frames are the caller's.
  ##
  ## CPU-24's `isp1181_tick` is the C entry point that calls this. The wrap
  ## lives here, with the field whose width it enforces, rather than there.
  if ctx.isNil or frames <= 0:
    return
  ctx.frameNumber = uint16((int(ctx.frameNumber) + frames) mod usbFrameCount)

proc isp1181_create*(user: pointer; irq: Isp1181IrqFn;
                     tx: Isp1181TxFn): ISP1181Ctx
    {.exportc: "isp1181_create", cdecl, dynlib.} =
  ## Allocate the handle and select the stub. THE DEFAULT IS `Stub` AND
  ## REVERSING IT WOULD REMOVE THE WORKING THING BEFORE THE REPLACEMENT WORKS:
  ## the firmware boot path exercises the stub and the milestone is checked
  ## against it. The constructor takes no mode parameter, so C is told nothing
  ## and `include/mcf5307.h` keeps its three declared arguments.
  new(result)
  result.backend = Stub
  result.frameNumber = 0'u16
  result.model = newISP1181(user, irq, tx)

proc isp1181_destroy*(ctx: ISP1181Ctx)
    {.exportc: "isp1181_destroy", cdecl, dynlib.} =
  ## Release the SELECTED backend. Under `--mm:arc` the handle itself is
  ## reclaimed when the owning reference is dropped, so the stub has nothing to
  ## release and the full model has its object.
  if ctx.isNil:
    return
  case ctx.backend
  of Stub:
    discard
  of FullModel:
    ctx.model = nil

proc isp1181_read*(ctx: ISP1181Ctx; address: uint32): uint8
    {.exportc: "isp1181_read", cdecl, dynlib.} =
  ## The stub answers the benign value at every address and in every device
  ## state; the full model decodes the port split and answers from its
  ## registers.
  if ctx.isNil:
    return 0x00'u8
  case ctx.backend
  of Stub: 0x00'u8
  of FullModel: portRead(ctx.model, address)

proc isp1181_write*(ctx: ISP1181Ctx; address: uint32; value: uint8)
    {.exportc: "isp1181_write", cdecl, dynlib.} =
  ## The stub accepts the write and keeps nothing - a stub that stored the byte
  ## would read it back, and a register file that answers is not a benign
  ## value. The full model routes it to the command or the data port.
  if ctx.isNil:
    return
  case ctx.backend
  of Stub:
    discard
  of FullModel:
    portWrite(ctx.model, address, value)

proc isp1181_rx*(ctx: ISP1181Ctx; endpoint: cint; data: ptr uint8;
                 length: csize_t)
    {.exportc: "isp1181_rx", cdecl, dynlib.} =
  ## The stub accepts host traffic and keeps nothing. The full model delivers
  ## it to the endpoint's buffer, which may NAK it.
  ##
  ## A NIL POINTER OR A ZERO LENGTH DELIVERS NOTHING AT ALL AND IS NOT AN EMPTY
  ## PACKET. The buffers accept a zero-byte packet and it OCCUPIES A SLOT, so
  ## reading a caller with no buffer as a caller offering an empty packet would
  ## fill a single-buffered endpoint and NAK the next real packet. Whether the
  ## device should carry a genuine zero-length packet is a question for the
  ## model's own task; this arm answers only for the caller that brought none.
  if ctx.isNil:
    return
  case ctx.backend
  of Stub:
    discard
  of FullModel:
    if data.isNil or length == 0:
      return
    discard deliver(ctx.model, int(endpoint),
        toOpenArray(cast[ptr UncheckedArray[uint8]](data), 0, int(length) - 1))
