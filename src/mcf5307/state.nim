## `state` - the snapshot of the core, as a flat block of bytes. Task CPU-18.
## Design section 5.3.
##
## THE BLOCK HOLDS NO POINTER, AND THAT IS A PROPERTY OF THE WALK BELOW RATHER
## THAN OF A LIST KEPT BY HAND. `MCF5307Ctx` carries the board's cookie and the
## board's callbacks, and none of them means anything in another process or
## after the board is rebuilt. The walk SKIPS them BY TYPE. Every other field
## is encoded, and a field of a type the walk has no encoding for STOPS THE
## COMPILE naming the field - which is why the unreachable arm of the walk is
## an `{.error.}` and not a `discard`. A context that grows a field therefore
## either enters the snapshot or refuses to build, and never leaves quietly.
##
## THERE IS ONE WALK AND NOT A WALK PER OPERATION. The size, the layout, the
## save and the load are the same procedure under different operations, so the
## number of bytes the size reports and the number the save writes cannot
## disagree. Two walks kept in step by hand is a buffer overrun in a C ABI
## waiting for the edit that forgets one of them.
##
## THE ENCODING IS BIG-ENDIAN AND NOT THE HOST'S ORDER. A block is a byte
## stream: a caller may write it to a file and read it back on another machine,
## and native order would make the same core produce two different blocks for
## one state. Big-endian is also the order the board reads through, so a reader
## comparing a snapshot against a memory dump reads one order and not two.
##
## THE C ENTRY POINT FOR THE LOAD REPORTS NO FAILURE AND THAT IS A PROPERTY OF
## THE CONTRACT, NOT A CHOICE MADE HERE. `include/mcf5307.h` declares
## `void mcf5307_state_load(mcf5307_ctx*, const void*)`: no result, no
## out-parameter and no status call, which is the shape `mcf5307_runtime_init`
## already records. So the Nim entry point `stateLoad` returns a NAMED status
## and the C wrapper can only refuse the block; what it refuses, it refuses
## WITHOUT TOUCHING THE CONTEXT, so a caller who ignores the missing channel
## keeps the state it had rather than a half-loaded one. Adding a channel means
## adding a declaration to the contract header, which belongs to another task.
##
## MIT licensed. Nothing here is a fact about Motorola silicon.

import mcf5307/decode_types

const
  stateMagic* = 0x4D435335'u32
    ## `MCS5` - the first longword of the block.
  stateVersion* = 1'u32
    ## The version word. It moves when the payload's layout moves, and
    ## `stateLoad` refuses a block that does not carry this exact value.
  stateHeaderBytes = 12
    ## magic, version, payload width
  stateChecksumBytes = 4

type
  StateStatus* = enum
    ## The result of a load. Every refusal has a name, so a caller reports
    ## WHICH part of the block it refused and not merely that it did.
    stateOk
    stateNilArgument
    stateBadMagic
    stateBadVersion
    stateBadWidth
    stateBadChecksum

  StateOp = enum
    stateMeasure
    stateSave
    stateLoad

  Mcf5307CtxObj = typeof(default(MCF5307Ctx)[])

  StateBuf = ptr UncheckedArray[uint8]

proc putBe32(buf: StateBuf; at: int; value: uint32) =
  buf[at] = uint8((value shr 24) and 0xFF'u32)
  buf[at + 1] = uint8((value shr 16) and 0xFF'u32)
  buf[at + 2] = uint8((value shr 8) and 0xFF'u32)
  buf[at + 3] = uint8(value and 0xFF'u32)

proc getBe32(buf: StateBuf; at: int): uint32 =
  (uint32(buf[at]) shl 24) or (uint32(buf[at + 1]) shl 16) or
    (uint32(buf[at + 2]) shl 8) or uint32(buf[at + 3])

proc stateChecksum(buf: StateBuf; upTo: int): uint32 =
  ## FNV-1a over the first `upTo` bytes.
  ##
  ## THE ALGORITHM IS CHOSEN FOR A PROOF AND NOT FOR ITS SPREAD. Each step is
  ## `hash = (hash xor byte) * prime`, and both halves are bijections on
  ## `uint32` because the prime is odd; processing the remaining bytes is
  ## therefore a bijection of the running value. Two blocks of one length that
  ## differ anywhere reach different running values at the first difference and
  ## can never rejoin, so ANY single changed byte is detected - not with high
  ## probability, but always. A sum or an exclusive-or over words has no such
  ## property: two compensating changes cancel.
  result = 2166136261'u32
  for index in 0 ..< upTo:
    result = (result xor uint32(buf[index])) * 16777619'u32

proc stateWalk(ctx: var Mcf5307CtxObj; buf: StateBuf; op: StateOp;
               layout: ptr seq[(string, int)]): int =
  ## Walks the payload once and returns its width in bytes.
  ##
  ## `buf` is read under `stateLoad`, written under `stateSave` and never
  ## touched under `stateMeasure`, which is what lets the width be computed
  ## against no buffer at all.
  ##
  ## `layout` IS A POINTER AND IS NIL UNDER THE SAVE AND THE LOAD, so those two
  ## walks reach no heap at all. Only the description reader asks for it. A
  ## `var seq` parameter has no way to say "no description wanted", so the two
  ## operations that must stay allocation-free would each build a list and drop
  ## it - one allocation per call for a value nobody reads.
  var at = 0
  for name, value in fieldPairs(ctx):
    when value is pointer:
      discard
    elif value is Mcf5307ReadFn or value is Mcf5307WriteFn or
         value is Mcf5307IackFn:
      discard
    else:
      let started = at
      when value is bool:
        if op == stateSave:
          buf[at] = (if value: 1'u8 else: 0'u8)
        elif op == stateLoad:
          value = buf[at] != 0'u8
        at += 1
      elif value is uint8:
        if op == stateSave:
          buf[at] = value
        elif op == stateLoad:
          value = buf[at]
        at += 1
      elif value is uint32:
        if op == stateSave:
          putBe32(buf, at, value)
        elif op == stateLoad:
          value = getBe32(buf, at)
        at += 4
      elif value is cint:
        if op == stateSave:
          putBe32(buf, at, cast[uint32](value))
        elif op == stateLoad:
          value = cast[cint](getBe32(buf, at))
        at += 4
      elif value is array:
        for index in low(value) .. high(value):
          when value[index] is uint32:
            if op == stateSave:
              putBe32(buf, at, value[index])
            elif op == stateLoad:
              value[index] = getBe32(buf, at)
            at += 4
          else:
            {.error: "mcf5307/state: an array of a type the walk cannot encode".}
      else:
        {.error: "mcf5307/state: a context field the walk cannot encode".}
      if layout != nil:
        layout[].add((name, at - started))
  at

proc statePayloadWidth(): int =
  var probe: Mcf5307CtxObj
  stateWalk(probe, nil, stateMeasure, nil)

const statePayloadBytes = statePayloadWidth()

proc stateLayout*(): seq[(string, int)] =
  ## The name and the byte width of every context field the snapshot carries,
  ## in the order the block carries them.
  var probe: Mcf5307CtxObj
  discard stateWalk(probe, nil, stateMeasure, addr result)

proc mcf5307_state_size*(): csize_t
    {.exportc: "mcf5307_state_size", cdecl, dynlib.} =
  csize_t(stateHeaderBytes + statePayloadBytes + stateChecksumBytes)

proc mcf5307_state_save*(ctx: MCF5307Ctx; dst: pointer)
    {.exportc: "mcf5307_state_save", cdecl, dynlib.} =
  if ctx.isNil or dst.isNil:
    return
  let buf = cast[StateBuf](dst)
  putBe32(buf, 0, stateMagic)
  putBe32(buf, 4, stateVersion)
  putBe32(buf, 8, uint32(statePayloadBytes))
  discard stateWalk(ctx[], cast[StateBuf](addr buf[stateHeaderBytes]),
                    stateSave, nil)
  putBe32(buf, stateHeaderBytes + statePayloadBytes,
          stateChecksum(buf, stateHeaderBytes + statePayloadBytes))

proc stateLoad*(ctx: MCF5307Ctx; src: pointer): StateStatus =
  ## Restores the core from a block `mcf5307_state_save` wrote, or names the
  ## reason it will not.
  ##
  ## EVERY CHECK PRECEDES THE DECODE, AND THE ORDER IS THE POINT. The context
  ## is written only after the block has been accepted whole, so a refusal
  ## leaves the caller with the state it had rather than with a core half
  ## restored from a block that was never valid.
  if ctx.isNil or src.isNil:
    return stateNilArgument
  let buf = cast[StateBuf](src)
  if getBe32(buf, 0) != stateMagic:
    return stateBadMagic
  if getBe32(buf, 4) != stateVersion:
    return stateBadVersion
  if getBe32(buf, 8) != uint32(statePayloadBytes):
    return stateBadWidth
  if getBe32(buf, stateHeaderBytes + statePayloadBytes) !=
      stateChecksum(buf, stateHeaderBytes + statePayloadBytes):
    return stateBadChecksum
  discard stateWalk(ctx[], cast[StateBuf](addr buf[stateHeaderBytes]),
                    stateLoad, nil)
  stateOk

proc mcf5307_state_load*(ctx: MCF5307Ctx; src: pointer)
    {.exportc: "mcf5307_state_load", cdecl, dynlib.} =
  ## THE REFUSAL IS DROPPED HERE AND IT IS NOT LOST. `stateLoad` names it, and
  ## `include/mcf5307.h` gives this entry point no result, no out-parameter and
  ## no status call to carry it out to C. What a C caller is left with is the
  ## state it already had, which is the strongest report a `void` signature
  ## admits. Carrying the name out to C means growing the contract header, and
  ## that header belongs to another task.
  discard stateLoad(ctx, src)
