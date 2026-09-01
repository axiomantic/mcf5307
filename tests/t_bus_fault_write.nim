## `t_bus_fault_write` - the imprecise stacked program counter of an operand
## write fault.
##
## It asserts that the fault was taken and that the write instruction's
## register write-back completed. It does not assert the stacked program
## counter, and no expected value in this file carries one.
##
## The write cycle may be decoupled from the processor's issuing of the
## operation, so the PC in the exception stack frame merely represents the
## location in the program when the access error was signaled, and all
## programming model updates associated with the write instruction are
## completed.
##
## So a pinned program counter would be a defect in this file and not a
## measurement. The general rule stacks the PC of the instruction that caused
## the exception, and the write direction withdraws exactly that. A case that
## held the frame's second longword to any literal would go red against a core that reported at a different point in the write
## pipeline, which is behaviour the manual permits; the reader would then be
## told a correct core is broken.
##
## The omission is made non-vacuous rather than left as silence. The same
## faulting instruction runs at two program addresses and the asserted outcome
## is one constant for both, so the outcome is measured to be independent of a
## stacked program counter that provably moved between the runs; and the runner
## returns that program counter outside the asserted tuple, so a later edit
## cannot fold it back in without deleting a field.
##
## Every expected value below is a hand-derived literal, written beside the bit
## string or the manual row it came from, and not a second call of the
## procedure under test. Every opcode is the output of `m68k-elf-as -mcpu=5307`
## on the mnemonic printed beside it.

import std/strutils

import mcf5307/cpu
import mcf5307/decode_types
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
# longword and reports `MCF5307_BUS_FAULT` for it.
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
                   status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return 0'u32
  status[] = Mcf5307BusStatus.busOk
  boardReadValue(b[], address, int(size))

proc protectedWrite(user: pointer; address: uint32; size: cint; value: uint32;
                    status: ptr Mcf5307BusStatus) {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    inc offBoardWrites
    status[] = Mcf5307BusStatus.busUnmapped
    return
  if address == protectedWord:
    status[] = Mcf5307BusStatus.busFault
    return
  status[] = Mcf5307BusStatus.busOk
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

  let ctx = mcf5307_create(addr board, protectedRead, protectedWrite, bIack)
  mcf5307_reset(ctx, startSp, at)
  discard mcf5307_set_reg(ctx, 0, sourceD0)
  discard mcf5307_set_reg(ctx, 8, a0Init)
  discard mcf5307_exec(ctx, 1'u32)
  result = (outcome: (sp: mcf5307_get_reg(ctx, 15),
                      pc: mcf5307_get_reg(ctx, 17),
                      sr: mcf5307_get_reg(ctx, 16),
                      halted: ctx.halted,
                      fault: ctx.fault,
                      frame: boardReadValue(board, frameBase, 4),
                      a0: mcf5307_get_reg(ctx, 8),
                      d0: mcf5307_get_reg(ctx, 0),
                      stored: boardReadValue(board, target, 4),
                      offBoard: offBoardWrites),
            stackedPc: boardReadValue(board, frameBase + 4'u32, 4))
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# Block 1. The fault is taken and the write instruction's register write-back
# completes.
#
# The frame's first longword is hand-derived from the bit positions and not
# from a second call of the encoder. A7 is 0x800 with its low two bits 00, so
# Table 3-2, folio 3-14, gives format 4 and a frame at 0x800 - 8. The vector is
# 2. `FS` is `1001`, Table 3-3's "Attempted write to write-protected space",
# and its two halves land in two non-adjacent fields of Figure 3-7:
#   0100 | 10 | 00000010 | 01 | 0010011100000000 -> 0x48092700
# This longword carries no program counter. Figure 3-7, folio 3-13, puts the
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
# Block 2. The stacked program counter moved between those two runs, and
# neither value is pinned.
#
# This is the one case that reads the frame's second longword, and it compares
# the two runs with each other rather than either with a literal. Folio 3-15
# fixes the stacked value only as "the location in the program when the access
# error was signaled", so an implementation may report at more than one point
# in its write pipeline and every such choice is correct. What the manual does
# not permit is a value unrelated to where the program was: two runs of one
# instruction placed 0x40 apart must not stack the same location.
#
# Without this case the omission above would be indistinguishable from an
# oversight. The two runs are asserted against one constant, and a core that
# stacked nothing at all in either run would satisfy that constant just as
# well; this case is what requires the program counter to have been stacked and
# to have moved.
check(post.stackedPc != postAlt.stackedPc,
      "the stacked program counter tracks the program and is not pinned here",
      "0x" & toHex(post.stackedPc) & " vs 0x" & toHex(postAlt.stackedPc),
      "two different values")

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
