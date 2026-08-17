## `movec` - the `MOVEC` encoding, the privilege rule, the control-register map
## and the group's executor.
##
## Everything above `movecFamily` is a function of the instruction stream and of
## the status register, so it can be asserted value by value without a machine to
## run. `movecFamily` is the one procedure that needs a context, and it is what
## makes every predicate above reachable from `mcf5307_exec`.
##
## `cmake/Nim.cmake` takes the library's compilation units from the `compile`
## array of Nim's own cache, which holds what the entry module's import graph
## reached. A module this graph does not reach is never compiled, never enters
## the archive, and its procedures cannot be called through `mcf5307_exec` -
## while a suite built with `--path:src` still compiles it from source and
## passes. So a predicate here is only as reachable as `cpu.nim`'s arm that
## calls it.
##
## Nothing here writes a control register: the value the instruction carries is
## discarded. The one consequence a reader must not miss is that
## `machine.nim`'s `takeException` still bases the vector table at zero, so a
## `MOVEC` to VBR is accepted and does not move it.
##
## MBAR is reachable only through `MOVEC`, so no peripheral is visible until
## software programs it, and the boot loader programs it before the operating
## system runs.
##
## The manuals were read as page images and every number below carries the folio
## it came from. The markdown transcription under `MCF5307UM-md/` is not a source
## for any of them.

import mcf5307/decode_types
import mcf5307/machine

# CFPRM Rev. 3, `MOVEC`, folio 8-13, prints the sixteen bits of the opcode word
# as `0100 1110 0111 1011`, then a second word carrying A/D at bit 15, the
# source register Ry at bits 14 to 12 and the control register Rc at bits 11 to
# 0. The opcode word is an equality and not a mask: line 4 is dense here, and
# `0x4E7A` is a word this part must refuse rather than a `MOVEC` variant.

const movecOpcodeWord* = 0x4E7B'u16

proc isMovec*(word: uint16): bool =
  word == movecOpcodeWord

proc movecControlField*(ext: uint16): uint16 =
  ## The control register number, Rc. Twelve bits and not sixteen: the top four
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
  ## The S-bit position is `machine.nim`'s fact and is read from there. Restating
  ## it here would put one fact in two files, where a later change to either
  ## leaves the other saying something the machine does not do.
  (sr and srSupervisor) == 0'u32

type
  ControlRegister* {.pure.} = enum
    ## The control registers this part implements, and one member for every
    ## other number.
    ##
    ## The set is the part's and not the family's. CFPRM Table 8-3, folios
    ## 8-13 and 8-14, assigns numbers the MCF5307 does not carry - ASID
    ## `0x003`, ACR2 `0x006`, ACR3 `0x007`, MMUBAR `0x008`, PC `0x80F`, the two
    ## ROMBARs, MPCR, EDRAMBAR, SECMBAR and the permutation registers at
    ## `0xD0x`. MCF5307 User's Manual Table B-2, Appendix folio B-5, is this
    ## part's own map. A member for a register the part does not have would be
    ## a destination nothing can reach and a decode that looks successful.
    crUnimplemented
      ## CFPRM folio 8-13: "Attempted access to undefined or unimplemented
      ## control register space produces undefined results." What the core does
      ## with such a write is the executor's decision, so this module classifies
      ## and decides nothing.
    crCacr, crAcr0, crAcr1, crVbr, crRambar0, crRambar1, crMbar

proc controlRegisterFor*(rc: uint16): ControlRegister =
  ## Decode against the ColdFire map only. The 68k collision is silent in both
  ## directions: `0x004` and `0x005` are ACR0 and ACR1 here and ITT0 and ITT1 on
  ## the 68040, and `0x800` is USP on the 68040 and names no register of this
  ## part.
  ##
  ## `0x800` is absent from both manuals and that is the measurement, not an
  ## omission. CFPRM Table 8-3's processor-miscellaneous group, folio 8-14,
  ## runs VBR `0x801` then PC `0x80F` and assigns nothing to `0x800`; Table B-2
  ## does not carry it either. The register a 68k reading would put there has
  ## no home on this part in any case: this core has one A7 with no supervisor
  ## and user split, and CFPRM Table 1-6, folio 1-11, makes OTHER_A7 conditional
  ## on ISA_A+, which this part is not.
  ##
  ## RAMBAR1 is the one entry Table B-2 does not carry:
  ## the firmware writes `0xC05` in genuine code, CFPRM folio 8-14
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
  of 0xC05'u16: crRambar1   # CFPRM Table 8-3 folio 8-14
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
    ## Times", folio 3-29, times `movec Ry,Rc` at `11(0/1)` whole. `cpu.nim`
    ## adds its own fetch cost to this return, and the pair sums to that 11.
    ## The decomposition is this core's and not the manual's.

proc movecFamily*(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one `MOVEC`. Returns the cycles the execution pipe spent, 0 for an
  ## instruction that did not run.
  ##
  ## The privilege is tested before the extension word is fetched, and the order
  ## is a decision the manuals do not settle. CFPRM folio 8-13 states the
  ## operation as a conditional whose first test is supervisor state, and
  ## `fetchExt` can itself take an access error - so fetching first would let
  ## an instruction the core is about to refuse for privilege report the wrong
  ## exception instead. The stacked program counter is the same either way,
  ## so an `RTE` from the handler re-executes the whole instruction and
  ## re-reads the word this path did not.
  if movecPrivilegeViolation(ctx.sr):
    # The stacked program counter is this instruction and not the next one.
    # Table 3-1's stacked-program-counter column reads "Fault" for vector 8,
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
    # control register space produces undefined results." This core halts
    # rather than running on, which is the posture `cpu.nim`'s
    # `opExg`/`opTas`/`opNbcd` arm already takes for the same shape - a valid
    # encoding whose semantics this core does not carry - and `fault` stays
    # clear for that same reason. A core that accepted the write instead would
    # let firmware configure a register that does not exist and report nothing.
    ctx.halted = true
    return 0'u32
  movecExecuteCycles

# ---------------------------------------------------------------------------
# THE SYSTEM-CONTROL GROUP: the SR and CCR transfers. Task CPU-30.
#
# IT LIVES IN THIS FILE FOR ONE REASON AND THE REASON IS `movecPrivilegeViolation`
# ABOVE. `MOVE to SR` and `MOVE from SR` are supervisor-only, so an executor in
# any other module would need either a SECOND COPY of `(sr and srSupervisor) == 0`
# or an export of the predicate to a file that could then drift from it. A
# predicate computed in two places is the defect this project has already been
# bitten by: mutating one copy leaves every control that reads the other GREEN,
# so the mutation reads as "the check is untested" and not as "the check is
# absent". There is one copy, one call site per privileged instruction, and
# `tests/t_claims.cmake` can therefore require that mutating it turns BOTH the
# `MOVEC` cases and the `t_system_control` cases red in ONE run.
#
# THE GROUP IS FOUR INSTRUCTIONS AND NOT FIVE. `STOP` is ISA_A and this part
# has it, and it is excluded on a MEASUREMENT: zero `4E72` words occur at any
# 16-bit-aligned position in either image this core executes. It is privileged,
# so when a trigger brings it back it belongs HERE - splitting it into a module
# of its own would re-open the privilege-predicate question this file exists to
# close once.
#
# THE SIZE READING, WHICH THE MANUALS DISAGREE ON AND WHICH IS RECORDED HERE
# BECAUSE SILENCE WOULD NOT BE. CFPRM folio 4-54 gives `MOVE to CCR` as
# "Size = Byte" with the syntax `MOVE.B Dy,CCR`; CFPRM's own summary at folio
# 3-9 and MCF5307 User's Manual Table 3-14 both give WORD; and the pinned
# assembler - GNU Binutils 2.47.20260726, `-mcpu=5307` - accepts `move.w` and
# REJECTS `move.b`. THIS CODE TAKES THE WORD READING, which is two of the three
# manual statements and the toolchain. Nothing observable turns on it: both
# readings agree on the encoding, both give the immediate form a 16-bit
# extension word, and both write the same five bits, so no test in this tree
# discriminates between them and none is written to pretend otherwise.
#
# WHAT HAPPENS TO A7 WHEN SOFTWARE CLEARS S: NOTHING, AND THAT IS A PROPERTY OF
# ISA_A RATHER THAN A SIMPLIFICATION OF THIS CORE. `MOVE to SR` is the one
# instruction here that can clear the S bit, so the question is this group's to
# answer. THERE IS ONE A7 ON THIS PART AND NO USP: `MOVE to USP` and
# `MOVE from USP` are ISA_B - CFPRM folios 8-10 and 8-12 - and CFPRM Table 1-6,
# folio 1-11, makes OTHER_A7 conditional on ISA_A+, which this part is not. So
# there is no second stack pointer to swap in and no shadow register to keep;
# `cpu.nim`'s "THE ONE A7" block and `include/mcf5307.h` both state the same
# rule, and `tests/t_system_control.nim` asserts it by clearing S from
# supervisor state and requiring A7 to be where it was.

const
  ccrBits = ccrX or ccrN or ccrZ or ccrV or ccrC
    ## The condition-code bits of the status register, bits 4 to 0. IT IS
    ## COMPOSED FROM `machine.nim`'s OWN CONSTANTS and not written as `0x1F`,
    ## for the reason `movecPrivilegeViolation` gives about the S bit: a bit
    ## position restated as a literal here is one fact in two files, and a
    ## later change to either leaves the other saying something the machine
    ## does not do.
    ##
    ## THE CCR IS FIVE BITS ON THIS PART AND NOT EIGHT. User's Manual section
    ## 3.2.2.1, folio 3-10, prints the low byte of the status register with X,
    ## N, Z, V and C at bits 4 to 0 and NOTHING assigned to bits 7 to 5. The
    ## "zero-extended" of `MOVE from CCR`'s description is therefore this mask
    ## widened to a word, and a core that copied the whole low BYTE would
    ## differ from this one only on bits no instruction of this part can set.

  systemControlCycles = 1'u32
    ## THIS NUMBER MAKES NO CLAIM ABOUT THE MANUAL'S TIMING TABLES, and the
    ## block at the head of `cpu.nim` states the convention it is written
    ## under: a return with no citation cites nothing. The User's Manual's
    ## Table 3-14 was NOT read for these four instructions, because the only
    ## copy of that manual on this machine is the markdown transcription under
    ## `MCF5307UM-md/`, which this project does not accept as a source for any
    ## number. What the value has to be is NON-ZERO: `mcf5307_exec` breaks its
    ## loop on a cost of zero, so a zero here would stop the machine after an
    ## instruction that executed correctly.

proc systemControlFamily*(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one SR or CCR transfer. Returns the cycles the execution pipe
  ## spent, 0 for an instruction that did not run.
  ##
  ## THE PRIVILEGE IS TESTED BEFORE THE SOURCE IS READ, and the order is the
  ## one `movecFamily` above already takes, for the reason stated there: the
  ## immediate form's `eaRead` can itself take an ACCESS ERROR, so reading
  ## first would let an instruction the core is about to refuse for privilege
  ## report the wrong exception instead. The stacked program counter is the
  ## same either way, so an `RTE` from the handler re-executes the whole
  ## instruction and re-reads the word this path did not.
  ##
  ## THE STACKED PROGRAM COUNTER IS THIS INSTRUCTION AND NOT THE NEXT ONE, for
  ## the reason `movecFamily` states at its own `takeException` call: Table
  ## 3-1's STACKED PROGRAM COUNTER column reads "Fault" for vector 8.
  case d.op
  of opMoveFromSr:
    # CFPRM folio 8-9: "If Supervisor State Then SR -> Destination Else
    # Privilege Violation Exception". THE CONDITION CODES ARE NOT AFFECTED -
    # this instruction reads the status register and writes none of it.
    if movecPrivilegeViolation(ctx.sr):
      takeException(ctx, vecPrivilegeViolation, ctx.pc - insWordBytes)
      return 0'u32
    setRegD(ctx, d.destReg,
            mergeSized(regD(ctx, d.destReg), ctx.sr and 0xFFFF'u32, 2'u8))
    systemControlCycles
  of opMoveFromCcr:
    # CFPRM folio 4-53, chapter 4 - the USER instructions. NO PRIVILEGE TEST,
    # and the absence is the point: a core that tested privilege here would be
    # a 68000-shaped core, and `tests/t_system_control.nim` runs this case with
    # S CLEAR for exactly that reason.
    #
    # THE WRITE IS A WORD, SO THE HIGH HALF OF `Dx` SURVIVES IT. `mergeSized`
    # replaces the low two bytes and nothing else.
    setRegD(ctx, d.destReg,
            mergeSized(regD(ctx, d.destReg), ctx.sr and ccrBits, 2'u8))
    systemControlCycles
  of opMoveToCcr:
    # CFPRM folio 4-54: X, N, Z, V and C take source bits 4 to 0. UNPRIVILEGED,
    # and it writes FIVE BITS AND NOT SIXTEEN - the interrupt mask, the S bit
    # and the T bit are all outside `ccrBits` and survive unchanged. A core
    # that assigned the whole source would clear the mask and leave supervisor
    # state, which is the difference this mask is carrying.
    let src = eaRead(ctx, d.ea, 2'u8)
    if ctx.halted:
      return 0'u32
    ctx.sr = (ctx.sr and not ccrBits) or (src and ccrBits)
    systemControlCycles
  of opMoveToSr:
    # CFPRM folio 8-11: "If Supervisor State Then Source -> SR Else Privilege
    # Violation Exception". THE WHOLE WORD IS WRITTEN, which is what separates
    # this from `MOVE to CCR` above: `0x3001B41E movew #8192,%sr` sets S and
    # drives the interrupt mask to ZERO, and a five-bit write would leave the
    # mask at seven and the firmware waiting for an interrupt it had asked for.
    if movecPrivilegeViolation(ctx.sr):
      takeException(ctx, vecPrivilegeViolation, ctx.pc - insWordBytes)
      return 0'u32
    let src = eaRead(ctx, d.ea, 2'u8)
    if ctx.halted:
      return 0'u32
    ctx.sr = src and 0xFFFF'u32
    systemControlCycles
  else:
    # NO ARM OF `decodeWord` REACHES THIS BRANCH; it exists because a `case`
    # over `Operation` must be exhaustive and because a dispatch that grew a
    # fifth member without an arm here should be LOUD rather than silent.
    ctx.fault = true
    ctx.halted = true
    0'u32
