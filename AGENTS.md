# mcf5307 — agent instructions

An emulator for the Freescale MCF5307 ColdFire processor, and a model of the
Philips ISP1181 USB device controller. The core is written in Nim. CMake drives
the Nim compiler and produces a static library plus a C header for a C or C++
caller.

Repository: `axiomantic/mcf5307`. Licence: MIT.

## Build and test

```bash
cmake -S . -B build
cmake --build build
ctest --test-dir build
```

Requirements: CMake 3.20 or later, and the exact Nim version named in
`.nim-version`. The configure step reads `.nim-version`, runs `nim --version`,
and stops with an error that prints both versions when they disagree.

Targets:

| Target | Content |
|---|---|
| `mcf5307` | The static library. The core and the ISP1181 model. |
| `mcf5307_tests` | The unit tests. |
| `mcf5307_conformance` | The runner for the generated ColdFire conformance corpus. |

CMake exports `mcf5307::mcf5307` for a consumer.

### The `--no-tests=error` convention

Every `ctest` invocation in this project carries `--no-tests=error`. A `-R`
pattern that matches nothing is not a weak check; it is a check that cannot
fail. **The flag governs RUN mode only.** In `-N` listing mode it is inert: the
listing exits 0 whether or not a test matched. Do not assert an effect from the
flag in listing mode, and do not remove the flag for tidiness.

## Layout

| Path | Content |
|---|---|
| `src/mcf5307.nim` | The library entry point. |
| `src/mcf5307/` | The core modules: decode, effective address, ALU, logic, move, control, exception, interrupt, CPU and machine. |
| `include/mcf5307.h` | The hand-written public C header. Not generated. |
| `tests/` | Nim unit tests, plus the C and C++ ABI gate tests. |
| `conformance/` | The generated ColdFire conformance corpus, its generator, and the runner. |
| `cmake/Nim.cmake` | The Nim toolchain integration. |

Test naming: `t_*` for the Nim unit tests, `t0_*` for the ABI and gate tests,
`mcf5307_conformance_*` for the conformance runs. Read the registered names out
of the build tree with `ctest --test-dir build -N` rather than counting them by
hand.

## Build flags

The Nim compile step uses `-d:release` and `--panics:on`. It does **not** use
`--checks:off`, and it does **not** use `-d:danger`. Do not add them. The
run-time checks stay in the release build deliberately: a check that stops the
process is better than a check that lets the library return a wrong result.

## The clean-room rule

This repository is MIT, and every contribution obeys a clean-room rule with
respect to GPL and LGPL code.

- **Facts are usable from any source.** Register addresses, MBAR offsets, bit
  layouts, field positions, access widths, opcode encodings and masks,
  exception frame layouts. These are facts about Motorola silicon, not the
  expression of an author. A GPL source file is a legitimate place to *check* a
  fact.
- **Expression is never usable.** No copied lines. No transliterated function
  body. No algorithm taken from a source file, including one taken "with its
  bugs fixed" — a corrected derivative is still a derivative. Do not write a
  decoder or a peripheral model while reading another project's source as a
  template or a decode specification.
- **Implement from** the Motorola manual set — the ColdFire Family
  Programmer's Reference Manual, the MCF5307 User's Manual, the 1997 ColdFire
  PRM — published datasheets, and this project's own measurements.

ColdFire condition codes differ from the 68000. Check the ColdFire PRM, not a
68000 reference.

## Comments

Comments are sparse. Write one only where a reader must otherwise reconstruct a
DECISION. The code says what it does. The comment says why you chose it instead
of the alternative.

Never write these in a comment:

- **A count** — cases, tests, scenarios, mutations, symbols, files, or lines.
  The next change makes it wrong, and nothing catches it.
- **A present-tense claim about what the tests cover**, or about what a wrong
  implementation would fail. If coverage matters, assert it in a test. A failing
  test is the only durable statement about coverage.
- **A note about history** ("this used to...", "an earlier version..."). Git
  holds that.

**One exception, and it is the only one.** A number that a mechanism reads and
checks at build time or at test time may stay. The check is then the source of
truth, not the comment, and it fails loudly when the number drifts. A number
that no mechanism reads is a liability.

**A date does not rescue a stale claim.** This tree has changed several times
within one day. A date discriminates nothing at that rate.

**An invariant with no mechanism is a comment.** If a property must hold, make
something go red when it stops holding. If no portable mechanism exists, say so
once at the site and record the acceptance — do not let a good comment stand in
for a check.

### Scope: code we authored

This repository is original work, so the rule applies throughout. Do not delete
or rewrite comments to satisfy this rule as a sweep; repair a comment when you
change the line it describes.

## Gotchas

- `xcode-select` on this machine points at CommandLineTools while full Xcode is
  installed. A CMake configure may need a `DEVELOPER_DIR` prefix. No `sudo`
  required.
- A build that succeeds is not a check. Verify the artifact a step should have
  produced, not the exit status. A stale binary left by a failed compile makes a
  test runner report a pass that describes code which no longer exists.
- `git grep` skips untracked files. Use `grep -r`, `rg`, or `git grep
  --untracked` before claiming something appears nowhere, and name the tool
  beside the claim.

## Related

This library is a component of a Nord Modular G2 emulator, but it holds no
knowledge of that instrument. A program that needs a ColdFire processor can use
it alone. The emulator's implementation plan and its cross-repository rules live
in the `nord-modular-emulator` workspace.
