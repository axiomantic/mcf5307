## `t_bus_fault` - the bus-fault channel of `mcf5407/bus`.
##
## The documents this file cites are outside this repository and are named in
## full, so that a citation can be checked without knowing this project.
##
##   THE MCF5407 USER'S MANUAL: Motorola, "MCF5407 ColdFire Integrated
##   Microprocessor User's Manual", order number MCF5407UM/D, Rev. 0.1,
##   11/2001. This is the part this suite targets and the source of every
##   citation below unless a citation says otherwise. Each one names its
##   section, table and folio page.
##
##   THE MCF5307 USER'S MANUAL: Motorola, "MCF5307 ColdFire Integrated
##   Microprocessor User's Manual", order number MCF5307UM/AD, (c) 1998. Cited
##   ONLY where it is the source, because the MCF5407 manual condenses the
##   MCF5307's section 3.5 "Processor Exceptions" into one table, Table 2-22,
##   and does not reproduce the narrative paragraphs on imprecise reporting of
##   access errors on operand writes. Each such citation says so at the point
##   of use.
##
## EVERY EXPECTED VALUE BELOW IS A HAND-DERIVED LITERAL and NOT a second call
## of the procedure under test.
##
## The fault status encodings are facts about Motorola silicon, from the
## MCF5407 User's Manual named above.

import std/strutils

import mcf5407/bus
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

proc checkEqImpl(site: int; got: uint32; want: uint32; label: string) =
  checkImpl(site, got == want, label, "0x" & toHex(got), "0x" & toHex(want))


template checkEq(got: uint32; want: uint32; label: string) =
  ## THE CALL SITE IS RECORDED TWICE, for the reason `check` above gives.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkEqImpl(site, got, want, label)

# ---------------------------------------------------------------------------
# BLOCK 1. The mapping from a bus status to a fault status code.
#
# User's Manual section 2.8.1, Table 2-21, "Fault Status Encodings", folio 2-33
# (PDF page 99), gives the defined fault status encodings for this part:
# `0000` not an access or address error nor an interrupted debug service
# routine, `0010` interrupt during a debug service routine, `0100` error on
# instruction fetch, `1000` error on operand write, `1001` attempted write to
# write-protected space, and `1100` error on operand read. Every other value of
# the four bits is Reserved.
#
# THE MAPPING TABLE assigns codes to the non-OK bus statuses, and each expected
# value below is the code that table's own row prints.

checkEq(faultStatusFor(Mcf5407BusStatus.busFault, operandWrite),
        0b1001'u32,
        "mapping: a device fault on a write is 1001")
checkEq(faultStatusFor(Mcf5407BusStatus.busFault, operandRead),
        0b1001'u32,
        "mapping: a device fault on a read is 1001")

checkEq(faultStatusFor(Mcf5407BusStatus.busUnmapped, operandRead),
        0b1100'u32,
        "mapping: unmapped on a read is 1100")
checkEq(faultStatusFor(Mcf5407BusStatus.busUnmapped, operandWrite),
        0b1000'u32,
        "mapping: unmapped on a write is 1000")

checkEq(faultStatusFor(Mcf5407BusStatus.busSizeIllegal, operandRead),
        0b1100'u32,
        "mapping: an illegal width on a read is 1100")
checkEq(faultStatusFor(Mcf5407BusStatus.busSizeIllegal, operandWrite),
        0b1000'u32,
        "mapping: an illegal width on a write is 1000")

# `busOk` IS NOT A ROW OF THE MAPPING TABLE and it is mapped anyway, so that
# the procedure is total over the enumeration. Table 2-21's own `0000` is the
# code for "not an access or address error nor an interrupted debug service
# routine", which is what a completed access is.
checkEq(faultStatusFor(Mcf5407BusStatus.busOk, operandRead),
        0b0000'u32,
        "mapping: a completed read is 0000")
checkEq(faultStatusFor(Mcf5407BusStatus.busOk, operandWrite),
        0b0000'u32,
        "mapping: a completed write is 0000")

# ---------------------------------------------------------------------------
# BLOCK 2. The class column of the same table, asserted rather than described.
#
# Only one of the three rows is silicon behaviour. The class is a value this
# module answers for, so that a
# reader who mistakes an extension for hardware behaviour is contradicted by a
# case rather than by a comment.

check(isEmulatorExtension(Mcf5407BusStatus.busFault) == false,
      "class: a write-protect fault is real MCF5307 behaviour",
      $isEmulatorExtension(Mcf5407BusStatus.busFault), "false")
check(isEmulatorExtension(Mcf5407BusStatus.busUnmapped) == true,
      "class: unmapped is this emulator's own extension",
      $isEmulatorExtension(Mcf5407BusStatus.busUnmapped), "true")
check(isEmulatorExtension(Mcf5407BusStatus.busSizeIllegal) == true,
      "class: an illegal width is this emulator's own extension",
      $isEmulatorExtension(Mcf5407BusStatus.busSizeIllegal), "true")
check(isEmulatorExtension(Mcf5407BusStatus.busOk) == false,
      "class: a completed access is not a fault of any class",
      $isEmulatorExtension(Mcf5407BusStatus.busOk), "false")

# ---------------------------------------------------------------------------
# The two boards. One flat byte array, big-endian, reached through TWO pairs of
# callbacks that differ in exactly one thing: whether they write `*status` at
# all.
#
# NEITHER PAIR EVER REPORTS A NON-OK VALUE, which is what makes both of them
# evidence about the core rather than about a board's decode.
#
# An access outside the array returns zero and reports nothing. The silent pair
# has no channel to report one on, and a pair that indexed the array anyway
# would end the process under `--panics:on`; an abort inside a plugin destroys
# the host's session.

const
  memSize = 0x1000
  execBase = 0x400'u32      ## above the whole 1024-byte vector table
  trapHandler = 0x500'u32
  frameBase = 0x7F8'u32     ## Table 2-20: 0x800 - 8, with FORMAT 4
  srReset = 0x2700'u32
  opTrap0 = 0x4E40'u16      ## `trap #0`, m68k-elf-as -mcpu=5307
  opRteWord = 0x4E73'u16    ## `rte`, the same assembler
  trapVector = 32'u8

type TestBoard = object
  bytes: array[memSize, uint8]

var board: TestBoard

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

proc silentRead(user: pointer; address: uint32; size: cint;
                status: ptr Mcf5407BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  boardReadValue(b[], address, int(size))

proc silentWrite(user: pointer; address: uint32; size: cint; value: uint32;
                 status: ptr Mcf5407BusStatus) {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  boardWrite(b[], address, int(size), value)

proc explicitRead(user: pointer; address: uint32; size: cint;
                  status: ptr Mcf5407BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  status[] = Mcf5407BusStatus.busOk
  boardReadValue(b[], address, int(size))

proc explicitWrite(user: pointer; address: uint32; size: cint; value: uint32;
                   status: ptr Mcf5407BusStatus) {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  status[] = Mcf5407BusStatus.busOk
  boardWrite(b[], address, int(size), value)

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

proc freshBoard() =
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8

# ---------------------------------------------------------------------------
# BLOCK 3. Silence means success, through the published entry points.
#
# The core writes `MCF5407_BUS_OK` into `*status` before every call, so a board
# that never writes it behaves exactly as it did before the parameter existed.
# The two pairs of callbacks differ in nothing else, and each run is held
# against the same hand-stated outcome
# rather than against the other run: two runs compared only with each other
# would agree just as well if the core had stopped executing altogether.
#
# The path is the published one - `mcf5407_create`, `mcf5407_reset`,
# `mcf5407_exec` - and not an internal helper reached around the back. `trap #0`
# then `rte` is chosen because exception entry reads the vector table, writes
# both longwords of the frame and fetches, so one program exercises the read,
# the write and the fetch call sites together.
#
# WHAT THESE TWO CASES DO NOT REACH, STATED SO THEIR SILENCE IS NOT READ AS
# COVERAGE. What they pin is the VALUE the board observes, which is `busOk`,
# and not the WRITE that puts it there. A location of this type that is left
# uninitialized holds zero, and zero is `busOk`, so a core that dropped the
# assignment and a core that kept it present the same cell to the board. These
# cases separate a WRONG default from a right one; they cannot separate an
# explicit right default from an implicit one.

type Outcome = tuple[sp: uint32, pc: uint32, sr: uint32, halted: bool,
                     fault: bool, frame: uint32, framePc: uint32]

proc runTrap(rd: Mcf5407ReadFn; wr: Mcf5407WriteFn): Outcome =
  freshBoard()
  boardWrite(board, execBase, 2, uint32(opTrap0))
  boardWrite(board, trapHandler, 2, uint32(opRteWord))
  boardWrite(board, 4'u32 * uint32(trapVector), 4, trapHandler)

  let ctx = mcf5407_create(addr board, rd, wr, bIack)
  mcf5407_reset(ctx, 0x800'u32, execBase)
  discard mcf5407_exec(ctx, 1'u32)
  result = (sp: mcf5407_get_reg(ctx, 15),
            pc: mcf5407_get_reg(ctx, 17),
            sr: mcf5407_get_reg(ctx, 16),
            halted: ctx.halted,
            fault: ctx.fault,
            frame: boardReadValue(board, frameBase, 4),
            framePc: boardReadValue(board, frameBase + 4'u32, 4))
  mcf5407_destroy(ctx)

# THE EXPECTED OUTCOME IS HAND-DERIVED. A7 is 0x800 with its low two bits 00,
# so Table 2-20, folio 2-33, gives FORMAT 4 and a frame at 0x800 - 8. `trap #0`
# is one word and Table 2-19, folio 2-32, gives a trap a stacked program
# counter of "Next", so the stacked value is `execBase + 2`. `FS` is 0000:
# Table 2-21 defines the field for access and address errors and for
# interrupted debug service routines only.
#   0100 | 00 | 00100000 | 00 | 0010011100000000 -> 0x40802700
const wantTrap: Outcome = (sp: frameBase, pc: trapHandler, sr: srReset,
                           halted: false, fault: false,
                           frame: 0x40802700'u32, framePc: execBase + 2'u32)

let silent = runTrap(silentRead, silentWrite)
check(silent == wantTrap,
      "silence means success: a board that never writes *status",
      $silent, $wantTrap)

let explicit = runTrap(explicitRead, explicitWrite)
check(explicit == wantTrap,
      "an explicit MCF5407_BUS_OK is the same run",
      $explicit, $wantTrap)

# ---------------------------------------------------------------------------
# BLOCK 4. The core originates no bus status of its own.
#
# `MCF5407_BUS_UNMAPPED` and `MCF5407_BUS_SIZE_ILLEGAL` have no producer on
# this part - User's Manual section 2.8.2, Table 2-22, "Access Error", folio
# 2-34, holds that an access error is reported only for a store to
# write-protected memory - so the only thing that can raise one is a board's
# own decode.
#
# THE SWEEP IS THE ASSERTION: every access below is answered by a pair
# of callbacks that report nothing at all, across the whole address range and
# every width, and none of them faults the core.
#
# THE VALUE IS READ BACK RATHER THAN THE FAULT FLAGS ALONE, so a core that
# answered without calling the board would be red here too.

type Access = tuple[address: uint32, size: uint8, want: uint32]

const sweep: array[7, Access] = [
  (address: 0x000'u32, size: 1'u8, want: 0x78'u32),
  (address: 0x001'u32, size: 2'u8, want: 0x5678'u32),
  (address: 0x100'u32, size: 4'u8, want: 0x12345678'u32),
  (address: 0x555'u32, size: 1'u8, want: 0x78'u32),
  (address: 0x800'u32, size: 2'u8, want: 0x5678'u32),
  (address: 0xFFC'u32, size: 4'u8, want: 0x12345678'u32),
  (address: 0xFFF'u32, size: 1'u8, want: 0x78'u32)]

freshBoard()
let sweepCtx = mcf5407_create(addr board, silentRead, silentWrite, bIack)
mcf5407_reset(sweepCtx, 0x800'u32, execBase)
for access in sweep:
  writeMem(sweepCtx, access.address, access.size, 0x12345678'u32)
  let seen = (value: readMem(sweepCtx, access.address, access.size),
              fault: sweepCtx.fault,
              halted: sweepCtx.halted)
  let wantSeen = (value: access.want, fault: false, halted: false)
  check(seen == wantSeen,
        "no core-originated status: " & $access.size & " bytes at 0x" &
          toHex(access.address),
        $seen, $wantSeen)
mcf5407_destroy(sweepCtx)

# ---------------------------------------------------------------------------
# BLOCK 5. A non-OK bus status becomes an access fault, and the frame carries a
# NON-ZERO `FS` through the core.
#
# BLOCK 5 SEPARATES A SPLIT `FS` ENCODER FROM A CONTIGUOUS ONE. Of the
# codes User's Manual Table 2-21, folio 2-33, defines, `1001` is the only one
# whose low half is not zero, so it is the only value that lands in BOTH
# halves of the split field. A frame carrying `FS` `0000` cannot separate
# "encodes the field as zero" from "has no field": both produce the same
# longword.
#
# THE ROW IS THE ONE THAT IS REAL SILICON. User's Manual section 2.8.2,
# Table 2-22, "Access Error", folio 2-34, verbatim: "Access errors are reported
# only in conjunction with an attempted store to write-protected memory. Thus,
# access errors associated with instruction fetch or operand read accesses are
# not possible." The board below refuses exactly one longword and reports
# `MCF5407_BUS_FAULT` for it.
#
# THE THIRD BOARD REPORTS A NON-OK STATUS, which is what separates it from the
# two above: those two exist to show that silence is success, and this one
# exists to show what a report does.

const
  protectedWord = 0x0C00'u32  ## the one longword this board refuses to store
  accessHandler = 0x600'u32
  vecAccess = 2'u8            ## Table 2-19, folio 2-32: access error, at $008
  opMoveProtected = 0x21C0'u16  ## `move.l %d0,0xC00`, m68k-elf-as -mcpu=5307
  extProtected = 0x0C00'u16     ## its `(xxx).W` extension word
  doubleSp = 0x1008'u32       ## Table 2-20: a frame base of 0x1000, off the board
  doubleFrameBase = 0x1000'u32

# AN ACCESS PAST THE ARRAY IS COUNTED AND NOT ONLY REFUSED. The count is what
# separates a core that halted on a fault during stacking from one that
# re-entered the stacking and tried again; both leave the same flags.
var offBoardWrites = 0

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

type FaultOutcome = tuple[sp: uint32, pc: uint32, sr: uint32, halted: bool,
                          fault: bool, frame: uint32, framePc: uint32,
                          offBoard: int]

proc runProtectedStore(startSp: uint32; readFrameAt: uint32): FaultOutcome =
  freshBoard()
  offBoardWrites = 0
  boardWrite(board, execBase, 2, uint32(opMoveProtected))
  boardWrite(board, execBase + 2'u32, 2, uint32(extProtected))
  boardWrite(board, accessHandler, 2, uint32(opRteWord))
  boardWrite(board, 4'u32 * uint32(vecAccess), 4, accessHandler)

  let ctx = mcf5407_create(addr board, protectedRead, protectedWrite, bIack)
  mcf5407_reset(ctx, startSp, execBase)
  discard mcf5407_exec(ctx, 1'u32)
  result = (sp: mcf5407_get_reg(ctx, 15),
            pc: mcf5407_get_reg(ctx, 17),
            sr: mcf5407_get_reg(ctx, 16),
            halted: ctx.halted,
            fault: ctx.fault,
            frame: boardReadValue(board, readFrameAt, 4),
            framePc: boardReadValue(board, readFrameAt + 4'u32, 4),
            offBoard: offBoardWrites)
  mcf5407_destroy(ctx)

# The expected frame is hand-derived from the bit positions and not from a
# second call of the encoder. A7 is 0x800 with its low two bits 00, so Table
# 2-20, folio 2-33, gives FORMAT 4 and a frame at 0x800 - 8. The vector is 2.
# `FS` is `1001`, the code for a write to write-protected space, and its two
# halves land in two non-adjacent fields:
#   0100 | 10 | 00000010 | 01 | 0010011100000000 -> 0x48092700
# The stacked program counter is the FAULTING INSTRUCTION'S OWN ADDRESS and not
# where the write pipeline had reached. MCF5407 User's Manual section 4.9.5.1,
# "Cache Filling", folio 4-17: "Note that unlike Version 2 and Version 3 access
# errors, the program counter stored on the exception stack frame points to the
# faulting instruction." A Version 3 stacks execBase + 4 here, past the opcode
# word and the one `(xxx).W` extension word; this part stacks execBase.
#
# THE LIVE STATUS REGISTER IS 0x2704 AND THE FRAME'S COPY IS 0x2700, AND THE
# DIFFERENCE IS REQUIRED RATHER THAN TOLERATED. THE MCF5307 USER'S MANUAL IS
# THE SOURCE OF THE SENTENCE, because the MCF5407 manual replaces the MCF5307's
# section 3.5.1 narrative with Table 2-22 and drops this paragraph: MCF5307
# User's Manual section 3.5.1, folio 3-15, verbatim, of an access error on an
# operand write: "All programming model updates associated with the write
# instruction are completed." The rule still holds on this part - MCF5407
# User's Manual Table 2-22, "Access Error", folio 2-34, records only that the
# Version 4 core additionally updates the condition code register when the
# write-protect error happens on a CLR or MOV3Q, which is a widening and not a
# contradiction. `MOVE`
# sets Z from its source AFTER the store, and the source here is zero, so Z is
# set once the faulting instruction finishes. The frame carries the copy
# `takeException` took BEFORE that, which is why the two differ by exactly Z.
const wantProtected: FaultOutcome =
  (sp: frameBase, pc: accessHandler, sr: 0x2704'u32, halted: false,
   fault: false, frame: 0x48092700'u32, framePc: execBase,
   offBoard: 0)

let protectedStore = runProtectedStore(0x800'u32, frameBase)
check(protectedStore == wantProtected,
      "a write-protected store takes an access fault carrying FS 1001",
      $protectedStore, $wantProtected)

# ---------------------------------------------------------------------------
# BLOCK 6. A fault DURING the stacking is a double fault: the core halts and
# does not recurse.
#
# A fault inside the exception-entry stacking itself is a double fault: the
# core halts, sets its own fault field, and returns from `mcf5407_exec` with the
# cycles it spent. It does not recurse.
#
# A7 is 0x1008, so the frame base is 0x1000 and is off the board. The same
# write-protected store faults, the access fault is taken, and the first
# longword of its frame is refused in turn.
#
# THE ASSERTION THAT NO RECURSION HAPPENED IS THE COUNT AND NOT THE FLAGS. A
# core that re-entered the stacking would set exactly the same `halted` and
# `fault` and would attempt the same write again; only the number of attempts
# tells the two apart, and a correct core attempts it ONCE.
#
# NOTHING IS STACKED AND THE STACK POINTER DOES NOT MOVE, because `takeException`
# commits A7 only after both longwords are written.
#
# THE STATUS REGISTER IS 0x2704 HERE FOR THE REASON BLOCK 5 GIVES, AND THE TWO
# BLOCKS NOW AGREE RATHER THAN DIFFER. MCF5307 User's Manual section 3.5.1,
# folio 3-15, cited because the MCF5407 manual does not reproduce the sentence:
# "All programming model updates associated with the write instruction are
# completed." The access error of a faulted store is taken at the instruction
# boundary, so `MOVE` has already set Z from its zero source by the time the
# stacking is attempted - and the stacking failing does not un-complete an
# update the manual required. A `0x2700` here would mean the double fault had
# reached back into the faulting instruction and cancelled half of it.

const wantDoubleFault: FaultOutcome =
  (sp: doubleSp, pc: execBase + 4'u32, sr: 0x2704'u32, halted: true,
   fault: true, frame: 0'u32, framePc: 0'u32, offBoard: 1)

let doubleFault = runProtectedStore(doubleSp, doubleFrameBase)
check(doubleFault == wantDoubleFault,
      "a fault while stacking halts the core and does not recurse",
      $doubleFault, $wantDoubleFault)

# ---------------------------------------------------------------------------
# BLOCK 7. An operand read fault still halts and takes no vector. This case
# pins a boundary and does not endorse it.
#
# A read of unmapped space ought to take an access fault, and this core does not
# do that yet. The blocker is that a fault must be taken "before it commits any
# register or memory side effect of the faulting instruction", together with the
# fact that `ctx.halted` is the only signal that unwinds a part-completed
# instruction. An access fault must not halt, so a read that took a vector would
# return into an executor that finished the instruction with a zero operand.
# Measured, with the vector taken: `d1` came back 0 over its
# sentinel, and the frame itself was correct - `0x4C082700`, `FS` `1100`.
#
# THE FIX IS NOT WRITABLE FROM THE FILES THIS SUITE COVERS. It needs a
# pending-fault field on `MCF5407Ctx` in `src/mcf5407/decode_types.nim`, or a
# check after the executor returns in `src/mcf5407/cpu.nim`'s `step`.
#
# SO THIS CASE ASSERTS WHAT THE CORE DOES AND SAYS WHY IT IS NOT WHAT THE CORE
# SHOULD DO. It goes RED the moment the read path is wired, which is the point:
# whoever wires it must come here, read this block, and replace it with the
# vector-taking outcome rather than discover the gap by accident.
#
# `move.l 0x1000,%d1` READS OFF THE BOARD. The sentinel survives because
# `execMove` checks `ctx.halted` between the read and the register write-back.

const
  opMoveReadFault = 0x2238'u16  ## `move.l 0x1000,%d1`, m68k-elf-as -mcpu=5307
  extReadFault = 0x1000'u16     ## its `(xxx).W` extension word, off the board
  sentinelD1 = 0xDEADBEEF'u32

type ReadOutcome = tuple[d1: uint32, pc: uint32, halted: bool, fault: bool,
                         frame: uint32, framePc: uint32]

proc runFaultingRead(): ReadOutcome =
  freshBoard()
  offBoardWrites = 0
  boardWrite(board, execBase, 2, uint32(opMoveReadFault))
  boardWrite(board, execBase + 2'u32, 2, uint32(extReadFault))
  boardWrite(board, accessHandler, 2, uint32(opRteWord))
  boardWrite(board, 4'u32 * uint32(vecAccess), 4, accessHandler)

  let ctx = mcf5407_create(addr board, protectedRead, protectedWrite, bIack)
  mcf5407_reset(ctx, 0x800'u32, execBase)
  discard mcf5407_set_reg(ctx, 1, sentinelD1)
  discard mcf5407_exec(ctx, 1'u32)
  result = (d1: mcf5407_get_reg(ctx, 1),
            pc: mcf5407_get_reg(ctx, 17),
            halted: ctx.halted,
            fault: ctx.fault,
            frame: boardReadValue(board, frameBase, 4),
            framePc: boardReadValue(board, frameBase + 4'u32, 4))
  mcf5407_destroy(ctx)

# NOTHING IS STACKED, so both frame longwords read back as the zeroed board.
# The program counter stays where the opcode word and the one `(xxx).W`
# extension word left it, because no handler address is loaded.
const wantFaultingRead: ReadOutcome =
  (d1: sentinelD1, pc: execBase + 4'u32, halted: true, fault: true,
   frame: 0'u32, framePc: 0'u32)

let faultingRead = runFaultingRead()
check(faultingRead == wantFaultingRead,
      "an operand read fault halts and takes no vector: the unwired half",
      $faultingRead, $wantFaultingRead)

# ---------------------------------------------------------------------------
# BLOCK 8. AN INSTRUCTION WHOSE OWN STACK PUSH FAULTS LANDS IN THE HANDLER, AND
# ITS PROGRAMMING-MODEL UPDATES ARE COMPLETED FIRST.
#
# THE TWO HALVES ARE ONE SENTENCE OF THE MANUAL AND NOT A COMPROMISE BETWEEN
# TWO. THE MCF5307 USER'S MANUAL IS THE SOURCE AND IS CITED DELIBERATELY: the
# MCF5407 manual condenses the MCF5307's section 3.5 into Table 2-22 and
# reproduces none of this paragraph, so there is no MCF5407 folio to point at.
# MCF5307 User's Manual section 3.5.1, "Access Error Exception", printed page
# 3-15, verbatim: "The ColdFire processor uses an imprecise reporting mechanism
# for access errors on operand writes. Because the actual write cycle may be
# decoupled from the processor's issuing of the operation, the signaling of an
# access error appears to be decoupled from the instruction that generated the
# write. ... All programming model updates associated with the write
# instruction are completed."
#
# So the faulting instruction FINISHES - which is what BLOCK 5 asserts of
# `MOVE`'s condition codes - and only then does the exception processing of
# MCF5407 User's Manual section 2.8, folio 2-31, run. An exception taken AT the
# store instead performs that section's third and fourth steps, which assign A7
# and the program counter, in the middle of an instruction that then completes
# against what those steps left.
#
# MEASURED ON THIS TREE BEFORE THE DEFERRAL EXISTED, with A7 at 0x0C04 so that
# each push lands on `protectedWord`: `jsr` ended at 0x0700, its own target,
# with the handler address discarded; `bsr.w` ended at 0x0442, its own branch
# target; and `link` ended at 0x0602 - two bytes INTO the handler, because
# `fetchExt` read the handler's first opword as the displacement - with that
# opword, `rte` as 0x4E73, sign-extended and added to A7 to give 0x5A6B, and
# with the exception frame base written into A0.
#
# THE STACKED PROGRAM COUNTER IS SETTLED AND THE STATUS REGISTER IS NOT, AND
# THE TWO CARRY DIFFERENT AUTHORITY BELOW BECAUSE OF IT. The MCF5307 passage
# calls the reporting imprecise and says the stacked program counter "merely
# represents the location in the program when the access error was signaled",
# which fixes no value; the MCF5407 manual then fixes one. Section 4.9.5.1,
# "Cache Filling", folio 4-17: "Note that unlike Version 2 and Version 3 access
# errors, the program counter stored on the exception stack frame points to the
# faulting instruction." So every `framePc` literal below is `execBase`,
# whatever the instruction's length and whatever its store left in `ctx.pc` -
# and a Version 3's would differ per instruction, which is what makes these
# literals one measurement rather than several. The status register has no such
# sentence and is still reported AS THE STORE FOUND IT.
#
# `PEA` IS HERE AND IS NOT A REPAIR. It pushes and then writes nothing, so it
# reached the handler correctly before the deferral and reaches it after. The
# case separates "the fix moved the instructions that clobber control state"
# from "the fix moved every instruction that pushes".
#
# TAKING THE VECTOR AT THE STORE LEAVES EXACTLY SIX RED. Six and not four: the
# three pushes here, the PEA, BLOCK 5's frame and BLOCK 6's status register.
# EVERY FRAME-ASSERTING CASE OF THIS FILE IS AMONG THEM, and folio 4-17 is why
# a mutation that only moves WHEN the vector is taken reaches WHAT the frame
# says. The address of the faulting instruction is not a value the store site
# holds - `ctx.pc` has left it - so a take at the store cannot produce the
# stacked program counter this part requires, whatever else it gets right.
# BLOCK 7's read fault and the trap cases above are what stay green, and they
# are the half that says the mutation reached the write path and no other.
# `tests/t_claims.cmake` registers that mutation as
# `write_fault_deferral_suite_t_bus_fault` and refutes this sentence when the
# count moves.

const
  linkSp = 0x0C04'u32          ## the push lands on `protectedWord`
  opJsrAbsW = 0x4EB8'u16       ## `jsr 0x700`, m68k-elf-as -mcpu=5307
  extJsrTarget = 0x0700'u16
  opBsrW = 0x6100'u16          ## `bsr.w .+0x42`, the same assembler
  extBsrDisp = 0x0040'u16
  opLinkA0 = 0x4E50'u16        ## `link %a0,#-8`, the same assembler
  extLinkDisp = 0xFFF8'u16
  opPeaAbsW = 0x4878'u16       ## `pea 0x700`, the same assembler
  extPeaTarget = 0x0700'u16
  a0Sentinel = 0xA5A5A5A5'u32

type PushOutcome = tuple[pc: uint32, sp: uint32, a0: uint32, halted: bool,
                         fault: bool, frame: uint32, framePc: uint32]

proc runFaultingPush(words: openArray[uint16]; frameAt: uint32): PushOutcome =
  freshBoard()
  offBoardWrites = 0
  for i, w in words:
    boardWrite(board, execBase + uint32(2 * i), 2, uint32(w))
  boardWrite(board, accessHandler, 2, uint32(opRteWord))
  boardWrite(board, 4'u32 * uint32(vecAccess), 4, accessHandler)

  let ctx = mcf5407_create(addr board, protectedRead, protectedWrite, bIack)
  mcf5407_reset(ctx, linkSp, execBase)
  discard mcf5407_set_reg(ctx, 8, a0Sentinel)
  discard mcf5407_exec(ctx, 1'u32)
  result = (pc: mcf5407_get_reg(ctx, 17),
            sp: mcf5407_get_reg(ctx, 15),
            a0: mcf5407_get_reg(ctx, 8),
            halted: ctx.halted,
            fault: ctx.fault,
            frame: boardReadValue(board, frameAt, 4),
            framePc: boardReadValue(board, frameAt + 4'u32, 4))
  mcf5407_destroy(ctx)

# JSR. Table 2-8, "User-Level Instruction Set Summary", folio 2-20, gives it
# "SP - 4 -> SP; next sequential PC -> (SP); <ea> -> PC". A7 goes 0x0C04 to
# 0x0C00, the push is refused, and "<ea> -> PC" is a programming-model update
# that the MCF5307 passage above completes. THE PUSH-BEFORE-TARGET ORDER IS
# THIS PART'S OWN AND NOT THE MCF5307'S: Table 2-22, "Address Error", folio
# 2-34, "If an address error occurs on a JSR instruction, the Version 4
# processor first pushes the return address onto the stack and then calculates
# the target address. On Version 2 and 3 processors, these functions are
# reversed." An absolute target is computed from no register, so this case
# cannot see that order and is not where it is measured; `t_control.nim` drives
# it with an A7-based operand. THEN the exception: Table 2-20, folio 2-33, puts the frame of an
# A7 of 0x0C00 at 0x0BF8 with FORMAT 4, and the handler address replaces the
# JSR target.
# The frame is 0100 | 10 | 00000010 | 01 | 0010011100000000, and the stacked
# program counter is the JSR's own address.
const wantJsr: PushOutcome =
  (pc: accessHandler, sp: 0x0BF8'u32, a0: a0Sentinel, halted: false,
   fault: false, frame: 0x48092700'u32, framePc: execBase)

let faultingJsr = runFaultingPush([opJsrAbsW, extJsrTarget], 0x0BF8'u32)
check(faultingJsr == wantJsr,
      "a JSR whose push faults enters the handler, not its own target",
      $faultingJsr, $wantJsr)

# BSR. Table 2-8, folio 2-20, gives it "SP - 4 -> SP; next sequential PC ->
# (SP); PC + 2 + dn -> PC" - the same shape as JSR and the same two updates, so
# the same outcome.
const wantBsr: PushOutcome =
  (pc: accessHandler, sp: 0x0BF8'u32, a0: a0Sentinel, halted: false,
   fault: false, frame: 0x48092700'u32, framePc: execBase)

let faultingBsr = runFaultingPush([opBsrW, extBsrDisp], 0x0BF8'u32)
check(faultingBsr == wantBsr,
      "a BSR whose push faults enters the handler, not its own target",
      $faultingBsr, $wantBsr)

# LINK. "SP - 4 -> SP; Ax -> (SP); SP -> Ax; SP + d16 -> SP" - Table 2-8, folio
# 2-21. THREE programming-model updates follow the push and the MCF5307
# passage above completes all three: A7 is 0x0C00 when the push is refused, so
# A0 takes 0x0C00 - THE STACK SLOT AND NOT THE FRAME BASE - and A7 then takes
# 0x0C00 - 8, which is 0x0BF8. Table 2-20 puts the frame of that A7 at 0x0BF0.
#
# THE DISPLACEMENT IS FETCHED AFTER THE PUSH, AND THE STACKED PROGRAM COUNTER
# NO LONGER SHOWS IT. `execLink` writes before it calls `fetchExt`, so the store
# found `ctx.pc` one word in: a Version 3 would stack execBase + 2 here while
# stacking execBase + 4 for the JSR above, and folio 4-17 collapses both onto
# the instruction's own address. The fetch itself now reads the instruction
# stream, which is the whole of what 0x0602 was: with the exception taken at the
# store, that fetch read the handler.
#
# -8 AND NOT +4, AND THE REASON IS THE BOARD RATHER THAN THE INSTRUCTION. A
# non-negative displacement leaves A7 at or above 0x0C00, and Table 2-20 then
# puts the frame across `protectedWord` itself - a double fault, which BLOCK 6
# already owns and which would hide this case's subject.
const wantLink: PushOutcome =
  (pc: accessHandler, sp: 0x0BF0'u32, a0: 0x0C00'u32, halted: false,
   fault: false, frame: 0x48092700'u32, framePc: execBase)

let faultingLink = runFaultingPush([opLinkA0, extLinkDisp], 0x0BF0'u32)
check(faultingLink == wantLink,
      "a LINK whose push faults completes An and A7 against the stack slot",
      $faultingLink, $wantLink)

# PEA. "SP - 4 -> SP; Address of <ea> -> (SP)" - Table 2-8, folio 2-21. The push
# is the last thing it does, so there is no update after it to complete and
# nothing for the deferral to move.
const wantPea: PushOutcome =
  (pc: accessHandler, sp: 0x0BF8'u32, a0: a0Sentinel, halted: false,
   fault: false, frame: 0x48092700'u32, framePc: execBase)

let faultingPea = runFaultingPush([opPeaAbsW, extPeaTarget], 0x0BF8'u32)
check(faultingPea == wantPea,
      "a PEA whose push faults was already correct and still is",
      $faultingPea, $wantPea)

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_bus_fault", declaredCaseSites)
echo caseSiteLine("executed", "t_bus_fault", executedSites)
echo caseSiteLine("off-green-path", "t_bus_fault", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_bus_fault: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_bus_fault: ", passCount, " cases passed"
