## `t_checks_on` - the run-time checks stay compiled in.
##
## `-d:release` alone keeps the bound check compiled in. `--checks:off` removes
## it, and the same program then reads outside the array, returns a wrong value
## and exits 0.
##
## The two fault classes get different responses and this file drives one of
## them. A firmware fault - the emulated firmware reads unmapped space - goes
## through the decode path's own explicit range test and is reported as
## `MCF5307_BUS_UNMAPPED` through the bus-status out-parameter. No language
## check fires there and nothing ends the process. An emulator defect - this
## project's own Nim code indexes outside an array - is what this file drives,
## and the language check is what ends the process. The decode path never uses
## a language check as its reporting mechanism.

import std/[os, strutils]

# The scratch region. Four elements and four distinct values, so that a read
# of the wrong element cannot return the value the right element holds.
var scratch: array[4, uint32] = [10'u32, 20'u32, 30'u32, 40'u32]

when isMainModule:
  # The index comes from the command line and is never a literal. A literal
  # out-of-range index is caught when this file is compiled, and a
  # compile-time error is a different mechanism from the run-time check this
  # program exists to observe.
  let index = parseInt(paramStr(1))
  echo "scratch[", index, "] = ", scratch[index]
