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
have to state every other one. This is what lets the seed corpus leave the
condition-code register (`sr`) unstated where the case sets no data register
it is required to change every time.

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
# name only the registers the case must change; every other register is not
# asserted. This keeps the seed corpus unambiguous about arithmetic that
# also touches the condition-code register, which no seed case asserts.
#
# The seed corpus is deliberately modest. CPU-7 to CPU-10 own their group's
# `*_*.json` files and add the full instruction set there; this table is the
# generator's living source for the cases it emits. Editing a case is done
# here, never in the committed JSON.

CASES = {
    "move": [
        {
            "name": "move_l_d0_to_d1",
            "mnemonic": "move.l",
            "instruction": "move.l %d0,%d1",
            "initial": {"regs": {"d0": 1, "d1": 2}},
            "expected": {"regs": {"d1": 1}},
        },
        {
            "name": "move_l_a0_to_a1",
            "mnemonic": "move.l",
            "instruction": "move.l %a0,%a1",
            "initial": {"regs": {"a0": 0x1000, "a1": 0}},
            "expected": {"regs": {"a1": 0x1000}},
        },
        {
            "name": "move_l_imm_to_d0",
            "mnemonic": "move.l",
            "instruction": "move.l #0x12345678,%d0",
            "initial": {"regs": {}},
            "expected": {"regs": {"d0": 0x12345678}},
        },
        {
            "name": "moveq_5_to_d0",
            "mnemonic": "moveq",
            "instruction": "moveq #5,%d0",
            "initial": {"regs": {"d0": 0}},
            "expected": {"regs": {"d0": 5}},
        },
        {
            "name": "lea_4_a0_to_a1",
            "mnemonic": "lea",
            "instruction": "lea (4,%a0),%a1",
            "initial": {"regs": {"a0": 0x1000, "a1": 0}},
            "expected": {"regs": {"a1": 0x1004}},
        },
        {
            "name": "move_w_d0_to_d1",
            "mnemonic": "move.w",
            "instruction": "move.w %d0,%d1",
            "initial": {"regs": {"d0": 0x1234, "d1": 0}},
            "expected": {"regs": {"d1": 0x1234}},
        },
        {
            "name": "move_b_d0_to_d1",
            "mnemonic": "move.b",
            "instruction": "move.b %d0,%d1",
            "initial": {"regs": {"d0": 0x1234, "d1": 0}},
            "expected": {"regs": {"d1": 0x34}},
        },
    ],

    "alu": [
        {
            "name": "add_l_d0_to_d1",
            "mnemonic": "add.l",
            "instruction": "add.l %d0,%d1",
            "initial": {"regs": {"d0": 1, "d1": 2}},
            "expected": {"regs": {"d1": 3}},
        },
        {
            "name": "sub_l_d0_from_d1",
            "mnemonic": "sub.l",
            "instruction": "sub.l %d0,%d1",
            "initial": {"regs": {"d0": 1, "d1": 2}},
            "expected": {"regs": {"d1": 1}},
        },
        {
            "name": "neg_l_d0",
            "mnemonic": "neg.l",
            "instruction": "neg.l %d0",
            "initial": {"regs": {"d0": 5}},
            "expected": {"regs": {"d0": -5}},
        },
        {
            "name": "clr_l_d0",
            "mnemonic": "clr.l",
            "instruction": "clr.l %d0",
            "initial": {"regs": {"d0": 0x12345678}},
            "expected": {"regs": {"d0": 0}},
        },
        {
            "name": "addq_l_1_to_d1",
            "mnemonic": "addq.l",
            "instruction": "addq.l #1,%d1",
            "initial": {"regs": {"d1": 6}},
            "expected": {"regs": {"d1": 7}},
        },
        {
            "name": "subq_l_1_from_d0",
            "mnemonic": "subq.l",
            "instruction": "subq.l #1,%d0",
            "initial": {"regs": {"d0": 6}},
            "expected": {"regs": {"d0": 5}},
        },
        {
            "name": "addi_l_7_to_d1",
            "mnemonic": "addi.l",
            "instruction": "addi.l #7,%d1",
            "initial": {"regs": {"d1": 1}},
            "expected": {"regs": {"d1": 8}},
        },
        {
            "name": "mulu_l_d0_by_d1",
            "mnemonic": "mulu.l",
            "instruction": "mulu.l %d0,%d1",
            "initial": {"regs": {"d0": 3, "d1": 4}},
            "expected": {"regs": {"d1": 12}},
        },
        {
            "name": "ext_l_d0_word",
            "mnemonic": "ext.l",
            "instruction": "ext.l %d0",
            "initial": {"regs": {"d0": 0x00008000}},
            "expected": {"regs": {"d0": -32768}},
        },
    ],

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
                "regs": dict(case["initial"]["regs"]),
                "mem": list(case["initial"].get("mem", [])),
            },
            "expected": {
                "regs": dict(case["expected"]["regs"]),
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
