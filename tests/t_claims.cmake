# `t_claims` - the registry of the claims this repository's tests make about
# mutations, and the driver that makes each one executable.
#
# THE DEFECT CLASS THIS EXISTS FOR is "claims the evidence does not
# establish". A test file may state that a change
# to the core is unobservable, that no case separates it, or that a mutant is
# equivalent. A FALSE CLAIM OF THAT SHAPE READS EXACTLY LIKE A TRUE ONE. It
# cannot be caught by reading, and it cannot be repaired by rewriting the
# sentence, because a rewritten sentence is still a sentence.
#
# SO EVERY SUCH CLAIM NAMES A MUTATION, THE MUTATION IS DEFINED HERE, AND THIS
# DRIVER APPLIES IT AND MEASURES THE RESULT. Two kinds, because the claims in
# this repository come in two shapes:
#
#   `suite-red`   The claim is SUITE-RELATIVE: "no case in <suite> separates
#                 this mutation from the shipped code", or "this mutation is
#                 caught by exactly N cases". The check applies the mutation
#                 and counts the RED cases of that suite. A baseline run of the
#                 same suite against the pristine tree must be 0 red first,
#                 because "0 red after" says nothing when "before" is not 0.
#
#   `equivalent`  The claim is ABSOLUTE: "changes no reachable state". The
#                 check compiles `tests/t_claims.nim` - which asserts nothing
#                 and only prints what it observed over a bounded space of
#                 scenarios - against the pristine tree and against the mutated
#                 tree, and requires the two traces to be IDENTICAL. ONE
#                 differing scenario refutes the claim.
#
# THE TWO KINDS ARE NOT TWO STRENGTHS OF ONE TEST. A mutation may be
# unseparated by a suite and still change reachable state; that is the ordinary
# case, and it is why the two are registered separately and why each claim is
# checked against WHAT IT SAYS rather than against the strongest reading of it.
#
# WHAT NO PASS HERE ESTABLISHES. An `equivalent` claim this driver does not
# refute is a claim NO SCENARIO IN A BOUNDED SPACE separates. That is not
# "changes no reachable state" and must never be recorded as it.
#
# THE MUTATED TREE IS A COPY AND THE REPOSITORY IS NEVER WRITTEN TO. Every edit
# below lands under `${CLAIMS_WORK_DIR}`, inside the build tree.

# ---------------------------------------------------------------------------
# THE REGISTRY.
#
# Each claim carries the FILE and the SENTENCE it appears in, so that a reader
# of the source can find the check and a reader of the check can find the
# source; its KIND; its edits; and its expectation. A `\n` inside a `FIND` or a
# `REPLACE` is a newline: CMake expands the escape inside a quoted argument.
# Every value is ONE quoted argument, because two arguments would make a list
# and a list carries a `;` into the text it replaces.

set(MCF5307_CLAIM_IDS
    "control_equivalent"
    "M3_suite_t_irq"
    "A11a_suite_t_irq"
    "edge_flag_suite_t_irq"
    "edge_vector_scope_suite_t_irq"
    "reset_inhibit_suite_t_irq"
    "reset_edge_call_suite_t_irq"
    "reset_edge_resample_suite_t_irq"
    "reset_edge_clear_suite_t_irq"
    "write_fault_deferral_suite_t_bus_fault")

# EVERY `CLAIM_TEXT` BELOW IS QUOTED FROM ITS `CLAIM_FILE` AND IS NOT A SUMMARY
# OF IT. The driver looks the text up in the file before it measures anything,
# so a claim cannot outlive the sentence it registers. A summary would defeat
# that: it stays true-looking after the sentence it summarises is gone, which is
# the failure this whole file exists to make unsayable.
#
# A CLAIM LEAVES THIS REGISTRY WHEN THE SENTENCE LEAVES THE SOURCE, AND IT
# COMES BACK WHEN A NEW SENTENCE TAKES THE OLD ONE'S PLACE. The two `A11a`
# entries registered the two halves of one sentence of `tests/t_irq.nim`: that
# moving the level-7 latch clear to just after `takeException` changes no
# reachable state, and that no case in `t_irq` separated it. This driver
# REFUTED the first half. The repair was not to reword the sentence - a
# rewritten sentence is still a sentence, which is the whole reason this file
# exists - but to give `t_irq` the case the sentence had stood in for: its
# block 17 raises a level-7 edge from inside the frame write, which is the
# construction the refutation named.
#
# `A11a_equivalent` IS GONE AND DOES NOT COME BACK. Its sentence was the
# absolute one - "changes no reachable state" - this driver measured it false,
# and no sentence of that shape replaced it.
#
# `A11a_suite_t_irq` IS BACK, REGISTERED AGAINST THE SENTENCE THAT REPLACED ITS
# OWN. Its old wording expected NO case to separate the move; block 17 made
# that false and the entry went out with the wording. WHAT WENT OUT WITH IT WAS
# THE POSITION ITSELF: that the move is separated by block 17 and by nothing
# else lived only in a report and in a comment, which is the exact standing the
# refuted sentence had before this driver measured it.
#
# THE REGRESSION THAT RE-REGISTRATION CLOSES, spelled out because every other
# gate is silent on it. Simplify block 17's re-entry to a single level-7 call:
# the presented level is already 7, so the call arms nothing and the second
# interrupt disappears. Adjust the asserted tuple to match and the case passes.
# `t_irq` still reports its full case total, every declared site still
# executes, the case total still agrees, `t_claims` still reports every claim
# upheld - and the
# position is unpinned with nothing anywhere to say so. The entry below expects
# exactly ONE red, so that run says it.
#
# THIS IS NOT A REOPENING OF THE RETIREMENT. It applies the retirement's own
# rule - a claim is registered exactly as long as its sentence is in the source
# - to the NEW measured sentence that took the retired one's place.

# --- the POSITIVE CONTROL for the equivalence path --------------------------
# A CHECK THAT CANNOT PASS IS AS BROKEN AS ONE THAT CANNOT FAIL, and the
# `equivalent` path is the one at risk of it: if the observer were
# nondeterministic, if the two compiles read different trees, or if the trace
# carried a pointer value, EVERY equivalence claim would be "refuted" and the
# refutation would mean nothing.
#
# So this entry mutates the core in a way that CANNOT change its behaviour and
# requires the traces to agree. The two operands of the `and` that arms the
# level-7 latch are swapped: both are comparisons of a value already in hand,
# neither has a side effect, so the short-circuit that `and` performs cannot be
# observed either way. The file changes, the compiler reads the change - the
# reached-the-compiler control below proves that separately - and the trace
# does not move.
#
# THE SENTENCE THIS ENTRY REGISTERS, and its `CLAIM_TEXT` quotes this line:
# swapping the two operands of that `and` changes no reachable state.
set(CLAIM_control_equivalent_KIND "equivalent")
set(CLAIM_control_equivalent_CLAIM_FILE "tests/t_claims.cmake")
set(CLAIM_control_equivalent_CLAIM_TEXT "swapping the two operands of that `and` changes no reachable state.")
set(CLAIM_control_equivalent_EDITS 1)
set(CLAIM_control_equivalent_EDIT_1_FILE "mcf5307/irq.nim")
set(CLAIM_control_equivalent_EDIT_1_FIND "  if level == 7 and ctx.irqLevel != 7:")
set(CLAIM_control_equivalent_EDIT_1_REPLACE "  if ctx.irqLevel != 7 and level == 7:")

# --- M3, the counting latch -------------------------------------------------
# `tests/t_irq.nim`, under "WHAT THIS FILE PINS": "Blocks 7 and 8 cannot reach
# the guard that decides it, because both of their calls happen before the take
# and a `bool` latch cannot count." M3 replaces the `bool` with an `int`
# incremented on every level-7 edge and decremented when the interrupt is
# taken.
#
# THE CLAIM REGISTERED IS THE SUITE-RELATIVE ONE AND IT IS NOT "M3 IS
# EQUIVALENT", and that distinction is why this file has two kinds. RE-MEASURED
# 2026-08-13 against the observer AS WIDENED BY THE PRESENTATION-PROFILE AXIS:
# 50 of its 450 scenarios SEPARATE M3 from the shipped latch, and they do NOT
# all arrive the same way.
#
#   THE PROFILE AXIS DOUBLES THE COUNT AND MOVES NOTHING ELSE, which is the
#   first thing the re-measurement had to answer. The separating scenarios split
#   25 under `pAutovectored` and 25 under `pVectored`, and the two halves carry
#   the same masks, sequences, scripts and budgets. M3 changes WHEN an interrupt
#   is taken and not WHICH VECTOR it carries, so the axis that reads the stored
#   vector adds no route to it. The account below is therefore the account each
#   profile makes on its own.
#
#   TWENTY-FOUR PER PROFILE come from the PRE-TAKE sequence `7, 3, 7`, which
#   arms the counter twice, so a THIRD interrupt is taken where the shipped
#   latch takes two. Re-measured 2026-08-13: exactly eight (script, budget)
#   pairs separate under that sequence and all three masks separate identically,
#   8 x 3 x 2 profiles = 48. Both of the budgets are the long ones - the third
#   interrupt needs cycles to be reached, and every separating pair carries
#   budget 8 or 64.
#
#   THE TWENTY-FIFTH OF EACH PROFILE DOES NOT COME FROM THE PRE-TAKE SEQUENCE AT
#   ALL. It is `mask 0 pre @[3] script
#   @[7, 3, 7] budget 64`, under each profile: ONE level-3 request before the
#   run, and the `7, 3, 7` arrives through the RE-ENTRY SCRIPT - the board
#   raises those three levels from inside the frame write, while the core is
#   stacking. So the counter is armed twice from a path the pre-take sequence
#   never touches, and the separation is visible in the stack pointer, the PC,
#   the frame and the vector reads (under `pAutovectored`, shipped `sp
#   0x000007F0 framePc 0x00000532`, mutated `sp 0x000007E8 framePc
#   0x00000572`).
#
# THE DISTINCTION IS WORTH THE PARAGRAPH because the two paths are what the
# retired A11a entries above turned on, and what `t_irq`'s block 17 now
# carries: a level-7 edge raised FROM the frame write reaches the core at a
# point no pre-take presentation can reach.
#
# So M3 is equivalent WITH RESPECT TO `t_irq` and is not equivalent with
# respect to the core, and if it were registered as `equivalent` this driver
# would refute it, correctly.
set(CLAIM_M3_suite_t_irq_KIND "suite-red")
set(CLAIM_M3_suite_t_irq_SUITE "t_irq")
set(CLAIM_M3_suite_t_irq_EXPECT_RED 0)
set(CLAIM_M3_suite_t_irq_CLAIM_FILE "tests/t_irq.nim")
set(CLAIM_M3_suite_t_irq_CLAIM_TEXT "a `bool` latch cannot count")
set(CLAIM_M3_suite_t_irq_EDITS 4)
set(CLAIM_M3_suite_t_irq_EDIT_1_FILE "mcf5307/decode_types.nim")
set(CLAIM_M3_suite_t_irq_EDIT_1_FIND "irq7Armed*: bool            ## a rising edge to level 7 is latched")
set(CLAIM_M3_suite_t_irq_EDIT_1_REPLACE "irq7Armed*: int             ## a rising edge to level 7 is latched")
set(CLAIM_M3_suite_t_irq_EDIT_2_FILE "mcf5307/irq.nim")
set(CLAIM_M3_suite_t_irq_EDIT_2_FIND "    ctx.irq7Armed = true")
set(CLAIM_M3_suite_t_irq_EDIT_2_REPLACE "    inc ctx.irq7Armed")
set(CLAIM_M3_suite_t_irq_EDIT_3_FILE "mcf5307/irq.nim")
set(CLAIM_M3_suite_t_irq_EDIT_3_FIND "    ctx.irq7Armed = false")
set(CLAIM_M3_suite_t_irq_EDIT_3_REPLACE "    dec ctx.irq7Armed")
set(CLAIM_M3_suite_t_irq_EDIT_4_FILE "mcf5307/irq.nim")
set(CLAIM_M3_suite_t_irq_EDIT_4_FIND "  if ctx.irq7Armed:")
set(CLAIM_M3_suite_t_irq_EDIT_4_REPLACE "  if ctx.irq7Armed > 0:")

# --- A11a, the latch clear moved to just after the stacking ------------------
# `src/mcf5307/irq.nim` clears the level-7 latch BEFORE `takeException`. A11a
# moves the clear to just after it and before the halted check. The two
# positions differ only for a board that reaches the core WHILE the frame is
# being stacked, because `takeException` stacks through the board's own write
# callback - and that is the one boundary a hand-written case does not think of,
# which is why the sentence this entry registers was wrong the first time.
#
# THE CLAIM IS SUITE-RELATIVE AND EXPECTS ONE RED, NOT NONE, and the difference
# between those two numbers is this entry's whole subject. Its predecessor
# expected none and was refuted. The count is an upper bound as much as a lower
# one: a run that goes 2 red is as much a refutation as one that goes 0, because
# the sentence says this case AND NO OTHER separates the move.
#
# WHY THE ABSOLUTE FORM IS NOT REGISTERED ALONGSIDE IT. `A11a_equivalent` said
# the move changes no reachable state; this driver's observer measured that
# false. A suite-relative claim about `t_irq` is a different and weaker
# statement, it is what `t_irq` is entitled to make, and nothing here promotes
# one to the other.
set(CLAIM_A11a_suite_t_irq_KIND "suite-red")
set(CLAIM_A11a_suite_t_irq_SUITE "t_irq")
set(CLAIM_A11a_suite_t_irq_EXPECT_RED 1)
set(CLAIM_A11a_suite_t_irq_CLAIM_FILE "tests/t_irq.nim")
set(CLAIM_A11a_suite_t_irq_CLAIM_TEXT "that move reds this case and no other case in this file")
set(CLAIM_A11a_suite_t_irq_EDITS 2)
set(CLAIM_A11a_suite_t_irq_EDIT_1_FILE "mcf5307/irq.nim")
set(CLAIM_A11a_suite_t_irq_EDIT_1_FIND "  if pending.level == 7:\n    ctx.irq7Armed = false\n\n")
set(CLAIM_A11a_suite_t_irq_EDIT_1_REPLACE "\n")
set(CLAIM_A11a_suite_t_irq_EDIT_2_FILE "mcf5307/irq.nim")
set(CLAIM_A11a_suite_t_irq_EDIT_2_FIND "  takeException(ctx, pending.vector, ctx.pc)\n")
set(CLAIM_A11a_suite_t_irq_EDIT_2_REPLACE "  takeException(ctx, pending.vector, ctx.pc)\n  if pending.level == 7:\n    ctx.irq7Armed = false\n")

# --- the two halves of the level-7 edge's stored pair -----------------------
# THE SENTENCES THESE TWO ENTRIES CARRY WERE PROSE UNTIL 2026-08-13, AND ONE OF
# THEM WAS FALSE WHILE EVERY SUITE WAS GREEN. `tests/t_irq.nim` block 9 said
# its tuple separated "a core that used the CURRENTLY PRESENTED vector for the
# armed level 7". Its edge is AUTOVECTORED, so `vectorFor` returns the
# autovector and the stored vector is never read: the block decided the FLAG
# and said it decided the vector. Nothing failed, because a comment cannot.
#
# THE MEASURED CONSEQUENCE, and the reason both halves are registered rather
# than one. Moving `ctx.irq7Vector = vector` OUT of the level-7 guard leaves a
# store that still runs at the edge and is then overwritten by every later
# presentation. MEASURED 2026-08-13 against the file gate 4.4's round 4 left -
# 25 cases: that move redded NOTHING, and the observer of `tests/t_claims.nim`
# UPHELD it over all 225 scenarios of the space IT THEN HAD, because every
# scenario that file then presented was autovectored. A defect no suite and no
# observer could see.
#
# THE OBSERVER NOW REFUTES THAT MOVE, AND THAT IS WHY THE SENTENCE ABOVE CARRIES
# THE SPACE IT WAS MEASURED IN. `tests/t_claims.nim` gained a PRESENTATION
# PROFILE axis on 2026-08-13: `pVectored` clears the autovector flag and hands
# every presentation a DISTINCT vector, so the stored vector is read and a later
# presentation's vector is a different number from the edge's. MEASURED the same
# day, with the move registered as an `equivalent` claim in a SCRATCH COPY of
# this file against the widened observer: REFUTED, by `mask 0 pre @[7, 7] script
# @[] budget 1 profile pVectored` - shipped acknowledges vector 0x50 and enters
# its handler at 0x580, mutated acknowledges 0x51 and enters at 0x590. THE
# CALIBRATION IS NOT REGISTERED HERE, for the reason no negative control in this
# file is: a registered claim this driver refutes fails the run, and what the
# refutation establishes is a fact about the OBSERVER rather than a claim the
# repository makes.
#
# THE SUITE-RELATIVE ENTRY BELOW IS UNAFFECTED AND IS NOT PROMOTED BY ANY OF
# THIS. What `t_irq` claims is that exactly one of ITS cases separates the move.
# An observer that also separates it says nothing about that count.
#
# WHY A `suite-red` KIND AND NOT AN `equivalent` ONE. Neither entry claims a
# mutation changes no reachable state - both of these mutations plainly do.
# What each claims is SUITE-RELATIVE, and it is the claim the comment in
# `t_irq.nim` actually makes: that a named arrangement of presentations is the
# one that reaches the defect, and that exactly one case of the suite carries
# it. An EXPECT_RED of 1 is that sentence: a case weakened until the mutation
# passes it goes to 0 and is REFUTED, and a second case that started separating
# the same mutation goes to 2 and is refuted too, because the file's account of
# which arrangement reaches it would then be wrong.
set(CLAIM_edge_flag_suite_t_irq_KIND "suite-red")
set(CLAIM_edge_flag_suite_t_irq_SUITE "t_irq")
set(CLAIM_edge_flag_suite_t_irq_EXPECT_RED 1)
set(CLAIM_edge_flag_suite_t_irq_CLAIM_FILE "tests/t_irq.nim")
set(CLAIM_edge_flag_suite_t_irq_CLAIM_TEXT "THIS BLOCK PINS THE FLAG HALF AND NOT THE VECTOR HALF.")
set(CLAIM_edge_flag_suite_t_irq_EDITS 1)
set(CLAIM_edge_flag_suite_t_irq_EDIT_1_FILE "mcf5307/irq.nim")
set(CLAIM_edge_flag_suite_t_irq_EDIT_1_FIND "    return (true, 7, vectorFor(7, ctx.irq7Vector, ctx.irq7Autovector))\n")
set(CLAIM_edge_flag_suite_t_irq_EDIT_1_REPLACE "    return (true, 7, vectorFor(7, ctx.irq7Vector, ctx.irqAutovector))\n")

set(CLAIM_edge_vector_scope_suite_t_irq_KIND "suite-red")
set(CLAIM_edge_vector_scope_suite_t_irq_SUITE "t_irq")
set(CLAIM_edge_vector_scope_suite_t_irq_EXPECT_RED 1)
set(CLAIM_edge_vector_scope_suite_t_irq_CLAIM_FILE "tests/t_irq.nim")
set(CLAIM_edge_vector_scope_suite_t_irq_CLAIM_TEXT "THAT MOVE REDS NO CASE OF THAT FILE AND IT REDS THIS BLOCK.")
set(CLAIM_edge_vector_scope_suite_t_irq_EDITS 2)
set(CLAIM_edge_vector_scope_suite_t_irq_EDIT_1_FILE "mcf5307/irq.nim")
set(CLAIM_edge_vector_scope_suite_t_irq_EDIT_1_FIND "    ctx.irq7Vector = vector\n")
set(CLAIM_edge_vector_scope_suite_t_irq_EDIT_1_REPLACE "")
set(CLAIM_edge_vector_scope_suite_t_irq_EDIT_2_FILE "mcf5307/irq.nim")
set(CLAIM_edge_vector_scope_suite_t_irq_EDIT_2_FIND "  ctx.irqAutovector = autovector != 0\n")
set(CLAIM_edge_vector_scope_suite_t_irq_EDIT_2_REPLACE "  ctx.irqAutovector = autovector != 0\n  ctx.irq7Vector = vector\n")

# --- The reset's own interrupt fixes ----------------------------------------
# The reset does two separable things and the second is itself two halves, and
# a count is only evidence about the half it moves with. Deleting the whole
# `resetInterruptEdge` call, keeping the clear without the re-presentation, and
# keeping the re-presentation without the clear are three different wrong cores
# with three different signatures, and the two that share a count fail
# different cases. A single entry would have been satisfied by any core that
# moved the total to the registered number, which is the shape of measurement
# this file exists to refuse.
#
# Every count below is measured by applying the mutation to a copy of `src/`
# and running the suite, against a no-op control on the same harness.
# ---------------------------------------------------------------------------
# The deferred write fault. `src/mcf5307/writeMem` records an access error on a
# store and `cpu.nim`'s `step` takes the vector at the instruction boundary,
# because User's Manual section 3.5.1, printed page 3-15, requires the faulting
# instruction's programming-model updates to complete first. THE MUTATION PUTS
# THE TAKE BACK AT THE STORE, which is where it was before that reading, and it
# is two edits because the procedure it calls is defined further down the file
# and needs its forward declaration back.
#
# FOUR RED IS THE WHOLE OF THE CLAIM AND THE TWO GREENS ARE HALF OF IT. A
# mutation that reddened BLOCK 5 as well would mean the deferral had changed
# what the frame CONTAINS and not only when it is written, and a mutation that
# reddened PEA would mean the repair had reached an instruction that was
# already correct.

set(CLAIM_write_fault_deferral_suite_t_bus_fault_KIND "suite-red")
set(CLAIM_write_fault_deferral_suite_t_bus_fault_SUITE "t_bus_fault")
set(CLAIM_write_fault_deferral_suite_t_bus_fault_EXPECT_RED 4)
set(CLAIM_write_fault_deferral_suite_t_bus_fault_CLAIM_FILE "tests/t_bus_fault.nim")
set(CLAIM_write_fault_deferral_suite_t_bus_fault_CLAIM_TEXT "EXACTLY FOUR RED. Four and not")
set(CLAIM_write_fault_deferral_suite_t_bus_fault_EDITS 2)
set(CLAIM_write_fault_deferral_suite_t_bus_fault_EDIT_1_FILE "mcf5307/machine.nim")
set(CLAIM_write_fault_deferral_suite_t_bus_fault_EDIT_1_FIND "proc boardRead(ctx: MCF5307Ctx; address: uint32; size: uint8;\n")
set(CLAIM_write_fault_deferral_suite_t_bus_fault_EDIT_1_REPLACE "proc takeExceptionCopiedSr*(ctx: MCF5307Ctx; vector: uint8; stackedPc: uint32;\n                            fs: uint32; stackedSr: uint32)\n\nproc boardRead(ctx: MCF5307Ctx; address: uint32; size: uint8;\n")
set(CLAIM_write_fault_deferral_suite_t_bus_fault_EDIT_2_FILE "mcf5307/machine.nim")
set(CLAIM_write_fault_deferral_suite_t_bus_fault_EDIT_2_FIND "    ctx.pendingWriteFault = true\n    ctx.pendingFaultStatus = faultStatusFor(st, operandWrite)\n    ctx.pendingStackedSr = ctx.sr and 0xFFFF'u32\n    ctx.pendingStackedPc = ctx.pc\n")
set(CLAIM_write_fault_deferral_suite_t_bus_fault_EDIT_2_REPLACE "    takeExceptionCopiedSr(ctx, vecAccessError, ctx.pc,\n                          faultStatusFor(st, operandWrite), ctx.sr and 0xFFFF'u32)\n")

set(CLAIM_reset_inhibit_suite_t_irq_KIND "suite-red")
set(CLAIM_reset_inhibit_suite_t_irq_SUITE "t_irq")
set(CLAIM_reset_inhibit_suite_t_irq_EXPECT_RED 6)
set(CLAIM_reset_inhibit_suite_t_irq_CLAIM_FILE "tests/t_irq.nim")
set(CLAIM_reset_inhibit_suite_t_irq_CLAIM_TEXT "EXACTLY SIX red. Six and not two,")
set(CLAIM_reset_inhibit_suite_t_irq_EDITS 1)
set(CLAIM_reset_inhibit_suite_t_irq_EDIT_1_FILE "mcf5307/cpu.nim")
set(CLAIM_reset_inhibit_suite_t_irq_EDIT_1_FIND "  ctx.atHandlerEntry = true\n")
set(CLAIM_reset_inhibit_suite_t_irq_EDIT_1_REPLACE "  ctx.atHandlerEntry = false\n")

set(CLAIM_reset_edge_call_suite_t_irq_KIND "suite-red")
set(CLAIM_reset_edge_call_suite_t_irq_SUITE "t_irq")
set(CLAIM_reset_edge_call_suite_t_irq_EXPECT_RED 3)
set(CLAIM_reset_edge_call_suite_t_irq_CLAIM_FILE "tests/t_irq.nim")
set(CLAIM_reset_edge_call_suite_t_irq_CLAIM_TEXT "a reset that does neither reds three cases of this file")
set(CLAIM_reset_edge_call_suite_t_irq_EDITS 1)
set(CLAIM_reset_edge_call_suite_t_irq_EDIT_1_FILE "mcf5307/cpu.nim")
set(CLAIM_reset_edge_call_suite_t_irq_EDIT_1_FIND "  resetInterruptEdge(ctx)\n")
set(CLAIM_reset_edge_call_suite_t_irq_EDIT_1_REPLACE "  discard\n")

set(CLAIM_reset_edge_resample_suite_t_irq_KIND "suite-red")
set(CLAIM_reset_edge_resample_suite_t_irq_SUITE "t_irq")
set(CLAIM_reset_edge_resample_suite_t_irq_EXPECT_RED 3)
set(CLAIM_reset_edge_resample_suite_t_irq_CLAIM_FILE "src/mcf5307/irq.nim")
set(CLAIM_reset_edge_resample_suite_t_irq_CLAIM_TEXT "reset that clears without re-observing reds three cases of `t_irq`")
set(CLAIM_reset_edge_resample_suite_t_irq_EDITS 1)
set(CLAIM_reset_edge_resample_suite_t_irq_EDIT_1_FILE "mcf5307/irq.nim")
set(CLAIM_reset_edge_resample_suite_t_irq_EDIT_1_FIND "  mcf5307_set_irq(ctx, level, vector, autovector)\n")
set(CLAIM_reset_edge_resample_suite_t_irq_EDIT_1_REPLACE "  discard (level, vector, autovector)\n")

# THIS ENTRY'S ANCHOR IS THE `default` SPELLING, AND THAT IS A SECOND REASON
# THE SPELLING IS LOAD-BEARING. `irq.nim` gives the first - M3 retypes the
# field and a literal `false` would stop M3 compiling. Respelling this line
# also takes this entry's FIND text out of the file, and an edit whose text is
# not in the source is a refusal in this driver rather than a silent skip.
set(CLAIM_reset_edge_clear_suite_t_irq_KIND "suite-red")
set(CLAIM_reset_edge_clear_suite_t_irq_SUITE "t_irq")
set(CLAIM_reset_edge_clear_suite_t_irq_EXPECT_RED 1)
set(CLAIM_reset_edge_clear_suite_t_irq_CLAIM_FILE "src/mcf5307/irq.nim")
set(CLAIM_reset_edge_clear_suite_t_irq_CLAIM_TEXT "clearing reds exactly one (`reset_edge_clear_suite_t_irq`)")
set(CLAIM_reset_edge_clear_suite_t_irq_EDITS 1)
set(CLAIM_reset_edge_clear_suite_t_irq_EDIT_1_FILE "mcf5307/irq.nim")
set(CLAIM_reset_edge_clear_suite_t_irq_EDIT_1_FIND "  ctx.irq7Armed = default(typeof(ctx.irq7Armed))\n")
set(CLAIM_reset_edge_clear_suite_t_irq_EDIT_1_REPLACE "")

# ---------------------------------------------------------------------------
# THE DRIVER.

foreach(required IN ITEMS CLAIMS_SOURCE_DIR CLAIMS_WORK_DIR CLAIMS_NIM_COMMAND)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR
            "t_claims: ${required} is not set. This driver takes the Nim flag "
            "set from the library's own compile command, and a run with no "
            "flags would compile a different program from the one the library "
            "is built from.")
    endif()
endforeach()

# ---- THE REGISTRY PRE-FLIGHT, RUN BEFORE ANYTHING IS COMPILED ---------------
# TWO WAYS A GREEN RUN OF THIS DRIVER CAN MEAN NOTHING, both of them measured
# on this file rather than imagined for it. Neither is caught by any check
# below, because every check below is inside the claim loop and both of these
# are ways of not entering it.
#
# ONE: THE REGISTRY HAS NO FLOOR. MEASURED 2026-08-13 by the gate-4.4 judge:
# with `MCF5307_CLAIM_IDS` emptied and every claim's definitions left in place,
# this test ran the shape battery, printed `0 claims checked: 0 upheld, 0
# withheld, 0 refuted` and exited 0. The claim loop is the half of this driver
# that measures the source's own sentences; a green run that entered it zero
# times is indistinguishable from one that entered it for every claim. A pass
# that shrinks this registry walks that path with nothing
# standing at the end of it.
#
# THE FLOOR IS DERIVED AND NOT TYPED, and that choice is the point. A typed
# count is a second thing to keep true, and the hand that retires a claim
# honestly would have to lower it - the same edit, reading the same way, as the
# deletion this check exists to refuse. What is derived instead is the set of
# claims this file DEFINES: each `set(CLAIM_<id>_KIND ...)` above declares one,
# and the defined set and `MCF5307_CLAIM_IDS` must agree exactly.
#
#   An id dropped from the list while its definitions stay is the silent
#   unregistration named above.
#   A definition with no id in the list is a claim written and never run, which
#   reads as coverage from the file and is none.
#
# A CLAIM STILL LEAVES BY THE HONEST EXIT: its id AND its definitions go
# together and the retirement note records why. That edit keeps the two sets
# equal and this check says nothing about it, which is what it is for.
#
# ONE NUMBER IS TYPED AND IT IS NAMED RATHER THAN COUNTED. The derivation
# cannot know that a registry emptied of BOTH its ids and its definitions is
# wrong, so `control_equivalent` is required by name. It is not a claim about
# the core: it is the POSITIVE CONTROL that proves the equivalence path can
# reach an UPHELD verdict at all, and a registry without it can refute and can
# never be shown able to pass.
#
# THE DERIVATION READS EVERY DEFINITION FIELD AND NOT THE `_KIND` LINE ALONE.
# MEASURED 2026-08-13: with the derivation keyed on `_KIND`, removing an id
# from the list AND removing that claim's ONE `_KIND` line left its other eight
# definition lines in the file, and this check passed and printed `the registry
# defines 2 claim(s) and runs all of them`. The paragraph above says the check
# refuses "an id dropped from the list while its definitions stay", and keyed on
# one line it refused that only while THAT line stayed. Keyed on all of them, a
# silent unregistration has to delete every field of the claim - which is the
# honest exit, and which the retirement note is there to record.
#
# THE MATCH IS ANCHORED AT THE START OF A LINE, and that is a repair and not a
# tightening. MEASURED 2026-08-13: an unanchored pattern matched a
# `set(CLAIM_<id>_KIND ...)` spelling written INSIDE A COMMENT, so a worked
# example of the registry's own syntax derived a claim that does not exist and
# stopped the configure. Every real definition below starts at column zero and
# no comment line does.
file(READ "${CMAKE_CURRENT_LIST_FILE}" claims_registry_text)
set(claims_definition_fields
    "KIND|CLAIM_FILE|CLAIM_TEXT|EDITS|SUITE|EXPECT_RED|EDIT_[0-9]+_FILE|EDIT_[0-9]+_FIND|EDIT_[0-9]+_REPLACE")
string(REGEX MATCHALL
    "\nset\\(CLAIM_[A-Za-z0-9_+]+_(${claims_definition_fields}) "
    claims_definition_lines "${claims_registry_text}")
set(claims_defined "")
foreach(line IN LISTS claims_definition_lines)
    string(REGEX REPLACE
        "^\nset\\(CLAIM_(.+)_(${claims_definition_fields}) $"
        "\\1" claims_id "${line}")
    list(APPEND claims_defined "${claims_id}")
endforeach()
list(LENGTH claims_definition_lines claims_definition_line_count)
list(REMOVE_DUPLICATES claims_defined)
list(SORT claims_defined)
set(claims_listed ${MCF5307_CLAIM_IDS})
list(SORT claims_listed)
if(NOT "${claims_defined}" STREQUAL "${claims_listed}")
    message(FATAL_ERROR
        "t_claims: the registry defines [${claims_defined}] and runs "
        "[${claims_listed}], and the two do not agree. A claim DEFINED here "
        "and absent from MCF5307_CLAIM_IDS is never measured while its "
        "definition still reads as coverage; a claim LISTED here and not "
        "defined would be measured against nothing. A claim is retired by "
        "removing BOTH, with the reason in the retirement note above.")
endif()
if(NOT "control_equivalent" IN_LIST MCF5307_CLAIM_IDS)
    message(FATAL_ERROR
        "t_claims: control_equivalent is not registered. It is the POSITIVE "
        "CONTROL for the equivalence path: without it, a run of this driver "
        "has shown that it can refute a claim and has shown nothing about "
        "whether it can uphold one, and every UPHELD verdict it prints is a "
        "verdict from a mechanism never demonstrated able to produce it.")
endif()

# THE CONTROL IS REQUIRED BY NAME AND BY KIND, BECAUSE THE NAME ALONE PROTECTS
# THE NAME. MEASURED 2026-08-13 with the real compiler: changing
# `CLAIM_control_equivalent_KIND` from `equivalent` to `suite-red` and giving it
# a SUITE and an EXPECT_RED left the id in the list, left the derived sets in
# agreement, and ran the whole driver to `3 claims checked: 3 upheld` at rc 0 -
# with the `equivalent` branch never entered, no observer comparison made and no
# refutation path exercised. The sentence the check above prints describes that
# run exactly: every UPHELD verdict it printed was a verdict from a mechanism
# never demonstrated able to produce it. A control that can be turned off by
# editing one word of its own entry is not a control.
if(NOT CLAIM_control_equivalent_KIND STREQUAL "equivalent")
    message(FATAL_ERROR
        "t_claims: control_equivalent carries the kind "
        "'${CLAIM_control_equivalent_KIND}' and it must carry 'equivalent'. It "
        "is the POSITIVE CONTROL FOR THE EQUIVALENCE PATH and nothing else: "
        "under any other kind that path is never entered, and every UPHELD "
        "verdict this driver prints comes from a mechanism it has not shown "
        "able to produce one. If the control's mutation stops being equivalent, "
        "the repair is a new equivalent mutation, not a new kind for this one.")
endif()

list(LENGTH claims_defined claims_floor)
message("t_claims: the registry defines ${claims_floor} claim(s) in "
        "${claims_definition_line_count} definition line(s) and runs all "
        "of them: ${claims_listed}")

# TWO: A CLAIM CAN OUTLIVE ITS SENTENCE. Every entry carries the FILE and the
# SENTENCE it registers, and until now nothing read that file. The retirement
# note above asserts BY HAND that a sentence left the source - which is a
# sentence about sentences, and exactly the shape of claim this driver exists
# to stop taking on trust. A registered claim whose sentence is gone measures a
# mutation nothing in the tree says anything about, and reports that it upheld
# something.
#
# THE REGISTRY'S OWN DEFINITION LINES ARE REMOVED BEFORE THE LOOKUP. One entry's
# `CLAIM_FILE` is this file, and its `set(...)` line carries the text verbatim,
# so a search over the raw text would find every claim in itself and the check
# would hold for a file that says nothing. EVERY definition line is dropped and
# not the `_CLAIM_TEXT` ones alone; the prose around them is what has to carry
# the sentence.
#
# DROPPING ONLY `_CLAIM_TEXT` LEFT THE REST OF THE ENTRY AS A PARKING SPACE.
# MEASURED 2026-08-13, twice: with a claim's `CLAIM_FILE` pointed at this
# registry and its sentence deleted from the source, the sentence parked on an
# `EDIT_9_FIND` line satisfied this lookup, and so did the sentence parked as
# another entry's `CLAIM_FILE` value. Each left the check printing that every
# registered claim's sentence is still in the file that makes it, about a file
# in which no prose says it.
#
# SATISFACTION FROM A COMMENT IS CORRECT AND IS NOT A HOLE. Every sentence
# registered against a `.nim` file lives in a comment - that is where this
# project's claims are written - so a lookup that demanded the text outside a
# comment would refuse the only shape the mechanism has ever had. What is
# refused is satisfaction from THIS FILE'S OWN MACHINE-READ DEFINITIONS, which
# no reader reads as a claim.
foreach(claim IN LISTS MCF5307_CLAIM_IDS)
    set(claims_sentence_path
        "${CLAIMS_SOURCE_DIR}/${CLAIM_${claim}_CLAIM_FILE}")
    if(NOT EXISTS "${claims_sentence_path}")
        message(FATAL_ERROR
            "t_claims: ${claim} names ${CLAIM_${claim}_CLAIM_FILE} as the file "
            "that makes its claim, and that file is not in the tree.")
    endif()

    # -- THE SENTENCE HAS A FLOOR, AND WITHOUT ONE THE LOOKUP IS A FORMALITY.
    # `string(FIND)` returns 0 for an EMPTY needle, so an emptied `CLAIM_TEXT`
    # is satisfied by every file in the tree - MEASURED 2026-08-13, an entry
    # whose text was emptied and whose sentence was deleted from the source
    # passed this loop. A one-word text is the same defect with a smaller step:
    # MEASURED the same day, `move` survived the replacement of the whole
    # registered sentence, because the word it kept was one the replacement
    # happened to use.
    #
    # THE FLOOR CONSTRAINS WHAT MAY BE ADDED and is not fitted to the shortest
    # sentence already registered. THE MARGIN BETWEEN THE TWO IS NOT RECORDED
    # HERE, and the sentence that recorded it was deleted rather than corrected:
    # it named the shortest registered sentence, a later entry was registered
    # shorter on both axes, and the paragraph went on asserting a margin that
    # by then did not exist. Nothing reads a figure in a comment, so nothing
    # made it fail. The floor below is the mechanism; a claimed distance from
    # it is not.
    #
    # NO REGISTERED SENTENCE IS QUOTED IN THIS COMMENT, because a second copy
    # of a registered sentence inside this file would satisfy that entry's own
    # lookup if its CLAIM_FILE ever moved here. It is a floor and not a measure
    # of specificity: a long sentence can still be a summary, and the rule
    # against summaries is stated above and enforced by reading.
    string(LENGTH "${CLAIM_${claim}_CLAIM_TEXT}" claims_text_length)
    string(REGEX MATCHALL "[^ \t\n]+" claims_text_words
        "${CLAIM_${claim}_CLAIM_TEXT}")
    list(LENGTH claims_text_words claims_text_word_count)
    if(claims_text_length LESS 20 OR claims_text_word_count LESS 4)
        message(FATAL_ERROR
            "t_claims: ${claim} registers a CLAIM_TEXT of "
            "${claims_text_length} character(s) in ${claims_text_word_count} "
            "word(s), and the floor is 20 characters in 4 words:\n"
            "      ${CLAIM_${claim}_CLAIM_TEXT}\n"
            "    AN EMPTY TEXT IS FOUND IN EVERY FILE - `string(FIND)` returns "
            "0 for an empty needle - and a text of one or two words survives "
            "the rewriting of the sentence it is supposed to hold in place. "
            "Quote enough of the sentence that rewording the sentence removes "
            "it.")
    endif()

    # THE STRIP IS BROADER THAN THE DERIVATION, DELIBERATELY. The derivation
    # above reads a NAMED set of fields, because a stray `set(CLAIM_...)` line
    # must not invent a claim id. The strip reads ANY `set(CLAIM_...)` line,
    # because any of them is machine-read text that no reader reads as a claim -
    # and a field name this file does not yet use is exactly where a sentence
    # would be parked to survive a strip keyed on the fields it does.
    file(READ "${claims_sentence_path}" claims_sentence_text)
    string(REGEX REPLACE "\nset\\(CLAIM_[A-Za-z0-9_+]+ [^\n]*"
        "\n" claims_sentence_text "${claims_sentence_text}")
    string(FIND "${claims_sentence_text}" "${CLAIM_${claim}_CLAIM_TEXT}"
        claims_sentence_at)
    if(claims_sentence_at EQUAL -1)
        message(FATAL_ERROR
            "t_claims: ${claim} registers a sentence that "
            "${CLAIM_${claim}_CLAIM_FILE} does not contain:\n"
            "      ${CLAIM_${claim}_CLAIM_TEXT}\n"
            "    A CLAIM MAY NOT OUTLIVE ITS SENTENCE. Either the sentence was "
            "reworded - and a reworded sentence is a new claim, which this "
            "registry must quote - or it was removed, and the entry goes with "
            "it. A `CLAIM_TEXT` is QUOTED from its file and is never a summary "
            "of it, because a summary survives the removal of what it "
            "summarises.")
    endif()

    # -- A QUOTE MAY NOT STOP SHORT OF A COUNT ITS OWN SENTENCE STATES.
    # The floor above asks for enough of the sentence that rewording the
    # sentence removes the quote. For a `suite-red` entry the number IS the
    # claim, so the sentence that matters is the one stating the count - and a
    # quote that ends one word before it survives the rewriting of the only
    # word it exists to hold in place.
    #
    # BOTH DEFECTS WERE CONSTRUCTED BEFORE THIS CHECK WAS WRITTEN, not imagined
    # for it. `reset_inhibit_suite_t_irq` quoted "requires `t_irq` to go" and
    # stopped before "EXACTLY SIX"; `reset_edge_clear_suite_t_irq` quoted "a
    # reset that re-observes without" and stopped before "clearing reds exactly
    # one". Rewriting `tests/t_irq.nim` to say EXACTLY TWO and `src/mcf5307/
    # irq.nim` to say exactly nine left the configure at rc 0 and this driver
    # at `9 claims checked: 9 upheld, 0 refuted` - a production source file
    # stating a number the registry contradicts, with nothing in the tree
    # saying so.
    #
    # WHY THE RULE IS NOT "THE TEXT MUST CONTAIN THE NUMBER". That rule was
    # written first and measured against this registry before being discarded:
    # it fires on `suite-red` entries whose sentence is correct as written.
    # English states a count of one without a numeral, and this
    # project's prose does it constantly - `A11a_suite_t_irq` quotes "this case
    # and no other case in this file", `edge_flag_suite_t_irq` and
    # `edge_vector_scope_suite_t_irq` each say "THIS BLOCK", and
    # `M3_suite_t_irq`'s zero is the qualitative "a `bool` latch cannot count".
    # Demanding a numeral of those would mean editing coherent prose to
    # satisfy a checker, which inverts this file: the registry quotes the
    # source, and the source is never rewritten to fit the registry.
    #
    # WHAT IS CHECKED INSTEAD IS THE TRUNCATION ITSELF. If the quote already
    # carries its own EXPECT_RED, nothing more is asked - the rest of the
    # sentence may name any number it likes, and two entries rely on that
    # because their sentence goes on to state a SIBLING claim's count. If the
    # quote does NOT carry its count, then a number left standing between the
    # end of the quote and the end of its sentence is the truncation, and it is
    # refused. The remainder stops at the sentence's own period, so a quote
    # that already ends at one has no remainder and is never asked about.
    if(DEFINED CLAIM_${claim}_EXPECT_RED)
        set(claims_number_words
            zero one two three four five six seven eight nine ten eleven twelve)
        set(claims_red "${CLAIM_${claim}_EXPECT_RED}")
        list(LENGTH claims_number_words claims_number_word_count)
        set(claims_red_word "")
        if(claims_red LESS claims_number_word_count)
            list(GET claims_number_words ${claims_red} claims_red_word)
        endif()

        string(TOLOWER "${CLAIM_${claim}_CLAIM_TEXT}" claims_text_lower)
        set(claims_text_carries_count FALSE)
        if(claims_text_lower MATCHES "(^|[^0-9])${claims_red}([^0-9]|$)")
            set(claims_text_carries_count TRUE)
        elseif(NOT claims_red_word STREQUAL ""
               AND claims_text_lower MATCHES
                   "(^|[^a-z])${claims_red_word}([^a-z]|$)")
            set(claims_text_carries_count TRUE)
        endif()

        # THE REMAINDER OF THE SENTENCE THE QUOTE SITS IN. A quote ending at a
        # period has already reached a sentence end and leaves none.
        set(claims_quote_tail "")
        if(NOT CLAIM_${claim}_CLAIM_TEXT MATCHES "\\.$")
            string(LENGTH "${CLAIM_${claim}_CLAIM_TEXT}" claims_quote_length)
            math(EXPR claims_tail_at
                 "${claims_sentence_at} + ${claims_quote_length}")
            string(SUBSTRING "${claims_sentence_text}" ${claims_tail_at} -1
                   claims_quote_rest)
            string(FIND "${claims_quote_rest}" "." claims_tail_end)
            if(claims_tail_end EQUAL -1)
                set(claims_quote_tail "${claims_quote_rest}")
            else()
                string(SUBSTRING "${claims_quote_rest}" 0 ${claims_tail_end}
                       claims_quote_tail)
            endif()
        endif()

        # THE COMMENT PREFIXES COME OUT BEFORE THE MATCH AND BEFORE THE PRINT.
        # A tail begins at a line break in the source, so left raw it both
        # reports as an empty `then says:` with its text stranded two lines
        # below, and carries `#` and `##` runs through the match. Neither a
        # line break nor a comment marker is a number, so collapsing them
        # changes no verdict and makes the diagnostic name the word it stopped
        # before.
        string(REGEX REPLACE "[\r\n]+[ \t]*#*[ \t]*" " "
               claims_quote_tail "${claims_quote_tail}")
        string(STRIP "${claims_quote_tail}" claims_quote_tail)

        string(TOLOWER "${claims_quote_tail}" claims_quote_tail_lower)
        string(REPLACE ";" "|" claims_number_alternation
               "${claims_number_words}")
        if(NOT claims_text_carries_count
           AND claims_quote_tail_lower MATCHES
               "(^|[^a-z0-9])([0-9]+|${claims_number_alternation})([^a-z0-9]|$)")
            message(FATAL_ERROR
                "t_claims: ${claim} expects ${claims_red} red case(s), and its "
                "CLAIM_TEXT stops before a number its own sentence goes on to "
                "state:\n"
                "      quoted:    ${CLAIM_${claim}_CLAIM_TEXT}\n"
                "      then says: ${claims_quote_tail}\n"
                "    THE NUMBER IS THE CLAIM, AND A QUOTE THAT STOPS BEFORE IT "
                "SURVIVES ITS REWRITING. Extend the quote through the count in "
                "${CLAIM_${claim}_CLAIM_FILE} so that changing the number in "
                "that file takes this entry's sentence out of it. A sentence "
                "that states its count WITHOUT a numeral - \"this case and no "
                "other case\" - satisfies this check already, because it leaves "
                "no number standing after the quote.")
        endif()
    endif()
endforeach()
message("t_claims: every registered claim's sentence is still in the file that "
        "makes it")

# ---- ONE RUN AT A TIME IN THE WORK DIRECTORY --------------------------------
# `CLAIMS_WORK_DIR` is one fixed path per build tree, and every claim below
# begins by REMOVING its subdirectory and copying a fresh `src` into it. Two
# runs of this driver against the same build tree therefore delete and rewrite
# each other's trees while they are being read.
#
# MEASURED 2026-08-13 by the gate-4.4 judge: `ctest -R ^t_claims$` started
# alongside a full `ctest` over the same build tree failed with
# `file COPY cannot set permissions ... No such file or directory`, once in
# about seven attempts. A visible error is the LUCKY outcome. The same
# interleaving can land a pristine `src` on top of a mutated one BETWEEN the
# SHA-256 that confirms the mutation and the compile that measures it - and
# then the observer compiles the shipped code, the trace matches the baseline
# exactly as an equivalent mutation's would, and the claim is UPHELD with
# nothing anywhere to say the mutation was not in the tree. That outcome is
# silent, and it is the one this lock exists for.
#
# THE WHOLE RUN IS INSIDE THE LOCK AND NOT EACH CLAIM. A per-claim lock would
# leave exactly the window described above open between one claim's edits and
# the next claim's `file(REMOVE_RECURSE)`.
#
# GUARD PROCESS TIES THE LOCK TO THE PROCESS, so a run that dies takes its lock
# with it and no stale file has to be cleaned up. The timeout is generous
# because the correct behaviour of the second run is to WAIT: this driver
# compiles the observer several times and a run of a minute or two is ordinary.
file(MAKE_DIRECTORY "${CLAIMS_WORK_DIR}")
file(LOCK "${CLAIMS_WORK_DIR}" DIRECTORY GUARD PROCESS
    TIMEOUT 1800 RESULT_VARIABLE claims_lock_result)
if(NOT claims_lock_result STREQUAL "0")
    message(FATAL_ERROR
        "t_claims: could not take the lock on ${CLAIMS_WORK_DIR} within the "
        "timeout: ${claims_lock_result}. Another run of this driver is using "
        "the same build tree and has not finished. THE LOCK IS NOT AN "
        "OPTIMISATION: two runs sharing this directory overwrite each other's "
        "mutated trees, and the failure that produces is an UPHELD verdict "
        "for a mutation that was not in the tree when it was measured.")
endif()

set(claims_observer "${CLAIMS_SOURCE_DIR}/tests/t_claims.nim")

# Compile `source` against the `src` tree at `tree`, then run it. Sets
# `<out>_COMPILE_RC`, `<out>_RC` and `<out>_OUTPUT` in the caller's scope. A
# compile failure is REPORTED AND NOT FATAL here, because one caller - the
# reached-the-compiler control - requires exactly that.
function(_mcf5307_claims_run source tree tag out)
    set(binary "${CLAIMS_WORK_DIR}/${tag}.bin")
    set(cache "${CLAIMS_WORK_DIR}/${tag}.nimcache")
    # THE BINARY OF AN EARLIER RUN IS REMOVED BEFORE THE COMPILE. Without this
    # a failed compile leaves the earlier binary in place and the run executes
    # code this pass never produced.
    file(REMOVE "${binary}")
    execute_process(
        COMMAND ${CLAIMS_NIM_COMMAND} "--path:${tree}" "--nimcache:${cache}"
                "-o:${binary}" "${source}"
        RESULT_VARIABLE compile_rc
        OUTPUT_VARIABLE compile_out
        ERROR_VARIABLE compile_err)
    set(${out}_COMPILE_RC "${compile_rc}" PARENT_SCOPE)
    if(NOT compile_rc EQUAL 0)
        set(${out}_OUTPUT "${compile_out}${compile_err}" PARENT_SCOPE)
        set(${out}_RC "-1" PARENT_SCOPE)
        return()
    endif()
    if(NOT EXISTS "${binary}")
        message(FATAL_ERROR
            "t_claims: ${tag} reported a successful compile and produced no "
            "binary at ${binary}.")
    endif()
    execute_process(
        COMMAND "${binary}"
        RESULT_VARIABLE run_rc
        OUTPUT_VARIABLE run_out
        ERROR_VARIABLE run_err)
    set(${out}_RC "${run_rc}" PARENT_SCOPE)
    set(${out}_OUTPUT "${run_out}${run_err}" PARENT_SCOPE)
endfunction()

# WHERE THE REACHABILITY PROBE PUTS ITS `quit(97)` FOR ONE ANCHOR, AND WHAT IT
# PUTS IT NOWHERE FOR. `<out_kind>` is `BODY`, `BEFORE` or `REFUSED`;
# `<out_text>` is the anchor's text with the statement inserted, empty for a
# refusal; `<out_point>` names the insertion in words, which the driver PRINTS,
# so a reader of the log knows which question the verdict rests on; and
# `<out_reason>` carries why a refusal was refused.
#
# THIS FUNCTION IS A LIST OF SHAPES IT RECOGNISES, AND THE DIRECTION OF THAT
# LIST IS THE WHOLE DESIGN. Its predecessor listed the anchors that OPEN A BLOCK
# and gave every other anchor the insertion BEFORE the text, licensed by the
# sentence "any other anchor is a statement whose entry IS its execution". That
# sentence is false of Nim, and it produced a false UPHELD twice by two routes,
# both MEASURED 2026-08-13 by the gate-4.4 judge:
#
#   A ROUTINE HEADER IS NOT A STATEMENT. `proc`, `func`, `method`, `iterator`,
#   `converter`, `template` and `macro` were in no list, so a header took the
#   before-insertion - which lands at MODULE TOP LEVEL and runs at program
#   start. Measured on a `proc` with no call site anywhere in the tree: anchored
#   on the header the probe reported REACHED and the driver UPHELD the claim;
#   anchored on a statement inside that same dead body it reported UNREACHED and
#   the verdict was withheld. The UPHELD text asserts that the insertion point
#   "IS EXECUTED", which was true of module initialisation and of nothing else.
#
#   A MULTI-STATEMENT ANCHOR WAS UPHELD ON ITS FIRST LINE. An edit spanning an
#   `if` arm and its `else` arm took the body-insertion into the `if` arm,
#   reported REACHED and was UPHELD, while the `else` arm the same edit changes
#   is UNREACHED - which the judge showed by anchoring on that arm alone.
#
# EXTENDING THE KEYWORD LIST IS NOT THE REPAIR, and three earlier passes over
# this function extended it. The defect is not that a particular word was
# missing. It is that the list decided what to DENY, so every construct nobody
# had thought of arrived at the WEAKER measurement wearing the STRONGER verdict.
# The list below decides what to ALLOW, and an anchor it does not name is
# refused rather than measured weakly. A REFUSAL WITHHOLDS A VERDICT; the
# default it replaces FABRICATED one.
#
# WHAT IS RECOGNISED. The set is written out here, and the refusal message in
# `_mcf5307_claims_reachable` writes it out again for the author who never opens
# this file. TWO PROSE COPIES OF ONE SET CAN DISAGREE WITH IT AND WITH EACH
# OTHER, and that cost is taken deliberately: neither reader can act without it,
# and THE CODE BELOW IS THE ONLY AUTHORITY. A shape added to one prose copy and
# not to the code changes nothing; a shape added to the code and to neither copy
# is a repair that leaves two sentences false.
#
#   A BLOCK HEADER - `if`, `elif`, `else`, `while`, `for`, `when`, `of`, `try`,
#   `finally` or `block` - whose first line ENDS IN `:`, whose remaining lines
#   are ALL INDENTED DEEPER than that header, and whose body is a STRAIGHT-LINE
#   RUN OF STATEMENTS. AN ANCHOR THAT IS THE HEADER LINE AND NOTHING ELSE HAS NO
#   REMAINING LINES, SO IT SATISFIES BOTH RULES VACUOUSLY and takes the body
#   indentation from the next line of the FILE; the row `AG_bare_header` is that
#   cell.
#   `quit(97)` becomes the first statement of the body, so
#   the probe answers "did this branch RUN" rather than "was this header
#   reached". The deeper-lines rule is what refuses the multi-statement anchor
#   above: a line at the header's own indentation opens a SECOND branch, and one
#   insertion cannot answer for two. The straight-line rule is the third test,
#   and the paragraph below is why it is here.
#
# A BODY INSERTION ANSWERS ONLY FOR THE FIRST STATEMENT OF THE BODY IT OPENS,
# AND THE DEEPER-LINES RULE ALONE DOES NOT CONFINE AN ANCHOR TO ONE STATEMENT.
# That rule refuses a SIBLING arm, because a sibling sits at the header's own
# indentation. It cannot refuse a NESTED branch, because nested is DEEPER by
# definition - and a nested branch is a second question the one insertion does
# not answer.
#
# MEASURED 2026-08-13 on repository source, `src/mcf5307/cpu.nim`. The anchor
#
#     if takeInterrupt(ctx):
#       if ctx.halted:
#         break
#
# and the mutation `break` -> `discard` changed exactly the innermost line.
# Anchored on the INNER two lines the probe reported UNREACHED and the verdict
# was WITHHELD. Anchored on the OUTER three - the SAME mutation, producing a
# file with the same SHA-256 - it reported REACHED and the driver UPHELD the
# claim. Instrumented with echo markers in the same run: the insertion point
# executed 249 times and the mutated line executed 0 times. A second instance
# 30 lines wide behaved identically, and synthetic controls put the same false
# UPHELD under `if`, under `block` and under `for`.
#
# SO THE BODY MUST BE A STRAIGHT-LINE RUN OF STATEMENTS. If any line inside the
# body opens a block of its own, the anchor is refused and the refusal names
# the nested line.
#
# THE SIGNAL IS STRUCTURAL AND IS NOT A FOURTH KEYWORD LIST: a body line with a
# non-blank body line indented DEEPER under it opens something. Extending a
# keyword list is what three earlier passes over this function did, and the
# paragraph above them records why that is not the repair.
#
# WHAT THE SIGNAL CANNOT SEE, stated because a reader who does not know its
# blind spots will read a refusal as the only failure mode:
#
#   A ONE-LINE BLOCK INSIDE THE BODY - `if b: c = 1` - has nothing indented
#   under it, so the signal does not see it, and a mutation to that line is
#   answered for by "the enclosing branch ran". A FALSE UPHELD OF THIS SHAPE
#   REMAINS REACHABLE, and it is narrower than the one repaired here: an anchor
#   must contain such a line AND mutate it.
#
#   A BODY LINE WHOSE BLOCK BEGINS OUTSIDE THE ANCHOR - an anchor whose LAST
#   line is a header - is invisible for the same reason. It cannot produce a
#   false UPHELD: the only line of that block the anchor contains is the header
#   itself, and a header is EVALUATED whenever the body's first statement runs.
#
#   A CONTINUATION LINE reads as an opened block, because a wrapped call's
#   second line is indented deeper than its first. Such an anchor is REFUSED
#   rather than measured. That is a lost measurement and not a false verdict,
#   and it is the price of a signal that consults the file instead of a list of
#   words.
#
#   A `case` SELECTOR - `case <expression>` - takes the insertion BEFORE it, and
#   is recognised apart from the block headers because reaching a `case` IS
#   evaluating the expression an edit to that line changes. Its `of` branches
#   are anchors of their own and are in the list above.
#
#   A SIMPLE STATEMENT ON ONE LINE - an assignment or op-assignment, a call, a
#   bare expression, a single-line `var`, `let` or `const` carrying an
#   initialiser, or one of `discard`, `return`, `raise`, `inc`, `dec`, `echo`,
#   `yield`, `break`, `continue` - takes the insertion BEFORE it, which for a
#   statement is its execution. A `var`, `let` or `const` that OPENS A SECTION
#   rather than defining one name is refused by the structural test below and
#   needs no word of its own to keep it out.
#
# `except` IS NOT RECOGNISED, and its absence is a decision rather than an
# oversight. MEASURED 2026-08-13: it sat in the wrong character class of the old
# test, so a bare `except:` matched neither branch of it, took the
# before-insertion, and made the pristine tree fail to COMPILE - which the driver
# reported as "the observer does not compile", a true sentence about a cause it
# named wrongly. A shape with no control is not a shape this probe knows it
# handles correctly, and MEASURED 2026-08-13 no control in this repository
# exercises an exception handler. It is refused until a control earns it a place
# here.
#
# THE SIMPLE STATEMENT CARRIES A SECOND TEST THAT CONSULTS NO LIST OF WORDS: THE
# NEXT NON-BLANK LINE OF THE FILE MUST NOT BE INDENTED DEEPER THAN THE ANCHOR. A
# line that something is indented under OPENS something - a routine, a `type` or
# `var` section, a wrapped call - and an insertion before it measures the
# enclosing scope rather than the line. This is the test that refuses the dead
# routine header above, and it refuses it WITHOUT KNOWING THAT `proc` IS A WORD,
# which is the property the keyword list never had.
function(_mcf5307_claims_probe_point find following_indent out_text out_kind
        out_point out_reason)
    string(REGEX MATCH "^[^\n]*" first "${find}")
    string(REGEX MATCH "^[ \t]*" indent "${first}")
    string(LENGTH "${first}" first_length)
    string(LENGTH "${find}" find_length)
    string(LENGTH "${indent}" indent_length)
    math(EXPR rest_length "${find_length}-${first_length}")
    string(SUBSTRING "${find}" ${first_length} ${rest_length} rest)

    # THE REFUSAL IS WHAT THIS FUNCTION RETURNS UNLESS A RECOGNISED SHAPE
    # OVERWRITES IT. Setting it before anything else is what makes every path
    # below - including one added later by someone who has not read this
    # paragraph - fail closed.
    set(${out_text} "" PARENT_SCOPE)
    set(${out_kind} "REFUSED" PARENT_SCOPE)
    set(${out_point} "REFUSED" PARENT_SCOPE)
    set(${out_reason} "it is not one of the shapes this probe recognises"
        PARENT_SCOPE)

    # ---- a BLOCK HEADER -----------------------------------------------------
    set(header FALSE)
    if(first MATCHES "^[ \t]*(else|try|finally|block)[ \t]*:[ \t]*$"
            OR first MATCHES
               "^[ \t]*(if|elif|while|for|when|of|block)[ \t(].*:[ \t]*$")
        set(header TRUE)
    endif()
    if(header)
        # THE BODY'S INDENTATION IS READ FROM THE FILE ON BOTH PATHS - from the
        # anchor's own first body line when it carries one, and from the line
        # AFTER the anchor when it does not.
        set(body_indent "")
        set(body_indent_found FALSE)
        set(previous_line "")
        set(previous_indent -1)
        string(REPLACE ";" "\\;" walk "${rest}")
        string(REPLACE "\n" ";" walk "${walk}")
        foreach(line IN LISTS walk)
            if(line MATCHES "^[ \t]*$")
                continue()
            endif()
            string(REGEX MATCH "^[ \t]*" line_indent "${line}")
            string(LENGTH "${line_indent}" line_indent_length)
            if(NOT line_indent_length GREATER indent_length)
                set(${out_reason} "it carries a line at the header's own indentation, so it spans more than the one block that header opens and a single insertion cannot answer for both" PARENT_SCOPE)
                return()
            endif()
            # THE STRAIGHT-LINE RUN TEST. A body line with a body line indented
            # deeper under it OPENS a block, and `quit(97)` at the top of the
            # body answers for the FIRST statement of the body and for nothing
            # nested inside it.
            if(NOT previous_indent EQUAL -1
                    AND line_indent_length GREATER previous_indent)
                set(${out_reason} "its body is not a straight-line run of statements: the body line `${previous_line}` has `${line}` indented deeper under it, so that line OPENS A BLOCK OF ITS OWN. A `quit(97)` at the top of this body answers for the FIRST statement of the body and says NOTHING about whether the nested block runs, and an edit that changes a line inside that nested block would be UPHELD on the strength of the outer branch having run. Narrow the edit's FIND text to the nested branch itself" PARENT_SCOPE)
                return()
            endif()
            set(previous_line "${line}")
            set(previous_indent "${line_indent_length}")
            if(NOT body_indent_found)
                set(body_indent "${line_indent}")
                set(body_indent_found TRUE)
            endif()
        endforeach()
        # A BARE HEADER - AN ANCHOR THAT IS THE HEADER LINE AND NOTHING ELSE -
        # TAKES ITS BODY INDENT FROM THE NEXT LINE OF THE FILE. Its `rest` is
        # empty, so the walk above never runs and nothing in the anchor says
        # how deep the body it opens is indented.
        #
        # THE INDENT THIS REPLACES WAS SYNTHESISED AS `${indent}  `, WHICH IS A
        # HARDCODED ASSUMPTION THAT THE TREE UNDER MEASUREMENT INDENTS BY TWO.
        # A body indented deeper than that puts `quit(97)` at one depth and the
        # body's own first statement at another, which Nim rejects. MEASURED
        # 2026-08-13 on the `AG_bare_header` row: with the indent synthesised
        # the row is MISCOMPILE and the table records UPHELD.
        #
        # A LENGTH IS TURNED BACK INTO SPACES AND THAT LOSES NOTHING HERE: Nim
        # rejects a tab in indentation outright, so an indentation this probe
        # reads is spaces or the file does not compile at all.
        #
        # THE REFUSAL BELOW HAS NO ROW IN THE SHAPE BATTERY, AND THAT IS STATED
        # RATHER THAN LEFT OUT. It fires when the line after a bare header is
        # NOT indented deeper than it - a header at the end of a file, or a
        # header whose body sits at its own indentation - and neither is valid
        # Nim, so no anchor in a tree that COMPILES can reach it. A row would
        # have to be written in a file the observer cannot be built against,
        # which is not a measurement of this probe.
        if(NOT body_indent_found)
            if(NOT following_indent GREATER indent_length)
                set(${out_reason} "it is a header line with no body line in the anchor, and the next non-blank line of the file is not indented deeper than it, so nothing in the file says how deep the body this header opens is indented and the probe will not guess" PARENT_SCOPE)
                return()
            endif()
            string(REPEAT " " ${following_indent} body_indent)
        endif()
        set(${out_text} "${first}\n${body_indent}quit(97)${rest}" PARENT_SCOPE)
        set(${out_kind} "BODY" PARENT_SCOPE)
        set(${out_point} "as the first statement of the branch it opens"
            PARENT_SCOPE)
        set(${out_reason} "" PARENT_SCOPE)
        return()
    endif()

    # ---- a `case` SELECTOR, or a SIMPLE STATEMENT ---------------------------
    if(NOT rest STREQUAL "" AND NOT rest STREQUAL "\n")
        set(${out_reason} "it spans more than one line and its first line opens no block, so an insertion before that line would answer for that line alone" PARENT_SCOPE)
        return()
    endif()
    if(following_indent GREATER indent_length)
        set(${out_reason} "the next non-blank line of the file is indented deeper than it, so it OPENS something - a routine, a section, or a construct that wraps - and an insertion before it measures the enclosing scope and not this line" PARENT_SCOPE)
        return()
    endif()
    # A LINE THAT ENDS IN A COMMA IS AN ELEMENT OF SOMETHING. An enumeration
    # member reads exactly like an assignment, and a `quit(97)` inserted into a
    # `type` section is a syntax error rather than a measurement.
    if(first MATCHES ",[ \t]*$")
        set(${out_reason} "it ends in a comma, so it is an element of something and not a statement" PARENT_SCOPE)
        return()
    endif()

    set(shape "")
    if(first MATCHES "^[ \t]*case[ \t][^:]*$")
        set(shape "a `case` selector")
    elseif(first MATCHES
           "^[ \t]*[A-Za-z_][A-Za-z0-9_.]*(\\[[^]]*\\])?[ \t]*[-+*/]?=[^=]")
        set(shape "an assignment")
    elseif(first MATCHES
           "^[ \t]*(var|let|const)[ \t]+[A-Za-z_][A-Za-z0-9_*]*[^=]*=[^=]")
        set(shape "a single-line definition with an initialiser")
    elseif(first MATCHES "^[ \t]*[A-Za-z_][A-Za-z0-9_.]*\\(.*\\)[ \t]*$")
        set(shape "a call")
    elseif(first MATCHES "^[ \t]*[A-Za-z_][A-Za-z0-9_.]*[ \t]*$")
        set(shape "a bare expression")
    elseif(first MATCHES
           "^[ \t]*(discard|return|raise|inc|dec|echo|yield|break|continue)([ \t].*)?$")
        set(shape "a simple statement")
    endif()
    if(shape STREQUAL "")
        return()
    endif()
    set(${out_text} "${indent}quit(97)\n${find}" PARENT_SCOPE)
    set(${out_kind} "BEFORE" PARENT_SCOPE)
    set(${out_point} "before the anchor, which this probe reads as ${shape}"
        PARENT_SCOPE)
    set(${out_reason} "" PARENT_SCOPE)
endfunction()

# THE NUMBER OF TIMES `find` OCCURS IN `text`, AND THE INDENTATION OF THE NEXT
# NON-BLANK LINE AFTER IT. Both are used by the reachability probe below and by
# the shape battery, and both live here rather than inline in either, because a
# battery that guarded a COPY of the code the driver runs would guard nothing.
#
# BOTH TAKE THEIR TEXTS BY NAME. A CMake function argument holding a `;` arrives
# split into two arguments, and an anchor's text is the one place a `;` is most
# likely; a name costs one dereference and removes the hazard outright.
function(_mcf5307_claims_occurrences text_name find_name out)
    string(REPLACE "${${find_name}}" "" stripped "${${text_name}}")
    string(LENGTH "${${text_name}}" text_length)
    string(LENGTH "${stripped}" stripped_length)
    string(LENGTH "${${find_name}}" find_length)
    math(EXPR occurrences "(${text_length}-${stripped_length})/${find_length}")
    set(${out} "${occurrences}" PARENT_SCOPE)
endfunction()

# -1 when the anchor is the last thing in the file. The probe uses it to tell a
# STATEMENT from a line that OPENS something, which is the one test in it that
# consults the file rather than a list of words.
function(_mcf5307_claims_following_indent text_name find_name out)
    string(FIND "${${text_name}}" "${${find_name}}" at)
    string(LENGTH "${${find_name}}" find_length)
    string(LENGTH "${${text_name}}" text_length)
    math(EXPR after "${at}+${find_length}")
    math(EXPR tail_length "${text_length}-${after}")
    string(SUBSTRING "${${text_name}}" ${after} ${tail_length} tail)
    set(following_indent -1)
    string(REPLACE ";" "\\;" walk "${tail}")
    string(REPLACE "\n" ";" walk "${walk}")
    foreach(line IN LISTS walk)
        if(line MATCHES "^[ \t]*$")
            continue()
        endif()
        string(REGEX MATCH "^[ \t]*" line_indent "${line}")
        string(LENGTH "${line_indent}" following_indent)
        break()
    endforeach()
    set(${out} "${following_indent}" PARENT_SCOPE)
endfunction()

# ---- the REACHABILITY PROBE, and the verdict it withholds -------------------
# THE DEFECT THIS EXISTS FOR, MEASURED 2026-08-13 by the gate-4.4 judge. An
# `equivalent` claim was registered whose single edit changes `alu.nim`'s
# `if carry: sr = sr or (ccrC or ccrX)` to `if carry: sr = sr or ccrC` - a real
# semantic break of every ADDX chain. `alu.nim` is imported by `cpu.nim`, so the
# reached-the-compiler control above PASSED. The observer never calls
# `setAddCc`. The driver issued UPHELD: "none of the 225 scenarios separates
# this". THE MECHANISM MANUFACTURED EXACTLY THE KIND OF CLAIM IT EXISTS TO
# CATCH, and in the same run the identical mutation registered as `suite-red`
# drove `t_alu` one red.
#
# THE READ THAT WENT WRONG IS "the observer did not separate it" TAKEN FOR
# "the observer looked". Those are the same output. The compiler control
# separates "the file was read" from "the file was not read"; it cannot
# separate "the line ran" from "the line never ran", because a line the
# compiler read and no scenario executed produces a byte-identical trace.
#
# SO THE LINE IS ASKED DIRECTLY. Into a fresh copy of the PRISTINE tree - not
# the mutated one - `quit(97)` is inserted at the edit's own text and the
# observer is compiled and run against it. A scenario that executes the
# insertion point takes the `quit`, so the run exits 97 and its trace is a
# strict prefix of the pristine trace. An insertion point no scenario executes
# leaves the run exiting 0 with a trace identical to pristine.
#
# BOTH SIGNALS ARE REQUIRED TO AGREE, and a disagreement is fatal rather than
# resolved in either direction: an exit of 97 with an unmoved trace, or an exit
# of 0 with a moved one, means the probe is not measuring what it says it is,
# and a probe whose meaning is in doubt must not be allowed to license a
# verdict.
#
# WHERE THE `quit(97)` GOES, AND THE DISTINCTION THAT DECIDES IT. An insertion
# BEFORE the found text measures that CONTROL REACHED THE STATEMENT. For an
# `if <condition>:` anchor that is a different question from whether the edit's
# effect ran: a scenario that arrives at the `if` with the condition never true
# reaches the statement and executes nothing the branch holds. An `equivalent`
# claim over such a branch would then be UPHELD on the ground that "every line
# it edits IS reached", which restores one level down the reading this probe
# exists to remove - "the observer did not separate it" taken for "the observer
# looked".
#
# SO AN ANCHOR THAT OPENS A BLOCK IS PROBED INSIDE THE BLOCK. `quit(97)` becomes
# the FIRST STATEMENT OF THE BODY the header opens, and the probe answers "did
# this branch run" instead of "was this header reached".
#
# WHICH ANCHORS TAKE WHICH INSERTION, AND WHICH TAKE NEITHER, IS DECIDED BY
# `_mcf5307_claims_probe_point` ABOVE, WHICH RECOGNISES A NAMED SET OF SHAPES AND
# REFUSES EVERYTHING ELSE. The paragraph at that function records the two false
# UPHELDs the opposite default produced and why extending a keyword list is not
# the repair for them. Nothing here restates the set: one place to read it is one
# place for it to be wrong in.
#
# AN ANCHOR THE PROBE DOES NOT RECOGNISE IS REFUSED AND NOT MEASURED WEAKLY. A
# one-line `if <condition>: <effect>` has no body line to become the first
# statement of, and a header whose condition wraps across lines has no complete
# header line to insert after; in both, the only insertion available is the one
# that measures the weaker thing. A probe that answers a question other than the
# one the verdict needs must not license the verdict, so it stops the run and
# names the anchor instead.
#
# MEASURED 2026-08-13, the negative control that made the distinction fire. An
# `equivalent` claim was registered in a SCRATCH COPY of this file DELETING the
# nil-context guard of `mcf5307_set_irq` - `if ctx.isNil: return`, a real
# semantic break over a branch no scenario of `tests/t_claims.nim` takes. With
# the `quit(97)` before the header the probe reported REACHED and the driver
# reported `UPHELD ... every line it edits IS reached`. With it inside the
# branch the probe reported UNREACHED and the verdict was WITHHELD. A second
# control in the same copy, a trace-preserving swap of the arms of `vectorFor`'s
# one-line `if autovector: autovectorFor(level) else: vector`, was REFUSED
# rather than measured weakly. NEITHER CONTROL IS REGISTERED HERE.
#
# MEASURED 2026-08-13 against the claims that are registered here:
# `control_equivalent`'s single edit is REACHED, probed as the first statement
# of the branch it opens, so this check invalidates no claim in the registry.
function(_mcf5307_claims_reachable claim edit out out_point)
    # THE FIND TEXT IS READ FROM THE REGISTRY AND NOT PASSED IN. A CMake
    # function argument holding a `;` would arrive split into two arguments,
    # and the registry's texts are the one place a `;` is most likely.
    set(relative "${CLAIM_${claim}_EDIT_${edit}_FILE}")
    set(find "${CLAIM_${claim}_EDIT_${edit}_FIND}")
    string(LENGTH "${find}" find_length)
    set(tag "${claim}-reach-${edit}")
    set(probe "${CLAIMS_WORK_DIR}/${tag}")
    file(REMOVE_RECURSE "${probe}")
    file(COPY "${CLAIMS_SOURCE_DIR}/src" DESTINATION "${probe}")
    set(path "${probe}/src/${relative}")
    file(READ "${path}" text)

    # THE TEXT MUST OCCUR EXACTLY ONCE. At two occurrences the probe cannot say
    # WHICH of them a moved trace reached, and "one of the two is reached" does
    # not license a verdict about the other.
    _mcf5307_claims_occurrences(text CLAIM_${claim}_EDIT_${edit}_FIND
        occurrences)
    if(NOT occurrences EQUAL 1)
        message(FATAL_ERROR
            "t_claims: ${claim} edit ${edit}: its text occurs ${occurrences} "
            "times in ${relative}, and the reachability probe reports on ONE "
            "line. Narrow the edit's FIND text until it names one place.")
    endif()

    # AND IT MUST BEGIN AT A LINE BOUNDARY, because a `quit(97)` inserted into
    # the middle of a line is a syntax error and not a measurement.
    string(FIND "${text}" "${find}" at)
    if(at GREATER 0)
        math(EXPR preceding_at "${at}-1")
        string(SUBSTRING "${text}" ${preceding_at} 1 preceding)
        if(NOT preceding STREQUAL "\n")
            message(FATAL_ERROR
                "t_claims: ${claim} edit ${edit}: its text does not begin at "
                "the start of a line in ${relative}, so the reachability probe "
                "cannot insert a statement before it.")
        endif()
    endif()

    _mcf5307_claims_following_indent(text CLAIM_${claim}_EDIT_${edit}_FIND
        following_indent)

    _mcf5307_claims_probe_point("${find}" "${following_indent}" inserted kind
        point reason)
    if(kind STREQUAL "REFUSED")
        message(FATAL_ERROR
            "t_claims: ${claim} edit ${edit}: THE PROBE REFUSES THIS ANCHOR, "
            "and a refused anchor gets NO VERDICT rather than a weak one.\n"
            "  The anchor is `${find}`.\n"
            "  The reason is that ${reason}.\n"
            "  THREE SHAPES ARE RECOGNISED AND THE REST ARE REFUSED. A block "
            "header - `if`, `elif`, `else`, `while`, `for`, `when`, `of`, "
            "`try`, `finally`, `block` - whose first line ends in `:`, whose "
            "remaining lines are all indented deeper than it, and whose body is "
            "a STRAIGHT-LINE RUN OF STATEMENTS with no line inside it opening a "
            "block of its own, probed as the "
            "FIRST STATEMENT OF THE BODY. A `case <expression>` selector, and a "
            "one-line simple statement with nothing indented under it, both "
            "probed BEFORE the line. Any other anchor leaves only an insertion "
            "that measures something OTHER than whether the edited line runs, "
            "and a verdict of \"no scenario separates this\" needs the line. "
            "Narrow the edit's FIND text to one statement inside the branch, or "
            "widen it to a header line and the lines of the one block it opens. "
            "ADDING THE ANCHOR'S SHAPE TO THE RECOGNISED SET IS A REPAIR ONLY "
            "WITH A CONTROL THAT PROVES THE INSERTION MEASURES WHAT IT SAYS.")
    endif()

    # THE ANCHOR MUST ALSO END AT A LINE BOUNDARY when it opens a block, for the
    # same reason it must begin at one: the inserted statement goes on a line of
    # its own, and text following the header on the header's own line would end
    # up beside it.
    if(kind STREQUAL "BODY")
        math(EXPR following_at "${at}+${find_length}")
        string(SUBSTRING "${text}" ${following_at} 1 following)
        set(ends_a_line FALSE)
        if(find MATCHES "\n$" OR following STREQUAL "\n")
            set(ends_a_line TRUE)
        endif()
        if(NOT ends_a_line)
            message(FATAL_ERROR
                "t_claims: ${claim} edit ${edit}: its text opens a block and "
                "does not end at the end of a line in ${relative}, so the "
                "probe cannot put a statement on the line under it.")
        endif()
    endif()

    string(REPLACE "${find}" "${inserted}" text "${text}")
    file(WRITE "${path}" "${text}")

    _mcf5307_claims_run("${claims_observer}" "${probe}/src" "${tag}" PROBE)
    if(NOT PROBE_COMPILE_RC EQUAL 0)
        message(FATAL_ERROR
            "t_claims: ${claim} edit ${edit}: the observer does not compile "
            "against a pristine tree carrying `quit(97)` ${point} in "
            "${relative}. THE PROBE DID NOT RUN, so nothing here is evidence "
            "either way.\n${PROBE_OUTPUT}")
    endif()
    set(${out_point} "${point}" PARENT_SCOPE)
    set(moved TRUE)
    if(PROBE_OUTPUT STREQUAL OBSERVER_BASE_OUTPUT)
        set(moved FALSE)
    endif()
    if(PROBE_RC EQUAL 97 AND moved)
        set(${out} "REACHED" PARENT_SCOPE)
    elseif(PROBE_RC EQUAL 0 AND NOT moved)
        set(${out} "UNREACHED" PARENT_SCOPE)
    else()
        message(FATAL_ERROR
            "t_claims: ${claim} edit ${edit}: the probe's two signals "
            "disagree. The run exited ${PROBE_RC} and the trace moved: "
            "${moved}. A run that took the `quit` exits 97 and stops early; a "
            "run that did not exits 0 and prints the pristine trace. Anything "
            "else means this probe is measuring something other than whether "
            "the line runs, and a probe whose meaning is in doubt must not "
            "license a verdict.")
    endif()
endfunction()

# ONE REPORT LINE IS ONE LIST ELEMENT HOWEVER IT IS SPELLED. The entries the
# two report lists carry are built from a claim's own registered text, and a `;`
# anywhere in that text would split one entry into several: `list(LENGTH)` would
# then count report lines where the arithmetic below needs claims, and the
# upheld count - the claim count less the refuted and the withheld - could be
# driven NEGATIVE by a claim's prose. Escaping the separator at the append is
# what keeps the three printed counts arithmetic about claims.
function(_mcf5307_claims_one_element name)
    string(REPLACE ";" "\\;" escaped "${${name}}")
    set(${name} "${escaped}" PARENT_SCOPE)
endfunction()

# The number of RED cases in a suite's output. Every suite prints one
# `FAILED  <label>` line per red case.
function(_mcf5307_claims_red output out)
    string(REGEX MATCHALL "\nFAILED  " hits "\n${output}")
    list(LENGTH hits count)
    set(${out} "${count}" PARENT_SCOPE)
endfunction()

# The FIRST line at which two traces differ, one from each. A refutation that
# printed both whole traces would print four hundred lines and bury the one
# that matters.
function(_mcf5307_claims_first_difference left right out_left out_right)
    string(REPLACE ";" "\\;" left "${left}")
    string(REPLACE ";" "\\;" right "${right}")
    string(REPLACE "\n" ";" left "${left}")
    string(REPLACE "\n" ";" right "${right}")
    list(LENGTH left left_length)
    list(LENGTH right right_length)
    set(index 0)
    while(index LESS left_length AND index LESS right_length)
        list(GET left ${index} left_line)
        list(GET right ${index} right_line)
        if(NOT left_line STREQUAL right_line)
            set(${out_left} "${left_line}" PARENT_SCOPE)
            set(${out_right} "${right_line}" PARENT_SCOPE)
            return()
        endif()
        math(EXPR index "${index}+1")
    endwhile()
    set(${out_left} "<the traces agree line for line and differ in length>"
        PARENT_SCOPE)
    set(${out_right} "<lengths ${left_length} and ${right_length}>"
        PARENT_SCOPE)
endfunction()

# ---- THE SHAPE BATTERY ------------------------------------------------------
# WHAT NOTHING IN THIS REPOSITORY GUARDED BEFORE THIS SECTION EXISTED. The
# reachability probe decides, for an anchor's SHAPE, where `quit(97)` goes and
# therefore what a verdict about that anchor MEANS. Review has repeatedly
# found a shape it decided wrongly, and each time the battery that
# found it was a scratch script that went away with the session. A shape
# regression was therefore findable only by hand.
#
# THE THREE ROUTES TO A FALSE UPHELD THAT REVIEW ACTUALLY FOUND, each MEASURED
# 2026-08-13 and each a row below: a routine header taking the before-insertion,
# which lands at module top level (H); an anchor spanning a SIBLING arm, upheld
# on the arm that ran (L); and a header over a NESTED dead branch, upheld on the
# outer branch that ran (AC, paired with AC_inner).
#
# THE CELL THAT HID THE THIRD ROUTE IS WHY THE TABLE IS WRITTEN OUT AND NOT
# SAMPLED. An earlier table carried a nested branch anchored ALONE, and a span
# across siblings, and no shape for a HEADER OVER A NESTED BRANCH. The false
# UPHELD lived in exactly that untested cell. A battery is only ever evidence
# about the cells it has.
#
# WHAT WAS CUT FROM THIS TABLE ON 2026-08-13, AND WHY. The table had grown a row
# for nearly every construct the probe recognises, and a row that has never
# separated a right decision from a wrong one costs a Nim compile to say
# something the row beside it already says. What is kept is: the three routes
# above; the paired INNER anchor of the one nested-branch route, because the
# pair is what makes the outer REFUSED read as a fix rather than as a lost
# measurement; the POSITIVE CONTROL (K), because a battery that upholds nothing
# is as useless as a probe that refuses everything; one row on the FALL-THROUGH
# refusal (F), which is the path taken by an anchor matching no recognised shape
# at all and therefore the one that proves the function fails closed; the one
# MISCOMPILE row (R), which is how a LOUD residual stays visible; and the BARE
# HEADER (AG), added in the same pass and described at its own row.
#
# EVERY ROW CARRIES ITS EXPECTED OUTCOME AND A MISMATCH FAILS THE RUN. A driver
# that produced verdicts and compared them against nothing is what made each of
# the four rounds need a human to read a log.
#
# THE OUTCOMES ARE THE DRIVER'S OWN WORDS - UPHELD, WITHHELD, REFUSED - AND ONE
# MORE. `MISCOMPILE` is recorded for a shape whose insertion does not compile:
# the run is LOUD, no verdict is fabricated, and recording it is how a change to
# it becomes visible.
#
# NO MUTATION IS APPLIED, AND THAT IS AN EXACT REDUCTION RATHER THAN A SAMPLE.
# Given a mutation the observer's scenarios do not separate - which is what a
# TRACE-PRESERVING mutation is - the driver's verdict is a function of the probe
# ALONE: REFUSED when the probe refuses the anchor, WITHHELD when it reports
# UNREACHED, UPHELD when it reports REACHED. So the battery runs the probe and
# names the verdict that follows. What it therefore does NOT exercise is the
# mutated-tree compile and the reached-the-compiler control; the claim loop
# below exercises those, for whatever claims the registry carries.
#
# THE PROBE PROCS ARE INJECTED INTO A COPY AND THE REPOSITORY IS NEVER WRITTEN
# TO, as everywhere else in this file. THE INJECTION IS REQUIRED TO BE INERT and
# is not assumed to be: the observer is run against the injected tree first and
# its trace must equal the pristine trace exactly. Every REACHED/UNREACHED
# reading below is a comparison against that trace, so an injection that moved
# it would make every reading meaningless in a way nothing else would catch.
#
# EVERY ANCHOR IN THE TABLE IS SYNTHETIC AND SITS IN THE INJECTED PROCS. The
# probe does not know which file it is reading and its tests are all RELATIVE to
# the anchor's own indentation, so a synthetic anchor and a repository one of
# the same shape take the same decision. The cost of the choice is stated
# plainly: this battery would not notice repository source drifting until it no
# longer CONTAINS an instance of a shape. IT GUARDS THE PROBE AND NOT THE
# SOURCE, and the rows cut on 2026-08-13 included the two that anchored on
# `irq.nim` as it ships - which narrowed nothing, because a row that reads a
# repository line guards the probe's decision about that line's SHAPE and never
# the line.
#
# WHAT THE REPOSITORY'S OWN ANCHORS ARE GUARDED BY INSTEAD is the claim loop
# below, which reads every registered edit's FIND text out of the source it
# names and refuses to measure a claim whose text is not there.

set(MCF5307_CLAIMS_SHAPE_PROCS "type MjShapeEnum = enum
  mjShapeA = 1
  mjShapeB = 2

proc mjNeverCalled(ctx: MCF5307Ctx, n: int): int =
  var mjacc = 0
  mjacc = mjacc + 1
  if n > 100000:
    mjacc = mjacc + 1
  mjacc

proc mjProbeShapes(ctx: MCF5307Ctx, level: int): int =
  var acc = 0
  if level >= 0:
    acc = acc + 2
  else:
    acc = acc + 23
  if level > 70000: acc = acc + 17
  if level > -1:
    if level > 40000:
      acc = acc + 47
  if level > -3:
      acc = acc + 67
  acc

")
set(MCF5307_CLAIMS_SHAPE_HOST "mcf5307/irq.nim")
set(MCF5307_CLAIMS_SHAPE_HOST_ANCHOR "proc mcf5307_set_irq*(ctx: MCF5307Ctx; level: cint; vector: uint8;\n")
set(MCF5307_CLAIMS_SHAPE_CALL_FIND "  if ctx.isNil:\n    return\n")
set(MCF5307_CLAIMS_SHAPE_CALL_REPLACE
    "  if ctx.isNil:\n    return\n  discard mjProbeShapes(ctx, int(level))\n")

set(MCF5307_CLAIMS_SHAPE_IDS
    "F_one_line_if"
    "H_dead_proc_header"
    "K_last_statement"
    "L_multi_statement"
    "R_enum_member"
    "AC_if_over_nested"
    "AC_inner"
    "AG_bare_header"
    )

set(MCF5307_SHAPE_F_one_line_if_WHAT "a one-line `if <condition>: <effect>` - no body line to become the first statement of")
set(MCF5307_SHAPE_F_one_line_if_FIND "  if level > 70000: acc = acc + 17\n")
set(MCF5307_SHAPE_F_one_line_if_EXPECT "REFUSED")

set(MCF5307_SHAPE_H_dead_proc_header_WHAT "the header of a proc with no call site anywhere - a routine header is not a statement - false UPHELD route 1")
set(MCF5307_SHAPE_H_dead_proc_header_FIND "proc mjNeverCalled(ctx: MCF5307Ctx, n: int): int =\n")
set(MCF5307_SHAPE_H_dead_proc_header_EXPECT "REFUSED")

set(MCF5307_SHAPE_K_last_statement_WHAT "the last statement of a proc every scenario calls - THE POSITIVE CONTROL - a battery that upholds nothing is as useless as a probe that refuses everything")
set(MCF5307_SHAPE_K_last_statement_FIND "  acc\n")
set(MCF5307_SHAPE_K_last_statement_EXPECT "UPHELD")

set(MCF5307_SHAPE_L_multi_statement_WHAT "an edit spanning a whole two-armed `if` - a SIBLING arm - false UPHELD route 2, refused by the deeper-lines rule")
set(MCF5307_SHAPE_L_multi_statement_FIND "  if level >= 0:\n    acc = acc + 2\n  else:\n    acc = acc + 23\n")
set(MCF5307_SHAPE_L_multi_statement_EXPECT "REFUSED")

set(MCF5307_SHAPE_R_enum_member_WHAT "an enumeration member, which reads as an assignment - A KNOWN RESIDUAL RECORDED AS IT STANDS: an enumeration member reads as an assignment, so the insertion lands in a `type` section and the compile fails. The run is LOUD and no verdict is fabricated; the expectation records the behaviour so that a change to it is visible")
set(MCF5307_SHAPE_R_enum_member_FIND "  mjShapeB = 2\n")
set(MCF5307_SHAPE_R_enum_member_EXPECT "MISCOMPILE")

set(MCF5307_SHAPE_AC_if_over_nested_WHAT "an `if` header whose body is a NESTED dead `if` - false UPHELD route 3, the cell the A..V table had no shape for")
set(MCF5307_SHAPE_AC_if_over_nested_FIND "  if level > -1:\n    if level > 40000:\n      acc = acc + 47\n")
set(MCF5307_SHAPE_AC_if_over_nested_EXPECT "REFUSED")

set(MCF5307_SHAPE_AC_inner_WHAT "the NESTED dead `if` of AC anchored alone - REFUSING THIS WOULD LOSE A REAL MEASUREMENT")
set(MCF5307_SHAPE_AC_inner_FIND "    if level > 40000:\n      acc = acc + 47\n")
set(MCF5307_SHAPE_AC_inner_EXPECT "WITHHELD")

set(MCF5307_SHAPE_AG_bare_header_WHAT "a BARE HEADER WITH NO BODY LINE IN THE ANCHOR, over a body indented DEEPER THAN THE HEADER PLUS TWO - THE CELL THE TABLE HAD NO ROW FOR WHILE THE ONLY REGISTERED equivalent CLAIM RAN THROUGH IT. `CLAIM_control_equivalent_EDIT_1_FIND` is a header line and nothing else, so the walk over the anchor's remaining lines never executes and neither the deeper-lines rule nor the straight-line-run rule runs on it. The body indent was SYNTHESISED as the header's plus two, which is a hardcoded assumption about how this tree indents rather than a reading of the file; this row's body is indented by four so that the assumption is wrong for it. MEASURED 2026-08-13 with the indent synthesised: MISCOMPILE, `invalid indentation`, against the UPHELD recorded here")
set(MCF5307_SHAPE_AG_bare_header_FIND "  if level > -3:")
set(MCF5307_SHAPE_AG_bare_header_EXPECT "UPHELD")

# ---- THE TABLE'S OWN FLOOR --------------------------------------------------
# THE BATTERY HAD NO FLOOR AND COULD THEREFORE SHRINK IN SILENCE, which is the
# defect the claim registry's pre-flight above exists for, in the half of this
# file that pre-flight does not read. MEASURED 2026-08-13 on this file with the
# rows already cut: one id removed from `MCF5307_CLAIMS_SHAPE_IDS` with its
# three definitions left in place ran to exit 0 and printed `7 probe shapes
# agreed with the outcomes recorded for them`. The row that went was the
# WITHHELD control, so the run that lost it reported nothing but a smaller
# number - and a number nothing compares against is not a report.
#
# THE FLOOR IS DERIVED AND NOT TYPED, for the reason the registry's is: a typed
# count is a second thing to keep true, and the hand that retires a row
# honestly would have to lower it - the same edit, reading the same way, as the
# deletion this check refuses. What is derived is the set of rows this file
# DEFINES: each `WHAT`, `FIND` and `EXPECT` line declares one, and the defined
# set and `MCF5307_CLAIMS_SHAPE_IDS` must agree exactly.
#
#   An id dropped from the list while its definitions stay is the silent shrink
#   measured above.
#   A definition with no id in the list is a row written and never run, which
#   reads from the file as a cell the battery has and is none.
#
# A ROW STILL LEAVES BY THE HONEST EXIT: its id AND its three definitions go
# together, and the record of what was cut sits above the table. That edit
# keeps the two sets equal and this check says nothing about it.
#
# THE DERIVATION READS ALL THREE FIELDS AND NOT ONE OF THEM, and the registry
# pre-flight records what keying on a single line cost there: a silent
# unregistration then had to delete only that one line. Keyed on all three, it
# has to delete the whole row, which is the honest exit.
#
# THE MATCH IS ANCHORED AT THE START OF A LINE. Every definition below starts at
# column zero, no comment line does, and the two patterns this check is built
# from are written on continuation lines for exactly that reason - an unanchored
# pattern would derive a row from a worked example of the table's own syntax.
#
# ONE ROW IS REQUIRED BY NAME AND BY OUTCOME, because the derivation cannot know
# that a table emptied of BOTH its ids and its definitions is wrong. It is the
# POSITIVE CONTROL: without a row the probe UPHOLDS, this battery can show that
# it refuses and can never be shown able to reach a verdict at all - and every
# REFUSED row it prints would then be a refusal from a mechanism that refuses
# everything. The outcome is checked with the name for the reason the claim
# registry checks `control_equivalent`'s KIND with its id: a control that can be
# turned off by editing one word of its own row is not a control.
file(READ "${CMAKE_CURRENT_LIST_FILE}" claims_shape_registry_text)
set(claims_shape_definition_fields "WHAT|FIND|EXPECT")
string(REGEX MATCHALL
    "\nset\\(MCF5307_SHAPE_[A-Za-z0-9_+]+_(${claims_shape_definition_fields}) "
    claims_shape_definition_lines "${claims_shape_registry_text}")
set(claims_shapes_defined "")
foreach(line IN LISTS claims_shape_definition_lines)
    string(REGEX REPLACE
        "^\nset\\(MCF5307_SHAPE_(.+)_(${claims_shape_definition_fields}) $"
        "\\1" claims_shape_id "${line}")
    list(APPEND claims_shapes_defined "${claims_shape_id}")
endforeach()
list(LENGTH claims_shape_definition_lines claims_shape_definition_line_count)
list(REMOVE_DUPLICATES claims_shapes_defined)
list(SORT claims_shapes_defined)
set(claims_shapes_listed ${MCF5307_CLAIMS_SHAPE_IDS})
list(SORT claims_shapes_listed)
if(NOT "${claims_shapes_defined}" STREQUAL "${claims_shapes_listed}")
    message(FATAL_ERROR
        "t_claims: the shape table defines [${claims_shapes_defined}] and runs "
        "[${claims_shapes_listed}], and the two do not agree. A row DEFINED "
        "here and absent from MCF5307_CLAIMS_SHAPE_IDS is never run while its "
        "definition still reads as a cell this battery has; a row LISTED here "
        "and not defined would be run against nothing. A row is cut by "
        "removing BOTH, with the reason in the record above the table.")
endif()
if(NOT "K_last_statement" IN_LIST MCF5307_CLAIMS_SHAPE_IDS)
    message(FATAL_ERROR
        "t_claims: K_last_statement is not in MCF5307_CLAIMS_SHAPE_IDS. It is "
        "the POSITIVE CONTROL for this battery: without it, a run has shown "
        "that the probe can REFUSE an anchor and has shown nothing about "
        "whether it can reach a verdict, and every REFUSED row it prints is a "
        "refusal from a mechanism never demonstrated able to do anything else.")
endif()
if(NOT MCF5307_SHAPE_K_last_statement_EXPECT STREQUAL "UPHELD")
    message(FATAL_ERROR
        "t_claims: K_last_statement records the outcome "
        "'${MCF5307_SHAPE_K_last_statement_EXPECT}' and it must record "
        "'UPHELD'. It is the POSITIVE CONTROL and nothing else: under any "
        "other recorded outcome the battery no longer requires the probe to "
        "reach a verdict, and the check above protects only the name. If this "
        "row's anchor stops being one the probe upholds, the repair is an "
        "anchor that is, not a new outcome for this one.")
endif()
list(LENGTH claims_shapes_defined claims_shape_floor)
message("t_claims: the shape table defines ${claims_shape_floor} shape(s) in "
        "${claims_shape_definition_line_count} definition line(s) and runs all "
        "of them: ${claims_shapes_listed}")

# Runs every shape and appends ONE entry to `<out_failures>` per shape whose
# outcome is not the one recorded for it. A FAILURE IS COLLECTED AND NOT FATAL,
# for the reason the claim loop below collects its refutations: a run that
# stopped at the first would hide which of the remaining shapes still hold.
function(_mcf5307_claims_shape_battery out_failures out_ran)
    set(failures "")
    set(ran 0)
    set(tree "${CLAIMS_WORK_DIR}/shape-battery")
    file(REMOVE_RECURSE "${tree}")
    file(COPY "${CLAIMS_SOURCE_DIR}/src" DESTINATION "${tree}")
    set(host "${tree}/src/${MCF5307_CLAIMS_SHAPE_HOST}")
    file(READ "${host}" injected)

    # THE HOST ANCHOR MUST OCCUR ONCE, AND IT IS UNIQUE BY CONSTRUCTION. It is
    # the first line of `mcf5307_set_irq`'s own signature, so it carries the
    # proc's name; a second copy of it would be a redefinition the Nim compiler
    # refuses before this driver ever runs. At zero the procs are not injected
    # and every shape below would report on an anchor that is not in the file.
    _mcf5307_claims_occurrences(injected MCF5307_CLAIMS_SHAPE_HOST_ANCHOR count)
    if(NOT count EQUAL 1)
        message(FATAL_ERROR
            "t_claims: the shape battery's host anchor occurs ${count} time(s) "
            "in ${MCF5307_CLAIMS_SHAPE_HOST}, and it must occur exactly once:\n"
            "      ${MCF5307_CLAIMS_SHAPE_HOST_ANCHOR}\n"
            "    THE ANCHOR IN `tests/t_claims.cmake` NO LONGER IDENTIFIES ONE "
            "PLACE - NARROW IT. It is `MCF5307_CLAIMS_SHAPE_HOST_ANCHOR` in "
            "this file, and it must match the signature of the one proc the "
            "probe procs are injected in front of. This is a fault in the "
            "anchor and not in the source that moved under it.")
    endif()
    # AND THE PROCS MUST NOT BE THERE ALREADY. Injecting a second copy defines
    # every one of their names twice, and the compile then fails with a
    # redefinition error that names a symbol and not a cause. MEASURED
    # 2026-08-13: a scratch harness that injects the same procs before invoking
    # this driver produced exactly that, once per shape.
    _mcf5307_claims_occurrences(injected MCF5307_CLAIMS_SHAPE_PROCS count)
    if(NOT count EQUAL 0)
        message(FATAL_ERROR
            "t_claims: the shape battery's probe procs are ALREADY in "
            "${MCF5307_CLAIMS_SHAPE_HOST} (${count} time(s)). Injecting them "
            "again would define every one of their names twice. Either the "
            "source tree carries them, or a caller injected them before "
            "invoking this driver.")
    endif()
    string(REPLACE "${MCF5307_CLAIMS_SHAPE_HOST_ANCHOR}"
        "${MCF5307_CLAIMS_SHAPE_PROCS}${MCF5307_CLAIMS_SHAPE_HOST_ANCHOR}"
        injected "${injected}")

    # THE CALL ANCHOR IS RESOLVED INSIDE THE HOST PROC AND NOWHERE ELSE, AND
    # THAT IS WHAT MAKES IT UNIQUE BY CONSTRUCTION RATHER THAN BY LUCK. Its
    # text is an ordinary Nim nil guard - `if ctx.isNil:` and `return` - which
    # is the most reproducible pair of lines this codebase writes. Matched over
    # the whole file it collided the first time a SECOND exported proc in
    # `irq.nim` guarded its context, and it will collide again on the third.
    #
    # THE COLLISION WAS CONSTRUCTED AND WATCHED BEFORE THIS WAS WRITTEN.
    # Adding that guard to the head of `resetInterruptEdge` - a hardening with
    # no behaviour change - took this driver to rc 8 with a message reading
    # that the battery could not place its probe procs. NOTHING IN IT NAMED THE
    # ANCHOR AS THE THING TO FIX, so the repair it invites is reverting the
    # guard: a test mechanism vetoing a correct change to production source.
    #
    # THE HOST ANCHOR IS THE PROC'S OWN SIGNATURE and cannot be duplicated, so
    # searching only the text that FOLLOWS it and taking the FIRST match names
    # "the nil guard at the head of `mcf5307_set_irq`" and can name nothing
    # else. Every other proc in the file may now guard its context freely.
    string(FIND "${injected}" "${MCF5307_CLAIMS_SHAPE_HOST_ANCHOR}"
           claims_host_at)
    string(LENGTH "${MCF5307_CLAIMS_SHAPE_HOST_ANCHOR}" claims_host_length)
    math(EXPR claims_body_at "${claims_host_at} + ${claims_host_length}")
    string(SUBSTRING "${injected}" 0 ${claims_body_at} claims_host_head)
    string(SUBSTRING "${injected}" ${claims_body_at} -1 claims_host_body)

    string(FIND "${claims_host_body}" "${MCF5307_CLAIMS_SHAPE_CALL_FIND}"
           claims_call_at)
    if(claims_call_at EQUAL -1)
        message(FATAL_ERROR
            "t_claims: the shape battery's call anchor does not appear "
            "anywhere after the host proc's signature in "
            "${MCF5307_CLAIMS_SHAPE_HOST}:\n"
            "      ${MCF5307_CLAIMS_SHAPE_CALL_FIND}\n"
            "    THE ANCHOR IN `tests/t_claims.cmake` NO LONGER MATCHES THE "
            "SOURCE - REPAIR IT. It is `MCF5307_CLAIMS_SHAPE_CALL_FIND` in "
            "this file, and the probe call is injected directly after it, so "
            "it must match a statement the host proc reaches on every call. "
            "Without it the battery would report on shapes it never placed.")
    endif()
    string(SUBSTRING "${claims_host_body}" 0 ${claims_call_at}
           claims_call_before)
    string(LENGTH "${MCF5307_CLAIMS_SHAPE_CALL_FIND}" claims_call_length)
    math(EXPR claims_call_end "${claims_call_at} + ${claims_call_length}")
    string(SUBSTRING "${claims_host_body}" ${claims_call_end} -1
           claims_call_after)
    # ONE QUOTED ARGUMENT, AND THAT IS NOT FORMATTING. Splitting this `set()`
    # across two arguments makes `injected` a LIST, and CMake joins a list with
    # `;` when it is expanded back into a string - which lands a stray
    # separator in the middle of the file and mangles the semicolons in this
    # host proc's own signature.
    set(injected "${claims_host_head}${claims_call_before}${MCF5307_CLAIMS_SHAPE_CALL_REPLACE}${claims_call_after}")
    file(WRITE "${host}" "${injected}")

    # THE INERTNESS CONTROL. Every reading below is a comparison against this
    # trace, so an injection that moved it would make all of them meaningless.
    _mcf5307_claims_run("${claims_observer}" "${tree}/src" "shape-battery-base"
        BATTERY_BASE)
    if(NOT BATTERY_BASE_COMPILE_RC EQUAL 0)
        message(FATAL_ERROR
            "t_claims: the shape battery's injected tree does not compile.\n"
            "${BATTERY_BASE_OUTPUT}")
    endif()
    if(NOT BATTERY_BASE_RC EQUAL 0)
        message(FATAL_ERROR
            "t_claims: the shape battery's injected tree ran the observer to "
            "exit ${BATTERY_BASE_RC}.\n${BATTERY_BASE_OUTPUT}")
    endif()
    if(NOT BATTERY_BASE_OUTPUT STREQUAL OBSERVER_BASE_OUTPUT)
        message(FATAL_ERROR
            "t_claims: the shape battery's probe procs are NOT INERT: the "
            "observer's trace against the injected tree differs from its trace "
            "against the pristine tree. Every REACHED/UNREACHED reading the "
            "battery takes is a comparison against that trace, so no shape "
            "below would mean what it says.")
    endif()

    foreach(shape IN LISTS MCF5307_CLAIMS_SHAPE_IDS)
        set(find "${MCF5307_SHAPE_${shape}_FIND}")
        set(expect "${MCF5307_SHAPE_${shape}_EXPECT}")

        # A SHAPE WHOSE ANCHOR IS NOT IN THE FILE IS A FAILURE AND NOT A SKIP.
        # A silently dropped row is a cell the battery reports on and does not
        # have, which is the defect the whole section exists for.
        _mcf5307_claims_occurrences(injected MCF5307_SHAPE_${shape}_FIND count)
        if(NOT count EQUAL 1)
            set(entry
                "${shape}: its anchor occurs ${count} times in the injected ${MCF5307_CLAIMS_SHAPE_HOST} and the battery reports on ONE. The table in tests/t_claims.cmake is stale with respect to the probe procs it anchors in.")
            _mcf5307_claims_one_element(entry)
            list(APPEND failures "${entry}")
            continue()
        endif()

        _mcf5307_claims_following_indent(injected MCF5307_SHAPE_${shape}_FIND
            following_indent)
        _mcf5307_claims_probe_point("${find}" "${following_indent}" inserted
            kind point reason)

        if(kind STREQUAL "REFUSED")
            set(actual "REFUSED")
            set(detail "${reason}")
        else()
            string(REPLACE "${find}" "${inserted}" probed "${injected}")
            file(WRITE "${host}" "${probed}")
            _mcf5307_claims_run("${claims_observer}" "${tree}/src"
                "shape-${shape}" PROBED)
            file(WRITE "${host}" "${injected}")
            math(EXPR ran "${ran}+1")
            set(detail "probed ${point}")
            if(NOT PROBED_COMPILE_RC EQUAL 0)
                set(actual "MISCOMPILE")
            elseif(PROBED_RC EQUAL 97
                    AND NOT PROBED_OUTPUT STREQUAL BATTERY_BASE_OUTPUT)
                set(actual "UPHELD")
            elseif(PROBED_RC EQUAL 0
                    AND PROBED_OUTPUT STREQUAL BATTERY_BASE_OUTPUT)
                set(actual "WITHHELD")
            else()
                # The probe's two signals disagree. The driver calls that fatal;
                # here it is one shape's outcome, so the remaining shapes are
                # still measured and the report names it.
                set(actual "DISAGREE")
            endif()
        endif()

        if(actual STREQUAL "${expect}")
            message("t_claims:   shape ${shape}: ${actual}, as recorded")
        else()
            message("t_claims:   shape ${shape}: ${actual}, and ${expect} is "
                    "recorded for it")
            set(entry
                "${shape} is ${actual} and the table records ${expect}. The shape is ${MCF5307_SHAPE_${shape}_WHAT}. The probe said: ${detail}. EITHER THE PROBE HAS CHANGED WHAT IT MEASURES OR THE TABLE IS WRONG, and the second is a repair only when the first has been ruled out: this table is what stands between a changed probe and a verdict whose meaning has quietly changed with it.")
            _mcf5307_claims_one_element(entry)
            list(APPEND failures "${entry}")
        endif()
    endforeach()

    set(${out_failures} "${failures}" PARENT_SCOPE)
    set(${out_ran} "${ran}" PARENT_SCOPE)
endfunction()

# ---- the baselines, measured once and shared by every claim -----------------
# A CLAIM THAT EXPECTS 0 RED AFTER A MUTATION SAYS NOTHING UNLESS THE SAME RUN
# IS 0 RED BEFORE IT, and a claim that expects an identical trace says nothing
# unless the trace can be produced at all.
message("t_claims: the pristine tree is ${CLAIMS_SOURCE_DIR}/src")

_mcf5307_claims_run("${claims_observer}" "${CLAIMS_SOURCE_DIR}/src"
    "observer-baseline" OBSERVER_BASE)
if(NOT OBSERVER_BASE_COMPILE_RC EQUAL 0)
    message(FATAL_ERROR
        "t_claims: the observer does not compile against the pristine tree.\n"
        "${OBSERVER_BASE_OUTPUT}")
endif()
if(NOT OBSERVER_BASE_RC EQUAL 0)
    message(FATAL_ERROR
        "t_claims: the observer exited ${OBSERVER_BASE_RC} against the "
        "pristine tree.\n${OBSERVER_BASE_OUTPUT}")
endif()
if(NOT OBSERVER_BASE_OUTPUT MATCHES "t_claims: observer complete")
    message(FATAL_ERROR
        "t_claims: the observer exited 0 against the pristine tree and did "
        "not print its completion line, so it did not run its whole scenario "
        "space. A trace compared against a partial trace is a comparison of "
        "two silences.")
endif()
string(REGEX MATCHALL "\nSCENARIO " claims_scenarios "\n${OBSERVER_BASE_OUTPUT}")
list(LENGTH claims_scenarios claims_scenario_count)
message("t_claims: the observer ran ${claims_scenario_count} scenarios against "
        "the pristine tree")

# ---- the shape battery, run BEFORE the claims -------------------------------
# IT RUNS BEFORE THE CLAIM LOOP AND ITS RESULT IS CARRIED TO THE END. A battery
# placed after the final report would never run in a tree where a claim is
# refuted, and a refutation is an outcome this driver exists to produce.
list(LENGTH MCF5307_CLAIMS_SHAPE_IDS claims_shape_count)
_mcf5307_claims_shape_battery(claims_battery_failures claims_shapes_compiled)
list(LENGTH claims_battery_failures claims_battery_failure_count)
message("t_claims: the shape battery ran ${claims_shape_count} shapes "
        "(${claims_shapes_compiled} of them needed a compile) and "
        "${claims_battery_failure_count} of them are not the outcome recorded "
        "for them")

# ---- every claim ------------------------------------------------------------
# A REFUTATION DOES NOT STOP THE RUN. Every claim is checked and the refuted
# ones are reported together at the end, because a driver that stopped at the
# first would hide from the reader which of the remaining claims still hold -
# and the pass that repairs the first one would then discover the second.
set(claims_refuted "")

# A WITHHELD VERDICT IS ITS OWN OUTCOME AND IS NOT AN UPHELD ONE. It is counted
# apart from the refutations because it says something different: not "the claim
# is false" but "this driver cannot say, and the run that looks like evidence
# for it is not evidence for it". Both end the run non-zero, because a claim the
# mechanism cannot check is a claim the mechanism must not appear to have
# checked - and a merely-printed note would keep its silence green for as long
# as nobody read the log.
set(claims_withheld "")

# HOW MANY CLAIMS ACTUALLY ENTERED THE EQUIVALENCE PATH. The pre-flight above
# requires the positive control to CARRY the kind `equivalent`; this counts how
# many claims the loop actually RAN through that branch. The two are a pair on
# purpose: the first is a statement about the registry's text and the second is
# a statement about this run, and a future edit that keeps the text and stops
# reaching the branch would satisfy the first alone.
set(claims_equivalent_ran 0)

foreach(claim IN LISTS MCF5307_CLAIM_IDS)
    set(kind "${CLAIM_${claim}_KIND}")
    set(work "${CLAIMS_WORK_DIR}/${claim}")
    file(REMOVE_RECURSE "${work}")
    file(COPY "${CLAIMS_SOURCE_DIR}/src" DESTINATION "${work}")

    message("t_claims: ${claim} (${kind}) - ${CLAIM_${claim}_CLAIM_FILE} "
            "claims: ${CLAIM_${claim}_CLAIM_TEXT}")

    # -- apply the edits, and PROVE that each one changed its file ------------
    set(touched "")
    set(edit 1)
    while(edit LESS_EQUAL CLAIM_${claim}_EDITS)
        set(relative "${CLAIM_${claim}_EDIT_${edit}_FILE}")
        set(path "${work}/src/${relative}")
        if(NOT EXISTS "${path}")
            message(FATAL_ERROR
                "t_claims: ${claim} edit ${edit} names ${relative}, which the "
                "copied tree does not carry.")
        endif()
        file(SHA256 "${path}" before)
        file(READ "${path}" text)
        string(FIND "${text}" "${CLAIM_${claim}_EDIT_${edit}_FIND}" at)
        if(at EQUAL -1)
            message(FATAL_ERROR
                "t_claims: ${claim} edit ${edit} did not find its text in "
                "${relative}. THE MUTATION WOULD HAVE APPLIED TO NOTHING, and "
                "a mutation that applies to nothing produces the same result "
                "as an equivalent one. The registry in tests/t_claims.cmake "
                "is stale with respect to the source.")
        endif()
        string(REPLACE "${CLAIM_${claim}_EDIT_${edit}_FIND}"
                       "${CLAIM_${claim}_EDIT_${edit}_REPLACE}" text "${text}")
        file(WRITE "${path}" "${text}")
        file(SHA256 "${path}" after)
        if(before STREQUAL after)
            message(FATAL_ERROR
                "t_claims: ${claim} edit ${edit} left ${relative} byte for "
                "byte as it was. NO COUNT IS REPORTED FOR AN UNCHANGED FILE.")
        endif()
        message("t_claims:   edit ${edit} ${relative}\n"
                "              before ${before}\n"
                "              after  ${after}")
        list(APPEND touched "${relative}")
        math(EXPR edit "${edit}+1")
    endwhile()
    list(REMOVE_DUPLICATES touched)

    if(kind STREQUAL "equivalent")
        set(claims_program "${claims_observer}")
    else()
        set(claims_program
            "${CLAIMS_SOURCE_DIR}/tests/${CLAIM_${claim}_SUITE}.nim")
    endif()

    # -- the reached-the-compiler control -------------------------------------
    # A GUARD THAT CANNOT FIRE IS THE DEFECT THIS CONTROL EXISTS FOR. For every
    # file the mutation edited, a second copy of that file is given a
    # deliberate syntax error and the same program is compiled again: the
    # compile MUST fail. If it succeeds, the compiler is not reading the file
    # the mutation edited, and every measurement below is about a program the
    # mutation never entered.
    foreach(relative IN LISTS touched)
        set(control "${CLAIMS_WORK_DIR}/${claim}-control")
        file(REMOVE_RECURSE "${control}")
        file(COPY "${work}/src" DESTINATION "${control}")
        file(APPEND "${control}/src/${relative}"
            "\nlet mcf5307ClaimsReachedTheCompiler = ((((\n")
        _mcf5307_claims_run("${claims_program}" "${control}/src"
            "${claim}-control" CONTROL)
        if(CONTROL_COMPILE_RC EQUAL 0)
            message(FATAL_ERROR
                "t_claims: ${claim}: a deliberate syntax error appended to "
                "${relative} COMPILED. The program under measurement does not "
                "read that file, so this claim's mutation never reached the "
                "compiler and its result means nothing.")
        endif()
        message("t_claims:   reached-the-compiler control for ${relative}: "
                "the compile failed, as it must")
    endforeach()

    # -- the claim itself -----------------------------------------------------
    if(kind STREQUAL "equivalent")
        math(EXPR claims_equivalent_ran "${claims_equivalent_ran}+1")
        _mcf5307_claims_run("${claims_observer}" "${work}/src"
            "${claim}-mutant" MUTANT)
        if(NOT MUTANT_COMPILE_RC EQUAL 0)
            message(FATAL_ERROR
                "t_claims: ${claim}: the mutated tree does not compile. A "
                "mutation that does not compile is not an equivalent one.\n"
                "${MUTANT_OUTPUT}")
        endif()
        if(NOT MUTANT_RC EQUAL 0)
            message(FATAL_ERROR
                "t_claims: ${claim}: the observer exited ${MUTANT_RC} against "
                "the mutated tree.\n${MUTANT_OUTPUT}")
        endif()
        if(MUTANT_OUTPUT STREQUAL OBSERVER_BASE_OUTPUT)
            # THE REACHABILITY PROBE RUNS ONLY HERE, on the path that is about
            # to issue a verdict of "no scenario separates it". On the refuting
            # path it is not needed and is not run: a scenario that separates
            # the mutation IS a witness that the mutation is reached, and a
            # claim already false is not made falser by a second measurement.
            set(unreached "")
            set(edit 1)
            while(edit LESS_EQUAL CLAIM_${claim}_EDITS)
                _mcf5307_claims_reachable("${claim}" "${edit}" reach
                    reach_point)
                message("t_claims:   reachability probe, edit ${edit} "
                        "${CLAIM_${claim}_EDIT_${edit}_FILE}: ${reach} "
                        "(probed ${reach_point})")
                if(reach STREQUAL "UNREACHED")
                    list(APPEND unreached
                        "edit ${edit} in ${CLAIM_${claim}_EDIT_${edit}_FILE} (probed ${reach_point})")
                endif()
                math(EXPR edit "${edit}+1")
            endwhile()
            if(NOT unreached STREQUAL "")
                string(REPLACE ";" ", " unreached_text "${unreached}")
                message("t_claims:   WITHHELD")
                set(entry
                    "${claim}: WITHHELD, NOT UPHELD. ${CLAIM_${claim}_CLAIM_FILE} claims: ${CLAIM_${claim}_CLAIM_TEXT}. The observer's ${claims_scenario_count} scenarios produced the same trace before and after the mutation, and they would have produced the same trace whatever the mutation said, because no scenario EXECUTES ${unreached_text}: a `quit(97)` inserted there against the PRISTINE tree left the run exiting 0 with the trace unmoved. An insertion point nothing executes separates nothing, so this run is not evidence for the claim and must not be recorded as it. The two honest repairs are to give the observer a scenario that executes it, or to stop registering this claim as `equivalent` and register what the suites actually measure instead. RELAXING THIS CHECK IS NOT ONE OF THEM.")
                _mcf5307_claims_one_element(entry)
                list(APPEND claims_withheld "${entry}")
            else()
                message("t_claims:   UPHELD: none of the "
                        "${claims_scenario_count} scenarios separates this "
                        "mutation from the shipped code, and the probe's "
                        "insertion point for every edit IS EXECUTED by at "
                        "least one of them - which for an edit that opens a "
                        "branch is the BRANCH RUNNING and not the header "
                        "being reached. THAT IS NOT A PROOF OF EQUIVALENCE - "
                        "it is the absence of a witness in a bounded space.")
            endif()
        else()
            _mcf5307_claims_first_difference("${OBSERVER_BASE_OUTPUT}"
                "${MUTANT_OUTPUT}" shipped mutated)
            message("t_claims:   REFUTED")
            set(entry
                "${claim}: REFUTED. ${CLAIM_${claim}_CLAIM_FILE} claims: ${CLAIM_${claim}_CLAIM_TEXT}. A scenario separates the mutation from the shipped code, so the state it changes IS reachable through the public interface:\n      shipped: ${shipped}\n      mutated: ${mutated}\n    The claim is false, and no rewording of it is a repair. Either the mutation is wrong for the core, or the file must stop claiming what this scenario disproves.")
            _mcf5307_claims_one_element(entry)
            list(APPEND claims_refuted "${entry}")
        endif()
    elseif(kind STREQUAL "suite-red")
        set(suite "${CLAIM_${claim}_SUITE}")

        _mcf5307_claims_run("${claims_program}" "${CLAIMS_SOURCE_DIR}/src"
            "${claim}-suite-baseline" SUITE_BASE)
        if(NOT SUITE_BASE_COMPILE_RC EQUAL 0)
            message(FATAL_ERROR
                "t_claims: ${claim}: ${suite} does not compile against the "
                "pristine tree.\n${SUITE_BASE_OUTPUT}")
        endif()
        _mcf5307_claims_red("${SUITE_BASE_OUTPUT}" base_red)
        if(NOT base_red EQUAL 0)
            message(FATAL_ERROR
                "t_claims: ${claim}: ${suite} is ${base_red} RED against the "
                "PRISTINE tree. A count measured after a mutation says "
                "nothing while the count before it is not zero.")
        endif()

        _mcf5307_claims_run("${claims_program}" "${work}/src"
            "${claim}-suite-mutant" SUITE_MUTANT)
        if(NOT SUITE_MUTANT_COMPILE_RC EQUAL 0)
            message(FATAL_ERROR
                "t_claims: ${claim}: ${suite} does not compile against the "
                "mutated tree. A mutation that does not compile is not a "
                "mutation this suite failed to catch.\n${SUITE_MUTANT_OUTPUT}")
        endif()
        if(NOT SUITE_MUTANT_OUTPUT MATCHES "cases passed|cases failed")
            message(FATAL_ERROR
                "t_claims: ${claim}: ${suite} against the mutated tree "
                "printed no summary line, so it did not run to the end and "
                "its red count is not a count of anything.")
        endif()
        _mcf5307_claims_red("${SUITE_MUTANT_OUTPUT}" mutant_red)
        if(NOT mutant_red EQUAL CLAIM_${claim}_EXPECT_RED)
            message("t_claims:   REFUTED")
            set(entry
                "${claim}: ${suite} went ${mutant_red} RED and the registry expects ${CLAIM_${claim}_EXPECT_RED}. ${CLAIM_${claim}_CLAIM_FILE} claims: ${CLAIM_${claim}_CLAIM_TEXT}. A count that has moved is a fact about the suite, and it belongs in the file that claims it.")
            _mcf5307_claims_one_element(entry)
            list(APPEND claims_refuted "${entry}")
        else()
            message("t_claims:   UPHELD: ${suite} is ${base_red} red before "
                    "the mutation and ${mutant_red} red after it, and the "
                    "registry expects ${CLAIM_${claim}_EXPECT_RED}")
        endif()
    else()
        message(FATAL_ERROR
            "t_claims: ${claim} carries the unknown kind '${kind}'.")
    endif()
endforeach()

if(claims_equivalent_ran LESS 1)
    message(FATAL_ERROR
        "t_claims: no claim entered the equivalence path in this run. The "
        "observer comparison, the reachability probe and the refutation that "
        "path carries are the half of this driver that measures an ABSOLUTE "
        "claim, and a run that never entered it has shown only that the "
        "suite-relative half works. `control_equivalent` exists to keep this "
        "impossible; if this fires, the registry has been edited so that it no "
        "longer does.")
endif()

list(LENGTH MCF5307_CLAIM_IDS claim_count)
list(LENGTH claims_refuted refuted_count)
list(LENGTH claims_withheld withheld_count)
math(EXPR upheld_count "${claim_count}-${refuted_count}-${withheld_count}")

if(refuted_count GREATER 0 OR withheld_count GREATER 0
        OR claims_battery_failure_count GREATER 0)
    set(report "")
    foreach(entry IN LISTS claims_refuted)
        string(APPEND report "\n  ${entry}")
    endforeach()
    foreach(entry IN LISTS claims_withheld)
        string(APPEND report "\n  ${entry}")
    endforeach()
    foreach(entry IN LISTS claims_battery_failures)
        string(APPEND report "\n  SHAPE BATTERY: ${entry}")
    endforeach()
    message(FATAL_ERROR
        "t_claims: of ${claim_count} claims, ${upheld_count} are upheld, "
        "${refuted_count} are REFUTED and ${withheld_count} are WITHHELD; of "
        "${claims_shape_count} probe shapes, ${claims_battery_failure_count} "
        "are not the outcome recorded for them. A refuted claim is false. A "
        "WITHHELD one is unchecked: the driver ran and produced nothing that "
        "bears on it. A SHAPE THAT HAS MOVED IS A CHANGE IN WHAT EVERY VERDICT "
        "IN THIS FILE MEANS.${report}")
endif()

# THE TERMINAL LINE NAMES ALL THREE OUTCOMES AND NOT JUST THE REFUTATIONS. Its
# predecessor read `${claim_count} claims checked, none refuted`, which is true
# of a run in which every verdict was withheld - and that sentence is the shape
# of claim this whole file exists to make unsayable.
message("t_claims: ${claim_count} claims checked: ${upheld_count} upheld, "
        "${withheld_count} withheld, ${refuted_count} refuted; "
        "${claims_equivalent_ran} of them went through the equivalence path; "
        "${claims_shape_count} probe shapes agreed with the outcomes recorded "
        "for them")
