## `state` - the snapshot of the core, as a flat block of bytes.
##
## The block holds no pointer, and that is a property of the walk below rather
## than of a list kept by hand. `MCF5307Ctx` carries the board's cookie and the
## board's callbacks, and none of them means anything in another process or
## after the board is rebuilt; the walk skips them by type. A field of a type
## the walk has no encoding for stops the compile naming the field - which is
## why the unreachable arm of the walk is an `{.error.}` and not a `discard`. A
## context that grows a field therefore either enters the snapshot or refuses
## to build, and never leaves quietly.
##
## There is one walk and not a walk per operation, so the number of bytes the
## size reports and the number the save writes cannot disagree. Two walks kept
## in step by hand is a buffer overrun in a C ABI waiting for the edit that
## forgets one of them.
##
## The encoding is big-endian and not the host's order. A block is a byte
## stream: a caller may write it to a file and read it back on another machine,
## and native order would make the same core produce two different blocks for
## one state. Big-endian is also the order the board reads through, so a reader
## comparing a snapshot against a memory dump reads one order and not two.

import mcf5307/decode_types

const
  stateMagic* = 0x4D435335'u32
    ## `MCS5` - the first longword of the block.
  stateVersion* = 3'u32
    ## The version word. It moves when the payload's layout moves, and
    ## `stateLoad` refuses a block that does not carry this exact value.
    ##
    ## Version 2 is the deferred write fault. `MCF5307Ctx` grew the `pending*`
    ## fields that let an access error on a store be taken at the instruction
    ## boundary, so the payload is wider and every field beyond the new ones
    ## would be read at the wrong offset from a version-1 block. `stateLoad`
    ## checks this word before the payload width, so such a block is refused as
    ## `stateBadVersion` and never as a width or a checksum - the refusal names
    ## the actual reason.
  stateHeaderBytes = 12
    ## magic, version, payload width
  stateChecksumBytes = 4

type
  StateStatus* = enum
    ## The result of a load. Every refusal has a name, so a caller reports
    ## which part of the block it refused and not merely that it did.
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
  ## The algorithm is chosen for a proof and not for its spread. Each step is
  ## `hash = (hash xor byte) * prime`, and both halves are bijections on
  ## `uint32` because the prime is odd; processing the remaining bytes is
  ## therefore a bijection of the running value. Two blocks of one length that
  ## differ anywhere reach different running values at the first difference and
  ## can never rejoin, so any single changed byte is detected - not with high
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
  ## `layout` is a pointer and is nil under the save and the load, so those two
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
  ## Every check precedes the decode, and the order is the point. The context
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
  ## The refusal is dropped here and it is not lost. `stateLoad` names it, and
  ## `include/mcf5307.h` gives this entry point no result, no out-parameter and
  ## no status call to carry it out to C. What a C caller is left with is the
  ## state it already had, which is the strongest report a `void` signature
  ## admits.
  discard stateLoad(ctx, src)
