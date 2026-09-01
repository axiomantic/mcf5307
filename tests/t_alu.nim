## `t_alu` - the integer-arithmetic instruction group.
##
## This file exists beside `mcf5307_conformance_alu` because it carries the
## sticky-Z rule of ADDX/SUBX/NEGX, the trap cases for encodings this part
## does not have, and the direct reads of `eaIsLegalFor`.
## Redundancy between a generated corpus and a hand-written
## case is not duplication to remove.
##
## Half of this instruction group is the condition codes: `ADDX`, `SUBX` and
## `NEGX` read X, the sticky-Z rule of those three is a rule about Z alone, and
## the overflow of `MULS.L` is observable in V and nowhere else. This file is
## where those are asserted, and it asserts them through the same entry points
## the corpus uses - `mcf5307_reset`, `mcf5307_set_reg`, `mcf5307_exec`,
## `mcf5307_get_reg` - so that a pass here is a pass of the shipped path and
## not of an internal helper reached around the back.
##
## The trap cases are the green-mirage control of the group. Byte and word
## arithmetic does not exist on this part, and neither does an `ADDI` to
## memory, a `NEG` to memory, a PC-relative `ADDQ` destination or a 64-bit
## `MULU.L`. Each one below was checked against `m68k-elf-as -mcpu=5307`,
## which rejects every one of them; the assembler is the ground truth for what
## the part has, and the corresponding encodings are asserted here to trap.

import std/strutils
import mcf5307/cpu
import mcf5307/decode
import mcf5307/decode_types
import mcf5307/ea
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
# The runner.

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
  pc: uint32               ## the only witness of an extension word too many

proc runIns(words: openArray[uint16];
            d: array[8, uint32] = zero8;
            a: array[8, uint32] = zero8;
            sr: uint32 = srBase;
            mem: seq[(uint32, uint32)] = @[]): Outcome =
  ## Place `words` at `execBase`, set the register file and the status
  ## register, run one `mcf5307_exec`, and report the whole machine state.
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  for i in 0 ..< words.len:
    boardWrite(board, execBase + 2'u32 * uint32(i), 2, uint32(words[i]))
  for (address, value) in mem:
    boardWrite(board, address, 4, value)

  let sp = if a[7] == 0'u32: stackBase else: a[7]
  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, sp, execBase)
  for i in 0 .. 7:
    discard mcf5307_set_reg(ctx, cint(i), d[i])
  for i in 0 .. 6:
    discard mcf5307_set_reg(ctx, cint(8 + i), a[i])
  # The status register is set last: `mcf5307_reset` writes it, so an earlier
  # write would be overwritten and every X-reading case would silently run
  # with X clear.
  discard mcf5307_set_reg(ctx, 16, sr)

  # One instruction, and the budget is what stops the loop after it. The
  # memory after the encoding is zero, and 0x0000 is not an instruction this
  # part has, so a generous budget would fetch it, halt with `fault`, and make
  # every case here report a fault that its own instruction did not cause.
  # `mcf5307_exec` executes one instruction whenever the budget is smaller
  # than that instruction's cost, and every cost is above one.
  #
  # The return is therefore 1 for an instruction that ran and 0 for one that
  # trapped, which is exactly the distinction the trap cases assert.
  result.cycles = mcf5307_exec(ctx, 1'u32)
  result.fault = ctx.fault
  result.halted = ctx.halted
  for i in 0 .. 7:
    result.d[i] = mcf5307_get_reg(ctx, cint(i))
    result.a[i] = mcf5307_get_reg(ctx, cint(8 + i))
  result.sr = mcf5307_get_reg(ctx, 16)
  result.pc = mcf5307_get_reg(ctx, 17)
  mcf5307_destroy(ctx)

proc mem32(address: uint32): uint32 =
  boardReadValue(board, address, 4)

# The two assertions. Each compares one complete tuple, so a right result with
# a wrong flag fails and a right flag with a wrong result fails.

proc expectD(o: Outcome; n: int; want: uint32; wantSr: uint32; label: string) =
  let got = (reg: o.d[n], sr: o.sr, fault: o.fault)
  let wanted = (reg: want, sr: wantSr, fault: false)
  check(got == wanted, label, $got, $wanted)

proc expectA(o: Outcome; n: int; want: uint32; wantSr: uint32; label: string) =
  let got = (reg: o.a[n], sr: o.sr, fault: o.fault)
  let wanted = (reg: want, sr: wantSr, fault: false)
  check(got == wanted, label, $got, $wanted)

proc expectTrapD(o: Outcome; n: int; unchanged: uint32; label: string) =
  ## An encoding the part does not have. It must halt with `fault`, return no
  ## cycles, and leave the destination register alone.
  let got = (reg: o.d[n], fault: o.fault, halted: o.halted, cycles: o.cycles)
  let wanted = (reg: unchanged, fault: true, halted: true, cycles: 0'u32)
  check(got == wanted, label, $got, $wanted)

# ---------------------------------------------------------------------------
# ADD, ADDA, ADDI, ADDQ, ADDX.

block:
  # add.l %d0,%d1 = d280. 1 + 2 = 3; no carry, no overflow, not negative.
  expectD(runIns([0xD280'u16], d = [1'u32, 2, 0, 0, 0, 0, 0, 0]),
    1, 3'u32, srBase, "add.l d0,d1 = 3, CCR clear")

  # The carry out of bit 31 sets both C and X, and the zero result sets Z.
  expectD(runIns([0xD280'u16], d = [1'u32, 0xFFFFFFFF'u32, 0, 0, 0, 0, 0, 0]),
    1, 0'u32, srBase or ccrC or ccrX or ccrZ,
    "add.l carry out sets C, X and Z")

  # Signed overflow: 0x7FFFFFFF + 1 crosses into the negative half. V and N
  # are set and C is not: the unsigned sum did not carry.
  expectD(runIns([0xD280'u16], d = [1'u32, 0x7FFFFFFF'u32, 0, 0, 0, 0, 0, 0]),
    1, 0x80000000'u32, srBase or ccrV or ccrN,
    "add.l signed overflow sets V and N and leaves C clear")

  # A negative sum with no carry and no overflow: N alone.
  expectD(runIns([0xD280'u16], d = [0xFFFFFFFF'u32, 0, 0, 0, 0, 0, 0, 0]),
    1, 0xFFFFFFFF'u32, srBase or ccrN, "add.l negative sum sets N alone")

  # add.l %a0,%d1 = d288. An direct is a legal source.
  expectD(runIns([0xD288'u16], d = [0'u32, 2, 0, 0, 0, 0, 0, 0],
                 a = [5'u32, 0, 0, 0, 0, 0, 0, 0]),
    1, 7'u32, srBase, "add.l a0,d1 reads the address register")

block:
  # add.l %d1,(%a0)+ = d398. The postincrement happens once. A read-modify-
  # write that evaluates the effective address twice increments a0 twice and
  # writes to the wrong address; both are visible here.
  let o = runIns([0xD398'u16], d = [0'u32, 5, 0, 0, 0, 0, 0, 0],
                 a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0],
                 mem = @[(0x200'u32, 10'u32)])
  let got = (mem: mem32(0x200'u32), a0: o.a[0], sr: o.sr, fault: o.fault)
  let want = (mem: 15'u32, a0: 0x204'u32, sr: srBase, fault: false)
  check(got == want, "add.l d1,(a0)+ writes once and increments a0 once",
    $got, $want)

block:
  # adda.l %d0,%a1 = d3c0. ADDA does not touch the condition codes: the whole
  # CCR is set on entry and must come back untouched, and the sum 0 would
  # otherwise have set Z and cleared N.
  let dirty = srBase or ccrC or ccrV or ccrZ or ccrN or ccrX
  expectA(runIns([0xD3C0'u16], d = [0xFFFFFFFF'u32, 0, 0, 0, 0, 0, 0, 0],
                 a = [0'u32, 1, 0, 0, 0, 0, 0, 0], sr = dirty),
    1, 0'u32, dirty, "adda.l leaves every condition code alone")

  # adda.l #500,%a1 = d3fc 0000 01f4. The immediate source is long.
  expectA(runIns([0xD3FC'u16, 0x0000'u16, 0x01F4'u16],
                 a = [0'u32, 4, 0, 0, 0, 0, 0, 0]),
    1, 504'u32, srBase, "adda.l #500,a1 adds the long immediate")

block:
  # addi.l #7,%d1 = 0681 0000 0007.
  expectD(runIns([0x0681'u16, 0x0000'u16, 0x0007'u16],
                 d = [0'u32, 1, 0, 0, 0, 0, 0, 0]),
    1, 8'u32, srBase, "addi.l #7,d1 = 8")

  # addq.l #1,%d1 = 5281.
  expectD(runIns([0x5281'u16], d = [0'u32, 6, 0, 0, 0, 0, 0, 0]),
    1, 7'u32, srBase, "addq.l #1,d1 = 7")

  # addq.l #8,%d1 = 5081. The data field 000 means eight, not zero. A decoder
  # that reads the field literally adds nothing and this case is the only one
  # that separates the two.
  expectD(runIns([0x5081'u16], d = [0'u32, 6, 0, 0, 0, 0, 0, 0]),
    1, 14'u32, srBase, "addq.l #8,d1 reads the 000 data field as eight")

  # addq.l #1,%a1 = 5289. An ADDQ whose destination is an address register
  # does not touch the condition codes either.
  let dirty = srBase or ccrC or ccrV or ccrZ or ccrN or ccrX
  expectA(runIns([0x5289'u16], a = [0'u32, 0xFFFFFFFF'u32, 0, 0, 0, 0, 0, 0],
                 sr = dirty),
    1, 0'u32, dirty, "addq.l #1,a1 wraps and leaves the condition codes alone")

block:
  # addx.l %d0,%d1 = d380. It adds the X bit.
  expectD(runIns([0xD380'u16], d = [1'u32, 2, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrX or ccrZ),
    1, 4'u32, srBase, "addx.l adds X, and a non-zero result clears Z")

  # The sticky Z. ADDX clears Z on a non-zero result and leaves it alone
  # otherwise. It never sets Z. These two cases differ only in the incoming Z
  # and they must differ in the outgoing Z, which is what separates the sticky
  # rule from the ordinary "Z = result is zero" rule of ADD.
  expectD(runIns([0xD380'u16], d = zero8, sr = srBase or ccrZ),
    1, 0'u32, srBase or ccrZ, "addx.l zero result keeps an incoming Z set")
  expectD(runIns([0xD380'u16], d = zero8, sr = srBase),
    1, 0'u32, srBase, "addx.l zero result does NOT set a clear Z")

# ---------------------------------------------------------------------------
# SUB, SUBA, SUBI, SUBQ, SUBX.

block:
  # sub.l %d0,%d1 = 9280. d1 = d1 - d0.
  expectD(runIns([0x9280'u16], d = [1'u32, 2, 0, 0, 0, 0, 0, 0]),
    1, 1'u32, srBase, "sub.l d0,d1 = 1")

  # A borrow sets C and X. 1 - 2 = -1.
  expectD(runIns([0x9280'u16], d = [2'u32, 1, 0, 0, 0, 0, 0, 0]),
    1, 0xFFFFFFFF'u32, srBase or ccrC or ccrX or ccrN,
    "sub.l borrow sets C, X and N")

  # 0 - 0 = 0 with no borrow.
  expectD(runIns([0x9280'u16], d = zero8),
    1, 0'u32, srBase or ccrZ, "sub.l equal operands set Z alone")

  # Signed overflow: 0x80000000 - 1 crosses into the positive half.
  expectD(runIns([0x9280'u16], d = [1'u32, 0x80000000'u32, 0, 0, 0, 0, 0, 0]),
    1, 0x7FFFFFFF'u32, srBase or ccrV,
    "sub.l signed overflow sets V and leaves C clear")

block:
  # suba.l %d0,%a1 = 93c0, and it leaves the condition codes alone.
  let dirty = srBase or ccrC or ccrV or ccrZ or ccrN or ccrX
  expectA(runIns([0x93C0'u16], d = [4'u32, 0, 0, 0, 0, 0, 0, 0],
                 a = [0'u32, 10, 0, 0, 0, 0, 0, 0], sr = dirty),
    1, 6'u32, dirty, "suba.l leaves every condition code alone")

  # subi.l #7,%d1 = 0481 0000 0007.
  expectD(runIns([0x0481'u16, 0x0000'u16, 0x0007'u16],
                 d = [0'u32, 8, 0, 0, 0, 0, 0, 0]),
    1, 1'u32, srBase, "subi.l #7,d1 = 1")

  # subq.l #1,%d0 = 5380.
  expectD(runIns([0x5380'u16], d = [6'u32, 0, 0, 0, 0, 0, 0, 0]),
    0, 5'u32, srBase, "subq.l #1,d0 = 5")

  # subx.l %d0,%d1 = 9380: d1 - d0 - X.
  expectD(runIns([0x9380'u16], d = [1'u32, 3, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrX or ccrZ),
    1, 1'u32, srBase, "subx.l subtracts X too, and clears Z on a non-zero result")
  expectD(runIns([0x9380'u16], d = zero8, sr = srBase),
    1, 0'u32, srBase, "subx.l zero result does NOT set a clear Z")

# ---------------------------------------------------------------------------
# NEG, NEGX, CLR.

block:
  # neg.l %d0 = 4480. C is set whenever the result is non-zero, which is the
  # rule that separates NEG from a plain subtraction from zero.
  expectD(runIns([0x4480'u16], d = [5'u32, 0, 0, 0, 0, 0, 0, 0]),
    0, 0xFFFFFFFB'u32, srBase or ccrC or ccrX or ccrN,
    "neg.l 5 sets C, X and N")
  expectD(runIns([0x4480'u16], d = zero8),
    0, 0'u32, srBase or ccrZ, "neg.l 0 sets Z and leaves C clear")

  # The one signed overflow of NEG: the most negative value has no positive.
  expectD(runIns([0x4480'u16], d = [0x80000000'u32, 0, 0, 0, 0, 0, 0, 0]),
    0, 0x80000000'u32, srBase or ccrV or ccrN or ccrC or ccrX,
    "neg.l of the most negative value sets V")

  # negx.l %d0 = 4080: 0 - d0 - X, and Z is sticky exactly as ADDX's is.
  expectD(runIns([0x4080'u16], d = [5'u32, 0, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrX),
    0, 0xFFFFFFFA'u32, srBase or ccrC or ccrX or ccrN,
    "negx.l subtracts X as well")
  expectD(runIns([0x4080'u16], d = zero8, sr = srBase or ccrZ),
    0, 0'u32, srBase or ccrZ, "negx.l zero result keeps an incoming Z set")

block:
  # clr.l %d0 = 4280. N, Z, V and C take fixed values and X is untouched.
  expectD(runIns([0x4280'u16], d = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrX or ccrN or ccrV or ccrC),
    0, 0'u32, srBase or ccrX or ccrZ,
    "clr.l sets Z, clears N, V and C, and leaves X alone")

  # clr.w and clr.b exist on this part (the assembler accepts both) and each
  # clears its own width alone.
  expectD(runIns([0x4240'u16], d = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0]),
    0, 0x12340000'u32, srBase or ccrZ, "clr.w clears the low word alone")
  expectD(runIns([0x4200'u16], d = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0]),
    0, 0x12345600'u32, srBase or ccrZ, "clr.b clears the low byte alone")

  # clr.l -(%a0) = 42a0. The predecrement happens once.
  let o = runIns([0x42A0'u16], a = [0x204'u32, 0, 0, 0, 0, 0, 0, 0],
                 mem = @[(0x200'u32, 0xDEADBEEF'u32)])
  let got = (mem: mem32(0x200'u32), a0: o.a[0], sr: o.sr, fault: o.fault)
  let want = (mem: 0'u32, a0: 0x200'u32, sr: srBase or ccrZ, fault: false)
  check(got == want, "clr.l -(a0) decrements a0 once and clears the word",
    $got, $want)

# ---------------------------------------------------------------------------
# EXT and EXTB.

block:
  # ext.w %d0 = 4880: the low byte becomes the low word, and the upper half is
  # untouched. N comes from bit 15 of the 16-bit result, not from bit 31.
  expectD(runIns([0x4880'u16], d = [0x12345680'u32, 0, 0, 0, 0, 0, 0, 0]),
    0, 0x1234FF80'u32, srBase or ccrN, "ext.w extends the byte into the word")

  # ext.l %d0 = 48c0: the low word becomes the whole register.
  expectD(runIns([0x48C0'u16], d = [0x00008000'u32, 0, 0, 0, 0, 0, 0, 0]),
    0, 0xFFFF8000'u32, srBase or ccrN, "ext.l extends the word into the long")
  expectD(runIns([0x48C0'u16], d = [0x00007FFF'u32, 0, 0, 0, 0, 0, 0, 0]),
    0, 0x00007FFF'u32, srBase, "ext.l of a positive word leaves it positive")

  # extb.l %d0 = 49c0: the low byte becomes the whole register, which is a
  # different instruction from ext.l and a different result for the same input.
  expectD(runIns([0x49C0'u16], d = [0x12345680'u32, 0, 0, 0, 0, 0, 0, 0]),
    0, 0xFFFFFF80'u32, srBase or ccrN, "extb.l extends the byte into the long")

# ---------------------------------------------------------------------------
# MULU.L, MULS.L, DIVU.L, DIVS.L and REMx.L. All of these carry the 68020
# two-word encoding; the second word names the registers and selects signed
# or unsigned.

block:
  # mulu.l %d0,%d1 = 4c00 1000.
  expectD(runIns([0x4C00'u16, 0x1000'u16], d = [3'u32, 4, 0, 0, 0, 0, 0, 0]),
    1, 12'u32, srBase, "mulu.l 3 * 4 = 12")

  # V stays clear even when the 32 bits written are not the whole product.
  # 0x10000 squared is 0x1_0000_0000, whose low 32 bits are zero, so this case
  # really is indistinguishable from a multiply by zero on this part, and V is
  # always cleared by MULU on this family. The case enters with V set.
  expectD(runIns([0x4C00'u16, 0x1000'u16],
                 d = [0x10000'u32, 0x10000'u32, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrV),
    1, 0'u32, srBase or ccrZ,
    "mulu.l truncating to zero CLEARS V rather than reporting the loss")

  # N comes from bit 31 of the unsigned product, so MULU's N is not always
  # zero. 2 * 0x50000000 is 0xA0000000, which fits 32 bits unsigned - no part
  # of the product is lost - and its bit 31 is set. N is set if the result is
  # negative, the result being the 32 bits loaded into the register.
  expectD(runIns([0x4C00'u16, 0x1000'u16],
                 d = [0x2'u32, 0x50000000'u32, 0, 0, 0, 0, 0, 0]),
    1, 0xA0000000'u32, srBase or ccrN,
    "mulu.l sets N from bit 31 of the unsigned product")

  # muls.l %d0,%d1 = 4c00 1800. The signed flag is bit 11 of the second word.
  # -1 * 3 is -3 unsigned-wrong and signed-right.
  expectD(runIns([0x4C00'u16, 0x1800'u16],
                 d = [0xFFFFFFFF'u32, 3, 0, 0, 0, 0, 0, 0]),
    1, 0xFFFFFFFD'u32, srBase or ccrN, "muls.l -1 * 3 = -3")

  # MULS clears V on the same terms. -0x10000 * 0x10000 is -0x1_0000_0000,
  # which no signed 32-bit result holds, and V is still clear: V is always
  # cleared by MULS on this family. The case enters with V set.
  expectD(runIns([0x4C00'u16, 0x1800'u16],
                 d = [0xFFFF0000'u32, 0x10000'u32, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrV),
    1, 0'u32, srBase or ccrZ, "muls.l losing the whole product CLEARS V")

  # Nothing separates MULS.L from MULU.L. The low 32 bits of a 32x32 product
  # do not depend on how the sign bits are read, and every flag comes from
  # those 32 bits, so the signed bit is unobservable in this form. Both enter
  # with V set.
  expectD(runIns([0x4C00'u16, 0x1800'u16],
                 d = [0xFFFFFFFF'u32, 0xFFFFFFFF'u32, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrV),
    1, 1'u32, srBase, "muls.l -1 * -1 = 1 with V clear")
  expectD(runIns([0x4C00'u16, 0x1000'u16],
                 d = [0xFFFFFFFF'u32, 0xFFFFFFFF'u32, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrV),
    1, 1'u32, srBase,
    "mulu.l of the same two words gives the same result and the same V")

block:
  # divu.l %d0,%d1 = 4c40 1001. The second word names Dq in bits 15..12 and
  # Dr in bits 2..0; equal registers select the quotient-only form.
  expectD(runIns([0x4C40'u16, 0x1001'u16], d = [3'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 5'u32, srBase, "divu.l 17 / 3 = 5")

  # divs.l %d0,%d1 = 4c40 1801. The signed quotient truncates toward zero:
  # 17 / -3 is -5 and not -6. A core that used a flooring division gives -6.
  expectD(runIns([0x4C40'u16, 0x1801'u16],
                 d = [0xFFFFFFFD'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 0xFFFFFFFB'u32, srBase or ccrN,
    "divs.l 17 / -3 truncates toward zero to -5")

  # The same two words read as unsigned: 17 / 0xFFFFFFFD is 0. Same operands,
  # opposite result, so this separates the signed bit from a coincidence.
  expectD(runIns([0x4C40'u16, 0x1001'u16],
                 d = [0xFFFFFFFD'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 0'u32, srBase or ccrZ, "divu.l of the same two words is 0")

block:
  # remu.l %d0,%d2:%d1 = 4c40 1002. Dq is d1 and Dr is d2. ColdFire's REMx.L
  # produces the remainder only: d2 takes the remainder and d1 is unchanged.
  let o = runIns([0x4C40'u16, 0x1002'u16], d = [5'u32, 17, 0, 0, 0, 0, 0, 0])
  let got = (d1: o.d[1], d2: o.d[2], sr: o.sr, fault: o.fault)
  let want = (d1: 17'u32, d2: 2'u32, sr: srBase, fault: false)
  check(got == want, "remu.l writes the remainder to Dr and leaves Dq alone",
    $got, $want)

  # rems.l %d0,%d2:%d1 = 4c40 1802. The signed remainder takes the sign of the
  # dividend: -17 rem 5 is -2, not +3.
  let os = runIns([0x4C40'u16, 0x1802'u16],
                  d = [5'u32, 0xFFFFFFEF'u32, 0, 0, 0, 0, 0, 0])
  let gotS = (d1: os.d[1], d2: os.d[2], sr: os.sr, fault: os.fault)
  let wantS = (d1: 0xFFFFFFEF'u32, d2: 0xFFFFFFFE'u32,
               sr: srBase or ccrN, fault: false)
  check(gotS == wantS, "rems.l -17 rem 5 = -2, signed by the dividend",
    $gotS, $wantS)

  # N and Z come from the quotient, not from the remainder the instruction
  # writes. N is set if the quotient is negative and Z if it is zero, while the
  # register still takes the remainder, so the two halves of each case below
  # come from different numbers.

  # Z separates them: 20 / 5 is a quotient of 4 with a remainder of zero. The
  # remainder rule sets Z, the quotient rule clears it. d2 takes the remainder
  # 0 either way, so only the status word tells the two apart.
  let oz = runIns([0x4C40'u16, 0x1002'u16],
                  d = [5'u32, 20'u32, 0, 0, 0, 0, 0, 0])
  let gotZ = (d1: oz.d[1], d2: oz.d[2], sr: oz.sr, fault: oz.fault)
  let wantZ = (d1: 20'u32, d2: 0'u32, sr: srBase, fault: false)
  check(gotZ == wantZ,
    "remu.l 20 / 5 leaves Z CLEAR: the quotient is 4 though the remainder is 0",
    $gotZ, $wantZ)

  # N separates them: 17 / -5 is a quotient of -3 with a remainder of +2, the
  # remainder taking the sign of the dividend. The remainder rule clears N, the
  # quotient rule sets it.
  let on = runIns([0x4C40'u16, 0x1802'u16],
                  d = [0xFFFFFFFB'u32, 17'u32, 0, 0, 0, 0, 0, 0])
  let gotN = (d1: on.d[1], d2: on.d[2], sr: on.sr, fault: on.fault)
  let wantN = (d1: 17'u32, d2: 2'u32, sr: srBase or ccrN, fault: false)
  check(gotN == wantN,
    "rems.l 17 / -5 SETS N: the quotient is -3 though the remainder is +2",
    $gotN, $wantN)

block:
  # The one signed division overflow: the most negative value divided by -1
  # has no positive quotient. V is set and the operands are unchanged.
  expectD(runIns([0x4C40'u16, 0x1801'u16],
                 d = [0xFFFFFFFF'u32, 0x80000000'u32, 0, 0, 0, 0, 0, 0]),
    1, 0x80000000'u32, srBase or ccrV,
    "divs.l of the most negative value by -1 sets V and writes nothing")

  # An overflow clears N and Z rather than leaving them as it found them.
  # N and Z are cleared if overflow is detected, and otherwise take the
  # quotient's sign and zero-ness.
  #
  # This case enters with N, Z and C set and X set. It pins all five bits at
  # once: V set, N cleared, Z cleared, C cleared ("C Always cleared" on both
  # folios), and X carried through unchanged ("X Not affected").
  expectD(runIns([0x4C40'u16, 0x1801'u16],
                 d = [0xFFFFFFFF'u32, 0x80000000'u32, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrN or ccrZ or ccrC or ccrX),
    1, 0x80000000'u32, srBase or ccrV or ccrX,
    "divs.l overflow CLEARS N and Z, clears C, sets V and leaves X alone")

  # A division by zero is a trap. There is no exception model yet, so the core
  # halts with `fault` rather than divide. It must not return a quotient of
  # any kind.
  expectTrapD(runIns([0x4C40'u16, 0x1001'u16],
                     d = [0'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 17'u32, "divu.l by zero traps")
  expectTrapD(runIns([0x4C40'u16, 0x1801'u16],
                     d = [0'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 17'u32, "divs.l by zero traps")

# ---------------------------------------------------------------------------
# MULU.W, MULS.W, DIVU.W and DIVS.W - the single-word forms.
#
# This part has them, and both oracles say so:
#
#   - `m68k-elf-as -mcpu=5307` (GNU Binutils 2.47.20260726) assembles
#     `mulu.w %d1,%d0` to `c0c1`, `muls.w %d1,%d0` to `c1c1`,
#     `divu.w %d1,%d0` to `80c1` and `divs.w %d1,%d0` to `81c1`. It rejects
#     the two divides at `-mcpu=5206` and `-mcpu=5202`, which is the part
#     without a divide unit and not the absence of a word form.
#   - The word forms are `16 x 16 -> 32` for MULS and MULU and
#     `32-bit Dx / 16-bit <ea>y -> (16r:16q) in Dx` for DIVS and DIVU, and each
#     carries an `Instruction Format: (Word)` diagram that is the encoding
#     above.
#
# The word form carries no extension word. The long form is the 68020 two-word
# encoding whose second word names the registers and selects signedness; the
# word form names Dx in bits 11..9 of the opcode and selects signedness in
# bits 8..6.

block:
  # (a) The decoder. Asserted directly rather than inferred from a mask.
  #
  # The tuple carries the size, which is what separates the word form from the
  # long one and what the executor branches on, and `destReg`, which is where
  # the word form's Dx comes from.
  for (word, wantOp, name) in [
      (0xC0C1'u16, opMulu, "mulu.w %d1,%d0"),
      (0xC1C1'u16, opMuls, "muls.w %d1,%d0"),
      (0x80C1'u16, opDivu, "divu.w %d1,%d0"),
      (0x81C1'u16, opDivs, "divs.w %d1,%d0")]:
    let dec = decodeWord(word)
    let got = (op: dec.op, size: dec.size, destReg: dec.destReg)
    let want = (op: wantOp, size: 2'u8, destReg: 0'u8)
    check(got == want,
      "decodes " & name & " (0x" & word.toHex(4) & ") as a WORD form", $got,
      $want)

block:
  # (b) MULU.W. `mulu.w %d0,%d1` is `c2c0`.
  expectD(runIns([0xC2C0'u16], d = [3'u32, 4, 0, 0, 0, 0, 0, 0]),
    1, 12'u32, srBase, "mulu.w 3 * 4 = 12")

  # The upper word of either operand is ignored on input: a register operand
  # is the low-order word. Both registers carry a distinctive upper half here.
  expectD(runIns([0xC2C0'u16],
                 d = [0xDEAD0003'u32, 0xBEEF0004'u32, 0, 0, 0, 0, 0, 0]),
    1, 12'u32, srBase,
    "mulu.w IGNORES the upper word of the source AND of the destination")

  # All 32 bits of the product are saved.
  expectD(runIns([0xC2C0'u16], d = [0xFFFF'u32, 3, 0, 0, 0, 0, 0, 0]),
    1, 0x0002FFFD'u32, srBase,
    "mulu.w 0xFFFF * 3 = 0x2FFFD - all 32 bits of the product are written")

  # (c) MULS.W. `muls.w %d0,%d1` is `c3c0`. The same two words, signed: 0xFFFF
  # is -1 as a word, so the product is -3.
  #
  # The signed bit is observable here and it is not in the long form. The
  # block above records why MULS.L and MULU.L are indistinguishable on this
  # part - the low 32 bits of a 32x32 product do not depend on how the sign
  # bits are read, and V is always cleared. A 16x16 product is kept whole in
  # 32 bits, so the sign extension of the two word operands survives into the
  # result and this pair separates the two opcodes on the result itself.
  expectD(runIns([0xC3C0'u16], d = [0xFFFF'u32, 3, 0, 0, 0, 0, 0, 0]),
    1, 0xFFFFFFFD'u32, srBase or ccrN,
    "muls.w -1 * 3 = -3, sign-extending both word operands")

  expectD(runIns([0xC3C0'u16],
                 d = [0xDEADFFFF'u32, 0xBEEF0003'u32, 0, 0, 0, 0, 0, 0]),
    1, 0xFFFFFFFD'u32, srBase or ccrN,
    "muls.w IGNORES the upper word of the source AND of the destination")

  # V is always cleared on this part, and the word form inherits that from the
  # same condition-code table the long form reads, and there is no second
  # table for the word form. The case enters with V set.
  expectD(runIns([0xC2C0'u16], d = [0'u32, 5, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrV),
    1, 0'u32, srBase or ccrZ, "mulu.w by zero CLEARS V and sets Z")
  expectD(runIns([0xC3C0'u16], d = [0'u32, 5, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrV),
    1, 0'u32, srBase or ccrZ, "muls.w by zero CLEARS V and sets Z")

block:
  # (d) DIVU.W. `divu.w %d0,%d1` is `82c0`. The result is one longword holding
  # two halves: the 16-bit quotient is in the lower word and the 16-bit
  # remainder is in the upper word of the destination.
  expectD(runIns([0x82C0'u16], d = [3'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 0x00020005'u32, srBase,
    "divu.w 17 / 3 writes quotient 5 low and remainder 2 high")

  # The divisor is a word. The same operands read as a longword divisor give
  # 17 / 0x0000FFFD = 0, so a core reading four bytes writes 0x00110000 and a
  # core reading two writes the quotient of 17 / 65533, which is also 0 - the
  # two agree, which is why the separating case is the zero-divisor one below
  # and not this one. This case pins the layout when the quotient is zero:
  # the whole dividend survives as the remainder.
  expectD(runIns([0x82C0'u16], d = [0xFFFD'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 0x00110000'u32, srBase or ccrZ,
    "divu.w 17 / 65533 = 0 remainder 17, and Z comes from the QUOTIENT")

  # (e) DIVS.W. `divs.w %d0,%d1` is `83c0`. 0xFFFD is -3 as a word, and the
  # quotient truncates toward zero: 17 / -3 is -5 and not -6.
  expectD(runIns([0x83C0'u16], d = [0xFFFD'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 0x0002FFFB'u32, srBase or ccrN,
    "divs.w 17 / -3 = -5 remainder +2, truncating toward zero")

  # The remainder takes the dividend's sign.
  expectD(runIns([0x83C0'u16],
                 d = [3'u32, 0xFFFFFFEF'u32, 0, 0, 0, 0, 0, 0]),
    1, 0xFFFEFFFB'u32, srBase or ccrN,
    "divs.w -17 / 3 = -5 remainder -2: the remainder takes the DIVIDEND's sign")

  # N comes from the quotient and not from the longword written. Here the
  # remainder's high word has bit 15 set while the quotient is positive, so a
  # core taking N from bit 31 of the written longword sets N and fails.
  expectD(runIns([0x83C0'u16],
                 d = [0xFFFB'u32, 0xFFFFFFEF'u32, 0, 0, 0, 0, 0, 0]),
    1, 0xFFFE0003'u32, srBase,
    "divs.w -17 / -5 = +3 remainder -2: N comes from the QUOTIENT, not bit 31")

block:
  # (f) The word-form overflow. An overflow occurs if the quotient is larger
  # than a 16-bit (.W) or 32-bit (.L) integer, and the destination register is
  # then unaffected.
  #
  # Each case enters with N, Z and C set and X set, so it pins all five bits:
  # V set, N and Z cleared, C cleared and X carried through.
  expectD(runIns([0x82C0'u16], d = [1'u32, 0x00100000'u32, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrN or ccrZ or ccrC or ccrX),
    1, 0x00100000'u32, srBase or ccrV or ccrX,
    "divu.w whose quotient exceeds 16 bits sets V and writes nothing")

  expectD(runIns([0x83C0'u16], d = [1'u32, 0x00010000'u32, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrN or ccrZ or ccrC or ccrX),
    1, 0x00010000'u32, srBase or ccrV or ccrX,
    "divs.w whose quotient exceeds 15 bits and a sign sets V and writes nothing")

  # The positive boundary is not ambiguous. +32767 is the largest 16-bit
  # signed integer, so a quotient of +32767 must not overflow and one of
  # +32768 must. 65534 / 2 is 32767 and 65536 / 2 is 32768.
  expectD(runIns([0x83C0'u16], d = [2'u32, 0x0000FFFE'u32, 0, 0, 0, 0, 0, 0]),
    1, 0x00007FFF'u32, srBase,
    "divs.w whose quotient is exactly +32767 does NOT overflow")
  expectD(runIns([0x83C0'u16], d = [2'u32, 0x00010000'u32, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrX),
    1, 0x00010000'u32, srBase or ccrV or ccrX,
    "divs.w whose quotient is exactly +32768 DOES overflow")

  # The negative boundary is the one inference in this whole path, and
  # `alu.nim` marks it at the line that decides it. -32768 is a 16-bit signed
  # integer, so under the folios' wording - "larger than a 16-bit (.W) signed
  # integer" - it does not overflow. -65536 / 2 is -32768 and -65538 / 2 is
  # -32769, which is one step outside and overflows under every reading.
  expectD(runIns([0x83C0'u16], d = [2'u32, 0xFFFF0000'u32, 0, 0, 0, 0, 0, 0]),
    1, 0x00008000'u32, srBase or ccrN,
    "divs.w whose quotient is exactly -32768 does NOT overflow [INFERENCE]")
  expectD(runIns([0x83C0'u16], d = [2'u32, 0xFFFEFFFE'u32, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrX),
    1, 0xFFFEFFFE'u32, srBase or ccrV or ccrX,
    "divs.w whose quotient is -32769 DOES overflow")

block:
  # (g) Division by zero is a trap. An attempt to divide by zero results in a
  # divide-by-zero exception and no registers are affected; it takes vector 5
  # at offset 0x014, of class Fault. There is no exception model yet, so the
  # core halts with `fault`, which is the channel the long form already uses.
  expectTrapD(runIns([0x82C0'u16], d = [0'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 17'u32, "divu.w by zero traps")
  expectTrapD(runIns([0x83C0'u16], d = [0'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 17'u32, "divs.w by zero traps")

  # The divisor is read as a word, and this is the case that says so. The low
  # word of the source is zero and its upper word is not, so a core reading
  # four bytes divides by 0x00010000 and returns a quotient of 0 instead of
  # trapping.
  expectTrapD(runIns([0x82C0'u16],
                     d = [0x00010000'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 17'u32, "divu.w by a source whose LOW WORD is zero traps")
  expectTrapD(runIns([0x83C0'u16],
                     d = [0x00010000'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 17'u32, "divs.w by a source whose LOW WORD is zero traps")

block:
  # (h) The word form's operand class is wider than the long form's, and these
  # cases execute the modes that separate them. The word operand table
  # carries `(xxx).W`, `(xxx).L`, `#<data>`, `(d16,PC)` and `(d8,PC,Xi)` where
  # the longword table prints a dash for every one.
  # `m68k-elf-as -mcpu=5307` agrees on every mode of every form.
  #
  # `mulu.w #5,%d1` is `c2fc 0005`.
  expectD(runIns([0xC2FC'u16, 0x0005'u16], d = [0'u32, 4, 0, 0, 0, 0, 0, 0]),
    1, 20'u32, srBase, "mulu.w takes an IMMEDIATE source")
  # `divs.w #3,%d1` is `83fc 0003`.
  expectD(runIns([0x83FC'u16, 0x0003'u16], d = [0'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 0x00020005'u32, srBase, "divs.w takes an IMMEDIATE source")
  # `mulu.w (4,%pc),%d1` is `c2fa 0004`. The PC-relative base is the address
  # of the displacement word - `machine.nim` says so at `fetchExt` - which is
  # 0x102 here, so the operand word is at 0x106.
  expectD(runIns([0xC2FA'u16, 0x0004'u16], d = [0'u32, 4, 0, 0, 0, 0, 0, 0],
                 mem = @[(0x104'u32, 0x00000007'u32)]),
    1, 28'u32, srBase, "mulu.w takes a PC-RELATIVE source")
  # `mulu.w 0x200.w,%d1` is `c2f8 0200`.
  expectD(runIns([0xC2F8'u16, 0x0200'u16], d = [0'u32, 4, 0, 0, 0, 0, 0, 0],
                 mem = @[(0x200'u32, 0x00060000'u32)]),
    1, 24'u32, srBase, "mulu.w takes an ABSOLUTE SHORT source")

  # A memory source is read two bytes wide, and the divide needs its own case
  # for that. The `and 0xFFFF` narrowing inside each executor hides the read
  # width for a data-register source - `eaRead` hands back the whole register
  # at either size - so only a memory operand separates a two-byte read from a
  # four-byte one. `divu.w 0x200.w,%d1` is `82f8 0200`; the seed puts the
  # divisor in the high half of the longword at 0x200, so a four-byte read
  # yields 0x00030000, narrows to zero and traps instead of dividing.
  expectD(runIns([0x82F8'u16, 0x0200'u16], d = [0'u32, 17, 0, 0, 0, 0, 0, 0],
                 mem = @[(0x200'u32, 0x00030000'u32)]),
    1, 0x00020005'u32, srBase, "divu.w takes an ABSOLUTE SHORT source")
  # `divs.w (%a0),%d1` is `83d0` - an indirect source, the commonest memory
  # mode.
  expectD(runIns([0x83D0'u16], d = [0'u32, 17, 0, 0, 0, 0, 0, 0],
                 a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0],
                 mem = @[(0x200'u32, 0xFFFD0000'u32)]),
    1, 0x0002FFFB'u32, srBase or ccrN, "divs.w takes an INDIRECT source")

  # And an address register is outside both tables. `mulu.w %a0,%d1` is
  # `c2c8`; the `Ay` row is dashed on every one of the tables and the
  # assembler rejects it at every size.
  let o = runIns([0xC2C8'u16], d = [0'u32, 4, 0, 0, 0, 0, 0, 0],
                 a = [7'u32, 0, 0, 0, 0, 0, 0, 0])
  let got = (d1: o.d[1], fault: o.fault, halted: o.halted, cycles: o.cycles)
  let want = (d1: 4'u32, fault: true, halted: true, cycles: 0'u32)
  check(got == want, "mulu.w from an address register traps", $got, $want)

block:
  # (i) The address-register sources, where the program counter is the
  # only witness. `(%a0)`, `(%a0)+` and `-(%a0)` read no word from the
  # instruction stream, so an executor that fetched an extension word here -
  # the word form has none, and `src/mcf5307/decode.nim` names the hazard -
  # writes the same destination register, the same status word and the same
  # address register, and leaves the pc two bytes high. The cases above whose
  # source word comes from the instruction stream catch such a fetch on the
  # operand value; `divs.w takes an indirect source` has no value to move and
  # stays green.
  #
  # The address register is not a second witness. `eaAddr` increments and
  # decrements it from the register alone, so an over-fetch does not move it,
  # and a case asserting the operand, the status word and a0 but not the pc
  # stays green under one.
  #
  # One mode per executor is what this pins, and that is the limit. The word
  # multiply and the word divide are separate procedures, so a fetch
  # conditional on both a procedure and one addressing mode - a divide that
  # over-fetched for `(%a0)` only - is not covered here.
  # `mulu_w_reg_source_takes_no_extension_word` in the corpus pins the same
  # rule for a data-register source.
  proc expectPc(o: Outcome; d1: uint32; a0: uint32; sr: uint32; label: string) =
    let got = (d1: o.d[1], a0: o.a[0], pc: o.pc, sr: o.sr, fault: o.fault)
    let want = (d1: d1, a0: a0, pc: execBase + 2'u32, sr: sr, fault: false)
    check(got == want, label, $got, $want)

  # `mulu.w (%a0),%d1` is `c2d0`. 7 * 6 = 42, and a0 must not move.
  expectPc(runIns([0xC2D0'u16], d = [0'u32, 6, 0, 0, 0, 0, 0, 0],
                  a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0],
                  mem = @[(0x200'u32, 0x00070000'u32)]),
    42'u32, 0x200'u32, srBase,
    "mulu.w (a0),d1 consumes no extension word")

  # `divu.w (%a0)+,%d1` is `82d8`. 17 / 3 is 5 remainder 2, and the source is
  # a word, so a0 advances by 2 and not by 4.
  expectPc(runIns([0x82D8'u16], d = [0'u32, 17, 0, 0, 0, 0, 0, 0],
                  a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0],
                  mem = @[(0x200'u32, 0x00030000'u32)]),
    0x00020005'u32, 0x202'u32, srBase,
    "divu.w (a0)+,d1 consumes no extension word")

  # `muls.w -(%a0),%d1` is `c3e0`. a0 enters at 0x202 and the decrement of 2
  # puts the operand at 0x200: -3 * 3 = -9.
  expectPc(runIns([0xC3E0'u16], d = [0'u32, 3, 0, 0, 0, 0, 0, 0],
                  a = [0x202'u32, 0, 0, 0, 0, 0, 0, 0],
                  mem = @[(0x200'u32, 0xFFFD0000'u32)]),
    0xFFFFFFF7'u32, 0x200'u32, srBase or ccrN,
    "muls.w -(a0),d1 consumes no extension word")

# ---------------------------------------------------------------------------
# The encodings this part does not have. Every one below was offered to
# `m68k-elf-as -mcpu=5307` and rejected. A permissive core executes them and
# hides a real firmware fault.

block:
  # Byte and word arithmetic. The size field is the only difference from the
  # long form directly above each line, so these also prove the size field is
  # read at all.
  let two = [1'u32, 2'u32, 0, 0, 0, 0, 0, 0]
  expectTrapD(runIns([0xD240'u16], d = two), 1, 2'u32, "add.w traps")
  expectTrapD(runIns([0xD200'u16], d = two), 1, 2'u32, "add.b traps")
  expectTrapD(runIns([0x9240'u16], d = two), 1, 2'u32, "sub.w traps")
  expectTrapD(runIns([0x9200'u16], d = two), 1, 2'u32, "sub.b traps")
  expectTrapD(runIns([0x0641'u16, 0x0007'u16], d = two), 1, 2'u32,
    "addi.w traps")
  expectTrapD(runIns([0x0601'u16, 0x0007'u16], d = two), 1, 2'u32,
    "addi.b traps")
  expectTrapD(runIns([0x5241'u16], d = two), 1, 2'u32, "addq.w traps")
  expectTrapD(runIns([0x5201'u16], d = two), 1, 2'u32, "addq.b traps")
  expectTrapD(runIns([0x4440'u16], d = two), 0, 1'u32, "neg.w traps")
  expectTrapD(runIns([0x4400'u16], d = two), 0, 1'u32, "neg.b traps")
  expectTrapD(runIns([0x4040'u16], d = two), 0, 1'u32, "negx.w traps")
  # addx.w %d0,%d1 - the ADDX slot is bits 5..4 = 00 inside the size-bearing
  # opmode, so a word ADDX must trap without being mistaken for add.w to <ea>.
  expectTrapD(runIns([0xD340'u16], d = two), 1, 2'u32, "addx.w traps")
  # adda.w %d0,%a1: opmode 011 is the word ADDA of the 68000 and this part has
  # only the long one.
  let o = runIns([0xD2C0'u16], d = two, a = [0'u32, 9, 0, 0, 0, 0, 0, 0])
  let got = (a1: o.a[1], fault: o.fault, cycles: o.cycles)
  let want = (a1: 9'u32, fault: true, cycles: 0'u32)
  check(got == want, "adda.w traps", $got, $want)

block:
  # The operand classes this part narrows. Each of these is a legal 68000
  # encoding that `-mcpu=5307` rejects.
  let two = [1'u32, 2'u32, 0, 0, 0, 0, 0, 0]
  # addi.l #7,(%a0) - ADDI takes a data register destination only.
  expectTrapD(runIns([0x0690'u16, 0x0000'u16, 0x0007'u16], d = two,
                     a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0],
                     mem = @[(0x200'u32, 1'u32)]), 1, 2'u32,
    "addi.l to memory traps")
  # neg.l (%a0) - NEG takes a data register destination only.
  expectTrapD(runIns([0x4490'u16], d = two,
                     a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0],
                     mem = @[(0x200'u32, 1'u32)]), 0, 1'u32,
    "neg.l to memory traps")
  # addq.l #1,(4,%pc) - a PC-relative destination is not alterable.
  expectTrapD(runIns([0x52BA'u16, 0x0004'u16], d = two), 1, 2'u32,
    "addq.l to a PC-relative destination traps")
  # clr.l %a0 - an address register is not a data-alterable destination.
  let oc = runIns([0x4288'u16], a = [0x1234'u32, 0, 0, 0, 0, 0, 0, 0])
  let gotc = (a0: oc.a[0], fault: oc.fault, cycles: oc.cycles)
  let wantc = (a0: 0x1234'u32, fault: true, cycles: 0'u32)
  check(gotc == wantc, "clr.l to an address register traps", $gotc, $wantc)
  # mulu.l (4,%pc),%d1 - the multiply source admits no PC-relative mode.
  expectTrapD(runIns([0x4C3A'u16, 0x1000'u16, 0x0004'u16], d = two), 1, 2'u32,
    "mulu.l from a PC-relative source traps")
  # The long form is narrower than data alterable, and these cases are the
  # difference. The longword operand table dashes `(xxx).W`, `(xxx).L` and
  # `(d8,Ay,Xi)`, keeping only `Dy`, `(Ay)`, `(Ay)+`, `-(Ay)` and `(d16,Ay)`
  # for all four operations. `m68k-elf-as -mcpu=5307` rejects
  # `mulu.l 0x1234.w,%d1`, `mulu.l 0x12345678,%d1` and
  # `mulu.l (4,%a0,%d2),%d1` and accepts the kept modes.
  #
  # The word form admits these, which is why one mask cannot serve
  # both sizes and `eaLegalityFor` takes the size.
  #
  # mulu.l 0x200.w,%d1 = 4c38 1000 0200.
  expectTrapD(runIns([0x4C38'u16, 0x1000'u16, 0x0200'u16], d = two), 1, 2'u32,
    "mulu.l from an ABSOLUTE SHORT source traps")
  # mulu.l 0x00000200,%d1 = 4c39 1000 0000 0200.
  expectTrapD(runIns([0x4C39'u16, 0x1000'u16, 0x0000'u16, 0x0200'u16],
                     d = two), 1, 2'u32,
    "mulu.l from an ABSOLUTE LONG source traps")
  # mulu.l (4,%a0,%d2),%d1 = 4c30 1000 2004.
  expectTrapD(runIns([0x4C30'u16, 0x1000'u16, 0x2004'u16], d = two,
                     a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0]), 1, 2'u32,
    "mulu.l from an INDEXED source traps")
  # divu.l 0x200.w,%d1 = 4c78 1001 0200 - the divide narrows identically.
  #
  # The divisor at 0x200 is non-zero and that is load-bearing. `runIns` zeroes
  # the board, so without the `mem` seed this case traps on a divide by zero
  # whatever the mask says - a green that would say nothing about the operand
  # class it names.
  expectTrapD(runIns([0x4C78'u16, 0x1001'u16, 0x0200'u16], d = two,
                     mem = @[(0x200'u32, 4'u32)]), 1, 2'u32,
    "divu.l from an ABSOLUTE SHORT source traps")
  # The 64-bit product form: bit 10 of the second word. It is a 68020
  # instruction and this part has only the 32-bit form.
  expectTrapD(runIns([0x4C00'u16, 0x1400'u16], d = two), 1, 2'u32,
    "the 64-bit mulu.l form traps")
  # addx.l -(%a0),-(%a1): the memory form of ADDX, which this part drops.
  expectTrapD(runIns([0xD388'u16], d = two), 1, 2'u32,
    "the memory form of addx.l traps")

# ---------------------------------------------------------------------------
# The declared operand masks, read directly.
#
# These are not redundant with the trap cases above. Widening the ADDQ mask to
# data addressing and re-running every case above changes nothing:
# `addq.l #1,(4,%pc)` still traps, because `eaResolve` in `mcf5307/machine`
# resolves no operand it cannot write and rejects the same mode-7
# sub-variants a second time. Defence in depth is correct and it also makes
# the two defences indistinguishable from the outside.
#
# `eaIsLegalFor` is a declaration that other code reads, so it has to be right
# on its own terms and not only right where a second check happens to cover
# it. These assertions read it directly. Each mask carries a negative case and
# a positive control, because a mask that rejected everything would report the
# negative case as a pass.

proc checkMaskImpl(site: int; got: bool; want: bool; label: string) =
  checkImpl(site, got == want, label, $got, $want)


template checkMask(got: bool; want: bool; label: string) =
  ## The call site is recorded twice - once at compile time into
  ## `declaredSites` by the `static` below, and once at run time into
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkMaskImpl(site, got, want, label)
block:
  # ADDQ and SUBQ: alterable. An address register is in, and a PC-relative or
  # an immediate destination is out.
  checkMask(eaIsLegalFor(opAddq, decodeEa(0x00'u16)), true,
    "the ADDQ mask admits Dn")
  checkMask(eaIsLegalFor(opAddq, decodeEa(0x09'u16)), true,
    "the ADDQ mask admits An")
  checkMask(eaIsLegalFor(opAddq, decodeEa(0x3A'u16)), false,
    "the ADDQ mask rejects (d16,PC)")
  checkMask(eaIsLegalFor(opAddq, decodeEa(0x3C'u16)), false,
    "the ADDQ mask rejects an immediate")
  checkMask(eaIsLegalFor(opSubq, decodeEa(0x3A'u16)), false,
    "the SUBQ mask rejects (d16,PC)")

  # ADDI, SUBI, NEG, NEGX, EXT, EXTB, ADDX and SUBX: a data register and
  # nothing else.
  for (opx, name) in [(opAddi, "ADDI"), (opSubi, "SUBI"), (opNeg, "NEG"),
                      (opNegx, "NEGX"), (opExt, "EXT"), (opExtb, "EXTB"),
                      (opAddx, "ADDX"), (opSubx, "SUBX")]:
    checkMask(eaIsLegalFor(opx, decodeEa(0x00'u16)), true,
      "the " & name & " mask admits Dn")
    checkMask(eaIsLegalFor(opx, decodeEa(0x10'u16)), false,
      "the " & name & " mask rejects (An)")
    checkMask(eaIsLegalFor(opx, decodeEa(0x08'u16)), false,
      "the " & name & " mask rejects An")

  # CLR and the multiply and divide source: data alterable. An address
  # register, a PC-relative operand and an immediate are all out.
  for (opx, name) in [(opClr, "CLR"), (opMulu, "MULU"), (opDivu, "DIVU")]:
    checkMask(eaIsLegalFor(opx, decodeEa(0x00'u16)), true,
      "the " & name & " mask admits Dn")
    checkMask(eaIsLegalFor(opx, decodeEa(0x10'u16)), true,
      "the " & name & " mask admits (An)")
    checkMask(eaIsLegalFor(opx, decodeEa(0x08'u16)), false,
      "the " & name & " mask rejects An")
    checkMask(eaIsLegalFor(opx, decodeEa(0x3A'u16)), false,
      "the " & name & " mask rejects (d16,PC)")
    checkMask(eaIsLegalFor(opx, decodeEa(0x3C'u16)), false,
      "the " & name & " mask rejects an immediate")

  # The `<ea>,Dn` direction of ADD and SUB reads data addressing, which does
  # admit an immediate and a PC-relative source.
  checkMask(eaIsLegalFor(opAdd, decodeEa(0x3C'u16)), true,
    "the ADD source mask admits an immediate")
  checkMask(eaIsLegalFor(opAdd, decodeEa(0x3D'u16)), false,
    "the ADD source mask rejects the reserved mode-7 encoding")

  # The `Dn,<ea>` direction writes memory. A register destination is the ADDX
  # and ADDA slot, never a memory destination.
  checkMask(isEaLegal(eaMemoryAlterable, decodeEa(0x10'u16)), true,
    "the memory-alterable mask admits (An)")
  checkMask(isEaLegal(eaMemoryAlterable, decodeEa(0x00'u16)), false,
    "the memory-alterable mask rejects Dn")
  checkMask(isEaLegal(eaMemoryAlterable, decodeEa(0x08'u16)), false,
    "the memory-alterable mask rejects An")
  checkMask(isEaLegal(eaMemoryAlterable, decodeEa(0x3A'u16)), false,
    "the memory-alterable mask rejects (d16,PC)")

# The registry lines. They are data and not a verdict: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_alu", declaredCaseSites)
echo caseSiteLine("executed", "t_alu", executedSites)
echo caseSiteLine("off-green-path", "t_alu", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_alu: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_alu: ", passCount, " cases passed"
