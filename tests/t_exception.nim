## `t_exception` - the exception model of `mcf5307/exception`, and the frame
## the shipped core actually writes. Task CPU-14 owns this file. Design
## sections 6.1 and 5.2.1.
##
## THE DOCUMENTS THIS FILE CITES ARE OUTSIDE THIS REPOSITORY and each is named
## in full, as `tests/t_control.nim` and `tests/t_logic.nim` name theirs.
##
##   THE MCF5307 USER'S MANUAL: Motorola, "MCF5307 ColdFire Integrated
##   Microprocessor User's Manual", order number MCF5307UM/AD, (c) 1998. Every
##   citation below names its section, table and folio page.
##
##   THE COLDFIRE FAMILY PROGRAMMER'S REFERENCE MANUAL, Rev. 3 (Freescale).
##   It is a SECOND oracle for the frame layout and it is the only one of the
##   two that states why the vector table is 1 MByte aligned.
##
##   DESIGN SECTIONS 6.1 AND 5.2.1 are "The core" and "Bus faults and the
##   error channel" of the NMG2 emulator DESIGN DOCUMENT
##   (`2026-08-04-nmg2-emulator-design.md`).
##
## WHAT THIS FILE PINS, AND WHAT ITS SILENCE WOULD MEAN.
##
##   1. THE FIRST LONGWORD OF THE FRAME, AS A NUMBER. `FS` is SPLIT across two
##      non-adjacent fields - bits 27-26 carry `FS[3:2]` and bits 17-16 carry
##      `FS[1:0]` - and an implementation that laid the four bits out
##      contiguously produces a different number for the same fault. EVERY
##      EXPECTED VALUE IN BLOCK 1 IS A HAND-DERIVED LITERAL, written beside the
##      bit string it came from, and NOT a second call of the procedure under
##      test. A test that built the frame with the encoder's own expression
##      would agree with a wrong encoder.
##
##      `FS` = `1001`, an attempted write to write-protected space, is the ONE
##      encoding the MCF5307 actually generates (User's Manual section 3.5.1,
##      folio 3-14) and the ONLY defined encoding whose two halves DIFFER. It
##      is therefore the case that separates a split layout from a contiguous
##      one, and block 1 carries it.
##
##   2. THE VECTOR TABLE. Vector 2 at `$008` is the ACCESS error and vector 3
##      at `$00C` is the ADDRESS error. They are different exceptions and the
##      core must not conflate them; a test that asserted vector 2 alone could
##      not see a core that took vector 2 for both. Block 6 raises BOTH through
##      `takeException` - neither has a producer the C ABI can reach yet - with
##      a DIFFERENT handler address in each slot, and asserts the handler each
##      one reached AND the vector-table address each one read. Block 5 is the
##      one that goes through the published entry points.
##
##   3. THE `FORMAT` FIELD AND THE `RTE` RESTORE, THROUGH THE CORE. Block 5
##      runs `trap #0` from all four A7 alignments and then executes the `RTE`,
##      and asserts that A7 comes back to the value it started from - 0x800,
##      0x801, 0x802 and 0x803, not a longword-aligned approximation of it. A
##      core that added a fixed 8 restores three of the four wrongly.
##
## THE MODEL AND THE CORE ARE ASSERTED AGAINST THE SAME LITERALS, ON PURPOSE.
## `mcf5307/exception` owns the frame layout, and `machine.nim`'s
## `takeException` - which CPU-10 wrote, one layer BELOW this module, where it
## cannot import it - builds the same longword from its own expression. The two
## expressions are held against the same hand-derived numbers here, so that a
## drift between them is a failing case rather than a silent disagreement.
##
## THE CORE-BINDING BLOCKS ARE CHARACTERISATION AND THEY WERE PROVED
## FALSIFIABLE BY MUTATION. Blocks 5 and 6 assert behaviour CPU-10 already
## shipped, so they could not be red before the code existed. Five mutations,
## measured 2026-08-12 against this tree, each applied alone and reverted, out
## of 39 cases:
##
##   `takeException`'s `format shl 28` at 24            12 red
##   `takeException`'s `uint32(vector) shl 18` at 16     7 red
##   `exceptionFormat`'s `4'u32 +` at `5'u32 +`         12 red
##   `execRte`'s `4'u32 + format` at `8'u32`             3 red
##   `takeException`'s vector fetch pinned to vector 2  11 red
##
## THE LAST TWO ROWS ARE THE POINTED ONES. The fixed-8 `RTE` reds the 0x801,
## 0x802 and 0x803 cases and LEAVES 0x800 GREEN, which is why one alignment
## would not have been a test. The pinned vector fetch reds the ADDRESS-error
## case and leaves the access-error case green, which is what conflating the
## two looks like from outside.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The frame
## layout, the vector assignments and the format encoding are facts about
## Motorola silicon, taken from the two manuals named above.

import std/strutils

import mcf5307/cpu
import mcf5307/decode_types
import mcf5307/exception
import mcf5307/machine

var failures: seq[string]
var passCount = 0

proc check(ok: bool; label: string; got: string; want: string) =
  if ok:
    echo "PASSED  ", label
    inc passCount
  else:
    echo "FAILED  ", label
    echo "          got  ", got
    echo "          want ", want
    failures.add(label)

proc checkEq(got: uint32; want: uint32; label: string) =
  check(got == want, label, "0x" & toHex(got), "0x" & toHex(want))

# ---------------------------------------------------------------------------
# BLOCK 1. The first longword of the frame, as a number.
#
# CFPRM Rev. 3 section 11.1.2, Figure 11-1, folio 11-4, prints the bit numbers
# 31, 28, 27, 26, 25, 18, 17, 16, 15 and 0 over the fields
# `FORMAT | FS[3-2] | VEC | FS[1-0] | Status Register`. MCF5307 User's Manual
# section 3.4, Figure 3-7, folio 3-13, prints the same figure with the same
# numbers. The two agree, and each expected value below is the bit string those
# two figures define, written out and converted by hand.

checkEq(frameFirstLongword(4'u32, fsWriteProtected, 2'u8, 0x2700'u32),
        0x48092700'u32,
        "frame: format 4, FS 1001, vector 2, SR 0x2700")
#   0100 | 10 | 00000010 | 01 | 0010011100000000
#   -> 0100 1000 0000 1001 0010 0111 0000 0000 = 0x48092700
#   THE SPLIT IS WHAT THIS CASE HOLDS. An encoder that wrote `FS[3:2]` and
#   dropped the other half gives 0x48082700; one that packed all four bits at
#   27-24 and left VEC where it is gives 0x49082700. Both differ from the
#   number above, and no other defined `FS` code would separate them.

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
# the decoders are held against the same bit string from the other side, so a
# decoder that agreed with a wrong encoder still fails.
#
# `frameFaultStatus` REJOINS TWO HALVES THAT ARE NOT ADJACENT. `1001` is the
# encoding whose halves differ, so a decoder that dropped bits 17-16 answers
# `1000` here.

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
# BLOCK 3. The vector numbers, and the offsets the manual prints beside them.
#
# MCF5307 User's Manual section 3.4, Table 3-1, "Exception Vector Assignments",
# folios 3-12 and 3-13; CFPRM Rev. 3 section 11.1, Table 11-1, folios 11-2 and
# 11-3. Both tables carry a VECTOR NUMBER column and a VECTOR OFFSET column,
# and the two blocks below hold the two columns SEPARATELY: the constants
# against the numbers, and `vectorAddress` against the offsets the table
# PRINTS. A `vectorAddress` that scaled by anything but four passes the first
# and fails the second.
#
# THE TWO TABLES ARE NOT IDENTICAL and this file cites only rows where they
# agree. Their disagreement is recorded in `src/mcf5307/exception.nim`.

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

# The table is 1024 bytes (User's Manual section 3.3, folio 3-12; CFPRM section
# 11.1, folio 11-2) and its last longword is the one at $3FC. Those are two
# facts printed in two different places and this case holds them against each
# other.
checkEq(vectorTableBytes, 1024'u32, "vector table: 1024 bytes")
checkEq(vectorAddress(0'u32, vecUserLast) + 4'u32, vectorTableBytes,
        "vector table: the $3FC longword is its last")

# ---------------------------------------------------------------------------
# BLOCK 4. The 1 MByte alignment, and where it comes from.
#
# CFPRM Rev. 3 section 11.1, folio 11-2, verbatim: "VBR[19-0] are not
# implemented and are assumed to be zero, forcing the vector table to be
# aligned on a 0-modulo-1-Mbyte boundary." The User's Manual states the
# CONSEQUENCE - section 3.3, folio 3-12, "aligned on any 1 MByte address
# boundary" - and not the mechanism, so the low bits of VBR are pinned from the
# CFPRM alone.
#
# THE MIDDLE CASE IS THE ONE THAT BITES. A model that added VBR whole agrees
# with the other two and answers 0x0010000C for a VBR of 0x00100004.

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
# IT RECORDS EVERY READ BELOW `vectorTableBytes`, which is the vector table and
# nothing else: the code sits at `execBase`, above the whole 1024-byte table,
# and the stack is higher still. Block 6 asserts the recorded list exactly, so
# a core that read the wrong slot, or read both, fails on the list even when it
# happens to land on the right handler.

const
  memSize = 0x1000
  execBase = 0x400'u32      ## above the whole 1024-byte vector table
  trapHandler = 0x500'u32
  accessHandler = 0x600'u32
  addressHandler = 0x700'u32
  frameBase = 0x7F8'u32     ## Table 3-2: 0x800-8, 0x801-9, 0x802-10, 0x803-11
  srReset = 0x2700'u32
  opTrap0 = 0x4E40'u16      ## `trap #0`, m68k-elf-as -mcpu=5307
  opRteWord = 0x4E73'u16    ## `rte`, the same assembler

type TestBoard = object
  bytes: array[memSize, uint8]

var board: TestBoard
var vectorReads: seq[uint32]

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

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

proc freshBoard() =
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  vectorReads = @[]
  # The three handler addresses are DIFFERENT so that a core which fetched the
  # wrong vector lands somewhere the assertions can see.
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
# MCF5307 User's Manual section 3.4, Table 3-2, "Format Field Encoding", folio
# 3-14, gives the four rows: an A7 whose low two bits are 00, 01, 10 or 11
# leaves the handler with A7-8, A7-9, A7-10 or A7-11 and a FORMAT of 4, 5, 6 or
# 7. All four of the A7 values below produce the same frame base, 0x7F8, and
# each of the four subtractions is written out above `frameBase`.
#
# THE STACKED PROGRAM COUNTER IS `execBase + 2`. Table 3-1 gives vectors 32 to
# 47 a STACKED PROGRAM COUNTER of "Next", and its footnote defines Next as the
# instruction after the one that caused the fault; `trap #0` is one word.

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

# The four expected frames are hand-derived exactly as block 1's are. `FS` is
# 0000 for a TRAP - Table 3-3, folio 3-14, defines the field for access and
# address errors only and writes zeros for every other exception - and the
# vector is 32, which Table 3-1 gives to `trap #0`.
#   0100 | 00 | 00100000 | 00 | 0010011100000000 -> 0x40802700
runTrapAndRte(0x800'u32, srReset, 0x40802700'u32, "A7 0x800, FORMAT 4")
runTrapAndRte(0x801'u32, srReset, 0x50802700'u32, "A7 0x801, FORMAT 5")
runTrapAndRte(0x802'u32, srReset, 0x60802700'u32, "A7 0x802, FORMAT 6")
runTrapAndRte(0x803'u32, srReset, 0x70802700'u32, "A7 0x803, FORMAT 7")

# THE STACKED STATUS REGISTER IS THE COPY TAKEN BEFORE THE EXCEPTION CHANGED
# IT. Section 3.3, folio 3-11: the processor "makes an internal copy of the SR
# and then enters supervisor mode by setting the S-bit and disabling trace mode
# by clearing the T-bit". Entered with T set, the FRAME must carry T and the
# HANDLER must not, so this case separates the copy from the modified word;
# every case above enters with T already clear and cannot.
#   0100 | 00 | 00100000 | 00 | 1010011100000000 -> 0x4080A700
runTrapAndRte(0x800'u32, 0xA700'u32, 0x4080A700'u32, "A7 0x800, T set")

# ---------------------------------------------------------------------------
# BLOCK 6. The access error and the address error are NOT the same exception.
#
# Table 3-1 gives vector 2 at $008 to the access error and vector 3 at $00C to
# the address error, and design section 5.2.1 states in bold that the core must
# not conflate them. Neither has a producer in the core yet - CPU-15 owns the
# bus-fault channel and no path raises an address error - so both are raised
# through `takeException`, which is the procedure every producer will call.
#
# THE TWO SLOTS HOLD DIFFERENT HANDLER ADDRESSES AND THE READ LIST IS ASSERTED
# EXACTLY. A core that took vector 2 for both lands on `accessHandler` twice; a
# core that read both slots fails on the list; a core that stacked the wrong
# vector number fails on the frame's VEC field.

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

if failures.len > 0:
  echo ""
  echo "t_exception: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_exception: ", passCount, " cases passed"
