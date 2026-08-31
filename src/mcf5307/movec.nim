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
