# Toolchain pins

The conformance corpus is generated with the GNU m68k cross binutils, and the
byte-identical regeneration check of CPU-4 depends on the assembler being
the pinned version. A different assembler version can emit different bytes
for the same source, so the pinned version is recorded here, beside
`.nim-version`, and the Linux x86-64 CI job installs exactly it. This file is
one of the files task CPU-4 owns.

## The m68k cross assembler

| What | Value |
|---|---|
| Assembler | `m68k-elf-as` |
| Targets | `-mcpu=5307` (ColdFire ISA_A) |
| Pinned version | **GNU assembler (GNU Binutils) 2.47.20260726** |
| Object copy | `m68k-elf-objcopy -O binary -j .text` |

The pinned version is the full first line of `m68k-elf-as --version`. The
generator (`conformance/generate.py`) reads that first line and **refuses to
regenerate the committed corpus** unless it equals the pinned value, so a
byte-identical regeneration can never be silently produced by a different
assembler.

`conformance/generate.py --out conformance/corpus` regenerates the corpus.
The committed copy under `conformance/corpus/` is the generator's output; the
Linux x86-64 check asserts the regeneration is byte-identical. On a platform
without the cross assembler (macOS arm64, Windows x86-64) the registered
parse test `t0_corpus_parses` is the check instead.

## Why byte-identical, and what keeps it true

The assertion is only meaningful if the writer is deterministic. The
generator fixes every choice that could vary the output: `sort_keys=True`
JSON with a fixed indent, fixed lowercase hex encodings, fixed per-group file
names (`<group>_00.json`) and a fixed case order. The one input it does not
control is the assembler, which is exactly why the assembler version is
pinned above and checked at generation time.

## The corpus schema

See the docstring in `conformance/generate.py` for the full specification.
In brief: one file per group (`move`, `alu`, `logic`, `control` — the four
groups CPU-7 to CPU-10 name), each with a non-empty `cases` array, and every
case carrying an `instruction`, an `initial` state and an `expected` state.
`t0_corpus_parses` (`conformance/parse_check.cpp`) validates exactly that.
