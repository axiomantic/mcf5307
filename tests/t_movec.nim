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
import mcf5307/cpu
import mcf5307/decode_types

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

# ---------------------------------------------------------------------------
# THE INSTRUCTION DRIVEN THROUGH THE SHIPPED PATH.
#
# EVERY CASE ABOVE IS A FUNCTION OF ITS ARGUMENTS AND NOT ONE OF THEM REACHES A
# MACHINE. A suite that calls `controlRegisterFor` directly answers the same way
# whether or not any instruction can reach it, so a full pass of those cases
# alone is consistent with `MOVEC` decoding to nothing and trapping as an
# illegal opcode. The cases below run the encoding through `mcf5307_reset`,
# `mcf5307_set_reg`, `mcf5307_exec` and `mcf5307_get_reg` - four of the calls
# `include/mcf5307.h` publishes - so that the map above is asserted on the path
# a boot loader takes.
#
# THIS SUITE STILL COMPILES THE CORE FROM SOURCE THROUGH `--path:src` AND NEVER
# LINKS `libmcf5307.a`, so it cannot see a module that the entry module's import
# graph fails to reach. `conformance/runner.cpp` is what links the archive.

const
  execBase = 0x100'u32     ## where the instruction words are placed
  stackBase = 0x800'u32
  srSuper = 0x2700'u32     ## supervisor, interrupt mask 7 - the reset value
  srUser = 0x0700'u32      ## USER state with the same mask, so that a wrong
                           ## bit read is red rather than green by coincidence
  dirtyD = 0x12345678'u32
  dirtyA = 0x0BADC0DE'u32
  handlerBase = 0x400'u32  ## where the seeded vector-8 entry points
  memSize = 0x1000

type TestBoard = object
  bytes: array[memSize, uint8]

var board: TestBoard

proc boardWrite(b: var TestBoard; address: uint32; size: int; value: uint32) =
  for i in 0 ..< size:
    b.bytes[int(address) + i] =
      uint8((value shr ((size - 1 - i) * 8)) and 0xFF'u32)

proc boardReadValue(b: TestBoard; address: uint32; size: int): uint32 =
  for i in 0 ..< size:
    result = (result shl 8) or uint32(b.bytes[int(address) + i])

proc bRead(user: pointer; address: uint32; size: cint;
           status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return 0'u32
  status[] = Mcf5307BusStatus.busOk
  boardReadValue(b[], address, int(size))

proc bWrite(user: pointer; address: uint32; size: cint; value: uint32;
            status: ptr Mcf5307BusStatus) {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return
  status[] = Mcf5307BusStatus.busOk
  boardWrite(b[], address, int(size), value)

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

type Outcome = object
  cycles: uint32
    ## `mcf5307_exec(ctx, 1)` SATURATES AT ITS BUDGET, so this is 1 for an
    ## instruction that ran and 0 for one that halted before spending
    ## anything. `cpu.nim`'s header block says why it is not a cycle count.
  fault: bool
  halted: bool
  d0: uint32
  a0: uint32
  sr: uint32
  pc: uint32
  a7: uint32

proc runIns(words: openArray[uint16]; sr: uint32;
            mem: seq[(uint32, uint32)] = @[]): Outcome =
  ## Place `words` at `execBase`, seed d0 and a0, run ONE `mcf5307_exec`, and
  ## report the whole machine state.
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  for i in 0 ..< words.len:
    boardWrite(board, execBase + 2'u32 * uint32(i), 2, uint32(words[i]))
  for (address, value) in mem:
    boardWrite(board, address, 4, value)

  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, stackBase, execBase)
  discard mcf5307_set_reg(ctx, 0, dirtyD)
  discard mcf5307_set_reg(ctx, 8, dirtyA)
  # The status register is set LAST, because `mcf5307_reset` writes it and an
  # earlier write would be overwritten - which would run every user-state case
  # in supervisor state and pass.
  discard mcf5307_set_reg(ctx, 16, sr)

  result.cycles = mcf5307_exec(ctx, 1'u32)
  result.fault = ctx.fault
  result.halted = ctx.halted
  result.d0 = mcf5307_get_reg(ctx, 0)
  result.a0 = mcf5307_get_reg(ctx, 8)
  result.sr = mcf5307_get_reg(ctx, 16)
  result.pc = mcf5307_get_reg(ctx, 17)
  result.a7 = mcf5307_get_reg(ctx, 15)

proc ranAndConsumedBothWords(o: Outcome): auto =
  ## The shape every ACCEPTED `MOVEC` must produce. The program counter is the
  ## discriminating field: `MOVEC` is TWO words, so a core that consumed only
  ## the opcode word would leave the pc at `execBase + 2` and decode the
  ## extension word as the next instruction.
  (cycles: o.cycles, fault: o.fault, halted: o.halted, pc: o.pc,
   d0: o.d0, a0: o.a0, sr: o.sr, a7: o.a7)

const accepted = (cycles: 1'u32, fault: false, halted: false,
                  pc: execBase + 4'u32, d0: dirtyD, a0: dirtyA,
                  sr: srSuper, a7: stackBase)
  ## NOTHING ARCHITECTURAL CHANGES. The control registers this part carries are
  ## not modelled by this core, so an accepted `MOVEC` advances the program
  ## counter and touches no register the ABI can read. `src/mcf5307/movec.nim`
  ## states the limitation and why it is not this task's to remove.

# The six numbers `AGENTS.md` section 4.2 records the firmware writing, plus
# ACR1, each driven as a whole instruction rather than as a bare register
# number. THE PAIR OF LISTS IS THE POINT: the identity cases above assert what
# the map says, and these assert that the machine consults it.

check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0002'u16], srSuper)),
    accepted, "movec %d0,CACR (0x002) executes")
check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0004'u16], srSuper)),
    accepted, "movec %d0,ACR0 (0x004) executes")
check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0005'u16], srSuper)),
    accepted, "movec %d0,ACR1 (0x005) executes")
check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0801'u16], srSuper)),
    accepted, "movec %d0,VBR (0x801) executes")
check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0C05'u16], srSuper)),
    accepted, "movec %d0,RAMBAR1 (0xC05) executes")
check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0C0F'u16], srSuper)),
    accepted, "movec %d0,MBAR (0xC0F) executes")

# THE A/D BIT IS EXERCISED ONCE, AND IT IS EXERCISED THROUGH THE MACHINE. The
# extension word `0x8C04` names ADDRESS register 0 as the source. The identity
# cases above assert that `movecSourceIsAddressRegister` reads bit 15; this
# asserts that an instruction carrying that bit still executes rather than
# being refused as a malformed encoding.

check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x8C04'u16], srSuper)),
    accepted, "movec %a0,RAMBAR0 (0xC04) executes with A/D set")

# A NUMBER THIS PART DOES NOT CARRY HALTS THE CORE, AND IT HALTS WITHOUT A
# FAULT. CFPRM folio 8-13: "Attempted access to undefined or unimplemented
# control register space produces undefined results." The encoding is a valid
# `MOVEC` and only the destination is absent from this part, which is the
# `opExg`/`opTas`/`opNbcd` shape `cpu.nim` already states: `halted` set and
# `fault` clear. A core that accepted these instead would run on with a
# register write that reached nothing, which is the permissive failure design
# section 17 row 7.10 names.

const refused = (cycles: 0'u32, fault: false, halted: true,
                 pc: execBase + 4'u32, d0: dirtyD, a0: dirtyA,
                 sr: srSuper, a7: stackBase)

check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0006'u16], srSuper)),
    refused, "movec %d0,0x006 halts: ACR2 is not on this part")

# `0x800` IS THE MEASUREMENT THIS TASK ALREADY MADE AND THIS CASE PINS IT TO
# THE MACHINE. CFPRM Table 8-3's processor group, folio 8-14, runs VBR `0x801`
# then PC `0x80F` and assigns NOTHING to `0x800`; MCF5307 User's Manual Table
# B-2, folio B-5, does not carry it either. A fork that restored the 68k
# reading would make this number a register and this case is what goes red.

check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0800'u16], srSuper)),
    refused, "movec %d0,0x800 halts: it names no register of this part")

# THE PRIVILEGE, TAKEN AS AN EXCEPTION AND NOT AS A HALT. CFPRM folio 8-13
# gives the operation as "If Supervisor State Then Ry -> Rc Else Privilege
# Violation Exception", and MCF5307 User's Manual Table 3-1, folio 3-13,
# assigns VECTOR 8 at offset `$020` to "Privilege violation" with a STACKED
# PROGRAM COUNTER column of "Fault" - which that table's own footnote defines
# as "the PC of the instruction that caused the exception". So the stacked
# value is `execBase` and NOT the address after either word: an `RTE` from the
# handler re-executes the whole instruction.

block:
  let o = runIns([0x4E7B'u16, 0x0C0F'u16], srUser,
                 mem = @[(4'u32 * 8'u32, handlerBase)])
  let got = (cycles: o.cycles, fault: o.fault, halted: o.halted, pc: o.pc,
             sr: o.sr, a7: o.a7, d0: o.d0,
             fv: boardReadValue(board, stackBase - 8'u32, 4),
             stackedPc: boardReadValue(board, stackBase - 4'u32, 4))
  # `fv` is FORMAT 4 (A7 was already longword aligned), FS 0 (this is not an
  # access error), VECTOR 8, and the status register AS IT WAS BEFORE the
  # exception changed it. The handler runs with S set and T clear.
  let want = (cycles: 1'u32, fault: false, halted: false, pc: handlerBase,
              sr: 0x2700'u32, a7: stackBase - 8'u32, d0: dirtyD,
              fv: 0x4020_0700'u32,
              stackedPc: execBase)
  check(got, want, "movec in user state takes the vector-8 privilege violation")

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
