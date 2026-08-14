## `t_checks_on` - the run-time checks stay compiled in. Task CPU-20 creates
## this file. Design sections 5.6 and 17 row 7.26.
##
## `-d:release` ALONE KEEPS THE BOUND CHECK COMPILED IN. `--checks:off`
## removes it, and the same program then reads outside the array, returns a
## wrong value and exits 0. A wrong answer with exit status 0 inside a CPU
## core is the one outcome this design refuses, so the flag set that governs
## the library is asserted here rather than described in a comment.
##
## THE TWO FAULT CLASSES GET DIFFERENT RESPONSES AND THIS FILE DRIVES ONE OF
## THEM. A firmware fault - the emulated firmware reads unmapped space - goes
## through the decode path's OWN EXPLICIT RANGE TEST and is reported as
## `MCF5307_BUS_UNMAPPED` through the bus-status out-parameter. No language
## check fires there and nothing ends the process. An emulator defect - this
## project's own Nim code indexes outside an array - is what this file drives,
## and the language check is what ends the process. The decode path never uses
## a language check as its reporting mechanism.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import std/[os, strutils]

# The scratch region. THE VALUES ARE DISTINCT, so that a read
# of the wrong element cannot return the value the right element holds.
var scratch: array[4, uint32] = [10'u32, 20'u32, 30'u32, 40'u32]

when isMainModule:
  # THE INDEX COMES FROM THE COMMAND LINE AND IS NEVER A LITERAL. A literal
  # out-of-range index is caught when this file is compiled, and a
  # compile-time error is a different mechanism from the run-time check this
  # program exists to observe.
  let index = parseInt(paramStr(1))
  echo "scratch[", index, "] = ", scratch[index]
