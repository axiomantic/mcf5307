## The CS3 stub standing in for the Philips ISP1181 USB device controller.
##
## It accepts every write, returns a benign value on every read, and never
## raises IRQ3.
##
## This file carries the five C entry points of the device model, and the full
## model is installed behind them rather than beside them.
##
## The stub's two refusals - it raises no interrupt and it invents no packet -
## are structural rather than maintained: every stub arm below calls nothing, so
## the stub path reaches neither host callback whatever the model holds.
##
## The benign value is `0x00`. On this device the byte the firmware reads most
## often is the interrupt register, whose zero means no interrupt is pending,
## and that is the answer a model which never raises IRQ3 owes.
##
## The address is not decoded here. The board owns the CS3 decode and answers
## `MCF5307_BUS_OK` for the whole window, so this model has no address it may
## refuse and no bus status of its own.
##
## The import below is load-bearing. `cmake/Nim.cmake` compiles exactly one
## entry module and takes its `.c` files from the `compile` array of Nim's own
## JSON, so a module no import chain reaches is never compiled at all - and
## `src/mcf5307.nim` reaches this file and no other under `src/isp1181/`. The
## import is what puts the full model in the library, and the two host-callback
## types living in the imported module make it a dependency the compiler
## enforces rather than a line a later edit could drop in silence.
##
## Which implementation answers is a run-time selection and never a build flag,
## so a developer can switch back to the stub to isolate a fault. The enum is
## Nim-side only and must never appear in `include/mcf5307.h`: the moment it does
## it is a growth of the published contract. C holds a pointer to `isp1181_ctx`
## and never sees a field.
##
## No C-reachable selector exists and its absence is deliberate: no consumer of
## one exists yet.

import ./isp1181
export Isp1181IrqFn, Isp1181TxFn

type
  ISP1181Backend* = enum
    ## Which implementation stands behind the five C entry points.
    Stub, FullModel

  ISP1181Ctx* = ref object
    ## Opaque to every caller: C sees `isp1181_ctx` and never its layout, so a
    ## field here is not a growth of the published contract.
    ##
    ## The fields are private and the setters below are the only writers.
    backend: ISP1181Backend
    frameNumber: uint16
      ## The USB frame number, 11 bits, wrapping at 2048.
      ##
      ## The width comes from the USB specification's frame-number field and not
      ## from any ISP1181 datasheet - no ISP1181 datasheet exists on this machine
      ## - so this is not a measured device fact and a later reader must not cite
      ## it as one. If the device turns out to expose a frame number of a
      ## different width at its register interface, that is a divergence to
      ## record against the device and not a correction to the USB frame number.
      ##
      ## The stored type is wider than the field it models, so the width is
      ## carried by `advanceFrames` below and by nothing else.
      ##
      ## SOFTCT is a bit, and it lives in the full model's mode byte as
      ## `softctBit`. There is no SOFTCT field here.
    model: ISP1181
      ## The full model, built at construction because it is built from the
      ## three host arguments and nothing later supplies them again. It is
      ## reached only through the `FullModel` arms below.

const usbFrameCount = 2048
  ## The modulus of the frame number above.

proc backend*(ctx: ISP1181Ctx): ISP1181Backend =
  ## A nil handle reports the default rather than aborting: the caller is a
  ## plugin's host.
  if ctx.isNil: Stub else: ctx.backend

proc setBackend*(ctx: ISP1181Ctx; value: ISP1181Backend) =
  ## The one writer of the selector after construction, reachable from Nim and
  ## not from C.
  if ctx.isNil:
    return
  ctx.backend = value

proc frameNumber*(ctx: ISP1181Ctx): uint16 =
  if ctx.isNil: 0'u16 else: ctx.frameNumber

proc advanceFrames*(ctx: ISP1181Ctx; frames: int) =
  ## Advance the USB frame number by `frames` Start-of-Frame frames of 1 ms
  ## each, wrapping at `usbFrameCount`. One call of N frames leaves the counter
  ## exactly where N calls of one would, which is what a state restore and a
  ## fast-forward both need.
  ##
  ## This model never reads a wall clock. The frames are the caller's.
  ##
  ## The wrap lives here, with the field whose width it enforces, rather than in
  ## the `isp1181_tick` entry point that calls this.
  if ctx.isNil or frames <= 0:
    return
  ctx.frameNumber = uint16((int(ctx.frameNumber) + frames) mod usbFrameCount)

proc isp1181_create*(user: pointer; irq: Isp1181IrqFn;
                     tx: Isp1181TxFn): ISP1181Ctx
    {.exportc: "isp1181_create", cdecl, dynlib.} =
  ## Allocate the handle and select the stub. The firmware boot path is checked
  ## against the stub, so reversing the default would remove the working thing
  ## before the replacement works. The constructor takes no mode parameter, so
  ## `include/mcf5307.h` keeps its three declared arguments.
  new(result)
  result.backend = Stub
  result.frameNumber = 0'u16
  result.model = newISP1181(user, irq, tx)

proc isp1181_destroy*(ctx: ISP1181Ctx)
    {.exportc: "isp1181_destroy", cdecl, dynlib.} =
  ## Release the selected backend. Under `--mm:arc` the handle itself is
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
  ## A nil pointer or a zero length delivers nothing at all and is not an empty
  ## packet. The buffers accept a zero-byte packet and it occupies a slot, so
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
