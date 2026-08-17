## The CS3 stub standing in for the Philips ISP1181 USB device controller.
##
## THE BENIGN VALUE IS `0x00`. On this device the byte the firmware reads most
## often is the interrupt register, whose zero means no interrupt is pending,
## and that is the answer a model which never raises IRQ3 owes.
##
## THE ADDRESS IS NOT DECODED HERE. The board owns the CS3 decode and answers
## for the whole window, so this model has no address it may refuse and no bus
## status of its own.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import ./isp1181
export Isp1181IrqFn, Isp1181TxFn

type
  ISP1181Backend* = enum
    Stub, FullModel

  ISP1181Ctx* = ref object
    ## Opaque to every caller: C sees `isp1181_ctx` and never its layout, so a
    ## field here is not a growth of the published contract.
    backend: ISP1181Backend
    frameNumber: uint16
    model: ISP1181

const usbFrameCount = 2048

proc backend*(ctx: ISP1181Ctx): ISP1181Backend =
  if ctx.isNil: Stub else: ctx.backend

proc setBackend*(ctx: ISP1181Ctx; value: ISP1181Backend) =
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
  if ctx.isNil or frames <= 0:
    return
  ctx.frameNumber = uint16((int(ctx.frameNumber) + frames) mod usbFrameCount)

proc isp1181_create*(user: pointer; irq: Isp1181IrqFn;
                     tx: Isp1181TxFn): ISP1181Ctx
    {.exportc: "isp1181_create", cdecl, dynlib.} =
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
  ## A NIL POINTER OR A ZERO LENGTH DELIVERS NOTHING AT ALL AND IS NOT AN EMPTY
  ## PACKET. The buffers accept a zero-byte packet and it OCCUPIES A SLOT, so
  ## reading a caller with no buffer as a caller offering an empty packet would
  ## fill a single-buffered endpoint and NAK the next real packet.
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
