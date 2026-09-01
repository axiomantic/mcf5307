## `t_move` - the sized write to a data register in the data-movement group.
##
## This file exists beside `mcf5307_conformance_move` because it carries
## source-operand and zero-source variants the corpus does not, and it is the
## control that would catch a corpus regenerated wrongly.
##
## Every case below starts the destination at 0x12345678. That is the whole
## point of the file: the bytes outside the operand size carry a value that a
## replacing write destroys and a merging write keeps.
##
## `MOVE.B` and `MOVE.W` into `Dn` write the low 8 or the low 16 bits and
## leave the rest of the register alone. `MOVE.L` writes all 32. The same
## rule already governs `CLR.B` and `CLR.W`, and it governs the low half of
## `EXT.W`.
##
## The cases run through the shipped C entry points - `mcf5307_create`,
## `mcf5307_reset`, `mcf5307_set_reg`, `mcf5307_exec`, `mcf5307_get_reg` - and
## not through an internal helper reached around the back, so a pass here is a
## pass of the path the corpus runner drives.
##
## The encodings below were produced by the pinned `m68k-elf-as -mcpu=5307`:
##
##     0:  1200    moveb %d0,%d1
##     2:  3200    movew %d0,%d1
##     4:  2200    movel %d0,%d1

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
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, ok, label, got, want)
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
  # The status register is set last: `mcf5307_reset` writes it, so an earlier
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
# The destination starts non-zero in every case.

const dirtyDest = 0x12345678'u32

# ---------------------------------------------------------------------------
# MOVE.B %d0,%d1 = 1200. The low byte is written and the upper bytes are kept.

block:
  # The reference case. 0xAA over the low byte of 0x12345678 is 0x123456AA.
  # Bit 7 of the byte is set, so N is set.
  expectD(runIns([0x1200'u16], d = [0x000000AA'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x123456AA'u32, srBase or ccrN,
    "move.b d0,d1 writes the low byte and keeps the upper three")

  # A zero source byte is the starkest case of the rule. Z is set and N is
  # clear.
  expectD(runIns([0x1200'u16], d = [0'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x12345600'u32, srBase or ccrZ,
    "move.b d0,d1 of a zero byte clears the low byte alone and sets Z")

  # The other half of the merge. The source carries bits above the byte, and
  # they must not reach the destination.
  expectD(runIns([0x1200'u16], d = [0xFFFFFFAA'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x123456AA'u32, srBase or ccrN,
    "move.b d0,d1 takes the low byte of the source alone")

# ---------------------------------------------------------------------------
# MOVE.W %d0,%d1 = 3200. The low word is written and the upper word is kept.

block:
  # 0xBEEF over the low word of 0x12345678 is 0x1234BEEF. Bit 15 of the word
  # is set, so N is set.
  expectD(runIns([0x3200'u16], d = [0x0000BEEF'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x1234BEEF'u32, srBase or ccrN,
    "move.w d0,d1 writes the low word and keeps the upper word")

  # The zero source word, for the reason the zero source byte is above.
  expectD(runIns([0x3200'u16], d = [0'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x12340000'u32, srBase or ccrZ,
    "move.w d0,d1 of a zero word clears the low word alone and sets Z")

  # The source's upper word must not reach the destination. N is clear here:
  # bit 15 of 0x1234 is zero.
  expectD(runIns([0x3200'u16], d = [0xFFFF1234'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0x12341234'u32, srBase,
    "move.w d0,d1 takes the low word of the source alone")

# ---------------------------------------------------------------------------
# MOVE.L %d0,%d1 = 2200. The control against an over-fix.
#
# A long write replaces the whole register rather than merging into it. The
# destination starts non-zero here too, and none of it survives.

block:
  expectD(runIns([0x2200'u16],
                 d = [0xAABBCCDD'u32, dirtyDest, 0, 0, 0, 0, 0, 0]),
    1, 0xAABBCCDD'u32, srBase or ccrN,
    "move.l d0,d1 replaces the whole register")

# ---------------------------------------------------------------------------
# The three-way effective-address split, and `SWAP`.
#
# `AGENTS.md`'s `Comments` section names the shape: an invariant with no
# mechanism is a comment. These cases are the mechanism.
#
# The helpers below assert whole post-states rather than one register.

proc expectDAll(o: Outcome; wantD: array[8, uint32]; wantSr: uint32;
                label: string) =
  ## The whole data-register file, the whole status register, and `fault`.
  let got = (d: o.d, sr: o.sr, fault: o.fault)
  let wanted = (d: wantD, sr: wantSr, fault: false)
  check(got == wanted, label, $got, $wanted)

proc expectA(o: Outcome; n: int; want: uint32; wantSr: uint32; label: string) =
  let got = (reg: o.a[n], sr: o.sr, fault: o.fault)
  let wanted = (reg: want, sr: wantSr, fault: false)
  check(got == wanted, label, $got, $wanted)

proc expectPushed(o: Outcome; wantSp: uint32; wantValue: uint32;
                  wantSr: uint32; label: string) =
  ## The stack pointer after the push, the long word the push left at it, the
  ## status register and `fault`.
  let got = (sp: o.a[7], pushed: boardReadValue(board, o.a[7], 4),
             sr: o.sr, fault: o.fault)
  let wanted = (sp: wantSp, pushed: wantValue, sr: wantSr, fault: false)
  check(got == wanted, label, $got, $wanted)

proc expectFault(o: Outcome; label: string) =
  let got = (fault: o.fault, halted: o.halted)
  let wanted = (fault: true, halted: true)
  check(got == wanted, label, $got, $wanted)

# ---------------------------------------------------------------------------
# `SWAP Dn` - the halves of a data register exchange.
#
# The condition codes come from the generic rule and not from a per-instruction
# one, because no per-instruction rule exists to read. Exchanging a register's
# halves is no addition, no subtraction and no arithmetic operation, so V and C
# are cleared and X is untouched, and N and Z come from the result. That is
# `setNzClearVc(ctx, result, 4)`, the rule this core already shares between
# MOVE, MOVEQ, EXT, EXTB and the 32-bit multiply.
#
# What the generic rule does not give is the width. It says "the result" and
# never states how wide that result is. A reader who takes the flags from the
# operand size sets N from bit 15 and Z from the low half; this core takes the
# whole 32-bit register, because the register is what the instruction writes.
# The two readings disagree on any value whose halves differ in their top bit,
# and that residue is genuinely open.
#
# If an authority ever contradicts this, the cases to change are the `sr`
# arguments below and `setNzClearVc`'s call in `move.nim`; the register results
# do not move.

block:
  # The reference case. 0x12345678 -> 0x56781234. Bit 31 of the result is
  # clear and the result is non-zero, so the CCR stays clear.
  expectDAll(runIns([0x4840'u16],
                    d = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0]),
    [0x56781234'u32, 0, 0, 0, 0, 0, 0, 0], srBase,
    "swap d0 exchanges the halves of d0")

  # N-separator.
  # 0x0000FFFF -> 0xFFFF0000. Bit 31 of the result is set, so N is set; bit 15
  # of the result is clear.
  expectDAll(runIns([0x4840'u16],
                    d = [0x0000FFFF'u32, 0, 0, 0, 0, 0, 0, 0]),
    [0xFFFF0000'u32, 0, 0, 0, 0, 0, 0, 0], srBase or ccrN,
    "swap d0 takes N from bit 31 of the whole result")

  # N-separator, the other direction. 0xFFFF0000 -> 0x0000FFFF. Bit 31 of the
  # result is clear so N is clear; bit 15 of the result is set.
  expectDAll(runIns([0x4840'u16],
                    d = [0xFFFF0000'u32, 0, 0, 0, 0, 0, 0, 0]),
    [0x0000FFFF'u32, 0, 0, 0, 0, 0, 0, 0], srBase,
    "swap d0 leaves N clear when bit 31 of the result is clear")

  # Z is taken from all 32 bits. Zero is the only value whose swap is itself.
  expectDAll(runIns([0x4840'u16], d = zero8),
    zero8, srBase or ccrZ,
    "swap d0 of zero sets Z")

  # A half-zero value must not set Z.
  # 0x00001234 -> 0x12340000: the low half of the result is zero.
  expectDAll(runIns([0x4840'u16],
                    d = [0x00001234'u32, 0, 0, 0, 0, 0, 0, 0]),
    [0x12340000'u32, 0, 0, 0, 0, 0, 0, 0], srBase,
    "swap d0 takes Z from all 32 bits and not from the low half")

block:
  # X is untouched and V and C are cleared. One case cannot show both: X must
  # start set to show it survives, and V and C must start set to show they do
  # not.
  expectDAll(runIns([0x4840'u16],
                    d = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0],
                    sr = srBase or ccrX or ccrV or ccrC),
    [0x56781234'u32, 0, 0, 0, 0, 0, 0, 0], srBase or ccrX,
    "swap d0 keeps X and clears V and C")

block:
  # Every register, and every other register left alone. The register file is
  # seeded with distinct values.
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
# `LEA` and `PEA` at `(xxx).W`, and `MOVEM` still refusing it.
#
# `(xxx).W` is in the control category, and each instruction is settled by its
# own row rather than by that category alone: LEA and PEA are legal at
# `(xxx).W` and MOVEM is not.
#
# The pinned `m68k-elf-as -mcpu=5307` agrees: it accepts
# `lea 0x1234.w,%a0` (`41f8 1234`), `lea 0x8000.w,%a0` (`41f8 8000`),
# `lea 0x1234.w,%a3` (`47f8 1234`), `pea 0x1234.w` (`4878 1234`) and
# `pea 0x8000.w` (`4878 8000`), and it rejects `movem.l %d0-%d1,0x1234.w`
# with "operands mismatch".

block:
  # LEA loads the address and touches no flag. `41f8 1234`.
  expectA(runIns([0x41F8'u16, 0x1234'u16]), 0, 0x00001234'u32, srBase,
    "lea (xxx).W loads the absolute short address into An")

  # The sign extension, and it is the case a zero-extending core fails.
  # `(xxx).W` is sign-extended to 32 bits, so `0x8000` addresses `0xFFFF8000`
  # and not `0x00008000`. `41f8 8000`.
  expectA(runIns([0x41F8'u16, 0x8000'u16]), 0, 0xFFFF8000'u32, srBase,
    "lea (xxx).W sign-extends the absolute short address")

  # A second destination register. `47f8 1234` is `lea 0x1234.w,%a3`.
  expectA(runIns([0x47F8'u16, 0x1234'u16]), 3, 0x00001234'u32, srBase,
    "lea (xxx).W honours the destination register field")

block:
  # PEA pushes the address and touches no flag. `4878 1234`. The stack starts
  # at `stackBase` and a long word is pushed, so the pointer lands four bytes
  # below it and the address is the long word at the new pointer.
  expectPushed(runIns([0x4878'u16, 0x1234'u16]),
    stackBase - 4'u32, 0x00001234'u32, srBase,
    "pea (xxx).W pushes the absolute short address")

  # The sign extension again, on the push path. `4878 8000`.
  expectPushed(runIns([0x4878'u16, 0x8000'u16]),
    stackBase - 4'u32, 0xFFFF8000'u32, srBase,
    "pea (xxx).W pushes the sign-extended absolute short address")

block:
  # MOVEM must still trap at `(xxx).W`.
  #
  # The encoding is hand-built because the assembler refuses to build it, and
  # that refusal is the point. `MOVEM.L reglist,<ea>` is `0x48C0 | <ea>`; the
  # `(xxx).W` effective address is mode 111 register 000, or `0x38`, giving
  # `48f8`. The register mask `0003` selects d0 and d1 and the address word
  # follows it.
  #
  # The address is `0x0400`, inside the board. A legality trap and a bus fault
  # are not the same failure and a test that cannot tell them apart is not a
  # test.
  expectFault(runIns([0x48F8'u16, 0x0003'u16, 0x0400'u16]),
    "movem.l to (xxx).W traps")

  # And the trap happened before any store. `fault` alone cannot say whether
  # the registers reached memory first; this reads the target back.
  block:
    discard runIns([0x48F8'u16, 0x0003'u16, 0x0400'u16],
                   d = [0xAABBCCDD'u32, 0x11223344, 0, 0, 0, 0, 0, 0])
    let got = (at400: boardReadValue(board, 0x400'u32, 4),
               at404: boardReadValue(board, 0x404'u32, 4))
    let wanted = (at400: 0'u32, at404: 0'u32)
    check(got == wanted,
      "movem.l to (xxx).W stores nothing before it traps", $got, $wanted)

  # And MOVEM must trap at `(xxx).L`. `m68k-elf-as -mcpu=5307`
  # rejects `movem.l %d0-%d1,0x400.l` with "operands mismatch", and
  # `m68k-elf-objdump -m m68k:5307` decodes `48f9` as `.short` while
  # `-m m68k:68020` decodes the same bytes as a real `moveml`.
  #
  # The encoding is hand-built for the reason the `(xxx).W` pair gives - the
  # assembler refuses to build it. `MOVEM.L reglist,<ea>` is `0x48C0 | <ea>`
  # and `(xxx).L` is mode 111 register 001, or `0x39`, giving `48f9`; the
  # register mask `0003` selects d0 and d1 and the 32-bit address follows as
  # two words.
  #
  # The address is `0x0400`, inside the 0x1000-byte board.
  expectFault(runIns([0x48F9'u16, 0x0003'u16, 0x0000'u16, 0x0400'u16]),
    "movem.l to (xxx).L traps")

  # And nothing reached memory. `fault` alone cannot separate a legality trap
  # taken before the store from a bus fault taken during one; this reads the
  # target back. On a wide mask both words are written.
  block:
    discard runIns([0x48F9'u16, 0x0003'u16, 0x0000'u16, 0x0400'u16],
                   d = [0xAABBCCDD'u32, 0x11223344, 0, 0, 0, 0, 0, 0])
    let got = (at400: boardReadValue(board, 0x400'u32, 4),
               at404: boardReadValue(board, 0x404'u32, 4))
    let wanted = (at400: 0'u32, at404: 0'u32)
    check(got == wanted,
      "movem.l to (xxx).L stores nothing before it traps", $got, $wanted)

  # A wrongly-admitted cell at the execution level: `(d8,An,Xi)`.
  # `48f0` is `0x48C0 | 0x30`, mode 110 register 000, and the extension word
  # `2804` is the one `m68k-elf-objdump -m m68k:68020` renders as
  # `%a0@(4,%d2:l)`. A0 is left at zero and the index register at zero.
  expectFault(runIns([0x48F0'u16, 0x0003'u16, 0x2804'u16]),
    "movem.l to (d8,An,Xi) traps")

  # The positive control. `48d0 0003` is `movem.l %d0-%d1,(%a0)`, which
  # the assembler does emit. A0 points
  # into the scratch area, well clear of the instruction words and the stack.
  expectDAll(runIns([0x48D0'u16, 0x0003'u16],
                    d = [0xAABBCCDD'u32, 0x11223344, 0, 0, 0, 0, 0, 0],
                    a = [0x400'u32, 0, 0, 0, 0, 0, 0, 0]),
    [0xAABBCCDD'u32, 0x11223344, 0, 0, 0, 0, 0, 0], srBase,
    "movem.l to (An) still executes and touches no flag")

  # The second legal mode, `(d16,An)`, at the execution level. `48e8 0003
  # 0004` is `movem.l %d0-%d1,(4,%a0)`, which the assembler emits and which
  # folios 4-50 and 4-51 print with mode 101. A0 holds 0x400, so the
  # displacement puts d0 at 0x404 and d1 at 0x408.
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

  # And the registers actually reached memory: d0 at 0x400 and d1 at 0x404,
  # ascending, d0 first.
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

# The registry lines. They are data and not a verdict: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_move", declaredCaseSites)
echo caseSiteLine("executed", "t_move", executedSites)
echo caseSiteLine("off-green-path", "t_move", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_move: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_move: ", passCount, " cases passed"
