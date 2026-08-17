## `isp1181/state` - the SOF tick and the snapshot of the USB device handle, as
## a flat block of bytes. Task CPU-24. Design sections 9.4 and 5.2.
##
## THE TICK CALLS `advanceFrames` AND DOES NOT REIMPLEMENT IT. The 11-bit width
## and its modulus live in `src/isp1181/stub.nim` beside the field they bound,
## so the modulus appears once in this library. An entry point that folded the
## wrap in here would be a second copy of a device width, and two copies of a
## width diverge at the first edit that reaches only one of them.
##
## NOTHING HERE ADVANCES A SOFTCT TIMER. SOFTCT is a BIT of the full model's
## mode byte, `softctBit`, and plan item W3-139 carries the ruling. No field of
## this block is a timer and none must be added on the strength of the word
## surviving in this project's history.
##
## THE BLOCK IS THE CPU-18 SHAPE AND NOT A NEW ONE: a fixed size, no pointer, a
## magic word, a version word, the payload width, the payload, and a checksum
## whose algorithm detects any single changed byte with certainty rather than
## with high probability. Every check precedes the decode, so a refusal leaves
## the caller with the state it had rather than with a handle half restored from
## a block that was never valid.
##
## THERE IS ONE WALK AND NOT A WALK PER OPERATION, which is CPU-18's reason
## applied here: the number of bytes the size reports and the number the save
## writes cannot disagree when one procedure produces both. A field of a type
## the walk has no encoding for STOPS THE COMPILE naming the field, so a handle
## that grows a field either enters the snapshot or refuses to build.
##
## THE WALK READS PRIVATE FIELDS OF A FOREIGN MODULE AND THAT IS DELIBERATE.
## `fieldPairs` reaches them, so this file needs no accessor added to
## `src/isp1181/stub.nim` - which is CPU-21's file and outside this task's
## declared set. The cost is stated rather than hidden: CPU-21's head block says
## its own setters are the only writers of those fields after construction, and
## the load below writes them without going through one. The alternative was a
## hand-kept list of accessors, which is precisely the arrangement whose silent
## drift the compile-stopping walk exists to prevent.
##
## WHAT THIS BLOCK DOES NOT CARRY, STATED AS A DECLARED GAP RATHER THAN LEFT AS
## A SILENCE. `ISP1181Ctx` holds the full device model, and the model's own
## fields are a string, A SEQUENCE OF STRINGS, an enum and an array of FIFOs
## holding sequences of bytes. A sequence of strings has NO BOUND AT ALL - the
## model appends one line to it per refused command and per delivery, without
## limit - so NO FIXED SIZE EXISTS that carries it, and a fixed-size block can
## only hold it by dropping it. Dropping it changes what a snapshot MEANS, which
## is a decision about the contract and not about this implementation, so it is
## not taken here. The model therefore appears in the layout AT WIDTH ZERO: a
## reader of `isp1181StateLayout` sees the gap instead of inferring it from an
## absence. Plan item W3-90 carries the finding and CPU-24's report carries what
## it costs and when it starts costing it.
##
## THE C ENTRY POINT FOR THE LOAD REPORTS NO FAILURE AND THAT IS A PROPERTY OF
## THE CONTRACT, NOT A CHOICE MADE HERE. `include/mcf5307.h` declares
## `void isp1181_state_load(isp1181_ctx*, const void*)`: no result, no
## out-parameter and no status call. So `isp1181Restore` returns a NAMED status
## and the C wrapper can only refuse the block; what it refuses, it refuses
## WITHOUT TOUCHING THE HANDLE. Adding a channel means adding a declaration to
## the contract header, which belongs to another task.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import ./isp1181
import ./stub

const
  isp1181StateMagic = 0x49535031'u32
    ## `ISP1` - the first longword of the block.
  isp1181StateVersion = 1'u32
    ## The version word. It moves when the payload's layout moves, and
    ## `isp1181Restore` refuses a block that does not carry this exact value.
    ## A LATER BLOCK THAT CARRIES THE FULL MODEL IS A DIFFERENT VERSION, so a
    ## block written today is refused by that loader rather than read short.
  isp1181StateHeaderBytes = 12
    ## magic, version, payload width
  isp1181StateChecksumBytes = 4

type
  Isp1181StateStatus* = enum
    ## The result of a load. Every refusal has a name, so a caller reports WHICH
    ## part of the block it refused and not merely that it did.
    isp1181StateOk
    isp1181StateNilArgument
    isp1181StateBadMagic
    isp1181StateBadVersion
    isp1181StateBadWidth
    isp1181StateBadChecksum
    isp1181StateBadField
      ## A payload field whose bytes name no value the field's type has. The
      ## checksum cannot reach this: a block whose checksum was recomputed over
      ## the damaged payload is internally consistent and still holds a byte the
      ## type has no name for.

  Isp1181StateOp = enum
    isp1181Measure
    isp1181Inspect
    isp1181SaveOp
    isp1181LoadOp

  Isp1181CtxObj = typeof(default(ISP1181Ctx)[])

  StateBuf = ptr UncheckedArray[uint8]

proc putBe16(buf: StateBuf; at: int; value: uint16) =
  buf[at] = uint8((value shr 8) and 0xFF'u16)
  buf[at + 1] = uint8(value and 0xFF'u16)

proc getBe16(buf: StateBuf; at: int): uint16 =
  (uint16(buf[at]) shl 8) or uint16(buf[at + 1])

proc putBe32(buf: StateBuf; at: int; value: uint32) =
  buf[at] = uint8((value shr 24) and 0xFF'u32)
  buf[at + 1] = uint8((value shr 16) and 0xFF'u32)
  buf[at + 2] = uint8((value shr 8) and 0xFF'u32)
  buf[at + 3] = uint8(value and 0xFF'u32)

proc getBe32(buf: StateBuf; at: int): uint32 =
  (uint32(buf[at]) shl 24) or (uint32(buf[at + 1]) shl 16) or
    (uint32(buf[at + 2]) shl 8) or uint32(buf[at + 3])

proc isp1181StateChecksum(buf: StateBuf; upTo: int): uint32 =
  ## FNV-1a over the first `upTo` bytes, which is the algorithm and the reason
  ## `src/mcf5307/state.nim` states in full: each step is a bijection on
  ## `uint32`, so two blocks of one length that differ anywhere reach different
  ## running values at the first difference and can never rejoin. ANY single
  ## changed byte is detected, not with high probability but always.
  result = 2166136261'u32
  for index in 0 ..< upTo:
    result = (result xor uint32(buf[index])) * 16777619'u32

proc isp1181StateWalk(ctx: var Isp1181CtxObj; buf: StateBuf;
                      op: Isp1181StateOp; layout: ptr seq[(string, int)];
                      status: ptr Isp1181StateStatus): int =
  ## Walks the payload once and returns its width in bytes.
  ##
  ## `buf` is read under `isp1181Inspect` and `isp1181LoadOp`, written under
  ## `isp1181SaveOp` and never touched under `isp1181Measure`, which is what
  ## lets the width be computed against no buffer at all.
  ##
  ## `isp1181Inspect` IS THE VALIDATE-BEFORE-DECODE PASS AND IT WRITES NO FIELD.
  ## It runs over a probe, so a block carrying a byte no field's type has a name
  ## for is refused before the handle has been touched at all.
  ##
  ## `layout` IS A POINTER AND IS NIL UNDER EVERY OPERATION BUT THE DESCRIPTION
  ## READER's, so the save and the load reach no heap.
  var at = 0
  for name, value in fieldPairs(ctx):
    let started = at
    when value is ISP1181:
      # THE FULL MODEL IS NOT CARRIED. The head block states why, and the zero
      # width below is what puts the gap in the layout rather than in a silence.
      discard
    elif value is enum:
      if op == isp1181SaveOp:
        buf[at] = uint8(ord(value))
      elif op == isp1181Inspect:
        if int(buf[at]) < ord(low(typeof(value))) or
            int(buf[at]) > ord(high(typeof(value))):
          status[] = isp1181StateBadField
      elif op == isp1181LoadOp:
        value = typeof(value)(buf[at])
      at += 1
    elif value is uint16:
      if op == isp1181SaveOp:
        putBe16(buf, at, value)
      elif op == isp1181LoadOp:
        value = getBe16(buf, at)
      at += 2
    else:
      {.error: "isp1181/state: a handle field the walk cannot encode".}
    if layout != nil:
      layout[].add((name, at - started))
  at

proc isp1181PayloadWidth(): int =
  var probe: Isp1181CtxObj
  isp1181StateWalk(probe, nil, isp1181Measure, nil, nil)

const isp1181PayloadBytes = isp1181PayloadWidth()

proc isp1181StateLayout*(): seq[(string, int)] =
  ## The name and the byte width of every handle field the snapshot carries, in
  ## the order the block carries them. A field the block does NOT carry appears
  ## at width zero rather than being left out.
  var probe: Isp1181CtxObj
  discard isp1181StateWalk(probe, nil, isp1181Measure, addr result, nil)

proc isp1181_state_size*(): csize_t
    {.exportc: "isp1181_state_size", cdecl, dynlib.} =
  csize_t(isp1181StateHeaderBytes + isp1181PayloadBytes +
          isp1181StateChecksumBytes)

proc isp1181_tick*(ctx: ISP1181Ctx; sofFrames: uint32)
    {.exportc: "isp1181_tick", cdecl, dynlib.} =
  ## Advance the USB frame counter by `sofFrames` Start-of-Frame frames of 1 ms
  ## each. THE FRAMES ARE THE CALLER'S AND NO CLOCK IS READ HERE.
  advanceFrames(ctx, int(sofFrames))

proc isp1181_state_save*(ctx: ISP1181Ctx; dst: pointer)
    {.exportc: "isp1181_state_save", cdecl, dynlib.} =
  if ctx.isNil or dst.isNil:
    return
  let buf = cast[StateBuf](dst)
  putBe32(buf, 0, isp1181StateMagic)
  putBe32(buf, 4, isp1181StateVersion)
  putBe32(buf, 8, uint32(isp1181PayloadBytes))
  discard isp1181StateWalk(ctx[],
                           cast[StateBuf](addr buf[isp1181StateHeaderBytes]),
                           isp1181SaveOp, nil, nil)
  putBe32(buf, isp1181StateHeaderBytes + isp1181PayloadBytes,
          isp1181StateChecksum(buf,
                               isp1181StateHeaderBytes + isp1181PayloadBytes))

proc isp1181Restore*(ctx: ISP1181Ctx; src: pointer): Isp1181StateStatus =
  ## Restores the handle from a block `isp1181_state_save` wrote, or names the
  ## reason it will not.
  ##
  ## EVERY CHECK PRECEDES THE DECODE, AND THE ORDER IS THE POINT. The handle is
  ## written only after the block has been accepted whole, so a refusal leaves
  ## the caller with the state it had rather than with a handle half restored
  ## from a block that was never valid.
  if ctx.isNil or src.isNil:
    return isp1181StateNilArgument
  let buf = cast[StateBuf](src)
  if getBe32(buf, 0) != isp1181StateMagic:
    return isp1181StateBadMagic
  if getBe32(buf, 4) != isp1181StateVersion:
    return isp1181StateBadVersion
  if getBe32(buf, 8) != uint32(isp1181PayloadBytes):
    return isp1181StateBadWidth
  if getBe32(buf, isp1181StateHeaderBytes + isp1181PayloadBytes) !=
      isp1181StateChecksum(buf,
                           isp1181StateHeaderBytes + isp1181PayloadBytes):
    return isp1181StateBadChecksum

  # THE FIELD PASS RUNS OVER A PROBE AND NOT OVER THE HANDLE. A block whose
  # checksum was recomputed over a damaged payload passes every check above and
  # still holds a byte a field's type has no name for; assigning that byte to an
  # enum leaves the handle carrying a value the type cannot express, which
  # `--panics:on` turns into an abort inside a plugin host - the one outcome
  # design section 5.6 refuses.
  var probe: Isp1181CtxObj
  var fieldStatus = isp1181StateOk
  discard isp1181StateWalk(probe,
                           cast[StateBuf](addr buf[isp1181StateHeaderBytes]),
                           isp1181Inspect, nil, addr fieldStatus)
  if fieldStatus != isp1181StateOk:
    return fieldStatus

  discard isp1181StateWalk(ctx[],
                           cast[StateBuf](addr buf[isp1181StateHeaderBytes]),
                           isp1181LoadOp, nil, nil)
  isp1181StateOk

proc isp1181_state_load*(ctx: ISP1181Ctx; src: pointer)
    {.exportc: "isp1181_state_load", cdecl, dynlib.} =
  ## THE REFUSAL IS DROPPED HERE AND IT IS NOT LOST. `isp1181Restore` names it,
  ## and `include/mcf5307.h` gives this entry point no result, no out-parameter
  ## and no status call to carry it out to C. What a C caller is left with is
  ## the state it already had, which is the strongest report a `void` signature
  ## admits.
  discard isp1181Restore(ctx, src)
