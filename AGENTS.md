# mcf5307 — agent instructions

An emulator for the Freescale MCF5307 ColdFire processor, and a model of the
Philips ISP1181 USB device controller. The core is written in Nim. CMake drives
the Nim compiler and produces a static library plus a C header for a C or C++
caller.

Repository: `axiomantic/mcf5307`. Licence: MIT.

## Build and test

### Narrow — the T0 suite

There is **no configure-time narrowing in this repository.** The Nim compile is
a configure step and produces the whole library, and `conformance/` is entered
whenever this project is top level, with no option to turn it off. Narrowing is
therefore a build-target choice and a `ctest -R` choice, and nothing else.

**Use the preset.** It carries the target, the keep-going flag and the pattern,
so none of the three can be dropped by hand.

```bash
cmake --preset t0
cmake --build --preset t0
ctest --preset t0
```

`cmake --list-presets`, `--list-presets=build` and `--list-presets=test` name
the rest. `CMakePresets.json` is committed: this repository is original work and
has no upstream to conflict with.

The raw form, which is what the preset expands to:

```bash
cmake -S . -B <build> -DCMAKE_BUILD_TYPE=Release
cmake --build <build> --parallel --target mcf5307_tests -- -k
ctest --test-dir <build> --no-tests=error -R '^t0_|^t_' --output-on-failure
```

`^t0_|^t_` is the pattern `.github/workflows/ci.yml` carries as `T0_PATTERN`.
It excludes the `mcf5307_conformance_*` runs and nothing else; `ci.yml` keeps a
written roster of exactly those exclusions, so read the roster there rather than
trusting this line **or the preset** — the preset is a second copy of the
pattern, not its source.

`--no-tests=error` has no test-preset field. The preset carries it as the
environment variable `CTEST_NO_TESTS_ACTION`, which needs CMake 3.26 or later —
above this project's declared 3.20 floor. On an older CTest the preset runs
without that guard while the raw form still has it.

### Full

```bash
cmake --preset full
cmake --build --preset full
ctest --preset full
```

The raw form:

```bash
cmake -S . -B <build> -DCMAKE_BUILD_TYPE=Release
cmake --build <build> --parallel -- -k
ctest --test-dir <build> --no-tests=error --output-on-failure
```

The narrow run leaves the conformance corpus unexecuted, so a change to the
core's decode, ALU, logic or control behaviour needs the full run. A change that
alters the published C ABI needs it too: the consumer that links this library is
`gearmulator`'s `g2Lib`, and nothing in this tree builds that.

### Traps

- **The presets build OUTSIDE the source tree**, at
  `../build-mcf5307/<preset>/`, and the raw forms above build inside it at
  `build/` and `build-asan/`. A `ctest --test-dir build` typed after a
  `cmake --build --preset t0` reads a different tree from the one just built.
  Pick one form per check.
- **`-- -k` under a Makefile generator is what keeps a build failure readable.**
  A target that did not build leaves its registered test `***Not Run`, and ctest
  counts that as failed. Without keep-going the targets after the first failure
  are never attempted either, so one broken target reds every suite behind it
  and the report stops naming which one broke. Keep-going is not a way of
  ignoring a broken build: `cmake --build` still exits non-zero. Ninja's
  spelling is `-- -k 0`.
- **The Nim compile runs at CONFIGURE time**, not at build time. `src/*.nim`,
  `.nim-version`, `include/mcf5307.h`, `tests/abi_smoke_symbols.inc`,
  `tests/abi_stub.c` and `tests/t_*.nim` are registered as configure
  dependencies, so an ordinary edit to one of them re-runs the configure by
  itself. A change those paths do not cover reaches nothing until
  `cmake -S . -B <build>` runs again.
- **A LIST FILE IS A DEPENDENCY BY MTIME, AND A RESTORE THAT REWINDS MTIME
  DEFEATS IT.** The per-suite drivers under `<build>/tests/*_driver.cmake` are
  GENERATED from templates inside `tests/tests_cpu.cmake`, and the case-total
  pins (`mcf5307_check_case_total`) live in the template, not in the driver.
  CMake does re-generate them when it sees the list file as newer — an ordinary
  edit is picked up by `cmake --build` on its own, with no explicit configure.
  **What it does NOT pick up is a list file whose mtime went BACKWARDS**: a `mv`
  from a `sed -i.bak` backup, a `git checkout` of an older blob, or a copied
  tree all leave the stale driver in place, and the suite is then graded against
  a pin that is on nobody's disk. MEASURED: restoring `tests/tests_cpu.cmake`
  from a `.bak` left a driver carrying a deliberately wrong pin of `999` while
  the source read `32`, and the suite failed against a figure the tree did not
  contain. **After any restore of a list file, `touch` it before reconfiguring**,
  and confirm the pin inside the generated driver rather than in the source.
- **THE BUILD IS A REGISTERED TEST: `t0_build_is_current`.** It runs first in
  every top-level ctest run, builds the tree it is in
  (`cmake --build <dir> --parallel`, the command `ci.yml` already uses), and
  fails with a banner when the build fails. Every other test carries
  `FIXTURES_REQUIRED`, so a failed build leaves them `Not Run` instead of
  Passed. MEASURED, and this is why it exists: with a syntax error planted in
  `conformance/runner.cpp`, `cmake --build --preset full` exited 2 and
  `ctest --preset full` then reported `100% tests passed, 0 tests failed out of
  37` from the binaries of the previous successful build; the same shape gave
  `t0_abi_smoke ... Passed` on the t0 preset. Read the two verdicts apart:
  `t0_build_is_current (Failed)` with everything else `(Not Run)` is a BUILD
  failure; a named test `(Failed)` while the gate Passed is a TEST failure.
  `cmake/BuildGate.cmake` registers it and `cmake/run_build_gate.cmake` is its
  body. It is registered only when `PROJECT_IS_TOP_LEVEL`, so a consumer's tree
  has no gate and no fixture requirement — verified: a consumer configure lists
  `t0_abi_gate_on` and nothing else.
- **`cmake --build --preset t0` still does not build `t0_corpus_parses`; the
  gate does.** The t0 build preset carries `--target mcf5307_tests`;
  `t0_corpus_parses` is a separate `add_executable` in
  `conformance/conformance_cpu.cmake` that the `^t0_|^t_` test pattern matches,
  so a clean clone used to report it `***Not Run`. The gate builds the tree's
  default target rather than a roster of targets, so the executable exists by
  the time any test runs. MEASURED: deleting
  `<build>/conformance/t0_corpus_parses` and running `ctest --preset t0` brings
  it back and the test passes. The consequence is that `ctest --preset t0` is
  now wider than the t0 BUILD preset — a break in `conformance/runner.cpp`,
  which that preset never compiles, turns the t0 run red.
- **Never configure this repository's own build tree with
  `-DMCF5307_ABI_GATE=OFF`.** The switch exists for a host that cannot run a
  symbol reader; it disarms step 4a whole, and the cache entry then persists
  silently through later builds. Scratch trees only.
- On this host `xcode-select` points at CommandLineTools while full Xcode is
  installed. The Unix-Makefiles configure resolves an SDK without help; prefix
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` only if a step
  fails to find one. `tests/reach.sh` sets it defensively for the same reason.

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
- **An enumeration whose length is the claim.** A stale enumeration is a stale
  count with the number spelled out. Delete the word "four" from "any of those
  four values" and the list above it still says four. It goes wrong by the
  mechanism the word did.
- **A path that does not resolve.** A comment that names a file, a script, a
  test, or a type must name one that exists.
- **A claim about the rest of the tree.** A comment describes the code beside
  it. Do not write what else imports this module, what its only consumer is,
  which task consumes it next, or what another file does not name. The import
  graph answers those and stays right; a sentence about them is derivable, goes
  stale the moment another task moves, and records no decision.

**One exception, and it is the only one.** A number that a mechanism reads and
checks at build time or at test time may stay. The check is then the source of
truth, not the comment, and it fails loudly when the number drifts. A number
that no mechanism reads is a liability.

**A date does not rescue a stale claim.** This tree has changed several times
within one day. A date discriminates nothing at that rate.

**The path rule is the one a machine can decide, and that is why it is stated
apart from the others.** Each other rule here needs a reader's judgement about
what a sentence claims. "Every path-shaped token resolves" is a regular
expression and a file test. Write the check. Do not trust a sweep to hold.

**A path that MOVED is corrected. A path that never existed is deleted.** A moved
path has a correct target, so give it one. A named script that exists nowhere has
no target, so the sentence goes — unless the sentence records a known GAP, and
then the gap moves to a tracked item BEFORE the comment goes.

**A cross-reference that helps a reader NAVIGATE still stands.** "The frame
layout is also computed in `machine.nim`" earns its place and stays, provided it
asserts no exclusivity and no sequence. What goes is ONLY, FIRST, NEXT, and
"does not name": those are the falsifiable forms, and that difference is the
whole of the rule.

**An invariant with no mechanism is a comment.** If a property must hold, make
something go red when it stops holding. If no portable mechanism exists, say so
once at the site and record the acceptance — do not let a good comment stand in
for a check.

### Scope: code we authored

This repository is original work, so the rule applies throughout. Repair a
comment when you change the line the comment describes.

**A sweep is permitted only when the sweep carries a mechanical proof that the
change is comment-only.** Strip the comments from the pre-change version of a
file. Strip the comments from the post-change version of the same file. The two
stripped outputs must be byte-identical. Produce that proof per file.

**Calibrate the stripper before you trust the stripper.** Delete a declaration
on purpose, and show that the stripper reports the file as changed. Change an
identifier on purpose, and show that the stripper reports the file as changed.
Put a comment marker inside a string literal, and show that the stripper leaves
that line intact. A stripper whose negative controls have never fired is a
claim, not a mechanism.

**Calibrate at the nesting depth the file uses.** `tests/tests_cpu.cmake` holds
complete CMake driver scripts inside `[==[ ]==]` bracket arguments. A bracket
argument is a string literal to the outer file, so a correct single-level
stripper reports `tests/tests_cpu.cmake` as changed. A proof over that file
needs a stripper that recurses into bracket arguments. Plant the negative
controls inside a bracket argument, not only outside one.

**A Python docstring is a string expression, not a comment.** A comment-only
proof therefore reports a docstring edit as a change. A sweep may still edit a
docstring that carries a forbidden claim, but only with three extra proofs.
Show a token-level diff where no non-comment, non-string token differs, and name
every string token that does. Show that `__doc__` has no consumer, because a
program that prints its own docstring changes behaviour when the docstring
changes. Show that any generated output is byte-identical. Without all three,
leave the docstring alone.

**Calibrate the docstring case too.** Anchor a positive control on a real
comment token chosen by the language's own tokenizer, not by a text search. A
search finds markdown headings inside docstrings and reports a broken control as
a broken stripper. Exclude the shebang: a tokenizer calls `#!` a comment, and
removing it changes how the file runs.

**The test suite must pass after the sweep, at the established count.**

**Without that proof the earlier rule stands.** Repair a comment when you change
the line the comment describes. Change nothing else.

## Gotchas

- **USE THE GDB DEBUGGER EARLY AND OFTEN for anything the MCF5307 stub can
  reach.** This repo ships the stub and the G2 harness exposes it as
  `g2TestConsole --gdb` (see `gearmulator/AGENTS.md`, "Debugging the MCF5307
  with GDB"). For any runtime question about firmware execution — is this
  routine reached, who writes this address, what do the registers hold — a
  breakpoint or watchpoint is the FIRST tool to reach for, before static
  disassembly and before adding probe scaffolds to test files. Static analysis
  enumerates candidate paths; the debugger tells you which one ran. Reserve
  scaffolds for what the stub cannot reach (DSP-side state, whole-run
  statistics). When dispatching a subagent on firmware work, state this in the
  dispatch prompt explicitly — an agent that defaults to print-probes and
  disassembly wastes the instrument this project already built.
- **FOR STATIC STRUCTURE QUESTIONS, USE THE GHIDRA DECOMPILER** — full setup,
  working recipe, and the decompile-vs-breakpoint decision table are in
  `nmg2-artifacts/AGENTS.md` §0.1 (project at `/tmp/ghidra_nmg2`, language
  `68000:BE:32:Coldfire`, base address `0x30000400`; Java scripts only —
  Ghidra 12 dropped Python). Decompile answers "what does this code do / who
  calls it"; the debugger answers "did it run". Decompile to plan breakpoints,
  break to confirm; neither alone is evidence.
- A build that succeeds is not a check. Verify the artifact a step should have
  produced, not the exit status. A stale binary left by a failed compile makes a
  test runner report a pass that describes code which no longer exists.
- `git grep` skips untracked files. Use `grep -r`, `rg`, or `git grep
  --untracked` before claiming something appears nowhere, and name the tool
  beside the claim.

## Corrections

**The sweep rule was amended.** The rule under "Scope: code we authored" once
forbade a comment sweep outright. The prohibition existed to stop an unverified
bulk edit — a large diff across lines that nothing tests. That risk is real, and
that risk is measurable. A sweep that measures the risk away is not the change
the prohibition was written to stop. The rule now admits a sweep that carries
the comment-only proof, and the rule refuses a sweep without the proof.

A sweep run under the earlier rule removed comment lines from eleven files. That
sweep carried the proof the amended rule now requires. The rule changed to admit
that class of change. The removal stands.

## Related

This library is a component of a Nord Modular G2 emulator, but it holds no
knowledge of that instrument. A program that needs a ColdFire processor can use
it alone. The emulator's implementation plan and its cross-repository rules live
in the `nord-modular-emulator` workspace.
