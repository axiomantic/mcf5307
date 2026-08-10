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
# The four seed bytes all differ, and neither pair is symmetric. A byte case
# names `MEM_BASE` and asserts the other three bytes are unchanged, so a write
# that was one byte too wide, or that landed on the wrong end of the longword,
# changes a byte the case names. A repeating seed would survive both.
#
# 0x02 is the addressed byte and it is chosen so that bit 1 of it is set while
# bit 1 of the longword 0x025A3CC1 - which is bit 1 of its low byte 0xC1 - is
# clear: `btst #1,(%a0)` therefore answers differently under the byte rule and
# under a longword rule, and the case separates them. 0xC1 at the far end has
# bit 1 clear too, so a core that read the wrong end of the longword also
# answers differently. The bit number is inside a byte, so the separation is
# of the access width alone and does not depend on how an out-of-range bit
# number is reduced - see uncertainty 5 in `logic.nim`'s header.
MEM_BASE = 0x2000
MEM_SEED_BYTES = (0x02, 0x5A, 0x3C, 0xC1)
MEM_GUARD = 0x0BADC0DE   # the longword after a longword memory destination

# ---------------------------------------------------------------------------
# THE ADDRESSING MODES THIS CORPUS DID NOT REACH, AND THE SEEDS THAT SEPARATE
# A CORRECT EVALUATOR FROM A WRONG ONE.
#
# Before these cases, NO case in any group used `(xxx).W`, `(xxx).L`,
# `(d16,PC)` or `(d8,PC,Xn)`. Three groups shipped green over a third of
# `eaAddr`, and all three defects that lived there were found by accident.
# Every case below therefore does two things: it reaches the mode at all, and
# it PINS THE EXACT ADDRESS, so that an evaluator which reaches a NEIGHBOURING
# address answers differently.
#
# THE TWO WINDOWS ARE THE MECHANISM. `EA_WINDOW` is seeded at the address the
# instruction names and `EA_DECOY_WINDOW` at the address a defective evaluator
# reaches. Every byte of each differs from every byte of the other, and neither
# window is symmetric, so a byte read, a longword read and a longword read two
# bytes off all give three different answers:
#
#   EA_WINDOW       byte at +0 = 0x80 (bit 7 SET), long at +0 = 0x80112233,
#                   long at +2 = 0x22334455
#   EA_DECOY_WINDOW byte at +0 = 0x0b (bit 7 CLEAR), long at +0 = MEM_GUARD
#
# The bit-7 disagreement is what the BTST cases read and what puts N in the
# MOVE and ADD cases' status words, so the destination AND the condition codes
# both separate the readings.
EA_WINDOW = (0x80, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77)
EA_DECOY_WINDOW = (0x0B, 0xAD, 0xC0, 0xDE, 0x1F, 0x2E, 0x3D, 0x4C)

# THE ABSOLUTE-LONG ADDRESS, AND THE ADDRESS ITS TWO HALVES SWAPPED.
#
# `(xxx).L` carries its address in TWO extension words. MCF5307 User's Manual
# section 3.7.2, "Organization of Integer Data Formats in Memory", page 3-19:
# "The address N of a longword data item corresponds to the address of the high
# order word. The lower order word is located at address N + 2." The FIRST
# extension word is therefore the HIGH half. `m68k-elf-as -mcpu=5307` agrees:
# `btst %d1,0x00030004` assembles to `0339 0003 0004`.
#
# `ABS_L_ADDR` and `ABS_L_SWAPPED` are each other's halves exchanged, both are
# inside the runner's 1 MiB board, and neither overlaps the other's window, so
# a core that combined the two words the wrong way round reads or writes the
# decoy and fails on a value the case names.
ABS_L_ADDR = 0x00030004
ABS_L_SWAPPED = 0x00040003

# THE ABSOLUTE-SHORT ADDRESS. `(xxx).W` carries ONE extension word,
# sign-extended. Every case that uses it also names `pc`, so a core that read
# two words for it - the `(xxx).L` shape - fails on the program counter even
# when the operand value happens to survive.
#
# THE SIGN EXTENSION ITSELF IS NOT PINNED HERE and cannot be: a negative
# `(xxx).W` addresses 0xFFFF8000 upward, the runner's board is 1 MiB, and a
# case whose operand access reports `busUnmapped` traps and fails on the run
# state rather than on the address. See the uncertainty note in
# `src/mcf5307/machine.nim`.
ABS_W_ADDR = MEM_BASE

# WHERE THE ENCODING IS PLACED. The runner defaults to this, and every
# PC-RELATIVE case NAMES IT in `initial.regs` anyway, so the operand addresses
# those cases assert are derived from a value the case states rather than from
# a constant inside the runner.
EXEC_BASE = 0x10000

# THE PC-RELATIVE BASE IS THE ADDRESS *OF* THE DISPLACEMENT WORD, not the
# address after it. Every instruction below puts its opcode at `EXEC_BASE` and
# its displacement word at `EXEC_BASE + 2`, so the operand is at
# `EXEC_BASE + 2 + PC_DISP`.
#
# THE MANUAL DOES NOT STATE THIS - it gives `(d16,PC)` a row in Table 3-5 and
# no effective-address equation anywhere - so the authority is the pinned
# assembler. Measured: `btst %d1,(target,%pc)` with the opcode at 0 assembles
# to `033a 0004` and the linker places `target` at 6, and
# `m68k-elf-objdump -m m68k:5307` prints `btst %d1,%pc@(6 <target>)`. Base
# plus 4 is 6, so the base is 2 - the address of the displacement word.
#
# A CORE THAT TOOK THE BASE AFTER THE WORD IS EXACTLY TWO BYTES HIGH, which is
# why `EA_WINDOW` is eight bytes and no two of them are equal: the byte the
# instruction names and the byte two along are different, and so are the
# longwords starting at each.
PC_DISP = 0x1E
PC_OPERAND = EXEC_BASE + 2 + PC_DISP

# THE INDEX REGISTER'S WIDTH, AND THE ONE VALUE THAT CAN SEE IT.
#
# An indexed extension word selects a WORD or a LONG index. The pinned
# assembler puts that select at BIT 11: `btst %d1,(4,%pc,%d2)` assembles to
# `033b 2804`, whose extension word `2804` has bit 11 SET and bit 8 CLEAR, and
# `m68k-elf-objdump -m m68k:5307` prints `%pc@(0x6,%d2:l)` - `:l`, a LONG
# index. Bit 8 is the brief-format marker and is always zero; a core that read
# the select there answers WORD for every instruction the assembler emits.
#
# A SMALL POSITIVE INDEX CANNOT TELL THE TWO READINGS APART, which is why the
# existing `tests/t_logic.nim` case used one and was explicitly agnostic.
# `INDEX_VALUE` is the value that can: its low word is 0xfff0, which
# sign-extends to -16, while the whole longword is +65520. The two readings
# therefore land 65536 bytes apart, both inside the runner's 1 MiB board, and
# each case seeds `EA_WINDOW` at one and `EA_DECOY_WINDOW` at the other.
#
# THE MANUAL DOES NOT PRINT THE EXTENSION WORD'S LAYOUT - there is no
# brief-format figure anywhere in it - so the assembler is the authority for
# the bit position. What the manual DOES say is section 3.5.2, "Address Error
# Exception", page 3-15: "Any attempted use of a word-sized index register
# (Xi.w) ... generates an address error". `m68k-elf-as -mcpu=5307` agrees and
# REJECTS `btst %d1,(4,%pc,%d2.w)`, so on this part the select is always LONG
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
            # V reports that the 32 bits written are not the whole product.
            # 0x10000 squared is 0x1_0000_0000, whose low 32 bits are zero:
            # without V this case is indistinguishable from a multiply by
            # zero, so the register expectation alone cannot catch a core that
            # never reports the overflow.
            "name": "mulu_l_overflow_sets_v",
            "mnemonic": "mulu.l",
            "instruction": "mulu.l %d0,%d1",
            "initial": {"regs": {"d0": 0x10000, "d1": 0x10000,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0,
                                  "sr": SR_BASE | CCR_V | CCR_Z | CCR_X}},
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
    #       the two right ones. N and Z come from the result. V is cleared by
    #       LSL, LSR and ASR - none of them can produce a value the operand
    #       size cannot represent - and ASL sets it when the sign changes.
    #
    # The ASL overflow cases all use a shift count of one, deliberately. The
    # two readings of the rule - "the MSB changed at any time during the shift"
    # and "the MSB of the result differs from the MSB of the operand" - are the
    # same statement at a count of one and can differ at a larger count. The
    # ColdFire Family Programmer's Reference Manual is the authority that
    # separates them and it is not on this machine, so no case here pins a
    # count at which the two disagree.
    # `asl_l_count_register_d1` carries no V hazard for the same reason: it
    # shifts by two, and its operand's top three bits are all zero - the sign
    # after k shifts is bit 31-k of the operand, so bits 31, 30 and 29 are
    # every sign the shift passes through - so the sign is unchanged under
    # either reading and both give V clear.
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
            # Measured: the mutation "zero `d.destReg` after the store" on
            # `execAndOr`'s `<ea>`-destination path - the path AND and OR
            # SHARE - failed `and_l_d1_to_memory` and this case PASSED it.
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
            # UNCHANGED, and this case is THE ONLY ONE THAT CAN ASSERT IT FOR
            # EOR. `execEor` is a SEPARATE path from `execAndOr`, so
            # `and_l_d1_to_memory` guards nothing here, and every other EOR
            # case in this group has a data register for its destination.
            # Measured: the mutation "zero `d.destReg` after the store" on
            # `execEor`'s `<ea>`-destination path left the whole group green
            # while this case named `sr` alone.
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
        # is 8. That is the OPERAND SIZE column of MCF5307 User's Manual
        # Table 3-7, which reads "8,32" for BTST, BSET, BCLR and BCHG and for
        # no other instruction in this group. The two cases that pin it are
        # `btst_l_bit_number_above_a_byte` and
        # `btst_b_memory_operand_is_one_byte`. Each one picks a bit number
        # whose answer under the other width is the opposite, so neither can
        # pass against a core that applies the wrong one.
        #
        # Neither case uses a bit number its operand cannot hold, and that is
        # deliberate. `logic.nim` reduces an out-of-range bit number modulo
        # the operand width, and no passage of the User's Manual states any
        # modulus - see uncertainty 5 in that module's header, which also says
        # why Figure 3-8's `MODULO (OFFSET)` annotation does not settle it.
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
        # The three count-of-one cases separate V from C in both directions.
        # `asl_l_1_sign_change_sets_v` has V set with C clear, and
        # `asl_l_1_sign_kept_clears_v` has C set with V clear, so a core that
        # copied one bit into the other fails one of them whichever way round
        # it copied. A core that never writes V fails the first.
        {
            "name": "asl_l_1_sign_change_sets_v",
            "mnemonic": "asl.l",
            "instruction": "asl.l #1,%d0",
            "initial": {"regs": {"d0": 0x60000000, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0xC0000000,
                                  "sr": SR_BASE | CCR_N | CCR_V}},
        },
        {
            "name": "asl_l_1_carry_out_and_sign_change",
            "mnemonic": "asl.l",
            "instruction": "asl.l #1,%d0",
            "initial": {"regs": {"d0": 0x87654321, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": 0x0ECA8642,
                                  "sr": SR_BASE | CCR_V | CCR_C | CCR_X}},
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
        # AN ABSOLUTE-SHORT MEMORY DESTINATION. `eaMemoryAlterable` admits
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
        # BOTH DIRECTIONS OF AND REACH THE ABSOLUTE MODES and they are separate
        # code paths: the `<ea>,Dn` direction READS through `eaRead` and the
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
            # The operand is ONE BYTE: 0x80 at ABS_L_ADDR, whose bit 7 is SET,
            # so Z clears. The byte at the swapped address is 0x0b, whose bit 7
            # is CLEAR, so the other reading sets Z instead.
            "expected": {
                "regs": {"d1": 7, "pc": EXEC_BASE + 6,
                         "sr": SR_DIRTY & ~CCR_Z},
                "mem": (mem_bytes(ABS_L_ADDR, EA_WINDOW)
                        + mem_bytes(ABS_L_SWAPPED, EA_DECOY_WINDOW)),
            },
        },

        # ------------------------------------------------------- (d16,PC)
        #
        # A DYNAMIC BTST IS THE ONE OPERATION IN THIS GROUP WHOSE MASK ADMITS A
        # PC-RELATIVE OPERAND - it reads and never writes. Bit 7 of the byte at
        # `PC_OPERAND` is SET and bit 7 of the byte two along is CLEAR, so Z
        # comes out the opposite way under the two readings of the base.
        # `tests/t_logic.nim` executes the same instruction and, until this
        # commit, deliberately seeded both candidate addresses alike so that it
        # would not pin the base; it now pins it.
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
            # THE SAME EXTENSION WORD ON AN ADDRESS-REGISTER BASE. `eaAnIndex`
            # and `ea7PCIndex` share `indexOperand`, so the width rule is one
            # line of code serving two addressing modes; a case that covered
            # only the PC form would leave the other half of that line
            # unguarded. This is the only case in the corpus that reaches
            # `(d8,An,Xn)` at all.
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

    # `nop` names `sr`.
    #
    # An `sr` expectation of "unchanged" is satisfied by a NOP that never
    # executed, since an instruction that never ran changes nothing. What
    # makes the expectation safe is that `conformance/runner.cpp` asserts
    # `mcf5307_faulted`, then `mcf5307_halted`, then a non-zero cycle return,
    # for every case and before it compares one register. A NOP that never
    # executed cannot reach the comparison: the core either faulted, halted or
    # completed no instruction, and each of those fails the case on its own.
    # Measured on the mutation "the encoding word is 0000 instead of 4e71" -
    # a NOP that is not there - the old runner passed the case with `sr`
    # named and this one reports the trap.
    #
    # So the case takes the corpus's ordinary shape for an instruction that
    # must not touch the condition codes: `SR_DIRTY` in, `SR_DIRTY` back. That
    # is now an assertion ON TOP OF the run-state checks rather than instead
    # of them, and it is the strongest statement this corpus can make about
    # NOP - the whole 16-bit status word is unchanged.
    "control": [
        {
            "name": "nop",
            "mnemonic": "nop",
            "instruction": "nop",
            "initial": {"regs": {"sr": SR_DIRTY}},
            "expected": {"regs": {"sr": SR_DIRTY}},
        },
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
