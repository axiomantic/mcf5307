#!/usr/bin/env python3
"""The ColdFire ISA_A conformance corpus generator.

Task CPU-4. Its Check: line has two halves; this script is the Linux half.

  Linux x86-64 : `python3 conformance/generate.py --out conformance/corpus`
                 must regenerate the committed corpus byte-identical.
  macOS arm64, Windows x86-64 : the parse check `t0_corpus_parses` runs
                 instead; regeneration proves nothing a parse does not.

The generator encodes each case's instruction with the GNU m68k cross
assembler and writes a deterministic JSON corpus. Both the script and the
generated corpus are committed, so no cross toolchain is needed at test time
on any platform.

## Determinism (plan work item M-9)

"Byte-identical regeneration" is only meaningful if the writer is
deterministic. Every decision that could vary the output is fixed here:

  * the JSON is written with `sort_keys=True` and a fixed indent, so the
    key order and layout cannot vary across runs or hosts;
  * every value is written from Python ints or fixed lowercase hex strings;
  * the per-group file names are fixed (`<group>_00.json`);
  * the case order is the order the CASES table lists, which is fixed.

The one non-deterministic input is the ASSEMBLER: a different binutils
version can emit different bytes for the same source. That is why the
assembler version is pinned in `docs/toolchain.md`. Regenerating under the
pinned version is byte-identical; the CI job installs exactly that version.

## The corpus schema

One file per group, `conformance/corpus/<group>_00.json`, where `<group>` is
one of the four groups CPU-7 to CPU-10 name: `move`, `alu`, `logic`,
`control`.

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

A register name is "d0".."d7", "a0".."a7", "sr" or "pc". The runner (CPU-5)
sets the `initial` registers, executes the case's encoding, and asserts each
`expected` register equals its value. Registers the `expected` object does
not name are not asserted: a case that affects only one register does not
have to state every other one.

## THE CONDITION CODES ARE ASSERTED THROUGH `sr`, AND THE WHOLE WORD IS
## ASSERTED

`sr` IS A REGISTER LIKE ANY OTHER, in `initial` and in `expected` both. The
runner sets it through the same bridge as `d0` and asserts it by the same
equality. This was true of the runner from CPU-5 and NO CASE USED IT: measured
on the committed corpus before this change, not one case in any of the four
files named `sr` in its expected state, so every condition-code rule in every
group was invisible to conformance. Dropping ADD's carry-out, dropping its
signed overflow, dropping SUB's and NEG's borrow, and making the multiply
never report V each left `mcf5307_conformance_alu` at 9 of 9.

THE VALUE IS THE WHOLE 16-BIT STATUS REGISTER AND NOT A CONDITION-CODE MASK.
`0x2700` is the reset value: supervisor set, interrupt mask 7, every condition
code clear. A case that expects `0x2718` therefore asserts three things at
once - that X and N are set, that C, V and Z are clear, AND that the executor
left the supervisor bit and the interrupt mask alone. `tests/t_alu.nim` and
`tests/t_move.nim` assert the same whole word, so the two views of one rule
cannot drift apart.

THE INCOMING `sr` IS DELIBERATELY DIRTY. A case whose instruction must CLEAR
a flag proves nothing when that flag was already clear on entry, exactly as a
sized MOVE proves nothing into a zero destination. Every flag-asserting case
below therefore starts from `SR_DIRTY` (0x271F: every condition code set) and
names the exact word the instruction must leave behind. A case whose
instruction must not touch the condition codes AT ALL - MOVEA, LEA, PEA, LINK,
UNLK, MOVEM - expects `SR_DIRTY` back unchanged, which is an assertion a clean
incoming `sr` cannot make.

WHERE THE MANUAL LEAVES A FLAG UNDEFINED, NO `sr` IS ASSERTED. The equality is
over the whole word, so a case cannot assert four flags and decline the fifth.
A case whose rule is not defined for every bit carries no `sr` at all rather
than pin an accident of this implementation. `docs/toolchain.md` is not the
authority here; the ColdFire Family Programmer's Reference Manual is
(AGENTS.md section 11).

A CASE THAT ASSERTS NO REGISTER IS JUDGED BY ITS CYCLE RETURN, and naming
`sr` takes that judgement away. The runner falls back to "the instruction
returned a non-zero cycle count" only when `expected.regs` is EMPTY. `nop` is
the one case in this corpus with no register effect at all, so it deliberately
names no `sr`: an `sr` expectation of "unchanged" would be satisfied by a NOP
that never executed.

"mem" is a list of `{"addr": int, "size": int, "value": int}` writes. The
seed corpus carries only register cases, so every "mem" array in it is empty;
the field exists so the memory-based cases CPU-7 to CPU-10 add have a place.
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
# These are facts about Motorola silicon (AGENTS.md section 11), and they are
# the same five bit positions `src/mcf5307/machine.nim` names and the same
# `srBase` `tests/t_alu.nim` and `tests/t_move.nim` name.

SR_BASE = 0x2700      # supervisor, interrupt mask 7, every condition code clear
CCR_C = 0x01
CCR_V = 0x02
CCR_Z = 0x04
CCR_N = 0x08
CCR_X = 0x10

# THE INCOMING STATUS REGISTER OF EVERY FLAG-ASSERTING CASE. Every condition
# code is SET on entry, so that an instruction which must CLEAR a flag is
# separable from one that never wrote the flag at all. A clean incoming `sr`
# cannot make that distinction, for the same reason a zero destination register
# cannot separate a merging sized write from a replacing one.
SR_DIRTY = SR_BASE | CCR_C | CCR_V | CCR_Z | CCR_N | CCR_X

# ---------------------------------------------------------------------------
# The destination seeds.
#
# A SIZED WRITE TO A DATA REGISTER REPLACES THE LOW size BYTES AND KEEPS THE
# REST. A destination that starts at zero cannot tell that rule from a write
# that replaces the whole register, because both leave the same value behind.
# That is not hypothetical: `eaWrite` in `src/mcf5307/machine.nim` replaced the
# whole register on a `MOVE.B` for days and `mcf5307_conformance_move` stayed at
# 18 of 18 throughout, because BOTH of its sized cases started the destination
# at zero.
#
# EVERY BYTE OF THESE SEEDS DIFFERS. A palindromic or repeating seed (0x11111111,
# 0x12341234) survives a wrong byte lane, a wrong word half or a byte-swapped
# store and still compares equal. 0x12345678 is the value the hand-written
# `tests/t_move.nim` uses and it is used here for the same reason.
DIRTY_D = 0x12345678   # the data-register destination seed
DIRTY_A = 0x0BADC0DE   # the address-register destination seed


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
# TWO RULES GOVERN EVERY CASE BELOW, and both exist because the corpus could
# not see what it was supposed to be measuring.
#
#   1. THE DESTINATION NEVER STARTS AT ZERO where a sized write could merge
#      into it. `DIRTY_D` and `DIRTY_A` are the seeds; see their definition.
#   2. THE INCOMING `sr` IS `SR_DIRTY` wherever the case asserts flags at all,
#      so that "the instruction cleared this flag" is separable from "the
#      instruction never wrote this flag".
#
# The seed corpus is deliberately modest. CPU-7 to CPU-10 own their group's
# `*_*.json` files and add the full instruction set there; this table is the
# generator's living source for the cases it emits. Editing a case is done
# here, never in the committed JSON.

CASES = {
    # THE CONDITION-CODE RULES OF THIS GROUP. `MOVE` sets N and Z from the
    # value moved AT THE OPERAND SIZE, clears V and C, and LEAVES X ALONE.
    # `MOVEQ` does the same over the sign-extended long. `MOVEA`, `LEA`,
    # `PEA`, `LINK`, `UNLK` and `MOVEM` AFFECT NO CONDITION CODE AT ALL, and
    # each of those expects `SR_DIRTY` straight back.
    "move": [
        {
            # THE CONTROL AGAINST AN OVER-FIX of the two sized cases below. A
            # long write REPLACES the whole register: none of the seed
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
            # whole register and TOUCHES NO CONDITION CODE, which is why the
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
            # THE WORD MERGE. The low word is replaced and THE UPPER WORD OF
            # THE SEED SURVIVES; a replacing write gives 0x00001234 here. The
            # source carries 0xFFFF above its low word and none of it may
            # reach the destination, and N comes from BIT 15 of the word
            # written (0) and not from bit 31 of the source (1).
            "name": "move_w_d0_to_d1",
            "mnemonic": "move.w",
            "instruction": "move.w %d0,%d1",
            "initial": {"regs": {"d0": 0xFFFF1234, "d1": DIRTY_D,
                                 "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 0x12341234, "sr": SR_BASE | CCR_X}},
        },
        {
            # THE BYTE MERGE, and the case the repaired `eaWrite` defect was
            # measured on: 0xAA over the low byte of 0x12345678 is 0x123456AA
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
            # THE BYTE MERGE FROM MEMORY. The load path and the register-to-
            # register path are different code, so the merge is asserted on
            # both; this one started the destination at zero too.
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
            # MOVEA.W SIGN-EXTENDS INTO THE WHOLE REGISTER. It is the one
            # word-sized write in this group that does NOT merge, so the seed
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
            # THE LOADED REGISTERS START DIRTY. MOVEM.L replaces each register
            # whole; a load that wrote a half-register would leave part of the
            # seed behind, and every one of these started at zero.
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
    ],

    # THE CONDITION-CODE RULES OF THIS GROUP. `ADD`, `SUB`, `ADDQ`, `SUBQ`,
    # `ADDI` and `NEG` set N and Z from the result, V from the SIGNED overflow,
    # and C AND X TOGETHER from the carry or the borrow out of bit 31 - X is
    # RECOMPUTED by these, not preserved. `CLR` sets Z, clears N, V and C, and
    # LEAVES X ALONE. `EXT` and the 32-bit multiply set N and Z from the
    # result, clear C, and leave X alone; the multiply's V reports that the 32
    # bits written are not the whole product.
    #
    # HALF OF THIS GROUP IS THE FLAGS, AND THE FLAGS WERE NOT ASSERTED. Every
    # `sr` below was measured against a mutation that the corpus previously
    # could not see; the four the task names are marked.
    "alu": [
        {
            "name": "add_l_d0_to_d1",
            "mnemonic": "add.l",
            "instruction": "add.l %d0,%d1",
            "initial": {"regs": {"d0": 1, "d1": 2, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": 3, "sr": SR_BASE}},
        },
        {
            # THE CARRY OUT OF BIT 31 SETS BOTH C AND X, and the result is
            # zero, so Z is set too. DROPPING ADD'S CARRY-OUT IS INVISIBLE
            # WITHOUT THIS CASE: `add.l` of 1 and 2 carries nothing, and the
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
            # THE SIGNED OVERFLOW IS A DIFFERENT QUESTION FROM THE CARRY, and
            # this case is where the two disagree: 0x7FFFFFFF + 1 crosses into
            # the negative half, so V and N are set and C IS CLEAR. A core that
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
            # THE BORROW SETS C AND X. 1 - 2 is -1, which a core that dropped
            # the borrow still computes correctly.
            "name": "sub_l_borrow",
            "mnemonic": "sub.l",
            "instruction": "sub.l %d0,%d1",
            "initial": {"regs": {"d0": 2, "d1": 1, "sr": SR_DIRTY}},
            "expected": {"regs": {"d1": -1,
                                  "sr": SR_BASE | CCR_C | CCR_X | CCR_N}},
        },
        {
            # NEG SETS C WHENEVER A BORROW LEFT THE WORD, which for a negation
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
            # CLR LEAVES X ALONE. It is the one instruction in this group that
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
            # THE ADDQ DATA FIELD 000 MEANS EIGHT, NOT ZERO. One to seven
            # encode themselves and zero would be a no-operation, so the
            # encoding spends that slot on the eighth value. NO OTHER CASE
            # SEPARATES THE TWO READINGS: every other ADDQ here uses #1.
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
            # V REPORTS THAT THE 32 BITS WRITTEN ARE NOT THE WHOLE PRODUCT.
            # 0x10000 squared is 0x1_0000_0000, whose low 32 bits are zero:
            # WITHOUT V THIS CASE IS INDISTINGUISHABLE FROM A MULTIPLY BY
            # ZERO, so the register expectation alone cannot catch a core that
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
            # EXT.L REPLACES THE WHOLE REGISTER from its low word, so the seed
            # above that word must not survive. N comes from bit 31 of the
            # extended long, and X is untouched.
            "name": "ext_l_d0_word",
            "mnemonic": "ext.l",
            "instruction": "ext.l %d0",
            "initial": {"regs": {"d0": 0xAAAA8000, "sr": SR_DIRTY}},
            "expected": {"regs": {"d0": -32768,
                                  "sr": SR_BASE | CCR_N | CCR_X}},
        },
    ],

    # THIS GROUP CARRIES NO `sr` EXPECTATION, AND THAT IS A DELIBERATE GAP.
    # `mcf5307_conformance_logic` is 0 of 8 because no executor for the group
    # exists yet; CPU-9 writes it and owns these cases. The shift rules - what
    # ASL's V reports, what a shift count of zero does to C, and which shifts
    # write X - are the substance of that task, and pinning them here from a
    # group with nothing to measure against would pin a guess rather than a
    # rule. The mechanism is proven on `move` and `alu`; CPU-9 adds `"sr"` to
    # these cases the same way, and the same two rules at the head of this
    # table apply.
    "logic": [
        {
            "name": "and_l_d0_d1",
            "mnemonic": "and.l",
            "instruction": "and.l %d0,%d1",
            "initial": {"regs": {"d0": 0x0f0f, "d1": 0xff00}},
            "expected": {"regs": {"d1": 0x0f00}},
        },
        {
            "name": "or_l_d0_d1",
            "mnemonic": "or.l",
            "instruction": "or.l %d0,%d1",
            "initial": {"regs": {"d0": 0x0001, "d1": 0x0100}},
            "expected": {"regs": {"d1": 0x0101}},
        },
        {
            "name": "eor_l_d0_d1",
            "mnemonic": "eor.l",
            "instruction": "eor.l %d0,%d1",
            "initial": {"regs": {"d0": 0x00ff, "d1": 0x0f0f}},
            "expected": {"regs": {"d1": 0x0ff0}},
        },
        {
            "name": "not_l_d0",
            "mnemonic": "not.l",
            "instruction": "not.l %d0",
            "initial": {"regs": {"d0": 0x0000000f}},
            "expected": {"regs": {"d0": 0xfffffff0}},
        },
        {
            "name": "asl_l_1_d0",
            "mnemonic": "asl.l",
            "instruction": "asl.l #1,%d0",
            "initial": {"regs": {"d0": 0x10000005}},
            "expected": {"regs": {"d0": 0x2000000a}},
        },
        {
            "name": "lsl_l_2_d1",
            "mnemonic": "lsl.l",
            "instruction": "lsl.l #2,%d1",
            "initial": {"regs": {"d1": 1}},
            "expected": {"regs": {"d1": 4}},
        },
        {
            "name": "asr_l_1_d0",
            "mnemonic": "asr.l",
            "instruction": "asr.l #1,%d0",
            "initial": {"regs": {"d0": 0x80000008}},
            "expected": {"regs": {"d0": 0xc0000004}},
        },
        {
            "name": "lsr_l_1_d1",
            "mnemonic": "lsr.l",
            "instruction": "lsr.l #1,%d1",
            "initial": {"regs": {"d1": 0x80000000}},
            "expected": {"regs": {"d1": 0x40000000}},
        },
    ],

    # `nop` NAMES NO REGISTER ON PURPOSE, AND THAT INCLUDES `sr`. It has no
    # register effect of any kind, so the runner judges it by its cycle return
    # - and the runner applies that judgement ONLY when `expected.regs` is
    # empty. An `sr` expectation of "unchanged" would be satisfied by a NOP
    # that never executed at all, so naming `sr` here would REMOVE the only
    # assertion this case has rather than add one.
    "control": [
        {
            "name": "nop",
            "mnemonic": "nop",
            "instruction": "nop",
            "initial": {"regs": {}},
            "expected": {"regs": {}},
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
