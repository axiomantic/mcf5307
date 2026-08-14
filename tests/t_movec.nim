## `t_movec` - the `MOVEC` encoding and the control-register map of
## `mcf5307/movec`. Task CPU-11. Design sections 6.1, 6.2 and 6.3.
##
## WHAT THIS SUITE ASSERTS, AND WHY EACH GROUP EXISTS.
##
##   THE ENCODING. `MOVEC` is one opcode word and one extension word. The
##   opcode word is asserted whole rather than under a mask, and two
##   neighbouring line-4 words are asserted NOT to be it. The extension word is
##   asserted field by field with the neighbouring fields set to ones, because
##   the failure this catches is a field that reads its neighbour's bits: a
##   control field taken as the low 16 bits rather than the low 12 would carry
##   the A/D bit and the source register into the register number.
##
##   THE PRIVILEGE. `MOVEC` is supervisor-only. The status register is asserted
##   with the interrupt mask both set and clear on each side of the S-bit, so
##   that a test of the wrong bit is red rather than green by coincidence.
##
##   THE REGISTER NUMBERS. This is the group the task exists for.
##   `AGENTS.md` section 4.2 gives the complete set the firmware writes and
##   each one has its own case. ACR1 has its own case beside them: the firmware
##   does not write it and the part implements it, so a map that answers only
##   the numbers the firmware uses would pass every other case here.
##
##   THE ALIASED NUMBERS. `0x004`, `0x005` and `0x800` are the numbers a 68k
##   decoder reads differently, and they are asserted through
##   `movecControlField` from a whole extension word rather than from a bare
##   register number. That composition is the claim the identity cases above do
##   not make: it is the field extraction and the map agreeing, which is the
##   path a real instruction takes.
##
## WHERE THE EXPECTED VALUES COME FROM. They are read from the two manuals as
## page images, at the folios `src/mcf5307/movec.nim` names beside each
## constant. The markdown transcription under `MCF5307UM-md/` is not a source
## for any value here.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import mcf5307/movec
import mcf5307/machine

var failures: seq[string]
import ./case_sites

var passCount = 0

proc checkImpl[T](site: int; got: T; want: T; label: string) =
  if got == want:
    echo "PASSED  ", label, " = ", want
    inc passCount
    executedSites.add(site)
  else:
    echo "FAILED  ", label, ": expected ", want, ", got ", got
    failures.add(label)
    executedSites.add(site)

template check(got: untyped; want: untyped; label: string) =
  ## THE CALL SITE IS RECORDED TWICE - once at COMPILE TIME into
  ## `declaredSites` by the `static` below, and once at RUN TIME into
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, got, want, label)

# ---------------------------------------------------------------------------
# The opcode word. CFPRM Rev. 3 folio 8-13 prints the sixteen bits
# `0100 1110 0111 1011` over the instruction format, which is `0x4E7B`.
#
# THE TWO NEGATIVE CASES ARE NOT DECORATION. `0x4E7A` is the word
# `tests/t_control.nim` asserts is illegal on this part, and `0x4E73` is `RTE`,
# which `decode.nim` already answers. A recogniser written as a mask over
# line 4 rather than as an equality claims both of them.

check(isMovec(0x4E7B'u16),  true, "isMovec(0x4E7B)")
check(isMovec(0x4E7A'u16), false, "isMovec(0x4E7A) - not MOVEC")
check(isMovec(0x4E73'u16), false, "isMovec(0x4E73) - RTE is not MOVEC")

# ---------------------------------------------------------------------------
# The extension word fields. CFPRM folio 8-13: bit 15 is A/D, bits 14 to 12 are
# the source register Ry, and bits 11 to 0 are the control register Rc.
#
# EACH FIELD IS READ TWICE, once with its neighbours clear and once with them
# set, so that a field taken one bit too wide is red rather than green.

check(movecControlField(0x0801'u16), 0x801'u16,
    "movecControlField(0x0801) - neighbours clear")
check(movecControlField(0xF801'u16), 0x801'u16,
    "movecControlField(0xF801) - A/D and Ry excluded")

check(movecSourceIsAddressRegister(0x0801'u16), false,
    "movecSourceIsAddressRegister(0x0801) - a data register")
check(movecSourceIsAddressRegister(0x8801'u16), true,
    "movecSourceIsAddressRegister(0x8801) - an address register")

check(movecSourceRegister(0x0801'u16), 0'u8,
    "movecSourceRegister(0x0801)")
check(movecSourceRegister(0x7801'u16), 7'u8,
    "movecSourceRegister(0x7801)")
check(movecSourceRegister(0x8801'u16), 0'u8,
    "movecSourceRegister(0x8801) - the A/D bit is not part of Ry")

# ---------------------------------------------------------------------------
# The privilege. CFPRM folio 8-13 gives the operation as "If Supervisor State
# Then Ry -> Rc Else Privilege Violation Exception".
#
# THE INTERRUPT MASK IS SET IN ONE CASE OF EACH PAIR. A predicate that read the
# wrong status-register bit would answer both of the S-clear cases correctly by
# accident if every other bit were clear in both.

check(movecPrivilegeViolation(0x0000'u32), true,
    "movecPrivilegeViolation(user state)")
check(movecPrivilegeViolation(0x0700'u32), true,
    "movecPrivilegeViolation(user state, interrupt mask set)")
check(movecPrivilegeViolation(srSupervisor), false,
    "movecPrivilegeViolation(supervisor state)")
check(movecPrivilegeViolation(0x2700'u32), false,
    "movecPrivilegeViolation(supervisor state, interrupt mask set)")

# ---------------------------------------------------------------------------
# The control registers the firmware writes. `AGENTS.md` section 4.2 is the
# complete list and it is the authority for which numbers appear here; the two
# manuals are the authority for what each number names.

check(controlRegisterFor(0x002'u16), crCacr,    "0x002 is CACR")
check(controlRegisterFor(0x004'u16), crAcr0,    "0x004 is ACR0")
check(controlRegisterFor(0x801'u16), crVbr,     "0x801 is VBR")
check(controlRegisterFor(0xC04'u16), crRambar0, "0xC04 is RAMBAR0")
check(controlRegisterFor(0xC05'u16), crRambar1, "0xC05 is RAMBAR1")
check(controlRegisterFor(0xC0F'u16), crMbar,    "0xC0F is MBAR")

# ---------------------------------------------------------------------------
# ACR1. The firmware does not write it and this part implements it: MCF5307
# User's Manual Table B-2, Appendix folio B-5, gives `CPU @ $005` the name
# ACR1. A map built from the firmware's own set alone would answer every case
# above and fail this one.

check(controlRegisterFor(0x005'u16), crAcr1, "0x005 is ACR1")

# ---------------------------------------------------------------------------
# The aliased numbers, read through the extension word. These are the numbers
# a decoder that kept the 68k map answers with a different register, and the
# design calls the collision the number one hazard.
#
#   0x004 and 0x005 are ITT0 and ITT1 on the 68040 and ACR0 and ACR1 here.
#   0x800 is USP on the 68040 and NAMES NO REGISTER OF THIS PART.

check(controlRegisterFor(movecControlField(0x0004'u16)), crAcr0,
    "extension word 0x0004 selects ACR0 and not ITT0")
check(controlRegisterFor(movecControlField(0x0005'u16)), crAcr1,
    "extension word 0x0005 selects ACR1 and not ITT1")
check(controlRegisterFor(movecControlField(0x0800'u16)), crUnimplemented,
    "extension word 0x0800 selects no register and is not USP")

# ---------------------------------------------------------------------------
# A number the ColdFire family assigns and this part does not implement. CFPRM
# Table 8-3, folio 8-13, gives `0x006` to ACR2; MCF5307 User's Manual Table
# B-2 does not carry it. RAMBAR1 is the one number this core accepts on the
# family table alone, and without this case a map that accepted every family
# number would look the same as one that accepted the part's own.

check(controlRegisterFor(0x006'u16), crUnimplemented,
    "0x006 is ACR2 on the family and is not implemented here")

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_movec", declaredCaseSites)
echo caseSiteLine("executed", "t_movec", executedSites)
echo caseSiteLine("off-green-path", "t_movec", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_movec: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_movec: ", passCount, " cases passed"
