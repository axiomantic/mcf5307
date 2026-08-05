# mcf5307

An emulator for the Freescale MCF5307 ColdFire processor, and a model of the
Philips ISP1181 USB device controller.

The core is written in Nim. CMake drives the Nim compiler and gives a static
library and a C header to a C or C++ program.

## Status

Early. This repository holds the build integration and the project policy. The
core is not complete. Do not use it in a product.

## What this repository contains

| Item | Content |
|---|---|
| `src/` | The Nim sources of the core and the ISP1181 model. |
| `include/` | The hand-written public C header. |
| `.nim-version` | The one exact Nim version this project uses. |

## Targets

| Target | Content |
|---|---|
| `mcf5307` | The static library. It holds the core and the ISP1181 model. |
| `mcf5307_tests` | The unit tests. |
| `mcf5307_conformance` | The runner for the generated ColdFire conformance corpus. |

CMake exports `mcf5307::mcf5307` for a program that uses this library.

## Requirements

- CMake 3.20 or later.
- The Nim compiler. The version must agree with `.nim-version`.

The CMake configure step reads `.nim-version`, runs `nim --version`, and stops
with an error if the two versions do not agree. The error message shows both
versions.

## How to build

```
cmake -S . -B build
cmake --build build
ctest --test-dir build
```

## The Nim version policy

1. The project pins one exact Nim version in `.nim-version`.
2. The CMake configure step stops on a version mismatch.
3. A change of the major version is scheduled work. It gets its own branch, its
   own full conformance run, and its own logbook entry.
4. A change of the minor version is permitted after the conformance corpus
   passes.

## Build flags

The Nim compile step uses `-d:release` and `--panics:on`. It does not use
`--checks:off`, and it does not use `-d:danger`. Do not add them. The run-time
checks stay in the release build on purpose: a check that stops the process is
better than a check that lets the library give a wrong result.

## Relation to other projects

This library is a component of a Nord Modular G2 emulator, but it holds no
knowledge of that instrument. It is a general MCF5307 core, and a program that
needs a ColdFire processor can use it alone.

## Licence

The licence is not yet set. This repository carries no `LICENSE` file until the
operator selects one.
