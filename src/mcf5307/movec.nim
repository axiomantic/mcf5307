## `movec` - the `MOVEC` encoding, the privilege rule, the control-register map
## and the group's executor. Task CPU-11. Design sections 6.1, 6.2 and 6.3.
##
## THE MAP AND THE EXECUTOR ARE BOTH HERE, AND THE SPLIT INSIDE THE FILE IS
## WHAT MATTERS. Everything above `movecFamily` is a function of the
## instruction stream and of the status register, so it can be asserted value
## by value without a machine to run. `movecFamily` is the one procedure that
## needs a context, and it is what makes every predicate above REACHABLE from
## `mcf5307_exec`.
##
## THE ROUTE INTO THE LIBRARY IS A BUILD FACT RATHER THAN A STYLE CHOICE.
## `cmake/Nim.cmake` step 3 takes the library's compilation units from the
## `compile` array of Nim's own cache,
## which holds what the entry module's import graph REACHED. A module this
## graph does not reach is never compiled, never enters the archive, and its
## procedures cannot be called through `mcf5307_exec` - while a suite built
## with `--path:src` still compiles it from source and passes. So a predicate
## here is only as reachable as `cpu.nim`'s arm that calls it.
##
## NOTHING HERE WRITES A CONTROL REGISTER, AND THAT IS A LIMITATION RATHER
## THAN AN OVERSIGHT. A control register this core kept would be context
## state, and the task that owns the context type is the task that adds a
## field to it; the value the instruction carries is therefore discarded. The
## one consequence a reader must not miss: `machine.nim`'s `takeException`
## still bases the vector table at zero, so a `MOVEC` to VBR is accepted and
## does not move it.
##
## MBAR IS WHY THIS INSTRUCTION IS FIRST. Design section 6.2: MBAR is reachable
## only through `MOVEC`, so no peripheral is visible until software programs
## it, and the boot loader programs it before the operating system runs.
##
## THE MANUALS WERE READ AS PAGE IMAGES. Every number below carries the folio
## it came from. The markdown transcription under `MCF5307UM-md/` is not a
## source for any of them.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The encoding,
## the register numbers and the privilege rule are facts about Motorola
## silicon, from the MCF5307 User's Manual (1998) and the ColdFire Family
## Programmer's Reference Manual, Rev. 3.

import mcf5307/decode_types
import mcf5307/machine

# CFPRM Rev. 3, `MOVEC`, folio 8-13, prints the sixteen bits of the opcode word
# as `0100 1110 0111 1011`, then a second word carrying A/D at bit 15, the
# source register Ry at bits 14 to 12 and the control register Rc at bits 11 to
# 0. THE OPCODE WORD IS AN EQUALITY AND NOT A MASK: line 4 is dense here, and
# `0x4E7A` is a word this part must refuse rather than a `MOVEC` variant.

const movecOpcodeWord* = 0x4E7B'u16

proc isMovec*(word: uint16): bool =
  word == movecOpcodeWord

proc movecControlField*(ext: uint16): uint16 =
  ## The control register number, Rc. TWELVE BITS AND NOT SIXTEEN: the top four
  ## carry A/D and Ry, and a wider read moves the register number by whichever
  ## register the instruction happens to name.
  ext and 0x0FFF'u16

proc movecSourceIsAddressRegister*(ext: uint16): bool =
  (ext and 0x8000'u16) != 0'u16

proc movecSourceRegister*(ext: uint16): uint8 =
  uint8((ext shr 12) and 0x7'u16)

proc movecPrivilegeViolation*(sr: uint32): bool =
  ## CFPRM folio 8-13 gives the operation as "If Supervisor State Then Ry -> Rc
  ## Else Privilege Violation Exception".
  ##
  ## THE S-BIT IS `machine.nim`'s FACT AND IS READ FROM THERE. Restating the
  ## bit position here would put one fact in two files, where a later change to
  ## either leaves the other saying something the machine does not do.
  (sr and srSupervisor) == 0'u32

type
  ControlRegister* {.pure.} = enum
    ## The control registers THIS PART implements, and one member for every
    ## other number.
    ##
    ## THE SET IS THE PART'S AND NOT THE FAMILY'S. CFPRM Table 8-3, folios
    ## 8-13 and 8-14, assigns numbers the MCF5307 does not carry - ASID
    ## `0x003`, ACR2 `0x006`, ACR3 `0x007`, MMUBAR `0x008`, PC `0x80F`, the two
    ## ROMBARs, MPCR, EDRAMBAR, SECMBAR and the permutation registers at
    ## `0xD0x`. MCF5307 User's Manual Table B-2, Appendix folio B-5, is this
    ## part's own map. A member for a register the part does not have would be
    ## a destination nothing can reach and a decode that looks successful.
    crUnimplemented
      ## CFPRM folio 8-13: "Attempted access to undefined or unimplemented
      ## control register space produces undefined results." What the core does
      ## with such a write is the executor's decision and no plan row settles
      ## it, so this module classifies and decides nothing.
    crCacr, crAcr0, crAcr1, crVbr, crRambar0, crRambar1, crMbar

proc controlRegisterFor*(rc: uint16): ControlRegister =
  ## DECODE AGAINST THE COLDFIRE MAP ONLY. Design section 6.1 calls the 68k
  ## collision the number one hazard, and it is silent in both directions:
  ## `0x004` and `0x005` are ACR0 and ACR1 here and ITT0 and ITT1 on the 68040,
  ## and `0x800` is USP on the 68040 and NAMES NO REGISTER OF THIS PART.
  ##
  ## `0x800` IS ABSENT FROM BOTH MANUALS AND THAT IS THE MEASUREMENT, NOT AN
  ## OMISSION. CFPRM Table 8-3's processor-miscellaneous group, folio 8-14,
  ## runs VBR `0x801` then PC `0x80F` and assigns nothing to `0x800`; Table B-2
  ## does not carry it either. The register a 68k reading would put there has
  ## no home on this part in any case: design section 6.1 gives this core ONE
  ## A7 with no supervisor and user split, and CFPRM Table 1-6, folio 1-11,
  ## makes OTHER_A7 conditional on ISA_A+, which this part is not.
  ##
  ## RAMBAR1 IS THE ONE ENTRY TABLE B-2 DOES NOT CARRY, and design section 6.3
  ## decides it: the firmware writes `0xC05` in genuine code, CFPRM folio 8-14
  ## assigns that number to RAM base address register 1, and the core accepts
  ## the write rather than treating the anomaly as a decode error. Table B-2
  ## names `0xC04` RAMBAR where CFPRM names it RAMBAR0; the two are one
  ## register and the family spelling is used here because it distinguishes.
  case rc
  of 0x002'u16: crCacr      # UM Table B-2 folio B-5; CFPRM Table 8-3 folio 8-13
  of 0x004'u16: crAcr0      # UM Table B-2 folio B-5; CFPRM Table 8-3 folio 8-13
  of 0x005'u16: crAcr1      # UM Table B-2 folio B-5; CFPRM Table 8-3 folio 8-13
  of 0x801'u16: crVbr       # UM Table B-2 folio B-5; CFPRM Table 8-3 folio 8-14
  of 0xC04'u16: crRambar0   # UM Table B-2 folio B-5; CFPRM Table 8-3 folio 8-14
  of 0xC05'u16: crRambar1   # CFPRM Table 8-3 folio 8-14; design section 6.3
  of 0xC0F'u16: crMbar      # UM Table B-2 folio B-5; CFPRM Table 8-3 folio 8-14
  else: crUnimplemented

# ---------------------------------------------------------------------------
# The executor.

const
  vecPrivilegeViolation = 8'u8
    ## MCF5307 User's Manual Table 3-1, "Exception Vector Assignments", folio
    ## 3-13: vector 8, at vector offset `$020`, is "Privilege violation".

  movecExecuteCycles = 9'u32
    ## MCF5307 User's Manual Table 3-14, "Miscellaneous Instruction Execution
    ## Times", folio 3-29, times `movec Ry,Rc` at `11(0/1)` WHOLE. `cpu.nim`
    ## adds its own fetch cost to this return, and the pair sums to that 11.
    ## The decomposition is this core's and not the manual's, exactly as the
    ## block at the head of `cpu.nim` states for every other return.

proc movecFamily*(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one `MOVEC`. Returns the cycles the execution pipe spent, 0 for an
  ## instruction that did not run.
  ##
  ## THE PRIVILEGE IS TESTED BEFORE THE EXTENSION WORD IS FETCHED, AND THE
  ## ORDER IS A DECISION THE MANUALS DO NOT SETTLE. CFPRM folio 8-13 states
  ## the operation as a conditional whose first test is supervisor state, and
  ## `fetchExt` can itself take an ACCESS ERROR - so fetching first would let
  ## an instruction the core is about to refuse for privilege report the wrong
  ## exception instead. The stacked program counter is the same either way,
  ## so an `RTE` from the handler re-executes the whole instruction and
  ## re-reads the word this path did not.
  if movecPrivilegeViolation(ctx.sr):
    # THE STACKED PROGRAM COUNTER IS THIS INSTRUCTION AND NOT THE NEXT ONE.
    # Table 3-1's STACKED PROGRAM COUNTER column reads "Fault" for vector 8,
    # which its own footnote defines as "the PC of the instruction that caused
    # the exception". `step` has already advanced the pc past the opcode word,
    # so the faulting address is one word back. `execTrap` in `control.nim` is
    # the other side of this distinction: its vectors read "Next" and it
    # stacks `ctx.pc` unchanged.
    takeException(ctx, vecPrivilegeViolation, ctx.pc - insWordBytes)
    return 0'u32
  let ext = fetchExt(ctx)
  if ctx.halted:
    return 0'u32
  if controlRegisterFor(movecControlField(ext)) == crUnimplemented:
    # CFPRM folio 8-13: "Attempted access to undefined or unimplemented
    # control register space produces undefined results." This core HALTS
    # rather than running on, which is the posture `cpu.nim`'s
    # `opExg`/`opTas`/`opNbcd` arm already takes for the same shape - a valid
    # encoding whose semantics this core does not carry - and `fault` stays
    # clear for that same reason. A core that accepted the write instead would
    # let firmware configure a register that does not exist and report
    # nothing, which is the permissive failure design section 17 row 7.10
    # names.
    ctx.halted = true
    return 0'u32
  movecExecuteCycles
