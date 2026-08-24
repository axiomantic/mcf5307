## `t_exception` - the exception model of `mcf5307/exception`, and the frame
## the shipped core actually writes.
##
## EVERY EXPECTED VALUE IN BLOCK 1 IS A HAND-DERIVED LITERAL, written beside
## the bit string it came from, and NOT a second call of the procedure under
## test.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The frame
## layout, the vector assignments and the format encoding are facts about
## Motorola silicon, taken from the MCF5307 User's Manual and the ColdFire
## Family Programmer's Reference Manual.

import std/strutils

import mcf5307/cpu
import mcf5307/decode_types
import mcf5307/exception
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
  ## THE CALL SITE IS RECORDED TWICE - once at COMPILE TIME into
  ## `declaredSites` by the `static` below, and once at RUN TIME into
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkEqImpl(site, got, want, label)
# ---------------------------------------------------------------------------
# BLOCK 1. The first longword of the frame, as a number.
#
# The fields are `FORMAT | FS[3-2] | VEC | FS[1-0] | Status Register`, and both
# manuals print the same figure. Each expected value below is the bit string
# that figure defines, written out and converted by hand.

checkEq(frameFirstLongword(4'u32, fsWriteProtected, 2'u8, 0x2700'u32),
        0x48092700'u32,
        "frame: format 4, FS 1001, vector 2, SR 0x2700")
#   0100 | 10 | 00000010 | 01 | 0010011100000000
#   -> 0100 1000 0000 1001 0010 0111 0000 0000 = 0x48092700

checkEq(frameFirstLongword(7'u32, fsOperandRead, 3'u8, 0x2000'u32),
        0x7C0C2000'u32,
        "frame: format 7, FS 1100, vector 3, SR 0x2000")
#   0111 | 11 | 00000011 | 00 | 0010000000000000
#   -> 0111 1100 0000 1100 0010 0000 0000 0000 = 0x7C0C2000

checkEq(frameFirstLongword(5'u32, fsNotAnAccessError, 32'u8, 0x2700'u32),
        0x50802700'u32,
        "frame: format 5, FS 0000, vector 32, SR 0x2700")
#   0101 | 00 | 00100000 | 00 | 0010011100000000
#   -> 0101 0000 1000 0000 0010 0111 0000 0000 = 0x50802700

checkEq(frameFirstLongword(6'u32, fsOperandWrite, 66'u8, 0x2700'u32),
        0x69082700'u32,
        "frame: format 6, FS 1000, vector 66, SR 0x2700")
#   0110 | 10 | 01000010 | 00 | 0010011100000000
#   -> 0110 1001 0000 1000 0010 0111 0000 0000 = 0x69082700

checkEq(frameFirstLongword(4'u32, fsInstructionFetch, 25'u8, 0x2700'u32),
        0x44642700'u32,
        "frame: format 4, FS 0100, vector 25, SR 0x2700")
#   0100 | 01 | 00011001 | 00 | 0010011100000000
#   -> 0100 0100 0110 0100 0010 0111 0000 0000 = 0x44642700

# ---------------------------------------------------------------------------
# BLOCK 2. Reading the fields back out of a longword written by hand.
#
# The literal is block 1's first case and it is READ HERE rather than produced:
# the decoders are held against the same bit string from the other side.
#
# `frameFaultStatus` REJOINS TWO HALVES THAT ARE NOT ADJACENT. `1001` is the
# encoding whose halves differ.

const handWritten = 0x48092700'u32

checkEq(frameFormat(handWritten), 4'u32, "decode: FORMAT of 0x48092700")
checkEq(frameFaultStatus(handWritten), 0b1001'u32,
        "decode: FS of 0x48092700, both halves")
checkEq(uint32(frameVector(handWritten)), 2'u32,
        "decode: VEC of 0x48092700")
checkEq(frameStatusRegister(handWritten), 0x2700'u32,
        "decode: SR of 0x48092700")
checkEq(frameFaultStatus(0x7C0C2000'u32), 0b1100'u32,
        "decode: FS of 0x7C0C2000")
checkEq(uint32(frameVector(0x7C0C2000'u32)), 3'u32,
        "decode: VEC of 0x7C0C2000")

# ---------------------------------------------------------------------------
# BLOCK 3. The vector numbers, and the offsets the manuals print beside them.
#
# THE TWO MANUALS' TABLES ARE NOT IDENTICAL and this file takes only rows where
# they agree. Their disagreement is recorded in `src/mcf5307/exception.nim`.

checkEq(uint32(vecAccessError), 2'u32, "vector number: access error is 2")
checkEq(uint32(vecAddressError), 3'u32, "vector number: address error is 3")
check(@[autovectorFor(1), autovectorFor(2), autovectorFor(3), autovectorFor(4),
        autovectorFor(5), autovectorFor(6), autovectorFor(7)] ==
      @[25'u8, 26'u8, 27'u8, 28'u8, 29'u8, 30'u8, 31'u8],
      "vector numbers: levels 1 to 7 autovector to 25 to 31",
      $(@[autovectorFor(1), autovectorFor(7)]), "@[25, 31] at the ends")
checkEq(uint32(vecUserFirst), 64'u32, "vector number: user-defined start 64")
checkEq(uint32(vecUserLast), 255'u32, "vector number: user-defined end 255")

checkEq(vectorAddress(0'u32, vecAccessError), 0x008'u32,
        "vector offset: access error at $008")
checkEq(vectorAddress(0'u32, vecAddressError), 0x00C'u32,
        "vector offset: address error at $00C")
checkEq(vectorAddress(0'u32, autovectorFor(1)), 0x064'u32,
        "vector offset: level 1 autovector at $064")
checkEq(vectorAddress(0'u32, autovectorFor(7)), 0x07C'u32,
        "vector offset: level 7 autovector at $07C")
checkEq(vectorAddress(0'u32, vecUserFirst), 0x100'u32,
        "vector offset: first user-defined vector at $100")
checkEq(vectorAddress(0'u32, vecUserLast), 0x3FC'u32,
        "vector offset: last user-defined vector at $3FC")

# The table is 1024 bytes and its last longword is the one at $3FC.
checkEq(vectorTableBytes, 1024'u32, "vector table: 1024 bytes")
checkEq(vectorAddress(0'u32, vecUserLast) + 4'u32, vectorTableBytes,
        "vector table: the $3FC longword is its last")

# ---------------------------------------------------------------------------
# BLOCK 4. The 1 MByte alignment, and where it comes from.
#
# VBR[19-0] are not implemented and are assumed to be zero, which is what
# forces the vector table onto a 1 MByte boundary. Only one of the two manuals
# gives that mechanism, so the low bits of VBR are pinned from it alone.

checkEq(vectorAddress(0x0010_0000'u32, vecAccessError), 0x0010_0008'u32,
        "VBR 0x00100000: access error at 0x00100008")
checkEq(vectorAddress(0x0010_0004'u32, vecAccessError), 0x0010_0008'u32,
        "VBR 0x00100004: VBR[19-0] are not implemented")
checkEq(vectorAddress(0x000F_FFFF'u32, vecAccessError), 0x008'u32,
        "VBR 0x000FFFFF: every implemented bit is zero")

# ---------------------------------------------------------------------------
# The board. One flat byte array, big-endian, as `t_control`'s and the
# conformance runner's. A read outside it reports `busUnmapped`.
#
# IT RECORDS EVERY READ INSIDE A VECTOR TABLE AND NOTHING ELSE: the code sits
# at `execBase`, above the whole 1024-byte zero-based table, and the stack is
# higher still. TWO TABLES CAN BE IN PLAY - the zero-based one and the one
# `vbrTableBase` names - and a read of EITHER is recorded, so a core that read
# the wrong table reports WHICH address it read rather than an empty list.
#
# THE MEMORY REACHES THE `VBR`-BASED TABLE AND STOPS THERE. `memSize` is
# COMPOSED from `vbrTableBase` and `vectorTableBytes` rather than written as a
# literal, so moving the base cannot leave the array one table short.

const
  vbrTableBase = 0x0010_0000'u32
    ## 1 MByte, THE SMALLEST NON-ZERO BASE THIS PART CAN HOLD: VBR[19-0] are
    ## not implemented, which block 4 above asserts value by value.
  memSize = int(vbrTableBase) + int(vectorTableBytes)
  execBase = 0x400'u32      ## above the whole 1024-byte zero-based table
  trapHandler = 0x500'u32
  accessHandler = 0x600'u32
  addressHandler = 0x700'u32
  frameBase = 0x7F8'u32     ## 0x800-8, 0x801-9, 0x802-10, 0x803-11
  srReset = 0x2700'u32
  opTrap0 = 0x4E40'u16      ## `trap #0`, m68k-elf-as -mcpu=5307
  opRteWord = 0x4E73'u16    ## `rte`, the same assembler

type TestBoard = object
  bytes: array[memSize, uint8]

var board: TestBoard
var vectorReads: seq[uint32]

var tableBase: uint32 = 0'u32
  ## The base the case under way put its OWN vector table at. It is the second
  ## table the read log recognizes; the zero-based one is always recognized.

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
  if address < vectorTableBytes or
     (address >= tableBase and address - tableBase < vectorTableBytes):
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

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

proc freshBoard(base: uint32 = 0'u32) =
  tableBase = base
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  vectorReads = @[]
  # The handler addresses are DIFFERENT.
  boardWrite(board, vectorAddress(0'u32, 32'u8), 4, trapHandler)
  boardWrite(board, vectorAddress(0'u32, vecAccessError), 4, accessHandler)
  boardWrite(board, vectorAddress(0'u32, vecAddressError), 4, addressHandler)

proc mem32(address: uint32): uint32 =
  boardReadValue(board, address, 4)

# ---------------------------------------------------------------------------
# BLOCK 5. The frame the shipped core writes, and the A7 `RTE` restores.
#
# The path is the published one - `mcf5307_create`, `mcf5307_reset`,
# `mcf5307_exec` - and not an internal helper reached around the back.
#
# The format field encoding is what makes an A7 whose low two bits are 00, 01,
# 10 or 11 leave the handler with A7-8, A7-9, A7-10 or A7-11 and a FORMAT of 4,
# 5, 6 or 7. All of the A7 values below produce the same frame base, 0x7F8, and
# each subtraction is written out above `frameBase`.
#
# THE STACKED PROGRAM COUNTER IS `execBase + 2`. A trap stacks the instruction
# after the one that caused the fault, and `trap #0` is one word.

proc runTrapAndRte(startSp: uint32; startSr: uint32;
                   expectFrame: uint32; label: string) =
  freshBoard()
  boardWrite(board, execBase, 2, uint32(opTrap0))
  boardWrite(board, trapHandler, 2, uint32(opRteWord))

  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, startSp, execBase)
  discard mcf5307_set_reg(ctx, 16, startSr)

  discard mcf5307_exec(ctx, 1'u32)
  let taken = (sp: mcf5307_get_reg(ctx, 15),
               pc: mcf5307_get_reg(ctx, 17),
               sr: mcf5307_get_reg(ctx, 16),
               frame: mem32(frameBase),
               framePc: mem32(frameBase + 4'u32),
               reads: vectorReads)
  let wantTaken = (sp: frameBase,
                   pc: trapHandler,
                   sr: srReset,
                   frame: expectFrame,
                   framePc: execBase + 2'u32,
                   reads: @[0x080'u32])
  check(taken == wantTaken, label & ": the frame", $taken, $wantTaken)

  discard mcf5307_exec(ctx, 1'u32)
  let returned = (sp: mcf5307_get_reg(ctx, 15),
                  pc: mcf5307_get_reg(ctx, 17),
                  sr: mcf5307_get_reg(ctx, 16))
  let wantReturned = (sp: startSp, pc: execBase + 2'u32, sr: startSr)
  check(returned == wantReturned, label & ": RTE restores A7",
        $returned, $wantReturned)
  mcf5307_destroy(ctx)

# The expected frames are hand-derived exactly as block 1's are. `FS` is 0000
# for a TRAP - the field is defined for access and address errors only and
# zeros for every other exception - and the vector is 32, which is `trap #0`.
#   0100 | 00 | 00100000 | 00 | 0010011100000000 -> 0x40802700
runTrapAndRte(0x800'u32, srReset, 0x40802700'u32, "A7 0x800, FORMAT 4")
runTrapAndRte(0x801'u32, srReset, 0x50802700'u32, "A7 0x801, FORMAT 5")
runTrapAndRte(0x802'u32, srReset, 0x60802700'u32, "A7 0x802, FORMAT 6")
runTrapAndRte(0x803'u32, srReset, 0x70802700'u32, "A7 0x803, FORMAT 7")

# THE STACKED STATUS REGISTER IS THE COPY TAKEN BEFORE THE EXCEPTION CHANGED
# IT. The processor copies the SR, then enters supervisor mode by setting the
# S-bit and disables trace mode by clearing the T-bit. Entered with T set, the
# FRAME must carry T and the HANDLER must not.
#   0100 | 00 | 00100000 | 00 | 1010011100000000 -> 0x4080A700
runTrapAndRte(0x800'u32, 0xA700'u32, 0x4080A700'u32, "A7 0x800, T set")

# ---------------------------------------------------------------------------
# BLOCK 6. The access error and the address error are NOT the same exception.
#
# Vector 2 at $008 is the access error and vector 3 at $00C is the address
# error, and the core must not conflate them. Neither has a producer in the
# core yet, so both are raised through `takeException`, which is the procedure
# every producer will call.
#
# THE TWO SLOTS HOLD DIFFERENT HANDLER ADDRESSES AND THE READ LIST IS ASSERTED
# EXACTLY.

type Taken = tuple[sp: uint32, pc: uint32, halted: bool, vec: uint8,
                   frame: uint32, framePc: uint32, reads: seq[uint32]]

proc runTakeException(vector: uint8; stackedPc: uint32): Taken =
  freshBoard()
  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, 0x800'u32, execBase)
  takeException(ctx, vector, stackedPc)
  result = (sp: ctx.sp,
            pc: ctx.pc,
            halted: ctx.halted,
            vec: frameVector(mem32(frameBase)),
            frame: mem32(frameBase),
            framePc: mem32(frameBase + 4'u32),
            reads: vectorReads)
  mcf5307_destroy(ctx)

let access = runTakeException(vecAccessError, 0x444'u32)
check(access == (sp: frameBase, pc: accessHandler, halted: false,
                 vec: 2'u8, frame: 0x40082700'u32, framePc: 0x444'u32,
                 reads: @[0x008'u32]),
      "access error: vector 2, handler from $008", $access,
      "the $008 handler, VEC 2, one read of $008")
#   0100 | 00 | 00000010 | 00 | 0010011100000000 -> 0x40082700

let addressErr = runTakeException(vecAddressError, 0x444'u32)
check(addressErr == (sp: frameBase, pc: addressHandler, halted: false,
                     vec: 3'u8, frame: 0x400C2700'u32, framePc: 0x444'u32,
                     reads: @[0x00C'u32]),
      "address error: vector 3, handler from $00C", $addressErr,
      "the $00C handler, VEC 3, one read of $00C")
#   0100 | 00 | 00000011 | 00 | 0010011100000000 -> 0x400C2700

# ---------------------------------------------------------------------------
# BLOCK 7. THE DISPATCH READS `VBR`, AND NO READ-BACK CAN SHOW THAT.
#
# A core that STORES the value in a context field no dispatch consults fails
# IDENTICALLY to one that discards it, and passes every read-back assertion.
# So the read-back below is carried in the tuple as DESCRIPTION and the
# handler address is what adjudicates: the ZERO-BASED slot for this vector
# holds `accessHandler` and the `VBR`-BASED slot holds `vbrHandler`, and the
# two are different addresses. A core basing the table at zero lands on
# `accessHandler` and says so; the read log names the address it fetched from.
#
# THE VECTOR IS THE ACCESS ERROR BECAUSE `freshBoard` ALREADY WRITES ITS
# ZERO-BASED SLOT. The decoy is therefore the same value block 6 asserts
# against, and not a second constant that could drift away from it.

const vbrHandler = 0x0010_0800'u32

type TakenVbr = tuple[setOk: bool, readBack: uint32, sp: uint32, pc: uint32,
                      halted: bool, framePc: uint32, reads: seq[uint32]]

proc runTakeExceptionWithVbr(vbr: uint32; vector: uint8;
                             stackedPc: uint32): TakenVbr =
  freshBoard(vbrTableBase)
  boardWrite(board, vectorAddress(vbrTableBase, vector), 4, vbrHandler)
  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, 0x800'u32, execBase)
  let setOk = mcf5307_set_reg(ctx, 18, vbr) != 0
  takeException(ctx, vector, stackedPc)
  result = (setOk: setOk,
            readBack: mcf5307_get_reg(ctx, 18),
            sp: ctx.sp,
            pc: ctx.pc,
            halted: ctx.halted,
            framePc: mem32(frameBase + 4'u32),
            reads: vectorReads)
  mcf5307_destroy(ctx)

let vbrBased = runTakeExceptionWithVbr(vbrTableBase, vecAccessError, 0x444'u32)
check(vbrBased == (setOk: true, readBack: vbrTableBase, sp: frameBase,
                   pc: vbrHandler, halted: false, framePc: 0x444'u32,
                   reads: @[vbrTableBase + 0x008'u32]),
      "VBR 0x00100000: the handler comes from 0x00100008 and not from $008",
      $vbrBased,
      "the 0x00100008 handler, one read of 0x00100008, the frame unchanged")

# THE UNIMPLEMENTED LOW BITS ARE MASKED BY THE DISPATCH AND NOT ONLY BY
# `vectorAddress`. Block 4 asserts the mask on the pure function; this asserts
# that the procedure which takes the exception is the one applying it.
let vbrMisaligned =
  runTakeExceptionWithVbr(vbrTableBase or 0x4'u32, vecAccessError, 0x444'u32)
check(vbrMisaligned == (setOk: true, readBack: vbrTableBase or 0x4'u32,
                        sp: frameBase, pc: vbrHandler, halted: false,
                        framePc: 0x444'u32,
                        reads: @[vbrTableBase + 0x008'u32]),
      "VBR 0x00100004: VBR[19-0] are not implemented at the dispatch",
      $vbrMisaligned,
      "the 0x00100008 handler, one read of 0x00100008")

# A ZERO `VBR` STILL READS THE ZERO-BASED TABLE. Without this case a core that
# hardcoded the dispatch at `vbrTableBase` instead of at zero would satisfy
# both cases above, and block 6's cases run on a board whose second table does
# not exist.
let vbrZero = runTakeExceptionWithVbr(0'u32, vecAccessError, 0x444'u32)
check(vbrZero == (setOk: true, readBack: 0'u32, sp: frameBase,
                  pc: accessHandler, halted: false, framePc: 0x444'u32,
                  reads: @[0x008'u32]),
      "VBR 0x00000000: the handler comes from $008",
      $vbrZero, "the $008 handler, one read of $008")

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_exception", declaredCaseSites)
echo caseSiteLine("executed", "t_exception", executedSites)
echo caseSiteLine("off-green-path", "t_exception", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_exception: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_exception: ", passCount, " cases passed"
