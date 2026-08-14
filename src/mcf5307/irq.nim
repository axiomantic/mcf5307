## `irq` - the interrupt input, the mask against the status register, and the
## interrupt exception. Task CPU-17. Design section 5.2.2.
##
## WHAT THIS MODULE OWNS AND WHAT IT REFUSES TO OWN. Design section 5.2.2 puts
## the pending bit of each source and the arbitration among them on the BOARD,
## and puts the mask against the status register and the exception frame in the
## CORE. This module is the core half and it holds NO pending set: the three
## `irqLevel*` fields of the context are the board's last presentation and
## nothing more. `mcf5307_set_irq` overwrites them whole, which is what makes
## the call idempotent without a comparison against a previous value.
##
## THE ONE PIECE OF HISTORY THE CORE DOES KEEP IS THE LEVEL-7 EDGE, and the
## manual is why. MCF5307 User's Manual section 7.6, folio 7-23, NOTE, read as
## a page image 2026-08-12: "Interrupt levels 1 through 6 are level-sensitive
## only. Interrupt level 7 is both level sensitive and edge triggered as
## described in 7.6.1 Level 7 Interrupts." Section 7.6.1, folio 7-24: a level 7
## interrupt "is a nonmaskable interrupt; therefore, a 7 in the interrupt mask
## does not disable a level 7 interrupt", and it is "edge triggered by a
## transition from a lower priority request to the level 7 request, as opposed
## to interrupt levels 1 through 6, which are level sensitive. Therefore, if
## IRQ7 remains asserted, the MCF5307 device will only recognize one level 7
## interrupt because only one transition from a lower level request to a level
## 7 request occurred."
##
## THIS MODULE IMPLEMENTS THE EDGE HALF OF LEVEL 7 AND NOT THE LEVEL HALF, AND
## THAT IS A DIVERGENCE FROM THE MANUAL THAT DESIGN SECTION 5.2.2 CHOSE. The
## design's rule 2 is edge-only: an edge arms one interrupt, a held level arms
## no second one, and the core clears the latch when it takes the interrupt.
## Section 7.6.1's second numbered sequence describes a case that rule cannot
## produce - a handler that LOWERS the interrupt mask sees a second level 7
## interrupt "even though no transition has occurred on the interrupt control
## pins". The G2 programs no level-7 source (design section 5.2.2), so nothing
## in this project can reach the difference. It is RECORDED HERE AND NOT
## RESOLVED, because resolving it would be this task choosing where the design
## is silent.
##
## THE ORDER INSIDE `takeInterrupt` IS THE MANUAL'S FOUR STEPS, AND THE
## ACKNOWLEDGE IS THE ONE PLACE IT IS NOT. Section 3.3, folio 3-11, puts the
## interrupt-acknowledge cycle SECOND, before the frame is stacked, because
## that is where the hardware gets the vector number from. This interface
## already has the vector: design section 5.2.2 records that divergence in full
## - the board PUSHES its whole state on every change instead of the core
## PULLING a vector at the moment of the interrupt - and it fixes the
## acknowledge at "after the 8-byte frame is on the stack and before the first
## handler instruction is fetched". That is the order below.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The mask
## rule, the status-register bit positions, the trigger types and the
## autovector assignments are facts about Motorola silicon, from the MCF5307
## User's Manual (1998).

import mcf5307/decode_types
import mcf5307/exception
import mcf5307/machine

# User's Manual section 3.2.2.1, folio 3-10, prints the whole 16-bit status
# register over its bit numbers: T at 15, S at 13, M at 12 and I[2:0] at bits
# 10 to 8. `machine.nim` names T, S and M with the rest of the register; the
# interrupt priority mask is here because its SHIFT is only meaningful to the
# comparison `pendingInterrupt` makes, and that comparison is this module's.
const
  srIpmMask* = 0x0700'u32      ## I[2:0], bits 10-8
  srIpmShift* = 8

proc srIpm*(sr: uint32): uint32 =
  ## The interrupt priority mask the status register `sr` carries.
  (sr and srIpmMask) shr srIpmShift

proc vectorFor(level: int; vector: uint8; autovector: bool): uint8 =
  ## The vector a presentation names. Section 5.2.2: "`autovector` non-zero
  ## makes the core use the autovector for `level` and ignore `vector`."
  ##
  ## `autovectorFor` IS CPU-14'S AND IT IS NOT RE-DERIVED HERE. It is typed
  ## `range[1 .. 7]`, and every caller below has already established that the
  ## level is in that range, so the conversion cannot fail.
  if autovector: autovectorFor(level) else: vector

proc mcf5307_set_irq*(ctx: MCF5307Ctx; level: cint; vector: uint8;
                      autovector: cint)
    {.exportc: "mcf5307_set_irq", cdecl, dynlib.} =
  ## Present the board's CURRENT highest-priority pending interrupt.
  ##
  ## IT IS A WHOLE-STATE WRITE AND THEREFORE IDEMPOTENT BY CONSTRUCTION. Two
  ## calls with the same arguments leave the same six fields holding the same
  ## values, and the level-7 arm below is conditional on a CHANGE of level, so
  ## the second of two identical calls arms nothing. A model that accumulated
  ## instead of overwriting would need a comparison here to stay idempotent,
  ## and design section 5.2.2 rejects it for a different and stronger reason:
  ## it would make the core hold a second copy of the board's pending state.
  ##
  ## A LEVEL OUTSIDE 0 TO 7 IS STORED AND NEVER TAKEN, and that is a property
  ## of the comparisons below rather than a rule this module states. Design
  ## section 5.2.2 defines the argument over 0 to 7 alone and says nothing
  ## about any other value, so nothing here invents a meaning for one; what
  ## the code guarantees is only that no such value can reach `autovectorFor`,
  ## whose parameter is a checked range.
  if ctx.isNil:
    return
  # THE ARM IS TESTED BEFORE THE PRESENTATION IS OVERWRITTEN, because the test
  # IS the transition: section 7.6.1's "a transition from a lower priority
  # request to the level 7 request". The old level is the only thing that can
  # answer it and the next line destroys it.
  if level == 7 and ctx.irqLevel != 7:
    ctx.irq7Armed = true
    ctx.irq7Vector = vector
    ctx.irq7Autovector = autovector != 0
  ctx.irqLevel = level
  ctx.irqVector = vector
  ctx.irqAutovector = autovector != 0

proc resetInterruptEdge*(ctx: MCF5307Ctx) =
  ## What a RESET does to the level-7 edge latch: clear it, then re-observe the
  ## pin. `mcf5307_reset` in `cpu.nim` is its one caller today, and the nil
  ## guard below is what makes that a fact about the tree rather than a
  ## precondition this procedure depends on.
  ##
  ## THIS IS AN INFERENCE AND NOT A CITATION, AND THE MANUALS ARE SILENT RATHER
  ## THAN BRIEF. Section 3.5.11, folio 3-17 (PDF page 74), enumerates the reset
  ## exception's effects and names no pending-interrupt state among them;
  ## sections 7.6 and 7.6.1, folios 7-23 and 7-24 (PDF pages 138 and 139), give
  ## level 7 its trigger type and never mention reset at all. Two arguments
  ## stand in for the quotation this procedure does not have, and they pull in
  ## opposite directions, which is why it does two things and not one:
  ##
  ##   THE CLEAR. RSTI resets every register in the SIM and every peripheral
  ##   (folio 8-10, PDF page 167) and the entire device including the PLL (folio
  ##   7-40, PDF page 155). There is no silicon that does all of that and
  ##   preserves a one-bit edge-history flop inside the core's own recognition
  ##   logic.
  ##
  ##   THE RE-OBSERVATION, WITHOUT WHICH THE CLEAR ALONE DROPS AN INTERRUPT REAL
  ##   HARDWARE TAKES. Section 7.6.1, folio 7-24 (PDF page 139): "The level 7
  ##   request on IRQ7 must be held until the second interrupt-acknowledge bus
  ##   cycle has begun to ensure that the interrupt is recognized." A latched
  ##   edge whose pin has since been released therefore has nothing left for an
  ##   acknowledge cycle to acknowledge, and keeping it models a state the
  ##   hardware cannot reach. A pin STILL ASSERTED across the reset is the other
  ##   case entirely: the detector's history is back at "last seen level 0", so
  ##   its next observation is a transition from a lower request to the level 7
  ##   request and the core RE-ARMS ITSELF.
  ##
  ## IT IS THE ORDINARY EDGE PATH THAT RE-ARMS AND NOT A SECOND COPY OF IT.
  ## Putting the stored history back to 0 and re-presenting the board's own last
  ## presentation is exactly what a detector reset to level 0 does at its next
  ## observation, and it writes the edge's vector and its flag by the ONE route
  ## that ever writes them.
  ##
  ## THE BOARD'S PRESENTATION IS NOT INVENTED OR DISCARDED HERE. `mcf5307_set_irq`
  ## is called with the values already in the context, so the six fields end
  ## holding what the board last said; what the two lines below change is the
  ## core's own edge history and its latch.
  ##
  ## THE RE-ARM TAKES ITS VECTOR FROM `ctx.irqVector` AND NOT FROM
  ## `ctx.irq7Vector`, AND THAT IS A DECISION RATHER THAN AN OVERSIGHT. The two
  ## can differ: a board that presents level 7 with vector A and then level 7
  ## again with vector B has made NO transition, so the second call arms
  ## nothing, and `ctx.irq7Vector` still holds A while `ctx.irqVector` holds B.
  ## The re-presentation below therefore arms an edge carrying B.
  ##
  ## B IS RIGHT BECAUSE THIS PROCEDURE RE-OBSERVES A PIN AND DOES NOT RESTORE A
  ## LATCH. `ctx.irq7Vector` is the core's own record of an edge THE LINE ABOVE
  ## HAS JUST CLEARED, and reading it back would carry pre-reset core history
  ## across the reset - the exact thing the clear exists to prevent, arriving by
  ## the other door. `ctx.irqVector` is what the board is presenting NOW, which
  ## is what a detector whose history has been put back to level 0 sees at its
  ## next observation, and that detector is the whole of what this procedure
  ## models. The vector a level-7 acknowledge carries is the board's to state
  ## and the core has no older copy of it worth preferring.
  ##
  ## LEVELS 1 TO 6 NEED NOTHING HERE. Section 7.6, folio 7-23, NOTE: they are
  ## "level-sensitive only", so `pendingInterrupt` reads the live presentation
  ## at every sample and there is no history for a reset to put back.
  ##
  ## THE TWO HALVES ARE SEPARATELY LOAD-BEARING AND THE REGISTRY MEASURES EACH.
  ## `tests/t_claims.cmake` applies them one at a time to a copy of `src/`: a
  ## reset that clears without re-observing reds three cases of `t_irq`
  ## (`reset_edge_resample_suite_t_irq`), and a reset that re-observes without
  ## clearing reds exactly one (`reset_edge_clear_suite_t_irq`). The counts
  ## DIFFER because the two halves fail different pins - dropping the clear is
  ## invisible to every case whose pin is still asserted, and only the released
  ## pin separates it - so one entry could not have stood for both.
  ##
  ## THE NIL GUARD IS A MECHANISM WHERE THE CALLER LIST WAS A SENTENCE. This
  ## procedure is not a C ABI entry point, so the argument does come from Nim
  ## and the type system does vouch for it - but only for as long as every
  ## caller is one this file's reader has seen. `mcf5307_reset`'s own guard
  ## returns BEFORE it reaches this call, so nothing upstream protects this
  ## procedure either, and a second caller forwarding a nil would fault on the
  ## first executable line below. A SENTENCE NAMING THE CALLERS CANNOT FAIL
  ## WHEN A CALLER IS ADDED; this guard and `tests/t_irq.nim` block 26 can.
  if ctx.isNil:
    return
  let level = ctx.irqLevel
  let vector = ctx.irqVector
  let autovector: cint = (if ctx.irqAutovector: 1 else: 0)
  # THE CLEAR IS SPELLED WITHOUT A LITERAL, AND THAT IS NOT STYLE.
  # `tests/t_claims.cmake` registers M3, a mutation that RETYPES this field as a
  # COUNTER in order to measure what `tests/t_irq.nim` claims about a `bool`
  # latch. `default` answers for whatever type the field carries, so M3 can
  # retype the field and this line still compiles - which is what leaves M3
  # MEASURING THE LATCH. A `false` here would be the one assignment M3 cannot
  # retype, and M3 would stop being a measurement of this core at all.
  #
  # THAT THE SPELLING IS LOAD-BEARING IS PINNED AND NOT ASSERTED, by M3's own
  # registry entry: a `suite-red` claim whose mutated tree does not compile is
  # a FATAL_ERROR in that driver, so the day this line stops accepting M3's
  # retype is the day `t_claims` stops.
  #
  # WHAT A `false` HERE WOULD DO IS NOT SILENT, AND THE SENTENCE THAT SAID IT
  # WAS IS DELETED RATHER THAN REWORDED. It read that the claim "would go
  # unmeasured with nothing to say so". MEASURED 2026-08-13 by respelling this
  # line as `ctx.irq7Armed = false` and running the suite: `t_claims` stops at
  # rc 8 and NAMES the claim - `M3_suite_t_irq: t_irq does not compile against
  # the mutated tree. A mutation that does not compile is not a mutation this
  # suite failed to catch.` - over Nim's own `type mismatch: got 'bool' for
  # 'false' but expected 'int'`. The difference the spelling buys is a
  # MEASUREMENT instead of a stopped run, and not a loud failure instead of a
  # quiet one.
  ctx.irq7Armed = default(typeof(ctx.irq7Armed))
  ctx.irqLevel = 0
  mcf5307_set_irq(ctx, level, vector, autovector)

proc pendingInterrupt*(ctx: MCF5307Ctx): tuple[take: bool, level: int,
                                               vector: uint8] =
  ## The interrupt the core would take at this instruction boundary.
  ##
  ## LEVEL 7 IS TESTED FIRST AND IT IS TESTED AGAINST THE LATCH, NOT AGAINST
  ## THE PRESENTED LEVEL. Section 7.6.1: it is nonmaskable, so no comparison
  ## against the mask guards it, and it is edge triggered, so a presented
  ## level 7 with no armed latch is not an interrupt at all - that is the
  ## state a held level 7 is in after the core has taken it.
  ##
  ## LEVELS 1 TO 6 ARE TESTED AGAINST THE PRESENTATION AND NOTHING ELSE.
  ## Section 3.2.2.1, folio 3-10: "Interrupt requests are inhibited for all
  ## priority levels less than or equal to the current priority", so the test
  ## is STRICTLY GREATER THAN. Section 7.6, folio 7-23, states it from the
  ## other side: "When an interrupt request has a priority higher than the
  ## value in the mask, the ColdFire core makes the request a pending
  ## interrupt." A `>=` here would take a level the hardware inhibits, and a
  ## mask of 7 would then stop nothing.
  if ctx.irq7Armed:
    return (true, 7, vectorFor(7, ctx.irq7Vector, ctx.irq7Autovector))
  let level = int(ctx.irqLevel)
  if level >= 1 and level <= 6 and uint32(level) > srIpm(ctx.sr):
    return (true, level, vectorFor(level, ctx.irqVector, ctx.irqAutovector))
  (false, 0, 0'u8)

proc takeInterrupt*(ctx: MCF5307Ctx): bool =
  ## Take the pending interrupt, if there is one. Returns true when one was
  ## taken. `mcf5307_exec` calls this at every instruction boundary.
  let pending = pendingInterrupt(ctx)
  if not pending.take:
    return false

  # THE LATCH IS CLEARED HERE AND NOT IN THE ACKNOWLEDGE CALLBACK. Design
  # section 5.2.2's acknowledge table: for level 7 the board does "nothing on
  # the board side ... so a board that also cleared something would be
  # clearing a second copy of one state". It is cleared BEFORE the frame is
  # stacked so that a fault inside the stacking - CPU-15's double fault - does
  # not leave an interrupt armed that the machine has already begun to take.
  if pending.level == 7:
    ctx.irq7Armed = false

  # The stacked program counter is the NEXT instruction: Table 3-1, folio
  # 3-13, gives vectors 25-31 a STACKED PROGRAM COUNTER of "Next", and its
  # footnote defines Next as "the PC of the next instruction that follows the
  # instruction that caused the fault". This runs at an instruction boundary,
  # where `ctx.pc` is exactly that.
  takeException(ctx, pending.vector, ctx.pc)
  if ctx.halted:
    return true

  # Section 3.3, folio 3-11: "The occurrence of an interrupt exception also
  # forces the M-bit to be cleared and the interrupt priority mask to be set
  # to the level of the current interrupt request." `takeException` has
  # already set S and cleared T and has already stacked the COPY of the
  # status register taken before any of it, so this write cannot reach the
  # frame. Section 7.6.1's second sequence depends on this mask write for
  # level 7 as much as for any other level: "the interrupt mask will be set
  # back to level 7".
  ctx.sr = (ctx.sr and not srMaster and not srIpmMask) or
           (uint32(pending.level) shl srIpmShift)

  # Design section 5.2.2: the core calls the acknowledge "after the 8-byte
  # frame is on the stack and before it fetches the first handler
  # instruction". The board does nothing here for a level source and nothing
  # here for level 7; an edge source on the board's own side clears itself.
  if not ctx.iackFn.isNil:
    ctx.iackFn(ctx.user, cint(pending.level), pending.vector)
  true
