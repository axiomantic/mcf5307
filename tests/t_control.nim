## `t_control` - control flow and comparison.
##
## WHY THIS FILE EXISTS BESIDE `mcf5307_conformance_control`. That corpus is
## POSITIVE cases: encodings this part has, run against an expected state. A
## positive corpus CANNOT SEE a wrongly-claimed encoding, because a stolen
## encoding produces a PASSING EXECUTION OF A DIFFERENT INSTRUCTION.
##
## EVERY CASE ASSERTS A COMPLETE TUPLE, never one field, exactly as `t_alu`,
## `t_move` and `t_logic` do.
##
## The condition matrix is exhaustive and the corpus is a sample. Sixteen
## conditions over sixteen condition-code words is 256 executions per opcode,
## which no corpus can carry; it is one loop here. Each condition's answer over
## all sixteen words is folded into one 16-bit vector and compared against a
## literal constant, so the expected value is a number a reader can check
## rather than a second copy of the implementation's own expression.

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
# ---------------------------------------------------------------------------
# The board. One flat byte array, big-endian, exactly as `t_logic`'s and the
# conformance runner's. A read outside it reports `busUnmapped`.

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
# The runner. It is `t_logic`'s and `t_alu`'s: a pass here has to be a pass of
# the shipped path - `mcf5307_reset`, `mcf5307_set_reg`, `mcf5307_exec`,
# `mcf5307_get_reg` - and not of an internal helper reached around the back.

const
  execBase = 0x100'u32     ## where the instruction words are placed
  stackBase = 0x800'u32
  srBase = 0x2700'u32      ## the reset status register, CCR all clear
  dirtyD = 0x12345678'u32  ## the data-register seed the corpus uses
  dirtyA = 0x0BADC0DE'u32  ## the address-register seed the corpus uses
  guard = 0x0BADC0DE'u32
  writableOperand = 0x400'u32
    ## An address inside the board, for the trap cases whose refused operand
    ## would otherwise be a write the board refuses anyway. It is clear of the
    ## encoding at `execBase` and below `stackBase`. See the note on the two
    ## Scc rows in block 6 for the measurement that put it here.
  zero8: array[8, uint32] = [0'u32, 0, 0, 0, 0, 0, 0, 0]

type Outcome = object
  cycles: uint32
    ## `mcf5307_exec(ctx, 1)`'s RETURN. It is the WHOLE RETIRED COST of the one
    ## instruction the call ran - `cpu.nim`'s header block is the contract -
    ## and this suite reads only whether it is zero. The `cycles: 0` half of
    ## every trap tuple below asserts "it did not run" and asserts no count;
    ## uncertainty 3 in `control.nim`'s header says why no count is asserted.
  fault: bool
  halted: bool
  d: array[8, uint32]
  a: array[8, uint32]      ## a[7] is the single A7 (the stack pointer)
  sr: uint32
  pc: uint32

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
  # write would be overwritten and every case that asserts an untouched
  # condition code would silently run with a clear one.
  discard mcf5307_set_reg(ctx, 16, sr)

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

# ---------------------------------------------------------------------------
# The assertions.

proc expectTrap(o: Outcome; d0, a0, a7, sr: uint32; label: string) =
  ## An encoding this part does not have, or an operand the opcode may not
  ## reach. It must halt with `fault`, return no cycles, and leave the register
  ## file and the status register exactly as it found them.
  ##
  ## EVERY CALLER SEEDS `d0`, `a0` AND `sr` NON-ZERO. A trap case whose
  ## registers start at zero asserts `0 == 0`.
  let got = (d0: o.d[0], a0: o.a[0], a7: o.a[7], sr: o.sr,
             fault: o.fault, halted: o.halted, cycles: o.cycles)
  let want = (d0: d0, a0: a0, a7: a7, sr: sr,
              fault: true, halted: true, cycles: 0'u32)
  check(got == want, label, $got, $want)

proc expectDecode(word: uint16; want: Operation; label: string) =
  let got = decodeWord(word).op
  check(got == want, label, $got, $want)

proc checkMaskImpl(site: int; got: bool; want: bool; label: string) =
  checkImpl(site, got == want, label, $got, $want)


template checkMask(got: bool; want: bool; label: string) =
  ## THE CALL SITE IS RECORDED TWICE - once at COMPILE TIME into
  ## `declaredSites` by the `static` below, and once at RUN TIME into
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkMaskImpl(site, got, want, label)
# The dirty condition codes an instruction of this group must carry through
# untouched. NOP, BRA, BSR, Bcc, JMP, JSR and Scc write no flag at all, so
# every one of them is entered with all five set and asserted unchanged.
const allDirty = srBase or ccrN or ccrZ or ccrV or ccrC or ccrX

# The seeded register file every trap case starts from.
const trapD: array[8, uint32] = [dirtyD, 0, 0, 0, 0, 0, 0, 0]
const trapA: array[8, uint32] = [dirtyA, 0, 0, 0, 0, 0, 0, 0]

# ---------------------------------------------------------------------------
# The condition table, written out as sixteen literal vectors.
#
# Bit k of each vector is the condition's answer when the condition-code bits
# hold the value k - C at bit 0, V at bit 1, Z at bit 2, N at bit 3, which is
# the layout `machine.nim`'s `ccrC` .. `ccrX` name.
#
# These are literals and not a second copy of the implementation's expression.
# A test that re-derived `(not C) and (not Z)` beside the core's own
# `(not C) and (not Z)` asserts that one transcription equals the other and
# would agree with the core about a rule they had both got wrong. A vector is a
# number: `hi` is 0x0505, which is the four condition-code words 0, 2, 8 and 10
# - exactly those with C clear and Z clear - and a reader can check that by
# hand.
#
# WHAT THE MANUAL ON THIS MACHINE DOES AND DOES NOT SETTLE. It gives the
# condition-code bits and it names the wildcard `cc`, and it prints NO table of
# the sixteen conditions and their tests anywhere. The four-bit ENCODING of
# each is measured rather than assumed:
# every mnemonic below was assembled by `m68k-elf-as -mcpu=5307`, which put
# `bhi` at 0x62, `bls` at 0x63, `bcc` at 0x64, `bcs` at 0x65, `bne` at 0x66,
# `beq` at 0x67, `bvc` at 0x68, `bvs` at 0x69, `bpl` at 0x6a, `bmi` at 0x6b,
# `bge` at 0x6c, `blt` at 0x6d, `bgt` at 0x6e and `ble` at 0x6f, and `st` at
# 0x50c0 and `sf` at 0x51c0. The boolean test of each is the M68000 family
# definition and it is uncertainty 1 in `control.nim`'s header.
const conditionVectors: array[16, uint16] = [
  0xFFFF'u16,   #  0  T    always
  0x0000'u16,   #  1  F    never
  0x0505'u16,   #  2  HI   not C and not Z
  0xFAFA'u16,   #  3  LS   C or Z
  0x5555'u16,   #  4  CC   not C
  0xAAAA'u16,   #  5  CS   C
  0x0F0F'u16,   #  6  NE   not Z
  0xF0F0'u16,   #  7  EQ   Z
  0x3333'u16,   #  8  VC   not V
  0xCCCC'u16,   #  9  VS   V
  0x00FF'u16,   # 10  PL   not N
  0xFF00'u16,   # 11  MI   N
  0xCC33'u16,   # 12  GE   N equals V
  0x33CC'u16,   # 13  LT   N differs from V
  0x0C03'u16,   # 14  GT   not Z and N equals V
  0xF3FC'u16,   # 15  LE   Z or N differs from V
]

const conditionNames: array[16, string] = [
  "t", "f", "hi", "ls", "cc", "cs", "ne", "eq",
  "vc", "vs", "pl", "mi", "ge", "lt", "gt", "le"]

# ---------------------------------------------------------------------------
# Block 1. The sixteen conditions, through `Bcc`.
#
# `0110 cccc dddddddd` with a displacement of 8: taken lands at
# `execBase + 2 + 8` and not taken at `execBase + 2`. The two are different
# addresses, so the program counter alone answers "was it taken".
#
# Conditions 0 and 1 are `BRA` and `BSR` and both are always taken. They occupy
# the slots a naive reading would give to the always-true and always-false
# conditions, and `0x0000` for slot 1 would be exactly what a core that treated
# `BSR` as `Bf` produced. Their expected vector is `0xffff` in both, which is
# `conditionVectors[0]` for the first and not `conditionVectors[1]` for the
# second - the one place in this file where the branch table and the Scc table
# deliberately disagree.

const branchTakenPc = execBase + 2'u32 + 8'u32
const branchNotTakenPc = execBase + 2'u32

block:
  for cc in 0 .. 15:
    var taken = 0'u16
    for ccr in 0 .. 15:
      let word = 0x6000'u16 or (uint16(cc) shl 8) or 0x08'u16
      let o = runIns([word], a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase],
                     sr = srBase or uint32(ccr))
      if o.fault or o.halted:
        # Neither of the two legal outcomes. Force a mismatch rather than
        # silently record "not taken" for a core that refused the word.
        taken = 0xDEAD'u16
        break
      elif o.pc == branchTakenPc:
        taken = taken or (1'u16 shl ccr)
      elif o.pc != branchNotTakenPc:
        taken = 0xDEAD'u16
        break
    let want = if cc <= 1: 0xFFFF'u16 else: conditionVectors[cc]
    check(taken == want,
      "b" & (if cc == 0: "ra" elif cc == 1: "sr" else: conditionNames[cc]) &
        " is taken on exactly the condition-code words its condition holds on",
      "0x" & taken.toHex(4), "0x" & want.toHex(4))

# ---------------------------------------------------------------------------
# Block 2. The sixteen conditions, through `Scc`.
#
# `0101 cccc 11 000 rrr` writes ones or zeros into the LOW BYTE of Dn, so the
# register is seeded with `DIRTY_D` and the answer is read off its low byte.
#
# BOTH TABLES ARE RUN THROUGH THE SAME SIXTEEN VECTORS ON PURPOSE. `Bcc` and
# `Scc` must read ONE condition evaluator.

const sccFalseD0 = dirtyD and not 0xFF'u32
const sccTrueD0 = sccFalseD0 or 0xFF'u32

block:
  for cc in 0 .. 15:
    var trueMask = 0'u16
    var wrongValue = false
    for ccr in 0 .. 15:
      let word = 0x50C0'u16 or (uint16(cc) shl 8)
      let o = runIns([word], d = [dirtyD, 0, 0, 0, 0, 0, 0, 0],
                     a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase],
                     sr = srBase or uint32(ccr))
      if o.fault or o.halted:
        wrongValue = true
      elif o.d[0] == sccTrueD0:
        trueMask = trueMask or (1'u16 shl ccr)
      elif o.d[0] != sccFalseD0:
        wrongValue = true
    let got = (mask: trueMask, wrongValue: wrongValue)
    let want = (mask: conditionVectors[cc], wrongValue: false)
    check(got == want,
      "s" & conditionNames[cc] &
        " sets the low byte to ones on exactly its condition's words",
      $got, $want)

# ---------------------------------------------------------------------------
# Block 3. What this group claims, word by word.
#
# Every word below was emitted by `m68k-elf-as -mcpu=5307` for the instruction
# named beside it.

block:
  expectDecode(0x6006'u16, opBra, "bra.b .+8 (6006) decodes as BRA")
  expectDecode(0x6000'u16, opBra, "bra.w (6000) decodes as BRA")
  expectDecode(0x6106'u16, opBsr, "bsr.b .+8 (6106) decodes as BSR")
  expectDecode(0x6708'u16, opBcc, "beq.b .+10 (6708) decodes as Bcc")
  expectDecode(0x6F00'u16, opBcc, "ble.w (6f00) decodes as Bcc")
  expectDecode(0x50C0'u16, opScc, "st %d0 (50c0) decodes as Scc")
  expectDecode(0x51C0'u16, opScc, "sf %d0 (51c0) decodes as Scc")
  expectDecode(0x5BC7'u16, opScc, "smi %d7 (5bc7) decodes as Scc")
  expectDecode(0x4A00'u16, opTst, "tst.b %d0 (4a00) decodes as TST")
  expectDecode(0x4A40'u16, opTst, "tst.w %d0 (4a40) decodes as TST")
  expectDecode(0x4A80'u16, opTst, "tst.l %d0 (4a80) decodes as TST")
  expectDecode(0x4ED0'u16, opJmp, "jmp (%a0) (4ed0) decodes as JMP")
  expectDecode(0x4E90'u16, opJsr, "jsr (%a0) (4e90) decodes as JSR")
  expectDecode(0x4E75'u16, opRts, "rts (4e75) decodes as RTS")
  expectDecode(0x4E73'u16, opRte, "rte (4e73) decodes as RTE")
  expectDecode(0x4E40'u16, opTrap, "trap #0 (4e40) decodes as TRAP")
  expectDecode(0x4E4F'u16, opTrap, "trap #15 (4e4f) decodes as TRAP")
  expectDecode(0xB280'u16, opCmp, "cmp.l %d0,%d1 (b280) decodes as CMP")
  expectDecode(0xB3C0'u16, opCmpa, "cmpa.l %d0,%a1 (b3c0) decodes as CMPA")
  expectDecode(0x0C80'u16, opCmpi, "cmpi.l #imm,%d0 (0c80) decodes as CMPI")
  expectDecode(0x4E71'u16, opNop, "nop (4e71) is still a NOP and not a TRAP")

# ---------------------------------------------------------------------------
# Block 4. What this group must not claim.
#
# A wrongly-claimed encoding produces a passing execution of a different
# instruction, which no positive corpus can see. Each word below is a real
# 68000 or 68020 instruction that this part does not have, or an encoding
# something else owns, and each must come back as an unrecognised word.

block:
  # `4ac0 | <ea>` is TAS and not a `TST` whose size field is 11. Measured:
  # `4ad0` decodes as `tas %a0@` on `m68k-elf-objdump -m m68k:68020` and as
  # `.short 0x4ad0` on `-m m68k:5307`, and no timing table carries a `tas` row
  # at all. If `TST` were
  # decoded on `word and 0xFF00 == 0x4a00` without a size guard, this word
  # would become a `TST` of size zero.
  expectDecode(0x4AD0'u16, opIllegal, "tas (%a0) (4ad0) is not a TST")
  expectDecode(0x4AC0'u16, opIllegal, "tas %d0 (4ac0) is not a TST")

  # The other inhabitants of `0100 1110 01xx xxxx`. TRAP is `4e4x` and the
  # neighbours are other instructions.
  expectDecode(0x4E70'u16, opIllegal, "reset (4e70) is not this group's")
  expectDecode(0x4E72'u16, opIllegal, "stop #imm (4e72) is not this group's")
  expectDecode(0x4E74'u16, opIllegal, "rtd #imm (4e74) is not this group's")
  expectDecode(0x4E76'u16, opIllegal, "trapv (4e76) is not this group's")
  expectDecode(0x4E77'u16, opIllegal, "rtr (4e77) is not this group's")
  expectDecode(0x4E7A'u16, opIllegal, "movec (4e7a) is not this group's")

  # `0cc0 | <ea>` is the 68020 `CMP2`/`CHK2` and not a `CMPI` of size 11.
  expectDecode(0x0CC0'u16, opIllegal, "cmp2/chk2 (0cc0) is not a CMPI")

  # LINE 1011 OPMODES 100 TO 110 ARE STILL EOR'S.
  expectDecode(0xB380'u16, opEor, "eor.l %d1,%d0 (b380) is still an EOR")
  expectDecode(0xB300'u16, opEor, "the byte EOR opmode (b300) is still an EOR")
  expectDecode(0xB340'u16, opEor, "the word EOR opmode (b340) is still an EOR")

  # THE ADDQ AND SUBQ REGRESSION GUARD. The `0101 cccc 11 <ea>` encoding space
  # is 1024 words, of which 128 are `Scc Dn`, three are TRAPF and none are
  # DBcc. `50c0` must be an Scc and `5040`, `5080` and `5180` must still be
  # what they were.
  expectDecode(0x50C0'u16, opScc, "scc_is_not_an_addq: 50c0 is an Scc")
  expectDecode(0x51C0'u16, opScc, "scc_is_not_a_subq: 51c0 is an Scc")
  expectDecode(0x5040'u16, opAddq, "addq.w #8,%d0 (5040) is still an ADDQ")
  expectDecode(0x5080'u16, opAddq, "addq.l #8,%d0 (5080) is still an ADDQ")
  expectDecode(0x5180'u16, opSubq, "subq.l #8,%d0 (5180) is still a SUBQ")

  # Three words inside `0101 cccc 11 <ea>` are TRAPF and not Scc, and TRAPF is
  # not implemented. Measured with the pinned assembler under `-mcpu=5307`:
  # `trapf` assembles to `51fc`, `trapf.w #1` to `51fa 0001` and `trapf.l #1`
  # to `51fb 0000 0001`.
  #
  # It is exactly three words and not a condition family. The same assembler
  # rejects `trapt`, `trapeq`, `trapne` and `traphi` under `-mcpu=5307` -
  # "invalid instruction for this architecture; needs 68020 ... cpu32" - so
  # only condition 0001 has the three forms and no `TRAPcc` exists here.
  #
  # They must fall through to `opIllegal` and stay unclaimed. Claiming them as
  # an Scc would execute a TRAPF as a byte write into a data register.
  expectDecode(0x51FA'u16, opIllegal, "trapf_is_not_an_scc: trapf.w (51fa)")
  expectDecode(0x51FB'u16, opIllegal, "trapf_is_not_an_scc: trapf.l (51fb)")
  expectDecode(0x51FC'u16, opIllegal, "trapf_is_not_an_scc: trapf (51fc)")

  # THE CONTROLS THAT KEEP THE EXCLUSION THREE WORDS WIDE. `51c0` is `sf %d0`
  # - the SAME condition
  # as the three TRAPF words - and `51f9` and `51fd` are its immediate
  # neighbours on either side of them.
  expectDecode(0x51C0'u16, opScc, "trapf_is_not_an_scc: sf %d0 (51c0) is Scc")
  expectDecode(0x51F9'u16, opScc, "trapf_is_not_an_scc: 51f9 is still an Scc")
  expectDecode(0x51FD'u16, opScc, "trapf_is_not_an_scc: 51fd is still an Scc")

# ---------------------------------------------------------------------------
# Block 5. The 32-bit displacement.
#
# `Bcc <label>`, `BRA <label>` and `BSR <label>` carry an operand size of
# "8,16" in Table 3-7, page 3-23, and no third value. An 8-bit displacement of
# 0xff is the marker for a 32-bit displacement, which is ISA_B, and this part
# does not have it.
#
# The pinned assembler agrees and its disassembler does not, and both
# measurements are named here because the second is a laxity that reads like
# evidence. `m68k-elf-as` rejects `bra.l`, `beq.l` and
# `bsr.l` under `-mcpu=5307` and accepts all three under `-m68020`, where
# `bra.l` assembles to `60ff 0000 0008` - so 0xff is the 32-bit marker and the
# ColdFire tables refuse it. `m68k-elf-objdump -m m68k:5307` nevertheless
# prints `60ff` as `bras 1`, an ordinary byte branch of -1 to an odd address,
# while `-m m68k:68020` prints the same bytes as `bral`. That is the
# disassembler declining to model the marker, exactly as it decodes `4690` as
# `notl %d0` (see `logic.nim`), and it is not evidence about the part.
#
# A displacement of 0x00 is the other marker and it is the 16-bit form, which
# the positive corpus exercises in both directions. Only 0xff traps.

block:
  expectTrap(runIns([0x60FF'u16, 0x0000'u16, 0x0008'u16], d = trapD,
                    a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "bra with an 8-bit displacement of 0xff traps: 32-bit is ISA_B")
  expectTrap(runIns([0x67FF'u16, 0x0000'u16, 0x0008'u16], d = trapD,
                    a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "beq with an 8-bit displacement of 0xff traps: 32-bit is ISA_B")
  expectTrap(runIns([0x61FF'u16, 0x0000'u16, 0x0008'u16], d = trapD,
                    a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "bsr with an 8-bit displacement of 0xff traps: 32-bit is ISA_B")

  # The positive controls. A core that trapped every branch would pass the
  # rows above. 0xfe is the largest displacement the byte form has and
  # 0x00 is the 16-bit marker; both must run.
  block:
    let o = runIns([0x60FE'u16], a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase],
                   sr = allDirty)
    let got = (pc: o.pc, sr: o.sr, fault: o.fault)
    let want = (pc: execBase + 2'u32 - 2'u32, sr: allDirty, fault: false)
    check(got == want, "bra.b with a displacement of 0xfe branches to -2",
      $got, $want)
  block:
    let o = runIns([0x6000'u16, 0x0010'u16],
                   a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase], sr = allDirty)
    let got = (pc: o.pc, sr: o.sr, fault: o.fault)
    let want = (pc: execBase + 2'u32 + 0x10'u32, sr: allDirty, fault: false)
    check(got == want,
      "bra with an 8-bit displacement of 0x00 takes the 16-bit form",
      $got, $want)

# ---------------------------------------------------------------------------
# Block 6. One illegal operand per opcode.
#
# Every implemented opcode must trap at least one illegal mode, and the
# mechanism is the per-opcode legality mask. The encodings below are built
# from a measured base word by replacing the low six bits, which is the
# effective-address field. `jmp (%a0)` is `4ed0`, so `jmp %d0` is
# `4ed0 and not 0x3f` or `00` = `4ec0`, and `m68k-elf-objdump` decodes `4ec0`
# as an instruction on neither `-m m68k:5307` nor `-m m68k:68020`.

block:
  # Scc takes a data register and nothing else. Table 3-12, page 3-27: the
  # `scc Dx` row is timed under `Rn` alone and dashed under all seven other
  # columns. `m68k-elf-as -mcpu=5307` rejects `scc (%a0)`, `scc %a0` and
  # `scc 0x1234.w`.
  #
  # `51c8` is the 68000 `DBcc` slot. `0101 cccc 11 001 rrr` is
  # `DBcc Dn,<label>` on a 68000 and no
  # instruction at all on this part: section 3.9, which begins on page 3-21,
  # lists "decrement and branch" among the removed instructions, no table in
  # the manual carries a DBcc row, and `m68k-elf-as -mcpu=5307` rejects
  # `dbra %d0,.` and `dbf %d0,.`.
  # `m68k-elf-objdump -m m68k:5307` prints `51c8` as `sf %d0` - it ignores the
  # mode field entirely - while `-m m68k:68020` reads the same two words as
  # `dbf %d0,...`; the disassembler is wrong on both counts and the mask is
  # what refuses the word.
  expectTrap(runIns([0x51C8'u16, 0xFFFC'u16], d = trapD, a = trapA,
                    sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "dbf %d0 (51c8) traps: DBcc is not an instruction on this part")

  # These two name an address the board answers, and that is the whole point.
  # A trap case whose operand is outside the board traps whatever the mask
  # says, because the write reports `busUnmapped` and the bus fault arrives
  # first. `writableOperand` is inside the board and clear of the encoding, so
  # the mask is the only thing that can refuse the write.
  expectTrap(runIns([0x54D0'u16],
                    d = trapD,
                    a = [writableOperand, 0, 0, 0, 0, 0, 0, 0],
                    sr = allDirty),
    dirtyD, writableOperand, stackBase, allDirty,
    "scc (%a0) (54d0) traps: an Scc destination is a data register")
  expectTrap(runIns([0x57F8'u16, uint16(writableOperand)], d = trapD,
                    a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "seq (xxx).w (57f8) traps: an Scc destination is a data register")

  # JMP and JSR take control addressing. Table 3-15, page 3-30, dashes `Rn`,
  # `(An)+`, `-(An)` and `#xxx` for both.
  expectTrap(runIns([0x4EC0'u16], d = trapD, a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "jmp %d0 (4ec0) traps: a data register is not a control operand")
  expectTrap(runIns([0x4EC8'u16], d = trapD, a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "jmp %a0 (4ec8) traps: an address register is not a control operand")
  expectTrap(runIns([0x4ED8'u16], d = trapD, a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "jmp (%a0)+ (4ed8) traps: postincrement is not a control operand")
  expectTrap(runIns([0x4EE0'u16], d = trapD, a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "jmp -(%a0) (4ee0) traps: predecrement is not a control operand")
  expectTrap(runIns([0x4EFC'u16, 0x0000'u16, 0x0004'u16], d = trapD,
                    a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "jmp #4 (4efc) traps: an immediate is not a control operand")
  expectTrap(runIns([0x4E80'u16], d = trapD, a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "jsr %d0 (4e80) traps: a data register is not a control operand")
  expectTrap(runIns([0x4E98'u16], d = trapD, a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "jsr (%a0)+ (4e98) traps: postincrement is not a control operand")

  # TST TAKES EVERY MODE - no `tst` row carries a dash - EXCEPT that a BYTE
  # operand may not be an address register.
  # `m68k-elf-as -mcpu=5307` accepts `tst.w %a0` and `tst.l %a0` and REJECTS
  # `tst.b %a0`. That is a rule about the SIZE and not about the mask.
  expectTrap(runIns([0x4A08'u16], d = trapD, a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "tst.b %a0 (4a08) traps: a byte operand is not an address register")
  block:
    let o = runIns([0x4A48'u16], d = trapD, a = trapA, sr = allDirty)
    let got = (a0: o.a[0], sr: o.sr, fault: o.fault)
    # `DIRTY_A`'s low word is 0xc0de, whose bit 15 is SET, so the word form
    # answers N. As a LONGWORD 0x0badc0de is positive.
    let want = (a0: dirtyA, sr: srBase or ccrX or ccrN, fault: false)
    check(got == want, "tst.w %a0 (4a48) runs: the word form reaches An",
      $got, $want)

  # CMP, CMPA and CMPI are 32-bit and there is no other size. Table 3-7, page
  # 3-23, gives all three an operand size column of `32` alone, and
  # `m68k-elf-as -mcpu=5307` rejects `cmp.b`, `cmp.w`, `cmpa.w`, `cmpi.b` and
  # `cmpi.w`.
  #
  # `b2c0` is CMPA.W and the disassembler settles it. `m68k-elf-objdump
  # -m m68k:68020` prints `b2c0` as `cmpaw %d0,%a1`; `-m m68k:5307` prints
  # `.short 0xb2c0`. That is the word form of CMPA, and it is refused here.
  expectTrap(runIns([0xB200'u16], d = trapD, a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "cmp.b %d0,%d1 (b200) traps: comparison on this part is 32-bit")
  expectTrap(runIns([0xB240'u16], d = trapD, a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "cmp.w %d0,%d1 (b240) traps: comparison on this part is 32-bit")
  expectTrap(runIns([0xB2C0'u16], d = trapD, a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "cmpa.w %d0,%a1 (b2c0) traps: CMPA.W does not exist on this part")
  expectTrap(runIns([0x0C00'u16, 0x0005'u16], d = trapD, a = trapA,
                    sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "cmpi.b #5,%d0 (0c00) traps: CMPI on this part is 32-bit")
  expectTrap(runIns([0x0C40'u16, 0x0005'u16], d = trapD, a = trapA,
                    sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "cmpi.w #5,%d0 (0c40) traps: CMPI on this part is 32-bit")

  # The CMPI destination is a data register and nothing else. Table 3-13, page
  # 3-28: the `cmpi.l #imm,Dx` row is timed under `Rn` alone. `m68k-elf-as
  # -mcpu=5307` rejects `cmpi.l #5,(%a0)` and `cmpi.l #5,%a0`.
  expectTrap(runIns([0x0C90'u16, 0x0000'u16, 0x0005'u16], d = trapD,
                    a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "cmpi.l #5,(%a0) (0c90) traps: the destination is a data register")
  expectTrap(runIns([0x0C88'u16, 0x0000'u16, 0x0005'u16], d = trapD,
                    a = trapA, sr = allDirty),
    dirtyD, dirtyA, stackBase, allDirty,
    "cmpi.l #5,%a0 (0c88) traps: the destination is a data register")

# ---------------------------------------------------------------------------
# Block 7. The `RTE` format field.
#
# Any attempted execution of an RTE whose format is not in {4,5,6,7} generates
# a format error, and those four values are exactly the rows of the format
# field encoding.
#
# THIS CORE TRAPS RATHER THAN TAKING THE FORMAT-ERROR VECTOR, AND THAT IS
# UNCERTAINTY 4 IN `control.nim`'s HEADER. Vector 14 is a real exception on
# silicon; a trap is this core's one observable for "refused", the same channel
# every illegal size and operand uses.

block:
  let frame = @[(stackBase, 0x30802703'u32), (stackBase + 4'u32, 0x00000400'u32)]
  expectTrap(runIns([0x4E73'u16], d = trapD, a = trapA, sr = allDirty,
                    mem = frame),
    dirtyD, dirtyA, stackBase, allDirty,
    "rte with a format field of 3 traps: only 4, 5, 6 and 7 are frames")

  # THE POSITIVE CONTROL. Format 4 restores SR, PC and A7 = SP + 4 + 4.
  block:
    let good = @[(stackBase, 0x40802703'u32),
                 (stackBase + 4'u32, 0x00000400'u32)]
    let o = runIns([0x4E73'u16], d = trapD, a = trapA, sr = allDirty,
                   mem = good)
    let got = (pc: o.pc, sr: o.sr, a7: o.a[7], fault: o.fault)
    let want = (pc: 0x400'u32, sr: 0x2703'u32, a7: stackBase + 8'u32,
                fault: false)
    check(got == want, "rte with a format field of 4 restores sr, pc and a7",
      $got, $want)

# ---------------------------------------------------------------------------
# Block 8. The operands the corpus cannot offer.
#
# The corpus assembles its cases, so it can only hold forms the assembler
# emits. Two forms of this group are legal on the part and unreachable that
# way, and both are executed here instead.

block:
  # `cmp.l #imm,Dx` in the line-1011 immediate form. Table 3-13, page 3-28,
  # gives the `cmp.l <ea>,Rx` row a time of `1(0/0)` under `#xxx`, so the form
  # exists - but `m68k-elf-as -mcpu=5307` assembles `cmp.l #5,%d1` as the CMPI
  # encoding `0c81 0000 0005` and never emits `b2bc`. The word here is built
  # from the measured `b280` by replacing the low six bits with mode 7 sub 4,
  # the same method the trap cases above use.
  let o = runIns([0xB2BC'u16, 0x1234'u16, 0x5678'u16],
                 d = [0'u32, dirtyD, 0, 0, 0, 0, 0, 0],
                 a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase], sr = allDirty)
  let got = (d1: o.d[1], sr: o.sr, pc: o.pc, fault: o.fault)
  let want = (d1: dirtyD, sr: srBase or ccrX or ccrZ, pc: execBase + 6'u32,
              fault: false)
  check(got == want,
    "cmp.l #0x12345678,%d1 (b2bc) compares against an immediate and writes no register",
    $got, $want)

block:
  # `jmp (d8,PC,Xi)`. The assembler emits it - `4efb 2804` for
  # `jmp (4,%pc,%d2)` - but the corpus has no case that needs it and the
  # PC-relative indexed arm of `eaAddr` is reached by no other opcode in this
  # group. The index is a longword: d2 here is 0x40, so the target is
  # execBase + 2 + 4 + 0x40.
  let o = runIns([0x4EFB'u16, 0x2804'u16],
                 d = [0'u32, 0, 0x40'u32, 0, 0, 0, 0, 0],
                 a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase], sr = allDirty)
  let got = (pc: o.pc, sr: o.sr, fault: o.fault)
  let want = (pc: execBase + 2'u32 + 4'u32 + 0x40'u32, sr: allDirty,
              fault: false)
  check(got == want, "jmp (4,%pc,%d2) (4efb 2804) jumps through the pc index",
    $got, $want)

# ---------------------------------------------------------------------------
# Block 9. The masks themselves.
#
# `eaJumpTarget` is
# CONTROL ADDRESSING INCLUDING `(xxx).W`: the absolute short row is marked
# CONTROL, and the timing tables' `xxx.wl` column refers to both forms of
# absolute addressing.
#
# `(xxx).W` separates this class from MOVEM's. `m68k-elf-as -mcpu=5307`
# accepts `lea 0x1234.w,%a0`, `pea 0x1234.w`,
# `jmp 0x1234.w` and `jsr 0x1234.w` and rejects `movem.l %d0-%d1,0x1234.w`.
# `ea.nim` declares the class as `eaControl7`, and
# `eaJumpTarget` and `eaLeaPeaTarget` in `decode_types.nim` are its two
# readers. MOVEM reads neither: it carries `{eaAnInd, eaAnDisp}`, because
# folios 4-50 and 4-51 dash `(d8,An,Xi)`, `(xxx).L`, `(d16,PC)` and
# `(d8,PC,Xi)` as well.
#
# THE CELLS BELOW ARE THE MASK-LEVEL TABLE FOR `opJmp` AND `opJsr`.
# They reach `eaIsLegalFor` directly.

block:
  for (field, name, legal) in [
      (0x00'u16, "%d0", false), (0x08'u16, "%a0", false),
      (0x10'u16, "(%a0)", true), (0x18'u16, "(%a0)+", false),
      (0x20'u16, "-(%a0)", false), (0x28'u16, "(d16,%a0)", true),
      (0x30'u16, "(d8,%a0,%d2)", true), (0x38'u16, "(xxx).w", true),
      (0x39'u16, "(xxx).l", true), (0x3A'u16, "(d16,%pc)", true),
      (0x3B'u16, "(d8,%pc,%d2)", true), (0x3C'u16, "#imm", false)]:
    checkMask(eaIsLegalFor(opJmp, decodeEa(field)), legal,
      "jmp " & name & (if legal: " is legal" else: " is illegal"))
    checkMask(eaIsLegalFor(opJsr, decodeEa(field)), legal,
      "jsr " & name & (if legal: " is legal" else: " is illegal"))

block:
  # Scc reaches a data register and nothing else, and CMPI's destination is
  # the same one operand.
  for (field, name) in [(0x08'u16, "%a0"), (0x10'u16, "(%a0)"),
                        (0x38'u16, "(xxx).w"), (0x3C'u16, "#imm")]:
    checkMask(eaIsLegalFor(opScc, decodeEa(field)), false,
      "scc " & name & " is illegal")
    checkMask(eaIsLegalFor(opCmpi, decodeEa(field)), false,
      "cmpi " & name & " is illegal")
  checkMask(eaIsLegalFor(opScc, decodeEa(0x00'u16)), true, "scc %d0 is legal")
  checkMask(eaIsLegalFor(opCmpi, decodeEa(0x00'u16)), true,
    "cmpi %d0 is legal")

block:
  # TST and CMP read, so both admit the PC-relative pair and the immediate,
  # and both admit an address register: the `tst` rows and the
  # `cmp.l <ea>,Rx` row carry a time in every column.
  for (field, name) in [(0x00'u16, "%d0"), (0x08'u16, "%a0"),
                        (0x10'u16, "(%a0)"), (0x18'u16, "(%a0)+"),
                        (0x20'u16, "-(%a0)"), (0x28'u16, "(d16,%a0)"),
                        (0x30'u16, "(d8,%a0,%d2)"), (0x38'u16, "(xxx).w"),
                        (0x39'u16, "(xxx).l"), (0x3A'u16, "(d16,%pc)"),
                        (0x3B'u16, "(d8,%pc,%d2)"), (0x3C'u16, "#imm")]:
    checkMask(eaIsLegalFor(opTst, decodeEa(field)), true,
      "tst " & name & " is legal")
    checkMask(eaIsLegalFor(opCmp, decodeEa(field)), true,
      "cmp " & name & " is legal")
  # The reserved mode-7 sub-variants are in no mask at all.
  for field in [0x3D'u16, 0x3E'u16, 0x3F'u16]:
    checkMask(eaIsLegalFor(opTst, decodeEa(field)), false,
      "tst mode 7 sub " & $(field and 7'u16) & " is illegal")

# ---------------------------------------------------------------------------
# Block 10. The stack writes, read back from the board.
#
# The corpus asserts these through its own board; they are repeated here
# because `mem32` reads the same array the core wrote, and because a BSR whose
# push went to the right address with the wrong value is a different defect
# from one that went to the wrong address.

block:
  let o = runIns([0x6106'u16], a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase],
                 sr = allDirty,
                 mem = @[(stackBase - 8'u32, guard), (stackBase, guard)])
  let got = (pc: o.pc, a7: o.a[7], pushed: mem32(stackBase - 4'u32),
             below: mem32(stackBase - 8'u32), at: mem32(stackBase),
             sr: o.sr, fault: o.fault)
  let want = (pc: execBase + 2'u32 + 6'u32, a7: stackBase - 4'u32,
              pushed: execBase + 2'u32, below: guard, at: guard,
              sr: allDirty, fault: false)
  check(got == want,
    "bsr.b pushes the address after the instruction and nothing else", $got,
    $want)

block:
  # The word form is four bytes long and the byte form is two, which is why
  # this row sits beside the one above. Only this one separates "push the
  # address after the instruction" from "push the branch base"; the two are
  # the same value for the byte form.
  let o = runIns([0x6100'u16, 0x0040'u16],
                 a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase], sr = allDirty,
                 mem = @[(stackBase - 8'u32, guard), (stackBase, guard)])
  let got = (pc: o.pc, a7: o.a[7], pushed: mem32(stackBase - 4'u32),
             below: mem32(stackBase - 8'u32), at: mem32(stackBase),
             sr: o.sr, fault: o.fault)
  let want = (pc: execBase + 2'u32 + 0x40'u32, a7: stackBase - 4'u32,
              pushed: execBase + 4'u32, below: guard, at: guard,
              sr: allDirty, fault: false)
  check(got == want,
    "bsr.w pushes the address after BOTH words and branches from the first",
    $got, $want)

block:
  # `trap #0` takes vector 32 and writes a two-longword frame. Table 3-1, page
  # 3-13, and Figure 3-7, page 3-13. The vector longword is seeded at 4 * 32.
  let o = runIns([0x4E40'u16], d = trapD,
                 a = [dirtyA, 0, 0, 0, 0, 0, 0, stackBase], sr = allDirty,
                 mem = @[(0x80'u32, 0x00000400'u32),
                         (stackBase - 12'u32, guard), (stackBase, guard)])
  let got = (pc: o.pc, a7: o.a[7], sr: o.sr,
             fv: mem32(stackBase - 8'u32), stackedPc: mem32(stackBase - 4'u32),
             below: mem32(stackBase - 12'u32), at: mem32(stackBase),
             fault: o.fault, halted: o.halted)
  let want = (pc: 0x400'u32, a7: stackBase - 8'u32, sr: allDirty,
              fv: (4'u32 shl 28) or (32'u32 shl 18) or allDirty,
              stackedPc: execBase + 2'u32, below: guard, at: guard,
              fault: false, halted: false)
  check(got == want,
    "trap #0 stacks the format/vector word, the sr and the next pc", $got,
    $want)

# ---------------------------------------------------------------------------
# BLOCK 11. THE ODD CONTROL-TRANSFER TARGET.
#
# "Any attempted execution transferring control to an odd instruction address
# (i.e., if bit 0 of the target address is set) results in an address error
# exception" - MCF5307 User's Manual, section 3.5.2, printed page 3-15. The
# ColdFire Family Programmer's Reference Manual, Rev. 3 does NOT answer this:
# its section 11.1.3 names a table of processor exceptions that the revision
# does not contain, so the vector assignment is all it carries.
#
# A CORE WITHOUT THE CHECK STILL FAULTS, AND THAT IS WHY EVERY CASE HERE
# ASSERTS THE HANDLER AND THE FRAME RATHER THAN A FLAG. An odd program counter
# makes the next fetch read one half of each of two neighbouring words, and
# almost every such word is an encoding this part refuses - so `fault` and
# `halted` come back set, from the WRONG exception, one instruction late, with
# no frame written. A `fault == true` assertion passes on both cores.
#
# THE TARGET IS ODD IN EACH CASE AND THE SAME INSTRUCTION WITH AN EVEN TARGET
# IS ALREADY GREEN ELSEWHERE IN THIS FILE - block 10's two BSR rows and block
# 6's branch rows - so the pair is a known positive beside each negative.
#
# THE STACKED PROGRAM COUNTER IS THE TRANSFERRING INSTRUCTION'S OWN ADDRESS.
# Table 3-1 marks vector 3 `Fault`, and "fault refers to the PC of the
# instruction that caused the exception".
#
# THE FAULT STATUS IS `0100`, "error on instruction fetch", the one code of
# Table 3-3 that names the access this exception refuses to make. FS[3-2] and
# FS[1-0] are not adjacent in the frame word, so `0100` reaches it as
# `1 shl 26` alone.
#
# THE CHECK IS PINNED BY MUTATION AND NOT BY THIS PARAGRAPH.
# `tests/t_claims.cmake` registers
# `address_error_odd_target_suite_t_control`, which takes the odd-target test
# out of `transferControl` and leaves the bare assignment behind. That mutation
# reds exactly six cases of this file, and the seventh - the BSR push read-back
# - stays green, because a core with no check pushes correctly and then
# transfers to the odd address anyway. A row weakened to a flag moves that
# count and the entry refutes; a date beside this paragraph would not.

const
  addressErrorHandler = 0x600'u32
  addressErrorVector = 0x00C'u32   ## 4 * 3
  addressErrorFv =
    (4'u32 shl 28) or (1'u32 shl 26) or (3'u32 shl 18) or allDirty

proc expectAddressError(o: Outcome; frameBase: uint32; label: string) =
  ## The whole machine state after a transfer to an odd address: the handler
  ## entered, the frame written where the stack pointer put it, and the
  ## transferring instruction's address stacked.
  let got = (pc: o.pc, a7: o.a[7], sr: o.sr,
             fv: mem32(frameBase), stackedPc: mem32(frameBase + 4'u32),
             fault: o.fault, halted: o.halted)
  let want = (pc: addressErrorHandler, a7: frameBase, sr: allDirty,
              fv: addressErrorFv, stackedPc: execBase,
              fault: false, halted: false)
  check(got == want, label, $got, $want)

block:
  # `bra.b` with displacement 1: base is the opcode's address plus two, so the
  # target is `execBase + 2 + 1` and odd.
  let o = runIns([0x6001'u16], a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase],
                 sr = allDirty,
                 mem = @[(addressErrorVector, addressErrorHandler)])
  expectAddressError(o, stackBase - 8'u32,
    "bra.b to an odd target takes the address error")

block:
  # The word form reaches the same place through a different displacement
  # path: a core that checked the byte form alone would leave this one silent.
  let o = runIns([0x6000'u16, 0x0101'u16],
                 a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase], sr = allDirty,
                 mem = @[(addressErrorVector, addressErrorHandler)])
  expectAddressError(o, stackBase - 8'u32,
    "bra.w to an odd target takes the address error")

block:
  # `beq.b`, and `allDirty` sets Z, so the branch is TAKEN. A not-taken branch
  # transfers control nowhere and must not fault; block 6 carries those.
  let o = runIns([0x6701'u16], a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase],
                 sr = allDirty,
                 mem = @[(addressErrorVector, addressErrorHandler)])
  expectAddressError(o, stackBase - 8'u32,
    "beq.b taken to an odd target takes the address error")

block:
  # `jmp (%a0)`. The odd address is in the register rather than in the opcode.
  let o = runIns([0x4ED0'u16], a = [0x201'u32, 0, 0, 0, 0, 0, 0, stackBase],
                 sr = allDirty,
                 mem = @[(addressErrorVector, addressErrorHandler)])
  expectAddressError(o, stackBase - 8'u32,
    "jmp to an odd target takes the address error")

block:
  # `rts`. The odd address comes off the stack, and the pop has already moved
  # A7 when the transfer is refused - so the frame lands eight bytes below the
  # POPPED pointer and not below the one the instruction started with.
  let o = runIns([0x4E75'u16],
                 a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase - 4'u32],
                 sr = allDirty,
                 mem = @[(addressErrorVector, addressErrorHandler),
                         (stackBase - 4'u32, 0x301'u32)])
  expectAddressError(o, stackBase - 8'u32,
    "rts to an odd target takes the address error")

block:
  # `bsr.b`. The return address is pushed BEFORE the transfer, so the push
  # stands and the frame goes below it. The pushed value is read back here
  # rather than left to the frame assertion: a BSR that skipped its push and
  # then faulted would put the frame at the same place.
  let o = runIns([0x6101'u16], a = [0'u32, 0, 0, 0, 0, 0, 0, stackBase],
                 sr = allDirty,
                 mem = @[(addressErrorVector, addressErrorHandler)])
  expectAddressError(o, stackBase - 12'u32,
    "bsr.b to an odd target takes the address error below its own push")
  let got = mem32(stackBase - 4'u32)
  let want = execBase + 2'u32
  check(got == want,
    "bsr.b to an odd target has already pushed the return address",
    $got, $want)

# ---------------------------------------------------------------------------

echo ""
# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_control", declaredCaseSites)
echo caseSiteLine("executed", "t_control", executedSites)
echo caseSiteLine("off-green-path", "t_control", declaredOffGreenPathSites)

if failures.len == 0:
  echo "t_control: ", passCount, " cases passed"
  quit(0)
else:
  echo "t_control: ", failures.len, " of ", passCount + failures.len,
       " cases failed"
  for f in failures:
    echo "  FAILED  ", f
  quit(1)
