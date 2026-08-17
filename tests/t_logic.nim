## `t_logic` - the logic, bit-operation and shift instruction group.
##
## WHY THIS FILE EXISTS BESIDE `mcf5307_conformance_logic`. That corpus holds
## POSITIVE cases: an encoding this part has,
## run against an expected register state. A positive corpus CANNOT SEE a
## wrongly-claimed encoding, which produces a passing execution of a DIFFERENT
## instruction, and it cannot see an operand the executor refuses but the
## legality mask admits, because the corpus never offers one. The reason is
## structural rather than a gap that more cases would close.
##
## THE ENCODINGS THE
## assembler refuses to emit are built from a MEASURED base word by replacing
## the low six bits, which is the effective-address field: `bset %d1,%d0` is
## `03c0`, so `bset %d1,(4,%pc)` is `03c0 or 3a` = `03fa`. That method is
## cross-checked by the two words the assembler DOES emit: `btst %d1,%d0` is
## `0300`, and `0300 or 3a` and `0300 or 3c` are `033a` and `033c`, which are
## exactly what the assembler produced for `btst %d1,(4,%pc)` and
## `btst %d1,#5`.
##
## `btst %d1,#5` IS THE FORM WHERE THIS FILE CONTRADICTS THE ASSEMBLER. The
## assembler ACCEPTS that form and emits
## `033c 0005`, and this file asserts that the core TRAPS it. It is
## deliberate, and the manual rows that put it there are on `eaBitDynamic` in
## `decode_types.nim`. It is uncertainty 3 in the `logic.nim` header.
##
## THE PC-RELATIVE BASE IS THE ADDRESS OF THE DISPLACEMENT WORD. `btst
## %d1,(target,%pc)` with the opcode at 0 assembles to `033a 0004` and places
## `target` at 6, so the base is 2 and not 4, and
## `m68k-elf-objdump -m m68k:5307` prints `btst %d1,%pc@(6 <target>)`.
## `eaAddr` takes the base before `fetchExt` advances the counter.
##
## So the cases below do not seed the same byte across both candidate
## addresses. `pcWindow` gives the byte at the CORRECT address bit 7 set and
## bit 6 clear, and the byte at the address the old base reached the opposite
## pair, so each Z assertion separates the two bases. The exact addresses are
## on `pcWindow` itself.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Instruction
## semantics, the condition-code rules and the encodings are facts about
## Motorola silicon; they are taken from the ColdFire Family Programmer's
## Reference Manual and the MCF5307 User's Manual and
## from this project's own measurements with the pinned cross assembler.

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
# The board. One flat byte array, big-endian, exactly as `t_alu`'s board and
# the conformance runner's. A read outside it reports `busUnmapped`.

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
# The runner. It is `t_alu`'s, for the reason that file gives: a pass here has
# to be a pass of the SHIPPED path - `mcf5307_reset`, `mcf5307_set_reg`,
# `mcf5307_exec`, `mcf5307_get_reg` - and not of an internal helper reached
# around the back.

const
  execBase = 0x100'u32     ## where the instruction words are placed
  stackBase = 0x800'u32
  srBase = 0x2700'u32      ## the reset status register, CCR all clear
  zero8: array[8, uint32] = [0'u32, 0, 0, 0, 0, 0, 0, 0]

type Outcome = object
  cycles: uint32
    ## `mcf5307_exec(ctx, 1)`'s RETURN, WHICH IS NOT A CYCLE COUNT despite the
    ## name. `mcf5307_exec` saturates at its budget, and every instruction in
    ## this group costs 2 for the fetch plus at least one more, so the value is
    ## 1 for an instruction that ran and 0 for one that trapped. Uncertainty 2
    ## in the `logic.nim` header says nothing asserts the cycle counts.
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
  # write would be overwritten and every case that asserts an untouched
  # condition code would silently run with a clear one.
  discard mcf5307_set_reg(ctx, 16, sr)

  # ONE INSTRUCTION, AND THE BUDGET IS WHAT STOPS THE LOOP AFTER IT, exactly as
  # in `t_alu`: the memory after the encoding is zero and `0x0000` is not an
  # instruction this part has. The return is 1 for an instruction that ran and
  # 0 for one that trapped.
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

# ---------------------------------------------------------------------------
# THE PC-RELATIVE WINDOW, AND THE ADDRESSES IT PINS.
#
# Every PC-relative case in this file places its opcode at `execBase` (0x100)
# and its extension word at 0x102, so:
#
#   `btst %d1,(4,%pc)`      (`033a 0004`)  reads the BYTE at 0x106
#   `btst %d1,(4,%pc,%d2)`  (`033b 2804`)  reads the BYTE at 0x106 + d2
#   `and.l (4,%pc),%d1`     (`c2ba 0004`)  reads the LONGWORD at 0x106
#
# and a core that based the address AFTER the extension word reads two bytes
# higher in each.
#
# THE WINDOW IS NON-UNIFORM ON PURPOSE.
# The bytes it puts at the addresses these cases can reach are:
#
#   0x106  0x80   bit 7 SET,   bit 6 CLEAR   the (4,%pc) operand
#   0x108  0x40   bit 7 CLEAR, bit 6 SET     where the old base read instead
#   0x10a  0x80   bit 7 SET,   bit 6 CLEAR   the (4,%pc,%d2) operand, d2 = 4
#   0x10c  0x40   bit 7 CLEAR, bit 6 SET     where the old base read instead
#
# THE INDEX WIDTH IS NOT SEPARABLE ON THIS BOARD. `033b 2804` selects a
# LONG index at bit 11 of its extension word, and a core reading that select at
# bit 8 would narrow the index to its low word and sign-extend it. The two
# readings agree on every value this board can hold: separating them needs an
# index whose low word sign-extends to something the whole longword is not,
# which is at least 0x10000 away from its other reading, and this board is
# 0x1000 bytes.
const pcWindow = @[(0x104'u32, 0xAABB80C3'u32),
                   (0x108'u32, 0x40558022'u32),
                   (0x10C'u32, 0x40AABBCC'u32)]

# The assertions.

proc expectD(o: Outcome; n: int; want: uint32; wantSr: uint32; label: string) =
  let got = (reg: o.d[n], sr: o.sr, fault: o.fault)
  let wanted = (reg: want, sr: wantSr, fault: false)
  check(got == wanted, label, $got, $wanted)

proc expectTrapD(o: Outcome; n: int; unchanged: uint32; label: string) =
  ## An encoding the part does not have, or an operand the opcode may not
  ## reach. It must halt with `fault`, return no cycles, and leave the
  ## destination register alone.
  ##
  ## `unchanged` IS SEEDED NON-ZERO BY EVERY CALLER. A trap case whose
  ## register starts at zero asserts 0 == 0 in this half and would pass
  ## against a core that wrote a zero into it.
  let got = (reg: o.d[n], fault: o.fault, halted: o.halted, cycles: o.cycles)
  let wanted = (reg: unchanged, fault: true, halted: true, cycles: 0'u32)
  check(got == wanted, label, $got, $wanted)

proc expectTrapA(o: Outcome; n: int; unchanged: uint32; label: string) =
  ## The address-register twin of `expectTrapD`, for a case whose operand IS
  ## an address register. `eaResolve` answers `erAn` for that operand and
  ## `eaRefWrite` puts the result INTO the register, so the register a removed
  ## mask would disturb is an A and not a D.
  let got = (reg: o.a[n], fault: o.fault, halted: o.halted, cycles: o.cycles)
  let wanted = (reg: unchanged, fault: true, halted: true, cycles: 0'u32)
  check(got == wanted, label, $got, $wanted)

proc freshCtx(): MCF5307Ctx =
  ## A context reset onto a cleared board. It serves the assertions that call
  ## a `machine.nim` procedure DIRECTLY; every instruction case goes through
  ## `runIns` and the shipped path instead.
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  result = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(result, stackBase, execBase)

proc expectUnresolvable(sub: EA7; label: string) =
  ## `eaResolve` must refuse this mode-7 sub-variant: no usable reference, and
  ## the context halted with `fault`.
  let ctx = freshCtx()
  let r = eaResolve(ctx, EA(mode: eaMode7, reg: uint8(ord(sub))), 4)
  let got = (kind: r.kind, fault: ctx.fault, halted: ctx.halted)
  let wanted = (kind: erNone, fault: true, halted: true)
  check(got == wanted, label, $got, $wanted)
  mcf5307_destroy(ctx)

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
# The dirty condition codes a bit operation must carry through untouched. A bit
# operation writes Z ALONE, so N, V, C
# and X are set on entry and asserted unchanged on exit.
const bitDirty = srBase or ccrN or ccrV or ccrC or ccrX

# ---------------------------------------------------------------------------
# BLOCKING 1. `CMP` AND `CMPA.L` ARE NOT THIS GROUP'S.
#
# Line 1011 carries EOR in opmodes 100, 101 and 110. The remaining opmodes are
# the comparison group's: CMP in 000, 001 and 010, CMPA.W in 011 and CMPA.L
# in 111.
#
# THE SENTENCE THESE ROWS ASSERT: the encoding belongs to the comparison group
# and not to the logic decoder.
#
# `cmpa.l %d0,%a1` is `b3c0`, assembled by `m68k-elf-as -mcpu=5307`.
#
# OPMODE 111 IS CMPA.L BECAUSE THE ASSEMBLER PUT IT THERE, AND NOT BY ANY
# INFERENCE FROM `cmpa.w`. `b3c0` is what `m68k-elf-as -mcpu=5307` emitted for
# `cmpa.l %d0,%a1`, and `(0xb3c0 shr 6) and 7` is 111. That is the whole
# argument and it needs no second measurement.
#
# `m68k-elf-as -mcpu=5307` does also reject `cmpa.w %d0,%a1` ("needs 68000 or
# higher"), which is a fact about OPMODE 011, where CMPA.W lives, and carries
# no conclusion about opmode 111.

block:
  expectDecode(0xB3C0'u16, opCmpa,
    "cmpa.l %d0,%a1 (b3c0) is CPU-10's CMPA and not this group's EOR")
  expectDecode(0xB280'u16, opCmp,
    "cmp.l %d0,%d1 (b280) is CPU-10's CMP and not this group's EOR")

  # THE POSITIVE CONTROLS. The byte and word EOR opmodes are not instructions
  # on this part and they trap on the SIZE, which is the channel
  # `decodeLogicLine` uses.
  expectDecode(0xB380'u16, opEor, "eor.l %d1,%d0 (b380) is still an EOR")
  expectDecode(0xB300'u16, opEor, "the byte EOR opmode (b300) is still an EOR")
  expectDecode(0xB340'u16, opEor, "the word EOR opmode (b340) is still an EOR")

  # AND THE EXECUTION.
  #
  # `cmpa.l %d0,%a1` computes a1 - d0 and DISCARDS it: 0x11223344 - 0x0f0f0f0f
  # is 0x02132435, which is non-zero, positive and borrows nothing, and
  # 0x0f0f0f0f and 0x11223344 are both positive so no signed overflow is
  # possible. The incoming `sr` is the reset word, so the whole 16-bit result
  # is 0x2700.
  let o = runIns([0xB3C0'u16],
                 d = [0x0F0F0F0F'u32, 0x12345678'u32, 0, 0, 0, 0, 0, 0],
                 a = [0'u32, 0x11223344'u32, 0, 0, 0, 0, 0, 0])
  let got = (d0: o.d[0], d1: o.d[1], a1: o.a[1], sr: o.sr,
             fault: o.fault, halted: o.halted, cycles: o.cycles)
  let want = (d0: 0x0F0F0F0F'u32, d1: 0x12345678'u32, a1: 0x11223344'u32,
              sr: srBase, fault: false, halted: false, cycles: 1'u32)
  check(got == want,
    "cmpa.l %d0,%a1 compares and writes no register",
    $got, $want)

# ---------------------------------------------------------------------------
# BLOCKING 2. A DYNAMIC `BTST` REACHES EVERY OPERAND ITS MASK ADMITS, AND THE
# MASK STOPS AT THE IMMEDIATE.
#
# `eaLegalityFor(opBtst)` is `eaBitDynamic`: the manual's DATA class WITHOUT
# the immediate. BTST NEVER WRITES, so it must read the two PC-relative
# sub-variants through `eaRead`; `eaResolve` serves `AbsW` and `AbsL` alone
# and faults on the rest, which is correct for the operations that WRITE and
# wrong for this one.
#
# `btst %d1,(4,%pc)` is `033a 0004` and `btst %d1,(4,%pc,%d2)` is `033b 2804`,
# both assembled by `m68k-elf-as -mcpu=5307`.
#
# WHY THE IMMEDIATE IS OUT, AND WHY THE ASSEMBLER DOES NOT SETTLE IT. See the
# `eaBitDynamic` doc comment in `decode_types.nim`. The short form: the timing
# table dashes the `#xxx` column of the `btst Dy,<ea>` row, and that dash is
# the same mark the table uses for every form this part does not have.
# `m68k-elf-as -mcpu=5307` does assemble `btst %d1,#5` as `033c 0005`, and
# that acceptance is byte-for-byte the plain-68000 one - the assembler
# narrows the STATIC bit-operation modes for ColdFire and leaves this form
# untouched - so it measures the 68000 rule and not this part.

block:
  # THE IMMEDIATE OPERAND TRAPS. `033c 0005` is the word the assembler emits
  # for `btst %d1,#5`; d1 is seeded non-zero so the "unchanged" half is an
  # assertion and not `0 == 0`.
  expectTrapD(runIns([0x033C'u16, 0x0005'u16],
                     d = [0'u32, 3, 0, 0, 0, 0, 0, 0], sr = bitDirty),
    1, 3'u32,
    "btst %d1,#5 traps: the immediate is not a dynamic BTST operand")

block:
  # The PC-relative operand, AND THE EXACT ADDRESS IT MUST REACH. `pcWindow`
  # puts 0x80 at 0x106 - the byte `(4,%pc)` names - and 0x40 at 0x108, where
  # a base taken after the extension word reads instead. See `pcWindow`.
  let oSet = runIns([0x033A'u16, 0x0004'u16],
                    d = [0'u32, 7, 0, 0, 0, 0, 0, 0], sr = bitDirty or ccrZ,
                    mem = pcWindow)
  let gotSet = (d1: oSet.d[1], mem: mem32(0x104'u32), mem2: mem32(0x108'u32),
                sr: oSet.sr, fault: oSet.fault, cycles: oSet.cycles)
  let wantSet = (d1: 7'u32, mem: 0xAABB80C3'u32, mem2: 0x40558022'u32,
                 sr: bitDirty, fault: false, cycles: 1'u32)
  check(gotSet == wantSet,
    "btst %d1,(4,%pc) reads the byte at 0x106, finds bit 7 set, " &
    "clears Z and writes nothing",
    $gotSet, $wantSet)

  let oClear = runIns([0x033A'u16, 0x0004'u16],
                      d = [0'u32, 6, 0, 0, 0, 0, 0, 0], sr = bitDirty,
                      mem = pcWindow)
  let gotClear = (d1: oClear.d[1], mem: mem32(0x104'u32), sr: oClear.sr,
                  fault: oClear.fault, cycles: oClear.cycles)
  let wantClear = (d1: 6'u32, mem: 0xAABB80C3'u32, sr: bitDirty or ccrZ,
                   fault: false, cycles: 1'u32)
  check(gotClear == wantClear,
    "btst %d1,(4,%pc) with a bit number of 6 finds a clear bit at 0x106 " &
    "and sets Z",
    $gotClear, $wantClear)

  # An asserted table entry that no case executes is a claim about the table
  # and not about the core, so here is the case.
  # `btst %d1,(4,%pc,%d2)` is `033b 2804`, assembled by `m68k-elf-as
  # -mcpu=5307`.
  #
  # With d2 = 4 the operand is the byte at 0x10a, which `pcWindow` seeds 0x80.
  let oIndex = runIns([0x033B'u16, 0x2804'u16],
                      d = [0'u32, 7, 4, 0, 0, 0, 0, 0], sr = bitDirty or ccrZ,
                      mem = pcWindow)
  let gotIndex = (d1: oIndex.d[1], d2: oIndex.d[2], mem: mem32(0x108'u32),
                  sr: oIndex.sr, fault: oIndex.fault, cycles: oIndex.cycles)
  let wantIndex = (d1: 7'u32, d2: 4'u32, mem: 0x40558022'u32, sr: bitDirty,
                   fault: false, cycles: 1'u32)
  check(gotIndex == wantIndex,
    "btst %d1,(4,%pc,%d2) reads the byte at 0x10a, finds bit 7 set, " &
    "clears Z and writes nothing",
    $gotIndex, $wantIndex)

block:
  # THE WIDENING IS BTST'S ALONE. `BSET`, `BCLR` and `BCHG` WRITE their
  # operand, so a PC-relative or an immediate destination stays refused. Each
  # of the words below is the measured base word with the low six bits
  # replaced: `bset %d1,%d0` is `03c0`, `bclr %d1,%d0` is `0380` and
  # `bchg %d1,%d0` is `0340`. `m68k-elf-as -mcpu=5307` rejects every one of
  # `bset %d1,(4,%pc)`, `bset %d1,#5`, `bclr %d1,(4,%pc)` and `bchg %d1,#5`.
  let d1only = [0'u32, 3'u32, 0, 0, 0, 0, 0, 0]
  expectTrapD(runIns([0x03FA'u16, 0x0004'u16], d = d1only), 1, 3'u32,
    "bset %d1,(4,%pc) still traps")
  expectTrapD(runIns([0x03FC'u16, 0x0005'u16], d = d1only), 1, 3'u32,
    "bset %d1,#5 still traps")
  expectTrapD(runIns([0x03BA'u16, 0x0004'u16], d = d1only), 1, 3'u32,
    "bclr %d1,(4,%pc) still traps")
  expectTrapD(runIns([0x037C'u16, 0x0005'u16], d = d1only), 1, 3'u32,
    "bchg %d1,#5 still traps")

  # AND THE OPERAND THE MASK REFUSES ON ITS OWN. `eaResolve` RESOLVES AN
  # ADDRESS REGISTER - it answers `erAn`, and `eaRefWrite` puts the result
  # INTO that register - so nothing under the executor stops these.
  #
  # `m68k-elf-as -mcpu=5307` rejects `bset %d1,%a0`, `bclr %d1,%a0` and
  # `bchg %d1,%a0`; each word is the measured base word with the low six bits
  # replaced by `%a0`, which is 001 000: `03c8`, `0388` and `0348`. a0 is
  # seeded non-zero, so "the register it must not have changed" is an
  # assertion and not `0 == 0`.
  let a0only = [0x1234'u32, 0, 0, 0, 0, 0, 0, 0]
  expectTrapA(runIns([0x03C8'u16], d = d1only, a = a0only), 0, 0x1234'u32,
    "bset %d1,%a0 traps: An is not data alterable")
  expectTrapA(runIns([0x0388'u16], d = d1only, a = a0only), 0, 0x1234'u32,
    "bclr %d1,%a0 traps: An is not data alterable")
  expectTrapA(runIns([0x0348'u16], d = d1only, a = a0only), 0, 0x1234'u32,
    "bchg %d1,%a0 traps: An is not data alterable")

  # THE POSITIVE CONTROL FOR THE WRITING BIT OPERATIONS.
  # `bset %d1,%d0` is `03c0`; d0 starts at 0 and bit 3 is set, so Z takes the
  # complement of the bit AS IT WAS FOUND and is set.
  expectD(runIns([0x03C0'u16], d = [0'u32, 3, 0, 0, 0, 0, 0, 0],
                 sr = bitDirty),
    0, 0x00000008'u32, bitDirty or ccrZ,
    "bset %d1,%d0 sets the bit and reports the bit it found in Z")

# ---------------------------------------------------------------------------
# `eaResolve` STAYS NARROW.
#
# `logic.nim` says of the BTST repair "THE FIX IS HERE AND NOT IN
# `eaResolve`", because widening that procedure would let a WRITE reach a
# PC-relative or an immediate operand and it has callers outside this module.
#
# THEY HAVE TO BE DIRECT. Every writing path in `logic.nim` - the
# `Dn op <ea> -> <ea>` direction of AND and OR, EOR, and BSET, BCLR and BCHG -
# checks a mask that already excludes these three sub-variants BEFORE it calls
# `eaResolve`, so a widened `eaResolve` changes the behaviour of no
# instruction this group executes.

block:
  expectUnresolvable(ea7PCDisp,
    "eaResolve refuses a (d16,PC) destination and halts with fault")
  expectUnresolvable(ea7PCIndex,
    "eaResolve refuses a (d8,PC,Xn) destination and halts with fault")
  expectUnresolvable(ea7Imm,
    "eaResolve refuses an immediate destination and halts with fault")

# ---------------------------------------------------------------------------
# `eaBitStatic` - THE STATIC BIT OPERATION'S OPERAND IS NARROWER THAN THE
# DYNAMIC ONE, and this is the mask that says so.
#
# Measured: `m68k-elf-as -mcpu=5307` accepts `btst #3,(%a0)` (`0810 0003`) and
# rejects `btst #3,(4,%pc)` and `btst #3,0x1234.w`. The two rejected words are
# `0800` (the measured `btst #3,%d0`) with the low six bits replaced: `083a`
# and `0838`.

block:
  # The mask, read directly. A negative case AND a positive control for each
  # end of it, because a mask that rejected everything would report every
  # negative case as a pass.
  checkMask(isEaLegal(eaBitStatic, decodeEa(0x00'u16)), true,
    "the static bit-operation mask admits Dn")
  checkMask(isEaLegal(eaBitStatic, decodeEa(0x10'u16)), true,
    "the static bit-operation mask admits (An)")
  checkMask(isEaLegal(eaBitStatic, decodeEa(0x18'u16)), true,
    "the static bit-operation mask admits (An)+")
  checkMask(isEaLegal(eaBitStatic, decodeEa(0x28'u16)), true,
    "the static bit-operation mask admits (d16,An)")
  checkMask(isEaLegal(eaBitStatic, decodeEa(0x08'u16)), false,
    "the static bit-operation mask rejects An")
  checkMask(isEaLegal(eaBitStatic, decodeEa(0x38'u16)), false,
    "the static bit-operation mask rejects an absolute short operand")
  checkMask(isEaLegal(eaBitStatic, decodeEa(0x3A'u16)), false,
    "the static bit-operation mask rejects (d16,PC)")
  checkMask(isEaLegal(eaBitStatic, decodeEa(0x3C'u16)), false,
    "the static bit-operation mask rejects an immediate")

  # And through the executor. `btst #3,(%a0)` reads ONE BYTE - a memory
  # operand of a bit operation is 8 bits wide - so the byte at 0x200 is 0x08,
  # whose bit 3 is set, and Z is cleared. The bytes beside it are given
  # distinct values and asserted unchanged.
  let o = runIns([0x0810'u16, 0x0003'u16],
                 a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0],
                 sr = bitDirty or ccrZ,
                 mem = @[(0x200'u32, 0x08AABBCC'u32)])
  let got = (mem: mem32(0x200'u32), a0: o.a[0], sr: o.sr, fault: o.fault,
             cycles: o.cycles)
  let want = (mem: 0x08AABBCC'u32, a0: 0x200'u32, sr: bitDirty, fault: false,
              cycles: 1'u32)
  check(got == want,
    "btst #3,(%a0) reads one byte, clears Z, and disturbs no neighbour",
    $got, $want)

  # The encodings the static form may not reach.
  #
  # EACH OPERAND IS AN ADDRESS THE BOARD ANSWERS, so the mask is the only
  # thing that can refuse it. An address off the board traps on `busUnmapped`
  # whatever the mask says, and 0x200 is on this board.
  #
  # d0 IS SEEDED NON-ZERO in both.
  let dSeed = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0]
  expectTrapD(runIns([0x083A'u16, 0x0003'u16, 0x0004'u16], d = dSeed),
    0, 0x12345678'u32,
    "btst #3,(4,%pc) traps: the static form reaches no PC-relative operand")
  expectTrapD(runIns([0x0838'u16, 0x0003'u16, 0x0200'u16], d = dSeed),
    0, 0x12345678'u32,
    "btst #3,0x200.w traps: the static form reaches no absolute operand")

# ---------------------------------------------------------------------------
# `eaDataAddressing` - THE MANUAL'S `DATA` CLASS, WHICH DOES NOT INCLUDE `An`.
# It is the source mask of the `<ea> op Dn -> Dn` direction of AND and OR, and
# THOSE TWO ONLY. Both READ and neither writes, so the PC-relative pair and
# the immediate are in and the address register is out. The `and.l <ea>,Rx` and
# `or.l <ea>,Rx` rows of the timing table carry a time in every column
# including `#xxx`.
#
# Measured: `m68k-elf-as -mcpu=5307` accepts `and.l (4,%pc),%d1` (`c2ba 0004`)
# and rejects `and.l %a0,%d1`; `c0bc 0000 0005` disassembles as `andl #5,%d0`
# on `m68k-elf-objdump -m m68k:5307`.

block:
  checkMask(isEaLegal(eaDataAddressing, decodeEa(0x00'u16)), true,
    "the data-addressing mask admits Dn")
  checkMask(isEaLegal(eaDataAddressing, decodeEa(0x08'u16)), false,
    "the data-addressing mask rejects An")
  checkMask(isEaLegal(eaDataAddressing, decodeEa(0x3A'u16)), true,
    "the data-addressing mask admits (d16,PC)")
  checkMask(isEaLegal(eaDataAddressing, decodeEa(0x3B'u16)), true,
    "the data-addressing mask admits (d8,PC,Xn)")
  checkMask(isEaLegal(eaDataAddressing, decodeEa(0x3C'u16)), true,
    "the data-addressing mask admits an immediate")
  checkMask(isEaLegal(eaDataAddressing, decodeEa(0x3D'u16)), false,
    "the data-addressing mask rejects the reserved mode-7 encoding")

  # THE DYNAMIC BIT OPERATION'S MASK IS `eaBitDynamic`. These rows read
  # `eaLegalityFor` through `eaIsLegalFor`, which is the call `execBitOp`
  # makes.
  checkMask(eaIsLegalFor(opBtst, decodeEa(0x3A'u16)), true,
    "the BTST mask admits (d16,PC)")
  checkMask(eaIsLegalFor(opBtst, decodeEa(0x3B'u16)), true,
    "the BTST mask admits (d8,PC,Xn)")
  checkMask(eaIsLegalFor(opBtst, decodeEa(0x3C'u16)), false,
    "the BTST mask rejects an immediate")
  checkMask(eaIsLegalFor(opBtst, decodeEa(0x08'u16)), false,
    "the BTST mask rejects An")

  # THE THREE BIT OPERATIONS THAT WRITE CARRY A NARROWER MASK, which is the
  # asymmetry the executor has to honour.
  for (opx, name) in [(opBset, "BSET"), (opBclr, "BCLR"), (opBchg, "BCHG")]:
    checkMask(eaIsLegalFor(opx, decodeEa(0x00'u16)), true,
      "the " & name & " mask admits Dn")
    checkMask(eaIsLegalFor(opx, decodeEa(0x3A'u16)), false,
      "the " & name & " mask rejects (d16,PC)")
    checkMask(eaIsLegalFor(opx, decodeEa(0x3C'u16)), false,
      "the " & name & " mask rejects an immediate")

  # And through the executor, both ends.
  #
  # THE POSITIVE CONTROL IS THE PC-RELATIVE SOURCE AND NOT AN IMMEDIATE ONE.
  # `m68k-elf-as -mcpu=5307` assembles `and.l #0x0f0f0f0f,%d1` as ANDI
  # (`0281 0f0f 0f0f`) and never emits the `and.l <ea>,Dn` form with an
  # immediate effective address, so that word is not a measured encoding and
  # is not asserted here. `and.l (4,%pc),%d1` IS one: `c2ba 0004`.
  #
  # THE SOURCE IS THE LONGWORD AT 0x106, which `pcWindow` seeds 0x80c34055.
  #
  #   0x12345678 and 0x80c34055 = 0x00004050
  expectD(runIns([0xC2BA'u16, 0x0004'u16],
                 d = [0'u32, 0x12345678'u32, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrX,
                 mem = pcWindow),
    1, 0x00004050'u32, srBase or ccrX,
    "and.l (4,%pc),%d1 reads the longword at 0x106 and leaves X alone")
  expectTrapD(runIns([0xC288'u16],
                     d = [0'u32, 0x12345678'u32, 0, 0, 0, 0, 0, 0],
                     a = [0x1234'u32, 0, 0, 0, 0, 0, 0, 0]),
    1, 0x12345678'u32, "and.l %a0,%d1 traps: An is not a data-addressing mode")

# ---------------------------------------------------------------------------
# THE `{eaDn}` ARM. Every shift on this part is register-only, and the four
# immediate-logic and NOT opcodes reach a data register and nothing else. The
# entry in `eaLegalityFor` that names all eight of them is one `EaLegality`
# whose modes are `{eaDn}` and whose mode-7 set is empty.
#
# THE SHIFT'S REGISTER FORM CANNOT VIOLATE THAT MASK - `decodeShift` builds its
# operand as `EA(mode: eaDn, ...)` and never asks `decodeEa`. The MEMORY form
# is what carries an effective address, and it is the case below. Measured:
# `m68k-elf-as -mcpu=5307` rejects `asl.w (%a0)`, `asr.w (%a0)`, `lsl.w (%a0)`
# and `lsr.w (%a0)`; the words are the `1110 0tt d 11 <ea>` encoding with
# `<ea>` = `(a0)` = 010 000.

block:
  checkMask(eaIsLegalFor(opAsl, decodeEa(0x00'u16)), true,
    "the shift mask admits Dn")
  checkMask(eaIsLegalFor(opAsl, decodeEa(0x10'u16)), false,
    "the shift mask rejects (An)")
  checkMask(eaIsLegalFor(opAsl, decodeEa(0x08'u16)), false,
    "the shift mask rejects An")
  checkMask(eaIsLegalFor(opAsl, decodeEa(0x3C'u16)), false,
    "the shift mask rejects an immediate")

  # ONE ILLEGAL MODE PER SHIFT OPERATION. The memory form is the encoding that
  # carries an effective address at all.
  #
  # THEY DO NOT ATTRIBUTE THE REFUSAL TO THE MASK. `decodeShift` gives the
  # memory form `size: 2`, so `execShift`'s guards - the `{eaDn}` mask and the
  # long-size rule - each refuse it ON THEIR OWN.
  expectTrapD(runIns([0xE1D0'u16], d = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0],
                     a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0]), 0, 0x12345678'u32,
    "the memory form of asl traps")
  expectTrapD(runIns([0xE0D0'u16], d = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0],
                     a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0]), 0, 0x12345678'u32,
    "the memory form of asr traps")
  expectTrapD(runIns([0xE3D0'u16], d = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0],
                     a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0]), 0, 0x12345678'u32,
    "the memory form of lsl traps")
  expectTrapD(runIns([0xE2D0'u16], d = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0],
                     a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0]), 0, 0x12345678'u32,
    "the memory form of lsr traps")

  # THE POSITIVE CONTROLS. Each word is the
  # assembler's: `asl.l #1,%d0` is `e380`, `asr.l #1,%d0` is `e280`,
  # `lsl.l #1,%d0` is `e388` and `lsr.l #1,%d0` is `e288`.
  #
  # X AND C BOTH TAKE THE LAST BIT SHIFTED OUT, so each case starts with a
  # dirty X and asserts the value the shift put there rather than the value it
  # inherited.
  # ASL LEAVES V CLEAR EVEN HERE, where the sign leaves the word and the 68K
  # rule would set it: on this family V is always cleared by ASL and ASR. The
  # case enters with V SET.
  expectD(runIns([0xE380'u16], d = [0x80000000'u32, 0, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrV),
    0, 0'u32, srBase or ccrC or ccrX or ccrZ,
    "asl.l #1 of 0x80000000 shifts the sign out into C and X, sets Z and " &
    "CLEARS V")
  expectD(runIns([0xE280'u16], d = [0x80000000'u32, 0, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrX),
    0, 0xC0000000'u32, srBase or ccrN,
    "asr.l #1 replicates the sign, and a zero carry clears X")
  expectD(runIns([0xE388'u16], d = [1'u32, 0, 0, 0, 0, 0, 0, 0],
                 sr = srBase or ccrX),
    0, 2'u32, srBase, "lsl.l #1 of 1 is 2, and a zero carry clears X")
  expectD(runIns([0xE288'u16], d = [3'u32, 0, 0, 0, 0, 0, 0, 0],
                 sr = srBase),
    0, 1'u32, srBase or ccrC or ccrX,
    "lsr.l #1 of 3 is 1 with the low bit in C and X")

# ---------------------------------------------------------------------------
# ONE ILLEGAL MODE PER REMAINING NEW OPERATION: EOR, ANDI, ORI and EORI.
#
# Every word below was offered to `m68k-elf-as -mcpu=5307` and REJECTED, and
# each is a measured base word with the low six bits replaced:
# `eor.l %d1,%d0` is `b380`, `andi.l #5,%d0` is `0280`, `ori.l #5,%d0` is
# `0080` and `eori.l #5,%d0` is `0a80`.

block:
  let two = [0x12345678'u32, 0x0F0F0F0F'u32, 0, 0, 0, 0, 0, 0]

  # EOR writes its effective address, so the class is DATA ALTERABLE: no
  # PC-relative operand and no address register.
  expectTrapD(runIns([0xB3BA'u16, 0x0004'u16], d = two), 0, 0x12345678'u32,
    "eor.l %d1,(4,%pc) traps: an EOR destination is not PC-relative")
  expectTrapA(runIns([0xB388'u16], d = two,
                     a = [0x1234'u32, 0, 0, 0, 0, 0, 0, 0]), 0, 0x1234'u32,
    "eor.l %d1,%a0 traps: An is not data alterable")

  # ANDI, ORI and EORI reach a data register and nothing else. The trap comes
  # BEFORE the immediate is fetched, which is why the extension words below
  # are present and never consumed.
  expectTrapD(runIns([0x0290'u16, 0x0000'u16, 0x0005'u16], d = two,
                     a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0]), 0, 0x12345678'u32,
    "andi.l #5,(%a0) traps: the destination is a data register only")
  expectTrapD(runIns([0x0090'u16, 0x0000'u16, 0x0005'u16], d = two,
                     a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0]), 0, 0x12345678'u32,
    "ori.l #5,(%a0) traps: the destination is a data register only")
  expectTrapD(runIns([0x0A90'u16, 0x0000'u16, 0x0005'u16], d = two,
                     a = [0x200'u32, 0, 0, 0, 0, 0, 0, 0]), 0, 0x12345678'u32,
    "eori.l #5,(%a0) traps: the destination is a data register only")

  # THE POSITIVE CONTROLS for the same four operations, each the assembler's
  # own word.
  expectD(runIns([0xB380'u16], d = two, sr = srBase or ccrX or ccrC or ccrV),
    0, 0x1D3B5977'u32, srBase or ccrX,
    "eor.l %d1,%d0 combines the two registers, clears V and C, and keeps X")
  expectD(runIns([0x0280'u16, 0x0000'u16, 0x0005'u16], d = two),
    0, 0x00000000'u32, srBase or ccrZ, "andi.l #5,%d0 = 0 and sets Z")
  expectD(runIns([0x0080'u16, 0x0000'u16, 0x0005'u16], d = two),
    0, 0x1234567D'u32, srBase, "ori.l #5,%d0 sets the two low bits")
  # THE EORI CONTROL USES A DIFFERENT IMMEDIATE FROM THE ORI ONE ON PURPOSE.
  # `0x12345678 or 5` and `0x12345678 xor 5` are the same word.
  # `eori.l #0xf,%d0` is `0a80 0000 000f`, and 0x78 xor 0x0f is 0x77 where
  # 0x78 or 0x0f is 0x7f.
  expectD(runIns([0x0A80'u16, 0x0000'u16, 0x000F'u16], d = two),
    0, 0x12345677'u32, srBase, "eori.l #0xf,%d0 flips the low four bits")

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_logic", declaredCaseSites)
echo caseSiteLine("executed", "t_logic", executedSites)
echo caseSiteLine("off-green-path", "t_logic", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_logic: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_logic: ", passCount, " cases passed"
