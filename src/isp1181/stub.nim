## The CS3 stub standing in for the Philips ISP1181 USB device controller.
##
## The benign value is `0x00`. On this device the byte the firmware reads most
## often is the interrupt register, whose zero means no interrupt is pending,
## and that is the answer a model which never raises IRQ3 owes.
##
## THE ADDRESS IS NOT DECODED HERE. The board owns the CS3 decode and answers
## for the whole window, so this model has no address it may refuse and no bus
## status of its own.

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
  ## each, wrapping at `usbFrameCount`. One call of N frames leaves the counter
  ## exactly where N calls of one would, which is what a state restore and a
  ## fast-forward both need.
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

proc isp1181_setup*(ctx: ISP1181Ctx; data: ptr uint8;
                    length: csize_t): cint
    {.exportc: "isp1181_setup", cdecl, dynlib.} =
  ## A SET-UP packet from the host. `include/mcf5307.h` states the contract;
  ## 1 means the control OUT buffer took it.
  ##
  ## A nil pointer or a zero length delivers nothing at all, for the reason
  ## `isp1181_rx` gives: a caller with no buffer is not a caller offering an
  ## empty packet, and a zero-byte packet occupies a slot.
  ##
  ## The stub answers zero and changes nothing: it is a device present in the
  ## CS3 window with nothing to say.
  if ctx.isNil:
    return 0
  case ctx.backend
  of Stub: 0
  of FullModel:
    if data.isNil or length == 0:
      0
    elif deliverSetup(ctx.model,
        toOpenArray(cast[ptr UncheckedArray[uint8]](data), 0,
                    int(length) - 1)):
      1
    else:
      0

proc isp1181_in_token*(ctx: ISP1181Ctx; endpoint: cint): cint
    {.exportc: "isp1181_in_token", cdecl, dynlib.} =
  ## The host asking the device for a packet. `include/mcf5307.h` states the
  ## contract; 1 means the transmit callback was called before this returned.
  ##
  ## The stub answers zero and calls nothing: it is a device present in the CS3
  ## window with nothing to say. A stub that reached the model here would call a
  ## host callback on a handle the caller never moved.
  if ctx.isNil:
    return 0
  case ctx.backend
  of Stub: 0
  of FullModel: (if transmit(ctx.model, int(endpoint)): 1 else: 0)

const
  backendStubValue = 0'i32
    ## `MCF5307_ISP1181_BACKEND_STUB` in `include/mcf5307.h`.
  backendFullModelValue = 1'i32
    ## `MCF5307_ISP1181_BACKEND_FULL_MODEL` in `include/mcf5307.h`.

# The two numbers above are the contract's and not the enum's. The `case` below
# names each backend explicitly rather than converting the argument to
# `ISP1181Backend`, so reordering the enum moves the state block's encoding and
# leaves every existing C caller pointing where it pointed.

proc isp1181_set_backend*(ctx: ISP1181Ctx; backend: cint): cint
    {.exportc: "isp1181_set_backend", cdecl, dynlib.} =
  ## Selects the implementation standing behind `isp1181_read`,
  ## `isp1181_write` and `isp1181_rx`. Returns 1 when the handle moved and 0
  ## when the call was refused.
  ##
  ## A fresh handle still selects the stub: it answers every read with the
  ## benign value, keeps nothing a write leaves, raises no interrupt and calls
  ## no host callback. A caller that wants the core without a USB device
  ## depends on all four, and changing the default would give it a device that
  ## answers from a register file and can call back - silently, on a rebuild,
  ## with no edit of its own.
  ##
  ## A value the contract does not name is refused and moves nothing. Falling
  ## through to either backend would repoint the handle on a caller's typo and
  ## report a success it did not get.
  if ctx.isNil:
    return 0
  case backend
  of backendStubValue:
    ctx.setBackend(Stub)
    1
  of backendFullModelValue:
    ctx.setBackend(FullModel)
    1
  else:
    0
