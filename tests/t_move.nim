## `t_move` - the sized write to a data register in the data-movement group.
## Design section 6.1.
##
## WHY THIS FILE EXISTS BESIDE `mcf5307_conformance_move`. When this file was
## written that corpus was 18 of 18, and it STAYED 18 of 18 with a destination
## register that was WRONG. The corpus held exactly two sized cases,
## `move_w_d0_to_d1` and `move_b_d0_to_d1`, and BOTH STARTED THE DESTINATION
## REGISTER AT ZERO. A core that keeps the bytes outside the size and a core
## that zeroes them produce the same register from a zero destination, so the
## two cores were not separable by any case the corpus held. The hole was in
## the corpus, not only in the executor.
##
## THE CORPUS HOLE IS NOW CLOSED AND THIS FILE STAYS. `conformance/generate.py`
## seeds every mergeable destination with 0x12345678 and both sized cases now
## fail against a replacing write, as does `move_b_mem_to_d1`, which had the
## same zero destination on the load path. The redundancy between a generated
## corpus and a hand-written case is not duplication to remove: this file
## carries source-operand and zero-source variants the corpus does not, and it
## is the control that would catch a corpus regenerated wrongly.
##
## EVERY CASE BELOW STARTS THE DESTINATION AT 0x12345678. That is the whole
## point of the file: the bytes outside the operand size carry a value that a
## replacing write destroys and a merging write keeps.
##
## THE RULE. `MOVE.B` and `MOVE.W` into `Dn` write the low 8 or the low 16 bits
## and LEAVE THE REST OF THE REGISTER ALONE. `MOVE.L` writes all 32. The same
## rule already governs `CLR.B` and `CLR.W`, which `t_alu` asserts, and it
## governs the low half of `EXT.W`; a core that is right there and wrong here
## holds two versions of one rule.
##
## THE CASES RUN THROUGH THE SHIPPED C ENTRY POINTS - `mcf5307_create`,
## `mcf5307_reset`, `mcf5307_set_reg`, `mcf5307_exec`, `mcf5307_get_reg` - and
## not through an internal helper reached around the back, so a pass here is a
## pass of the path the corpus runner drives. The board, the runner and the
## tuple assertions are the ones `tests/t_alu.nim` established.
##
## EVERY CASE ASSERTS A COMPLETE TUPLE (the register, the whole status
## register, `fault`), so a register that is right with a flag that is wrong
## fails, and a flag that is right with a register that is wrong fails. When
## this file was written it could assert the condition codes AT ALL only
## because it was not the corpus: no case in any of the four corpus files
## named `sr`. The corpus now names `sr` in the `move` and `alu` groups and
## asserts THE SAME WHOLE 16-BIT WORD against the same `srBase` of 0x2700, so
## the two views of one rule cannot drift apart.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Instruction
## semantics, the condition-code rules and the encodings are facts about
## Motorola silicon; they are taken from the ColdFire Family Programmer's
## Reference Manual and the MCF5307 User's Manual (AGENTS.md section 11) and
## from this project's own measurements. The three encodings below were
## produced by the pinned `m68k-elf-as -mcpu=5307`:
##
##     0:  1200    moveb %d0,%d1
##     2:  3200    movew %d0,%d1
##     4:  2200    movel %d0,%d1

import mcf5307/cpu
import mcf5307/decode_types
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

# ---------------------------------------------------------------------------
# The board. One flat byte array, big-endian, exactly as the conformance
# runner's board. A read outside it reports `busUnmapped` so that a runaway
# program faults instead of reading zeroes for ever.

const memSize = 0x1000

type TestBoard = object
  bytes: array[memSize, uint8]

var board: TestBoard

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

# ---------------------------------------------------------------------------
# The runner. Identical in shape to `t_alu`'s, and one instruction per call for
# the reason that file gives: the memory after the encoding is zero, 0x0000 is
# not an instruction this part has, and a generous budget would fetch it and
# report a fault the case's own instruction did not cause.

const
  execBase = 0x100'u32     ## where the instruction words are placed
  stackBase = 0x800'u32
  srBase = 0x2700'u32      ## the reset status register, CCR all clear
  zero8: array[8, uint32] = [0'u32, 0, 0, 0, 0, 0, 0, 0]

type Outcome = object
  cycles: uint32
  fault: bool
  halted: bool
  d: array[8, uint32]
  a: array[8, uint32]      ## a[7] is the single A7 (the stack pointer)
  sr: uint32

proc runIns(words: openArray[uint16];
            d: array[8, uint32] = zero8;
            a: array[8, uint32] = zero8;
            sr: uint32 = srBase): Outcome =
  ## Place `words` at `execBase`, set the register file and the status
  ## register, run one `mcf5307_exec`, and report the whole machine state.
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  for i in 0 ..< words.len:
    boardWrite(board, execBase + 2'u32 * uint32(i), 2, uint32(words[i]))

  let sp = if a[7] == 0'u32: stackBase else: a[7]
  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, sp, execBase)
  for i in 0 .. 7:
    discard mcf5307_set_reg(ctx, cint(i), d[i])
  for i in 0 .. 6:
    discard mcf5307_set_reg(ctx, cint(8 + i), a[i])
  # The status register is set LAST: `mcf5307_reset` writes it, so an earlier
  # write would be overwritten.
  discard mcf5307_set_reg(ctx, 16, sr)

  result.cycles = mcf5307_exec(ctx, 1'u32)
  result.fault = ctx.fault
  result.halted = ctx.halted
  for i in 0 .. 7:
    result.d[i] = mcf5307_get_reg(ctx, cint(i))
    result.a[i] = mcf5307_get_reg(ctx, cint(8 + i))
  result.sr = mcf5307_get_reg(ctx, 16)
  mcf5307_destroy(ctx)

proc expectD(o: Outcome; n: int; want: uint32; wantSr: uint32; label: string) =
  let got = (reg: o.d[n], sr: o.sr, fault: o.fault)
  let wanted = (reg: want, sr: wantSr, fault: false)
  check(got == wanted, label, $got, $wanted)

# ---------------------------------------------------------------------------
# THE DESTINATION STARTS NON-ZERO IN EVERY CASE.

const dirtyDest = 0x12345678'u32

# ---------------------------------------------------------------------------
# MOVE.B %d0,%d1 = 1200. The low byte is written and the upper THREE bytes are
# kept.

block:
  # The reference case. 0xAA over the low byte of 0x12345678 is 0x123456AA;
  # a replacing write gives 0x000000AA. Bit 7 of the byte is set, so N is set.
  expectD(runIns([0x1200'u16], d = [0x000000AA'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x123456AA'u32, srBase or ccrN,
    "move.b d0,d1 writes the low byte and keeps the upper three")

  # A ZERO SOURCE BYTE IS THE STARKEST CASE OF THE RULE. The written value and
  # the value a replacing write would leave behind are both zero in the low
  # byte, so the two cores differ in the upper three bytes ALONE: 0x12345600
  # against 0x00000000. Z is set and N is clear.
  expectD(runIns([0x1200'u16], d = [0'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x12345600'u32, srBase or ccrZ,
    "move.b d0,d1 of a zero byte clears the low byte alone and sets Z")

  # THE OTHER HALF OF THE MERGE. The source carries bits above the byte, and
  # they must NOT reach the destination. A merge that dropped the mask on the
  # incoming value gives 0xFFFFFFAA here and is right on both cases above.
  expectD(runIns([0x1200'u16], d = [0xFFFFFFAA'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x123456AA'u32, srBase or ccrN,
    "move.b d0,d1 takes the low byte of the source alone")

# ---------------------------------------------------------------------------
# MOVE.W %d0,%d1 = 3200. The low word is written and the upper word is kept.
# The word form is asserted separately from the byte form because the corpus
# case for each is degenerate in the same way, and a fix applied to one size
# does not prove the other.

block:
  # 0xBEEF over the low word of 0x12345678 is 0x1234BEEF; a replacing write
  # gives 0x0000BEEF. Bit 15 of the word is set, so N is set.
  expectD(runIns([0x3200'u16], d = [0x0000BEEF'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x1234BEEF'u32, srBase or ccrN,
    "move.w d0,d1 writes the low word and keeps the upper word")

  # The zero source word, for the reason the zero source byte is above: the two
  # cores differ in the upper word alone.
  expectD(runIns([0x3200'u16], d = [0'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x12340000'u32, srBase or ccrZ,
    "move.w d0,d1 of a zero word clears the low word alone and sets Z")

  # The source's upper word must not reach the destination. N is CLEAR here:
  # bit 15 of 0x1234 is zero, and a core that took N from bit 31 of the whole
  # source would set it.
  expectD(runIns([0x3200'u16], d = [0xFFFF1234'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x12341234'u32, srBase,
    "move.w d0,d1 takes the low word of the source alone")

# ---------------------------------------------------------------------------
# MOVE.L %d0,%d1 = 2200. THE CONTROL AGAINST AN OVER-FIX.
#
# A long write REPLACES the whole register, and it is the only one of the three
# that does. Without this case a core that preserved bytes at every size - one
# that masked with the byte width whatever the operand size - passes every case
# above. The destination starts non-zero here too, and none of it survives.

block:
  expectD(runIns([0x2200'u16],
                 d = [0xAABBCCDD'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0xAABBCCDD'u32, srBase or ccrN,
    "move.l d0,d1 replaces the whole register")

# ---------------------------------------------------------------------------
# THE THREE-WAY EFFECTIVE-ADDRESS SPLIT, AND `SWAP`.
#
# Everything below this line is the mechanism for two defects that were
# RECORDED and never FILED. `decode_types.nim`'s `eaJumpTarget` docstring and
# `tests/t_control.nim` block 9 both described the LEA/PEA mask defect in
# detail, and nothing went red while it was live. `AGENTS.md`'s 2026-08-06
# `EsaiClock` rule names the shape: an invariant with no mechanism is a
# comment. These cases are the mechanism.
#
# The helpers below assert WHOLE POST-STATES rather than one register, for the
# reason the file's header gives: a register that is right with a flag that is
# wrong must fail, and so must the reverse.

proc expectDAll(o: Outcome; wantD: array[8, uint32]; wantSr: uint32;
                label: string) =
  ## The WHOLE data-register file, the whole status register, and `fault`.
  let got = (d: o.d, sr: o.sr, fault: o.fault)
  let wanted = (d: wantD, sr: wantSr, fault: false)
  check(got == wanted, label, $got, $wanted)

proc expectA(o: Outcome; n: int; want: uint32; wantSr: uint32; label: string) =
  let got = (reg: o.a[n], sr: o.sr, fault: o.fault)
  let wanted = (reg: want, sr: wantSr, fault: false)
  check(got == wanted, label, $got, $wanted)

proc expectPushed(o: Outcome; wantSp: uint32; wantValue: uint32;
                  wantSr: uint32; label: string) =
  ## The stack pointer AFTER the push, the long word the push left at it, the
  ## status register and `fault`. Reading the memory is what separates a PEA
  ## that computed the address from one that only moved the pointer.
  let got = (sp: o.a[7], pushed: boardReadValue(board, o.a[7], 4),
             sr: o.sr, fault: o.fault)
  let wanted = (sp: wantSp, pushed: wantValue, sr: wantSr, fault: false)
  check(got == wanted, label, $got, $wanted)

proc expectFault(o: Outcome; label: string) =
  let got = (fault: o.fault, halted: o.halted)
  let wanted = (fault: true, halted: true)
  check(got == wanted, label, $got, $wanted)

# ---------------------------------------------------------------------------
# `SWAP Dn` - THE HALVES OF A DATA REGISTER EXCHANGE.
#
# WHY THIS IS HERE AT ALL. `SWAP` was in no cpu task's covered list anywhere in
# the implementation plan, so `opSwap` sat in the `Operation` enum with no arm
# of `decodeWord` producing it. That was not a gap awaiting a later task: the
# PEA arm's mask `word and 0xFFC0 == 0x4840` spans `4840`-`487f` and SWALLOWED
# all eight SWAP encodings, and `eaLegalityFor(opPea)` excludes `Dn`, so every
# `swap` on this core faulted as an illegal PEA operand.
#
# THE ENCODING AND THE OPERATION ARE MANUAL-GROUNDED AND MEASURED.
#   - MCF5307 User's Manual Table 3-7, "Instruction Set Summary", page 3-25,
#     read as a RENDERED IMAGE: `SWAP | Dn | 16 | MSW of Dn <-> LSW of Dn`.
#     (The row does NOT survive `pdftotext`; a text-extracted search for
#     "SWAP" over the whole manual returns only the Table 3-12 timing row.)
#   - Table 3-12, "One Operand Instruction Execution Times", page 3-27:
#     `swap | Dx | Rn 1(0/0)` and a DASH in all seven other columns, which is
#     this project's legality oracle for "a data register and nothing else".
#   - Section 3.9, page 3-21, lists the removed instruction groups - BCD, bit
#     field, logical rotate, decrement and branch, integer division, and
#     integer multiply with a 64-bit result. SWAP IS NOT AMONG THEM.
#   - The pinned `m68k-elf-as -mcpu=5307` (GNU Binutils 2.47.20260726) emits
#     `4840` for `swap %d0`, `4843` for `swap %d3` and `4847` for `swap %d7`.
#   - The shipped G2 operating system uses it: `CODE_30000400.bin` holds 339
#     words in `4840`-`4847` on a two-byte-aligned scan, the first at
#     `0x3000066c`. 339 IS THE MEASURED FIGURE AND 335 IS NOT RECONSTRUCTIBLE.
#     An earlier relay of this count gave 335; no derivation reproduces it,
#     and six were tried - unaligned 423, four-byte-aligned 167, skipping a
#     `0x400` header 334, skipping `0x10000` 330, `objdump -m m68k:5307` 337,
#     `objdump -m m68k:68000` 334. The 335 is recorded here as unexplained so
#     that it is not mistaken for a third measurement if it resurfaces.
#     `m68k-elf-objdump -m m68k:5307` decodes the first hit's context as
#     `mulsl %d0,%d2 / addil #32768,%d2 / swap %d2 / extl %d2` - a 16.16
#     fixed-point multiply that rounds by adding a half and then takes the
#     high word. A core that faults on `swap` cannot run that firmware.
#
# THE CONDITION CODES ARE MANUAL-DERIVED, FROM SECTION 3.2.1.5, PAGE 3-9.
# No PER-INSTRUCTION rule exists to read: Table 3-7's OPERATION column for
# SWAP reads `MSW of Dn <-> LSW of Dn` with NO condition-code clause and
# Table 3-12 gives timing only, and those two rows are the only places the
# manual names SWAP. The GENERIC rule is what settles it. Section 3.2.1.5
# opens at the foot of page 3-8 with the CCR bit-field figure and DOES NOT
# END THERE; page 3-9 defines each bit - N "Set if the most significant bit
# of the result is set; otherwise cleared", Z "Set if the result equals
# zero; otherwise cleared", V "Set if an arithmetic overflow occurs implying
# that the result cannot be represented in the operand size; otherwise
# cleared", C "Set if a carryout of the operand MSB occurs for an addition,
# or if a borrow occurs in a subtraction; otherwise cleared", X "Set to the
# value of the C-bit for arithmetic operations; otherwise not affected".
# Exchanging a register's halves is no addition, no subtraction and no
# arithmetic operation, so V and C are cleared and X is untouched, and N and
# Z come from the result. That is `setNzClearVc(ctx, result, 4)`, the rule
# this core already shares between MOVE, MOVEQ, EXT, EXTB and the 32-bit
# multiply - and it is the SAME derivation `logic.nim` runs for AND, OR, EOR
# and NOT and for its shift-by-zero X guard, not a second argument.
#
# SECTION 3.9 IS NOT THE ORACLE, AND AN EARLIER REVISION OF THIS BLOCK MADE
# IT ONE. It was cited here for "a reduced version of the 68000 instruction
# set", concluding that a retained SWAP keeps its 68000 flags. That inference
# fails twice over. Section 3.9's removed list is itself unreliable - page
# 3-21 names "integer division" as removed while Table 3-7 on page 3-23
# carries DIVS and DIVU rows and Table 3-13 on page 3-28 times `divs.w`,
# `divu.w`, `divs.l` and `divu.l`. And "reduced version" is a claim about SET
# MEMBERSHIP, not per-instruction semantics: Table 3-7 gives ADD, SUB, AND,
# OR, EOR and CMP an OPERAND SIZE of 32 ALONE where the 68000 has `.b`, `.w`
# and `.l`, so retained instructions here are not semantically identical to
# their 68000 originals. Section 3.9 is still good for what it is used for
# above - SWAP not appearing in a removal list is evidence about MEMBERSHIP,
# which is the one kind of claim that list makes.
#
# THE CFPRM WALL IS REAL BUT IT IS NOT WHAT DECIDES THIS. CPU-9 met the same
# wall on `ASL`'s overflow reading and the zero-shift-count status word
# (section 24.6 row W3-28), derived what section 3.2.1.5 gives, and then
# DECLINED to pin the residue. The flags below are pinned because 3.2.1.5
# DERIVES them - not by precedent, and not by a 68000 inheritance argument.
#
# WHAT 3.2.1.5 DOES NOT GIVE IS THE WIDTH, AND THE CASES BELOW SEPARATE IT.
# The section says "the result" and never states how wide that result is,
# while Table 3-7's OPERAND SIZE column for SWAP says 16. A reader who takes
# the flags from the operand size sets N from bit 15 and Z from the low half;
# this core takes the whole 32-bit register, because the register is what the
# instruction writes. The two readings disagree on any value whose halves
# differ in their top bit, and the two cases marked N-SEPARATOR below -
# `0x0000FFFF` and `0xFFFF0000` - are exactly those values. That residue is
# genuinely open; the CFPRM would close it.
#
# IF THE CFPRM EVER ARRIVES AND CONTRADICTS THIS, the cases to change are the
# `sr` arguments below and `setNzClearVc`'s call in `move.nim`; the register
# results are manual-grounded and do not move.

block:
  # The reference case. 0x12345678 -> 0x56781234. Bit 31 of the result is
  # clear and the result is non-zero, so the CCR stays clear.
  expectDAll(runIns([0x4840'u16],
                    d = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0]),
    [0x56781234'u32, 0, 0, 0, 0, 0, 0, 0], srBase,
    "swap d0 exchanges the halves of d0")

  # N-SEPARATOR, and the direction that catches N taken from bit 15.
  # 0x0000FFFF -> 0xFFFF0000. Bit 31 of the RESULT is set, so N is set; bit 15
  # of the result is CLEAR, so a core that read the operand-size column of
  # Table 3-7 as the flag width leaves N clear here and fails.
  expectDAll(runIns([0x4840'u16],
                    d = [0x0000FFFF'u32, 0, 0, 0, 0, 0, 0, 0]),
    [0xFFFF0000'u32, 0, 0, 0, 0, 0, 0, 0], srBase or ccrN,
    "swap d0 takes N from bit 31 of the whole result")

  # N-SEPARATOR, the other direction. 0xFFFF0000 -> 0x0000FFFF. Bit 31 of the
  # result is CLEAR so N is clear; bit 15 of the result is SET, so a bit-15
  # core sets N here and fails. The pair brackets the rule from both sides,
  # which one case alone cannot do.
  expectDAll(runIns([0x4840'u16],
                    d = [0xFFFF0000'u32, 0, 0, 0, 0, 0, 0, 0]),
    [0x0000FFFF'u32, 0, 0, 0, 0, 0, 0, 0], srBase,
    "swap d0 leaves N clear when bit 31 of the result is clear")

  # Z IS TAKEN FROM ALL 32 BITS. Zero is the only value whose swap is itself,
  # so this case cannot tell a swap from a no-operation on the register - it
  # is here for the flag alone, and the cases above carry the register rule.
  expectDAll(runIns([0x4840'u16], d = zero8),
    zero8, srBase or ccrZ,
    "swap d0 of zero sets Z")

  # A HALF-ZERO VALUE MUST NOT SET Z, which a core taking Z from 16 bits does.
  # 0x00001234 -> 0x12340000: the low half of the RESULT is zero.
  expectDAll(runIns([0x4840'u16],
                    d = [0x00001234'u32, 0, 0, 0, 0, 0, 0, 0]),
    [0x12340000'u32, 0, 0, 0, 0, 0, 0, 0], srBase,
    "swap d0 takes Z from all 32 bits and not from the low half")

block:
  # X IS UNTOUCHED AND V AND C ARE CLEARED. One case cannot show both: X must
  # start SET to show it survives, and V and C must start SET to show they do
  # not. This case starts all three set and asserts X alone survives.
  expectDAll(runIns([0x4840'u16],
                    d = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0],
                    sr = srBase or ccrX or ccrV or ccrC),
    [0x56781234'u32, 0, 0, 0, 0, 0, 0, 0], srBase or ccrX,
    "swap d0 keeps X and clears V and C")

block:
  # EVERY REGISTER, AND EVERY OTHER REGISTER LEFT ALONE. The register file is
  # seeded with eight distinct values, so a core that decoded the register
  # field wrongly - or ignored it and always swapped d0 - writes the right
  # value into the wrong place and the whole-array assertion catches it.
  # `4840`-`4847` is the range the PEA mask used to swallow entire.
  const seed: array[8, uint32] = [0x00010002'u32, 0x00110012, 0x00210022,
                                  0x00310032, 0x00410042, 0x00510052,
                                  0x00610062, 0x00710072]
  const swapped: array[8, uint32] = [0x00020001'u32, 0x00120011, 0x00220021,
                                     0x00320031, 0x00420041, 0x00520051,
                                     0x00620061, 0x00720071]
  for n in 0 .. 7:
    var want = seed
    want[n] = swapped[n]
    expectDAll(runIns([uint16(0x4840 + n)], d = seed), want, srBase,
      "swap d" & $n & " swaps d" & $n & " and leaves the other seven alone")

# ---------------------------------------------------------------------------
# `LEA` AND `PEA` AT `(xxx).W`, AND `MOVEM` STILL REFUSING IT.
#
# A SET THEN CALLED `eaControl7NoAbsW` HELD
# `{ea7AbsL, ea7PCDisp, ea7PCIndex}` - no `(xxx).W`. It is RETIRED as of
# 2026-08-11, and `ea.nim`'s `eaControl7` now holds the full control mode-7
# class with `(xxx).W` in it; this block reads the behaviour and not the set.
# LEA, PEA and MOVEM ALL READ THE `NoAbsW` SET UNTIL 2026-08-11: LEA's and
# PEA's exclusion of `(xxx).W` was WRONG and MOVEM's was RIGHT, so one
# constant could not serve all three. LEA and PEA moved to `eaLeaPeaTarget`,
# and MOVEM then moved OFF the constant entirely - its `(xxx).W` exclusion was
# the only cell that set got right for it, and folios 4-50 and 4-51 dash four
# more. MOVEM now carries `{eaAnInd, eaAnDisp}` with an empty `ea7`.
#
# THE MANUAL PUTS `(xxx).W` IN THE CONTROL CATEGORY, and each of the three
# instructions is settled by its OWN row rather than by that category alone:
#   - Table 3-5, "Effective Addressing Modes and Categories", page 3-21:
#     "Absolute Data Addressing / Short", syntax `(xxx).W`, mode field 111,
#     register field 000, carries an `x` under DATA, MEMORY and CONTROL.
#   - Table 3-13, "Two Operand Instruction Execution Times", page 3-28: the
#     `lea | <ea>,Ax` row is timed 1(0/0) under `xxx.wl` and DASHED under
#     `Rn`, `(An)+`, `-(An)` and `#xxx`.
#   - Table 3-14, "Miscellaneous Instruction Execution Times", page 3-29: the
#     `pea | <ea>` row is timed 2(0/1) under `xxx.wl`. PEA has its own row in
#     its own table and does not have to borrow LEA's.
#   - Page 3-26 defines the column: 'The nomenclature "xxx.wl" refers to both
#     forms of absolute addressing, xxx.w and xxx.l.' So a time under
#     `xxx.wl` is a time under `(xxx).W`.
#   - Table 3-14 again, and this is what keeps MOVEM out: both `movem.l`
#     rows are timed under `(An)` and `(d16,An)` ONLY, and DASHED under
#     `xxx.wl`. Table 3-13's dash is this project's legality oracle, and here
#     it points the other way from LEA's and PEA's times.
#
# The pinned `m68k-elf-as -mcpu=5307` agrees with all four rows: it accepts
# `lea 0x1234.w,%a0` (`41f8 1234`), `lea 0x8000.w,%a0` (`41f8 8000`),
# `lea 0x1234.w,%a3` (`47f8 1234`), `pea 0x1234.w` (`4878 1234`) and
# `pea 0x8000.w` (`4878 8000`), and it REJECTS `movem.l %d0-%d1,0x1234.w`
# with "operands mismatch".

block:
  # LEA loads the ADDRESS and touches no flag. `41f8 1234`.
  expectA(runIns([0x41F8'u16, 0x1234'u16]), 0, 0x00001234'u32, srBase,
    "lea (xxx).W loads the absolute short address into An")

  # THE SIGN EXTENSION, AND IT IS THE CASE A ZERO-EXTENDING CORE FAILS.
  # `(xxx).W` is sign-extended to 32 bits, so `0x8000` addresses `0xFFFF8000`
  # and not `0x00008000`. `41f8 8000`.
  expectA(runIns([0x41F8'u16, 0x8000'u16]), 0, 0xFFFF8000'u32, srBase,
    "lea (xxx).W sign-extends the absolute short address")

  # A SECOND DESTINATION REGISTER. `47f8 1234` is `lea 0x1234.w,%a3`, and a
  # core that ignored the destination field would put the address in a0.
  expectA(runIns([0x47F8'u16, 0x1234'u16]), 3, 0x00001234'u32, srBase,
    "lea (xxx).W honours the destination register field")

block:
  # PEA pushes the ADDRESS and touches no flag. `4878 1234`. The stack starts
  # at `stackBase` and a long word is pushed, so the pointer lands four bytes
  # below it and the address is the long word AT the new pointer.
  expectPushed(runIns([0x4878'u16, 0x1234'u16]),
    stackBase - 4'u32, 0x00001234'u32, srBase,
    "pea (xxx).W pushes the absolute short address")

  # The sign extension again, on the push path. `4878 8000`.
  expectPushed(runIns([0x4878'u16, 0x8000'u16]),
    stackBase - 4'u32, 0xFFFF8000'u32, srBase,
    "pea (xxx).W pushes the sign-extended absolute short address")

block:
  # MOVEM MUST STILL TRAP AT `(xxx).W`. This is the third direction of the
  # split and the one that fails if `eaControl7` is handed to the MOVEM arm.
  #
  # THE ENCODING IS HAND-BUILT BECAUSE THE ASSEMBLER REFUSES TO BUILD IT, and
  # that refusal is the point. `MOVEM.L reglist,<ea>` is `0x48C0 | <ea>`; the
  # `(xxx).W` effective address is mode 111 register 000, or `0x38`, giving
  # `48f8`. The register mask `0003` selects d0 and d1 and the address word
  # follows it.
  #
  # THE ADDRESS IS `0x0400`, INSIDE THE BOARD, AND THE CHOICE IS THE WHOLE
  # STRENGTH OF THIS CASE. An earlier draft used `0x1234`, which is past the
  # end of this file's 0x1000-byte board - so a MOVEM whose mask had been
  # WIDENED to accept `(xxx).W` would reach the executor, attempt the store,
  # take a BUS fault on the unmapped address, and set `fault` anyway. The
  # case passed either way and asserted nothing. Measured: with the address
  # at `0x1234`, wiring `opMovem` to `eaLeaPeaTarget` left this case GREEN.
  # At `0x0400` the widened mask completes the store and `fault` stays
  # false, so the case goes red. A legality trap and a bus fault are not the
  # same failure and a test that cannot tell them apart is not a test.
  expectFault(runIns([0x48F8'u16, 0x0003'u16, 0x0400'u16]),
    "movem.l to (xxx).W traps")

  # AND THE TRAP HAPPENED BEFORE ANY STORE. `fault` alone cannot say whether
  # the registers reached memory first; this reads the target back. A widened
  # mask leaves 0xAABBCCDD at 0x400 and fails here as well as above, so the
  # rule is asserted in two independent directions.
  block:
    discard runIns([0x48F8'u16, 0x0003'u16, 0x0400'u16],
                   d = [0xAABBCCDD'u32, 0x11223344, 0, 0, 0, 0, 0, 0])
    let got = (at400: boardReadValue(board, 0x400'u32, 4),
               at404: boardReadValue(board, 0x404'u32, 4))
    let wanted = (at400: 0'u32, at404: 0'u32)
    check(got == wanted,
      "movem.l to (xxx).W stores nothing before it traps", $got, $wanted)

  # AND MOVEM MUST TRAP AT `(xxx).L`, WHICH IS THE CELL THAT WAS LIVE. The
  # `(xxx).W` pair above passed against a mask that admitted FOUR OTHER CELLS,
  # because the retired `NoAbsW` set excluded the absolute SHORT form alone
  # and the `opMovem` arm read the whole control class either side of it.
  # Folios 4-50
  # and 4-51 dash `(xxx).L` in BOTH directions, `m68k-elf-as -mcpu=5307`
  # rejects `movem.l %d0-%d1,0x400.l` with "operands mismatch", and
  # `m68k-elf-objdump -m m68k:5307` decodes `48f9` as `.short` while
  # `-m m68k:68020` decodes the same bytes as a real `moveml`.
  #
  # MEASURED ON THE WIDE MASK, 2026-08-11: this instruction reached the
  # executor and COMPLETED ITS STORE. `fault` was false and 0xAABBCCDD stood
  # at 0x400. That is the whole reason the narrowing is not cosmetic.
  #
  # THE ENCODING IS HAND-BUILT for the reason the `(xxx).W` pair gives - the
  # assembler refuses to build it. `MOVEM.L reglist,<ea>` is `0x48C0 | <ea>`
  # and `(xxx).L` is mode 111 register 001, or `0x39`, giving `48f9`; the
  # register mask `0003` selects d0 and d1 and the 32-bit address follows as
  # two words.
  #
  # THE ADDRESS IS `0x0400`, INSIDE THE 0x1000-BYTE BOARD, AND THAT IS WHAT
  # MAKES THE CASE ABLE TO FAIL. At an address past the end of the board a
  # widened mask would reach the executor, attempt the store, take a BUS fault
  # on the unmapped address and set `fault` anyway - passing while asserting
  # nothing. The `(xxx).W` pair records the same trap being measured at
  # `0x1234`, where it left the case GREEN.
  expectFault(runIns([0x48F9'u16, 0x0003'u16, 0x0000'u16, 0x0400'u16]),
    "movem.l to (xxx).L traps")

  # AND NOTHING REACHED MEMORY. `fault` alone cannot separate a legality trap
  # taken before the store from a bus fault taken during one; this reads the
  # target back. On the wide mask both words were written and this case names
  # the bytes that were there.
  block:
    discard runIns([0x48F9'u16, 0x0003'u16, 0x0000'u16, 0x0400'u16],
                   d = [0xAABBCCDD'u32, 0x11223344, 0, 0, 0, 0, 0, 0])
    let got = (at400: boardReadValue(board, 0x400'u32, 4),
               at404: boardReadValue(board, 0x404'u32, 4))
    let wanted = (at400: 0'u32, at404: 0'u32)
    check(got == wanted,
      "movem.l to (xxx).L stores nothing before it traps", $got, $wanted)

  # THE THIRD WRONGLY-ADMITTED CELL AT THE EXECUTION LEVEL: `(d8,An,Xi)`.
  # `48f0` is `0x48C0 | 0x30`, mode 110 register 000, and the extension word
  # `2804` is the one `m68k-elf-objdump -m m68k:68020` renders as
  # `%a0@(4,%d2:l)`. A0 is left at zero and the index register at zero, so a
  # widened mask computes 0x004 + 0 and stores INSIDE the board rather than
  # faulting on an unmapped address - the same requirement the `(xxx).L` case
  # states. `(d16,PC)` and `(d8,PC,Xi)` are not asserted here: as a
  # register-to-MEMORY destination the folio dashes them in a direction the
  # executor has no store path for, and block (13) of `t_ea_masks` carries
  # them at the mask level where the assertion is exact.
  expectFault(runIns([0x48F0'u16, 0x0003'u16, 0x2804'u16]),
    "movem.l to (d8,An,Xi) traps")

  # THE POSITIVE CONTROL, and without it the case above passes on a core whose
  # MOVEM is broken outright. `48d0 0003` is `movem.l %d0-%d1,(%a0)`, which
  # the assembler DOES emit and which Table 3-14 times under `(An)`. A0 points
  # into the scratch area, well clear of the instruction words and the stack.
  expectDAll(runIns([0x48D0'u16, 0x0003'u16],
                    d = [0xAABBCCDD'u32, 0x11223344, 0, 0, 0, 0, 0, 0],
                    a = [0x400'u32, 0, 0, 0, 0, 0, 0, 0]),
    [0xAABBCCDD'u32, 0x11223344, 0, 0, 0, 0, 0, 0], srBase,
    "movem.l to (An) still executes and touches no flag")

  # THE SECOND LEGAL MODE, `(d16,An)`, AT THE EXECUTION LEVEL. `48e8 0003
  # 0004` is `movem.l %d0-%d1,(4,%a0)`, which the assembler emits and which
  # folios 4-50 and 4-51 print with mode 101. A0 holds 0x400, so the
  # displacement puts d0 at 0x404 and d1 at 0x408.
  #
  # IT IS HERE BECAUSE THE NARROWING HAD NO EXECUTION-LEVEL POSITIVE CONTROL
  # FOR THIS MODE. Measured 2026-08-11, BEFORE THIS CASE EXISTED: dropping
  # `eaAnDisp` from the `opMovem` arm - over-narrowing it to `{eaAnInd}` - left
  # `t_move` at 33 of 33 PASSED and reddened exactly ONE case, in block (13) of
  # `tests/t_ea_masks.nim`. A single assertion in one file was the whole guard
  # against a MOVEM that traps a form the compiler emits constantly for
  # prologues, so this case gives the executor its own witness.
  #
  # RE-MEASURED 2026-08-12 with this case and with block (19) of that file both
  # in place: the same drop now reds THREE - this case, block (13)'s `movem:
  # the mask accepts (d16,An)`, and block (19)'s `opMovem` row.
  block:
    let o = runIns([0x48E8'u16, 0x0003'u16, 0x0004'u16],
                   d = [0xAABBCCDD'u32, 0x11223344, 0, 0, 0, 0, 0, 0],
                   a = [0x400'u32, 0, 0, 0, 0, 0, 0, 0])
    let got = (at404: boardReadValue(board, 0x404'u32, 4),
               at408: boardReadValue(board, 0x408'u32, 4),
               fault: o.fault, sr: o.sr)
    let wanted = (at404: 0xAABBCCDD'u32, at408: 0x11223344'u32,
                  fault: false, sr: srBase)
    check(got == wanted,
      "movem.l to (d16,An) executes and stores at the displaced address",
      $got, $wanted)

  # And the registers actually reached memory, which the register assertion
  # above cannot see: d0 at 0x400 and d1 at 0x404, ascending, d0 first.
  block:
    let o = runIns([0x48D0'u16, 0x0003'u16],
                   d = [0xAABBCCDD'u32, 0x11223344, 0, 0, 0, 0, 0, 0],
                   a = [0x400'u32, 0, 0, 0, 0, 0, 0, 0])
    let got = (at400: boardReadValue(board, 0x400'u32, 4),
               at404: boardReadValue(board, 0x404'u32, 4),
               fault: o.fault)
    let wanted = (at400: 0xAABBCCDD'u32, at404: 0x11223344'u32, fault: false)
    check(got == wanted, "movem.l to (An) stores d0 then d1 in ascending order",
      $got, $wanted)

if failures.len > 0:
  echo ""
  echo "t_move: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_move: ", passCount, " cases passed"
