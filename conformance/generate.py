#!/usr/bin/env python3
"""The ColdFire ISA_A conformance corpus generator.

  Linux x86-64 : `python3 conformance/generate.py --out conformance/corpus`
                 must regenerate the committed corpus byte-identical.
  macOS arm64, Windows x86-64 : the parse check `t0_corpus_parses` runs
                 instead; regeneration proves nothing a parse does not.

The generator encodes each case's instruction with the GNU m68k cross
assembler and writes a deterministic JSON corpus. Both the script and the
generated corpus are committed, so no cross toolchain is needed at test time
on any platform.

## Determinism

"Byte-identical regeneration" is only meaningful if the writer is
deterministic. Every decision that could vary the output is fixed here:

  * the JSON is written with `sort_keys=True` and a fixed indent, so the
    key order and layout cannot vary across runs or hosts;
  * every value is written from Python ints or fixed lowercase hex strings;
  * the per-group file names are fixed (`<group>_00.json`);
  * the case order is the order the CASES table lists, which is fixed.

The one non-deterministic input is the assembler: a different binutils
version can emit different bytes for the same source. That is why the
assembler version is pinned in `docs/toolchain.md`. Regenerating under the
pinned version is byte-identical; the CI job installs exactly that version.

## The corpus schema

One file per group, `conformance/corpus/<group>_00.json`, where `<group>` is
one of `move`, `alu`, `logic`, `control`.

Each file is an object with:

  "format"    int         the schema version (1).
  "group"     str         the group name, matching the file's <group> prefix.
  "binutils"  str         the pinned assembler version this file was
                          generated with (from docs/toolchain.md).
  "cases"     array       the group's cases. Non-empty.

Each case is an object with:

  "name"        str     a stable identifier (unique within the file).
  "mnemonic"    str     the family, e.g. "move.l".
  "instruction" str     the assembly text the generator assembled.
  "encoding"    array   the machine words, each a lowercase 4-hex-digit
                        string, big-endian, in the order the assembler
                        emitted them.
  "initial"     object  the state before the instruction runs:
                          "regs"  object  register name -> 32-bit int value
                          "mem"   array   intended writes to set up memory
                                          (empty in this corpus; see below)
  "expected"    object  the state to assert after the instruction runs:
                          "regs"  object  register name -> expected value
                          "mem"   array   expected writes to memory

A register name is "d0".."d7", "a0".."a7", "sr" or "pc". The runner
sets the `initial` registers, executes the case's encoding, and asserts each
`expected` register equals its value. Registers the `expected` object does
not name are not asserted: a case that affects only one register does not
have to state every other one.

## The condition codes are asserted through `sr`, and the whole word is
## asserted

`sr` is a register like any other, in `initial` and in `expected` both. The
runner sets it through the same bridge as `d0` and asserts it by the same
equality. A corpus that names `sr` in no case leaves every condition-code
rule in every group invisible to conformance.

The value is the whole 16-bit status register and not a condition-code mask.
`0x2700` is the reset value: supervisor set, interrupt mask 7, every condition
code clear. A case that expects `0x2718` therefore asserts three things at
once - that X and N are set, that C, V and Z are clear, AND that the executor
left the supervisor bit and the interrupt mask alone. `tests/t_alu.nim` and
`tests/t_move.nim` assert the same whole word, so the two views of one rule
cannot drift apart.

The incoming `sr` is deliberately dirty. A case whose instruction must clear
a flag proves nothing when that flag was already clear on entry, exactly as a
sized MOVE proves nothing into a zero destination. Every flag-asserting case
below therefore starts from `SR_DIRTY` (0x271F: every condition code set) and
names the exact word the instruction must leave behind. A case whose
instruction must not touch the condition codes at all - MOVEA, LEA, PEA, LINK,
UNLK, MOVEM - expects `SR_DIRTY` back unchanged, which is an assertion a clean
incoming `sr` cannot make.

Where the manual leaves a flag undefined, no `sr` is asserted. The equality is
over the whole word, so a case cannot assert four flags and decline the fifth.
A case whose rule is not defined for every bit carries no `sr` at all rather
than pin an accident of this implementation. The authority here is the
ColdFire Family Programmer's Reference Manual.

Every case is judged on the core's run state before any value is compared.
`conformance/runner.cpp` asserts `mcf5307_faulted`, then `mcf5307_halted`,
then a non-zero cycle return, for every case and whatever registers the case
names. A case whose instruction traps therefore fails even when the registers
it names hold the expected values - which is the whole class of case that
expects a register to be unchanged, because a trap leaves its operands alone.
That check is unconditional, so `nop` names `sr` like every other case whose
instruction must not touch the condition codes.

"mem" is a list of `{"addr": int, "size": int, "value": int}` writes. The
seed corpus carries only register cases, so every "mem" array in it is empty;
the field exists so that later memory-based cases have a place.
A caller that writes no memory follows the same rule as the registers: omit
it.

A register value is the 32-bit integer it is, exactly as Python wrote it.
A case that sets a register to all ones (for example `neg.l` of 1, or the
sign extension `ext.l` of a negative word) is written as -1 or -32768, the
two's-complement 32-bit value; `conformance/parse_check.cpp` parses signed
integers and the runner reads them as 32-bit two's-complement, so the two
views are the same number.

The instruction the generator assembles is the bare mnemonic line. It is
written to its own assembly translation unit and assembled with
`-mcpu=5307`, so the assembler rejects an instruction that does not exist on
the part at the corpus's own generation. A case that fails to assemble fails
the generator, not just the later runner.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile

M68K_AS = os.environ.get("M68K_AS", "m68k-elf-as")
M68K_OBJCOPY = os.environ.get("M68K_OBJCOPY", "m68k-elf-objcopy")

FORMAT_VERSION = 1

# The pinned assembler version. Kept in step with docs/toolchain.md.
BINUTILS_VERSION = "GNU assembler (GNU Binutils) 2.47.20260726"

GROUPS = ("move", "alu", "logic", "control")

# ---------------------------------------------------------------------------
# The status register, written by name.
#
# ColdFire keeps the 68k condition-code register in bits 0..4 of the status
# register: C at 0, V at 1, Z at 2, N at 3, X at 4. Bits 15..8 hold the trace
# bits, the supervisor bit and the interrupt mask, and 0x2700 is the value the
# part comes out of reset with: supervisor set, interrupt mask 7, every
# condition code clear.
#
# These are the same five bit positions `src/mcf5307/machine.nim` names, and
# the same `srBase` `tests/t_alu.nim` and `tests/t_move.nim` name.

SR_BASE = 0x2700      # supervisor, interrupt mask 7, every condition code clear
CCR_C = 0x01
CCR_V = 0x02
CCR_Z = 0x04
CCR_N = 0x08
CCR_X = 0x10

# The incoming status register of every flag-asserting case. Every condition
# code is set on entry, so that an instruction which must clear a flag is
# separable from one that never wrote the flag at all. A clean incoming `sr`
# cannot make that distinction, for the same reason a zero destination register
# cannot separate a merging sized write from a replacing one.
SR_DIRTY = SR_BASE | CCR_C | CCR_V | CCR_Z | CCR_N | CCR_X

# ---------------------------------------------------------------------------
# The destination seeds.
#
# A sized write to a data register replaces the low `size` bytes and keeps the
# rest. A destination that starts at zero cannot tell that rule from a write
# that replaces the whole register, because both leave the same value behind.
#
# Every byte of these seeds differs. A palindromic or repeating seed (0x11111111,
# 0x12341234) survives a wrong byte lane, a wrong word half or a byte-swapped
# store and still compares equal. 0x12345678 is the value the hand-written
# `tests/t_move.nim` uses and it is used here for the same reason.
DIRTY_D = 0x12345678   # the data-register destination seed
DIRTY_A = 0x0BADC0DE   # the address-register destination seed

# ---------------------------------------------------------------------------
# The memory seeds, and the address the memory cases point an address register
# at. The bit operations are the first group whose memory operand is a byte
# while the register operand is a longword, so a core that read or wrote four
# bytes where the part reads one is a defect this corpus has to be able to
# see.
#
# `MEM_BASE` is clear of the encoding (the runner places that at 0x10000) and
# inside the runner's 1 MiB board.
#
# The seed bytes all differ, and neither pair is symmetric. A byte case
# names `MEM_BASE` and asserts the remaining bytes are unchanged, so a write
# that was one byte too wide, or that landed on the wrong end of the longword,
# changes a byte the case names. A repeating seed would survive both.
#
# 0x02 is the addressed byte and it is chosen so that bit 1 of it is set while
# bit 1 of the longword 0x025A3CC1 - which is bit 1 of its low byte 0xC1 - is
# clear: `btst #1,(%a0)` therefore answers differently under the byte rule and
# under a longword rule, and the case separates them. 0xC1 at the far end has
# bit 1 clear too, so a core that read the wrong end of the longword also
# answers differently. The bit number is inside a byte, so the separation is of
# the access width alone and does not depend on how an out-of-range bit number
# is reduced.
MEM_BASE = 0x2000
MEM_SEED_BYTES = (0x02, 0x5A, 0x3C, 0xC1)
MEM_GUARD = 0x0BADC0DE   # the longword after a longword memory destination

# ---------------------------------------------------------------------------
# The addressing modes this corpus reaches, and the seeds that separate a
# correct evaluator from a wrong one.
#
# Every case below does two things: it reaches the mode at all, and it pins the
# exact address, so that an evaluator which reaches a neighbouring address
# answers differently.
#
# The two windows are the mechanism. `EA_WINDOW` is seeded at the address the
# instruction names and `EA_DECOY_WINDOW` at the address a defective evaluator
# reaches. Every byte of each differs from every byte of the other, and neither
# window is symmetric, so a byte read, a longword read and a longword read two
# bytes off all give three different answers:
#
#   EA_WINDOW       byte at +0 = 0x80 (bit 7 set), long at +0 = 0x80112233,
#                   long at +2 = 0x22334455
#   EA_DECOY_WINDOW byte at +0 = 0x0b (bit 7 clear), long at +0 = MEM_GUARD
#
# The bit-7 disagreement is what the BTST cases read and what puts N in the
# MOVE and ADD cases' status words, so the destination and the condition codes
# both separate the readings.
EA_WINDOW = (0x80, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77)
EA_DECOY_WINDOW = (0x0B, 0xAD, 0xC0, 0xDE, 0x1F, 0x2E, 0x3D, 0x4C)

# The absolute-long address, and the address its two halves swapped.
#
# `(xxx).L` carries its address in TWO extension words. The reference:
# "The address N of a longword data item corresponds to the address of the high
# order word. The lower order word is located at address N + 2." The first
# extension word is therefore the high half. `m68k-elf-as -mcpu=5307` agrees:
# `btst %d1,0x00030004` assembles to `0339 0003 0004`.
#
# `ABS_L_ADDR` and `ABS_L_SWAPPED` are each other's halves exchanged, both are
# inside the runner's 1 MiB board, and neither overlaps the other's window, so
# a core that combined the two words the wrong way round reads or writes the
# decoy and fails on a value the case names.
ABS_L_ADDR = 0x00030004
ABS_L_SWAPPED = 0x00040003

# The absolute-short address. `(xxx).W` carries one extension word,
# sign-extended. Every case that uses it also names `pc`, so a core that read
# two words for it - the `(xxx).L` shape - fails on the program counter even
# when the operand value happens to survive.
#
# The sign extension itself is not pinned here and cannot be: a negative
# `(xxx).W` addresses 0xFFFF8000 upward, the runner's board is 1 MiB, and a
# case whose operand access reports `busUnmapped` traps and fails on the run
# state rather than on the address. See the uncertainty note in
# `src/mcf5307/machine.nim`.
ABS_W_ADDR = MEM_BASE

# Where the encoding is placed. The runner defaults to this, and every
# PC-relative case names it in `initial.regs` anyway, so the operand addresses
# those cases assert are derived from a value the case states rather than from
# a constant inside the runner.
EXEC_BASE = 0x10000

# The PC-relative base is the address *of* the displacement word, not the
# address after it. Every instruction below puts its opcode at `EXEC_BASE` and
# its displacement word at `EXEC_BASE + 2`, so the operand is at
# `EXEC_BASE + 2 + PC_DISP`.
#
# The manual does not state this - it gives `(d16,PC)` a row in Table 3-5 and
# no effective-address equation anywhere - so the authority is the pinned
# assembler. Measured: `btst %d1,(target,%pc)` with the opcode at 0 assembles
# to `033a 0004` and the linker places `target` at 6, and
# `m68k-elf-objdump -m m68k:5307` prints `btst %d1,%pc@(6 <target>)`. Base
# plus 4 is 6, so the base is 2 - the address of the displacement word.
#
# A core that took the base after the word is exactly two bytes high, which is
# why `EA_WINDOW` is eight bytes and no two of them are equal: the byte the
# instruction names and the byte two along are different, and so are the
# longwords starting at each.
PC_DISP = 0x1E
PC_OPERAND = EXEC_BASE + 2 + PC_DISP

# The index register's width, and the one value that can see it.
#
# An indexed extension word selects a word or a long index. The pinned
# assembler puts that select at bit 11: `btst %d1,(4,%pc,%d2)` assembles to
# `033b 2804`, whose extension word `2804` has bit 11 set and bit 8 clear, and
# `m68k-elf-objdump -m m68k:5307` prints `%pc@(0x6,%d2:l)` - `:l`, a long
# index. Bit 8 is the brief-format marker and is always zero; a core that read
# the select there answers word for every instruction the assembler emits.
#
# A small positive index cannot tell the two readings apart.
# `INDEX_VALUE` is the value that can: its low word is 0xfff0, which
# sign-extends to -16, while the whole longword is +65520. The two readings
# therefore land 65536 bytes apart, both inside the runner's 1 MiB board, and
# each case seeds `EA_WINDOW` at one and `EA_DECOY_WINDOW` at the other.
#
# The manual does not print the extension word's layout - there is no
# brief-format figure anywhere in it - so the assembler is the authority for
# the bit position. What the manual does say is section 3.5.2, "Address Error
# Exception", page 3-15: "Any attempted use of a word-sized index register
# (Xi.w) ... generates an address error". `m68k-elf-as -mcpu=5307` agrees and
# rejects `btst %d1,(4,%pc,%d2.w)`, so on this part the select is always long
# and a core reading bit 8 is wrong for every legal encoding.
INDEX_D8 = 4
INDEX_VALUE = 0x0000FFF0
INDEX_WORD_READING = -0x10          # what INDEX_VALUE's low word sign-extends to

PC_INDEX_OPERAND = EXEC_BASE + 2 + INDEX_D8 + INDEX_VALUE
PC_INDEX_DECOY = EXEC_BASE + 2 + INDEX_D8 + INDEX_WORD_READING

AN_INDEX_OPERAND = MEM_BASE + INDEX_D8 + INDEX_VALUE
AN_INDEX_DECOY = MEM_BASE + INDEX_D8 + INDEX_WORD_READING


def mem_bytes(base, values):
    """The `mem` list that seeds or asserts consecutive single bytes."""
    return [{"addr": base + i, "size": 1, "value": v}
            for i, v in enumerate(values)]


def lw(addr, value):
    """One longword `mem` entry."""
    return {"addr": addr, "size": 4, "value": value}


# ---------------------------------------------------------------------------
# The control group's seeds: the stack, the branch targets and the vector table.
#
# The stack must be inside the runner's board and the default is not.
# `conformance/runner.cpp` resets A7 to 0x400000 and its board is 1 MiB, so a
# push through the default pointer is silently dropped by `MemBoard::write` and
# a pop reads back zero. Every case below that touches the stack - BSR, JSR,
# RTS, RTE, TRAP - therefore names `a7`, and names it inside the board.
#
# `CTRL_STACK` is longword-aligned so that the TRAP cases which vary A7's low
# two bits can do so by adding to it, and every one of them still writes its
# frame at the same 0-modulo-4 address. Table 3-2 of the MCF5307 User's Manual
# (page 3-14) is the rule those cases assert; see the TRAP block below.
CTRL_STACK = 0x3000

# The guard longword at the incoming A7. A push writes below the pointer, so
# the longword at it must come back untouched; each case pairs this with a
# second guard below whatever it wrote. Seeding and asserting both makes "the
# core wrote four bytes, at this address, and nowhere else" an assertion rather
# than an assumption. `MEM_GUARD` is the same 0x0BADC0DE the earlier groups use.
CTRL_GUARD_AT = CTRL_STACK              # at the incoming A7

# The branch and call targets. Both are inside the board, neither is symmetric,
# and neither shares a byte with the other, so a program counter that landed on
# the wrong one is a different value in every byte.
CTRL_TARGET = 0x00054320
CTRL_TARGET_2 = 0x00098760

# THE EXCEPTION VECTOR TABLE. `TRAP #0-15` are vector numbers 32 to 47 at
# vector offsets $080 to $0BC, and the vector offset is 4 x vector_number. The
# table is based at the vector base register, whose reset value is zero, and
# these cases do not write it. So the vector longword of `trap #n` is at
# 4 * (32 + n) and these two cases seed exactly that.
TRAP_VECTOR_0 = 4 * 32                  # $080
TRAP_VECTOR_15 = 4 * 47                 # $0BC


def frame_fv(fmt, vector, sr):
    """The first longword of an exception stack frame.

    The first longword holds the 16-bit format/vector word and the 16-bit
    status register, with FORMAT in bits 31..28, FS[3:2] in 27..26,
    VECTOR[7:0] in 25..18, FS[1:0] in 17..16 and the status register in 15..0.

    FS IS ZERO HERE AND THE REFERENCE SAYS WHY. `0000` is "Not an access or
    address error", and the
    field "is defined for access and address errors only and written as zeros
    for all other types of exceptions". A TRAP is neither.
    """
    return (fmt << 28) | (vector << 18) | sr


# ---------------------------------------------------------------------------
# The conditional branch table, and why its cases cannot all start from
# `SR_DIRTY`.
#
# Every other case in this corpus starts from `SR_DIRTY` so that a flag the
# instruction must clear is separable from a flag it never wrote. A `Bcc`
# writes no flag, and the incoming status register is its input: it is the
# whole of what decides whether the branch is taken. One fixed incoming word
# would exercise one truth value of each condition and leave the other
# unreached.
#
# So each condition below carries two condition-code words - one on which it is
# true and one on which it is false - and the pair is chosen to differ in the
# flags that condition reads. `X` is set in both halves of every pair, because
# no condition reads it and its arrival unchanged is the "Bcc touches no flag"
# assertion this group can make.
#
# This table samples the condition table; it does not pin it. Two conditions
# that agree on both words of a pair are not separated by that pair, and the
# corpus cannot afford the condition-code words it takes to separate all
# sixteen. The exhaustive condition matrix is in `tests/t_control.nim`.
#
# THE ENCODING OF EACH CONDITION IS MEASURED AND NOT ASSUMED. Every mnemonic
# below was assembled by `m68k-elf-as -mcpu=5307` at generation time, which is
# what puts `bhi` at 0x62, `bls` at 0x63 and so on; the generator fails if any
# one of them is not an instruction on this part.
BCC_CONDITIONS = [
    # (mnemonic, condition-code bits on which it is TRUE, and on which FALSE)
    ("bhi", 0, CCR_C),                       # !C & !Z
    ("bls", CCR_Z, 0),                       # C | Z
    ("bcc", CCR_Z, CCR_C),                   # !C
    ("bcs", CCR_C, CCR_Z),                   # C
    ("bne", CCR_C, CCR_Z),                   # !Z
    ("beq", CCR_Z, CCR_C),                   # Z
    ("bvc", CCR_C, CCR_V),                   # !V
    ("bvs", CCR_V, CCR_C),                   # V
    ("bpl", CCR_V, CCR_N),                   # !N
    ("bmi", CCR_N, CCR_V),                   # N
    ("bge", CCR_N | CCR_V, CCR_N),           # N == V
    ("blt", CCR_N, CCR_N | CCR_V),           # N != V
    ("bgt", CCR_N | CCR_V, CCR_N | CCR_V | CCR_Z),   # !Z & (N == V)
    ("ble", CCR_N | CCR_V | CCR_Z, CCR_N | CCR_V),   # Z | (N != V)
]

# THE TWO DISPLACEMENT FORMS, AND THE FOUR PROGRAM COUNTERS THEY PRODUCE.
#
# `Bcc <label>` has an operand size of "8,16" and no other, so a branch is
# either two words or one. The four outcomes are four different program
# counters and each one is asserted:
#
#   taken, byte form     opcode + 2 + d8      the displacement is in the opcode
#   taken, word form     opcode + 2 + d16     the base is the DISPLACEMENT WORD
#   not taken, byte      opcode + 2           one word consumed
#   not taken, word      opcode + 4           two words consumed
#
# THE BASE IS THE ADDRESS OF THE WORD AFTER THE OPCODE FOR BOTH FORMS, and it
# is measured, not assumed: `bra.b .+8` assembles to `6006` and `bra.w .+0x2000`
# to `6000 1ffe`, so in each the displacement is the target minus (opcode + 2).
#
# EACH CONDITION ALTERNATES WHICH FORM CARRIES WHICH OUTCOME, so that all four
# rows above are reached across the table rather than only the two a fixed
# assignment would reach.
BCC_TAKEN_BYTE_PC = EXEC_BASE + 2 + 8
BCC_TAKEN_WORD_PC = EXEC_BASE + 2 + 0xFE
BCC_NOT_TAKEN_BYTE_PC = EXEC_BASE + 2
BCC_NOT_TAKEN_WORD_PC = EXEC_BASE + 4


def bcc_cases():
    """One taken and one not-taken case for each of the fourteen conditions."""
    out = []
    for index, (mnemonic, ccr_true, ccr_false) in enumerate(BCC_CONDITIONS):
        taken_is_byte = (index % 2) == 0
        for taken in (True, False):
            byte_form = taken_is_byte if taken else not taken_is_byte
            suffix = "b" if byte_form else "w"
            text = "%s.%s .+%s" % (mnemonic, suffix,
                                   "10" if byte_form else "0x100")
            ccr = ccr_true if taken else ccr_false
            sr = SR_BASE | CCR_X | ccr
            if taken:
                pc = BCC_TAKEN_BYTE_PC if byte_form else BCC_TAKEN_WORD_PC
            else:
                pc = (BCC_NOT_TAKEN_BYTE_PC if byte_form
                      else BCC_NOT_TAKEN_WORD_PC)
            out.append({
                "name": "%s_%s_%s" % (mnemonic,
                                      "taken" if taken else "not_taken",
                                      suffix),
                "mnemonic": mnemonic,
                "instruction": text,
                "initial": {"regs": {"pc": EXEC_BASE, "sr": sr}},
                "expected": {"regs": {"pc": pc, "sr": sr}},
            })
    return out


def assemble_to_words(instruction):
    """Assemble one instruction line and return its machine words.

    Each case is assembled in isolation, so the words returned are exactly
    the encoding of that one instruction and nothing else. The instruction
    is the only line of runnable text; the label keeps the section non-empty
    on assemblers that drop an empty .text.
    """
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "prog.s")
        with open(src, "w") as f:
            f.write(".text\n.global _corpus_seed\n_corpus_seed:\n    "
                    + instruction + "\n")
        obj = os.path.join(td, "prog.o")
        as_r = subprocess.run(
            [M68K_AS, "-mcpu=5307", "-o", obj, src],
            capture_output=True, text=True)
        if as_r.returncode != 0:
            raise SystemExit(
                "generate.py: assembler rejected instruction %r:\n%s"
                % (instruction, as_r.stderr))
        binp = os.path.join(td, "prog.bin")
        subprocess.run(
            [M68K_OBJCOPY, "-O", "binary", "-j", ".text", obj, binp],
            check=True)
        data = open(binp, "rb").read()
    if len(data) % 2 != 0:
        raise SystemExit(
            "generate.py: instruction %r assembled to an odd byte count %d"
            % (instruction, len(data)))
    return ["%04x" % int.from_bytes(data[i:i + 2], "big")
            for i in range(0, len(data), 2)]


# ---------------------------------------------------------------------------
# The seed corpus. One entry per case, in the order it appears in the file.
#
# `initial` and `expected` are {"regs": {...}} states. The expected "regs"
# name only the registers the case must change, plus `sr` wherever the
# condition-code rule is defined for every bit of the word; every other
# register is not asserted.
#
# Two rules govern every case below, and both exist so that the corpus can see
# what it is supposed to be measuring.
#
#   1. The destination never starts at zero where a sized write could merge
#      into it. `DIRTY_D` and `DIRTY_A` are the seeds; see their definition.
#   2. The incoming `sr` is `SR_DIRTY` wherever the case asserts flags at all,
#      so that "the instruction cleared this flag" is separable from "the
#      instruction never wrote this flag".
#
# This table is the generator's source for the cases it emits. Editing a case
# is done here, never in the committed JSON.

CASES = {
    # The condition-code rules of this group. `MOVE` sets N and Z from the
    # value moved at the operand size, clears V and C, and leaves X alone.
    # `MOVEQ` does the same over the sign-extended long. `MOVEA`, `LEA`,
    # `PEA`, `LINK`, `UNLK` and `MOVEM` affect no condition code at all, and
    # each of those expects `SR_DIRTY` straight back.
    "move": [
        {
            # The control against an over-fix of the sized cases below. A
            # long write replaces the whole register: none of the seed
            # survives. A core that merged at every size passes both sized
            # cases and fails here.
            "name": "move_l_d0_to_d1",
            "mnemonic": "move.l",
            "instruction": "move.l %d0,%d1",
            "initial": {"regs": {"d0": 0xAABBCCDD, "d1": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0xAABBCCDD,
                                  "sr": SR_BASE | CCR_X | CCR_N}},
        },
        {
            # `move.l %a0,%a1` is MOVEA.L: destination mode 001. It writes the
            # whole register and touches no condition code, which is why the
            # dirty `sr` comes back unchanged.
            "name": "move_l_a0_to_a1",
            "mnemonic": "move.l",
            "instruction": "move.l %a0,%a1",
            "initial": {"regs": {"a0": 0x1000, "a1": DIRTY_A,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"a1": 0x1000, "sr": SR_DIRTY}},
        },
        {
            "name": "move_l_imm_to_d0",
            "mnemonic": "move.l",
            "instruction": "move.l #0x12345678,%d0",
            "initial": {"regs": {"d0": 0xFFFFFFFF, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x12345678, "sr": SR_BASE | CCR_X}},
        },
        {
            "name": "moveq_5_to_d0",
            "mnemonic": "moveq",
            "instruction": "moveq #5,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 5, "sr": SR_BASE | CCR_X}},
        },
        {
            "name": "lea_4_a0_to_a1",
            "mnemonic": "lea",
            "instruction": "lea (4,%a0),%a1",
            "initial": {"regs": {"a0": 0x1000, "a1": DIRTY_A,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"a1": 0x1004, "sr": SR_DIRTY}},
        },
        {
            # The word merge. The low word is replaced and the upper word of
            # the seed survives; a replacing write gives 0x00001234 here. The
            # source carries 0xFFFF above its low word and none of it may
            # reach the destination, and N comes from bit 15 of the word
            # written (0) and not from bit 31 of the source (1).
            "name": "move_w_d0_to_d1",
            "mnemonic": "move.w",
            "instruction": "move.w %d0,%d1",
            "initial": {"regs": {"d0": 0xFFFF1234, "d1": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0x12341234, "sr": SR_BASE | CCR_X}},
        },
        {
            # The byte merge: 0xAA over the low byte of 0x12345678 is 0x123456AA
            # and a replacing write gives 0x000000AA. Bit 7 of the byte is
            # set, so N is set.
            "name": "move_b_d0_to_d1",
            "mnemonic": "move.b",
            "instruction": "move.b %d0,%d1",
            "initial": {"regs": {"d0": 0xFFFFFFAA, "d1": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0x123456AA,
                                  "sr": SR_BASE | CCR_X | CCR_N}},
        },
        {
            "name": "move_l_mem_to_d0",
            "mnemonic": "move.l",
            "instruction": "move.l (4,%a1),%d0",
            "initial": {"regs": {"a1": 0x200, "d0": 0xFFFFFFFF,
                                 "sr": SR_DIRTY},
                        "mem": [{"addr": 0x204, "size": 4,
                                 "value": 0x12345678}]},
            "expected": {"regs": {"d0": 0x12345678, "sr": SR_BASE | CCR_X}},
        },
        {
            "name": "move_l_d0_to_mem",
            "mnemonic": "move.l",
            "instruction": "move.l %d0,(4,%a1)",
            "initial": {"regs": {"a1": 0x200, "d0": 0xDEADBEEF,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"sr": SR_BASE | CCR_X | CCR_N},
                         "mem": [{"addr": 0x204, "size": 4,
                                  "value": 0xDEADBEEF}]},
        },
        {
            # The byte merge from memory. The load path and the register-to-
            # register path are different code, so the merge is asserted on both.
            "name": "move_b_mem_to_d1",
            "mnemonic": "move.b",
            "instruction": "move.b (0,%a0),%d1",
            "initial": {"regs": {"a0": 0x300, "d1": DIRTY_D,
                                 "sr": SR_DIRTY},
                        "mem": [{"addr": 0x300, "size": 1, "value": 0xAB}]},
            "expected": {"regs": {"d1": 0x123456AB,
                                  "sr": SR_BASE | CCR_X | CCR_N}},
        },
        {
            # MOVEA.W sign-extends into the whole register. It is the one
            # word-sized write in this group that does not merge, so the seed
            # must not survive any part of it.
            "name": "movea_w_imm_signext",
            "mnemonic": "movea.w",
            "instruction": "movea.w #0x8000,%a0",
            "initial": {"regs": {"a0": DIRTY_A, "sr": SR_DIRTY}},
            "expected": {"regs": {"a0": 0xFFFF8000, "sr": SR_DIRTY}},
        },
        {
            "name": "movea_w_d0_signext",
            "mnemonic": "movea.w",
            "instruction": "movea.w %d0,%a1",
            "initial": {"regs": {"d0": 0x00001234, "a1": DIRTY_A,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"a1": 0x1234, "sr": SR_DIRTY}},
        },
        {
            "name": "moveq_neg1_to_d3",
            "mnemonic": "moveq",
            "instruction": "moveq #-1,%d3",
            "initial": {"regs": {"d3": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d3": -1,
                                  "sr": SR_BASE | CCR_X | CCR_N}},
        },
        {
            "name": "movem_l_d0_d3_to_mem",
            "mnemonic": "movem.l",
            "instruction": "movem.l %d0-%d3,(%a1)",
            "initial": {"regs": {"d0": 0x11111111, "d1": 0x22222222,
                                 "d2": 0x33333333, "d3": 0x44444444,
                                 "a1": 0x300, "sr": SR_DIRTY}},
            "expected": {"regs": {"sr": SR_DIRTY},
                         "mem": [
                             {"addr": 0x300, "size": 4, "value": 0x11111111},
                             {"addr": 0x304, "size": 4, "value": 0x22222222},
                             {"addr": 0x308, "size": 4, "value": 0x33333333},
                             {"addr": 0x30C, "size": 4, "value": 0x44444444},
                         ]},
        },
        {
            # The loaded registers start dirty. MOVEM.L replaces each register
            # whole; a load that wrote a half-register would leave part of the
            # seed behind.
            "name": "movem_l_mem_to_a0_a3",
            "mnemonic": "movem.l",
            "instruction": "movem.l (%a1),%a0-%a3",
            "initial": {"regs": {"a0": DIRTY_A, "a1": 0x300,
                                 "a2": 0x1F2E3D4C, "a3": 0x5A6B7C8D,
                                 "sr": SR_DIRTY},
                        "mem": [
                            {"addr": 0x300, "size": 4, "value": 0x55555555},
                            {"addr": 0x304, "size": 4, "value": 0x66666666},
                            {"addr": 0x308, "size": 4, "value": 0x77777777},
                            {"addr": 0x30C, "size": 4, "value": 0x88888888},
                        ]},
            "expected": {"regs": {"a0": 0x55555555, "a1": 0x66666666,
                                  "a2": 0x77777777, "a3": 0x88888888,
                                  "sr": SR_DIRTY}},
        },
        {
            "name": "pea_4_a0",
            "mnemonic": "pea",
            "instruction": "pea (4,%a0)",
            "initial": {"regs": {"a0": 0x400, "a7": 0x1000,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"a7": 0xFFC, "sr": SR_DIRTY},
                         "mem": [{"addr": 0xFFC, "size": 4, "value": 0x404}]},
        },
        {
            "name": "link_a5_neg8",
            "mnemonic": "link",
            "instruction": "link %a5,#-8",
            "initial": {"regs": {"a5": 0x500, "a7": 0x1000,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"a5": 0xFFC, "a7": 0xFF4,
                                  "sr": SR_DIRTY},
                         "mem": [{"addr": 0xFFC, "size": 4, "value": 0x500}]},
        },
        {
            "name": "unlk_a5",
            "mnemonic": "unlk",
            "instruction": "unlk %a5",
            "initial": {"regs": {"a5": 0xFFC, "a7": 0xFF4,
                                 "sr": SR_DIRTY},
                        "mem": [{"addr": 0xFFC, "size": 4, "value": 0x500}]},
            "expected": {"regs": {"a5": 0x500, "a7": 0x1000,
                                  "sr": SR_DIRTY}},
        },

        # -------------------------------------------------------- (xxx).W
        #
        # ONE EXTENSION WORD, AND THE PROGRAM COUNTER SAYS SO. A core that read
        # two words here - the `(xxx).L` shape - would end four bytes past this
        # instruction rather than two, and the `pc` expectation is what catches
        # it. `EA_WINDOW` at the named address gives a value whose bit 31 is
        # set, so the N bit is asserted rather than defaulted.
        {
            "name": "move_l_abs_w_to_d0",
            "mnemonic": "move.l",
            "instruction": "move.l 0x2000.w,%d0",
            "initial": {
                "regs": {"pc": EXEC_BASE, "d0": DIRTY_D, "sr": SR_DIRTY},
                "mem": mem_bytes(ABS_W_ADDR, EA_WINDOW),
            },
            "expected": {
                "regs": {"d0": 0x80112233, "pc": EXEC_BASE + 4,
                         "sr": SR_BASE | CCR_X | CCR_N},
                "mem": mem_bytes(ABS_W_ADDR, EA_WINDOW),
            },
        },

        # -------------------------------------------------------- (xxx).L
        #
        # THE TWO EXTENSION WORDS ARE HIGH HALF FIRST. See `ABS_L_ADDR` above
        # for the manual section and the assembler measurement. These two cases
        # are the read path and the write path, and each one names the address
        # the OTHER reading would reach and asserts that window untouched.
        {
            "name": "move_l_abs_l_to_d0",
            "mnemonic": "move.l",
            "instruction": "move.l 0x00030004,%d0",
            "initial": {
                "regs": {"d0": DIRTY_D, "sr": SR_DIRTY},
                "mem": (mem_bytes(ABS_L_ADDR, EA_WINDOW)
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
            "expected": {
                "regs": {"d0": 0x80112233, "pc": EXEC_BASE + 6,
                         "sr": SR_BASE | CCR_X | CCR_N},
                "mem": (mem_bytes(ABS_L_ADDR, EA_WINDOW)
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
        },
        {
            "name": "move_l_d0_to_abs_l",
            "mnemonic": "move.l",
            "instruction": "move.l %d0,0x00030004",
            "initial": {
                "regs": {"d0": 0xDEADBEEF, "sr": SR_DIRTY},
                "mem": ([{"addr": ABS_L_ADDR, "size": 4, "value": 0x80112233},
                         {"addr": ABS_L_ADDR + 4, "size": 4,
                          "value": MEM_GUARD}]
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
            "expected": {
                "regs": {"pc": EXEC_BASE + 6,
                         "sr": SR_BASE | CCR_X | CCR_N},
                "mem": ([{"addr": ABS_L_ADDR, "size": 4, "value": 0xDEADBEEF},
                         {"addr": ABS_L_ADDR + 4, "size": 4,
                          "value": MEM_GUARD}]
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
        },

        # ------------------------------------------------------- (d16,PC)
        #
        # THE OPERAND IS ONE BYTE AND IT IS THE ONE THE INSTRUCTION NAMES. The
        # byte at `PC_OPERAND` is 0x80 and the byte two along - where a core
        # that based the address after the displacement word would read - is
        # 0x22. The two differ in bit 7, so the merged destination AND the N
        # bit both separate the two readings.
        {
            "name": "move_b_pc_disp_to_d0",
            "mnemonic": "move.b",
            "instruction": "move.b (0x1e,%pc),%d0",
            "initial": {
                "regs": {"pc": EXEC_BASE, "d0": DIRTY_D, "sr": SR_DIRTY},
                "mem": mem_bytes(PC_OPERAND, EA_WINDOW),
            },
            "expected": {
                "regs": {"d0": 0x12345680, "pc": EXEC_BASE + 4,
                         "sr": SR_BASE | CCR_X | CCR_N},
                "mem": mem_bytes(PC_OPERAND, EA_WINDOW),
            },
        },

        # ----------------------------------------------------- (d8,PC,Xn)
        #
        # THE INDEX IS A LONGWORD, and `INDEX_VALUE` is the value that says so:
        # a core that took the low word and sign-extended it reads 65536 bytes
        # lower, where `EA_DECOY_WINDOW` sits. See `INDEX_VALUE` above.
        {
            "name": "move_b_pc_index_to_d0",
            "mnemonic": "move.b",
            "instruction": "move.b (4,%pc,%d2),%d0",
            "initial": {
                "regs": {"pc": EXEC_BASE, "d0": DIRTY_D, "d2": INDEX_VALUE,
                         "sr": SR_DIRTY},
                "mem": (mem_bytes(PC_INDEX_OPERAND, EA_WINDOW)
                        + mem_bytes(PC_INDEX_DECOY, EA_DECOY_WINDOW)),
            },
            "expected": {
                "regs": {"d0": 0x12345680, "d2": INDEX_VALUE,
                         "pc": EXEC_BASE + 4,
                         "sr": SR_BASE | CCR_X | CCR_N},
                "mem": (mem_bytes(PC_INDEX_OPERAND, EA_WINDOW)
                        + mem_bytes(PC_INDEX_DECOY, EA_DECOY_WINDOW)),
            },
        },
    ],

    # The condition-code rules of this group. `ADD`, `SUB`, `ADDQ`, `SUBQ`,
    # `ADDI` and `NEG` set N and Z from the result, V from the signed overflow,
    # and C and X together from the carry or the borrow out of bit 31 - X is
    # recomputed by these, not preserved. `CLR` sets Z, clears N, V and C, and
    # leaves X alone. `EXT` and the 32-bit multiply set N and Z from the
    # result, clear C, and leave X alone; the multiply's V reports that the 32
    # bits written are not the whole product.
    #
    # Half of this group is the flags. Every `sr` below was measured against a
    # mutation the corpus would otherwise not see.
    "alu": [
        {
            "name": "add_l_d0_to_d1",
            "mnemonic": "add.l",
            "instruction": "add.l %d0,%d1",
            "initial": {"regs": {"d0": 1, "d1": 2, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 3, "sr": SR_BASE}},
        },
        {
            # The carry out of bit 31 sets both C and X, and the result is
            # zero, so Z is set too. Dropping ADD's carry-out is invisible
            # without this case: `add.l` of 1 and 2 carries nothing, and the
            # register result 0 is the same either way.
            "name": "add_l_carry_out",
            "mnemonic": "add.l",
            "instruction": "add.l %d0,%d1",
            "initial": {"regs": {"d0": 1, "d1": 0xFFFFFFFF,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0,
                                  "sr": SR_BASE | CCR_C | CCR_X | CCR_Z}},
        },
        {
            # The signed overflow is a different question from the carry, and
            # this case is where the two disagree: 0x7FFFFFFF + 1 crosses into
            # the negative half, so V and N are set and C is clear. A core that
            # reported the carry as the overflow fails here and a core that
            # dropped V altogether fails here; the register result is right in
            # both.
            "name": "add_l_signed_overflow",
            "mnemonic": "add.l",
            "instruction": "add.l %d0,%d1",
            "initial": {"regs": {"d0": 1, "d1": 0x7FFFFFFF,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0x80000000,
                                  "sr": SR_BASE | CCR_V | CCR_N}},
        },
        {
            "name": "sub_l_d0_from_d1",
            "mnemonic": "sub.l",
            "instruction": "sub.l %d0,%d1",
            "initial": {"regs": {"d0": 1, "d1": 2, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 1, "sr": SR_BASE}},
        },
        {
            # The borrow sets C and X. 1 - 2 is -1, which a core that dropped
            # the borrow still computes correctly.
            "name": "sub_l_borrow",
            "mnemonic": "sub.l",
            "instruction": "sub.l %d0,%d1",
            "initial": {"regs": {"d0": 2, "d1": 1, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": -1,
                                  "sr": SR_BASE | CCR_C | CCR_X | CCR_N}},
        },
        {
            # NEG sets C whenever a borrow left the word, which for a negation
            # is exactly "the operand was not zero". The register result -5 is
            # the same with or without that rule.
            "name": "neg_l_d0",
            "mnemonic": "neg.l",
            "instruction": "neg.l %d0",
            "initial": {"regs": {"d0": 5, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": -5,
                                  "sr": SR_BASE | CCR_C | CCR_X | CCR_N}},
        },
        {
            # CLR leaves X alone. It is the one instruction in this group that
            # does, and a dirty incoming X is the only way to say so: from a
            # clear X, "preserved" and "cleared" are the same answer.
            "name": "clr_l_d0",
            "mnemonic": "clr.l",
            "instruction": "clr.l %d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0, "sr": SR_BASE | CCR_Z | CCR_X}},
        },
        {
            "name": "addq_l_1_to_d1",
            "mnemonic": "addq.l",
            "instruction": "addq.l #1,%d1",
            "initial": {"regs": {"d1": 6, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 7, "sr": SR_BASE}},
        },
        {
            # The ADDQ data field 000 means eight, not zero. One to seven
            # encode themselves and zero would be a no-operation, so the
            # encoding spends that slot on the eighth value. No other case
            # separates the two readings: every other ADDQ here uses #1.
            "name": "addq_l_8_to_d1",
            "mnemonic": "addq.l",
            "instruction": "addq.l #8,%d1",
            "initial": {"regs": {"d1": 6, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 14, "sr": SR_BASE}},
        },
        {
            "name": "subq_l_1_from_d0",
            "mnemonic": "subq.l",
            "instruction": "subq.l #1,%d0",
            "initial": {"regs": {"d0": 6, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 5, "sr": SR_BASE}},
        },
        {
            "name": "addi_l_7_to_d1",
            "mnemonic": "addi.l",
            "instruction": "addi.l #7,%d1",
            "initial": {"regs": {"d1": 1, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 8, "sr": SR_BASE}},
        },
        {
            "name": "mulu_l_d0_by_d1",
            "mnemonic": "mulu.l",
            "instruction": "mulu.l %d0,%d1",
            "initial": {"regs": {"d0": 3, "d1": 4, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 12, "sr": SR_BASE | CCR_X}},
        },
        {
            # V STAYS CLEAR WHEN THE 32 BITS WRITTEN ARE NOT THE WHOLE PRODUCT.
            # 0x10000 squared is 0x1_0000_0000, whose low 32 bits are zero, so
            # on this part the case really is indistinguishable from a multiply
            # by zero. The reference gives V "Always cleared" and adds "Note
            # that CCR[V] is always cleared by MULU, unlike the 68K family
            # processors". The initial SR_DIRTY carries V SET, so a core that
            # never writes V fails on the status word.
            "name": "mulu_l_truncation_clears_v",
            "mnemonic": "mulu.l",
            "instruction": "mulu.l %d0,%d1",
            "initial": {"regs": {"d0": 0x10000, "d1": 0x10000,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0,
                                  "sr": SR_BASE | CCR_Z | CCR_X}},
        },
        {
            # N COMES FROM BIT 31 OF THE UNSIGNED PRODUCT, so MULU's N is not
            # always zero. 2 * 0x50000000 is 0xA0000000: no part of the product
            # is lost and bit 31 is set. The reference: "N Set if result is
            # negative; cleared otherwise". SR_DIRTY carries Z set, so a core
            # that leaves Z alone fails this too.
            "name": "mulu_l_sets_n_from_bit31",
            "mnemonic": "mulu.l",
            "instruction": "mulu.l %d0,%d1",
            "initial": {"regs": {"d0": 0x2, "d1": 0x50000000,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0xA0000000,
                                  "sr": SR_BASE | CCR_N | CCR_X}},
        },

        # ---------------------------------- THE WORD MULTIPLY AND DIVIDE
        #
        # The word forms are real instructions - `m68k-elf-as -mcpu=5307`
        # assembles them, the reference prints a "(Word)" instruction format
        # for each, and the timing table times them.
        #
        # EVERY EXPECTED VALUE BELOW IS DERIVED FROM THE REFERENCE AND NOT FROM
        # THIS PROJECT'S CORE. This generator takes only the ENCODING from the
        # assembler; the register and status words are hand-written here, so
        # a case that merely echoed the implementation would ratify it.
        {
            # THE UPPER WORD OF EITHER OPERAND IS IGNORED ON INPUT. The
            # reference: "A register operand is the low-order word; the upper
            # word of the register is ignored." Both registers carry a
            # distinctive upper half, so a core multiplying the full 32 bits
            # writes neither 12 nor anything close to it.
            "name": "mulu_w_ignores_the_upper_words",
            "mnemonic": "mulu.w",
            "instruction": "mulu.w %d0,%d1",
            "initial": {"regs": {"d0": 0xDEAD0003, "d1": 0xBEEF0004,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 12, "sr": SR_BASE | CCR_X}},
        },
        {
            # THE WORD FORM CONSUMES NO EXTENSION WORD, AND THE PROGRAM
            # COUNTER IS THE ONLY PLACE THAT SHOWS IT. The word form is ONE
            # instruction word - Dx is bits 11..9 of that word and the
            # signedness is bits 8..6 - where the long form takes both from a
            # second word it fetches. `src/mcf5307/decode.nim` states the
            # hazard: "an executor that fetched an extension word here would
            # consume the NEXT INSTRUCTION".
            #
            # WITH A REGISTER SOURCE THERE IS NOTHING ELSE TO SEE. A memory
            # source would move the operand address and change the product
            # too, so the over-fetch would be caught by the register value
            # and the PC would prove nothing on its own. `%d0` reads no
            # memory, so an executor that fetched an extension word here
            # writes the SAME 42 into `d1` and the SAME status word, and
            # leaves the program counter at EXEC_BASE + 4 instead of
            # EXEC_BASE + 2. That single difference is the whole case.
            #
            # `d0` IS PINNED IN THE EXPECTED STATE as the control: the source
            # register must survive unchanged, so an executor that wrote the
            # product to the wrong register cannot pass by leaving `d1`
            # alone. `mulu.w %d0,%d1` is `c2c0`, two bytes.
            "name": "mulu_w_reg_source_takes_no_extension_word",
            "mnemonic": "mulu.w",
            "instruction": "mulu.w %d0,%d1",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": 6, "d1": 7,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 6, "d1": 42, "pc": EXEC_BASE + 2,
                                  "sr": SR_BASE | CCR_X}},
        },
        {
            # ALL 32 BITS OF THE PRODUCT ARE SAVED - the reference's own
            # sentence - so a 16x16 product keeps its whole width. A core that
            # wrote only the low word gives 0x0000FFFD.
            "name": "muls_w_sign_extends_both_word_operands",
            "mnemonic": "muls.w",
            "instruction": "muls.w %d0,%d1",
            "initial": {"regs": {"d0": 0xFFFF, "d1": 3, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0xFFFFFFFD,
                                  "sr": SR_BASE | CCR_N | CCR_X}},
        },
        {
            # THE SAME TWO WORDS UNSIGNED. The signed bit is UNOBSERVABLE in
            # the longword multiply - the low 32 bits of a 32x32 product do
            # not depend on how the sign bits are read - and it IS observable
            # here, because a 16x16 product is kept whole. This pair is what
            # separates the two opcodes on the result itself.
            "name": "mulu_w_of_the_same_two_words_is_unsigned",
            "mnemonic": "mulu.w",
            "instruction": "mulu.w %d0,%d1",
            "initial": {"regs": {"d0": 0xFFFF, "d1": 3, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0x0002FFFD, "sr": SR_BASE | CCR_X}},
        },
        {
            # ONE LONGWORD HOLDING TWO HALVES. The reference:
            # "the 16-bit quotient is in the lower word and the 16-bit
            # remainder is in the upper word of the destination".
            "name": "divu_w_packs_remainder_high_and_quotient_low",
            "mnemonic": "divu.w",
            "instruction": "divu.w %d0,%d1",
            "initial": {"regs": {"d0": 3, "d1": 17, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0x00020005, "sr": SR_BASE | CCR_X}},
        },
        {
            # THE REMAINDER TAKES THE DIVIDEND'S SIGN - "Note that the sign of
            # the remainder is the same as the sign of the dividend" - and the
            # quotient truncates TOWARD ZERO. -17 / 3 is -5 remainder -2. A
            # core using a flooring division gives -6 remainder +1, which is
            # 0x0001FFFA, and fails on both halves at once.
            "name": "divs_w_remainder_takes_the_dividend_sign",
            "mnemonic": "divs.w",
            "instruction": "divs.w %d0,%d1",
            "initial": {"regs": {"d0": 3, "d1": 0xFFFFFFEF, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0xFFFEFFFB,
                                  "sr": SR_BASE | CCR_N | CCR_X}},
        },
        {
            # N COMES FROM THE QUOTIENT AND NOT FROM THE LONGWORD WRITTEN.
            # Folios 4-31 and 4-33: "N ... set if the QUOTIENT is negative".
            # -17 / -5 is quotient +3 with remainder -2, so the register's bit
            # 31 is SET while the quotient is positive; a core taking N from
            # the register it just wrote reports the remainder's sign and
            # fails on the status word alone.
            "name": "divs_w_n_comes_from_the_quotient_not_bit31",
            "mnemonic": "divs.w",
            "instruction": "divs.w %d0,%d1",
            "initial": {"regs": {"d0": 0xFFFB, "d1": 0xFFFFFFEF,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0xFFFE0003, "sr": SR_BASE | CCR_X}},
        },
        {
            # THE WORD OVERFLOW. "An overflow occurs if the quotient is larger
            # than a 16-bit (.W) ... signed integer", and "if overflow is
            # detected, the destination register is unaffected". 65536 / 1 is
            # 65536, which no 16-bit signed integer holds. SR_DIRTY enters
            # with N, Z and C SET, so this pins V set, N and Z CLEARED, C
            # cleared and X carried through.
            "name": "divs_w_overflow_clears_n_and_z",
            "mnemonic": "divs.w",
            "instruction": "divs.w %d0,%d1",
            "initial": {"regs": {"d0": 1, "d1": 0x00010000, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0x00010000,
                                  "sr": SR_BASE | CCR_V | CCR_X}},
        },
        {
            # THIS CASE IS AN INFERENCE AND NOT A MEASUREMENT, AND IT IS THE
            # ONLY ONE IN THE DIVIDE PATH. The reference says an overflow occurs
            # if the quotient is "larger than a 16-bit (.W) signed integer"
            # and do not define "larger" at the asymmetric end of the range.
            # -32768 IS a 16-bit signed integer, so under the reading taken by
            # `src/mcf5307/alu.nim` - which marks it at the comparison that
            # decides it - -65536 / 2 does NOT overflow and writes a quotient
            # of 0x8000 with a remainder of 0.
            #
            # THE OTHER READING is that "larger" means larger in MAGNITUDE
            # than the largest positive value, under which this case would set
            # V and leave d1 at 0xFFFF0000. WHAT WOULD SETTLE IT: this exact
            # case run on silicon or a hardware model, or an erratum. IF THIS
            # CORPUS IS EVER RUN AGAINST REAL HARDWARE, THIS IS THE CASE TO
            # READ FIRST.
            "name": "divs_w_quotient_of_minus_32768_does_not_overflow",
            "mnemonic": "divs.w",
            "instruction": "divs.w %d0,%d1",
            "initial": {"regs": {"d0": 2, "d1": 0xFFFF0000, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0x00008000,
                                  "sr": SR_BASE | CCR_N | CCR_X}},
        },
        {
            # THE WORD FORM'S OPERAND CLASS IS WIDER THAN THE LONG FORM'S. An
            # immediate source is dashed on every "(Longword)" table and
            # carried on every "(Word)" table,
            # and `m68k-elf-as -mcpu=5307` agrees: it assembles
            # `mulu.w #5,%d1` and rejects `mulu.l #5,%d1`.
            "name": "mulu_w_takes_an_immediate_source",
            "mnemonic": "mulu.w",
            "instruction": "mulu.w #5,%d1",
            "initial": {"regs": {"d1": 4, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 20, "sr": SR_BASE | CCR_X}},
        },

        # -------------------------------------------- DIVS, REMU and REMS
        #
        # Each case below is chosen to be DISCRIMINATING on the status word,
        # which is the half of these instructions that a plausible wrong
        # implementation gets wrong while still writing the right register.
        {
            # AN OVERFLOW CLEARS N AND Z. The reference: "N
            # Cleared if overflow is detected", "Z Cleared if overflow is
            # detected", with "V Set if an overflow occurs", "C Always cleared"
            # and X "Not affected". The most negative value over -1 has no
            # quotient, so d1 IS UNCHANGED and only the status word moves.
            # SR_DIRTY enters with N, Z and C SET, so a core that leaves N and
            # Z as it found them fails here.
            "name": "divs_l_overflow_clears_n_and_z",
            "mnemonic": "divs.l",
            "instruction": "divs.l %d0,%d1",
            "initial": {"regs": {"d0": 0xFFFFFFFF, "d1": 0x80000000,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0x80000000,
                                  "sr": SR_BASE | CCR_V | CCR_X}},
        },
        {
            # Z COMES FROM THE QUOTIENT AND NOT FROM THE REMAINDER WRITTEN.
            # The reference: "Z ... set if the quotient is zero, cleared if
            # nonzero", while the operation line is "Destination/Source ->
            # Remainder". 20 / 5 is a quotient of 4 with a remainder of ZERO,
            # so the two rules disagree on Z and agree on the register: d2
            # takes 0 either way. ONLY the status word separates them.
            "name": "remu_l_z_from_quotient_not_remainder",
            "mnemonic": "remu.l",
            "instruction": "remu.l %d0,%d2:%d1",
            "initial": {"regs": {"d0": 5, "d1": 20, "d2": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 20, "d2": 0,
                                  "sr": SR_BASE | CCR_X}},
        },
        {
            # N COMES FROM THE QUOTIENT TOO. The reference: "N ... set if
            # the quotient is negative". 17 / -5 is a quotient of -3 with a
            # remainder of +2 - the remainder takes the sign of the DIVIDEND -
            # so the quotient rule sets N and the remainder rule clears it.
            "name": "rems_l_n_from_quotient_not_remainder",
            "mnemonic": "rems.l",
            "instruction": "rems.l %d0,%d2:%d1",
            "initial": {"regs": {"d0": 0xFFFFFFFB, "d1": 17, "d2": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 17, "d2": 2,
                                  "sr": SR_BASE | CCR_N | CCR_X}},
        },
        {
            # EXT.L replaces the whole register from its low word, so the seed
            # above that word must not survive. N comes from bit 31 of the
            # extended long, and X is untouched.
            "name": "ext_l_d0_word",
            "mnemonic": "ext.l",
            "instruction": "ext.l %d0",
            "initial": {"regs": {"d0": 0xAAAA8000, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": -32768,
                                  "sr": SR_BASE | CCR_N | CCR_X}},
        },

        # -------------------------------------------------------- (xxx).W
        {
            "name": "add_l_abs_w_to_d1",
            "mnemonic": "add.l",
            "instruction": "add.l 0x2000.w,%d1",
            "initial": {
                "regs": {"pc": EXEC_BASE, "d1": DIRTY_D, "sr": SR_DIRTY},
                "mem": mem_bytes(ABS_W_ADDR, EA_WINDOW),
            },
            "expected": {
                "regs": {"d1": 0x924578AB, "pc": EXEC_BASE + 4,
                         "sr": SR_BASE | CCR_N},
                "mem": mem_bytes(ABS_W_ADDR, EA_WINDOW),
            },
        },

        # -------------------------------------------------------- (xxx).L
        #
        # ADD's `<ea>` operand takes DATA addressing, so the absolute modes are
        # in. The addend at the swapped address is `MEM_GUARD`, whose sum with
        # the seed is neither the expected value nor negative, so the register
        # and the status word both separate the two readings.
        {
            "name": "add_l_abs_l_to_d1",
            "mnemonic": "add.l",
            "instruction": "add.l 0x00030004,%d1",
            "initial": {
                "regs": {"d1": DIRTY_D, "sr": SR_DIRTY},
                "mem": (mem_bytes(ABS_L_ADDR, EA_WINDOW)
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
            "expected": {
                "regs": {"d1": 0x924578AB, "pc": EXEC_BASE + 6,
                         "sr": SR_BASE | CCR_N},
                "mem": (mem_bytes(ABS_L_ADDR, EA_WINDOW)
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
        },

        # ------------------------------------------------------- (d16,PC)
        #
        # THE LONGWORD READ, where the byte cases above read a byte. The
        # longword at `PC_OPERAND` is 0x80112233 and the one two bytes along is
        # 0x22334455, so the sum and the N bit both separate the two readings.
        {
            "name": "add_l_pc_disp_to_d1",
            "mnemonic": "add.l",
            "instruction": "add.l (0x1e,%pc),%d1",
            "initial": {
                "regs": {"pc": EXEC_BASE, "d1": DIRTY_D, "sr": SR_DIRTY},
                "mem": mem_bytes(PC_OPERAND, EA_WINDOW),
            },
            "expected": {
                "regs": {"d1": 0x924578AB, "pc": EXEC_BASE + 4,
                         "sr": SR_BASE | CCR_N},
                "mem": mem_bytes(PC_OPERAND, EA_WINDOW),
            },
        },

        # ----------------------------------------------------- (d8,PC,Xn)
        {
            "name": "add_l_pc_index_to_d1",
            "mnemonic": "add.l",
            "instruction": "add.l (4,%pc,%d2),%d1",
            "initial": {
                "regs": {"pc": EXEC_BASE, "d1": DIRTY_D, "d2": INDEX_VALUE,
                         "sr": SR_DIRTY},
                "mem": (mem_bytes(PC_INDEX_OPERAND, EA_WINDOW)
                        + mem_bytes(PC_INDEX_DECOY, EA_DECOY_WINDOW)),
            },
            "expected": {
                "regs": {"d1": 0x924578AB, "d2": INDEX_VALUE,
                         "pc": EXEC_BASE + 4, "sr": SR_BASE | CCR_N},
                "mem": (mem_bytes(PC_INDEX_OPERAND, EA_WINDOW)
                        + mem_bytes(PC_INDEX_DECOY, EA_DECOY_WINDOW)),
            },
        },
    ],

    # The condition-code rules of this group, and where each one comes from.
    #
    #   AND, ANDI, OR, ORI, EOR, EORI, NOT
    #       N and Z from the 32-bit result, V and C cleared, X untouched. The
    #       MCF5307 User's Manual section 3.2.1.5 defines V as set "if an
    #       arithmetic overflow occurs", C as set on "a carryout of the operand
    #       MSB ... for an addition, or ... a borrow ... in a subtraction", and
    #       X as "set to the value of the C-bit for arithmetic operations;
    #       otherwise not affected". A logical operation is neither an addition
    #       nor a subtraction, so V and C are cleared and X is left alone. This
    #       is the same rule `setNzClearVc` in `src/mcf5307/machine.nim`
    #       already carries for MOVE.
    #
    #   BTST, BSET, BCLR, BCHG
    #       Z alone. The manual's Table 3-7 gives the operation as
    #       `~(<Bit Number> of Destination) -> Z` and names no other bit, so N,
    #       V, C and X are untouched. Every bit case below therefore starts
    #       from a status word in which Z has the wrong value and asserts the
    #       whole word back: a case whose bit is set starts with Z set, and a
    #       case whose bit is clear starts with Z clear. A case that started
    #       from the value it expects would pass against a core that never
    #       writes Z at all.
    #
    #   LSL, LSR, ASL, ASR
    #       X and C both take the last bit shifted out, which Table 3-7 states
    #       directly for all four: `X/C <- (Dy << Dx) <- 0` for the two left
    #       shifts and `MSB -> (Dy >> Dx) -> X/C`, `0 -> (Dy >> Dx) -> X/C` for
    #       the two right ones. N and Z come from the result. V IS CLEARED BY
    #       ALL FOUR, ASL INCLUDED.
    #
    # ASL'S V IS SETTLED, AND THE REFERENCE SETTLES IT. Folio 4-12 gives V a
    # flat "Always cleared" and adds "Note that CCR[V] is always cleared by ASL
    # and ASR, unlike on the 68K family processors"; the prose says "The
    # overflow bit is always zero". ColdFire computes no ASL overflow at all, so
    # there is no dichotomy to hedge and no count that separates anything. The
    # shift count of a V case is free to be whatever the case needs.
    #
    # The register shift count of zero carries no `sr`, for the same reason:
    # what a zero count does to C is a rule this project cannot cite today. The
    # case still earns its place - it asserts the destination is unchanged,
    # which a core that read the count out of the instruction word instead of
    # out of the register would fail, because that core shifts by one.
    "logic": [
        # ------------------------------------------------------------ AND
        {
            "name": "and_l_d0_d1",
            "mnemonic": "and.l",
            "instruction": "and.l %d0,%d1",
            "initial": {"regs": {"d0": 0x0F0F0F0F, "d1": DIRTY_D,
                                 "sr": SR_DIRTY}},
            # The source register is asserted unchanged, so a core that wrote
            # the result into the wrong operand fails here and not only on the
            # destination.
            "expected": {"regs": {"d0": 0x0F0F0F0F, "d1": 0x02040608,
                                  "sr": SR_BASE | CCR_X}},
        },
        {
            "name": "and_l_result_negative_sets_n",
            "mnemonic": "and.l",
            "instruction": "and.l %d0,%d1",
            "initial": {"regs": {"d0": 0xF0F0F0F0, "d1": 0x87654321,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0x80604020,
                                  "sr": SR_BASE | CCR_N | CCR_X}},
        },
        {
            "name": "and_l_result_zero_sets_z",
            "mnemonic": "and.l",
            "instruction": "and.l %d0,%d1",
            "initial": {"regs": {"d0": 0x0000FFFF, "d1": 0x12340000,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0,
                                  "sr": SR_BASE | CCR_Z | CCR_X}},
        },
        {
            # THE OTHER DIRECTION: `Dn & <ea> -> <ea>`, whose destination is a
            # memory-alterable operand and NOT the same operand class as the
            # direction above. The guard longword after the destination is
            # asserted unchanged, so a store that was too wide fails.
            "name": "and_l_d1_to_memory",
            "mnemonic": "and.l",
            "instruction": "and.l %d1,(%a0)",
            "initial": {
                "regs": {"a0": MEM_BASE, "d1": DIRTY_D, "sr": SR_DIRTY},
                "mem": [{"addr": MEM_BASE, "size": 4, "value": 0xF0F0F0F0},
                        {"addr": MEM_BASE + 4, "size": 4, "value": MEM_GUARD}],
            },
            "expected": {
                "regs": {"a0": MEM_BASE, "d1": DIRTY_D,
                         "sr": SR_BASE | CCR_X},
                "mem": [{"addr": MEM_BASE, "size": 4, "value": 0x10305070},
                        {"addr": MEM_BASE + 4, "size": 4, "value": MEM_GUARD}],
            },
        },

        # ----------------------------------------------------------- ANDI
        {
            "name": "andi_l_d1",
            "mnemonic": "andi.l",
            "instruction": "andi.l #0x0f0f0f0f,%d1",
            "initial": {"regs": {"d1": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0x02040608,
                                  "sr": SR_BASE | CCR_X}},
        },

        # ------------------------------------------------------------- OR
        {
            "name": "or_l_d0_d1",
            "mnemonic": "or.l",
            "instruction": "or.l %d0,%d1",
            "initial": {"regs": {"d0": 0x0F0F0F0F, "d1": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x0F0F0F0F, "d1": 0x1F3F5F7F,
                                  "sr": SR_BASE | CCR_X}},
        },
        {
            "name": "or_l_result_negative_sets_n",
            "mnemonic": "or.l",
            "instruction": "or.l %d0,%d1",
            "initial": {"regs": {"d0": 0x80000000, "d1": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0x92345678,
                                  "sr": SR_BASE | CCR_N | CCR_X}},
        },
        {
            # THE SOURCE REGISTER AND THE ADDRESS REGISTER ARE BOTH ASSERTED
            # UNCHANGED, exactly as `and_l_d1_to_memory` asserts them. The
            # runner compares only the registers a case NAMES, so a case that
            # named `sr` alone was blind to a core that clobbered either one.
            "name": "or_l_d1_to_memory",
            "mnemonic": "or.l",
            "instruction": "or.l %d1,(%a0)",
            "initial": {
                "regs": {"a0": MEM_BASE, "d1": DIRTY_D, "sr": SR_DIRTY},
                "mem": [{"addr": MEM_BASE, "size": 4, "value": 0x0F0F0F0F},
                        {"addr": MEM_BASE + 4, "size": 4, "value": MEM_GUARD}],
            },
            "expected": {
                "regs": {"a0": MEM_BASE, "d1": DIRTY_D,
                         "sr": SR_BASE | CCR_X},
                "mem": [{"addr": MEM_BASE, "size": 4, "value": 0x1F3F5F7F},
                        {"addr": MEM_BASE + 4, "size": 4, "value": MEM_GUARD}],
            },
        },

        # ------------------------------------------------------------ ORI
        {
            "name": "ori_l_d0",
            "mnemonic": "ori.l",
            "instruction": "ori.l #0x0000ff00,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x1234FF78,
                                  "sr": SR_BASE | CCR_X}},
        },

        # ------------------------------------------------------------ EOR
        {
            # EOR HAS ONE DIRECTION ONLY on this part: `Dn ^ <ea> -> <ea>`.
            # `eor.l (%a0),%d1` is not an encoding the assembler will produce
            # for `-mcpu=5307`, so the destination here is the data register
            # named by the effective address and not by bits 11..9.
            "name": "eor_l_d0_d1",
            "mnemonic": "eor.l",
            "instruction": "eor.l %d0,%d1",
            "initial": {"regs": {"d0": 0xFFFF0000, "d1": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0xFFFF0000, "d1": 0xEDCB5678,
                                  "sr": SR_BASE | CCR_N | CCR_X}},
        },
        {
            "name": "eor_l_d0_with_itself_sets_z",
            "mnemonic": "eor.l",
            "instruction": "eor.l %d0,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0,
                                  "sr": SR_BASE | CCR_Z | CCR_X}},
        },
        {
            # THE SOURCE REGISTER AND THE ADDRESS REGISTER ARE BOTH ASSERTED
            # UNCHANGED. `execEor` is a SEPARATE path from `execAndOr`.
            "name": "eor_l_d1_to_memory",
            "mnemonic": "eor.l",
            "instruction": "eor.l %d1,(%a0)",
            "initial": {
                "regs": {"a0": MEM_BASE, "d1": DIRTY_D, "sr": SR_DIRTY},
                "mem": [{"addr": MEM_BASE, "size": 4, "value": 0xFFFF0000},
                        {"addr": MEM_BASE + 4, "size": 4, "value": MEM_GUARD}],
            },
            "expected": {
                "regs": {"a0": MEM_BASE, "d1": DIRTY_D,
                         "sr": SR_BASE | CCR_N | CCR_X},
                "mem": [{"addr": MEM_BASE, "size": 4, "value": 0xEDCB5678},
                        {"addr": MEM_BASE + 4, "size": 4, "value": MEM_GUARD}],
            },
        },

        # ----------------------------------------------------------- EORI
        {
            "name": "eori_l_d1",
            "mnemonic": "eori.l",
            "instruction": "eori.l #0xffffffff,%d1",
            "initial": {"regs": {"d1": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0xEDCBA987,
                                  "sr": SR_BASE | CCR_N | CCR_X}},
        },

        # ------------------------------------------------------------ NOT
        {
            "name": "not_l_d0",
            "mnemonic": "not.l",
            "instruction": "not.l %d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0xEDCBA987,
                                  "sr": SR_BASE | CCR_N | CCR_X}},
        },
        {
            "name": "not_l_all_ones_sets_z",
            "mnemonic": "not.l",
            "instruction": "not.l %d0",
            "initial": {"regs": {"d0": 0xFFFFFFFF, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0,
                                  "sr": SR_BASE | CCR_Z | CCR_X}},
        },

        # ----------------------------------------------------------- BTST
        #
        # A bit operation on a data register is 32 bits wide and one on memory
        # is 8. That is the operand size column of MCF5307 User's Manual
        # Table 3-7, which reads "8,32" for BTST, BSET, BCLR and BCHG and for
        # no other instruction in this group. The two cases that pin it are
        # `btst_l_bit_number_above_a_byte` and
        # `btst_b_memory_operand_is_one_byte`. Each one picks a bit number
        # whose answer under the other width is the opposite, so neither can
        # pass against a core that applies the wrong one.
        #
        # Neither case uses a bit number its operand cannot hold, and that is
        # deliberate. `logic.nim` reduces an out-of-range bit number modulo the
        # operand width, and no passage of the reference states any modulus -
        # and Figure 3-8's `MODULO (OFFSET)` annotation does not settle it.
        # That reduction is this core's choice, and the corpus must not pin a
        # choice no document supports. The two cases below get the same
        # discrimination out of in-range numbers:
        #
        #   - bit 9 of the seed is set, and a core that treated a data
        #     register operand as a byte could not reach bit 9 at all;
        #   - bit 1 of the addressed byte 0x02 is set while bit 1 of the
        #     longword at the same address (0x025A3CC1, low byte 0xC1) is
        #     clear, so a longword access answers the opposite.
        {
            "name": "btst_l_set_bit_clears_z",
            "mnemonic": "btst",
            "instruction": "btst #4,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": DIRTY_D,
                                  "sr": SR_DIRTY & ~CCR_Z}},
        },
        {
            "name": "btst_l_clear_bit_sets_z",
            "mnemonic": "btst",
            "instruction": "btst #7,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY & ~CCR_Z}},
            "expected": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
        },
        {
            # A data register operand is 32 bits, so bit 9 exists. Bit 9 of
            # the seed 0x12345678 is set, so Z is cleared. A core that gave a
            # register operand the memory width of 8 could not name bit 9 at
            # all: under any byte reading it reaches bit 1 of 0x78, which is
            # clear, and sets Z. The bit number is inside the operand either
            # way, so this case asserts the width and pins no modulus.
            "name": "btst_l_bit_number_above_a_byte",
            "mnemonic": "btst",
            "instruction": "btst #9,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": DIRTY_D,
                                  "sr": SR_DIRTY & ~CCR_Z}},
        },
        {
            # A memory operand is one byte, and it is the addressed one. Bit 1
            # of the byte at MEM_BASE (0x02) is set, so Z is cleared. Bit 1 of
            # the longword at the same address (0x025A3CC1) is bit 1 of its low
            # byte 0xC1, which is clear, and bit 1 of the far-end byte is the
            # same bit, so a longword access and a wrong-ended byte access both
            # set Z where this case asserts it cleared. The bit number is 1,
            # which every candidate width holds, so this case asserts the
            # width and pins no modulus.
            #
            # The memory is asserted unchanged: BTST reads and must not write.
            "name": "btst_b_memory_operand_is_one_byte",
            "mnemonic": "btst",
            "instruction": "btst #1,(%a0)",
            "initial": {
                "regs": {"a0": MEM_BASE, "sr": SR_DIRTY},
                "mem": mem_bytes(MEM_BASE, MEM_SEED_BYTES),
            },
            "expected": {
                "regs": {"a0": MEM_BASE, "sr": SR_DIRTY & ~CCR_Z},
                "mem": mem_bytes(MEM_BASE, MEM_SEED_BYTES),
            },
        },
        {
            # The dynamic form takes the bit number from a data register, and
            # that register is asserted unchanged.
            "name": "btst_l_dynamic_bit_number_in_d1",
            "mnemonic": "btst",
            "instruction": "btst %d1,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "d1": 9, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": DIRTY_D, "d1": 9,
                                  "sr": SR_DIRTY & ~CCR_Z}},
        },

        # ----------------------------------------------------------- BSET
        {
            "name": "bset_l_clear_bit_sets_z_and_the_bit",
            "mnemonic": "bset",
            "instruction": "bset #7,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY & ~CCR_Z}},
            "expected": {"regs": {"d0": 0x123456F8, "sr": SR_DIRTY}},
        },
        {
            # The three bytes around the operand are asserted unchanged. A
            # core that read, modified and wrote a longword here would leave
            # them equal by accident; one that wrote a longword built from the
            # byte would not. Both are caught, because the seed's four bytes
            # all differ.
            "name": "bset_b_memory_keeps_the_other_three_bytes",
            "mnemonic": "bset",
            "instruction": "bset #0,(%a0)",
            "initial": {
                "regs": {"a0": MEM_BASE, "sr": SR_DIRTY & ~CCR_Z},
                "mem": mem_bytes(MEM_BASE, MEM_SEED_BYTES),
            },
            "expected": {
                "regs": {"a0": MEM_BASE, "sr": SR_DIRTY},
                "mem": mem_bytes(MEM_BASE, (0x03,) + MEM_SEED_BYTES[1:]),
            },
        },

        # ----------------------------------------------------------- BCLR
        {
            "name": "bclr_l_set_bit_clears_z_and_the_bit",
            "mnemonic": "bclr",
            "instruction": "bclr #4,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x12345668,
                                  "sr": SR_DIRTY & ~CCR_Z}},
        },
        {
            "name": "bclr_b_memory_keeps_the_other_three_bytes",
            "mnemonic": "bclr",
            "instruction": "bclr #1,(%a0)",
            "initial": {
                "regs": {"a0": MEM_BASE, "sr": SR_DIRTY},
                "mem": mem_bytes(MEM_BASE, MEM_SEED_BYTES),
            },
            "expected": {
                "regs": {"a0": MEM_BASE, "sr": SR_DIRTY & ~CCR_Z},
                "mem": mem_bytes(MEM_BASE, (0x00,) + MEM_SEED_BYTES[1:]),
            },
        },

        # ----------------------------------------------------------- BCHG
        {
            "name": "bchg_l_clear_bit_sets_z_and_flips_the_bit",
            "mnemonic": "bchg",
            "instruction": "bchg #7,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY & ~CCR_Z}},
            "expected": {"regs": {"d0": 0x123456F8, "sr": SR_DIRTY}},
        },
        {
            # The dynamic form against a byte in memory: 9 mod 8 is bit 1 of
            # 0x02, which is set, so Z clears and the bit flips to 0.
            "name": "bchg_b_memory_dynamic_bit_number",
            "mnemonic": "bchg",
            "instruction": "bchg %d1,(%a0)",
            "initial": {
                "regs": {"a0": MEM_BASE, "d1": 9, "sr": SR_DIRTY},
                "mem": mem_bytes(MEM_BASE, MEM_SEED_BYTES),
            },
            "expected": {
                "regs": {"a0": MEM_BASE, "d1": 9,
                         "sr": SR_DIRTY & ~CCR_Z},
                "mem": mem_bytes(MEM_BASE, (0x00,) + MEM_SEED_BYTES[1:]),
            },
        },

        # ------------------------------------------------------------ LSL
        {
            # Nothing leaves the word, so C and X are both cleared. X starts
            # set, so this case asserts that a shift writes X rather than
            # leaving it, which is the one thing a `setNzClearVc`-shaped
            # implementation would get wrong.
            "name": "lsl_l_1_d0",
            "mnemonic": "lsl.l",
            "instruction": "lsl.l #1,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x2468ACF0, "sr": SR_BASE}},
        },
        {
            "name": "lsl_l_1_carry_out_sets_c_and_x",
            "mnemonic": "lsl.l",
            "instruction": "lsl.l #1,%d0",
            "initial": {"regs": {"d0": 0x87654321, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x0ECA8642,
                                  "sr": SR_BASE | CCR_C | CCR_X}},
        },
        {
            # The encoded count field 000 means eight. A core that read it as
            # zero leaves the register alone and fails on the value.
            "name": "lsl_l_8_d0",
            "mnemonic": "lsl.l",
            "instruction": "lsl.l #8,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x34567800, "sr": SR_BASE}},
        },
        {
            "name": "lsl_l_count_register_d1",
            "mnemonic": "lsl.l",
            "instruction": "lsl.l %d1,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "d1": 4, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x23456780, "d1": 4,
                                  "sr": SR_BASE | CCR_C | CCR_X}},
        },
        {
            # No `sr`: see the note at the head of this group.
            "name": "lsl_l_count_register_zero_is_a_no_operation",
            "mnemonic": "lsl.l",
            "instruction": "lsl.l %d1,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "d1": 0}},
            "expected": {"regs": {"d0": DIRTY_D, "d1": 0}},
        },

        # ------------------------------------------------------------ LSR
        {
            "name": "lsr_l_1_d0",
            "mnemonic": "lsr.l",
            "instruction": "lsr.l #1,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x091A2B3C, "sr": SR_BASE}},
        },
        {
            # The same destination value as the case above and different
            # flags. The pair is what proves C and X come from the bit shifted
            # out and not from anything in the result.
            "name": "lsr_l_1_carry_out_sets_c_and_x",
            "mnemonic": "lsr.l",
            "instruction": "lsr.l #1,%d0",
            "initial": {"regs": {"d0": 0x12345679, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x091A2B3C,
                                  "sr": SR_BASE | CCR_C | CCR_X}},
        },
        {
            # A logical right shift feeds zeros in. An arithmetic one would
            # give 0xF8765432 and set N; this case asserts N is clear.
            "name": "lsr_l_4_is_logical_not_arithmetic",
            "mnemonic": "lsr.l",
            "instruction": "lsr.l #4,%d0",
            "initial": {"regs": {"d0": 0x87654321, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x08765432, "sr": SR_BASE}},
        },

        # ------------------------------------------------------------ ASR
        {
            # An arithmetic right shift replicates the sign. A logical one
            # would give 0x43B2A190 and clear N.
            "name": "asr_l_1_replicates_the_sign",
            "mnemonic": "asr.l",
            "instruction": "asr.l #1,%d0",
            "initial": {"regs": {"d0": 0x87654321, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0xC3B2A190,
                                  "sr": SR_BASE | CCR_N | CCR_C | CCR_X}},
        },
        {
            "name": "asr_l_1_positive",
            "mnemonic": "asr.l",
            "instruction": "asr.l #1,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x091A2B3C, "sr": SR_BASE}},
        },
        {
            "name": "asr_l_count_register_d1",
            "mnemonic": "asr.l",
            "instruction": "asr.l %d1,%d0",
            "initial": {"regs": {"d0": 0x87654321, "d1": 4, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0xF8765432, "d1": 4,
                                  "sr": SR_BASE | CCR_N}},
        },

        # ------------------------------------------------------------ ASL
        #
        # ASL NEVER SETS V ON THIS PART, AND THESE CASES ARE WHAT PINS THAT.
        # The reference gives V a flat "Always cleared" and adds "Note that
        # CCR[V] is always cleared by ASL and ASR, unlike on the 68K family
        # processors"; the prose says "The overflow bit is always zero".
        #
        # EACH CASE BELOW CHANGES THE SIGN AND STILL EXPECTS V CLEAR, so a core
        # carrying the 68K rule - V set when the sign changed - fails both, and
        # every case starts from SR_DIRTY with V SET so that a core which never
        # writes V fails them too. `asl_l_1_sign_kept_clears_v` holds the other
        # corner: C set with V clear, so a core that copied C into V fails it.
        {
            "name": "asl_l_1_sign_change_clears_v",
            "mnemonic": "asl.l",
            "instruction": "asl.l #1,%d0",
            "initial": {"regs": {"d0": 0x60000000, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0xC0000000,
                                  "sr": SR_BASE | CCR_N}},
        },
        {
            "name": "asl_l_1_carry_out_and_sign_change",
            "mnemonic": "asl.l",
            "instruction": "asl.l #1,%d0",
            "initial": {"regs": {"d0": 0x87654321, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x0ECA8642,
                                  "sr": SR_BASE | CCR_C | CCR_X}},
        },
        {
            "name": "asl_l_1_sign_kept_clears_v",
            "mnemonic": "asl.l",
            "instruction": "asl.l #1,%d0",
            "initial": {"regs": {"d0": 0xC0000000, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x80000000,
                                  "sr": SR_BASE | CCR_N | CCR_C | CCR_X}},
        },
        {
            "name": "asl_l_count_register_d1",
            "mnemonic": "asl.l",
            "instruction": "asl.l %d1,%d0",
            "initial": {"regs": {"d0": DIRTY_D, "d1": 2, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x48D159E0, "d1": 2,
                                  "sr": SR_BASE}},
        },

        # -------------------------------------------------------- (xxx).W
        #
        # An absolute-short memory destination. `eaMemoryAlterable` admits
        # `(xxx).W`, and the `Dn op <ea> -> <ea>` direction of OR is the path
        # that writes one. The guard longword after it is asserted unchanged,
        # so a store that was too wide fails.
        {
            "name": "or_l_d1_to_abs_w",
            "mnemonic": "or.l",
            "instruction": "or.l %d1,0x2000.w",
            "initial": {
                "regs": {"pc": EXEC_BASE, "d1": DIRTY_D, "sr": SR_DIRTY},
                "mem": [{"addr": ABS_W_ADDR, "size": 4, "value": 0x0F0F0F0F},
                        {"addr": ABS_W_ADDR + 4, "size": 4,
                         "value": MEM_GUARD}],
            },
            "expected": {
                "regs": {"d1": DIRTY_D, "pc": EXEC_BASE + 4,
                         "sr": SR_BASE | CCR_X},
                "mem": [{"addr": ABS_W_ADDR, "size": 4, "value": 0x1F3F5F7F},
                        {"addr": ABS_W_ADDR + 4, "size": 4,
                         "value": MEM_GUARD}],
            },
        },

        # -------------------------------------------------------- (xxx).L
        #
        # Both directions of AND reach the absolute modes and they are separate
        # code paths: the `<ea>,Dn` direction reads through `eaRead` and the
        # `Dn,<ea>` direction resolves a writable reference through
        # `eaResolve`. Each path gets its own case, and each names the swapped
        # address and asserts that window untouched.
        {
            "name": "and_l_abs_l_to_d1",
            "mnemonic": "and.l",
            "instruction": "and.l 0x00030004,%d1",
            "initial": {
                "regs": {"d1": DIRTY_D, "sr": SR_DIRTY},
                "mem": (mem_bytes(ABS_L_ADDR, EA_WINDOW)
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
            "expected": {
                "regs": {"d1": 0x00100230, "pc": EXEC_BASE + 6,
                         "sr": SR_BASE | CCR_X},
                "mem": (mem_bytes(ABS_L_ADDR, EA_WINDOW)
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
        },
        {
            "name": "and_l_d1_to_abs_l",
            "mnemonic": "and.l",
            "instruction": "and.l %d1,0x00030004",
            "initial": {
                "regs": {"d1": DIRTY_D, "sr": SR_DIRTY},
                "mem": ([{"addr": ABS_L_ADDR, "size": 4, "value": 0x80112233},
                         {"addr": ABS_L_ADDR + 4, "size": 4,
                          "value": MEM_GUARD}]
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
            "expected": {
                "regs": {"d1": DIRTY_D, "pc": EXEC_BASE + 6,
                         "sr": SR_BASE | CCR_X},
                "mem": ([{"addr": ABS_L_ADDR, "size": 4, "value": 0x00100230},
                         {"addr": ABS_L_ADDR + 4, "size": 4,
                          "value": MEM_GUARD}]
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
        },
        {
            "name": "btst_b_abs_l",
            "mnemonic": "btst",
            "instruction": "btst %d1,0x00030004",
            "initial": {
                "regs": {"d1": 7, "sr": SR_DIRTY},
                "mem": (mem_bytes(ABS_L_ADDR, EA_WINDOW)
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
            # The operand is one byte: 0x80 at ABS_L_ADDR, whose bit 7 is set,
            # so Z clears. The byte at the swapped address is 0x0b, whose bit 7
            # is clear, so the other reading sets Z instead.
            "expected": {
                "regs": {"d1": 7, "pc": EXEC_BASE + 6,
                         "sr": SR_DIRTY & ~CCR_Z},
                "mem": (mem_bytes(ABS_L_ADDR, EA_WINDOW)
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
        },

        # ------------------------------------------------------- (d16,PC)
        #
        # A dynamic BTST is the one operation in this group whose mask admits a
        # PC-relative operand - it reads and never writes. Bit 7 of the byte at
        # `PC_OPERAND` is set and bit 7 of the byte two along is clear, so Z
        # comes out the opposite way under the two readings of the base.
        # `tests/t_logic.nim` executes the same instruction and pins it too.
        {
            "name": "btst_b_pc_disp",
            "mnemonic": "btst",
            "instruction": "btst %d1,(0x1e,%pc)",
            "initial": {
                "regs": {"pc": EXEC_BASE, "d1": 7, "sr": SR_DIRTY},
                "mem": mem_bytes(PC_OPERAND, EA_WINDOW),
            },
            "expected": {
                "regs": {"d1": 7, "pc": EXEC_BASE + 4,
                         "sr": SR_DIRTY & ~CCR_Z},
                "mem": mem_bytes(PC_OPERAND, EA_WINDOW),
            },
        },

        # ----------------------------------------------------- (d8,PC,Xn)
        {
            "name": "btst_b_pc_index",
            "mnemonic": "btst",
            "instruction": "btst %d1,(4,%pc,%d2)",
            "initial": {
                "regs": {"pc": EXEC_BASE, "d1": 7, "d2": INDEX_VALUE,
                         "sr": SR_DIRTY},
                "mem": (mem_bytes(PC_INDEX_OPERAND, EA_WINDOW)
                        + mem_bytes(PC_INDEX_DECOY, EA_DECOY_WINDOW)),
            },
            "expected": {
                "regs": {"d1": 7, "d2": INDEX_VALUE, "pc": EXEC_BASE + 4,
                         "sr": SR_DIRTY & ~CCR_Z},
                "mem": (mem_bytes(PC_INDEX_OPERAND, EA_WINDOW)
                        + mem_bytes(PC_INDEX_DECOY, EA_DECOY_WINDOW)),
            },
        },
        {
            # The same extension word on an address-register base. `eaAnIndex`
            # and `ea7PCIndex` share `indexOperand`, so the width rule is one
            # line of code serving two addressing modes; a case that covered
            # only the PC form would leave the other half of that line
            # unguarded.
            "name": "btst_b_an_index",
            "mnemonic": "btst",
            "instruction": "btst %d1,(4,%a0,%d2)",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a0": MEM_BASE, "d1": 7,
                         "d2": INDEX_VALUE, "sr": SR_DIRTY},
                "mem": (mem_bytes(AN_INDEX_OPERAND, EA_WINDOW)
                        + mem_bytes(AN_INDEX_DECOY, EA_DECOY_WINDOW)),
            },
            "expected": {
                "regs": {"a0": MEM_BASE, "d1": 7, "d2": INDEX_VALUE,
                         "pc": EXEC_BASE + 4, "sr": SR_DIRTY & ~CCR_Z},
                "mem": (mem_bytes(AN_INDEX_OPERAND, EA_WINDOW)
                        + mem_bytes(AN_INDEX_DECOY, EA_DECOY_WINDOW)),
            },
        },
    ],

    # -----------------------------------------------------------------------
    # The condition-code rules of this group, and where each comes from.
    #
    #   NOP, BRA, BSR, Bcc, JMP, JSR, Scc
    #       No condition code at all. MCF5307 User's Manual Table 3-7,
    #       "Instruction Set Summary", pages 3-23 and 3-25, gives each of these
    #       an operation column that names the program counter, the stack
    #       pointer or the destination and no flag. Every one of these cases
    #       therefore expects its incoming status word back byte for byte.
    #
    #   TST
    #       "Set Integer Condition Codes" (Table 3-7, page 3-25) at the operand
    #       size. N and Z from the operand, V and C cleared, X untouched -
    #       section 3.2.1.5, page 3-8, defines V as an arithmetic overflow, C as
    #       a carry out of an addition or a borrow in a subtraction, and TST
    #       performs neither. That is `setNzClearVc`, the rule MOVE already has.
    #
    #   CMP, CMPA, CMPI
    #       "Destination - Source" (Table 3-7, page 3-23) with the result
    #       discarded. N, Z, V and C come from that subtraction and X is not
    #       written. The X rule is unsettled: the
    #       same section 3.2.1.5 says X takes C's value "for arithmetic
    #       operations", which read literally would have a comparison write it.
    #       These cases assert X unchanged, so a reader who reverses that
    #       reading must change them.
    #
    #   RTE
    #       The status register is reloaded from the frame, not computed. Every
    #       RTE case below therefore starts from a different word than the one
    #       it expects, so "the core reloaded it" is separable from "the core
    #       left it alone".
    #
    #   TRAP
    #       The reference: "the
    #       processor makes an internal copy of the SR and then enters
    #       supervisor mode by setting the S-bit and disabling trace mode by
    #       clearing the T-bit". The copy is what reaches the stack frame and
    #       the modified word is what the handler runs under.
    "control": [
        {
            # An `sr` expectation of "unchanged" is satisfied by a NOP that
            # never executed, so it carries no assertion of its own.
            # `conformance/runner.cpp` supplies the missing one: it asserts
            # `mcf5307_faulted`, then `mcf5307_halted`, then a non-zero cycle
            # return, before it compares one register.
            #
            # `pc` separates a NOP from every other one-word instruction in this
            # group: the program counter advances by exactly one word and by
            # nothing else.
            "name": "nop",
            "mnemonic": "nop",
            "instruction": "nop",
            "initial": {"regs": {"pc": EXEC_BASE, "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "sr": SR_DIRTY}},
        },

        # -------------------------------------------------------------- BRA
        # Both directions of both forms. A displacement is signed, and a core
        # that zero-extended it passes every forward case and fails both
        # backward ones. `bra.b .-6` is `60f8` and `bra.w .-0x4000` is
        # `6000 bffe`, each assembled by `m68k-elf-as -mcpu=5307`.
        {
            "name": "bra_b_forward",
            "mnemonic": "bra.b",
            "instruction": "bra.b .+8",
            "initial": {"regs": {"pc": EXEC_BASE, "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2 + 6, "sr": SR_DIRTY}},
        },
        {
            "name": "bra_b_backward",
            "mnemonic": "bra.b",
            "instruction": "bra.b .-6",
            "initial": {"regs": {"pc": EXEC_BASE, "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2 - 8, "sr": SR_DIRTY}},
        },
        {
            "name": "bra_w_forward",
            "mnemonic": "bra.w",
            "instruction": "bra.w .+0x2000",
            "initial": {"regs": {"pc": EXEC_BASE, "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2 + 0x1FFE,
                                  "sr": SR_DIRTY}},
        },
        {
            "name": "bra_w_backward",
            "mnemonic": "bra.w",
            "instruction": "bra.w .-0x4000",
            "initial": {"regs": {"pc": EXEC_BASE, "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2 - 0x4002,
                                  "sr": SR_DIRTY}},
        },

        # -------------------------------------------------------------- BSR
        # The return address is the address after the whole instruction, and
        # the two forms are different lengths. Table 3-7, page 3-23, gives BSR
        # as "SP - 4 -> SP; PC -> (SP); PC + dn -> PC". The byte form pushes
        # opcode + 2 and the word form pushes opcode + 4; a core that pushed
        # the branch BASE - which is opcode + 2 for both - passes the byte case
        # and fails the word one.
        {
            "name": "bsr_b_pushes_return_address",
            "mnemonic": "bsr.b",
            "instruction": "bsr.b .+8",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a7": CTRL_STACK, "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 8, MEM_GUARD),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
            "expected": {
                "regs": {"pc": EXEC_BASE + 2 + 6, "a7": CTRL_STACK - 4,
                         "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 8, MEM_GUARD),
                        lw(CTRL_STACK - 4, EXEC_BASE + 2),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
        },
        {
            "name": "bsr_w_pushes_return_address",
            "mnemonic": "bsr.w",
            "instruction": "bsr.w .+0x40",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a7": CTRL_STACK, "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 8, MEM_GUARD),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
            "expected": {
                "regs": {"pc": EXEC_BASE + 2 + 0x3E, "a7": CTRL_STACK - 4,
                         "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 8, MEM_GUARD),
                        lw(CTRL_STACK - 4, EXEC_BASE + 4),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
        },
    ] + bcc_cases() + [

        # -------------------------------------------------------------- Scc
        # The destination is one byte of a data register and nothing wider.
        # Table 3-7, page 3-25, gives `Scc Dx` an operand size of 8 and the
        # operation "If Condition True, Then 1's -> Destination; Else 0's ->
        # Destination". `DIRTY_D` is 0x12345678 and every byte of it differs,
        # so a core that wrote the whole register lands on 0xFFFFFFFF or 0 and
        # a core that wrote the wrong byte lane lands somewhere else again.
        #
        # The operand is a data register and nothing else. Table 3-12, "One
        # Operand Instruction Execution Times", page 3-27: the `scc Dx` row
        # carries `1(0/0)` under `Rn` and A DASH under `(An)`, `(An)+`, `-(An)`,
        # `(d16,An)`, `(d8,An,Xi*SF)`, `xxx.wl` and `#xxx`. The `clr.b` rows
        # above it and the `tst.b` rows below it carry times in those columns,
        # so the dashes are this row's. `m68k-elf-as -mcpu=5307` agrees and
        # rejects `scc (%a0)`, `scc %a0` and `scc 0x1234.w`. The negative cases
        # are in `tests/t_control.nim`; a positive corpus cannot hold them.
        {
            "name": "scc_st_writes_ones_into_the_low_byte",
            "mnemonic": "st",
            "instruction": "st %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2,
                                  "d0": (DIRTY_D & ~0xFF) | 0xFF,
                                  "sr": SR_DIRTY}},
        },
        {
            "name": "scc_sf_writes_zeros_into_the_low_byte",
            "mnemonic": "sf",
            "instruction": "sf %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2,
                                  "d0": DIRTY_D & ~0xFF,
                                  "sr": SR_DIRTY}},
        },
        {
            "name": "scc_seq_true",
            "mnemonic": "seq",
            "instruction": "seq %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": DIRTY_D,
                                 "sr": SR_BASE | CCR_X | CCR_Z}},
            "expected": {"regs": {"pc": EXEC_BASE + 2,
                                  "d0": (DIRTY_D & ~0xFF) | 0xFF,
                                  "sr": SR_BASE | CCR_X | CCR_Z}},
        },
        {
            "name": "scc_seq_false",
            "mnemonic": "seq",
            "instruction": "seq %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": DIRTY_D,
                                 "sr": SR_BASE | CCR_X | CCR_C}},
            "expected": {"regs": {"pc": EXEC_BASE + 2,
                                  "d0": DIRTY_D & ~0xFF,
                                  "sr": SR_BASE | CCR_X | CCR_C}},
        },
        {
            "name": "scc_smi_true",
            "mnemonic": "smi",
            "instruction": "smi %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": DIRTY_D,
                                 "sr": SR_BASE | CCR_X | CCR_N}},
            "expected": {"regs": {"pc": EXEC_BASE + 2,
                                  "d0": (DIRTY_D & ~0xFF) | 0xFF,
                                  "sr": SR_BASE | CCR_X | CCR_N}},
        },
        {
            "name": "scc_scc_carry_clear_true",
            "mnemonic": "scc",
            "instruction": "scc %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": DIRTY_D,
                                 "sr": SR_BASE | CCR_X | CCR_Z}},
            "expected": {"regs": {"pc": EXEC_BASE + 2,
                                  "d0": (DIRTY_D & ~0xFF) | 0xFF,
                                  "sr": SR_BASE | CCR_X | CCR_Z}},
        },

        # -------------------------------------------------------------- TST
        # All three sizes exist here and the manual prints all three. Table
        # 3-12, page 3-27, carries a `tst.b`, a `tst.w` AND a `tst.l` row, each
        # timed under every one of `Rn`, `(An)`, `(An)+`, `-(An)`, `(d16,An)`,
        # `(d8,An,Xi*SF)`, `xxx.wl` and `#xxx` - no dash anywhere in those
        # rows. TST is the ONE instruction in this group that keeps the byte and
        # word forms the rest of the core traps, and `m68k-elf-as -mcpu=5307`
        # agrees: it accepts `tst.b %d0`, `tst.w %d0` and `tst.l #5`.
        #
        # Each sized case answers the opposite way at the other sizes. The seed
        # is chosen so that the flag the case asserts changes if the operand is
        # read one size wider or narrower, which is what makes these cases a
        # test of the SIZE and not only of the flags.
        {
            "name": "tst_l_positive_clears_n_and_z_and_keeps_x",
            "mnemonic": "tst.l",
            "instruction": "tst.l %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "d0": DIRTY_D,
                                  "sr": SR_BASE | CCR_X}},
        },
        {
            "name": "tst_l_negative_sets_n",
            "mnemonic": "tst.l",
            "instruction": "tst.l %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": 0x80000000,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "d0": 0x80000000,
                                  "sr": SR_BASE | CCR_X | CCR_N}},
        },
        {
            # The operand is zero and that is the point. Every other case in
            # this corpus seeds its destination non-zero; TST has no
            # destination, and the value it reads is the whole of its input.
            "name": "tst_l_zero_sets_z",
            "mnemonic": "tst.l",
            "instruction": "tst.l %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": 0, "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "d0": 0,
                                  "sr": SR_BASE | CCR_X | CCR_Z}},
        },
        {
            # 0x1234FFFF is negative as a word and positive as a longword.
            "name": "tst_w_negative_low_word",
            "mnemonic": "tst.w",
            "instruction": "tst.w %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": 0x1234FFFF,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "d0": 0x1234FFFF,
                                  "sr": SR_BASE | CCR_X | CCR_N}},
        },
        {
            # 0x12340000 is zero as a word and non-zero as a longword.
            "name": "tst_w_zero_low_word",
            "mnemonic": "tst.w",
            "instruction": "tst.w %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": 0x12340000,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "d0": 0x12340000,
                                  "sr": SR_BASE | CCR_X | CCR_Z}},
        },
        {
            # 0x12345680 is negative as a byte and positive as a word.
            "name": "tst_b_negative_low_byte",
            "mnemonic": "tst.b",
            "instruction": "tst.b %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": 0x12345680,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "d0": 0x12345680,
                                  "sr": SR_BASE | CCR_X | CCR_N}},
        },
        {
            # 0x12345600 IS ZERO AS A BYTE AND NON-ZERO AS A WORD.
            "name": "tst_b_zero_low_byte",
            "mnemonic": "tst.b",
            "instruction": "tst.b %d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": 0x12345600,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "d0": 0x12345600,
                                  "sr": SR_BASE | CCR_X | CCR_Z}},
        },
        {
            # An address register is a legal `tst.l` operand and not a legal
            # `tst.b` ONE. `m68k-elf-as -mcpu=5307` accepts `tst.l %a0` and
            # `tst.w %a0` and rejects `tst.b %a0`; the byte half is a trap case
            # and lives in `tests/t_control.nim`.
            "name": "tst_l_address_register",
            "mnemonic": "tst.l",
            "instruction": "tst.l %a0",
            "initial": {"regs": {"pc": EXEC_BASE, "a0": DIRTY_A,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "a0": DIRTY_A,
                                  "sr": SR_BASE | CCR_X}},
        },
        {
            # TST reads and writes nothing. All four seeded bytes are asserted
            # unchanged, so a core that wrote its result back fails here.
            "name": "tst_l_memory_reads_and_does_not_write",
            "mnemonic": "tst.l",
            "instruction": "tst.l (%a0)",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a0": MEM_BASE, "sr": SR_DIRTY},
                "mem": mem_bytes(MEM_BASE, (0xF0, 0xE1, 0xD2, 0xC3)),
            },
            "expected": {
                "regs": {"pc": EXEC_BASE + 2, "a0": MEM_BASE,
                         "sr": SR_BASE | CCR_X | CCR_N},
                "mem": mem_bytes(MEM_BASE, (0xF0, 0xE1, 0xD2, 0xC3)),
            },
        },
        {
            # The postincrement is by the operand size, which is one byte here.
            # A core that advanced by four lands on `MEM_BASE + 4`.
            "name": "tst_b_postincrement_advances_by_one",
            "mnemonic": "tst.b",
            "instruction": "tst.b (%a0)+",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a0": MEM_BASE, "sr": SR_DIRTY},
                "mem": mem_bytes(MEM_BASE, MEM_SEED_BYTES),
            },
            "expected": {
                "regs": {"pc": EXEC_BASE + 2, "a0": MEM_BASE + 1,
                         "sr": SR_BASE | CCR_X},
                "mem": mem_bytes(MEM_BASE, MEM_SEED_BYTES),
            },
        },
        {
            # An immediate operand is timed in Table 3-12 - `tst.l` reads
            # `1(0/0)` under `#xxx` - and `m68k-elf-as -mcpu=5307` emits
            # `4abc 0000 0005` for it. The program counter is what proves the
            # core consumed TWO extension words and not one.
            "name": "tst_l_immediate",
            "mnemonic": "tst.l",
            "instruction": "tst.l #5",
            "initial": {"regs": {"pc": EXEC_BASE, "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 6,
                                  "sr": SR_BASE | CCR_X}},
        },

        # -------------------------------------------------------------- CMP
        # `cmp.l %d0,%d1` is `d1 - d0`, and the order is measured. The word is
        # `b280` = `1011 001 010 000 000`: bits 11..9 are the destination data
        # register (d1) and the low six bits are the source effective address
        # (d0). Table 3-7, page 3-23, gives the operation as "Destination -
        # Source". A core that subtracted the other way round gets the sign and
        # the carry of `cmp_l_source_greater_sets_n_and_c` backwards.
        {
            "name": "cmp_l_equal_sets_z",
            "mnemonic": "cmp.l",
            "instruction": "cmp.l %d0,%d1",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": DIRTY_D, "d1": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "d0": DIRTY_D,
                                  "d1": DIRTY_D,
                                  "sr": SR_BASE | CCR_X | CCR_Z}},
        },
        {
            "name": "cmp_l_source_greater_sets_n_and_c",
            "mnemonic": "cmp.l",
            "instruction": "cmp.l %d0,%d1",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": 2, "d1": 1,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "d0": 2, "d1": 1,
                                  "sr": SR_BASE | CCR_X | CCR_N | CCR_C}},
        },
        {
            # THE SIGNED OVERFLOW IS A DIFFERENT QUESTION FROM THE BORROW.
            # 0x80000000 - 1 is 0x7fffffff: no borrow, so C is CLEAR, and the
            # sign of the result is not the sign the operands imply, so V is
            # SET. A core that computed V from the carry fails here.
            "name": "cmp_l_signed_overflow_sets_v_without_c",
            "mnemonic": "cmp.l",
            "instruction": "cmp.l %d0,%d1",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": 1, "d1": 0x80000000,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "d0": 1,
                                  "d1": 0x80000000,
                                  "sr": SR_BASE | CCR_X | CCR_V}},
        },
        {
            "name": "cmp_l_memory_source",
            "mnemonic": "cmp.l",
            "instruction": "cmp.l (%a0),%d1",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a0": MEM_BASE, "d1": DIRTY_D,
                         "sr": SR_DIRTY},
                "mem": [lw(MEM_BASE, DIRTY_D), lw(MEM_BASE + 4, MEM_GUARD)],
            },
            "expected": {
                "regs": {"pc": EXEC_BASE + 2, "a0": MEM_BASE, "d1": DIRTY_D,
                         "sr": SR_BASE | CCR_X | CCR_Z},
                "mem": [lw(MEM_BASE, DIRTY_D), lw(MEM_BASE + 4, MEM_GUARD)],
            },
        },
        {
            # AN ADDRESS REGISTER IS A LEGAL CMP SOURCE. `b288` is what
            # `m68k-elf-as -mcpu=5307` emits for `cmp.l %a0,%d1`, and the
            # timing table times the `cmp.l <ea>,Rx` row under `Rn`.
            "name": "cmp_l_address_register_source",
            "mnemonic": "cmp.l",
            "instruction": "cmp.l %a0,%d1",
            "initial": {"regs": {"pc": EXEC_BASE, "a0": DIRTY_A, "d1": DIRTY_A,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "a0": DIRTY_A,
                                  "d1": DIRTY_A,
                                  "sr": SR_BASE | CCR_X | CCR_Z}},
        },
        {
            # THE PC-RELATIVE BASE IS THE ADDRESS OF THE DISPLACEMENT WORD.
            # `b2ba 0020` puts its operand at EXEC_BASE + 2 + 0x20; the
            # longword TWO BYTES FURTHER ON - where a core that based the
            # address after the word would read - is seeded with the guard, so
            # the two readings give different flags.
            "name": "cmp_l_pc_relative_source",
            "mnemonic": "cmp.l",
            "instruction": "cmp.l (0x20,%pc),%d1",
            "initial": {
                "regs": {"pc": EXEC_BASE, "d1": 0x80112233, "sr": SR_DIRTY},
                "mem": [lw(EXEC_BASE + 2 + 0x20, 0x80112233)],
            },
            "expected": {
                "regs": {"pc": EXEC_BASE + 4, "d1": 0x80112233,
                         "sr": SR_BASE | CCR_X | CCR_Z},
                "mem": [lw(EXEC_BASE + 2 + 0x20, 0x80112233)],
            },
        },

        # ------------------------------------------------------------- CMPA
        # CMPA IS 32-BIT AND THERE IS NO OTHER SIZE. The reference
        # gives `CMPA <ea>y,Ax` an OPERAND SIZE column of `32` and nothing else,
        # and `m68k-elf-as -mcpu=5307` rejects `cmpa.w %d0,%a1`. The word form's
        # encoding - line 1011 opmode 011 - is a trap case in
        # `tests/t_control.nim`.
        {
            "name": "cmpa_l_equal_sets_z",
            "mnemonic": "cmpa.l",
            "instruction": "cmpa.l %d0,%a1",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": DIRTY_A, "a1": DIRTY_A,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2, "d0": DIRTY_A,
                                  "a1": DIRTY_A,
                                  "sr": SR_BASE | CCR_X | CCR_Z}},
        },
        {
            "name": "cmpa_l_immediate",
            "mnemonic": "cmpa.l",
            "instruction": "cmpa.l #0x0badc0de,%a1",
            "initial": {"regs": {"pc": EXEC_BASE, "a1": DIRTY_A,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 6, "a1": DIRTY_A,
                                  "sr": SR_BASE | CCR_X | CCR_Z}},
        },
        {
            "name": "cmpa_l_memory_source",
            "mnemonic": "cmpa.l",
            "instruction": "cmpa.l (%a0),%a1",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a0": MEM_BASE, "a1": DIRTY_A,
                         "sr": SR_DIRTY},
                "mem": [lw(MEM_BASE, 1), lw(MEM_BASE + 4, MEM_GUARD)],
            },
            "expected": {
                "regs": {"pc": EXEC_BASE + 2, "a0": MEM_BASE, "a1": DIRTY_A,
                         "sr": SR_BASE | CCR_X},
                "mem": [lw(MEM_BASE, 1), lw(MEM_BASE + 4, MEM_GUARD)],
            },
        },

        # ------------------------------------------------------------- CMPI
        # THE DESTINATION IS A DATA REGISTER AND NOTHING ELSE. The timing table
        # 3-28: the `cmpi.l #imm,Dx` row carries `1(0/0)` under `Rn` and A DASH
        # under every memory column and under `#xxx`. `m68k-elf-as -mcpu=5307`
        # agrees and rejects `cmpi.l #5,(%a0)` and `cmpi.l #5,%a0`.
        {
            "name": "cmpi_l_equal_sets_z",
            "mnemonic": "cmpi.l",
            "instruction": "cmpi.l #0x12345678,%d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 6, "d0": DIRTY_D,
                                  "sr": SR_BASE | CCR_X | CCR_Z}},
        },
        {
            "name": "cmpi_l_immediate_greater_sets_n_and_c",
            "mnemonic": "cmpi.l",
            "instruction": "cmpi.l #2,%d0",
            "initial": {"regs": {"pc": EXEC_BASE, "d0": 1, "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 6, "d0": 1,
                                  "sr": SR_BASE | CCR_X | CCR_N | CCR_C}},
        },

        # -------------------------------------------------------------- JMP
        # THE OPERAND CLASS IS CONTROL ADDRESSING, AND THE MANUAL GIVES IT TWICE.
        # The branch timing table:
        # the `jmp <ea>` row carries a time under `(An)`, under
        # `(d16,An)/(d16,PC)`, under `(d8,An,Xi*SF)/(d8,PC,Xi*SF)` and under
        # `xxx.wl`, and A DASH under `Rn`, `(An)+`, `-(An)` and `#xxx`. Table
        # marks exactly those modes CONTROL. `m68k-elf-as
        # -mcpu=5307` agrees on both halves: it rejects `jmp %d0`, `jmp %a0`,
        # `jmp (%a0)+`, `jmp -(%a0)` and `jmp #4`, and it accepts the rest.
        #
        # `(xxx).W` IS IN THE CLASS. The category table marks the absolute
        # SHORT row CONTROL, and the tables' `xxx.wl` column "refers
        # to both forms of absolute addressing, xxx.w and xxx.l".
        #
        # JMP AND JSR CARRY A MASK OF THEIR OWN, AND THE REASON IS NOT
        # `(xxx).W`. `eaJumpTarget` in `src/mcf5307/decode_types.nim` is the
        # class of a BRANCH TARGET and `eaLeaPeaTarget` is the class of an
        # ADDRESS an instruction computes. The two are equal BY MEASUREMENT
        # rather than by definition, and folding them together would let a
        # later correction to one silently move the other. That entry records
        # the argument in full.
        #
        # BOTH READ `ea.nim`'s `eaControl7`, which holds the full control
        # mode-7 class with `(xxx).W` in it. MOVEM reads neither and carries
        # `{eaAnInd, eaAnDisp}`, because the reference dashes every row
        # but `(An)` and `(d16,An)`.
        {
            "name": "jmp_indirect",
            "mnemonic": "jmp",
            "instruction": "jmp (%a0)",
            "initial": {"regs": {"pc": EXEC_BASE, "a0": CTRL_TARGET,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": CTRL_TARGET, "a0": CTRL_TARGET,
                                  "sr": SR_DIRTY}},
        },
        {
            "name": "jmp_displacement",
            "mnemonic": "jmp",
            "instruction": "jmp 4(%a0)",
            "initial": {"regs": {"pc": EXEC_BASE, "a0": MEM_BASE,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": MEM_BASE + 4, "a0": MEM_BASE,
                                  "sr": SR_DIRTY}},
        },
        {
            # THE FIRST EXTENSION WORD IS THE HIGH HALF OF AN ABSOLUTE LONG
            # ADDRESS. `4ef9 0005 4320` - a core that swapped the halves lands
            # at 0x43200005, which is outside the board.
            "name": "jmp_absolute_long",
            "mnemonic": "jmp",
            "instruction": "jmp 0x00054320",
            "initial": {"regs": {"pc": EXEC_BASE, "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": CTRL_TARGET, "sr": SR_DIRTY}},
        },
        {
            "name": "jmp_absolute_short",
            "mnemonic": "jmp",
            "instruction": "jmp 0x1234.w",
            "initial": {"regs": {"pc": EXEC_BASE, "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": 0x1234, "sr": SR_DIRTY}},
        },
        {
            # THE PC-RELATIVE BASE AGAIN, ON AN INSTRUCTION WHOSE WHOLE RESULT
            # IS THE ADDRESS. `4efa 0020` jumps to EXEC_BASE + 2 + 0x20; a core
            # that based it after the displacement word lands two bytes on.
            "name": "jmp_pc_displacement",
            "mnemonic": "jmp",
            "instruction": "jmp (0x20,%pc)",
            "initial": {"regs": {"pc": EXEC_BASE, "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": EXEC_BASE + 2 + 0x20, "sr": SR_DIRTY}},
        },
        {
            # THE INDEX IS A LONGWORD AND NOT A SIGN-EXTENDED WORD.
            # `INDEX_VALUE`'s low word sign-extends to -16 and the whole
            # longword is +65520, so the two readings land 65536 bytes apart and
            # the program counter names which one the core took.
            "name": "jmp_an_index",
            "mnemonic": "jmp",
            "instruction": "jmp (4,%a0,%d2)",
            "initial": {"regs": {"pc": EXEC_BASE, "a0": MEM_BASE,
                                 "d2": INDEX_VALUE, "sr": SR_DIRTY}},
            "expected": {"regs": {"pc": AN_INDEX_OPERAND, "a0": MEM_BASE,
                                  "d2": INDEX_VALUE, "sr": SR_DIRTY}},
        },

        # -------------------------------------------------------------- JSR
        # "SP - 4 -> SP; PC -> (SP); <ea> -> PC". THE
        # PUSHED PROGRAM COUNTER IS THE ADDRESS AFTER THE WHOLE INSTRUCTION,
        # EXTENSION WORDS INCLUDED, which is why the absolute-long case is here
        # beside the register-indirect one: they are three words and one word
        # long, so a core that pushed the address after the OPCODE passes the
        # first and fails the second.
        {
            "name": "jsr_indirect_pushes_return_address",
            "mnemonic": "jsr",
            "instruction": "jsr (%a0)",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a0": CTRL_TARGET,
                         "a7": CTRL_STACK, "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 8, MEM_GUARD),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
            "expected": {
                "regs": {"pc": CTRL_TARGET, "a0": CTRL_TARGET,
                         "a7": CTRL_STACK - 4, "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 8, MEM_GUARD),
                        lw(CTRL_STACK - 4, EXEC_BASE + 2),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
        },
        {
            "name": "jsr_absolute_long_pushes_after_the_extension_words",
            "mnemonic": "jsr",
            "instruction": "jsr 0x00054320",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a7": CTRL_STACK, "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 8, MEM_GUARD),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
            "expected": {
                "regs": {"pc": CTRL_TARGET, "a7": CTRL_STACK - 4,
                         "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 8, MEM_GUARD),
                        lw(CTRL_STACK - 4, EXEC_BASE + 6),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
        },

        # -------------------------------------------------------------- RTS
        # "(SP) -> PC; SP + 4 -> SP". RTS WRITES NO
        # MEMORY, and the longword it read is asserted still there.
        {
            "name": "rts_pops_the_return_address",
            "mnemonic": "rts",
            "instruction": "rts",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a7": CTRL_STACK, "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 4, MEM_GUARD),
                        lw(CTRL_STACK, CTRL_TARGET),
                        lw(CTRL_STACK + 4, MEM_GUARD)],
            },
            "expected": {
                "regs": {"pc": CTRL_TARGET, "a7": CTRL_STACK + 4,
                         "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 4, MEM_GUARD),
                        lw(CTRL_STACK, CTRL_TARGET),
                        lw(CTRL_STACK + 4, MEM_GUARD)],
            },
        },
    ] + [

        # -------------------------------------------------------------- RTE
        # "(SP+2) -> SR; (SP+4) -> PC; SP + 8 -> PC" in the summary,
        # AND THAT LAST ARROW IS A MISPRINT IN THE MANUAL: the program counter
        # has just been loaded from (SP+4), and the row would otherwise
        # overwrite it with an address on the stack. The stack-pointer rule is
        # given properly in the prose: the processor "adjusts the stack
        # pointer by adding the
        # format value to the auto-incremented address after the fetch of the
        # first longword", which is SP + 4 + FORMAT.
        #
        # THAT IS THE INVERSE OF THE FORMAT FIELD ENCODING, and the cases below
        # are that table's four rows read backwards: a frame whose format is
        # 4, 5, 6 or 7 restores an A7 of SP + 8, SP + 9, SP + 10 or SP + 11.
        # A core that added a fixed 8 passes the first case and fails the other
        # three.
        #
        # THE INCOMING STATUS REGISTER IS `SR_DIRTY` AND THE FRAME HOLDS A
        # DIFFERENT WORD, so "the core reloaded SR from the frame" is separable
        # from "the core left SR alone".
        {
            "name": "rte_format_%d_restores_sr_pc_and_a7" % fmt,
            "mnemonic": "rte",
            "instruction": "rte",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a7": CTRL_STACK, "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 4, MEM_GUARD),
                        lw(CTRL_STACK, frame_fv(fmt, 32, 0x2703)),
                        lw(CTRL_STACK + 4, CTRL_TARGET)],
            },
            "expected": {
                "regs": {"pc": CTRL_TARGET, "a7": CTRL_STACK + 4 + fmt,
                         "sr": 0x2703},
                "mem": [lw(CTRL_STACK - 4, MEM_GUARD),
                        lw(CTRL_STACK, frame_fv(fmt, 32, 0x2703)),
                        lw(CTRL_STACK + 4, CTRL_TARGET)],
            },
        }
        for fmt in (4, 5, 6, 7)
    ] + [

        # ------------------------------------------------------------- TRAP
        # THE WHOLE EXCEPTION SEQUENCE, AND EVERY PART OF IT IS IN THE MANUAL.
        #
        #   THE VECTOR. `TRAP #0-15` are vector numbers
        #   32 to 47, the vector offset is 4 x vector_number, and the stacked
        #   program counter is "Next" - the address of the instruction after the
        #   TRAP, not the address of the TRAP itself.
        #
        #   THE FRAME. The first longword is the 16-bit
        #   format/vector word above the 16-bit status register, and the second
        #   is the program counter. The reference writes the fault
        #   status field as zeros for everything that is not an access or
        #   address error.
        #
        #   THE SELF-ALIGNMENT. The frame is written at a
        #   0-modulo-4 address and the FORMAT field records how far the stack
        #   pointer had to move to get there - A7-8 and format 0100 when A7's
        #   low two bits were 00, through A7-11 and format 0111 when they were
        #   11. The four cases below are that table's four rows.
        #
        #   THE STATUS REGISTER. The processor copies
        #   SR, sets the S-bit and clears the T-bit. The COPY is what is
        #   stacked. `trap_0_clears_trace_and_sets_supervisor` starts from
        #   0x871f - trace SET, supervisor CLEAR - so the frame holds 0x871f
        #   and the machine continues under 0x271f; under `SR_DIRTY` alone the
        #   two words are equal and the rule is invisible.
        {
            "name": "trap_0_takes_vector_32",
            "mnemonic": "trap",
            "instruction": "trap #0",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a7": CTRL_STACK, "sr": SR_DIRTY},
                "mem": [lw(TRAP_VECTOR_0, CTRL_TARGET),
                        lw(CTRL_STACK - 12, MEM_GUARD),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
            "expected": {
                "regs": {"pc": CTRL_TARGET, "a7": CTRL_STACK - 8,
                         "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 12, MEM_GUARD),
                        lw(CTRL_STACK - 8, frame_fv(4, 32, SR_DIRTY)),
                        lw(CTRL_STACK - 4, EXEC_BASE + 2),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
        },
        {
            # THE VECTOR NUMBER IS 32 PLUS THE FIELD AND THE OFFSET IS FOUR
            # TIMES THAT. `trap #15` reads $0BC and stacks vector 47; a core
            # that forgot the 32, or that indexed by the vector rather than by
            # four times it, reads a longword this case did not seed and jumps
            # to zero.
            "name": "trap_15_takes_vector_47",
            "mnemonic": "trap",
            "instruction": "trap #15",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a7": CTRL_STACK, "sr": SR_DIRTY},
                "mem": [lw(TRAP_VECTOR_15, CTRL_TARGET_2),
                        lw(CTRL_STACK - 12, MEM_GUARD),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
            "expected": {
                "regs": {"pc": CTRL_TARGET_2, "a7": CTRL_STACK - 8,
                         "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 12, MEM_GUARD),
                        lw(CTRL_STACK - 8, frame_fv(4, 47, SR_DIRTY)),
                        lw(CTRL_STACK - 4, EXEC_BASE + 2),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
        },
        {
            "name": "trap_0_clears_trace_and_sets_supervisor",
            "mnemonic": "trap",
            "instruction": "trap #0",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a7": CTRL_STACK, "sr": 0x871F},
                "mem": [lw(TRAP_VECTOR_0, CTRL_TARGET),
                        lw(CTRL_STACK - 12, MEM_GUARD),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
            "expected": {
                "regs": {"pc": CTRL_TARGET, "a7": CTRL_STACK - 8,
                         "sr": 0x271F},
                "mem": [lw(CTRL_STACK - 12, MEM_GUARD),
                        lw(CTRL_STACK - 8, frame_fv(4, 32, 0x871F)),
                        lw(CTRL_STACK - 4, EXEC_BASE + 2),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
        },
    ] + [
        {
            # THE THREE MISALIGNED ROWS OF TABLE 3-2. The frame lands at the
            # SAME 0-modulo-4 address in all three, and the FORMAT field is the
            # only thing that records how far A7 moved.
            "name": "trap_0_a7_low_bits_%d_writes_format_%d" % (bits, 4 + bits),
            "mnemonic": "trap",
            "instruction": "trap #0",
            "initial": {
                "regs": {"pc": EXEC_BASE, "a7": CTRL_STACK + bits,
                         "sr": SR_DIRTY},
                "mem": [lw(TRAP_VECTOR_0, CTRL_TARGET),
                        lw(CTRL_STACK - 12, MEM_GUARD),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
            "expected": {
                "regs": {"pc": CTRL_TARGET, "a7": CTRL_STACK - 8,
                         "sr": SR_DIRTY},
                "mem": [lw(CTRL_STACK - 12, MEM_GUARD),
                        lw(CTRL_STACK - 8, frame_fv(4 + bits, 32, SR_DIRTY)),
                        lw(CTRL_STACK - 4, EXEC_BASE + 2),
                        lw(CTRL_GUARD_AT, MEM_GUARD)],
            },
        }
        for bits in (1, 2, 3)
    ],
}


def build_group_document(group, cases):
    """Assemble every case in a group and build its JSON document."""
    doc_cases = []
    for case in cases:
        encoding = assemble_to_words(case["instruction"])
        doc_cases.append({
            "name": case["name"],
            "mnemonic": case["mnemonic"],
            "instruction": case["instruction"],
            "encoding": encoding,
            "initial": {
                "regs": dict(case["initial"].get("regs", {})),
                "mem": list(case["initial"].get("mem", [])),
            },
            "expected": {
                "regs": dict(case["expected"].get("regs", {})),
                "mem": list(case["expected"].get("mem", [])),
            },
        })
    return {
        "format": FORMAT_VERSION,
        "group": group,
        "binutils": BINUTILS_VERSION,
        "cases": doc_cases,
    }


def write_group(out_dir, group, cases):
    """Assemble and write one group's file, deterministically."""
    doc = build_group_document(group, cases)
    path = os.path.join(out_dir, "%s_00.json" % group)
    # `sort_keys=True` plus a fixed indent and ensure_ascii are what make the
    # regenerated bytes identical run to run. No unique separator is added:
    # the platform newline rule is the same on every machine this runs on,
    # so the emitted newline is stable.
    with open(path, "w") as f:
        json.dump(doc, f, indent=2, sort_keys=True, ensure_ascii=True)
        f.write("\n")
    return path


def main(argv):
    parser = argparse.ArgumentParser(
        description="Regenerate the ColdFire conformance corpus.")
    parser.add_argument("--out", required=True,
                        help="directory to write the corpus into (created if "
                             "missing)")
    args = parser.parse_args(argv)
    out_dir = args.out
    os.makedirs(out_dir, exist_ok=True)

    # Fail the whole run if the pinned assembler version is not the one being
    # used, so a byte-identical regeneration can never be silently produced
    # by a different assembler. docs/toolchain.md pins the same version.
    version_r = subprocess.run(
        [M68K_AS, "--version"], capture_output=True, text=True)
    first_line = version_r.stdout.splitlines()[0].strip() if version_r.stdout \
        else ""
    if first_line != BINUTILS_VERSION:
        # The assembler is present but its version differs from the pinned
        # one. The committed corpus is still authoritative, but this run
        # would not be a byte-identical regeneration.
        parser.error(
            "assembler %r reports %r; docs/toolchain.md pins %r. Refuse to "
            "regenerate the committed corpus with a different assembler."
            % (M68K_AS, first_line, BINUTILS_VERSION))

    wrote = [write_group(out_dir, g, CASES[g]) for g in GROUPS]
    for path in wrote:
        print("wrote %s" % path)
    print("conformance corpus regenerated: %d groups, %d cases"
          % (len(GROUPS),
             sum(len(CASES[g]) for g in GROUPS)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
