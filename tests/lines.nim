## `lines` - the line-A and line-F opcode spaces.
##
## This module classifies and decides nothing: every procedure here is a
## function of one instruction word, so it can be asserted value by value
## without a machine to run. What the core does with a word these predicates
## accept is the executor's decision.
##
## Line-A is not decoded. The part has a MAC unit and this core does not
## model it, so refusing the whole space makes a firmware that reaches a MAC
## instruction fail loudly instead of executing something this core invented.
##
## Line-F is refused rather than accepted and discarded. Line-F on this
## part is cache and debug, both supervisor-only, so a core that accepted and
## discarded would succeed at a supervisor-only instruction executed in user
## state and would report nothing about the cache or the debug write that did
## not happen. Refusing says which of the two the core is.
##
## This core takes no vector for a refused word: it halts and sets its fault
## bit. No constant here names the line-A or line-F vector, because a constant
## no caller reads is a destination that looks like a decision and is not one.
##
## The manuals were read as page images: the MCF5307 User's Manual (1998) and
## the ColdFire Family Programmer's Reference Manual, Rev. 3.

proc opcodeLine(word: uint16): uint16 =
  (word shr 12) and 0xF'u16

proc isLineA*(word: uint16): bool =
  opcodeLine(word) == 0xA'u16

proc isLineF*(word: uint16): bool =
  opcodeLine(word) == 0xF'u16
