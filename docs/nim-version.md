# The Nim version policy

## The pin

| What | Value | Where |
|---|---|---|
| Pinned Nim version | **2.2.10** | `.nim-version` |
| Compiler that answers today | `Nim Compiler Version 2.2.10 [MacOSX: arm64]` | `nim --version` |

`.nim-version` holds one exact version and nothing else. It is a record of the
pin. **It does not install or select a compiler.**

## What selects the compiler, and why this document exists

The compiler on `PATH` comes from `mise`, and `mise` reads the version from
`~/.config/mise/config.toml`, which is **machine-wide**:

```
$ mise ls nim
nim  2.2.6
nim  2.2.10  ~/.config/mise/config.toml  2.2.10
$ mise settings get idiomatic_version_file_enable_tools
[]
```

The empty tool list is the point: `mise` reads **no** idiomatic version file,
so it never reads `.nim-version`. The repository records a pin; the machine
supplies a compiler; the two are joined only by the check below.

A change to the machine-wide `mise` pin therefore moves **every** Nim project
on the machine at once. This repository does not stop that change. It detects
it.

## Rule 1 — Pin one exact version

`.nim-version` holds one exact `MAJOR.MINOR.PATCH` version. No range. No
`latest`.

Reason: the emulator core is compiled to C and linked into a C++ build. A
patch-level change in the Nim code generator changes the emitted C. An exact
pin makes a build reproducible from the repository alone.

## Rule 2 — The CMake integration fails configure on a mismatch

`cmake/Nim.cmake` step 1 reads `.nim-version`, runs `nim --version`, takes the
version from the **first line** of the output, and calls `message(FATAL_ERROR)`
when the two differ. The message prints both versions, the file that holds the
pin, and the compiler that answered.

This is the only mechanism that connects the repository pin to the machine
compiler. Without it, a machine-wide pin move is silent.

`.nim-version` is a declared configure dependency (`CMAKE_CONFIGURE_DEPENDS` in
`cmake/Nim.cmake`), so an edit to it re-runs the configure step.

## Rule 3 — A major-version migration is scheduled work

A major-version move (2.x to 3.x) needs:

- its own branch,
- its own full conformance run,
- its own logbook entry.

Reason, and it is measured rather than assumed: both known audio-Nim
precedents broke at a major version. Omni pins Nim 1.6.0 and never crossed the
Nim 2 boundary. `elijahr/june` does not build on Nim 2.

## Rule 4 — A minor bump is allowed after the conformance corpus passes

Run the conformance corpus first. Move the pin in the same change that runs
it.

The 2.2.6 to 2.2.10 move (commit `73a61cf`) followed this rule: the bound-check
measurement was re-run on 2.2.10 before the pin moved, and all three cases were
unchanged.

## What is known to break

### The `--app:lib` latch — CONFIRMED PRESENT on 2.2.10

Nim treats `--app:lib` from a configuration file as a latch. A later
command-line `--app:console` does **not** override it.

Measured on 2026-08-26 with Nim 2.2.10, outside this repository:

| Condition | Command | Result of `file` on the output |
|---|---|---|
| `nim.cfg` holds `--app:lib` | `nim c --app:console -o:probe_out probe.nim` | `Mach-O 64-bit dynamically linked shared library arm64` |
| No `nim.cfg` (control) | same command | `Mach-O 64-bit executable arm64`, and it runs |

The control run proves the probe can tell the two apart. The behaviour was
recorded at 2.2.6 and it is unchanged at 2.2.10.

**This repository is not affected.** `rg -n 'app:lib|app=lib|appType|--app'`
over the tree, excluding `build/`, returns zero hits, while `rg -n
'compileOnly'` over the same tree returns hits. The absence is measured, not
assumed.

The affected consumer is a different project (`sqorbit` /
`my-audio-plugins`), whose build carries a workaround built around this
latch. Whether that workaround is still correct is **UNVERIFIED** — this
measurement shows the latch still exists, not that the workaround still fits
it. Reading that repository's build files and running its build would settle
it.

### Bound checks — no change at 2.2.10

Re-measured before commit `73a61cf`. `-d:release --panics:on` keeps the bound
check and exits 1 on `IndexDefect`; `--checks:off` removes it and returns a
wrong value with exit 0; `{.push boundChecks: on.}` re-enables the check for
one region. **This entry is carried from that commit's record and was not
re-run today.** Re-running the three cases would settle it.

### Everything else — nothing known

No other breakage is known at this pin. This statement is falsifiable: a
build or conformance failure attributable to the compiler version refutes it,
and the entry is then moved into the list above.

## Unverified

| Claim | What would settle it |
|---|---|
| The `sqorbit` `--app:lib` workaround is still correct at 2.2.10 | Read that repository's build files and run its build |
| Bound-check behaviour is unchanged at 2.2.10 | Re-run the three cases recorded at commit `73a61cf` |
| No other Nim-version breakage exists | A full conformance run at this pin |

## Related

- `docs/toolchain.md` — the m68k cross-assembler pin, kept beside this one.
- `cmake/Nim.cmake` — the check that enforces rule 2.
