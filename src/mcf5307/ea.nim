## `ea` - effective-address decoding and the per-opcode legality masks for
## ColdFire ISA_A. Task CPU-6 owns this file. Design section 6.1.
##
## An effective address occupies the low six bits of the instruction word that
## carries it: the mode in bits 5..3 and the register in bits 2..0. For mode 7
## the register field selects the sub-variant (absolute, PC-relative,
## immediate, or the reserved/invalid encodings).
##
## EACH OPCODE CARRIES ITS OWN LEGALITY MASK. The mask is a set of modes and,
## for mode 7, a set of sub-variants, that the opcode accepts. An effective
## address whose mode is outside the mask is illegal and must trap. Design
## section 6.1 makes this a mandatory property of the core: a permissive core
## hides a firmware fault by executing an addressing mode the silicon rejects.
## The instruction-specific negative cases (a memory shift, byte and word
## arithmetic, `MOVEM -(An)`, ...) are CPU-13's, and this module provides the
## mechanism they assert through.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The
## addressing-mode encoding and the classes below are facts about Motorola
## silicon; they are taken from the ColdFire Family Programmer's Reference
## Manual (AGENTS.md section 11) and from this project's own measurements.
## No expression was taken from any copyleft source.

type
  EAMode* = enum
    eaDn        ## 0  Dn          data register direct
    eaAn        ## 1  An          address register direct
    eaAnInd     ## 2  (An)        address register indirect
    eaAnPost    ## 3  (An)+       indirect with postincrement
    eaAnPre     ## 4  -(An)       indirect with predecrement
    eaAnDisp    ## 5  (d16,An)    indirect with displacement
    eaAnIndex   ## 6  (d8,An,Xn)  indirect with index
    eaMode7     ## 7  mode 7: the register field selects the sub-variant

  ## The mode-7 sub-variants, selected by the register field (bits 2..0).
  EA7* = enum
    ea7AbsW       ## (xxx).W     absolute short
    ea7AbsL       ## (xxx).L     absolute long
    ea7PCDisp     ## (d16,PC)    PC-relative with displacement
    ea7PCIndex    ## (d8,PC,Xn)  PC-relative with index
    ea7Imm        ## #imm        immediate
    ea7Unused5    ## reserved
    ea7Invalid    ## invalid encoding
    ea7Unused7    ## reserved

  EA* = object
    ## The decoded effective address of an instruction word.
    mode*: EAMode
    reg*: uint8   ## Dn/An index, or the mode-7 sub-variant for `eaMode7`

proc decodeEa*(field: uint16): EA =
  ## Decode the low six bits of an instruction word into an effective address.
  ## Mode is bits 5..3, register is bits 2..0. This is the canonical 68k and
  ## ColdFire placement.
  EA(mode: EAMode((field shr 3) and 0x7), reg: uint8(field and 0x7))

proc isMode7*(ea: EA): bool =
  ea.mode == eaMode7

# ---------------------------------------------------------------------------
# The addressing-mode classes.
#
# These are the canonical ColdFire classes (CFPRM, "Addressing Modes"). Each
# opcode selects the class its operand must belong to, and the decoder turns
# the class into a `EaLegality` mask.
#
#   Data addressing      Dn, An, (An), (An)+, -(An), (d16,An), (d8,An,Xn),
#                        (xxx).W, (xxx).L, (d16,PC), (d8,PC,Xn), #imm
#   Control addressing   (An), (d16,An), (d8,An,Xn), (xxx).L, (d16,PC),
#                        (d8,PC,Xn)
#   Alterable addressing Data addressing without PC-relative or immediate.

const
  eaDataModes* = {eaDn, eaAn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp,
                  eaAnIndex, eaMode7}
  eaData7* = {ea7AbsW, ea7AbsL, ea7PCDisp, ea7PCIndex, ea7Imm}

  eaControlModes* = {eaAnInd, eaAnDisp, eaAnIndex, eaMode7}
  eaControl7* = {ea7AbsL, ea7PCDisp, ea7PCIndex}

  eaAlterableModes* = {eaDn, eaAn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp,
                       eaAnIndex, eaMode7}
  eaAlterable7* = {ea7AbsW, ea7AbsL}

  # Data alterable: alterable without An. CLR takes this class - measured
  # against `m68k-elf-as -mcpu=5307`, which rejects `clr.l %a0` and accepts
  # every other mode this set names.
  #
  # THE MULTIPLY AND DIVIDE DO NOT TAKE THIS CLASS AT EITHER SIZE, AND AN
  # EARLIER REVISION OF THIS COMMENT SAID THEY DID. It read "and so does the
  # source of the ColdFire 32-bit multiply and divide ... rejects `clr.l %a0`,
  # `mulu.l %a0,%d1`, `mulu.l (4,%pc),%d1` and `mulu.l #5,%d1` AND ACCEPTS THE
  # REST". The last four words were wrong: the assembler also rejects
  # `mulu.l 0x1234.w,%d1`, `mulu.l 0x12345678,%d1` and
  # `mulu.l (4,%a0,%d2),%d1`. The two masks those four operations really carry
  # are below.
  eaDataAlterableModes* = {eaDn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp,
                           eaAnIndex, eaMode7}
  eaDataAlterable7* = {ea7AbsW, ea7AbsL}

  # THE SOURCE OF THE LONGWORD MULTIPLY AND DIVIDE. Narrower than data
  # alterable by the INDEXED mode and by the whole of mode 7, so its `ea7` set
  # is empty and no mode-7 sub-variant can be legal.
  #
  # CFPRM folios 4-32, 4-34, 4-56 and 4-58, "Instruction Fields (Longword)":
  # each prints a mode and register value for `Dy`, `(Ay)`, `(Ay)+`, `-(Ay)`
  # and `(d16,Ay)` and a DASH for `Ay`, `(d8,Ay,Xi)`, `(xxx).W`, `(xxx).L`,
  # `#<data>`, `(d16,PC)` and `(d8,PC,Xi)`. `m68k-elf-as -mcpu=5307` answers
  # the same twelve cells for all four operations.
  #
  # `eaMulDivLong7` IS DEAD FOR THESE OPERATIONS. IT RECORDS THE FOLIOS; IT
  # CONSTRAINS NOTHING, AND IT MUST NOT BE READ AS A CHECKED MASK. `isEaLegal`
  # below returns at `ea.mode notin leg.modes` before it reaches `ea7`, and
  # the mode set on the line above has no `eaMode7`, so the ONLY read of the
  # field anywhere in the core - `EA7(ea.reg) in leg.ea7` - is unreachable
  # through this mask. The emptiness is therefore not what rejects a mode-7
  # operand here; the absent `eaMode7` is.
  #
  # MEASURED 2026-08-11, AND BOTH HALVES ARE INDIVIDUALLY UNGUARDED. Widening
  # this set to all EIGHT mode-7 sub-variants leaves the whole suite green.
  # Adding `eaMode7` to the mode set while leaving this set empty ALSO leaves
  # the whole suite green. Only widening BOTH is caught, and then 28 cases
  # red. A reader who takes either line alone for a tested constraint has the
  # same wrong picture that the defect this split was written to close had.
  eaMulDivLongModes* = {eaDn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp}
  eaMulDivLong7*: set[EA7] = {}

  # Memory alterable: data alterable without Dn. It is the destination class
  # of the `Dn op <ea> -> <ea>` direction of ADD and SUB; the Dn and An
  # encodings of that direction are the ADDX and ADDA slots and never a
  # memory destination.
  eaMemAlterableModes* = {eaAnInd, eaAnPost, eaAnPre, eaAnDisp, eaAnIndex,
                          eaMode7}
  eaMemAlterable7* = {ea7AbsW, ea7AbsL}

# ---------------------------------------------------------------------------
# A legality mask is a set of modes plus, for mode 7, a set of allowed
# sub-variants.

type
  EaLegality* = object
    modes*: set[EAMode]
    ea7*: set[EA7]

proc isEaLegal*(leg: EaLegality; ea: EA): bool =
  ## True when the effective address is inside the opcode's legality mask.
  ## A mode outside the mask is illegal; mode 7 is legal only when the
  ## sub-variant selected by the register field is in `leg.ea7`.
  if ea.mode notin leg.modes:
    return false
  if ea.mode == eaMode7:
    result = EA7(ea.reg) in leg.ea7
  else:
    result = true
