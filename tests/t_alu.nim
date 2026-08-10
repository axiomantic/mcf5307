## `t_alu` - the integer-arithmetic instruction group. Task CPU-8 creates this
## file. Design section 6.1.
##
## WHY THIS FILE EXISTS BESIDE THE CONFORMANCE CORPUS. The CPU-8 Check: line is
## `mcf5307_conformance_alu`, and that corpus asserted REGISTER RESULTS ALONE.
## Measured on the committed corpus at CPU-8's start: not one case in any of
## the four groups named `sr` in its `expected` state, and the runner asserts
## only the registers a case names. THE CONDITION CODES WERE THEREFORE
## INVISIBLE TO THE CORPUS. A core that computed every arithmetic result
## correctly and set no flag at all reported 9 of 9.
##
## THE CORPUS NOW NAMES `sr` AND THIS FILE STAYS. `conformance/generate.py`
## gives every `move` and `alu` case a dirty incoming `sr` and an exact
## expected word, and five mutations that previously left the group green -
## ADD's carry-out, ADD's signed overflow, SUB's and NEG's borrow, the
## multiply's V, and the ADDQ 000 data field - are each caught there now. This
## file is deliberately NOT reduced to match: it carries the sticky-Z rule of
## ADDX/SUBX/NEGX, the trap cases for encodings this part does not have, and
## the direct reads of `eaIsLegalFor`, none of which the corpus expresses.
## Redundancy between a generated corpus and a hand-written case is not
## duplication to remove.
##
## Half of this instruction group IS the condition codes: `ADDX`, `SUBX` and
## `NEGX` read X, the sticky-Z rule of those three is a rule about Z alone, and
## the overflow of `MULS.L` is observable in V and nowhere else. This file is
## where those are asserted, and it asserts them THROUGH THE SAME ENTRY POINT
## the corpus uses - `mcf5307_reset`, `mcf5307_set_reg`, `mcf5307_exec`,
## `mcf5307_get_reg` - so that a pass here is a pass of the shipped path and
## not of an internal helper reached around the back.
##
## EVERY CASE ASSERTS A COMPLETE TUPLE, never one field. A case that changes a
## register asserts (that register, the whole status register, `fault`), so a
## result that is right with a flag that is wrong fails, and a flag that is
## right with a result that is wrong fails. A case that must TRAP asserts
## (the register it must not have changed, `fault`, `halted`, the cycle
## return), so "it trapped" is separable from "it executed and wrote nothing".
##
## THE TRAP CASES ARE THE GREEN-MIRAGE CONTROL of the group. Byte and word
## arithmetic does not exist on this part, and neither does an `ADDI` to
## memory, a `NEG` to memory, a PC-relative `ADDQ` destination or a 64-bit
## `MULU.L`. The instruction encodings for all of those exist and a permissive
## core executes them silently. Each one below was checked against
## `m68k-elf-as -mcpu=5307`, which REJECTS every one of them; the assembler is
## the ground truth for what the part has, and the corresponding encodings are
## asserted here to trap.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Instruction
## semantics, the condition-code rules and the encodings are facts about
## Motorola silicon; they are taken from the ColdFire Family Programmer's
## Reference Manual and the MCF5307 User's Manual (AGENTS.md section 11) and
## from this project's own measurements with the pinned cross assembler.

import mcf5307/cpu
import mcf5307/decode_types
import mcf5307/ea
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
  # The status register is set LAST: `mcf5307_reset` writes it, so an earlier
  # write would be overwritten and every X-reading case would silently run
  # with X clear.
  discard mcf5307_set_reg(ctx, 16, sr)

  # ONE INSTRUCTION, AND THE BUDGET IS WHAT STOPS THE LOOP AFTER IT. The
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
  mcf5307_destroy(ctx)

proc mem32(address: uint32): uint32 =
  boardReadValue(board, address, 4)

# The two assertions. Each compares ONE complete tuple, so a right result with
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

  # The carry out of bit 31 sets BOTH C and X, and the zero result sets Z.
  expectD(runIns([0xD280'u16], d = [1'u32, 0xFFFFFFFF'u32, 0, 0, 0, 0, 0, 0]),
    1, 0'u32, srBase or ccrC or ccrX or ccrZ,
    "add.l carry out sets C, X and Z")

  # Signed overflow: 0x7FFFFFFF + 1 crosses into the negative half. V and N
  # are set and C is NOT: the unsigned sum did not carry.
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
  # add.l %d1,(%a0)+ = d398. THE POSTINCREMENT HAPPENS ONCE. A read-modify-
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
  # adda.l %d0,%a1 = d3c0. ADDA DOES NOT TOUCH THE CONDITION CODES: the whole
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

  # addq.l #8,%d1 = 5081. THE DATA FIELD 000 MEANS EIGHT, NOT ZERO. A decoder
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

  # THE STICKY Z. ADDX CLEARS Z ON A NON-ZERO RESULT AND LEAVES IT ALONE
  # OTHERWISE. It never SETS Z. These two cases differ only in the incoming Z
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
  # neg.l %d0 = 4480. C IS SET WHENEVER THE RESULT IS NON-ZERO, which is the
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
  # clr.l %d0 = 4280. N, Z, V and C take fixed values and X IS UNTOUCHED.
  expectD(runIns([0x4280'u16], d = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrX or ccrN or ccrV or ccrC),
    0, 0'u32, srBase or ccrX or ccrZ,
    "clr.l sets Z, clears N, V and C, and leaves X alone")

  # clr.w and clr.b exist on this part (the assembler accepts both) and each
  # clears ITS OWN WIDTH ALONE. A core that cleared the whole register would
  # pass a long-only test and corrupt the upper half here.
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
  # ext.w %d0 = 4880: the low byte becomes the low word, and THE UPPER HALF IS
  # UNTOUCHED. N comes from bit 15 of the 16-bit result, not from bit 31.
  expectD(runIns([0x4880'u16], d = [0x12345680'u32, 0, 0, 0, 0, 0, 0, 0]),
    0, 0x1234FF80'u32, srBase or ccrN, "ext.w extends the byte into the word")

  # ext.l %d0 = 48c0: the low word becomes the whole register.
  expectD(runIns([0x48C0'u16], d = [0x00008000'u32, 0, 0, 0, 0, 0, 0, 0]),
    0, 0xFFFF8000'u32, srBase or ccrN, "ext.l extends the word into the long")
  expectD(runIns([0x48C0'u16], d = [0x00007FFF'u32, 0, 0, 0, 0, 0, 0, 0]),
    0, 0x00007FFF'u32, srBase, "ext.l of a positive word leaves it positive")

  # extb.l %d0 = 49c0: the low BYTE becomes the whole register, which is a
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

  # V REPORTS THAT THE 32-BIT RESULT IS NOT THE WHOLE PRODUCT. 0x10000 squared
  # is 0x1_0000_0000, whose low 32 bits are zero: without V this case is
  # indistinguishable from a multiply by zero.
  expectD(runIns([0x4C00'u16, 0x1000'u16],
                 d = [0x10000'u32, 0x10000'u32, 0, 0, 0, 0, 0, 0]),
    1, 0'u32, srBase or ccrV or ccrZ,
    "mulu.l overflow sets V with the truncated result")

  # muls.l %d0,%d1 = 4c00 1800. THE SIGNED FLAG IS BIT 11 OF THE SECOND WORD.
  # -1 * 3 is -3 unsigned-wrong and signed-right, so a core that ignores the
  # bit gives 0xFFFFFFFD here too - which is why the overflow case below is
  # the one that separates them.
  expectD(runIns([0x4C00'u16, 0x1800'u16],
                 d = [0xFFFFFFFF'u32, 3, 0, 0, 0, 0, 0, 0]),
    1, 0xFFFFFFFD'u32, srBase or ccrN, "muls.l -1 * 3 = -3")

  # -0x10000 * 0x10000 is -0x1_0000_0000, which does not fit a signed 32-bit
  # result: V is set. The same operands read as UNSIGNED overflow too, so the
  # separating case is the pair below.
  expectD(runIns([0x4C00'u16, 0x1800'u16],
                 d = [0xFFFF0000'u32, 0x10000'u32, 0, 0, 0, 0, 0, 0]),
    1, 0'u32, srBase or ccrV or ccrZ, "muls.l overflow sets V")

  # THE ONE CASE THAT SEPARATES SIGNED FROM UNSIGNED OVERFLOW. -1 * -1 is 1,
  # which fits a signed 32-bit result, so MULS sets no V. The same two words
  # read as unsigned are 0xFFFFFFFF * 0xFFFFFFFF, a 64-bit product, so MULU
  # sets V. Same operands, same low 32 bits, opposite V.
  expectD(runIns([0x4C00'u16, 0x1800'u16],
                 d = [0xFFFFFFFF'u32, 0xFFFFFFFF'u32, 0, 0, 0, 0, 0, 0]),
    1, 1'u32, srBase, "muls.l -1 * -1 = 1 with no overflow")
  expectD(runIns([0x4C00'u16, 0x1000'u16],
                 d = [0xFFFFFFFF'u32, 0xFFFFFFFF'u32, 0, 0, 0, 0, 0, 0]),
    1, 1'u32, srBase or ccrV,
    "mulu.l of the same two words DOES overflow")

block:
  # divu.l %d0,%d1 = 4c40 1001. The second word names Dq in bits 15..12 and
  # Dr in bits 2..0; equal registers select the quotient-only form.
  expectD(runIns([0x4C40'u16, 0x1001'u16], d = [3'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 5'u32, srBase, "divu.l 17 / 3 = 5")

  # divs.l %d0,%d1 = 4c40 1801. THE SIGNED QUOTIENT TRUNCATES TOWARD ZERO:
  # 17 / -3 is -5 and not -6. A core that used a flooring division gives -6.
  expectD(runIns([0x4C40'u16, 0x1801'u16],
                 d = [0xFFFFFFFD'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 0xFFFFFFFB'u32, srBase or ccrN,
    "divs.l 17 / -3 truncates toward zero to -5")

  # The same two words read as UNSIGNED: 17 / 0xFFFFFFFD is 0. Same operands,
  # opposite result, so this separates the signed bit from a coincidence.
  expectD(runIns([0x4C40'u16, 0x1001'u16],
                 d = [0xFFFFFFFD'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 0'u32, srBase or ccrZ, "divu.l of the same two words is 0")

block:
  # remu.l %d0,%d2:%d1 = 4c40 1002. Dq is d1 and Dr is d2. COLDFIRE'S REMx.L
  # PRODUCES THE REMAINDER ONLY: d2 takes the remainder and d1 IS UNCHANGED.
  # A core that wrote the quotient into Dq as the 68020 DIVUL does fails on
  # the d1 half of this tuple.
  let o = runIns([0x4C40'u16, 0x1002'u16], d = [5'u32, 17, 0, 0, 0, 0, 0, 0])
  let got = (d1: o.d[1], d2: o.d[2], sr: o.sr, fault: o.fault)
  let want = (d1: 17'u32, d2: 2'u32, sr: srBase, fault: false)
  check(got == want, "remu.l writes the remainder to Dr and leaves Dq alone",
    $got, $want)

  # rems.l %d0,%d2:%d1 = 4c40 1802. The signed remainder takes the sign of the
  # DIVIDEND: -17 rem 5 is -2, not +3.
  let os = runIns([0x4C40'u16, 0x1802'u16],
                  d = [5'u32, 0xFFFFFFEF'u32, 0, 0, 0, 0, 0, 0])
  let gotS = (d1: os.d[1], d2: os.d[2], sr: os.sr, fault: os.fault)
  let wantS = (d1: 0xFFFFFFEF'u32, d2: 0xFFFFFFFE'u32,
               sr: srBase or ccrN, fault: false)
  check(gotS == wantS, "rems.l -17 rem 5 = -2, signed by the dividend",
    $gotS, $wantS)

block:
  # The one signed division overflow: the most negative value divided by -1
  # has no positive quotient. V is set and THE OPERANDS ARE UNCHANGED.
  expectD(runIns([0x4C40'u16, 0x1801'u16],
                 d = [0xFFFFFFFF'u32, 0x80000000'u32, 0, 0, 0, 0, 0, 0]),
    1, 0x80000000'u32, srBase or ccrV,
    "divs.l of the most negative value by -1 sets V and writes nothing")

  # A DIVISION BY ZERO IS A TRAP. There is no exception model yet (CPU-14), so
  # the core halts with `fault` rather than divide. It must NOT return a
  # quotient of any kind.
  expectTrapD(runIns([0x4C40'u16, 0x1001'u16],
                     d = [0'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 17'u32, "divu.l by zero traps")
  expectTrapD(runIns([0x4C40'u16, 0x1801'u16],
                     d = [0'u32, 17, 0, 0, 0, 0, 0, 0]),
    1, 17'u32, "divs.l by zero traps")

# ---------------------------------------------------------------------------
# THE ENCODINGS THIS PART DOES NOT HAVE. Every one below was offered to
# `m68k-elf-as -mcpu=5307` and REJECTED. A permissive core executes them and
# hides a real firmware fault (design section 17 row 7.10).

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
  # The 64-bit product form: bit 10 of the second word. It is a 68020
  # instruction and this part has only the 32-bit form.
  expectTrapD(runIns([0x4C00'u16, 0x1400'u16], d = two), 1, 2'u32,
    "the 64-bit mulu.l form traps")
  # addx.l -(%a0),-(%a1): the memory form of ADDX, which this part drops.
  expectTrapD(runIns([0xD388'u16], d = two), 1, 2'u32,
    "the memory form of addx.l traps")

# ---------------------------------------------------------------------------
# THE DECLARED OPERAND MASKS, READ DIRECTLY.
#
# WHY THESE ARE NOT REDUNDANT WITH THE TRAP CASES ABOVE, and the measurement
# that says so. Widening the ADDQ mask back to data addressing - which is what
# it was before this task - and re-running every case above changes NOTHING:
# `addq.l #1,(4,%pc)` still traps, because `eaResolve` in `mcf5307/machine`
# resolves no operand it cannot write and rejects the same three mode-7
# sub-variants a second time. Defence in depth is correct and it also makes
# the two defences INDISTINGUISHABLE from the outside.
#
# `eaIsLegalFor` is a declaration that other code reads - `t_ea_masks` reads
# it, and CPU-13's negative corpus will - so it has to be right on its own
# terms and not only right where a second check happens to cover it. These
# assertions read it directly. Each mask carries a NEGATIVE case and a
# POSITIVE control, because a mask that rejected everything would report the
# negative case as a pass.

proc checkMask(got: bool; want: bool; label: string) =
  check(got == want, label, $got, $want)

block:
  # ADDQ and SUBQ: alterable. An address register is IN, and a PC-relative or
  # an immediate destination is OUT.
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

  # The `<ea>,Dn` direction of ADD and SUB reads data addressing, which DOES
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

if failures.len > 0:
  echo ""
  echo "t_alu: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_alu: ", passCount, " cases passed"
