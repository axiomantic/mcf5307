## `irq` - the interrupt input, the mask against the status register, and the
## interrupt exception.
##
## The core holds no pending set: the three `irqLevel*` fields of the context
## are the board's last presentation and nothing more. `mcf5307_set_irq`
## overwrites them whole, which is what makes the call idempotent without a
## comparison against a previous value.
##
## The one piece of history the core does keep is the level-7 edge, and the
## manual is why. MCF5307 User's Manual section 7.6, folio 7-23, NOTE:
## "Interrupt levels 1 through 6 are level-sensitive only. Interrupt level 7 is
## both level sensitive and edge triggered as described in 7.6.1 Level 7
## Interrupts." Section 7.6.1, folio 7-24: a level 7 interrupt "is a
## nonmaskable interrupt; therefore, a 7 in the interrupt mask does not disable
## a level 7 interrupt", and it is "edge triggered by a transition from a lower
## priority request to the level 7 request, as opposed to interrupt levels 1
## through 6, which are level sensitive. Therefore, if IRQ7 remains asserted,
## the MCF5307 device will only recognize one level 7 interrupt because only
## one transition from a lower level request to a level 7 request occurred."
##
## This module implements the edge half of level 7 and not the level half,
## which is a deliberate divergence from the manual. The rule here is
## edge-only: an edge arms one interrupt, a held level arms no second one, and
## the core clears the latch when it takes the interrupt. Section 7.6.1's
## second numbered sequence describes a case that rule cannot produce - a
## handler that lowers the interrupt mask sees a second level 7 interrupt "even
## though no transition has occurred on the interrupt control pins". No level-7
## source is programmed in this project, so nothing here can reach the
## difference.
##
## The order inside `takeInterrupt` is the manual's four steps, and the
## acknowledge is the one place it is not. Section 3.3, folio 3-11, puts the
## interrupt-acknowledge cycle second, before the frame is stacked, because
## that is where the hardware gets the vector number from. This interface
## already has the vector - the board pushes its whole state on every change
## instead of the core pulling a vector at the moment of the interrupt - so the
## acknowledge happens after the 8-byte frame is on the stack and before the
## first handler instruction is fetched.

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
  ## The vector a presentation names. A non-zero `autovector` makes the core
  ## use the autovector for `level` and ignore `vector`.
  ##
  ## `autovectorFor` is typed `range[1 .. 7]`, and every caller below has
  ## already established that the level is in that range, so the conversion
  ## cannot fail.
  if autovector: autovectorFor(level) else: vector

proc mcf5307_set_irq*(ctx: MCF5307Ctx; level: cint; vector: uint8;
                      autovector: cint)
    {.exportc: "mcf5307_set_irq", cdecl, dynlib.} =
  ## Present the board's current highest-priority pending interrupt.
  ##
  ## It is a whole-state write and therefore idempotent by construction: the
  ## level-7 arm below is conditional on a change of level, so the second of
  ## two identical calls arms nothing. A model that accumulated instead of
  ## overwriting would need a comparison here to stay idempotent, and would
  ## make the core hold a second copy of the board's pending state.
  ##
  ## A level outside 0 to 7 is stored and never taken, and that is a property
  ## of the comparisons below rather than a rule this module states. What the
  ## code guarantees is only that no such value can reach `autovectorFor`,
  ## whose parameter is a checked range.
  if ctx.isNil:
    return
  # The arm is tested before the presentation is overwritten, because the test
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
  ## pin.
  ##
  ## This is an inference, not a citation: the manuals are silent. Section
  ## 3.5.11, folio 3-17, enumerates the reset exception's effects and names no
  ## pending-interrupt state among them; sections 7.6 and 7.6.1, folios 7-23
  ## and 7-24, give level 7 its trigger type and never mention reset. Two
  ## arguments pull in opposite directions, which is why it does two things and
  ## not one:
  ##
  ##   The clear. RSTI resets every register in the SIM and every peripheral
  ##   (folio 8-10) and the entire device including the PLL (folio 7-40). There
  ##   is no silicon that does all of that and preserves a one-bit edge-history
  ##   flop inside the core's own recognition logic.
  ##
  ##   The re-observation, without which the clear alone drops an interrupt real
  ##   hardware takes. Section 7.6.1, folio 7-24: "The level 7 request on IRQ7
  ##   must be held until the second interrupt-acknowledge bus cycle has begun
  ##   to ensure that the interrupt is recognized." A latched edge whose pin has
  ##   since been released has nothing left for an acknowledge cycle to
  ##   acknowledge, and keeping it models a state the hardware cannot reach. A
  ##   pin still asserted across the reset is the other case entirely: the
  ##   detector's history is back at "last seen level 0", so its next
  ##   observation is a transition from a lower request to the level 7 request
  ##   and the core re-arms itself.
  ##
  ## Putting the stored history back to 0 and re-presenting the board's own last
  ## presentation is exactly what a detector reset to level 0 does at its next
  ## observation, and it writes the edge's vector and its flag by the one route
  ## that ever writes them.
  ##
  ## The re-arm takes its vector from `ctx.irqVector` and not from
  ## `ctx.irq7Vector`, and that is a decision rather than an oversight. The two
  ## can differ: a board that presents level 7 with vector A and then level 7
  ## again with vector B has made no transition, so the second call arms
  ## nothing, and `ctx.irq7Vector` still holds A while `ctx.irqVector` holds B.
  ## The re-presentation below therefore arms an edge carrying B. B is right
  ## because this procedure re-observes a pin and does not restore a latch:
  ## `ctx.irq7Vector` is the core's own record of an edge the line above has
  ## just cleared, and reading it back would carry pre-reset core history across
  ## the reset - the exact thing the clear exists to prevent, arriving by the
  ## other door.
  ##
  ## The two halves are separately load-bearing and the registry measures each.
  ## `tests/t_claims.cmake` applies them one at a time to a copy of `src/`: a
  ## reset that clears without re-observing reds three cases of `t_irq`
  ## (`reset_edge_resample_suite_t_irq`), and a reset that re-observes without
  ## clearing reds exactly one (`reset_edge_clear_suite_t_irq`). The counts
  ## differ because the two halves fail different pins - dropping the clear is
  ## invisible to every case whose pin is still asserted, and only the released
  ## pin separates it - so one entry could not have stood for both.
  ##
  ## Levels 1 to 6 need nothing here. Section 7.6, folio 7-23, NOTE: they are
  ## "level-sensitive only", so `pendingInterrupt` reads the live presentation
  ## at every sample and there is no history for a reset to put back.
  if ctx.isNil:
    return
  let level = ctx.irqLevel
  let vector = ctx.irqVector
  let autovector: cint = (if ctx.irqAutovector: 1 else: 0)
  # The clear is spelled without a literal so that a mutation registered in
  # `tests/t_claims.cmake` can retype this field as a counter and still
  # compile. A `false` here would be the one assignment that mutation cannot
  # retype, and it would stop measuring the latch.
  ctx.irq7Armed = default(typeof(ctx.irq7Armed))
  ctx.irqLevel = 0
  mcf5307_set_irq(ctx, level, vector, autovector)

proc pendingInterrupt*(ctx: MCF5307Ctx): tuple[take: bool, level: int,
                                               vector: uint8] =
  ## The interrupt the core would take at this instruction boundary.
  ##
  ## Level 7 is tested first and it is tested against the latch, not against
  ## the presented level. Section 7.6.1: it is nonmaskable, so no comparison
  ## against the mask guards it, and it is edge triggered, so a presented
  ## level 7 with no armed latch is not an interrupt at all - that is the
  ## state a held level 7 is in after the core has taken it.
  ##
  ## Levels 1 to 6 are tested against the presentation and nothing else.
  ## Section 3.2.2.1, folio 3-10: "Interrupt requests are inhibited for all
  ## priority levels less than or equal to the current priority", so the test
  ## is strictly greater than. Section 7.6, folio 7-23, states it from the
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

  # The latch is cleared here and not in the acknowledge callback: the board
  # does nothing for level 7, so a board that also cleared something would be
  # clearing a second copy of one state. It is cleared before the frame is
  # stacked so that a fault inside the stacking does not leave an interrupt
  # armed that the machine has already begun to take.
  if pending.level == 7:
    ctx.irq7Armed = false

  # The stacked program counter is the next instruction: Table 3-1, folio
  # 3-13, gives vectors 25-31 a stacked program counter of "Next", and its
  # footnote defines Next as "the PC of the next instruction that follows the
  # instruction that caused the fault". This runs at an instruction boundary,
  # where `ctx.pc` is exactly that.
  takeException(ctx, pending.vector, ctx.pc)
  if ctx.halted:
    return true

  # Section 3.3, folio 3-11: "The occurrence of an interrupt exception also
  # forces the M-bit to be cleared and the interrupt priority mask to be set
  # to the level of the current interrupt request." `takeException` has
  # already set S and cleared T and has already stacked the copy of the
  # status register taken before any of it, so this write cannot reach the
  # frame. Section 7.6.1's second sequence depends on this mask write for
  # level 7 as much as for any other level: "the interrupt mask will be set
  # back to level 7".
  ctx.sr = (ctx.sr and not srMaster and not srIpmMask) or
           (uint32(pending.level) shl srIpmShift)

  # The acknowledge runs after the 8-byte frame is on the stack and before the
  # first handler instruction is fetched. The board does nothing here for a
  # level source and nothing here for level 7; an edge source on the board's
  # own side clears itself.
  if not ctx.iackFn.isNil:
    ctx.iackFn(ctx.user, cint(pending.level), pending.vector)
  true
