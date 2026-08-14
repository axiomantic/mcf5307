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
## THE HOST'S THREE ARGUMENTS ARE ACCEPTED AND NONE OF THEM IS KEPT. A stub
## that held the interrupt callback could raise IRQ3 - a later edit away from a
## line design section 9.1 forbids - and a stub that held the transmit callback
## could invent a packet. Holding neither makes both refusals structural, so
## they are not properties a reader has to keep true.
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
## THE ENTRY POINTS BELOW STILL ANSWER WITH THE STUB, AND THAT IS NOT AN
## OVERSIGHT. Which implementation stands behind them is an OPEN OPERATOR
## DECISION, plan item W3-51: the design document's only sentence on the
## run-time selection names no flag, no identifier, no type, no default and no
## owner, and the row explicitly picks none of the three shapes it lists.
## Wiring one here would take that decision by accident and would silently
## remove the stub the milestone path boots against.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import ./isp1181
export Isp1181IrqFn, Isp1181TxFn

type
  ISP1181Ctx* = ref object
    ## Opaque to every caller: C sees `isp1181_ctx` and never its layout. It
    ## carries no field because the stub holds no state that a read could
    ## return or a write could change.

proc isp1181_create*(user: pointer; irq: Isp1181IrqFn;
                     tx: Isp1181TxFn): ISP1181Ctx
    {.exportc: "isp1181_create", cdecl, dynlib.} =
  ## Allocate the handle. This is the one place this model allocates.
  new(result)

proc isp1181_destroy*(ctx: ISP1181Ctx)
    {.exportc: "isp1181_destroy", cdecl, dynlib.} =
  ## Tear the handle down. Under `--mm:arc` the object is reclaimed when the
  ## owning reference is dropped, and the stub has nothing else to release.
  discard

proc isp1181_read*(ctx: ISP1181Ctx; address: uint32): uint8
    {.exportc: "isp1181_read", cdecl, dynlib.} =
  ## The benign value, at every address and in every device state.
  0x00'u8

proc isp1181_write*(ctx: ISP1181Ctx; address: uint32; value: uint8)
    {.exportc: "isp1181_write", cdecl, dynlib.} =
  ## Accept the write and keep nothing. A stub that stored the byte would read
  ## it back, and a register file that answers is not a benign value.
  discard

proc isp1181_rx*(ctx: ISP1181Ctx; endpoint: cint; data: ptr uint8;
                 length: csize_t)
    {.exportc: "isp1181_rx", cdecl, dynlib.} =
  ## Accept host traffic and keep nothing. The buffer is not read, so a nil
  ## pointer and a zero length are ordinary arguments here.
  discard
