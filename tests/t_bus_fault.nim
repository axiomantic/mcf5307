## `t_bus_fault` - the bus-fault channel of `mcf5307/bus`. Task CPU-15 owns
## this file. Design sections 5.2.1, 5.6 and 17 row 7.24.
##
## THE DOCUMENTS THIS FILE CITES ARE OUTSIDE THIS REPOSITORY and each is named
## in full, so that a citation can be checked without knowing this project.
##
##   THE MCF5307 USER'S MANUAL: Motorola, "MCF5307 ColdFire Integrated
##   Microprocessor User's Manual", order number MCF5307UM/AD, (c) 1998. Every
##   citation below names its section, table and folio page.
##
##   DESIGN SECTION 5.2.1 is "Bus faults and the error channel" of the NMG2
##   emulator DESIGN DOCUMENT (`2026-08-04-nmg2-emulator-design.md`), and its
##   mapping table is the specification `mcf5307/bus` implements.
##
## EVERY EXPECTED VALUE BELOW IS A HAND-DERIVED LITERAL, written beside the bit
## string or the manual row it came from, and NOT a second call of the
## procedure under test.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The fault
## status encodings are facts about Motorola silicon, from the User's Manual
## named above.

import std/strutils

import mcf5307/bus
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
# User's Manual section 3.4, Table 3-3, "Fault Status Encodings", folio 3-14
# (PDF page 71), read as a page image 2026-08-14, gives the whole defined set
# for this part: `0000` not an access or address error, `0100` error on
# instruction fetch, `1000` error on operand write, `1001` attempted write to
# write-protected space, `1100` error on operand read. Every other value of the
# four bits is Reserved.
#
# DESIGN SECTION 5.2.1's MAPPING TABLE assigns three of those five codes to the
# three non-OK bus statuses, and each expected value below is the code that
# table's own row prints.

checkEq(faultStatusFor(Mcf5307BusStatus.busFault, operandWrite),
        0b1001'u32,
        "mapping: a device fault on a write is 1001")
checkEq(faultStatusFor(Mcf5307BusStatus.busFault, operandRead),
        0b1001'u32,
        "mapping: a device fault on a read is 1001")

checkEq(faultStatusFor(Mcf5307BusStatus.busUnmapped, operandRead),
        0b1100'u32,
        "mapping: unmapped on a read is 1100")
checkEq(faultStatusFor(Mcf5307BusStatus.busUnmapped, operandWrite),
        0b1000'u32,
        "mapping: unmapped on a write is 1000")

checkEq(faultStatusFor(Mcf5307BusStatus.busSizeIllegal, operandRead),
        0b1100'u32,
        "mapping: an illegal width on a read is 1100")
checkEq(faultStatusFor(Mcf5307BusStatus.busSizeIllegal, operandWrite),
        0b1000'u32,
        "mapping: an illegal width on a write is 1000")

# `busOk` IS NOT A ROW OF THE MAPPING TABLE and it is mapped anyway, so that
# the procedure is total over the enumeration. Table 3-3's own `0000` is the
# code for "not an access or address error", which is what a completed access
# is.
checkEq(faultStatusFor(Mcf5307BusStatus.busOk, operandRead),
        0b0000'u32,
        "mapping: a completed read is 0000")
checkEq(faultStatusFor(Mcf5307BusStatus.busOk, operandWrite),
        0b0000'u32,
        "mapping: a completed write is 0000")

# ---------------------------------------------------------------------------
# BLOCK 2. The class column of the same table, asserted rather than described.
#
# Design section 5.2.1 gives each row a class, and only one of the three is
# silicon behaviour. The class is a value this module answers for, so that a
# reader who mistakes an extension for hardware behaviour is contradicted by a
# case rather than by a comment.

check(isEmulatorExtension(Mcf5307BusStatus.busFault) == false,
      "class: a write-protect fault is real MCF5307 behaviour",
      $isEmulatorExtension(Mcf5307BusStatus.busFault), "false")
check(isEmulatorExtension(Mcf5307BusStatus.busUnmapped) == true,
      "class: unmapped is this emulator's own extension",
      $isEmulatorExtension(Mcf5307BusStatus.busUnmapped), "true")
check(isEmulatorExtension(Mcf5307BusStatus.busSizeIllegal) == true,
      "class: an illegal width is this emulator's own extension",
      $isEmulatorExtension(Mcf5307BusStatus.busSizeIllegal), "true")
check(isEmulatorExtension(Mcf5307BusStatus.busOk) == false,
      "class: a completed access is not a fault of any class",
      $isEmulatorExtension(Mcf5307BusStatus.busOk), "false")

# ---------------------------------------------------------------------------
# The two boards. One flat byte array, big-endian, reached through TWO pairs of
# callbacks that differ in exactly one thing: whether they write `*status` at
# all.
#
# NEITHER PAIR EVER REPORTS A NON-OK VALUE, which is what makes both of them
# evidence about the core rather than about a board's decode.
#
# AN ACCESS OUTSIDE THE ARRAY RETURNS ZERO AND REPORTS NOTHING. The silent pair
# has no channel to report one on, and a pair that indexed the array anyway
# would end the process under `--panics:on` - which design section 5.6 and this
# task's own rule forbid, because an abort inside a plugin destroys the host's
# session.

const
  memSize = 0x1000
  execBase = 0x400'u32      ## above the whole 1024-byte vector table
  trapHandler = 0x500'u32
  frameBase = 0x7F8'u32     ## Table 3-2: 0x800 - 8, with FORMAT 4
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
                status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  boardReadValue(b[], address, int(size))

proc silentWrite(user: pointer; address: uint32; size: cint; value: uint32;
                 status: ptr Mcf5307BusStatus) {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  boardWrite(b[], address, int(size), value)

proc explicitRead(user: pointer; address: uint32; size: cint;
                  status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  status[] = Mcf5307BusStatus.busOk
  boardReadValue(b[], address, int(size))

proc explicitWrite(user: pointer; address: uint32; size: cint; value: uint32;
                   status: ptr Mcf5307BusStatus) {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  status[] = Mcf5307BusStatus.busOk
  boardWrite(b[], address, int(size), value)

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

proc freshBoard() =
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8

# ---------------------------------------------------------------------------
# BLOCK 3. Silence means success, through the published entry points.
#
# Design section 5.2.1 rule 1: the core writes `MCF5307_BUS_OK` into `*status`
# before every call, "so a board that never writes it therefore behaves exactly
# as it did before the parameter existed". THE TWO PAIRS OF CALLBACKS DIFFER IN
# NOTHING ELSE, and each run is held against the same hand-stated outcome
# rather than against the other run: two runs compared only with each other
# would agree just as well if the core had stopped executing altogether.
#
# The path is the published one - `mcf5307_create`, `mcf5307_reset`,
# `mcf5307_exec` - and not an internal helper reached around the back. `trap #0`
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

proc runTrap(rd: Mcf5307ReadFn; wr: Mcf5307WriteFn): Outcome =
  freshBoard()
  boardWrite(board, execBase, 2, uint32(opTrap0))
  boardWrite(board, trapHandler, 2, uint32(opRteWord))
  boardWrite(board, 4'u32 * uint32(trapVector), 4, trapHandler)

  let ctx = mcf5307_create(addr board, rd, wr, bIack)
  mcf5307_reset(ctx, 0x800'u32, execBase)
  discard mcf5307_exec(ctx, 1'u32)
  result = (sp: mcf5307_get_reg(ctx, 15),
            pc: mcf5307_get_reg(ctx, 17),
            sr: mcf5307_get_reg(ctx, 16),
            halted: ctx.halted,
            fault: ctx.fault,
            frame: boardReadValue(board, frameBase, 4),
            framePc: boardReadValue(board, frameBase + 4'u32, 4))
  mcf5307_destroy(ctx)

# THE EXPECTED OUTCOME IS HAND-DERIVED. A7 is 0x800 with its low two bits 00,
# so Table 3-2, folio 3-14, gives FORMAT 4 and a frame at 0x800 - 8. `trap #0`
# is one word, and Table 3-1 gives vectors 32 to 47 a stacked program counter
# of "Next", so the stacked value is `execBase + 2`. `FS` is 0000: Table 3-3
# defines the field for access and address errors only.
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
      "an explicit MCF5307_BUS_OK is the same run",
      $explicit, $wantTrap)

# ---------------------------------------------------------------------------
# BLOCK 4. The core originates no bus status of its own.
#
# `MCF5307_BUS_UNMAPPED` and `MCF5307_BUS_SIZE_ILLEGAL` have no producer on
# this part - User's Manual section 3.5.1, folio 3-14, holds that access errors
# are reported only for a store to write-protected space - so the only thing
# that can raise one is a board's own decode.
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
let sweepCtx = mcf5307_create(addr board, silentRead, silentWrite, bIack)
mcf5307_reset(sweepCtx, 0x800'u32, execBase)
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
mcf5307_destroy(sweepCtx)

# ---------------------------------------------------------------------------
# BLOCK 5. A non-OK bus status becomes an access fault, and the frame carries a
# NON-ZERO `FS` through the core.
#
# THIS IS THE FIRST CASE IN THIS REPOSITORY THAT CAN SEPARATE A SPLIT `FS`
# ENCODER FROM A CONTIGUOUS ONE. User's Manual Table 3-3, folio 3-14, defines
# five codes - `0000`, `0100`, `1000`, `1001`, `1100` - and `1001` is the only
# one whose low half is not zero, so it is the only value that lands in BOTH
# halves of the split field. Every other core-path frame this tree stacks
# carries `FS` `0000`, where "encodes the field as zero" and "has no field"
# produce the same longword.
#
# THE ROW IS THE ONE THAT IS REAL SILICON. User's Manual section 3.5.1, folio
# 3-14, verbatim: access errors are "only reported in conjunction with an
# attempted store to a write-protected memory space". The board below refuses
# exactly one longword and reports `MCF5307_BUS_FAULT` for it.
#
# THE THIRD BOARD REPORTS A NON-OK STATUS, which is what separates it from the
# two above: those two exist to show that silence is success, and this one
# exists to show what a report does.

const
  protectedWord = 0x0C00'u32  ## the one longword this board refuses to store
  accessHandler = 0x600'u32
  vecAccess = 2'u8            ## Table 3-1, folio 3-13: access error, at $008
  opMoveProtected = 0x21C0'u16  ## `move.l %d0,0xC00`, m68k-elf-as -mcpu=5307
  extProtected = 0x0C00'u16     ## its `(xxx).W` extension word
  doubleSp = 0x1008'u32       ## Table 3-2: a frame base of 0x1000, off the board
  doubleFrameBase = 0x1000'u32

# AN ACCESS PAST THE ARRAY IS COUNTED AND NOT ONLY REFUSED. The count is what
# separates a core that halted on a fault during stacking from one that
# re-entered the stacking and tried again; both leave the same flags.
var offBoardWrites = 0

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

  let ctx = mcf5307_create(addr board, protectedRead, protectedWrite, bIack)
  mcf5307_reset(ctx, startSp, execBase)
  discard mcf5307_exec(ctx, 1'u32)
  result = (sp: mcf5307_get_reg(ctx, 15),
            pc: mcf5307_get_reg(ctx, 17),
            sr: mcf5307_get_reg(ctx, 16),
            halted: ctx.halted,
            fault: ctx.fault,
            frame: boardReadValue(board, readFrameAt, 4),
            framePc: boardReadValue(board, readFrameAt + 4'u32, 4),
            offBoard: offBoardWrites)
  mcf5307_destroy(ctx)

# THE EXPECTED FRAME IS HAND-DERIVED FROM THE BIT POSITIONS AND NOT FROM A
# SECOND CALL OF THE ENCODER. A7 is 0x800 with its low two bits 00, so Table
# 3-2, folio 3-14, gives FORMAT 4 and a frame at 0x800 - 8. The vector is 2.
# `FS` is `1001`, design section 5.2.1's row for a write to write-protected
# space, and its two halves land in two non-adjacent fields:
#   0100 | 10 | 00000010 | 01 | 0010011100000000 -> 0x48092700
# The stacked program counter is `ctx.pc`, which the opcode word and the one
# `(xxx).W` extension word have advanced to execBase + 4.
#
# THE LIVE STATUS REGISTER IS 0x2704 AND THE FRAME'S COPY IS 0x2700, AND THE
# DIFFERENCE IS REQUIRED RATHER THAN TOLERATED. User's Manual section 3.5.1,
# folio 3-14, verbatim, of an access error on an operand write: "All programming
# model updates associated with the write instruction are completed." `MOVE`
# sets Z from its source AFTER the store, and the source here is zero, so Z is
# set once the faulting instruction finishes. The frame carries the copy
# `takeException` took BEFORE that, which is why the two differ by exactly Z.
const wantProtected: FaultOutcome =
  (sp: frameBase, pc: accessHandler, sr: 0x2704'u32, halted: false,
   fault: false, frame: 0x48092700'u32, framePc: execBase + 4'u32,
   offBoard: 0)

let protectedStore = runProtectedStore(0x800'u32, frameBase)
check(protectedStore == wantProtected,
      "a write-protected store takes an access fault carrying FS 1001",
      $protectedStore, $wantProtected)

# ---------------------------------------------------------------------------
# BLOCK 6. A fault DURING the stacking is a double fault: the core halts and
# does not recurse.
#
# Design section 5.2.1 rule 5: "A fault inside the exception-entry stacking
# itself is a double fault. The core halts, sets its own fault field, and
# returns from `mcf5307_exec` with the cycles it spent. It does not recurse."
#
# A7 IS 0x1008, SO THE FRAME BASE IS 0x1000 AND IS OFF THE BOARD. The same
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

const wantDoubleFault: FaultOutcome =
  (sp: doubleSp, pc: execBase + 4'u32, sr: srReset, halted: true, fault: true,
   frame: 0'u32, framePc: 0'u32, offBoard: 1)

let doubleFault = runProtectedStore(doubleSp, doubleFrameBase)
check(doubleFault == wantDoubleFault,
      "a fault while stacking halts the core and does not recurse",
      $doubleFault, $wantDoubleFault)

# ---------------------------------------------------------------------------
# BLOCK 7. AN OPERAND READ FAULT STILL HALTS AND TAKES NO VECTOR. THIS CASE
# PINS A BOUNDARY AND DOES NOT ENDORSE IT.
#
# Design section 5.2.1 and this task's own `Check:` line both ask that a read of
# unmapped space TAKE AN ACCESS FAULT, and this core does not do that yet. The
# blocker is design section 5.2.1 rule 4 - a fault is taken "before it commits
# any register or memory side effect of the faulting instruction" - together
# with the fact that `ctx.halted` is the only signal that unwinds a
# part-completed instruction. An access fault must not halt, so a read that took
# a vector would return into an executor that finished the instruction with a
# zero operand. MEASURED, with the vector taken: `d1` came back 0 over its
# sentinel, and the frame itself was correct - `0x4C082700`, `FS` `1100`.
#
# THE FIX IS NOT WRITABLE FROM THE FILES THIS TASK DECLARES. It needs a
# pending-fault field on `MCF5307Ctx` in `src/mcf5307/decode_types.nim`, or a
# check after the executor returns in `src/mcf5307/cpu.nim`'s `step`.
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

  let ctx = mcf5307_create(addr board, protectedRead, protectedWrite, bIack)
  mcf5307_reset(ctx, 0x800'u32, execBase)
  discard mcf5307_set_reg(ctx, 1, sentinelD1)
  discard mcf5307_exec(ctx, 1'u32)
  result = (d1: mcf5307_get_reg(ctx, 1),
            pc: mcf5307_get_reg(ctx, 17),
            halted: ctx.halted,
            fault: ctx.fault,
            frame: boardReadValue(board, frameBase, 4),
            framePc: boardReadValue(board, frameBase + 4'u32, 4))
  mcf5307_destroy(ctx)

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
