## `t_logic` - the logic, bit-operation and shift instruction group.
##
## Why this file exists beside `mcf5307_conformance_logic`. Every case in that
## corpus is a positive case: an encoding this part has, run against an
## expected register state. A positive corpus cannot see either of the two
## defects this file was written to catch, and the reason is structural rather
## than a gap that more cases would close.
##
##   DESIGN SECTION 6.1 is section 6 "The MCF5307 Core and the Board Model",
##   subsection 6.1 "The core", of the NMG2 emulator DESIGN DOCUMENT
##   (`2026-08-04-nmg2-emulator-design.md`, in the nord-modular-emulator plan
##   set). Opened and checked: it is the section that makes the legality mask a
##   MANDATORY property of this core - "Each opcode carries its own legality
##   mask. An illegal mode traps." - and it is the section that sizes the core
##   and forbids a Musashi fork.
##
##   AGENTS.MD SECTION 11 is section 11 "External resources" of the
##   nord-modular-emulator project's `AGENTS.md`. Opened and checked: it is the
##   section that names the two Motorola documents this file takes instruction
##   semantics from - the ColdFire Family Programmer's Reference Manual Rev 3
##   and the MCF5307 User's Manual - and gives a download location for each.
##
##   ONE OF THE TWO IS OBTAINABLE AND ONE IS NOT, AND AN EARLIER REVISION OF
##   THIS PARAGRAPH SAID NEITHER WAS. That was false, it was never searched
##   for, and it is the sentence that told the next reader not to look for a
##   document that was in fact at hand.
##
##   THE MCF5307 USER'S MANUAL is the one that was found, and it is the
##   document every table and page cited below refers to. Its full identity,
##   so that a reader can be sure of holding the same edition: Motorola,
##   "MCF5307 ColdFire Integrated Microprocessor User's Manual", order number
##   MCF5307UM/AD, (c) 1998 - the order number is printed at the top right of
##   the cover and the title is the title page. IT IS NOT IN THIS REPOSITORY,
##   it may not be copied into it, and a reader who has only this tree must
##   obtain it separately from the download location AGENTS.md section 11
##   gives. That is why every citation here names table, page and row instead
##   of quoting.
##
##   THE COLDFIRE FAMILY PROGRAMMER'S REFERENCE MANUAL IS GENUINELY ABSENT -
##   searched for by name and by content across the scratchpad, and the
##   network is closed - and it is the document that would settle FIVE OF THE
##   SIX uncertainties the `logic.nim` header declares: numbers 1, 2, 4, 5 and
##   6, which is the list that header itself gives. Number 3, the exact cycle
##   count, is not one of them - it needs the clock work of AGENTS.md open
##   question 6. AN EARLIER REVISION OF THIS PARAGRAPH SAID "the four
##   uncertainties", which named neither the right total nor the right subset.
##   That absence, and not the User's Manual's, is why the shift-overflow note
##   in `logic.nim` says what it says.
##
##   CPU-6'S PLAN ROW is the CPU-6 row of section 11.3 "The instruction set" of
##   the NMG2 emulator IMPLEMENTATION PLAN
##   (`2026-08-04-nmg2-emulator-impl.md`). Opened and checked: its Check line
##   reads "The test asserts a trap for at least one illegal mode for each
##   implemented opcode", which is the property the shift block below cites it
##   for.
##
## Fifteen other files in this repository carry the same bare-citation style,
## and one of them cites a path on the author's desktop. They belong to their
## own tasks and are not repaired here.
##
## WHY THIS FILE EXISTS BESIDE `mcf5307_conformance_logic`. That corpus is 41
## cases and every one of them is a POSITIVE case: an encoding this part has,
## run against an expected register state. A positive corpus CANNOT SEE either
## of the two defects this file was written to catch, and the reason is
## structural rather than a gap that more cases would close.
##
##   A WRONGLY-CLAIMED ENCODING PRODUCES A PASSING EXECUTION OF A DIFFERENT
##   INSTRUCTION. `decode.nim` claimed line 1011 opmode 111 - which is CMPA.L -
##   as an EOR, because its predicate read `>= 4` where the opmodes of EOR are
##   100, 101 and 110. `opmodeSize(7)` answers 4, so the wrong claim presented
##   as a well-formed long EOR and nothing downstream noticed. Measured against
##   the source before the fix: `cmpa.l %d0,%a1` is `b3c0`, and running it with
##   d0 = 0x0f0f0f0f and d1 = 0x12345678 left d0 = 0x1d3b5977, which is
##   d0 xor d1. The core ran `EOR.L D1,D0`: it wrote a register CMPA must not
##   touch and it computed no comparison. NO NUMBER OF GREEN CASES FINDS THAT.
##   Only a case that asserts what must NOT decode can, which is what
##   `decodeWord(0xb3c0).op == opIllegal` below is.
##
##   An operand the executor refuses is not an operand the corpus offers. The
##   corpus holds no dynamic BTST against a PC-relative operand, so a
##   disagreement between `eaLegalityFor(opBtst)` - which admits it - and
##   `execBitOp` - which would refuse it if it resolved the operand through
##   `eaResolve` - is invisible there. `btst %d1,(4,%pc)` (`033a 0004`) and
##   `btst %d1,(4,%pc,%d2)` (`033b 2804`) both assemble on
##   `m68k-elf-as -mcpu=5307`.
##
## Every case asserts a complete tuple, never one field, exactly as `t_alu`
## does. A case that changes a register asserts (that register, the whole
## status register, `fault`), so a right result with a wrong flag fails and a
## right flag with a wrong result fails. A case that must trap asserts (the
## register it must not have changed, `fault`, `halted`, the cycle return), so
## "it trapped" is separable from "it executed and wrote nothing".
##
## Every trap case but one was offered to `m68k-elf-as -mcpu=5307` and
## rejected, and every positive case was assembled by it. The encodings the
## assembler refuses to emit are built from a measured base word by replacing
## the low six bits, which is the effective-address field: `bset %d1,%d0` is
## `03c0`, so `bset %d1,(4,%pc)` is `03c0 or 3a` = `03fa`. That method is
## cross-checked by the two words the assembler does emit: `btst %d1,%d0` is
## `0300`, and `0300 or 3a` and `0300 or 3c` are `033a` and `033c`, which are
## exactly what the assembler produced for `btst %d1,(4,%pc)` and
## `btst %d1,#5`.
##
## The one exception is `btst %d1,#5`. The assembler accepts that form and
## emits `033c 0005`, and this file asserts that the core traps it. That is
## the only place in this file where a trap case contradicts the assembler, it
## is deliberate, and the manual rows that put it there are on `eaBitDynamic`
## in `decode_types.nim`. It is uncertainty 4 in the `logic.nim` header - the
## one entry on that list which a future reader may have to reverse. Two
## assertions go red when they do, not one: this trap case and the
## `checkMask(eaIsLegalFor(opBtst, decodeEa(0x3C)), false, ...)` row further
## down. The corpus does not pin this question either way.
##
## THE PC-RELATIVE CASES NOW PIN THE PC-RELATIVE BASE, AND THEY USED NOT TO.
## An earlier revision of this paragraph said they did not pin it "and that is
## deliberate", because `machine.nim` computed a `(d16,PC)` address from the
## program counter AFTER the displacement word was consumed while the
## assembler's base is the ADDRESS OF that word. Measured: `btst
## %d1,(target,%pc)` with the opcode at 0 assembles to `033a 0004` and places
## `target` at 6, so the base is 2 and not 4, and
## `m68k-elf-objdump -m m68k:5307` prints `btst %d1,%pc@(6 <target>)`. That was
## a defect of `machine.nim` and it is repaired; `eaAddr` takes the base before
## `fetchExt` advances the counter, and the comment on `fetchExt` that asserted
## the wrong rule is gone.
##
## So the cases below no longer seed the same byte across both candidate
## addresses. `pcWindow` gives the byte at the CORRECT address bit 7 set and
## bit 6 clear, and the byte at the address the old base reached the opposite
## pair, so each Z assertion separates the two bases. The exact addresses are
## on `pcWindow` itself.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Instruction
## semantics, the condition-code rules and the encodings are facts about
## Motorola silicon; they are taken from the ColdFire Family Programmer's
## Reference Manual and the MCF5307 User's Manual (AGENTS.md section 11) and
## from this project's own measurements with the pinned cross assembler.

import mcf5307/cpu
import mcf5307/decode
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
# to be a pass of the shipped path - `mcf5307_reset`, `mcf5307_set_reg`,
# `mcf5307_exec`, `mcf5307_get_reg` - and not of an internal helper reached
# around the back.

const
  execBase = 0x100'u32     ## where the instruction words are placed
  stackBase = 0x800'u32
  srBase = 0x2700'u32      ## the reset status register, CCR all clear
  zero8: array[8, uint32] = [0'u32, 0, 0, 0, 0, 0, 0, 0]

type Outcome = object
  cycles: uint32
    ## `mcf5307_exec(ctx, 1)`'s return, which is not a cycle count despite the
    ## name. `mcf5307_exec` saturates at its budget, and every instruction in
    ## this group costs 2 for the fetch plus at least one more, so the value is
    ## 1 for an instruction that ran and 0 for one that trapped. The
    ## `cycles: 1` half of every tuple below asserts "it ran" and asserts no
    ## count. Nothing in this file asserts a cycle count; uncertainty 3 in the
    ## `logic.nim` header says why.
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

  # One instruction, and the budget is what stops the loop after it, exactly as
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
# and a core that based the address AFTER the extension word - which this one
# did until the `eaAddr` repair - reads two bytes higher in each.
#
# THE WINDOW IS NON-UNIFORM ON PURPOSE, and it used to be uniform on purpose.
# The bytes it puts at the three addresses these cases can reach are:
#
#   0x106  0x80   bit 7 SET,   bit 6 CLEAR   the (4,%pc) operand
#   0x108  0x40   bit 7 CLEAR, bit 6 SET     where the old base read instead
#   0x10a  0x80   bit 7 SET,   bit 6 CLEAR   the (4,%pc,%d2) operand, d2 = 4
#   0x10c  0x40   bit 7 CLEAR, bit 6 SET     where the old base read instead
#
# so every Z assertion below comes out the OPPOSITE way under the old base.
#
# WHAT THIS WINDOW STILL DOES NOT PIN IS THE INDEX WIDTH. `033b 2804` selects a
# LONG index at bit 11 of its extension word, and a core reading that select at
# bit 8 would narrow the index to its low word and sign-extend it. The two
# readings agree on every value this board can hold: separating them needs an
# index whose low word sign-extends to something the whole longword is not,
# which is at least 0x10000 away from its other reading, and this board is
# 0x1000 bytes. `conformance/corpus/logic_00.json`'s `btst_b_pc_index` and
# `btst_b_an_index` pin it instead - the runner's board is 1 MiB.
const pcWindow = @[(0x104'u32, 0xAABB80C3'u32),
                   (0x108'u32, 0x40558022'u32),
                   (0x10C'u32, 0x40AABBCC'u32)]

# The assertions. Each compares one complete tuple.

proc expectD(o: Outcome; n: int; want: uint32; wantSr: uint32; label: string) =
  let got = (reg: o.d[n], sr: o.sr, fault: o.fault)
  let wanted = (reg: want, sr: wantSr, fault: false)
  check(got == wanted, label, $got, $wanted)

proc expectTrapD(o: Outcome; n: int; unchanged: uint32; label: string) =
  ## An encoding the part does not have, or an operand the opcode may not
  ## reach. It must halt with `fault`, return no cycles, and leave the
  ## destination register alone.
  ##
  ## `unchanged` is seeded non-zero by every caller. A trap case whose
  ## register starts at zero asserts 0 == 0 in this half and would pass
  ## against a core that wrote a zero into it.
  let got = (reg: o.d[n], fault: o.fault, halted: o.halted, cycles: o.cycles)
  let wanted = (reg: unchanged, fault: true, halted: true, cycles: 0'u32)
  check(got == wanted, label, $got, $wanted)

proc expectTrapA(o: Outcome; n: int; unchanged: uint32; label: string) =
  ## The address-register twin of `expectTrapD`, for a case whose operand is
  ## an address register. `eaResolve` answers `erAn` for that operand and
  ## `eaRefWrite` puts the result into the register, so the register a removed
  ## mask would disturb is an A and not a D.
  let got = (reg: o.a[n], fault: o.fault, halted: o.halted, cycles: o.cycles)
  let wanted = (reg: unchanged, fault: true, halted: true, cycles: 0'u32)
  check(got == wanted, label, $got, $wanted)

proc freshCtx(): MCF5307Ctx =
  ## A context reset onto a cleared board. It serves the assertions that call
  ## a `machine.nim` procedure directly; every instruction case goes through
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

proc checkMask(got: bool; want: bool; label: string) =
  check(got == want, label, $got, $want)

# The dirty condition codes a bit operation must carry through untouched. A bit
# operation writes Z alone (manual Table 3-7 names no other bit), so N, V, C
# and X are set on entry and asserted unchanged on exit.
const bitDirty = srBase or ccrN or ccrV or ccrC or ccrX

# ---------------------------------------------------------------------------
# BLOCKING 1. `CMP` AND `CMPA.L` ARE NOT THIS GROUP'S, AND CPU-10 HAS TAKEN
# THEM.
#
# Line 1011 carries EOR in opmodes 100, 101 and 110. THE OTHER FIVE OPMODES
# ARE CPU-10'S: CMP in 000, 001 and 010, CMPA.W in 011 and CMPA.L in 111.
# FIVE AND NOT FOUR - an earlier revision of this comment omitted 011, where
# `decode.nim`'s comment beside the same predicate counts five.
#
# THESE THREE ROWS USED TO ASSERT `opIllegal` AND THE SENTENCE THEY ASSERT IS
# UNCHANGED: the encoding belongs to CPU-10 and not to the logic decoder. Until
# CPU-10 landed, "belongs to CPU-10" and "not decoded" were the same
# observable, and `opIllegal` was how this file said it. Now that the group
# exists the same sentence has a stronger form - the encoding comes back as
# CPU-10's own operation - and a defect that fed it back into `decodeLogicLine`
# would show here exactly as it did before. `tests/t_control.nim` holds the
# other half: that all three EOR opmodes stay EOR.
#
# Opmode 111 is CMPA.L because the assembler put it there, and not by any
# inference from `cmpa.w`. `b3c0` is what `m68k-elf-as -mcpu=5307` emitted for
# `cmpa.l %d0,%a1`, and `(0xb3c0 shr 6) and 7` is 111.

block:
  expectDecode(0xB3C0'u16, opCmpa,
    "cmpa.l %d0,%a1 (b3c0) is CPU-10's CMPA and not this group's EOR")
  expectDecode(0xB280'u16, opCmp,
    "cmp.l %d0,%d1 (b280) is CPU-10's CMP and not this group's EOR")

  # THE POSITIVE CONTROLS. Without them a predicate that gave the WHOLE of
  # line 1011 to CPU-10 would report the two cases above as passes, and EOR
  # would be gone. All three EOR opmodes are still claimed, byte and word
  # included - those two are not instructions on this part and they trap on
  # the SIZE, which is the channel `decodeLogicLine` and CPU-13 both use.
  expectDecode(0xB380'u16, opEor, "eor.l %d1,%d0 (b380) is still an EOR")
  expectDecode(0xB300'u16, opEor, "the byte EOR opmode (b300) is still an EOR")
  expectDecode(0xB340'u16, opEor, "the word EOR opmode (b340) is still an EOR")

  # AND THE EXECUTION. THE DEFECT THIS ROW WAS WRITTEN FOR IS AN EOR, AND IT
  # STILL IS. `b3c0` decoded as a well-formed long EOR once and left
  # d0 = d0 xor d1 = 0x1d3b5977; the row asserted a trap while CPU-10 was
  # unwritten and it asserts the CMPA now, and BOTH REFUSE THAT VALUE.
  #
  # `cmpa.l %d0,%a1` computes a1 - d0 and DISCARDS it: 0x11223344 - 0x0f0f0f0f
  # is 0x02132435, which is non-zero, positive and borrows nothing, and
  # 0x0f0f0f0f and 0x11223344 are both positive so no signed overflow is
  # possible. The incoming `sr` is the reset word, so the whole 16-bit result
  # is 0x2700 - and a core that wrote a register would have to leave `d0`,
  # `d1` or `a1` different from the values named here.
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
# A dynamic `BTST` reaches every operand its mask admits, and the mask stops
# at the immediate.
#
# `eaLegalityFor(opBtst)` is `eaBitDynamic`: the manual's DATA class without
# the immediate. BTST never writes, so it must read the two PC-relative
# sub-variants through `eaRead`; `eaResolve` serves `AbsW` and `AbsL` alone
# and faults on the rest, which is correct for the operations that write and
# wrong for this one.
#
# `btst %d1,(4,%pc)` is `033a 0004` and `btst %d1,(4,%pc,%d2)` is `033b 2804`,
# both assembled by `m68k-elf-as -mcpu=5307`.
#
# Why the immediate is out, and why the assembler does not settle it. See the
# `eaBitDynamic` doc comment in `decode_types.nim` for the manual rows and the
# toolchain measurements. The short form: MCF5307 User's Manual Table 3-13
# (page 3-28) dashes the `#xxx` column of the `btst Dy,<ea>` row, and that
# dash is the same mark the table uses for every form this part does not have.
# `m68k-elf-as -mcpu=5307` does assemble `btst %d1,#5` as `033c 0005`, and
# that acceptance is byte-for-byte the plain-68000 one - the assembler
# narrows the static bit-operation modes for ColdFire and leaves this form
# untouched - so it measures the 68000 rule and not this part.

block:
  # The immediate operand traps. `033c 0005` is the word the assembler emits
  # for `btst %d1,#5`; d1 is seeded non-zero so the "unchanged" half is an
  # assertion and not `0 == 0`.
  expectTrapD(runIns([0x033C'u16, 0x0005'u16],
                     d = [0'u32, 3, 0, 0, 0, 0, 0, 0], sr = bitDirty),
    1, 3'u32,
    "btst %d1,#5 traps: the immediate is not a dynamic BTST operand")

block:
  # The PC-relative operand, AND THE EXACT ADDRESS IT MUST REACH. `pcWindow`
  # puts 0x80 at 0x106 - the byte `(4,%pc)` names - and 0x40 at 0x108, where
  # the old base read instead, so each of the two cases below comes out the
  # opposite way under the old base. See `pcWindow`.
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

  # The indexed PC-relative operand. `eaLegalityFor(opBtst)` admits
  # `(d8,PC,Xn)` - the `eaIsLegalFor(opBtst, ...)` row further down asserts
  # exactly that - and a bit operation that resolved every operand through
  # `eaResolve` would refuse it. An asserted table entry that no case executes
  # is a claim about the table and not about the core, so here is the case.
  # `btst %d1,(4,%pc,%d2)` is `033b 2804`, assembled by `m68k-elf-as
  # -mcpu=5307`.
  #
  # THE EXACT ADDRESS IS NOW PINNED AND THE INDEX WIDTH IS STILL NOT, and the
  # two halves of that sentence have different reasons. An earlier revision of
  # this comment said the index is "a small positive number on purpose" so that
  # the case would stay green whichever way `machine.nim` read the word/long
  # select, and that select is now repaired - it is bit 11, not bit 8.
  #
  # With d2 = 4 the operand is the byte at 0x10a, which `pcWindow` seeds 0x80,
  # while the old base reached 0x10c, seeded 0x40. So this case now separates
  # the two BASES exactly as the two above it do.
  #
  # IT STILL CANNOT SEPARATE THE TWO WIDTHS, and no case on this 0x1000-byte
  # board can: the readings differ only for an index whose low word
  # sign-extends to something the whole longword is not, and those two
  # addresses are at least 0x10000 apart. `btst_b_pc_index` and
  # `btst_b_an_index` in `conformance/corpus/logic_00.json` pin the width on
  # the runner's 1 MiB board.
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
  # The widening is BTST's alone. `BSET`, `BCLR` and `BCHG` write their
  # operand, so a PC-relative or an immediate destination stays refused. Each
  # of the four words below is the measured base word with the low six bits
  # replaced: `bset %d1,%d0` is `03c0`, `bclr %d1,%d0` is `0380` and
  # `bchg %d1,%d0` is `0340`. `m68k-elf-as -mcpu=5307` rejects every one of
  # `bset %d1,(4,%pc)`, `bset %d1,#5`, `bclr %d1,(4,%pc)` and `bchg %d1,#5`.
  #
  # More than one guard refuses these four, and no case here can name one of
  # them. The per-operation mask in `execBitOp` runs first and `eaResolve`
  # runs second, and the two immediate cases meet a third underneath both:
  # `eaAddr` has no address for an immediate and faults on its own. The four
  # cases assert that the encoding does not execute, and that is all they
  # assert.
  #
  # Each guard is measured somewhere that can see it, and the places are named
  # here so that no property rests on a case that cannot fail on it:
  #   - the dynamic mask is measured by the BSET, BCLR and BCHG rows of the
  #     `eaIsLegalFor` block further down, and by the three An cases at the
  #     end of this block, which are the only cases in this block that trap on
  #     the mask alone;
  #   - the static mask `eaBitStatic` is measured by its own `checkMask` rows
  #     and by the two `btst #3,...` cases beside them, which go red both when
  #     that mask is widened and when the mask check is deleted;
  #   - `eaResolve`'s own refusal is measured by the block that follows this
  #     one, which calls it directly, because no instruction in this group can
  #     see a widened `eaResolve` at all.
  let d1only = [0'u32, 3'u32, 0, 0, 0, 0, 0, 0]
  expectTrapD(runIns([0x03FA'u16, 0x0004'u16], d = d1only), 1, 3'u32,
    "bset %d1,(4,%pc) still traps")
  expectTrapD(runIns([0x03FC'u16, 0x0005'u16], d = d1only), 1, 3'u32,
    "bset %d1,#5 still traps")
  expectTrapD(runIns([0x03BA'u16, 0x0004'u16], d = d1only), 1, 3'u32,
    "bclr %d1,(4,%pc) still traps")
  expectTrapD(runIns([0x037C'u16, 0x0005'u16], d = d1only), 1, 3'u32,
    "bchg %d1,#5 still traps")

  # And the one operand the mask refuses on its own. `eaResolve` resolves an
  # address register - it answers `erAn`, and `eaRefWrite` puts the result
  # into that register - so nothing under the executor stops these three. The
  # per-operation mask is the only guard they meet, which is what makes them
  # cases that go red when it is removed, and what the four cases above
  # cannot be. Measured with the mask check deleted from `execBitOp`:
  # `bset %d1,%a0` reported no fault, returned a cycle, and left a0 at
  # 0x0000123c - the seeded 0x00001234 with bit 3 set.
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

  # The positive control for the writing bit operations. Without it the trap
  # cases above would pass against a `BSET` that refused every operand.
  # `bset %d1,%d0` is `03c0`; d0 starts at 0 and bit 3 is set, so Z takes the
  # complement of the bit as it was found and is set.
  expectD(runIns([0x03C0'u16], d = [0'u32, 3, 0, 0, 0, 0, 0, 0],
                 sr = bitDirty),
    0, 0x00000008'u32, bitDirty or ccrZ,
    "bset %d1,%d0 sets the bit and reports the bit it found in Z")

# ---------------------------------------------------------------------------
# `eaResolve` stays narrow, and this is the only place in this file that can
# say so.
#
# `logic.nim` puts the BTST fix in the executor and not in `eaResolve`,
# because widening that procedure would let a write reach a PC-relative or an
# immediate operand and it has callers outside this module. That is a claim
# about `machine.nim`, and the three assertions below are what make it a
# measured one: they call `eaResolve` directly and require it to refuse, with
# `fault` and `halted` set and no usable reference returned.
#
# They have to be direct. Every writing path in `logic.nim` - the
# `Dn op <ea> -> <ea>` direction of AND and OR, EOR, and BSET, BCLR and BCHG -
# checks a mask that already excludes these three sub-variants BEFORE it calls
# `eaResolve`, so a widened `eaResolve` changes the behaviour of no
# instruction this group executes. Measured: widening it to admit
# `ea7PCDisp` and `ea7PCIndex` left every executor case in this file green.
# A case routed through an instruction would therefore be a case that cannot
# fail on the thing it names.

block:
  expectUnresolvable(ea7PCDisp,
    "eaResolve refuses a (d16,PC) destination and halts with fault")
  expectUnresolvable(ea7PCIndex,
    "eaResolve refuses a (d8,PC,Xn) destination and halts with fault")
  expectUnresolvable(ea7Imm,
    "eaResolve refuses an immediate destination and halts with fault")

# ---------------------------------------------------------------------------
# `eaBitStatic` - the static bit operation's operand is narrower than the
# dynamic one, and this is the mask that says so.
#
# Measured: `m68k-elf-as -mcpu=5307` accepts `btst #3,(%a0)` (`0810 0003`) and
# rejects `btst #3,(4,%pc)` and `btst #3,0x1234.w`. The two rejected words are
# `0800` (the measured `btst #3,%d0`) with the low six bits replaced: `083a`
# and `0838`.

block:
  # The mask, read directly. A negative case and a positive control for each
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

  # And through the executor. `btst #3,(%a0)` reads one byte - a memory
  # operand of a bit operation is 8 bits wide - so the byte at 0x200 is 0x08,
  # whose bit 3 is set, and Z is cleared. The three bytes beside it are given
  # distinct values and asserted unchanged, because a core that read or wrote
  # a longword here would answer a different question.
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

  # The two encodings the static form may not reach.
  #
  # Each operand is an address the board answers, so the mask is the only
  # thing that can refuse it. An address off this 0x1000 board would trap on
  # `busUnmapped` whatever the mask says: with `eaBitStatic` widened to mode 7
  # an off-board absolute-short case stays green while its `(d16,PC)` sibling
  # goes red. 0x200 is on this board, so the widened core executes it here and
  # the case goes red - which is what a case about a mask has to do.
  #
  # d0 is seeded non-zero in both, so the "unchanged register" half is an
  # assertion and not `0 == 0`.
  let dSeed = [0x12345678'u32, 0, 0, 0, 0, 0, 0, 0]
  expectTrapD(runIns([0x083A'u16, 0x0003'u16, 0x0004'u16], d = dSeed),
    0, 0x12345678'u32,
    "btst #3,(4,%pc) traps: the static form reaches no PC-relative operand")
  expectTrapD(runIns([0x0838'u16, 0x0003'u16, 0x0200'u16], d = dSeed),
    0, 0x12345678'u32,
    "btst #3,0x200.w traps: the static form reaches no absolute operand")

# ---------------------------------------------------------------------------
# `eaDataAddressing` - the manual's DATA class, which does not include `An`.
# It is the source mask of the `<ea> op Dn -> Dn` direction of AND and OR, and
# those two only. Both read and neither writes, so the PC-relative pair and
# the immediate are in and the address register is out. MCF5307 User's Manual
# Table 3-13: the `and.l <ea>,Rx` row on page 3-28 and the `or.l <ea>,Rx` row
# on the continuation page 3-29 carry a time in every column including `#xxx`,
# where both read `1(0/0)`.
#
# A dynamic BTST does not read this mask. It reads `eaBitDynamic`, which is
# this class minus the immediate; the rows behind that difference are on the
# constant itself and the block below asserts both ends of it.
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

  # The dynamic bit operation's mask is `eaBitDynamic`, and these rows are
  # what say so. They read `eaLegalityFor` through `eaIsLegalFor`, which is
  # the call `execBitOp` makes, so a table entry changed under the executor
  # fails here. The immediate row is the one that separates this mask from
  # `eaDataAddressing` above, and it is asserted at both ends: that mask
  # admits the immediate two rows up, this one rejects it.
  checkMask(eaIsLegalFor(opBtst, decodeEa(0x3A'u16)), true,
    "the BTST mask admits (d16,PC)")
  checkMask(eaIsLegalFor(opBtst, decodeEa(0x3B'u16)), true,
    "the BTST mask admits (d8,PC,Xn)")
  checkMask(eaIsLegalFor(opBtst, decodeEa(0x3C'u16)), false,
    "the BTST mask rejects an immediate")
  checkMask(eaIsLegalFor(opBtst, decodeEa(0x08'u16)), false,
    "the BTST mask rejects An")

  # The three bit operations that write carry a narrower mask, which is the
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
  # The positive control is the PC-relative source and not an immediate one.
  # `m68k-elf-as -mcpu=5307` assembles `and.l #0x0f0f0f0f,%d1` as ANDI
  # (`0281 0f0f 0f0f`) and never emits the `and.l <ea>,Dn` form with an
  # immediate effective address, so that word is not a measured encoding and
  # is not asserted here. `and.l (4,%pc),%d1` is one: `c2ba 0004`.
  #
  # THE SOURCE IS THE LONGWORD AT 0x106, and `pcWindow` makes that a different
  # longword from the one at 0x108 that the old PC-relative base reached:
  # 0x80c34055 against 0x40558022. An earlier revision seeded both with
  # 0x0f0f0f0f so that the case could not tell them apart.
  #
  #   0x12345678 and 0x80c34055 = 0x00004050   (this case)
  #   0x12345678 and 0x40558022 = 0x00140020   (the old base)
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
# The `{eaDn}` arm. Every shift on this part is register-only, and the
# immediate-logic and NOT opcodes reach a data register and nothing else. The
# entry in `eaLegalityFor` that names them is one `EaLegality` whose modes are
# `{eaDn}` and whose mode-7 set is empty.
#
# The shift's register form cannot violate that mask - `decodeShift` builds its
# operand as `EA(mode: eaDn, ...)` and never asks `decodeEa`. The memory form
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

  # One illegal mode per shift operation. The memory form is the encoding that
  # carries an effective address at all, and these cases assert that the core
  # refuses it.
  #
  # They do not attribute the refusal to the mask. `decodeShift` gives the
  # memory form `size: 2`, so `execShift`'s two guards - the `{eaDn}` mask and
  # the long-size rule - each refuse it on their own. Measured: removing the
  # `eaIsLegalFor` call from `execShift` leaves every case in this file green,
  # and removing the `d.size != 4` check instead leaves every case green too.
  # The mask is measured by the `checkMask` rows just above, which read it
  # directly; these cases measure that the encoding does not execute.
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

  # The positive controls. Without them the cases above would pass against a
  # shift group that refused every operand. Each word is the assembler's:
  # `asl.l #1,%d0` is `e380`, `asr.l #1,%d0` is `e280`, `lsl.l #1,%d0` is
  # `e388` and `lsr.l #1,%d0` is `e288`.
  #
  # X and C both take the last bit shifted out, so each case starts with a
  # dirty X and asserts the value the shift put there rather than the value it
  # inherited.
  expectD(runIns([0xE380'u16], d = [0x80000000'u32, 0, 0, 0, 0, 0, 0, 0],
                 sr = srBase),
    0, 0'u32, srBase or ccrC or ccrX or ccrV or ccrZ,
    "asl.l #1 of 0x80000000 shifts the sign out into C and X and sets V and Z")
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
# One illegal mode per remaining new operation: EOR, ANDI, ORI and EORI.
#
# Every word below was offered to `m68k-elf-as -mcpu=5307` and rejected, and
# each is a measured base word with the low six bits replaced:
# `eor.l %d1,%d0` is `b380`, `andi.l #5,%d0` is `0280`, `ori.l #5,%d0` is
# `0080` and `eori.l #5,%d0` is `0a80`.

block:
  let two = [0x12345678'u32, 0x0F0F0F0F'u32, 0, 0, 0, 0, 0, 0]

  # EOR writes its effective address, so the class is data alterable: no
  # PC-relative operand and no address register.
  #
  # The two cases are not equally sharp and the difference is `eaResolve`. It
  # refuses a PC-relative destination on its own, so the PC-relative case is
  # refused twice over and cannot name the guard that stopped it - measured,
  # it stayed green when the EOR mask was widened to `eaAlterableModes` +
  # `eaData7`. `eaResolve` resolves an address register, so the An case meets
  # the mask alone, and it went red under that same widening. Both are kept
  # and they say different things: the first asserts the encoding does not
  # execute, the second asserts which guard stops it.
  expectTrapD(runIns([0xB3BA'u16, 0x0004'u16], d = two), 0, 0x12345678'u32,
    "eor.l %d1,(4,%pc) traps: an EOR destination is not PC-relative")
  expectTrapA(runIns([0xB388'u16], d = two,
                     a = [0x1234'u32, 0, 0, 0, 0, 0, 0, 0]), 0, 0x1234'u32,
    "eor.l %d1,%a0 traps: An is not data alterable")

  # ANDI, ORI and EORI reach a data register and nothing else. The trap comes
  # before the immediate is fetched, which is why the extension words below
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

  # The positive controls for the same four operations, each the assembler's
  # own word. Without them the cases above would pass against executors that
  # refused every operand.
  expectD(runIns([0xB380'u16], d = two, sr = srBase or ccrX or ccrC or ccrV),
    0, 0x1D3B5977'u32, srBase or ccrX,
    "eor.l %d1,%d0 combines the two registers, clears V and C, and keeps X")
  expectD(runIns([0x0280'u16, 0x0000'u16, 0x0005'u16], d = two),
    0, 0x00000000'u32, srBase or ccrZ, "andi.l #5,%d0 = 0 and sets Z")
  expectD(runIns([0x0080'u16, 0x0000'u16, 0x0005'u16], d = two),
    0, 0x1234567D'u32, srBase, "ori.l #5,%d0 sets the two low bits")
  # The EORI control uses a different immediate from the ORI one on purpose.
  # `0x12345678 or 5` and `0x12345678 xor 5` are the same word, so a pair that
  # shared an immediate would pass against an executor that confused the two.
  # `eori.l #0xf,%d0` is `0a80 0000 000f`, and 0x78 xor 0x0f is 0x77 where
  # 0x78 or 0x0f is 0x7f.
  expectD(runIns([0x0A80'u16, 0x0000'u16, 0x000F'u16], d = two),
    0, 0x12345677'u32, srBase, "eori.l #0xf,%d0 flips the low four bits")

if failures.len > 0:
  echo ""
  echo "t_logic: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_logic: ", passCount, " cases passed"
