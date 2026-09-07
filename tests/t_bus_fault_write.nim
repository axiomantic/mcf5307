## `t_bus_fault_write` - the stacked program counter of an operand write fault,
## and the condition codes a refused CLR leaves in the frame.
##
## It asserts that the fault was taken, that the write instruction's register
## write-back completed, and that the frame names the FAULTING INSTRUCTION.
##
## The write cycle may be decoupled from the processor's issuing of the
## operation, and all programming model updates associated with the write
## instruction are completed. The MCF5307 leaves the stacked program counter
## at whatever point in that pipeline the error was signaled; THIS PART DOES
## NOT. MCF5407 User's Manual section 4.9.5.1, "Cache Filling", folio 4-17:
## "Note that unlike Version 2 and Version 3 access errors, the program counter
## stored on the exception stack frame points to the faulting instruction."
##
## So the frame's second longword is pinned here, and it is pinned to a value
## that is not `ctx.pc` at any point of any instruction in this file. The same
## faulting instruction runs at two program addresses and each run is held to
## its own instruction address, so the pin measures the sentence rather than a
## constant that a core stacking nothing could also satisfy.
##
## Every expected value below is a hand-derived literal, written beside the bit
## string or the manual row it came from, and not a second call of the
## procedure under test. Every opcode is the output of `m68k-elf-as -mcpu=5307`
## on the mnemonic printed beside it.
##
## The manual this file cites is Motorola, "MCF5407 ColdFire Integrated
## Microprocessor User's Manual", order number MCF5407UM/D, Rev. 0.1, 11/2001,
## except where a citation names the MCF5307 User's Manual (order number
## MCF5307UM/AD, (c) 1998) and says why.

import std/strutils

import mcf5407/cpu
import mcf5407/decode_types
import mcf5407/machine

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
  ## The call site is recorded twice - once at compile time into
  ## `declaredSites` by the `static` below, and once at run time into
  ## `executedSites`, by the implementation and only when it reaches a verdict.
  ## `tests/case_sites.nim` states what the pair is for. The template exists
  ## for `instantiationInfo`: a proc cannot see where it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, ok, label, got, want)

# ---------------------------------------------------------------------------
# The board. One flat byte array, big-endian, which refuses exactly one
# longword and reports `MCF5407_BUS_FAULT` for it.
#
# The refused row is the one that is real silicon. On this part an access error
# is reported only for an attempted store to write-protected space, so such a
# store is the only access this suite can drive that a real MCF5307 would also
# fault on.
#
# An access past the array is counted and not only refused. The count separates
# a run that stacked its frame on the board from one that did not, without
# reading any address the frame occupies.

const
  memSize = 0x1000
  execBase = 0x400'u32       ## above the whole 1024-byte vector table
  execBaseAlt = 0x440'u32    ## the SAME instruction, at a different address
  accessHandler = 0x600'u32
  protectedWord = 0x0C00'u32 ## the one longword this board refuses to store
  openWord = 0x0900'u32      ## a longword the same board stores
  frameBase = 0x7F8'u32      ## 0x800 - 8, with FORMAT 4
  startSp = 0x800'u32
  vecAccess = 2'u8           ## the access error, at $008
  srReset = 0x2700'u32
  opMovePost = 0x20C0'u16    ## `move.l %d0,(%a0)+`, m68k-elf-as -mcpu=5307
  opMovePre = 0x2100'u16     ## `move.l %d0,-(%a0)`, the same assembler
  opRteWord = 0x4E73'u16     ## `rte`, the same assembler
  sourceD0 = 0x80000000'u32  ## negative, so the write's own N update is visible

type TestBoard = object
  bytes: array[memSize, uint8]

var board: TestBoard
var offBoardWrites = 0

proc boardWrite(b: var TestBoard; address: uint32; size: int; value: uint32) =
  if int(address) + size > memSize:
    return
  for i in 0 ..< size:
    b.bytes[int(address) + i] =
      uint8((value shr ((size - 1 - i) * 8)) and 0xFF'u32)

proc boardReadValue(b: TestBoard; address: uint32; size: int): uint32 =
  if int(address) + size > memSize:
    return 0'u32
  for i in 0 ..< size:
    result = (result shl 8) or uint32(b.bytes[int(address) + i])

proc protectedRead(user: pointer; address: uint32; size: cint;
                   status: ptr Mcf5407BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5407BusStatus.busUnmapped
    return 0'u32
  status[] = Mcf5407BusStatus.busOk
  boardReadValue(b[], address, int(size))

proc protectedWrite(user: pointer; address: uint32; size: cint; value: uint32;
                    status: ptr Mcf5407BusStatus) {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    inc offBoardWrites
    status[] = Mcf5407BusStatus.busUnmapped
    return
  if address == protectedWord:
    status[] = Mcf5407BusStatus.busFault
    return
  status[] = Mcf5407BusStatus.busOk
  boardWrite(b[], address, int(size), value)

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

proc freshBoard() =
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8

# ---------------------------------------------------------------------------
# The runner. The stacked program counter is returned beside the asserted
# tuple and not inside it, which is this file's rule expressed as a type: a
# case can compare two runs' program counters with each other, and no expected
# constant can carry one.

type WriteOutcome = tuple[sp: uint32, pc: uint32, sr: uint32, halted: bool,
                          fault: bool, frame: uint32, a0: uint32, d0: uint32,
                          stored: uint32, offBoard: int]

type WriteRun = tuple[outcome: WriteOutcome, stackedPc: uint32]

proc runWrite(opcode: uint16; at: uint32; a0Init: uint32;
              target: uint32): WriteRun =
  freshBoard()
  offBoardWrites = 0
  boardWrite(board, at, 2, uint32(opcode))
  boardWrite(board, accessHandler, 2, uint32(opRteWord))
  boardWrite(board, 4'u32 * uint32(vecAccess), 4, accessHandler)

  let ctx = mcf5407_create(addr board, protectedRead, protectedWrite, bIack)
  mcf5407_reset(ctx, startSp, at)
  discard mcf5407_set_reg(ctx, 0, sourceD0)
  discard mcf5407_set_reg(ctx, 8, a0Init)
  discard mcf5407_exec(ctx, 1'u32)
  result = (outcome: (sp: mcf5407_get_reg(ctx, 15),
                      pc: mcf5407_get_reg(ctx, 17),
                      sr: mcf5407_get_reg(ctx, 16),
                      halted: ctx.halted,
                      fault: ctx.fault,
                      frame: boardReadValue(board, frameBase, 4),
                      a0: mcf5407_get_reg(ctx, 8),
                      d0: mcf5407_get_reg(ctx, 0),
                      stored: boardReadValue(board, target, 4),
                      offBoard: offBoardWrites),
            stackedPc: boardReadValue(board, frameBase + 4'u32, 4))
  mcf5407_destroy(ctx)

# ---------------------------------------------------------------------------
# Block 1. The fault is taken and the write instruction's register write-back
# completes.
#
# The frame's first longword is hand-derived from the bit positions and not
# from a second call of the encoder. A7 is 0x800 with its low two bits 00, so
# MCF5407 User's Manual Table 2-20, "Format Field Encoding", folio 2-33, gives
# format 4 and a frame at 0x800 - 8. The vector is 2. `FS` is `1001`,
# Table 2-21's "Attempted write to write-protected space", and its two halves
# land in two non-adjacent fields of Figure 2-1, "Exception Stack Frame Form":
#   0100 | 10 | 00000010 | 01 | 0010011100000000 -> 0x48092700
# This longword carries no program counter. Figure 2-1, folio 2-33, puts the
# program counter in the second longword, which is the one this suite reads
# outside its asserted tuple.
#
# The live status register is 0x2708 and the frame's copy is 0x2700, and the
# difference is the assertion rather than a tolerance. `takeException` copies
# the status register before it changes it, so the frame carries 0x2700. The
# write instruction then sets N from its source, which is negative here, and
# that update lands after the faulting access. That is the rule that every
# programming model update associated with the write instruction completes,
# observed on the one register it reaches without an addressing mode.
#
# The address register is the second half of the same sentence. `(%a0)+`
# updates A0, and the updated value survives the fault rather than being rolled
# back to the pre-instruction one.
#
# The store itself did not commit, and `stored` is what separates that from the
# register updates. The board refused the longword, so memory keeps its zero
# while A0 and the condition codes both moved - which is the asymmetry the
# manual describes and which a core that simply completed the write would not
# show.

const wantFaultedPost: WriteOutcome =
  (sp: frameBase, pc: accessHandler, sr: 0x2708'u32, halted: false,
   fault: false, frame: 0x48092700'u32, a0: protectedWord + 4'u32,
   d0: sourceD0, stored: 0'u32, offBoard: 0)

let post = runWrite(opMovePost, execBase, protectedWord, protectedWord)
check(post.outcome == wantFaultedPost,
      "a refused store takes the access fault and completes its write-back",
      $post.outcome, $wantFaultedPost)

# The same instruction at a different program address is held to the same
# constant. Nothing in the expected value above mentions where the program sat,
# so this run is the measurement that the asserted outcome does not depend on
# it.
let postAlt = runWrite(opMovePost, execBaseAlt, protectedWord, protectedWord)
check(postAlt.outcome == wantFaultedPost,
      "the same refused store at another address gives the same outcome",
      $postAlt.outcome, $wantFaultedPost)

# ---------------------------------------------------------------------------
# Block 2. The stacked program counter is the faulting instruction's address.
#
# MCF5407 User's Manual section 4.9.5.1, "Cache Filling", folio 4-17: "Note
# that unlike Version 2 and Version 3 access errors, the program counter stored
# on the exception stack frame points to the faulting instruction." The
# instruction is `move.l %d0,(%a0)+`, one word, so a Version 2 or 3 stacks the
# word after it and this part stacks the word itself.
#
# THE PAIR IS THE MEASUREMENT AND NOT EITHER LITERAL. Each run is held to ITS
# OWN program address, so a core that stacked a constant satisfies neither, a
# core that stacked nothing satisfies neither, and a core that stacked the
# Version 3 value satisfies neither - while a core that stacked the address of
# whatever instruction it happened to be running satisfies both, which is what
# the sentence says.
let stackedPair = (at: post.stackedPc, atAlt: postAlt.stackedPc)
let wantStackedPair = (at: execBase, atAlt: execBaseAlt)
check(stackedPair == wantStackedPair,
      "the stacked program counter points to the faulting instruction",
      "0x" & toHex(stackedPair.at) & " and 0x" & toHex(stackedPair.atAlt),
      "0x" & toHex(wantStackedPair.at) & " and 0x" &
        toHex(wantStackedPair.atAlt))

# ---------------------------------------------------------------------------
# Block 3. The other auto-addressing direction, so that the surviving register
# update is measured with its sign reversed rather than once.
#
# `-(%a0)` decrements before the access, so A0 starts one longword above the
# refused address and ends on it. A core that rolled the addressing-mode update
# back on a fault would leave A0 at its pre-instruction value, which is the
# value this case's start is chosen to make distinguishable from the expected
# one.

const wantFaultedPre: WriteOutcome =
  (sp: frameBase, pc: accessHandler, sr: 0x2708'u32, halted: false,
   fault: false, frame: 0x48092700'u32, a0: protectedWord,
   d0: sourceD0, stored: 0'u32, offBoard: 0)

let pre = runWrite(opMovePre, execBase, protectedWord + 4'u32, protectedWord)
check(pre.outcome == wantFaultedPre,
      "a predecrement refused store keeps its decremented address register",
      $pre.outcome, $wantFaultedPre)

# ---------------------------------------------------------------------------
# Block 4. The negative control: the same instruction, the same board, an
# address the board accepts.
#
# Without it every case above would pass against a core that faulted on every
# write. This run pins that the fault is caused by the refusal and not by the
# instruction shape: no frame is stacked, the stack pointer does not move, the
# program counter reaches the next instruction rather than the handler, and the
# longword arrives in memory. The register write-back is the same in both, and
# that is the point - it is the fault, not the write-back, that the two runs
# differ in.

const wantAccepted: WriteOutcome =
  (sp: startSp, pc: execBase + 2'u32, sr: 0x2708'u32, halted: false,
   fault: false, frame: 0'u32, a0: openWord + 4'u32, d0: sourceD0,
   stored: sourceD0, offBoard: 0)

let accepted = runWrite(opMovePost, execBase, openWord, openWord)
check(accepted.outcome == wantAccepted,
      "the same store to an accepted address takes no fault at all",
      $accepted.outcome, $wantAccepted)

# ---------------------------------------------------------------------------
# Block 5. THE CONDITION CODES A REFUSED CLR LEAVES IN THE FRAME.
#
# MCF5407 User's Manual Table 2-22, "MCF5407 Exceptions", the Access Error row,
# folio 2-34: "The Version 4 processor, unlike the Version 2 and 3 processors,
# updates the condition code register if a write-protect error occurs during a
# CLR or MOV3Q operation to memory." MOV3Q is Revision B and this core does not
# decode it, so CLR is the whole of the reachable half.
#
# WHAT VALUE THE REGISTER TAKES IS NOT IN THE MANUAL. It is this core's choice,
# argued for at `execClr` in `src/mcf5407/alu.nim` and settled by nothing in
# this repository: the value is CLR's ordinary result, N, V and C clear and Z
# set. THE LITERALS BELOW PIN THAT CHOICE AND CITE THE MANUAL ONLY FOR THE FACT
# THAT SOME UPDATE HAPPENS. A run on silicon replaces them.
#
# The frame's first longword is hand-derived from Figure 2-1's bit positions,
# and it is the case's whole subject: it differs from every other frame in this
# file in its low sixteen bits alone.
#   0100 | 10 | 00000010 | 01 | 0010011100000100 -> 0x48092704
# A Version 2 or 3 stacks 0x48092700 there - the status register as the store
# found it, which is what `writeMem` records and what a MOVE still stacks.
#
# THE ACCEPTED RUN IS WHERE THE CHOSEN VALUE COMES FROM, AND IT IS HERE SO THAT
# THE CHOICE CANNOT BE READ AS AN INVENTION. The same CLR to an address the
# board takes leaves the live status register at 0x2704; the refused run puts
# that same word in the frame. A core that wrote some other value into the
# frame would break the equality between the two runs, which is the argument
# `execClr` makes stated as a case.

const
  opClrInd = 0x4290'u16      ## `clr.l (%a0)`, m68k-elf-as -mcpu=5307

const wantClrRefused: WriteOutcome =
  (sp: frameBase, pc: accessHandler, sr: 0x2704'u32, halted: false,
   fault: false, frame: 0x48092704'u32, a0: protectedWord,
   d0: sourceD0, stored: 0'u32, offBoard: 0)

let clrRefused = runWrite(opClrInd, execBase, protectedWord, protectedWord)
check(clrRefused.outcome == wantClrRefused,
      "a refused CLR stacks the condition codes the clear wrote",
      $clrRefused.outcome, $wantClrRefused)

const wantClrAccepted: WriteOutcome =
  (sp: startSp, pc: execBase + 2'u32, sr: 0x2704'u32, halted: false,
   fault: false, frame: 0'u32, a0: openWord, d0: sourceD0,
   stored: 0'u32, offBoard: 0)

let clrAccepted = runWrite(opClrInd, execBase, openWord, openWord)
check(clrAccepted.outcome == wantClrAccepted,
      "the same CLR to an accepted address takes no fault and sets the same Z",
      $clrAccepted.outcome, $wantClrAccepted)

let clrCcPair = (inFrame: clrRefused.outcome.frame and 0xFFFF'u32,
                 live: clrAccepted.outcome.sr and 0xFFFF'u32)
check(clrCcPair.inFrame == clrCcPair.live,
      "the stacked status register is the one an unrefused CLR leaves live",
      $clrCcPair, "the two equal")

# ---------------------------------------------------------------------------
# One instruction, two faults, and the second one is not stacked.
#
# `bsr` to an odd target whose return-address push lands on the refused
# longword. The push records the access error and lets the instruction finish,
# which is the rule of MCF5307 User's Manual section 3.5.1, folio 3-15 - cited
# because the MCF5407 manual condenses that section into Table 2-22 and does
# not reproduce the sentence; `transferControl` then takes the address error,
# because MCF5407 User's Manual Table 2-22, "Address Error", folio 2-34, makes
# "an attempted execution transferring control to an odd instruction address
# (that is, if bit 0 of the target address is set)" one. Stacking the recorded
# access error afterwards would put two
# frames on the stack for one instruction, and the access handler's `RTE`
# would return into the address handler's first instruction rather than into
# the program.
#
# The manual set carries no rule for a write error still outstanding when the
# same instruction has already entered a handler. This core stops instead of
# choosing one: `fault` and `halted` are what its stacking layer already
# raises for a fault it cannot represent, and `transferControl`'s own comment
# names the fault-on-fault halted state for the neighbouring case.
#
# `below` is the discriminating field. It reads the longword where a second
# frame's first word would land, and a run that stacked one leaves it
# non-zero.
#
# The frame's first longword is hand-derived from Figure 2-1's bit positions.
# A7 is 0x0C00 with its low two bits 00, so Table 2-20 gives format 4 and a
# frame at 0x0C00 - 8. The vector is 3. `FS` is `0100`, Table 2-21's "Error on
# instruction fetch":
#   0100 | 01 | 00000011 | 00 | 0010011100000000 -> 0x440C2700

const
  doubleSp = 0x0C04'u32        ## so the BSR push lands on `protectedWord`
  doubleFrame = 0x0BF8'u32     ## (0x0C00 - 8) and not 3, with FORMAT 4
  addressHandler = 0x0680'u32
  vecAddress = 3'u8            ## the address error, at $00C
  opBsrOdd = 0x6101'u16        ## `bsr.b .+3`, m68k-elf-as -mcpu=5307

block:
  freshBoard()
  offBoardWrites = 0
  boardWrite(board, execBase, 2, uint32(opBsrOdd))
  boardWrite(board, addressHandler, 2, uint32(opRteWord))
  boardWrite(board, accessHandler, 2, uint32(opRteWord))
  boardWrite(board, 4'u32 * uint32(vecAddress), 4, addressHandler)
  boardWrite(board, 4'u32 * uint32(vecAccess), 4, accessHandler)

  let ctx = mcf5407_create(addr board, protectedRead, protectedWrite, bIack)
  mcf5407_reset(ctx, doubleSp, execBase)
  discard mcf5407_exec(ctx, 1'u32)
  let got = (sp: mcf5407_get_reg(ctx, 15),
             pc: mcf5407_get_reg(ctx, 17),
             halted: ctx.halted,
             fault: ctx.fault,
             frame: boardReadValue(board, doubleFrame, 4),
             below: boardReadValue(board, doubleFrame - 8'u32, 4))
  mcf5407_destroy(ctx)
  let wanted = (sp: doubleFrame, pc: addressHandler, halted: true,
                fault: true, frame: 0x440C2700'u32, below: 0'u32)
  check(got == wanted,
        "a faulted push and an odd branch target stack one frame, not two",
        $got, $wanted)

# The registry lines. They are data and not a verdict: this program reports
# what its text declares and what its run adjudicated, and the registered
# test's driver is what compares them. A verdict printed here would be a
# self-assessment, and a run that stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_bus_fault_write", declaredCaseSites)
echo caseSiteLine("executed", "t_bus_fault_write", executedSites)
echo caseSiteLine("off-green-path", "t_bus_fault_write",
                  declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_bus_fault_write: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_bus_fault_write: ", passCount, " cases passed"
