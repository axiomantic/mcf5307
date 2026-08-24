## `movec` - the `MOVEC` encoding, the privilege rule, the control-register map
## and the group's executor.
##
## THE MAP AND THE EXECUTOR ARE BOTH HERE, AND THE SPLIT INSIDE THE FILE IS
## WHAT MATTERS. Everything above `movecFamily` is a function of the
## instruction stream and of the status register, so it can be asserted value
## by value without a machine to run. `movecFamily` is the one procedure that
## needs a context.
##
## THE WRITE LANDS AND ONLY ONE OF THE DESTINATIONS MEANS ANYTHING YET, AND
## THE DISTINCTION IS THE LIMITATION A READER MUST NOT MISS. Every implemented
## control register is a field of the context and `movecFamily` stores into it,
## so the value survives the instruction and the register file can read it
## back. `VBR` is consumed: `machine.nim`'s `takeException` bases the vector
## table on it. THE OTHERS ARE STORED AND UNCONSUMED - this core does not model
## the cache, the access control regions, the on-chip SRAM or the peripheral
## base, so writing `RAMBAR0` does not move the SRAM and writing `CACR` does
## not change caching. A task that gives one of them a behaviour reads the
## field this file writes.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The encoding,
## the register numbers and the privilege rule are facts about Motorola
## silicon, from the MCF5307 User's Manual (1998) and the ColdFire Family
## Programmer's Reference Manual, Rev. 3.

import mcf5307/decode_types
import mcf5307/machine

# THE OPCODE WORD IS AN EQUALITY AND NOT A MASK: line 4 is dense here, and
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
  ## THE S-BIT IS `machine.nim`'s FACT AND IS READ FROM THERE. Restating the
  ## bit position here would put one fact in two files, where a later change to
  ## either leaves the other saying something the machine does not do.
  (sr and srSupervisor) == 0'u32

type
  ControlRegister* {.pure.} = enum
    ## The control registers THIS PART implements, and one member for every
    ## other number.
    ##
    ## THE SET IS THE PART'S AND NOT THE FAMILY'S. A member for a register the
    ## part does not have would be a destination nothing can reach and a decode
    ## that looks successful.
    crUnimplemented
    crCacr, crAcr0, crAcr1, crVbr, crRambar0, crRambar1, crMbar

proc controlRegisterFor*(rc: uint16): ControlRegister =
  ## DECODE AGAINST THE COLDFIRE MAP ONLY. The 68k collision is silent in both
  ## directions: `0x004` and `0x005` are ACR0 and ACR1 here and ITT0 and ITT1
  ## on the 68040, and `0x800` is USP on the 68040 and NAMES NO REGISTER OF
  ## THIS PART. This core has one A7 with no supervisor and user split, so the
  ## register a 68k reading would put at `0x800` has no home here in any case.
  ##
  ## RAMBAR1 AT `0xC05` IS ACCEPTED RATHER THAN TREATED AS A DECODE ERROR: the
  ## firmware writes that number in genuine code. `crRambar0` carries the
  ## family spelling of `0xC04` because that spelling distinguishes the two.
  case rc
  of 0x002'u16: crCacr
  of 0x004'u16: crAcr0
  of 0x005'u16: crAcr1
  of 0x801'u16: crVbr
  of 0xC04'u16: crRambar0
  of 0xC05'u16: crRambar1
  of 0xC0F'u16: crMbar
  else: crUnimplemented

# ---------------------------------------------------------------------------
# The executor.

const
  vecPrivilegeViolation = 8'u8

  movecExecuteCycles = 9'u32
    ## The manual times `movec Ry,Rc` WHOLE. `cpu.nim` adds the fetch cost to
    ## this return, so this constant carries the execution part alone. The
    ## decomposition is this core's and not the manual's.

proc movecFamily*(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one `MOVEC`. Returns the cycles the execution pipe spent, 0 for an
  ## instruction that did not run.
  ##
  ## THE PRIVILEGE IS TESTED BEFORE THE EXTENSION WORD IS FETCHED, AND THE
  ## ORDER IS A DECISION THE MANUALS DO NOT SETTLE. `fetchExt` can itself take
  ## an ACCESS ERROR, so fetching first would let
  ## an instruction the core is about to refuse for privilege report the wrong
  ## exception instead. The stacked program counter is the same either way,
  ## so an `RTE` from the handler re-executes the whole instruction and
  ## re-reads the word this path did not.
  if movecPrivilegeViolation(ctx.sr):
    # THE STACKED PROGRAM COUNTER IS THIS INSTRUCTION AND NOT THE NEXT ONE.
    # `step` has already advanced the pc past the opcode word, so the faulting
    # address is one word back.
    takeException(ctx, vecPrivilegeViolation, ctx.pc - insWordBytes)
    return 0'u32
  let ext = fetchExt(ctx)
  if ctx.halted:
    return 0'u32
  # THE MAP IS CONSULTED ONCE AND THE REFUSAL AND THE STORE BOTH READ THAT ONE
  # ANSWER. Two calls would be two decodes of one instruction, and a later
  # change to `controlRegisterFor` could then be refused by one and accepted by
  # the other.
  let destination = controlRegisterFor(movecControlField(ext))
  if destination == crUnimplemented:
    # Undefined control register space produces undefined results. This core
    # HALTS rather than running on, and `fault` stays clear: the encoding is
    # valid and only its semantics are absent. A core that accepted the write
    # instead would let firmware configure a register that does not exist and
    # report nothing.
    ctx.halted = true
    return 0'u32
  # THE SOURCE IS THE REGISTER THE EXTENSION WORD NAMES, ACROSS BOTH FILES. The
  # A/D bit selects the file and Ry selects within it, so an implementation
  # that read a data register whatever the encoding said would move the wrong
  # value for every `movec Ay,Rc` the firmware issues.
  let source =
    if movecSourceIsAddressRegister(ext): regA(ctx, movecSourceRegister(ext))
    else: regD(ctx, movecSourceRegister(ext))
  # THE VALUE IS STORED AS WRITTEN AND IS NOT MASKED HERE. VBR's unimplemented
  # low bits are dropped by `exception.nim` AT THE DISPATCH, so a reader of the
  # field sees what the machine was given rather than what one consumer of it
  # makes of the value; the other registers have no consumer to mask for.
  case destination
  of crCacr: ctx.cacr = source
  of crAcr0: ctx.acr0 = source
  of crAcr1: ctx.acr1 = source
  of crVbr: ctx.vbr = source
  of crRambar0: ctx.rambar0 = source
  of crRambar1: ctx.rambar1 = source
  of crMbar: ctx.mbar = source
  of crUnimplemented: discard
  movecExecuteCycles

# ---------------------------------------------------------------------------
# THE SYSTEM-CONTROL GROUP: the SR and CCR transfers.

const
  ccrBits = ccrX or ccrN or ccrZ or ccrV or ccrC
    ## The condition-code bits of the status register, bits 4 to 0. IT IS
    ## COMPOSED FROM `machine.nim`'s OWN CONSTANTS and not written as `0x1F`,
    ## for the reason `movecPrivilegeViolation` gives about the S bit: a bit
    ## position restated as a literal here is one fact in two files, and a
    ## later change to either leaves the other saying something the machine
    ## does not do.

  systemControlCycles = 1'u32

proc systemControlFamily*(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one SR or CCR transfer. Returns the cycles the execution pipe
  ## spent, 0 for an instruction that did not run.
  case d.op
  of opMoveFromSr:
    # THE CONDITION CODES ARE NOT AFFECTED - this instruction reads the status
    # register and writes none of it.
    if movecPrivilegeViolation(ctx.sr):
      takeException(ctx, vecPrivilegeViolation, ctx.pc - insWordBytes)
      return 0'u32
    setRegD(ctx, d.destReg,
            mergeSized(regD(ctx, d.destReg), ctx.sr and 0xFFFF'u32, 2'u8))
    systemControlCycles
  of opMoveFromCcr:
    # THE WRITE IS A WORD, SO THE HIGH HALF OF `Dx` SURVIVES IT. `mergeSized`
    # replaces the low two bytes and nothing else.
    setRegD(ctx, d.destReg,
            mergeSized(regD(ctx, d.destReg), ctx.sr and ccrBits, 2'u8))
    systemControlCycles
  of opMoveToCcr:
    # UNPRIVILEGED, and it writes the condition-code bits and no more - the
    # interrupt mask, the S bit
    # and the T bit are all outside `ccrBits` and survive unchanged. A core
    # that assigned the whole source would clear the mask and leave supervisor
    # state, which is the difference this mask is carrying.
    let src = eaRead(ctx, d.ea, 2'u8)
    if ctx.halted:
      return 0'u32
    ctx.sr = (ctx.sr and not ccrBits) or (src and ccrBits)
    systemControlCycles
  of opMoveToSr:
    # THE WHOLE WORD IS WRITTEN, which is what separates
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
    ctx.fault = true
    ctx.halted = true
    0'u32
