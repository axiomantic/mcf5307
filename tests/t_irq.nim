## `t_irq` - the interrupt model of `mcf5307/irq`.
##
## The MCF5307 User's Manual is Motorola, "MCF5307 ColdFire Integrated
## Microprocessor User's Manual", order number MCF5307UM/AD, (c) 1998. Every
## citation below names its section and folio page.
##
## The rising edge itself, and not only its consequence, is pinned. Block 11
## re-presents level 7 after the take, which is what a board that may call it
## unconditionally after every recomputation does. Blocks 7 and 8 cannot reach
## the guard that decides it, because both of their calls happen before the take
## and a `bool` latch cannot count.
##
## The board logs every vector-table read and every acknowledge, and every
## assertion compares the whole outcome tuple. A core that landed on the right
## handler by reading the wrong slot fails on the read list; a core that took
## the right vector at the wrong level fails on the acknowledge log; and a core
## that acknowledged at the wrong point fails on the acknowledge's own snapshot
## of A7, the program counter, the read count and the status register.

import mcf5307/cpu
import mcf5307/decode_types
import mcf5307/exception
import mcf5307/irq
import mcf5307/machine

var failures: seq[string]
import ./case_sites

var passCount = 0

proc checkImpl(site: int; ok: bool; label: string; got: string; want: string) =
  if ok:
    echo "PASSED  ", label
    inc passCount
    executedSites.add(site)
  else:
    echo "FAILED  ", label
    echo "          got  ", got
    echo "          want ", want
    failures.add(label)
    executedSites.add(site)


template check(ok: bool; label: string; got: string; want: string) =
  ## THE CALL SITE IS RECORDED TWICE - once at COMPILE TIME into
  ## `declaredSites` by the `static` below, and once at RUN TIME into
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, ok, label, got, want)
# ---------------------------------------------------------------------------
# The board. One flat byte array, big-endian, as `t_exception`'s. A read
# outside it reports `busUnmapped`.
#
# IT RECORDS EVERY READ BELOW `vectorTableBytes` and every acknowledge. The
# code sits at `execBase`, above the whole 1024-byte table, and every handler
# is higher still, so the recorded read list is the vector fetch and nothing
# else.

const
  memSize = 0x1000
  execBase = 0x400'u32      ## above the whole 1024-byte vector table
  execPc = execBase + 2'u32
    ## WHERE `newCtxSr` LEAVES THE PROGRAM COUNTER, and the offset is block 22's
    ## rule and not an arbitrary choice. `mcf5307_reset` inhibits the interrupt
    ## sample for the first instruction at the reset program counter, because the
    ## reset exception is an exception. `newCtxSr` spends that inhibition on the NOP at
    ## `execBase` so that every block which is about something ELSE reaches its
    ## own first `mcf5307_exec` with the machine able to sample. This is the
    ## address such a block runs its first instruction at, and therefore the
    ## address its first exception frame stacks.
  startSp = 0x800'u32
  frameBase = 0x7F8'u32     ## 0x800 - 8, longword aligned already
  opNopWord = 0x4E71'u16    ## `nop`, m68k-elf-as -mcpu=5307
  opTrapZeroWord = 0x4E40'u16
    ## `trap #0`. `src/mcf5307/decode.nim` records that `m68k-elf-as
    ## -mcpu=5307` emits `4e40` for it. It is the only exception an
    ## instruction of this tree can take: `takeException` is the whole of
    ## the core's exception path and `execTrap` is its one caller from
    ## inside `step`.
  trapZeroVector = 32'u8
    ## Vector numbers 32 to 47, at vector offsets $080 to $0BC, are the
    ## trap instructions.

  # The handler address in each slot this file uses. THEY ARE ALL DIFFERENT so
  # that a core which fetched the wrong vector lands where an assertion sees
  # it. Vectors 25 to 31 are the level 1 to 7 autovectors; 66 and 67 are in the
  # user-defined range 64-255.
  handlerAuto2 = 0x510'u32  ## vector 26, the level 2 autovector, at $068
  handlerAuto3 = 0x520'u32  ## vector 27, the level 3 autovector, at $06C
  handlerAuto4 = 0x530'u32  ## vector 28, the level 4 autovector, at $070
  handlerAuto5 = 0x540'u32  ## vector 29, the level 5 autovector, at $074
  handlerAuto6 = 0x550'u32  ## vector 30, the level 6 autovector, at $078
  handlerAuto7 = 0x560'u32  ## vector 31, the level 7 autovector, at $07C
  handlerVec66 = 0x580'u32  ## vector 66 = 0x42, at $108
  handlerVec67 = 0x590'u32  ## vector 67 = 0x43, at $10C
  handlerTrap0 = 0x5A0'u32  ## vector 32, `trap #0`, at $080

  userVector = 0x42'u8      ## 66. VISIBLE IF THE AUTOVECTOR FLAG HONOURED IT.
  otherVector = 0x43'u8     ## 67

type
  # An acknowledge carries where it happened and not only that it happened.
  # The acknowledge is fixed after the 8-byte frame is on the stack and before
  # the first handler instruction is fetched; `src/mcf5307/irq.nim` justifies
  # that position against section 3.3, folio 3-11, which puts the hardware's
  # acknowledge cycle second instead. A tuple of level and vector alone records
  # none of that. The fields below are what the position is observable through:
  #
  #   `sp`     A7 at the acknowledge. `takeException` assigns the frame base
  #            to A7 only AFTER both frame longwords are written, so an A7 of
  #            `frameBase` is the assertion that THE FRAME IS ALREADY ON THE
  #            STACK. An acknowledge before the stacking reports the entry A7.
  #   `pc`     the program counter at the acknowledge: the handler's ENTRY,
  #            never its second instruction, which is the assertion that the
  #            acknowledge precedes the first handler instruction.
  #   `reads`  how many vector-table reads had happened. One, for the fetch
  #            this take made.
  #   `sr`     the status register at the acknowledge. The interrupt's own
  #            mask write and M-clear have already happened, so
  #            this is the level's mask and not the entry mask.
  Ack = tuple[level: int, vector: uint8, sp: uint32, pc: uint32,
              reads: int, sr: uint32]
  TestBoard = object
    bytes: array[memSize, uint8]
  Outcome = tuple[sp: uint32, pc: uint32, sr: uint32, halted: bool,
                  frame: uint32, framePc: uint32,
                  acks: seq[Ack], reads: seq[uint32]]

var board: TestBoard
var vectorReads: seq[uint32]
var acks: seq[Ack]

# The context the acknowledge reads its snapshot from. The `user` pointer the
# acknowledge receives is the board, so the callback cannot reach the core's
# registers through its own
# arguments. `newCtxSr` publishes the context here and every block in this file
# creates its context through `newCtxSr`.
var ackCtx: MCF5307Ctx

# WHETHER THE ACKNOWLEDGE RE-PRESENTS A LEVEL 7. It is false for every block
# but one; `freshBoard` clears it. Block 15 is the only place a second
# interrupt can become pending across a single instruction boundary, and it
# needs the board to raise one at the moment the core acknowledges the first.
var iackArmsLevelSeven = false

# WHETHER THE FRAME WRITE RAISES A FRESH LEVEL-7 EDGE, AND IT IS A SECOND
# RE-ENTRY PATH AND NOT A SPELLING OF THE FIRST. It is false for every block but
# one; `freshBoard` clears it. The acknowledge runs AFTER `takeException` has
# returned, so a board that re-enters from there cannot reach the core while it
# is stacking. `takeException` writes both frame longwords through this board's
# own write callback, which is the one place a board can present an interrupt
# BETWEEN the shipped latch clear and the end of the stacking. That window is
# what block 17 exists to reach.
var writeArmsLevelSeven = false

proc boardWrite(b: var TestBoard; address: uint32; size: int; value: uint32) =
  for i in 0 ..< size:
    b.bytes[int(address) + i] =
      uint8((value shr ((size - 1 - i) * 8)) and 0xFF'u32)

proc boardReadValue(b: TestBoard; address: uint32; size: int): uint32 =
  for i in 0 ..< size:
    result = (result shl 8) or uint32(b.bytes[int(address) + i])

proc bRead(user: pointer; address: uint32; size: cint;
           status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return 0'u32
  status[] = Mcf5307BusStatus.busOk
  if address < vectorTableBytes:
    vectorReads.add(address)
  boardReadValue(b[], address, int(size))

proc bWrite(user: pointer; address: uint32; size: cint; value: uint32;
            status: ptr Mcf5307BusStatus) {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return
  status[] = Mcf5307BusStatus.busOk
  boardWrite(b[], address, int(size), value)
  # THE PRESENTATION IS TWO CALLS AND THE FIRST ONE IS WHAT MAKES THE SECOND AN
  # EDGE. `mcf5307_set_irq` arms only on a transition to level 7, and level 7 is
  # what this block entered the take with, so a lone level-7 call here would
  # find the level already 7 and arm nothing. The level 3 drops the presented
  # level first. It is ONE-SHOT because `takeException` writes the frame twice
  # and a second arming would measure a different sequence than the one this
  # names.
  if writeArmsLevelSeven:
    writeArmsLevelSeven = false
    mcf5307_set_irq(ackCtx, 3, userVector, 1)
    mcf5307_set_irq(ackCtx, 7, otherVector, 0)

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  ## THE SNAPSHOT IS TAKEN BEFORE ANY RE-PRESENTATION, so that the recorded
  ## state is the state the CORE was in when it called, and not a state this
  ## callback produced.
  acks.add((level: int(level), vector: vector,
            sp: mcf5307_get_reg(ackCtx, 15),
            pc: mcf5307_get_reg(ackCtx, 17),
            reads: vectorReads.len,
            sr: mcf5307_get_reg(ackCtx, 16)))
  if iackArmsLevelSeven:
    iackArmsLevelSeven = false
    mcf5307_set_irq(ackCtx, 7, otherVector, 1)

proc freshBoard() =
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  vectorReads = @[]
  acks = @[]
  iackArmsLevelSeven = false
  writeArmsLevelSeven = false
  # A RUN OF NOPs AT THE RESET PROGRAM COUNTER AND AT THE HEAD OF EVERY
  # HANDLER, AND THE LENGTH IS NOT DECORATION. The core executes the handler's
  # first instruction in the same pass that takes the interrupt: the device
  # executes at least one instruction in an interrupt exception handler before
  # recognizing another interrupt request. A block that ran past its single NOP
  # would decode the ZERO word beyond it, and a zero word is not a NOP -
  # measured with one NOP per handler, the core halted on it and later cases
  # then asserted a take that could not happen for a reason that had nothing to
  # do with interrupts.
  # `halted` is in every asserted tuple below so that the same shape cannot
  # hide again. Four NOPs is 8 bytes, the handlers are 16 apart, and no block
  # here executes more than three handler instructions.
  for word in 0 ..< 4:
    boardWrite(board, execBase + uint32(word) * 2'u32, 2, uint32(opNopWord))
  for handler in [handlerAuto2, handlerAuto3, handlerAuto4, handlerAuto5,
                  handlerAuto6, handlerAuto7, handlerVec66, handlerVec67,
                  handlerTrap0]:
    for word in 0 ..< 4:
      boardWrite(board, handler + uint32(word) * 2'u32, 2, uint32(opNopWord))
  boardWrite(board, vectorAddress(0'u32, autovectorFor(2)), 4, handlerAuto2)
  boardWrite(board, vectorAddress(0'u32, autovectorFor(3)), 4, handlerAuto3)
  boardWrite(board, vectorAddress(0'u32, autovectorFor(4)), 4, handlerAuto4)
  boardWrite(board, vectorAddress(0'u32, autovectorFor(5)), 4, handlerAuto5)
  boardWrite(board, vectorAddress(0'u32, autovectorFor(6)), 4, handlerAuto6)
  boardWrite(board, vectorAddress(0'u32, autovectorFor(7)), 4, handlerAuto7)
  boardWrite(board, vectorAddress(0'u32, userVector), 4, handlerVec66)
  boardWrite(board, vectorAddress(0'u32, otherVector), 4, handlerVec67)
  boardWrite(board, vectorAddress(0'u32, trapZeroVector), 4, handlerTrap0)

proc mem32(address: uint32): uint32 =
  ## Zero for a longword the board does not carry, and the guard is not
  ## defensive decoration. `observe` reads the two frame longwords AT THE
  ## CURRENT A7, and block 13 is entered with an A7 whose frame write the board
  ## refuses - an A7 that is off the end of the array. Without this the
  ## observation of that block would end the process on an index check instead
  ## of reporting the outcome the block asserts.
  if int(address) + 4 > memSize:
    return 0'u32
  boardReadValue(board, address, 4)

proc observe(ctx: MCF5307Ctx): Outcome =
  ## THE FRAME IS READ AT THE CURRENT A7 AND NOT AT A FIXED ADDRESS, so that a
  ## block which takes a SECOND interrupt asserts the SECOND frame. Each frame
  ## is self-aligning and goes below the last (`exceptionFrameBase`), so a
  ## fixed address would keep reporting the first frame while the assertion's
  ## label claimed the second: block 3's steps 3 and 4 once
  ## read the first frame's stacked program counter and never looked at the
  ## second frame at all. When nothing was taken, A7 is the reset stack pointer
  ## and the two words below are the zeros `freshBoard` wrote.
  (sp: mcf5307_get_reg(ctx, 15),
   pc: mcf5307_get_reg(ctx, 17),
   sr: mcf5307_get_reg(ctx, 16),
   halted: mcf5307_halted(ctx) != 0,
   frame: mem32(mcf5307_get_reg(ctx, 15)),
   framePc: mem32(mcf5307_get_reg(ctx, 15) + 4'u32),
   acks: acks,
   reads: vectorReads)

# The status register with an interrupt priority mask of `ipm` and nothing
# else set but S. I[2:0] is at bits 10-8, S at bit 13 and M at bit 12;
# `mcf5307_reset` writes 0x2700, which is S set and a mask of 7, the value the
# status register holds after a reset exception.
proc srWithIpm(ipm: uint32): uint32 =
  0x2000'u32 or (ipm shl 8)

proc newCtxAtReset(sr: uint32): MCF5307Ctx =
  ## A context STANDING AT ITS RESET PROGRAM COUNTER, with the reset
  ## exception's own inhibition of the interrupt sample still unspent.
  ##
  ## THE RESET EXCEPTION IS AN EXCEPTION AND ITS FIRST INSTRUCTION IS
  ## INHIBITED, which is block 22's subject and the reason this procedure is
  ## separate from `newCtxSr`. Every block that is about something else wants
  ## the machine PAST that instruction, because otherwise its own first
  ## `mcf5307_exec` spends a call on it; the blocks that are about the reset
  ## itself want the machine before it.
  freshBoard()
  result = mcf5307_create(addr board, bRead, bWrite, bIack)
  ackCtx = result
  mcf5307_reset(result, startSp, execBase)
  discard mcf5307_set_reg(result, 16, sr)

proc newCtxSr(sr: uint32): MCF5307Ctx =
  ## The context every block that is NOT about the reset uses: `newCtxAtReset`
  ## with THE RESET EXCEPTION'S OWN FIRST INSTRUCTION ALREADY RETIRED, so that
  ## the caller's first `mcf5307_exec` is a boundary at which an interrupt can
  ## be sampled.
  ##
  ## THE SPEND IS IN THE HELPER AND NOT IN EACH BLOCK, and the trade is worth
  ## stating. In each block it would be one more `mcf5307_exec` line per block
  ## saying the same thing twenty times, and the property it spells is pinned in
  ## one place already (block 22). Here it is one line, and the price is that
  ## `execPc` rather than `execBase` is the address every other block's first
  ## frame carries - which the constant is named and commented for.
  ##
  ## NO INTERRUPT IS PRESENTED YET AT THIS POINT, so the call cannot take one
  ## whether or not the sample is inhibited: every block presents its own after
  ## this returns. What the call spends is the inhibition and nothing else.
  result = newCtxAtReset(sr)
  discard mcf5307_exec(result, 1'u32)

proc newCtx(ipm: uint32): MCF5307Ctx =
  newCtxSr(srWithIpm(ipm))

# The first longword of the frame an interrupt at `vector` writes, entered
# with `stackedSr`. The A7 of every case here is 0x800, whose low two bits are
# 00, so the FORMAT is 4 and the frame base is 0x7F8. `FS` is 0000: the field
# is defined for access and address errors and zero for every other
# exception.
proc frameOf(vector: uint8; stackedSr: uint32): uint32 =
  (4'u32 shl 28) or (uint32(vector) shl 18) or stackedSr

proc ackOf(level: int; vector: uint8; sp: uint32; pc: uint32; reads: int;
           sr: uint32): Ack =
  ## One expected acknowledge, written out in full. EVERY FIELD IS SPELLED AT
  ## THE CALL SITE and none is derived from another, so that a core which
  ## acknowledged at the wrong point in the sequence differs from the written
  ## expectation rather than from a rule this file recomputed.
  (level: level, vector: vector, sp: sp, pc: pc, reads: reads, sr: sr)

# ---------------------------------------------------------------------------
# BLOCK 1. THE MASK INHIBITS AT LESS-THAN-OR-EQUAL.
#
# Interrupt requests are inhibited for all priority levels less than or equal
# to the current priority, except the edge-sensitive level 7 request, which
# cannot be masked. Level 3 at a mask
# of 3 is therefore inhibited. Nothing is stacked, no vector is read, no
# acknowledge happens, and the one instruction the budget pays for is the NOP
# at the reset program counter.

block:
  let ctx = newCtx(3)
  mcf5307_set_irq(ctx, 3, userVector, 1)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: startSp, pc: execPc + 2'u32, sr: srWithIpm(3),
                       halted: false,
                       frame: 0'u32, framePc: 0'u32,
                       acks: @[], reads: @[])
  check(got == want, "mask 3 inhibits level 3", $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 2. THE SAME LEVEL AT A LOWER MASK IS TAKEN.
#
# THE PAIR IS THE POINT. Block 1 alone passes on a core that takes no
# interrupt at all, and that core is exactly what a missing mechanism looks
# like. Only the mask differs between the two blocks.
#
# An interrupt exception also forces the M-bit to be cleared and the interrupt
# priority mask to be set to the level of the current interrupt request. So the
# handler runs at a mask
# of 3, and the STACKED status register is the copy taken before that change.

block:
  let ctx = newCtx(2)
  mcf5307_set_irq(ctx, 3, userVector, 1)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase,
                       pc: handlerAuto3 + 2'u32,
                       sr: srWithIpm(3),
                       halted: false,
                       frame: frameOf(autovectorFor(3), srWithIpm(2)),
                       framePc: execPc,
                       acks: @[ackOf(3, autovectorFor(3), frameBase,
                                     handlerAuto3, 1, srWithIpm(3))],
                       reads: @[vectorAddress(0'u32, autovectorFor(3))])
  check(got == want, "mask 2 admits level 3", $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 3. NOTHING LATCHES AT LEVELS 1 TO 6.
#
# THE FULL SEQUENCE, AND EVERY STEP OF IT IS LOAD-BEARING:
#
#   1  assert level 3 at a mask of 0, and take it
#   2  run again at the raised mask and take NOTHING - the core does not
#      re-enter its own handler
#   3  lower the mask by hand, WITH NO SECOND `mcf5307_set_irq` CALL, and take
#      the SAME interrupt again. The source is still pending because the
#      device has not cleared its condition. THIS IS THE STEP A LATCHING CORE
#      FAILS AND A TEST THAT STOPS AT THE ACKNOWLEDGE NEVER REACHES.
#   4  deassert at the source with `MCF5307_IRQ_NONE`, lower the mask again,
#      and take nothing.
#
# A level source drops when the device model clears its own condition. Nothing
# in the emulator drops it on the firmware's behalf.

block:
  let ctx = newCtx(0)
  mcf5307_set_irq(ctx, 3, userVector, 1)

  discard mcf5307_exec(ctx, 1'u32)
  let firstTake = observe(ctx)
  let wantFirst: Outcome = (sp: frameBase,
                            pc: handlerAuto3 + 2'u32,
                            sr: srWithIpm(3),
                            halted: false,
                            frame: frameOf(autovectorFor(3), srWithIpm(0)),
                            framePc: execPc,
                            acks: @[ackOf(3, autovectorFor(3), frameBase,
                                          handlerAuto3, 1, srWithIpm(3))],
                            reads: @[vectorAddress(0'u32, autovectorFor(3))])
  check(firstTake == wantFirst, "level-sensitive step 1: the first take",
        $firstTake, $wantFirst)

  discard mcf5307_exec(ctx, 1'u32)
  let masked = observe(ctx)
  let wantMasked: Outcome = (sp: frameBase,
                             pc: handlerAuto3 + 4'u32,
                             sr: srWithIpm(3),
                             halted: false,
                             frame: frameOf(autovectorFor(3), srWithIpm(0)),
                             framePc: execPc,
                             acks: @[ackOf(3, autovectorFor(3), frameBase,
                                           handlerAuto3, 1, srWithIpm(3))],
                             reads: @[vectorAddress(0'u32, autovectorFor(3))])
  check(masked == wantMasked,
        "level-sensitive step 2: the raised mask holds it off",
        $masked, $wantMasked)

  # NO `mcf5307_set_irq` CALL HERE. The board has not recomputed anything and
  # the device has not cleared its condition, so the level is still presented.
  discard mcf5307_set_reg(ctx, 16, srWithIpm(0))
  discard mcf5307_exec(ctx, 1'u32)
  let stillPending = observe(ctx)
  let wantStill: Outcome = (sp: frameBase - 8'u32,
                            pc: handlerAuto3 + 2'u32,
                            sr: srWithIpm(3),
                            halted: false,
                            frame: frameOf(autovectorFor(3), srWithIpm(0)),
                            framePc: handlerAuto3 + 4'u32,
                            acks: @[ackOf(3, autovectorFor(3), frameBase,
                                          handlerAuto3, 1, srWithIpm(3)),
                                    ackOf(3, autovectorFor(3), frameBase - 8'u32,
                                          handlerAuto3, 2, srWithIpm(3))],
                            reads: @[vectorAddress(0'u32, autovectorFor(3)),
                                     vectorAddress(0'u32, autovectorFor(3))])
  check(stillPending == wantStill,
        "level-sensitive step 3: still pending across the acknowledge",
        $stillPending, $wantStill)

  # The device clears its own condition and the board presents the whole new
  # state, which is no interrupt at all.
  mcf5307_set_irq(ctx, 0, userVector, 1)
  discard mcf5307_set_reg(ctx, 16, srWithIpm(0))
  discard mcf5307_exec(ctx, 1'u32)
  let gone = observe(ctx)
  let wantGone: Outcome = (sp: frameBase - 8'u32,
                           pc: handlerAuto3 + 4'u32,
                           sr: srWithIpm(0),
                           halted: false,
                           frame: frameOf(autovectorFor(3), srWithIpm(0)),
                           framePc: handlerAuto3 + 4'u32,
                           acks: @[ackOf(3, autovectorFor(3), frameBase,
                                         handlerAuto3, 1, srWithIpm(3)),
                                   ackOf(3, autovectorFor(3), frameBase - 8'u32,
                                         handlerAuto3, 2, srWithIpm(3))],
                           reads: @[vectorAddress(0'u32, autovectorFor(3)),
                                    vectorAddress(0'u32, autovectorFor(3))])
  check(gone == wantGone,
        "level-sensitive step 4: MCF5307_IRQ_NONE deasserts",
        $gone, $wantGone)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 4. THE CALL IS IDEMPOTENT.
#
# Two calls with the same arguments have the same effect as one, so the board
# may call it unconditionally after every recomputation. The two runs below
# differ in the number of calls and in nothing else, and both are held against
# the same written-out expectation, so
# two runs broken the same way cannot pass as a pair.
#
# THE PRESENTATION IS LEVEL 2 AND NO OTHER BLOCK PRESENTS IT. An earlier
# revision ran this control at level 5 autovectored - byte for byte the
# arguments and the expectation of block 5's first case - so the file reported
# sixteen cases and contained fifteen, and no mutation could red one of the
# pair without redding the other. A control whose every mutation is another
# case's mutation measures nothing of its own.
#
# THE FLAG IS SET, AND THAT IS THE PART OF THE ARGUMENT LIST THAT REPEATING
# CAN BREAK. The vector fields are overwritten with the same values twice and a
# second write of the same value is invisible; the FLAG is the field a model
# that accumulated instead of overwriting would toggle. A first attempt at this
# repair moved the block to a VECTORED presentation and lost that: a
# `mcf5307_set_irq` whose flag assignment was `xor` instead of `=` went from
# one red case to none. The presented `vector` here is
# `otherVector`, which the flag makes the core ignore, so a toggled flag lands
# on `handlerVec67` where this block's assertion sees it.

proc runOnce(callCount: int; level: cint; vector: uint8;
             autovector: cint; ipm: uint32; budget: uint32): Outcome =
  let ctx = newCtx(ipm)
  for _ in 1 .. callCount:
    mcf5307_set_irq(ctx, level, vector, autovector)
  discard mcf5307_exec(ctx, budget)
  result = observe(ctx)
  mcf5307_destroy(ctx)

block:
  let wantOne: Outcome = (sp: frameBase,
                          pc: handlerAuto2 + 2'u32,
                          sr: srWithIpm(2),
                          halted: false,
                          frame: frameOf(autovectorFor(2), srWithIpm(0)),
                          framePc: execPc,
                          acks: @[ackOf(2, autovectorFor(2), frameBase,
                                        handlerAuto2, 1, srWithIpm(2))],
                          reads: @[vectorAddress(0'u32, autovectorFor(2))])
  let once = runOnce(1, 2, otherVector, 1, 0, 1'u32)
  check(once == wantOne,
        "idempotence control: one call, level 2 autovectored",
        $once, $wantOne)
  let twice = runOnce(2, 2, otherVector, 1, 0, 1'u32)
  check(twice == wantOne,
        "idempotent: two identical calls match the one-call control",
        $twice, $wantOne)

# ---------------------------------------------------------------------------
# BLOCK 5. THE AUTOVECTOR FLAG IGNORES `vector`.
#
# BOTH CASES PASS THE SAME `vector` AND DIFFER ONLY IN THE FLAG. 0x42 is 66,
# which is in the user-defined range 64-255, and its
# table slot at $108 holds a handler address that no autovector slot holds. A
# core that honoured `vector` under the flag reads $108 and lands on
# `handlerVec66`, and both of those are in the asserted tuple.

block:
  let auto = runOnce(1, 5, userVector, 1, 0, 1'u32)
  let wantAuto: Outcome = (sp: frameBase,
                           pc: handlerAuto5 + 2'u32,
                           sr: srWithIpm(5),
                           halted: false,
                           frame: frameOf(autovectorFor(5), srWithIpm(0)),
                           framePc: execPc,
                           acks: @[ackOf(5, autovectorFor(5), frameBase,
                                         handlerAuto5, 1, srWithIpm(5))],
                           reads: @[vectorAddress(0'u32, autovectorFor(5))])
  check(auto == wantAuto, "autovector 1: vector 0x42 is ignored",
        $auto, $wantAuto)

  let vectored = runOnce(1, 5, userVector, 0, 0, 1'u32)
  let wantVectored: Outcome = (sp: frameBase,
                               pc: handlerVec66 + 2'u32,
                               sr: srWithIpm(5),
                               halted: false,
                               frame: frameOf(userVector, srWithIpm(0)),
                               framePc: execPc,
                               acks: @[ackOf(5, userVector, frameBase,
                                             handlerVec66, 1, srWithIpm(5))],
                               reads: @[vectorAddress(0'u32, userVector)])
  check(vectored == wantVectored, "autovector 0: vector 0x42 is used",
        $vectored, $wantVectored)

# ---------------------------------------------------------------------------
# BLOCK 6. LEVEL 7 CANNOT BE MASKED, AND LEVEL 6 AT THE SAME MASK CAN.
#
# A level 7 interrupt is nonmaskable, so a 7 in the interrupt mask does not
# disable it.
#
# THE LEVEL 6 CASE IS THE CONTROL. Without it, "level 7 is taken at mask 7"
# passes on a core that ignores the mask entirely.

block:
  let seven = runOnce(1, 7, otherVector, 1, 7, 1'u32)
  let wantSeven: Outcome = (sp: frameBase,
                            pc: handlerAuto7 + 2'u32,
                            sr: srWithIpm(7),
                            halted: false,
                            frame: frameOf(autovectorFor(7), srWithIpm(7)),
                            framePc: execPc,
                            acks: @[ackOf(7, autovectorFor(7), frameBase,
                                          handlerAuto7, 1, srWithIpm(7))],
                            reads: @[vectorAddress(0'u32, autovectorFor(7))])
  check(seven == wantSeven, "mask 7 does not disable level 7",
        $seven, $wantSeven)

  let six = runOnce(1, 6, otherVector, 1, 7, 1'u32)
  let wantSix: Outcome = (sp: startSp, pc: execPc + 2'u32,
                          sr: srWithIpm(7),
                          halted: false,
                          frame: 0'u32, framePc: 0'u32,
                          acks: @[], reads: @[])
  check(six == wantSix, "mask 7 does disable level 6", $six, $wantSix)

# ---------------------------------------------------------------------------
# BLOCK 7. A RISING EDGE TO LEVEL 7 ARMS EXACTLY ONE INTERRUPT.
#
# If IRQ7 remains asserted only one level 7 interrupt is recognized, because
# only one transition from a lower level request to a level 7 request
# occurred.
#
# THE SECOND `mcf5307_exec` IS THE ASSERTION. The level is still 7 at that
# boundary and the acknowledge log must still hold ONE entry. A core that
# treated level 7 as level-sensitive acknowledges twice.

block:
  let ctx = newCtx(0)
  mcf5307_set_irq(ctx, 7, otherVector, 1)
  discard mcf5307_exec(ctx, 1'u32)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase,
                       pc: handlerAuto7 + 4'u32,
                       sr: srWithIpm(7),
                       halted: false,
                       frame: frameOf(autovectorFor(7), srWithIpm(0)),
                       framePc: execPc,
                       acks: @[ackOf(7, autovectorFor(7), frameBase,
                                     handlerAuto7, 1, srWithIpm(7))],
                       reads: @[vectorAddress(0'u32, autovectorFor(7))])
  check(got == want, "level 7 held: exactly one interrupt", $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 8. LEVEL 7 PRESENTED TWICE ARMS ONLY ONE.
#
# The same rule read from the other side: the second call presents the level
# that is already presented, so no transition occurred and no second interrupt
# is armed. This is also the level-7 half of the idempotence rule.

block:
  let ctx = newCtx(0)
  mcf5307_set_irq(ctx, 7, otherVector, 1)
  mcf5307_set_irq(ctx, 7, otherVector, 1)
  discard mcf5307_exec(ctx, 1'u32)
  discard mcf5307_exec(ctx, 1'u32)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase,
                       pc: handlerAuto7 + 6'u32,
                       sr: srWithIpm(7),
                       halted: false,
                       frame: frameOf(autovectorFor(7), srWithIpm(0)),
                       framePc: execPc,
                       acks: @[ackOf(7, autovectorFor(7), frameBase,
                                     handlerAuto7, 1, srWithIpm(7))],
                       reads: @[vectorAddress(0'u32, autovectorFor(7))])
  check(got == want, "level 7 twice: only one is armed", $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 9. THE LEVEL DROPPING BACK BEFORE THE TAKE DOES NOT DISARM IT.
#
# A transition to level 7 arms one non-maskable interrupt; the level dropping
# back does not disarm it.
#
# The drop is to a level the mask would admit, and its vector is vectored and
# different. Level 3 vectored at 0x42 would land on `handlerVec66` after
# reading $108. The armed level 7 must land on `handlerAuto7` after reading
# $07C, and the acknowledge must name level 7. A core that disarmed on the drop
# takes level 3, and a core that read the PRESENTED PAIR - the level 3's vector
# together with the level 3's flag - reads $108. Both are separated by this
# tuple.
#
# WHAT THIS TUPLE CANNOT DECIDE, AND AN EARLIER REVISION OF THIS COMMENT SAID
# IT COULD. THE EDGE HERE IS AUTOVECTORED, so `vectorFor` returns the
# autovector and never reads `ctx.irq7Vector` at all. A core that kept the
# edge's FLAG and read the PRESENTED VECTOR reaches the autovector anyway and
# is green here. The sentence this comment used to carry - that a core using
# the currently presented vector reads $108 - was true only of a core that took
# the presented FLAG along with it, and it read as though the stored vector
# were under test here. It is not.
#
# THIS BLOCK PINS THE FLAG HALF AND NOT THE VECTOR HALF. Block 19 runs this
# same drop sequence with a VECTORED edge, and block 18 presents a vectored
# level 7 on the ordinary single-presentation path.
# `tests/t_claims.cmake` registers `edge_flag_suite_t_irq` against the sentence
# that opens this paragraph: it presents the level-3 flag to the take in place
# of the edge's and requires exactly one case of this suite to red, so the half
# this block does pin is measured rather than asserted.

block:
  let ctx = newCtx(0)
  mcf5307_set_irq(ctx, 7, otherVector, 1)
  mcf5307_set_irq(ctx, 3, userVector, 0)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase,
                       pc: handlerAuto7 + 2'u32,
                       sr: srWithIpm(7),
                       halted: false,
                       frame: frameOf(autovectorFor(7), srWithIpm(0)),
                       framePc: execPc,
                       acks: @[ackOf(7, autovectorFor(7), frameBase,
                                     handlerAuto7, 1, srWithIpm(7))],
                       reads: @[vectorAddress(0'u32, autovectorFor(7))])
  check(got == want,
        "level 7 armed, level dropped: still taken, with the edge's flag",
        $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 10. THE INTERRUPT EXCEPTION CLEARS THE M-BIT, AND THE FRAME KEEPS IT.
#
# An interrupt exception forces the M-bit to be cleared and the interrupt
# priority mask to be set to the level of the current interrupt request. M is
# bit 12, cleared by an interrupt exception and set by software during an RTE
# or a move to SR.
#
# THIS IS THE ONE CASE IN THIS FILE ENTERED WITH M SET, AND WITHOUT IT THE
# M-CLEAR IS UNREACHABLE. Every other block enters with M already clear, where
# a core that never touched the bit and a core that clears it are the same
# core. The frame must carry M SET, because the stacked word is the copy taken
# before the exception changed anything, and the handler must run with it
# CLEAR - so one case separates the copy from the modified word as well.

block:
  const srWithMaster = 0x3000'u32   ## S at bit 13 and M at bit 12, mask 0
  let ctx = newCtxSr(srWithMaster)
  mcf5307_set_irq(ctx, 4, userVector, 1)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase,
                       pc: handlerAuto4 + 2'u32,
                       sr: srWithIpm(4),
                       halted: false,
                       frame: frameOf(autovectorFor(4), srWithMaster),
                       framePc: execPc,
                       acks: @[ackOf(4, autovectorFor(4), frameBase,
                                     handlerAuto4, 1, srWithIpm(4))],
                       reads: @[vectorAddress(0'u32, autovectorFor(4))])
  check(got == want, "the interrupt clears M and the frame keeps it",
        $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 11. THE LEVEL 7 THAT IS RE-PRESENTED AFTER ITS TAKE IS NOT A SECOND
# EDGE.
#
# This is the board's documented normal behaviour and not an exotic one.
# Two calls with the same arguments have the same effect as one, so the board
# may call it unconditionally after every recomputation. A board that does
# exactly that, with IRQ7 still asserted, calls `mcf5307_set_irq(7, ...)` again
# after the core has already taken the level 7 interrupt - which is the
# sequence below, and the sequence a second recognition is forbidden for
# because only one transition from a lower level request to a level 7 request
# occurred.
#
# Block 8 does not reach this and cannot. Its two calls both happen before the
# take, so the two arms land on a latch that is still armed from the first, and
# `irq7Armed` being a `bool` makes arming twice indistinguishable from arming
# once. What decides block 8 is therefore the type of the field and not the
# `and ctx.irqLevel != 7` guard in `mcf5307_set_irq`: deleting that guard
# reddens nothing.
# The take must happen between the two calls, because only then is the latch
# consumed and only then can a second arm produce a second interrupt.

block:
  let ctx = newCtx(0)
  mcf5307_set_irq(ctx, 7, otherVector, 1)
  discard mcf5307_exec(ctx, 1'u32)
  # The re-presentation, with the same arguments and after the take. The level
  # was 7 before this call and is 7 after it, so no transition occurred.
  mcf5307_set_irq(ctx, 7, otherVector, 1)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase,
                       pc: handlerAuto7 + 4'u32,
                       sr: srWithIpm(7),
                       halted: false,
                       frame: frameOf(autovectorFor(7), srWithIpm(0)),
                       framePc: execPc,
                       acks: @[ackOf(7, autovectorFor(7), frameBase,
                                     handlerAuto7, 1, srWithIpm(7))],
                       reads: @[vectorAddress(0'u32, autovectorFor(7))])
  check(got == want,
        "level 7 re-presented after its take: no transition, no second take",
        $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 12. A HELD LEVEL 7 WHOSE LATCH IS SPENT IS NOT TAKEN WHEN THE HANDLER
# LOWERS THE MASK. THIS PINS A DIVERGENCE FROM THE MANUAL AND NOT AN AGREEMENT
# WITH IT.
#
# The manual describes TWO sequences. The first is the edge
# rule this file's blocks 7, 8 and 11 pin. The SECOND is a handler that lowers
# the interrupt mask below 7 while IRQ7 is still asserted, and it says the core
# recognizes a further level 7 interrupt there "even though no transition has
# occurred on the interrupt control pins".
#
# `src/mcf5307/irq.nim` declares that this project implements the edge half and
# not the level half, because the rule here is edge-only and no level-7 source
# is programmed. Deleting `and level <= 6` from `pendingInterrupt` is exactly
# the manual's second sequence: the spent level 7 falls through to the
# level path and is taken again as soon as the mask drops below 7.
#
# THE SEQUENCE BELOW IS THAT SECOND SEQUENCE, and the assertion is that
# NOTHING FURTHER IS TAKEN. It asserts what this project chose, not what the
# manual describes. Changing the choice is an open decision that belongs to the
# operator and not to this file; if it is ever made, THIS BLOCK IS THE ONE THAT
# MUST CHANGE, and its failure is the intended signal.

block:
  let ctx = newCtx(0)
  mcf5307_set_irq(ctx, 7, otherVector, 1)
  discard mcf5307_exec(ctx, 1'u32)
  # The handler lowers the mask to 0 while level 7 is STILL PRESENTED and with
  # NO second `mcf5307_set_irq` call - the device has not cleared its
  # condition. This is block 3 step 3's sequence at level 7 instead of level 3,
  # and the asserted answer is the opposite one.
  discard mcf5307_set_reg(ctx, 16, srWithIpm(0))
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase,
                       pc: handlerAuto7 + 4'u32,
                       sr: srWithIpm(0),
                       halted: false,
                       frame: frameOf(autovectorFor(7), srWithIpm(0)),
                       framePc: execPc,
                       acks: @[ackOf(7, autovectorFor(7), frameBase,
                                     handlerAuto7, 1, srWithIpm(7))],
                       reads: @[vectorAddress(0'u32, autovectorFor(7))])
  check(got == want,
        "held level 7, latch spent, mask lowered: NOT retaken (the divergence)",
        $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 13. A FAULT INSIDE THE STACKING HALTS THE TAKE, AND THE EDGE IT
# CONSUMED STAYS CONSUMED.
#
# `src/mcf5307/irq.nim` justifies two orderings by this case.
#
# The fault is reachable today. A7 is set to an address whose frame write is
# off the end of the board, so `machine.nim`'s `writeMem` reports the refusal
# and `takeException` returns early with the context halted. What this block
# pins is only what today's core does, which is: stop.
#
# The two steps are separate assertions and both are load-bearing:
#
#   1  The halted take stacked nothing, read no vector and did not
#      acknowledge. `irq.nim` returns before the mask write and before the
#      acknowledge; a core that ran on would tell the board it had accepted an
#      interrupt it never entered. `cpu.nim` then breaks out of the loop rather
#      than executing an instruction on a halted machine.
#   2  The reset that recovers the machine re-observes the pin. The level 7 is
#      still presented across the reset, and the reset's re-sample arms a fresh
#      edge from it, so the recovered machine takes a level 7 one instruction
#      after the reset program counter.
#
# A mutation that leaves the latch armed on the fault path is unobservable
# through the ABI: `mcf5307_reset` clears the latch and re-arms it from the
# presented level, so the latch after a reset is a function of the pin alone,
# the core publishes no other way to read it, and a halted context cannot
# execute an instruction. The clear before the stacking is still the shipped
# order and `irq.nim` gives the reason, but no case in this file separates it on
# the fault path. The non-fault half of the same position is pinned by block 17.
#
# What step 2 pins instead is the recovery itself and the reset's re-sample:
# the latch this take consumed is gone, so the interrupt the recovered machine
# takes can only have been armed by the reset re-observing a pin that is still
# asserted. A reset that cleared the latch and did NOT re-sample takes nothing
# here.

block:
  # (0x1008 - 8) and not 3 is 0x1000, and the board's last byte is 0xFFF, so
  # the FIRST of the two frame writes is the one that is refused.
  const faultingSp = 0x1008'u32
  let ctx = newCtx(0)
  discard mcf5307_set_reg(ctx, 15, faultingSp)
  mcf5307_set_irq(ctx, 7, otherVector, 1)
  discard mcf5307_exec(ctx, 1'u32)
  let faulted = observe(ctx)
  let wantFaulted: Outcome = (sp: faultingSp,
                              pc: execPc,
                              sr: srWithIpm(0),
                              halted: true,
                              frame: 0'u32, framePc: 0'u32,
                              acks: @[], reads: @[])
  check(faulted == wantFaulted,
        "a refused frame write halts the take: no vector, no acknowledge",
        $faulted, $wantFaulted)

  # THE RECOVERY IS TWO `mcf5307_exec` CALLS AND NOT ONE, because the reset
  # inhibits the sample at the reset program counter (block 22). The first call
  # retires the instruction there; the second is the first boundary at which an
  # interrupt can be taken at all.
  mcf5307_reset(ctx, startSp, execBase)
  discard mcf5307_exec(ctx, 1'u32)
  discard mcf5307_exec(ctx, 1'u32)
  let recovered = observe(ctx)
  # `mcf5307_reset` writes 0x2700, which is S set and a mask of 7, and level 7
  # is nonmaskable, so the re-armed edge is taken under that mask.
  let wantRecovered: Outcome = (sp: frameBase,
                                pc: handlerAuto7 + 2'u32,
                                sr: srWithIpm(7),
                                halted: false,
                                frame: frameOf(autovectorFor(7), srWithIpm(7)),
                                framePc: execBase + 2'u32,
                                acks: @[ackOf(7, autovectorFor(7), frameBase,
                                              handlerAuto7, 1, srWithIpm(7))],
                                reads: @[vectorAddress(0'u32,
                                                       autovectorFor(7))])
  check(recovered == wantRecovered,
        "the reset re-observes the still-asserted level 7 the halted take " &
        "consumed",
        $recovered, $wantRecovered)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 14. `mcf5307_set_irq` ON A NIL CONTEXT RETURNS, AND THE LEVEL-6
# AUTOVECTORED TAKE AFTER IT.
#
# `mcf5307_set_irq` is a C ABI entry point (`include/mcf5307.h`) and its first
# statement is a nil guard. NOTHING MEASURED IT - deleting the guard left all
# sixteen cases of the previous revision green, because no case ever passed a
# nil context. The guard's whole contract is that the call RETURNS, and a call
# that did not return would end the process before the assertion below was
# reached, so REACHING A VERDICT AT ALL is what decides that half.
#
# THE LABEL USED TO CLAIM A SECOND CLAUSE THAT NO ASSERTION REACHES, and it is
# worth saying what went wrong with it because the shape is cheap to repeat.
# It read "the next real context is unaffected", which is a BEFORE-AND-AFTER
# sentence, and this block has no before: the context is created AFTER the nil
# call, there is no run without the nil call to compare it against, and the one
# tuple asserted below cannot tell a context that was affected from one that
# was not. What the assertion actually decides is the take.
#
# THE LEVEL IS 6 AND IT IS THE ONLY LEVEL-6 TAKE IN THIS FILE, which is what
# the case adds beyond the nil call. Block 6 presents level 6 only to have it
# inhibited, so `handlerAuto6` and vector 30 are otherwise never reached.

block:
  mcf5307_set_irq(nil, 6, otherVector, 1)
  let got = runOnce(1, 6, otherVector, 1, 0, 1'u32)
  let want: Outcome = (sp: frameBase,
                       pc: handlerAuto6 + 2'u32,
                       sr: srWithIpm(6),
                       halted: false,
                       frame: frameOf(autovectorFor(6), srWithIpm(0)),
                       framePc: execPc,
                       acks: @[ackOf(6, autovectorFor(6), frameBase,
                                     handlerAuto6, 1, srWithIpm(6))],
                       reads: @[vectorAddress(0'u32, autovectorFor(6))])
  check(got == want,
        "mcf5307_set_irq on a nil context returns; level 6 autovectored is " &
        "then taken",
        $got, $want)

# ---------------------------------------------------------------------------
# BLOCK 15. THE HANDLER'S FIRST INSTRUCTION RUNS BEFORE THE NEXT INTERRUPT IS
# RECOGNIZED.
#
# The device executes at least one instruction in an interrupt exception
# handler before recognizing another interrupt request, and the same rule holds
# for every handler. `src/mcf5307/cpu.nim` says its sample and its `step` are
# ONE iteration for exactly this reason, and that making the take `continue`
# instead would sample again before the handler had executed anything. THAT
# SENTENCE HAD NO TEST: adding the `continue` once reddened nothing.
#
# IT WENT UNTESTED BECAUSE THE INTERFACE MAKES A SECOND PENDING INTERRUPT HARD
# TO ARRANGE. The board presents ONE level, and a take raises the mask to that
# level, so the presentation that was just taken is never pending again at the
# next boundary. The one thing that can raise a second interrupt between the
# take and the handler's first instruction is THE BOARD ITSELF, inside the
# acknowledge - which is what a chained interrupt controller does, and what
# `bIack` does here when `iackArmsLevelSeven` is set.
#
# THE SEPARATOR IS THE SECOND FRAME'S STACKED PROGRAM COUNTER. With the
# handler's first instruction executed first it is `handlerAuto3 + 2`; with a
# core that sampled again immediately it is `handlerAuto3`, the instruction
# that never ran.

block:
  let ctx = newCtx(0)
  mcf5307_set_irq(ctx, 3, userVector, 1)
  iackArmsLevelSeven = true
  discard mcf5307_exec(ctx, 1'u32)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase - 8'u32,
                       pc: handlerAuto7 + 2'u32,
                       sr: srWithIpm(7),
                       halted: false,
                       frame: frameOf(autovectorFor(7), srWithIpm(3)),
                       framePc: handlerAuto3 + 2'u32,
                       acks: @[ackOf(3, autovectorFor(3), frameBase,
                                     handlerAuto3, 1, srWithIpm(3)),
                               ackOf(7, autovectorFor(7), frameBase - 8'u32,
                                     handlerAuto7, 2, srWithIpm(7))],
                       reads: @[vectorAddress(0'u32, autovectorFor(3)),
                                vectorAddress(0'u32, autovectorFor(7))])
  check(got == want,
        "a level 7 raised by the acknowledge waits for the handler's first " &
        "instruction",
        $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 16. A LEVEL OUTSIDE 0 TO 7 IS STORED AND NEVER TAKEN.
#
# `include/mcf5307.h` defines `level` as "`MCF5307_IRQ_NONE` for none, or 1 to
# 7" and says nothing about any other value. `src/mcf5307/irq.nim` states what
# the code guarantees for one anyway: such a level "is STORED AND NEVER TAKEN,
# and that is a property of the comparisons below rather than a rule this
# module states", and the property matters because it is what keeps an
# out-of-range level away from `autovectorFor`, whose parameter is a checked
# range and whose violation ends the process under `--panics:on`.
#
# THE PROPERTY RESTS ENTIRELY ON `level >= 1`, AND NOTHING MEASURED IT -
# deleting that bound left all sixteen cases of the previous revision green.
# The presentation below is VECTORED so that the assertion reports the take a
# core without the bound would make, rather than the range panic an
# autovectored one would die on: `uint32(-1)` is 0xFFFFFFFF, which is greater
# than every mask, so the level path admits it the moment the lower bound is
# gone.

block:
  let got = runOnce(1, -1, otherVector, 0, 0, 1'u32)
  let want: Outcome = (sp: startSp, pc: execPc + 2'u32,
                       sr: srWithIpm(0),
                       halted: false,
                       frame: 0'u32, framePc: 0'u32,
                       acks: @[], reads: @[])
  check(got == want, "a level outside 0 to 7 is stored and never taken",
        $got, $want)

# ---------------------------------------------------------------------------
# BLOCK 17. A LEVEL-7 EDGE RAISED FROM INSIDE THE FRAME WRITE SURVIVES THE
# TAKE THAT IS STACKING IT. THIS IS WHERE THE LATCH CLEAR SITS IN THE
# NON-FAULTING PATH.
#
# `src/mcf5307/irq.nim` clears the level-7 latch BEFORE `takeException` and
# gives one reason for it: a fault inside the stacking must not leave an
# interrupt armed. Block 13 pins that reason. IT IS NOT THE ONLY CONSEQUENCE OF
# THE POSITION, and the other one needs a board that reaches the core WHILE the
# frame is being written - which `takeException` allows, because it stacks
# through the board's own write callback.
#
# THE SEQUENCE IS 7, THEN 3 AND 7 FROM INSIDE THE WRITE. The first level 7 is
# the edge this take consumes. The 3 and the 7 arrive while the core is between
# its latch clear and the end of the stacking, and together they are a fresh
# rising edge. With the shipped order the latch is already clear when that edge
# arrives, so the edge ARMS and a second interrupt is taken. With the clear
# moved to just after `takeException` the same edge is wiped by a clear that
# runs after it, and the second interrupt never happens:
# that move reds this case and no other case in this file.
#
# THE RE-ENTERED EDGE IS VECTORED AND THE FIRST IS NOT, so the second take must
# read $10C and land on `handlerVec67` while the first reads $07C and lands on
# `handlerAuto7`. A core that carried the FIRST edge's vector into the second
# take differs from this tuple in the read list, the program counter and the
# acknowledge.
#
# THE TWO PRESENTATIONS CARRY DIFFERENT VECTORS, AND THAT DIFFERENCE IS WHAT
# MAKES THE STORE AT THE EDGE OBSERVABLE. The first presentation is
# AUTOVECTORED, so the vector it names never reaches the asserted tuple and any
# value would pass; where it does reach is `ctx.irq7Vector`, and it stays there
# until a later edge overwrites it. Give the two presentations the SAME vector
# and that field holds the value this block asserts WHETHER OR NOT the
# re-entered edge wrote it - and a store that only ever writes what is already
# in the field is a store no case can separate from no store at all. That is
# not a deletion of the store: a deletion leaves the field at its zero and any
# earlier presentation exposes it. It is the store made CONDITIONAL on
# something, which keeps every board that never exercises the condition
# passing. `userVector` on the first presentation and `otherVector` on the
# re-entry is what puts the two apart, and the re-entry is what makes the edge
# arrive on a presentation that is not idle.

block:
  let ctx = newCtx(0)
  mcf5307_set_irq(ctx, 7, userVector, 1)
  writeArmsLevelSeven = true
  discard mcf5307_exec(ctx, 1'u32)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase - 8'u32,
                       pc: handlerVec67 + 2'u32,
                       sr: srWithIpm(7),
                       halted: false,
                       frame: frameOf(otherVector, srWithIpm(7)),
                       framePc: handlerAuto7 + 2'u32,
                       acks: @[ackOf(7, autovectorFor(7), frameBase,
                                     handlerAuto7, 1, srWithIpm(7)),
                               ackOf(7, otherVector, frameBase - 8'u32,
                                     handlerVec67, 2, srWithIpm(7))],
                       reads: @[vectorAddress(0'u32, autovectorFor(7)),
                                vectorAddress(0'u32, otherVector)])
  check(got == want,
        "a level 7 raised from inside the frame write survives the take " &
        "that is stacking it",
        $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 18. THE LEVEL-7 EDGE CARRIES ITS OWN VECTOR, AND A VECTORED LEVEL 7
# READS THE SLOT THAT VECTOR NAMES.
#
# `mcf5307_set_irq` stores the vector and the flag of the edge in fields of
# their own, and `pendingInterrupt` reads THOSE and not the presented pair.
# Block 9 pins the FLAG half of that - an armed level 7 whose presentation has
# dropped to a vectored level 3 still autovectors - and the registry entry
# `edge_flag_suite_t_irq` in `tests/t_claims.cmake` is what keeps that true:
# this sentence is a pointer to where the flag half is pinned and not the
# record that it is. THE VECTOR HALF NEEDS A
# LEVEL 7 THAT IS ITSELF VECTORED, because under the flag `vectorFor` returns
# the autovector without reading the stored field at all, so no autovectored
# presentation can separate a stored vector from a dropped one. Against a file
# carrying neither this block nor block 17, deleting `ctx.irq7Vector = vector`
# from `mcf5307_set_irq` reddened nothing; against a copy of this file with
# THIS block removed, the same deletion reds block 17.
#
# WHY THIS BLOCK STAYS, given that block 17's re-entered edge is vectored too
# and header item 11 records which mutations each of the two separates. Block
# 17's vectored take is a SECOND take, reached only because the board re-enters
# `mcf5307_set_irq` from inside the frame write - a mechanism `takeException`
# allows through the write callback and which no document in this repository
# describes. This block is the ordinary reading of the same rule: one vectored
# level 7, taken FIRST, out of a context nothing has re-entered. A file that
# pinned the stored vector only through the re-entrant path would lose the rule
# the moment that path moved, and would report nothing while it did.
#
# 0x42 IS THE SAME VECTOR BLOCK 5 USES AND FOR THE SAME REASON. 64-255 is the
# user-defined range; the slot at $108 holds
# `handlerVec66`, which no autovector slot holds. A core that dropped the
# stored vector reads slot 0 instead, whose longword `freshBoard` leaves zero.

block:
  let got = runOnce(1, 7, userVector, 0, 0, 1'u32)
  let want: Outcome = (sp: frameBase,
                       pc: handlerVec66 + 2'u32,
                       sr: srWithIpm(7),
                       halted: false,
                       frame: frameOf(userVector, srWithIpm(0)),
                       framePc: execPc,
                       acks: @[ackOf(7, userVector, frameBase,
                                     handlerVec66, 1, srWithIpm(7))],
                       reads: @[vectorAddress(0'u32, userVector)])
  check(got == want, "a vectored level 7 uses the vector its edge carried",
        $got, $want)

# ---------------------------------------------------------------------------
# BLOCK 19. A LATER PRESENTATION DOES NOT OVERWRITE THE VECTOR THE LEVEL-7
# EDGE STORED.
#
# THIS IS BLOCK 9'S SEQUENCE WITH A VECTORED EDGE, AND THE TWO ARE NOT ONE
# CASE. Block 9's edge is AUTOVECTORED, so `vectorFor` returns the autovector
# and never reads `ctx.irq7Vector` at all. Block 9 therefore decides the FLAG
# and CANNOT DECIDE THE VECTOR: a core that kept the edge's flag and read the
# PRESENTED vector is green in block 9 and lands on a different handler here.
#
# WHAT THIS BLOCK SEPARATES AND THE OTHER TWO VECTORED CASES DO NOT. The store
# at `irq.nim`'s level-7 arm can be wrong in its SCOPE as well as in its value
# or its condition: moved OUT of the `if level == 7` guard it still runs, still
# writes the edge's vector at the edge, and is then overwritten by every later
# presentation. Block 18 presents nothing after its edge, so there is nothing
# to overwrite it. Block 17's re-entry is itself the last presentation, so a
# store outside the guard writes the value the block already expects. ONLY A
# LEVEL-7 EDGE FOLLOWED BY A DIFFERENT PRESENTATION REACHES IT, and only when
# the edge is vectored. Measured against the file as it stood before this
# block:
# THAT MOVE REDS NO CASE OF THAT FILE AND IT REDS THIS BLOCK.
#
# THAT SENTENCE IS REGISTERED AND NOT ONLY WRITTEN DOWN. `tests/t_claims.cmake`
# carries it as `edge_vector_scope_suite_t_irq`, applies the move to a copy of
# `src/` and requires this suite to go EXACTLY ONE red. Prose alone would go
# stale the moment this block was weakened; the entry reds instead.
#
# THE OBSERVER OF `tests/t_claims.nim` STILL CANNOT STAND IN FOR THIS BLOCK,
# AND THE REASON THIS COMMENT USED TO GIVE HAS GONE FALSE. It read that every
# scenario that observer presents is AUTOVECTORED, so the stored vector is
# written and never read there, and that all 225 of its scenarios UPHELD this
# move. That was true of the space the observer ran when the sentence was
# written and is false of the space it runs now: it gained a PRESENTATION
# PROFILE axis, `pVectored` clears the autovector flag and hands every call a
# distinct vector, and the stored vector is therefore read. Compiling that
# observer against a pristine `src/` and against one carrying this move and
# comparing the two traces REFUTES the move.
#
# A SCENARIO COUNT AND THE POSITION ARE TWO DIFFERENT JOBS. A sentence carrying
# a count of scenarios is a measurement in prose. What this block claims is
# SUITE-RELATIVE - that exactly one case of THIS file reds under the move - and
# that is not a measurement in prose at all: `edge_vector_scope_suite_t_irq` in
# `tests/t_claims.cmake` applies the move and requires this suite to go exactly
# one red, so a weakened case reds the registry instead of quietly agreeing
# with a comment. AN OBSERVER THAT ALSO SEPARATES THE MOVE SAYS NOTHING ABOUT
# THAT COUNT, which is the reason this block stays and the reason the two
# mechanisms are not interchangeable.
#
# THE DROP IS VECTORED AND ITS VECTOR IS THE OTHER ONE. The edge carries
# `otherVector`, whose slot $10C holds `handlerVec67`; the drop presents a
# level 3 at `userVector`, whose slot $108 holds `handlerVec66`. The armed
# level 7 must read $10C and acknowledge vector 0x43, so a core that carried
# the presentation's vector into the take differs in the read list, in the
# program counter and in the acknowledge.

block:
  let ctx = newCtx(0)
  mcf5307_set_irq(ctx, 7, otherVector, 0)
  mcf5307_set_irq(ctx, 3, userVector, 0)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase,
                       pc: handlerVec67 + 2'u32,
                       sr: srWithIpm(7),
                       halted: false,
                       frame: frameOf(otherVector, srWithIpm(0)),
                       framePc: execPc,
                       acks: @[ackOf(7, otherVector, frameBase,
                                     handlerVec67, 1, srWithIpm(7))],
                       reads: @[vectorAddress(0'u32, otherVector)])
  check(got == want,
        "a vectored level 7 whose level dropped keeps its edge's vector",
        $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 20. THE FIRST INSTRUCTION OF A *TRAP* HANDLER RUNS BEFORE AN INTERRUPT
# IS SAMPLED. THIS IS THE HALF OF THE RULE THAT IS NOT ABOUT INTERRUPT
# HANDLERS.
#
# ColdFire processors inhibit sampling for interrupts during the first
# instruction of all exception handlers. ALL exception handlers, not only
# interrupt handlers - and an
# interrupt handler is the only kind block 15 can reach, because the only
# exception `mcf5307_exec` itself takes is the interrupt.
#
# THE OTHER HALF IS REACHABLE THROUGH `TRAP` AND THROUGH NOTHING ELSE IN THIS
# TREE. An exception taken from inside `step` returns to `mcf5307_exec` with
# the machine at a handler's entry and `halted` false - `execTrap` in
# `src/mcf5307/control.nim` is that path - so the loop comes back round to its
# sample with the program counter on an instruction that has not run.
#
# THE SEPARATOR IS THE SECOND FRAME'S STACKED PROGRAM COUNTER, which is what
# tells "the trap handler ran its first instruction" from "the trap handler ran
# nothing at all": `handlerTrap0 + 2` against `handlerTrap0`. A core that
# stacks the entry has made the trap handler execute ZERO instructions, and the
# handler's first instruction is unrecoverable - nothing on the stack says it
# was skipped.
#
# THE INTERRUPT IS RAISED BETWEEN THE TWO `mcf5307_exec` CALLS AND NOT BEFORE
# THE FIRST, and the position is the whole construction. Raised before the
# first call it would be sampled at `execPc` and taken instead of the TRAP,
# and no trap handler would be entered at all. The board raising it while the
# machine sits at the handler's entry is the sequence both rules govern.
#
# THE BUDGET IS ONE CYCLE PER CALL, so each call runs exactly one instruction:
# the loop tests the budget only BEFORE a step (the cycle block at the head of
# `src/mcf5307/cpu.nim`), and every instruction here costs more than one. The
# RETURN of each call is the instruction's whole cost and is discarded here.

block:
  let ctx = newCtx(0)
  # `trap #0` in place of the SECOND of the four NOPs `freshBoard` wrote at the
  # reset program counter, which is the one `execPc` stands on: `newCtxSr` has
  # already retired the first.
  boardWrite(board, execPc, 2, uint32(opTrapZeroWord))
  discard mcf5307_exec(ctx, 1'u32)

  # The board presents a level 3 while the machine is at the trap handler's
  # entry, which is where sampling is inhibited.
  mcf5307_set_irq(ctx, 3, userVector, 1)
  discard mcf5307_exec(ctx, 1'u32)
  let firstInstruction = observe(ctx)
  let wantFirst: Outcome = (sp: frameBase,
                            pc: handlerTrap0 + 2'u32,
                            sr: srWithIpm(0),
                            halted: false,
                            frame: frameOf(trapZeroVector, srWithIpm(0)),
                            framePc: execPc + 2'u32,
                            acks: @[],
                            reads: @[vectorAddress(0'u32, trapZeroVector)])
  check(firstInstruction == wantFirst,
        "trap handler entry: the level 3 is not sampled there",
        $firstInstruction, $wantFirst)

  discard mcf5307_exec(ctx, 1'u32)
  let taken = observe(ctx)
  let wantTaken: Outcome = (sp: frameBase - 8'u32,
                            pc: handlerAuto3 + 2'u32,
                            sr: srWithIpm(3),
                            halted: false,
                            frame: frameOf(autovectorFor(3), srWithIpm(0)),
                            framePc: handlerTrap0 + 2'u32,
                            acks: @[ackOf(3, autovectorFor(3),
                                          frameBase - 8'u32, handlerAuto3, 2,
                                          srWithIpm(3))],
                            reads: @[vectorAddress(0'u32, trapZeroVector),
                                     vectorAddress(0'u32, autovectorFor(3))])
  check(taken == wantTaken,
        "the level 3 is taken one instruction later, and stacks that address",
        $taken, $wantTaken)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 21. A CONTEXT WITH NO BOARD CALLBACKS FAULTS AND DOES NOT END THE
# PROCESS.
#
# Nothing may abort the process: an abort inside a plugin destroys the host's
# session. `include/mcf5307.h` forbids no
# argument of `mcf5307_create`, and `step` in `src/mcf5307/cpu.nim` opens with
# a nil-`readFn` guard that faults and halts - so the core's own code is the
# statement that a context without callbacks is a state it survives.
#
# THE INTERRUPT PATH REACHES THE BOARD BEFORE ANY INSTRUCTION DOES, and that is
# what makes this case reachable at all: the frame write of `takeException`
# happens at the instruction boundary, ahead of the first fetch, so `step`'s
# guard is behind it and cannot answer for it.
#
# THE WHOLE OUTCOME IS ASSERTED AND `halted` ALONE IS NOT ENOUGH. A core that
# refused the interrupt for the wrong reason - one that dropped it silently and
# then halted on the fetch - reaches the same two bits by a different route,
# and the status register separates them: `takeException` sets S before it
# writes, so a fault DURING the take leaves S set where a fault at the fetch
# leaves the register at its created zero.
#
# THE TAKE REACHES TWO CALLBACKS AND THERE IS A CASE FOR EACH. `takeException`
# writes the frame and then READS the vector, so the write callback answers
# first and a context missing only the READ callback gets all the way past the
# stacking. One case with neither callback can only ever reach the first of the
# two.

block:
  let ctx = mcf5307_create(nil, nil, nil, nil)
  mcf5307_set_irq(ctx, 3, otherVector, 1)
  let cycles = mcf5307_exec(ctx, 1'u32)
  let got = (cycles: cycles,
             halted: mcf5307_halted(ctx) != 0,
             faulted: mcf5307_faulted(ctx) != 0,
             sp: mcf5307_get_reg(ctx, 15),
             pc: mcf5307_get_reg(ctx, 17),
             sr: mcf5307_get_reg(ctx, 16))
  # `mcf5307_create` leaves every register zero, so the mask is 0 and a level 3
  # is admitted. The frame write is refused, `takeException` returns early, and
  # `mcf5307_exec` breaks without spending a cycle. A7 and the program counter
  # never move: `takeException` assigns A7 only after both longwords are
  # written and the program counter only after the vector is read.
  let want = (cycles: 0'u32,
              halted: true,
              faulted: true,
              sp: 0'u32,
              pc: 0'u32,
              sr: srWithIpm(0))
  check(got == want,
        "no board callbacks at all: the frame write faults, nothing aborts",
        $got, $want)
  mcf5307_destroy(ctx)

block:
  # A BOARD THAT CAN BE WRITTEN AND NOT READ. The stack pointer is a real one,
  # so both frame longwords land and the take gets as far as the vector fetch.
  #
  # THE STACK POINTER IS SET DIRECTLY AND NOT BY `mcf5307_reset`, AND THAT IS
  # FORCED BY BLOCK 22'S RULE. A reset inhibits the interrupt sample until one
  # instruction has retired, and this board cannot retire one: `step` faults on
  # the nil read callback before it fetches. A reset here would therefore end
  # the run at the FETCH and never reach the take this case is about. The
  # program counter stays at the zero `mcf5307_create` leaves - the ABI's
  # `mcf5307_set_reg` refuses index 17 - and the frame carries that zero, which
  # costs this case nothing: what it separates is WHERE the take stopped, and
  # `sp`, the two frame longwords, the read list and the acknowledge log all
  # answer that.
  freshBoard()
  let ctx = mcf5307_create(addr board, nil, bWrite, nil)
  discard mcf5307_set_reg(ctx, 15, startSp)
  discard mcf5307_set_reg(ctx, 16, srWithIpm(0))
  mcf5307_set_irq(ctx, 3, otherVector, 1)
  let cycles = mcf5307_exec(ctx, 1'u32)
  let got = (cycles: cycles,
             halted: mcf5307_halted(ctx) != 0,
             faulted: mcf5307_faulted(ctx) != 0,
             sp: mcf5307_get_reg(ctx, 15),
             pc: mcf5307_get_reg(ctx, 17),
             sr: mcf5307_get_reg(ctx, 16),
             frame: mem32(frameBase),
             framePc: mem32(frameBase + 4'u32),
             reads: vectorReads,
             acks: acks)
  # THE FRAME IS ON THE STACK AND THE VECTOR WAS NEVER FETCHED, which is what
  # separates a fault at the read from a fault at the write: A7 has moved to
  # the frame base, both longwords are there, the program counter is still the
  # one the frame carries, and the acknowledge - which `irq.nim` places after
  # the whole take - never happened.
  let want = (cycles: 0'u32,
              halted: true,
              faulted: true,
              sp: frameBase,
              pc: 0'u32,
              sr: srWithIpm(0),
              frame: frameOf(autovectorFor(3), srWithIpm(0)),
              framePc: 0'u32,
              reads: newSeq[uint32](),
              acks: newSeq[Ack]())
  check(got == want,
        "a write-only board: the vector read faults, nothing aborts",
        $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 22. `mcf5307_reset` INHIBITS THE FIRST INTERRUPT SAMPLE, BECAUSE THE
# RESET EXCEPTION IS AN EXCEPTION.
#
# THIS IS A CITATION AND NOT AN INFERENCE. ColdFire processors inhibit sampling
# for interrupts during the first instruction of ALL exception handlers, and
# reset has an exception entry of its own, so the code at the reset program
# counter is the first instruction of an exception handler and that rule
# governs it.
#
# `mcf5307_reset` DOES NOT ROUTE THROUGH `takeException`, which is where every
# other exception in this core acquires the inhibition (`machine.nim` states
# why the write sits on that procedure's last line), so the reset has to write
# the field itself. It used to write `false`, which is a core that can take an
# interrupt at the reset program counter before retiring a single instruction -
# the state the sentence above forbids.
#
# THE PREDECESSOR OF THIS BLOCK PINNED THE OPPOSITE ANSWER AND ITS REASONING
# SURVIVES ITS VERDICT. It read that a reset must not carry an inhibition into a
# machine whose program counter it has just moved, "and the first interrupt
# after the reset would be skipped for a handler that no longer exists". The
# premise is right - a stale inhibition would be wrong - and the conclusion was
# wrong, because the reset does not merely FAIL TO CLEAR the field: it has an
# exception of its own to acquire it for, and the instruction the inhibition is
# spent on is the one the reset itself has just installed.
#
# THE TWO CASES ARE THE TWO SIDES OF ONE BOUNDARY, and the second is not a
# nicety. A core that took nothing at all would pass the first alone.
#
# THIS BLOCK IS NOT THE ONLY PIN ON THE INHIBITION AND THE REGISTRY SAYS SO.
# `tests/t_claims.cmake` carries `reset_inhibit_suite_t_irq`, which writes
# `false` where `mcf5307_reset` writes `true` and requires `t_irq` to go
# EXACTLY SIX red. Six and not two, because the write reaches every case whose
# outcome depends on WHEN the first post-reset sample happens: this block holds
# two of them, and block 13's step 2, block 23's held pin, block 24 and block 25
# hold the other four. WEAKENING ANY ONE OF THE SIX MOVES THE COUNT AND THE
# ENTRY REDS - which is the whole reason the number is registered and not
# merely written down. Weakening this block's two assertions to compare
# `.halted` alone leaves the suite green and every derived check silent, and
# the mutation then reds fewer cases than the registry expects, so
# `reset_inhibit_suite_t_irq` refutes where nothing else had spoken.

block:
  let ctx = newCtxAtReset(srWithIpm(0))
  mcf5307_set_irq(ctx, 3, userVector, 1)
  discard mcf5307_exec(ctx, 1'u32)
  let atReset = observe(ctx)
  let wantAtReset: Outcome = (sp: startSp, pc: execBase + 2'u32,
                              sr: srWithIpm(0),
                              halted: false,
                              frame: 0'u32, framePc: 0'u32,
                              acks: @[], reads: @[])
  check(atReset == wantAtReset,
        "the reset pc's first instruction retires before a level 3 is sampled",
        $atReset, $wantAtReset)

  discard mcf5307_exec(ctx, 1'u32)
  let taken = observe(ctx)
  let wantTaken: Outcome = (sp: frameBase,
                            pc: handlerAuto3 + 2'u32,
                            sr: srWithIpm(3),
                            halted: false,
                            frame: frameOf(autovectorFor(3), srWithIpm(0)),
                            framePc: execBase + 2'u32,
                            acks: @[ackOf(3, autovectorFor(3), frameBase,
                                          handlerAuto3, 1, srWithIpm(3))],
                            reads: @[vectorAddress(0'u32, autovectorFor(3))])
  check(taken == wantTaken,
        "the level 3 is taken at the boundary after it, and stacks the " &
        "instruction that follows the retired one",
        $taken, $wantTaken)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 23. WHAT A RESET DOES TO THE LEVEL-7 EDGE LATCH: IT CLEARS IT AND THEN
# RE-OBSERVES THE PIN.
#
# THIS IS AN INFERENCE AND NOT A CITATION, AND THE MANUALS ARE SILENT RATHER
# THAN BRIEF. The reset exception's entry names no pending-interrupt state at
# all, and the sections that describe the level-7 trigger type never mention
# reset. So nothing below is quoted, and what
# stands in for a quotation is stated rather than assumed:
#
#   THE CLEAR. RSTI resets every register in the SIM, every peripheral, and the
#   entire device including the PLL. There is no silicon that does all of that
#   and preserves
#   a one-bit edge-history flop inside the core's recognition logic.
#
#   THE RE-OBSERVATION, WITHOUT WHICH THE CLEAR ALONE DROPS AN INTERRUPT REAL
#   HARDWARE TAKES. The level 7 request on IRQ7 must be held until the second
#   interrupt-acknowledge bus cycle has begun to ensure that the interrupt is
#   recognized. A latched edge
#   whose pin has since been released therefore models a state the hardware
#   cannot acknowledge, and preserving it is wrong. But a pin that is STILL
#   ASSERTED across the reset meets a detector whose history the reset has just
#   put back to "last seen level 0", so the next sample is a transition from a
#   lower request to level 7 and the core RE-ARMS ITSELF. A reset that only
#   cleared would drop that interrupt.
#
# THE TWO CASES ARE THE TWO PINS. They differ in ONE call - whether the board
# releases the pin before the reset - and in nothing else. The second is the one
# a clear-only reset fails.
#
# THE THREE WAYS TO GET THE RESET WRONG ARE REGISTERED SEPARATELY, because a
# single entry could not tell them apart and each fails a different case here.
# `tests/t_claims.cmake` carries them: deleting the `resetInterruptEdge` call
# outright, so that a reset that does neither reds three cases of this file
# (`reset_edge_call_suite_t_irq`) - keeping the clear and dropping the
# re-presentation (`reset_edge_resample_suite_t_irq`) - and keeping the
# re-presentation and dropping the clear (`reset_edge_clear_suite_t_irq`). The
# released pin above and the held pin below fail DIFFERENT members of that set,
# which is why neither case alone would do and why no one count answers for all
# three.
#
# THE EDGE IS VECTORED IN BOTH, so the second case also decides WHERE the
# re-armed edge got its vector and its flag: they come from the PRESENTATION the
# reset re-observed. `otherVector`'s slot $10C holds `handlerVec67`, which no
# autovector slot holds, so a re-arm that autovectored instead lands on
# `handlerAuto7` and is separated by the read list, the program counter and the
# acknowledge.

block:
  let released = newCtxAtReset(srWithIpm(0))
  mcf5307_set_irq(released, 7, otherVector, 0)
  # THE PIN IS RELEASED AND THE LATCH IS NOT DISARMED BY THAT - block 9 pins
  # the rule. What clears it is the reset on the next line.
  mcf5307_set_irq(released, 0, otherVector, 0)
  mcf5307_reset(released, startSp, execBase)
  discard mcf5307_set_reg(released, 16, srWithIpm(0))
  discard mcf5307_exec(released, 1'u32)
  discard mcf5307_exec(released, 1'u32)
  let gotReleased = observe(released)
  let wantReleased: Outcome = (sp: startSp, pc: execBase + 4'u32,
                               sr: srWithIpm(0),
                               halted: false,
                               frame: 0'u32, framePc: 0'u32,
                               acks: @[], reads: @[])
  check(gotReleased == wantReleased,
        "a level-7 edge whose pin was released does not survive a reset",
        $gotReleased, $wantReleased)
  mcf5307_destroy(released)

block:
  let held = newCtxAtReset(srWithIpm(0))
  mcf5307_set_irq(held, 7, otherVector, 0)
  mcf5307_reset(held, startSp, execBase)
  discard mcf5307_set_reg(held, 16, srWithIpm(0))
  discard mcf5307_exec(held, 1'u32)
  discard mcf5307_exec(held, 1'u32)
  let gotHeld = observe(held)
  let wantHeld: Outcome = (sp: frameBase,
                           pc: handlerVec67 + 2'u32,
                           sr: srWithIpm(7),
                           halted: false,
                           frame: frameOf(otherVector, srWithIpm(0)),
                           framePc: execBase + 2'u32,
                           acks: @[ackOf(7, otherVector, frameBase,
                                         handlerVec67, 1, srWithIpm(7))],
                           reads: @[vectorAddress(0'u32, otherVector)])
  check(gotHeld == wantHeld,
        "a level 7 still asserted across a reset re-arms and is taken after " &
        "the reset pc's first instruction",
        $gotHeld, $wantHeld)
  mcf5307_destroy(held)

# ---------------------------------------------------------------------------
# BLOCK 24. THE EDGE A RESET RE-ARMS CARRIES THE VECTOR THE BOARD IS PRESENTING
# NOW, AND NOT THE VECTOR THE CLEARED EDGE CARRIED.
#
# THIS IS THE ONE ARRANGEMENT IN WHICH THE TWO DIFFER, AND NOTHING IN THIS FILE
# REACHED IT BEFORE. `mcf5307_set_irq` arms only on a TRANSITION to level 7, so
# a second level-7 presentation writes `ctx.irqVector` and leaves
# `ctx.irq7Vector` holding the first one. Every other case here presents level 7
# at most once before its reset, where the two fields agree and no assertion can
# tell which of them `resetInterruptEdge` read.
#
# THE TWO VECTORS LAND ON DIFFERENT HANDLERS, which is what makes the case an
# assertion and not a description. The first presentation carries `otherVector`,
# whose slot $10C holds `handlerVec67`; the second carries `userVector`, whose
# slot $108 holds `handlerVec66`. A `resetInterruptEdge` that re-armed from
# `ctx.irq7Vector` acknowledges 0x43 and enters at `handlerVec67`, and the
# program counter, the read list and the acknowledge all separate it.
#
# `src/mcf5307/irq.nim` STATES THE REASON THE ANSWER IS THE PRESENTATION: the
# procedure re-observes a pin and does not restore a latch, and `ctx.irq7Vector`
# is the record of an edge the same procedure has just cleared.

block:
  let ctx = newCtxAtReset(srWithIpm(0))
  mcf5307_set_irq(ctx, 7, otherVector, 0)
  # NO TRANSITION: the level is already 7, so this call arms nothing and the
  # edge keeps `otherVector` while the PRESENTATION becomes `userVector`.
  mcf5307_set_irq(ctx, 7, userVector, 0)
  mcf5307_reset(ctx, startSp, execBase)
  discard mcf5307_set_reg(ctx, 16, srWithIpm(0))
  discard mcf5307_exec(ctx, 1'u32)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase,
                       pc: handlerVec66 + 2'u32,
                       sr: srWithIpm(7),
                       halted: false,
                       frame: frameOf(userVector, srWithIpm(0)),
                       framePc: execBase + 2'u32,
                       acks: @[ackOf(7, userVector, frameBase,
                                     handlerVec66, 1, srWithIpm(7))],
                       reads: @[vectorAddress(0'u32, userVector)])
  check(got == want,
        "the reset re-arms from the presented vector, not the cleared edge's",
        $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 25. `mcf5307_reset` ON A NIL CONTEXT RETURNS.
#
# THIS IS BLOCK 14'S SHAPE AND IT IS HERE FOR BLOCK 14'S REASON. `mcf5307_reset`
# is a C ABI entry point (`include/mcf5307.h`), its guard's whole contract is
# that the call RETURNS, and a call that did not return would end the process
# before the assertion below was reached - so REACHING A VERDICT AT ALL is what
# decides it. Nothing measured it before: no case in this file had ever passed
# a nil context to this entry point.
#
# THE TAKE AFTER IT IS A REAL ONE AND NOT A FORMALITY, for the reason block 14
# gives about its own: this block has no BEFORE to compare against, so the tuple
# below cannot tell a context the nil call damaged from one it did not. What the
# assertion decides is that the process is still running and the ordinary path
# still works.

block:
  mcf5307_reset(nil, startSp, execBase)
  let ctx = newCtxAtReset(srWithIpm(0))
  mcf5307_set_irq(ctx, 7, otherVector, 0)
  discard mcf5307_set_reg(ctx, 16, srWithIpm(0))
  discard mcf5307_exec(ctx, 1'u32)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase,
                       pc: handlerVec67 + 2'u32,
                       sr: srWithIpm(7),
                       halted: false,
                       frame: frameOf(otherVector, srWithIpm(0)),
                       framePc: execBase + 2'u32,
                       acks: @[ackOf(7, otherVector, frameBase,
                                     handlerVec67, 1, srWithIpm(7))],
                       reads: @[vectorAddress(0'u32, otherVector)])
  check(got == want,
        "mcf5307_reset on a nil context returns; the next real context resets",
        $got, $want)
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# BLOCK 26. `resetInterruptEdge` ON A NIL CONTEXT RETURNS.
#
# THIS IS BLOCK 25'S SHAPE FOR A PROCEDURE THAT IS NOT A C ABI ENTRY POINT, AND
# THAT DIFFERENCE IS THE WHOLE ARGUMENT FOR THE CASE. `mcf5307_reset` and
# `mcf5307_set_irq` guard their contexts because a C caller hands them whatever
# it likes. `resetInterruptEdge` is reached only from Nim, and its docstring
# named the protection it actually had: "`mcf5307_reset` in `cpu.nim` is the
# only caller", which is a true sentence about the tree and NOT a mechanism.
#
# WHAT MADE IT WORTH A CASE IS THAT THE SENTENCE IS GREEN-FALSIFIABLE.
# `mcf5307_reset`'s own nil guard returns BEFORE it reaches
# `resetInterruptEdge`, so block 25 does not exercise this path at all and no
# case in this file ever passed a nil context to this procedure. A SECOND
# CALLER COULD BE ADDED WITH EVERY REGISTERED TEST STILL GREEN, and the first
# one that forwarded a nil would fault on this procedure's first executable
# line. Memory safety resting on prose is the defect; the guard and this case
# are the repair.
#
# REACHING A VERDICT AT ALL IS WHAT DECIDES IT, for block 14's and block 25's
# reason: a call that did not return would end the process before the assertion
# below, and the case would then be DECLARED and never EXECUTED - which is the
# pair `tests/case_sites.nim` exists to compare.
#
# THE TAKE AFTER IT DELIBERATELY AVOIDS THE RESET PATH. It is block 2's level-3
# take from `newCtx`, which retires the reset's own first instruction in the
# helper, so this case is not one of those whose outcome depends on when the
# first post-reset sample happens. The four reset entries in
# `tests/t_claims.cmake` therefore keep the counts they had, and that was
# measured rather than assumed.

block:
  resetInterruptEdge(nil)
  let ctx = newCtx(2)
  mcf5307_set_irq(ctx, 3, userVector, 1)
  discard mcf5307_exec(ctx, 1'u32)
  let got = observe(ctx)
  let want: Outcome = (sp: frameBase,
                       pc: handlerAuto3 + 2'u32,
                       sr: srWithIpm(3),
                       halted: false,
                       frame: frameOf(autovectorFor(3), srWithIpm(2)),
                       framePc: execPc,
                       acks: @[ackOf(3, autovectorFor(3), frameBase,
                                     handlerAuto3, 1, srWithIpm(3))],
                       reads: @[vectorAddress(0'u32, autovectorFor(3))])
  check(got == want,
        "resetInterruptEdge on a nil context returns; the next real context " &
        "takes a level 3",
        $got, $want)
  mcf5307_destroy(ctx)

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_irq", declaredCaseSites)
echo caseSiteLine("executed", "t_irq", executedSites)
echo caseSiteLine("off-green-path", "t_irq", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_irq: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_irq: ", passCount, " cases passed"
