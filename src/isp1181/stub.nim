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

import std/envvars
import std/syncio

import ./isp1181
import ./report
# The one-time runtime latch. `isp1181_create` reads it for the reason
# `mcf5307/cpu.nim` gives at its own `create`.
import mcf5307/latch
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
  ## IT REFUSES WHEN THE RUNTIME WAS ABANDONED. See `mcf5307_create` in
  ## `mcf5307/cpu.nim`: the two allocate, the allocator needs the runtime, and
  ## a nil handle is a value every `isp1181_*` call already answers for.
  if runtimeAbandoned(runtimeLatch):
    return nil
  new(result)
  result.backend = Stub
  result.frameNumber = 0'u16
  result.model = newISP1181(user, irq, tx)

const reportEnvVar* = "MCF5307_ISP1181_REPORT"
  ## The variable that names a file to append the teardown report to.
  ##
  ## WHY A VARIABLE AND NOT A CALL. The consumer whose account matters is
  ## gearmulator's `g2Lib`, which links this library and never asked for a
  ## report. Getting the model's account out of it used to mean editing that
  ## repository - a patch applied and reverted by hand on every run, in a
  ## checkout other authors are editing at the same time. A variable is the one
  ## trigger that needs no edit at all: an EXISTING binary emits the account.
  ##
  ## UNSET OR EMPTY MEANS NOTHING HAPPENS. Not an empty file, not a default
  ## path, not a line on stderr. `tests/t_isp1181_stub.nim` holds that as a
  ## registered case, because a trigger that changed behaviour when it was not
  ## asked for would be a worse defect than the friction it removes.
  ##
  ## IT APPENDS. One process may create and destroy several handles, and a
  ## truncating open would leave only the last account - which is exactly the
  ## silent loss this whole door exists to prevent. `isp1181/report` fences
  ## each report so a reader can tell them apart and can see one that stopped
  ## early.

proc writeTeardownReport(m: ISP1181) =
  ## Append the model's account to the file `reportEnvVar` names, or say on
  ## stderr why it could not.
  ##
  ## THE FAILURE IS LOUD. A dump that silently did nothing when the path was
  ## unwritable would be indistinguishable from a run that had nothing to say,
  ## and this hook exists precisely because an unreadable account and an empty
  ## one had looked alike.
  ##
  ## NOTHING HERE MAY ESCAPE INTO C. `isp1181_destroy` is `cdecl` and its
  ## caller has no handler, so every raise is caught and reported here.
  let destination = getEnv(reportEnvVar)
  if destination.len == 0:
    return
  var handle: File
  if not open(handle, destination, fmAppend):
    stderr.write("isp1181: " & reportEnvVar & " names \"" & destination &
                 "\" and it could not be opened for append; no report was " &
                 "written\n")
    return
  try:
    handle.write(reportText(m))
  except CatchableError as err:
    stderr.write("isp1181: the report could not be written to \"" &
                 destination & "\": " & err.msg & "\n")
  finally:
    handle.close()

proc isp1181_destroy*(ctx: ISP1181Ctx)
    {.exportc: "isp1181_destroy", cdecl, dynlib.} =
  ## Release the SELECTED backend. Under `--mm:arc` the handle itself is
  ## reclaimed when the owning reference is dropped, so the stub has nothing to
  ## release and the full model has its object.
  ##
  ## THE TEARDOWN REPORT IS WRITTEN FIRST AND IT IS NOT GATED ON THE BACKEND,
  ## for the reason the log door below gives in full: the account is what the
  ## model SAID, and a handle moved back to the stub still holds it.
  if ctx.isNil:
    return
  if not ctx.model.isNil:
    writeTeardownReport(ctx.model)
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
                 length: csize_t): cint
    {.exportc: "isp1181_rx", cdecl, dynlib.} =
  ## A NIL POINTER OR A ZERO LENGTH DELIVERS NOTHING AT ALL AND IS NOT AN EMPTY
  ## PACKET. The buffers accept a zero-byte packet and it OCCUPIES A SLOT, so
  ## reading a caller with no buffer as a caller offering an empty packet would
  ## fill a single-buffered endpoint and NAK the next real packet.
  ##
  ## THE ANSWER IS THE POINT. `deliver` refuses a packet for four separate
  ## reasons and says which one in the log, and this entry point used to
  ## discard that answer - so a caller handing bytes to a device that took none
  ## of them saw exactly what a caller handing bytes to a device that took all
  ## of them saw. `include/mcf5307.h` states the contract; 1 means an OUT
  ## buffer holds the packet.
  if ctx.isNil:
    return 0
  case ctx.backend
  of Stub: 0
  of FullModel:
    if data.isNil or length == 0:
      0
    elif deliver(ctx.model, int(endpoint),
        toOpenArray(cast[ptr UncheckedArray[uint8]](data), 0,
                    int(length) - 1)):
      1
    else:
      0

proc isp1181_setup*(ctx: ISP1181Ctx; data: ptr uint8;
                    length: csize_t): cint
    {.exportc: "isp1181_setup", cdecl, dynlib.} =
  ## A SET-UP packet from the host. `include/mcf5307.h` states the contract;
  ## 1 means the control OUT buffer took it.
  ##
  ## A NIL POINTER OR A ZERO LENGTH DELIVERS NOTHING AT ALL, for the reason
  ## `isp1181_rx` gives: a caller with no buffer is not a caller offering an
  ## empty packet, and a zero-byte packet OCCUPIES A SLOT.
  ##
  ## THE STUB ANSWERS ZERO AND CHANGES NOTHING, which is the whole of what the
  ## stub is: a device present in the CS3 window with nothing to say.
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
  ## THE STUB ANSWERS ZERO AND CALLS NOTHING, which is the whole of what the
  ## stub is: a device present in the CS3 window with nothing to say. A stub
  ## that reached the model here would call a host callback on a handle the
  ## caller never moved.
  if ctx.isNil:
    return 0
  case ctx.backend
  of Stub: 0
  of FullModel: (if transmit(ctx.model, int(endpoint)): 1 else: 0)

# ---------------------------------------------------------------------------
# The model's own account of what it did, and the door a C caller reads it
# through.
#
# THE ACCOUNT IS NOT GATED ON THE BACKEND, and every other entry point in this
# file is. The log is what the model SAID, not a register the device answers
# from: a handle that spent a run on the full model and was moved back to the
# stub still holds that account, and casing on the current backend would hide
# exactly the record this door exists to carry. The stub writes no line of its
# own, so a handle that never left the stub reads zero here without help.
#
# `written` AND `retained` ARE TWO CALLS AND NOT ONE. Their difference is the
# number of lines the reader cannot see. A single "count" would be whichever of
# the two the implementation happened to return, and a reader could not tell a
# complete account from a truncated one - which is the failure this whole door
# was added to close.

proc isp1181_log_written*(ctx: ISP1181Ctx): csize_t
    {.exportc: "isp1181_log_written", cdecl, dynlib.} =
  if ctx.isNil or ctx.model.isNil:
    return 0
  csize_t(logWritten(ctx.model))

proc isp1181_log_retained*(ctx: ISP1181Ctx): csize_t
    {.exportc: "isp1181_log_retained", cdecl, dynlib.} =
  if ctx.isNil or ctx.model.isNil:
    return 0
  csize_t(logRetained(ctx.model))

proc isp1181_log_line*(ctx: ISP1181Ctx; index: csize_t; dst: ptr cchar;
                       capacity: csize_t): csize_t
    {.exportc: "isp1181_log_line", cdecl, dynlib.} =
  ## THE RETURN IS THE SIZE THE LINE NEEDS AND NOT THE SIZE THAT WAS COPIED.
  ## `include/mcf5307.h` states the contract: a return greater than `capacity`
  ## is a line the caller's buffer could not hold, which is the second way this
  ## door could have lied by omission, and 0 is no such retained line.
  if ctx.isNil or ctx.model.isNil:
    return 0
  let line = logLine(ctx.model, int(index))
  if line.len == 0:
    return 0
  if not dst.isNil and capacity > 0:
    let room = min(line.len, int(capacity) - 1)
    if room > 0:
      copyMem(dst, unsafeAddr line[0], room)
    cast[ptr UncheckedArray[cchar]](dst)[room] = cchar(0)
  csize_t(line.len + 1)

proc isp1181_config_slots*(): csize_t
    {.exportc: "isp1181_config_slots", cdecl, dynlib.} =
  ## How many DcEndpointConfiguration slots `isp1181_config_slot` accepts.
  ##
  ## IT IS A FUNCTION AND NOT A MACRO IN THE HEADER. A macro is a second copy
  ## of the number that no build step compares against this one, and it would
  ## go stale in silence on the day the model's slot count moved.
  csize_t(configSlotCount)

proc isp1181_config_slot*(ctx: ISP1181Ctx; slot: csize_t;
                          value: ptr uint8): cint
    {.exportc: "isp1181_config_slot", cdecl, dynlib.} =
  ## THREE ANSWERS AND NOT TWO. `include/mcf5307.h` states the contract:
  ## 1 is a slot the firmware wrote, 0 is a slot it never wrote, and -1 is no
  ## such slot or no handle. A slot never written and a slot written with
  ## `0x00` hold the same byte, so a call that returned only the byte would
  ## answer both with `0x00` and a reader could not tell a configuration the
  ## firmware chose from one it never sent.
  ##
  ## `value` IS WRITTEN IF AND ONLY IF THIS RETURNS 1. On the other two answers
  ## there is no configuration byte to report, and storing the reset value
  ## there would hand a caller who skipped the return a plausible byte the
  ## firmware never wrote.
  if ctx.isNil or ctx.model.isNil:
    return -1
  if slot >= csize_t(configSlotCount):
    return -1
  if not configSlotWritten(ctx.model, int(slot)):
    return 0
  if not value.isNil:
    value[] = configSlotValue(ctx.model, int(slot))
  1

proc isp1181_slot_buffer*(ctx: ISP1181Ctx; slot: csize_t;
                          max_packet_bytes: ptr csize_t;
                          buffer_count: ptr csize_t): cint
    {.exportc: "isp1181_slot_buffer", cdecl, dynlib.} =
  ## THE ENDPOINT'S BUFFER GEOMETRY, SO THAT A PRODUCER CAN ASK INSTEAD OF
  ## ASSUMING. `include/mcf5307.h` states the contract and the reason at
  ## length. In short: gearmulator's board held its own `64` because there was
  ## no call to make, and a differently configured endpoint would have broken
  ## it silently in the direction that resurrects the size refusals.
  ##
  ## THREE ANSWERS, `isp1181_config_slot`'s CONVENTION AND NOT A SECOND ONE:
  ## 1 is a slot this model buffers, 0 is a slot it does not, and -1 is no such
  ## slot or no handle.
  ##
  ## IT DOES NOT ANSWER "WAS THE SLOT WRITTEN" AND THAT IS DELIBERATE.
  ## `isp1181_config_slot` already answers it, and a second symbol answering it
  ## too would be a second copy of one fact that nothing holds together - which
  ## is the exact defect the duplicated `64` was. The third state the report
  ## distinguishes is reached by asking both calls, and the header says so.
  ##
  ## BOTH OUT-PARAMETERS ARE WRITTEN IF AND ONLY IF THIS RETURNS 1, for the
  ## reason `isp1181_config_slot` leaves `value` alone: a stored figure on an
  ## answer of 0 is a size a caller who skipped the return would split packets
  ## to, and there is no buffer behind it to make that size true. Either
  ## pointer may be nil and the return is still the answer.
  if ctx.isNil or ctx.model.isNil:
    return -1
  if slot >= csize_t(configSlotCount):
    return -1
  if not slotHasBuffer(int(slot)):
    return 0
  let shape = slotBufferGeometry(int(slot))
  if not max_packet_bytes.isNil:
    max_packet_bytes[] = csize_t(shape.maxPacketBytes)
  if not buffer_count.isNil:
    buffer_count[] = csize_t(shape.buffers)
  1

proc isp1181_report*(ctx: ISP1181Ctx; dst: ptr cchar;
                     capacity: csize_t): csize_t
    {.exportc: "isp1181_report", cdecl, dynlib.} =
  ## The whole account as one NUL-terminated block of text: the counters, the
  ## truncation verdict in words, every configuration slot, and every retained
  ## line with its place in the sequence.
  ##
  ## THE RETURN IS THE SIZE THE TEXT NEEDS AND NOT THE SIZE THAT WAS COPIED,
  ## which is `isp1181_log_line`'s convention and is here for its reason: a
  ## return greater than `capacity` is a report the caller's buffer could not
  ## hold, and a caller that reads the buffer without comparing has an account
  ## that ends early and looks whole.
  ##
  ## A NIL HANDLE ANSWERS 0 AND WRITES NOTHING, which is the one case with no
  ## model to report on.
  if ctx.isNil or ctx.model.isNil:
    return 0
  let text = reportText(ctx.model)
  if not dst.isNil and capacity > 0:
    let room = min(text.len, int(capacity) - 1)
    if room > 0:
      copyMem(dst, unsafeAddr text[0], room)
    cast[ptr UncheckedArray[cchar]](dst)[room] = cchar(0)
  csize_t(text.len + 1)

const
  backendStubValue = 0'i32
    ## `MCF5307_ISP1181_BACKEND_STUB` in `include/mcf5307.h`.
  backendFullModelValue = 1'i32
    ## `MCF5307_ISP1181_BACKEND_FULL_MODEL` in `include/mcf5307.h`.

# THE TWO NUMBERS ABOVE ARE THE CONTRACT'S AND NOT THE ENUM'S. The `case` below
# names each backend explicitly rather than converting the argument to
# `ISP1181Backend`, so reordering the enum moves the state block's encoding and
# leaves every existing C caller pointing where it pointed.

proc isp1181_set_backend*(ctx: ISP1181Ctx; backend: cint): cint
    {.exportc: "isp1181_set_backend", cdecl, dynlib.} =
  ## Selects the implementation standing behind `isp1181_read`,
  ## `isp1181_write` and `isp1181_rx`. Returns 1 when the handle moved and 0
  ## when the call was refused.
  ##
  ## A FRESH HANDLE STILL SELECTS THE STUB, AND THAT IS THE POINT OF ADDING A
  ## SETTER RATHER THAN MOVING THE DEFAULT. The stub is a device that is
  ## present in the CS3 window and inert: it answers every read with the benign
  ## value, keeps nothing a write leaves, raises no interrupt and calls no host
  ## callback. A caller that wants the core without a USB device depends on all
  ## four, and changing the default would give it a device that answers from a
  ## register file and can call back - silently, on a rebuild, with no edit of
  ## its own.
  ##
  ## A VALUE THE CONTRACT DOES NOT NAME IS REFUSED AND MOVES NOTHING. Falling
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
