## `ea` - effective-address decoding and the per-opcode legality masks for
## ColdFire ISA_A.
##
## An effective address occupies the low six bits of the instruction word that
## carries it: the mode in bits 5..3 and the register in bits 2..0. For mode 7
## the register field selects the sub-variant (absolute, PC-relative,
## immediate, or the reserved/invalid encodings).
##
## Each opcode carries its own legality mask: a set of modes and, for mode 7,
## a set of sub-variants, that the opcode accepts. An effective address whose
## mode is outside the mask is illegal and must trap. A permissive core hides
## a firmware fault by executing an addressing mode the silicon rejects.

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
  # EVERY ADDRESSING MODE, AND THE NAME SAYS SO. This set holds all eight
  # values of `EAMode`, `eaAn` INCLUDED, so it is not the manual's DATA class
  # and never was.
  #
  # IT WAS CALLED `eaDataModes` UNTIL 2026-08-11, AND THE VALUE IS UNCHANGED
  # BY THE RENAME. The old name read as the manual's DATA category, which
  # EXCLUDES `An` - that class is `eaDataAlterableModes` above, and
  # `decode_types.nim` reaches it through `eaDataAddressing`. A reader who
  # took the old name at face value would have concluded that the nine
  # operations reading this set reject an address register, and all nine
  # ACCEPT one.
  #
  # THE `eaAn` MEMBERSHIP IS LOAD-BEARING AND IS NOT AN OVERSIGHT TO TIDY.
  # `m68k-elf-as -mcpu=5307` emits `4a88` for `tst.l %a0`, `b288` for
  # `cmp.l %a0,%d1` and `b3c8` for `cmpa.l %a0,%a1`, and MOVE and the ADD/SUB
  # pair take an address register source.
  #
  # MEASURED 2026-08-11 BY DELETING `eaAn` FROM THIS SET, AND THE COUNT IS
  # STATED THE WAY THE RUN PRINTS IT rather than as one round number. SEVEN
  # DISTINCT CASES GO RED, over TEN failure lines:
  #
  #   t_alu       1  `add.l a0,d1 reads the address register`
  #   t_control   3  `tst.w %a0 (4a48) runs: the word form reaches An`,
  #                  `tst %a0 is legal`, `cmp %a0 is legal`
  #   conformance 3  `move_l_a0_to_a1`, `tst_l_address_register`,
  #                  `cmp_l_address_register_source`
  #
  # The three conformance cases each print TWICE - once in their per-group
  # target and once in `mcf5307_conformance_all`, which re-runs the whole
  # corpus - so a reader counting failure LINES gets ten and a reader counting
  # CASES gets seven. Neither figure is wrong and they are not the same
  # figure, which is why both are written here.
  #
  # NOTE WHAT DOES *NOT* GO RED: `t_ea_masks` stays at 367 passed. Its
  # `coverage` row for each of these nine operations cites a RESERVED mode-7
  # encoding as the illegal mode, not `An`, so the file that exists to guard
  # the legality table cannot see this particular narrowing at all. The
  # evidence for `eaAn` is the executor and corpus cases above.
  eaAllModes* = {eaDn, eaAn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp,
                 eaAnIndex, eaMode7}
  eaData7* = {ea7AbsW, ea7AbsL, ea7PCDisp, ea7PCIndex, ea7Imm}

  eaControlModes* = {eaAnInd, eaAnDisp, eaAnIndex, eaMode7}

  # THE CONTROL CLASS'S MODE-7 SUB-VARIANTS WITHOUT THE ABSOLUTE SHORT FORM,
  # AND THE NAME NOW SAYS WHICH ONE IS MISSING. Table 3-5 p.3-21 marks
  # `(xxx).W`, `(xxx).L`, `(d16,PC)` and `(d8,PC,Xi)` as CONTROL; this set
  # omits the first of the four.
  #
  # IT WAS CALLED `eaControl7` UNTIL 2026-08-11, AND THE VALUE IS UNCHANGED BY
  # THE RENAME. The old name claimed to BE the control mode-7 class while
  # being narrower than it, which is the same defect as the old `eaDataModes`
  # above and inverted: that one was WIDER than its name and this one is
  # NARROWER.
  #
  # THE OLD NAME COST REAL WORK TWICE. LEA and PEA were wired to it and
  # trapped `lea 0x1234.w,%a0` and `pea 0x1234.w`, two forms the pinned
  # assembler emits; `eaLeaPeaTarget` in `decode_types.nim` is that repair.
  # MOVEM was then left on it on the reasoning that its `(xxx).W` exclusion
  # was correct - which it is - while the REST of the set was four cells too
  # wide for MOVEM, which folios 4-50 and 4-51 dash. That was a live defect
  # until the `opMovem` arm was narrowed to `{eaAnInd, eaAnDisp}`.
  #
  # BOTH REMAINING READERS ADD `ea7AbsW` BACK. `eaJumpTarget` and
  # `eaLeaPeaTarget` each spell `eaControl7NoAbsW + {ea7AbsW}`, so this
  # constant survives only as the left operand of that sum. It is NOT dead -
  # a prediction that MOVEM's narrowing would leave it unread was checked on
  # 2026-08-11 and is wrong by two consumers.
  eaControl7NoAbsW* = {ea7AbsL, ea7PCDisp, ea7PCIndex}

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
