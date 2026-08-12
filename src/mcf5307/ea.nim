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
  # EVERY ADDRESSING MODE, AND THE NAME SAYS SO. This set holds all eight
  # values of `EAMode`, `eaAn` INCLUDED, so it is not the manual's DATA class
  # and never was.
  #
  # RENAMED FROM `eaDataModes` 2026-08-11, VALUE UNCHANGED. The old name read
  # as the manual's DATA category, which EXCLUDES `An`; a reader taking it at
  # face value would have concluded that the nine operations reading this set
  # reject an address register, and all nine ACCEPT one. The DATA class is
  # `eaDataAlterableModes` below, reached through `eaDataAddressing`.
  #
  # THE `eaAn` MEMBERSHIP IS LOAD-BEARING AND IS NOT AN OVERSIGHT TO TIDY.
  # `m68k-elf-as -mcpu=5307` emits `4a88` for `tst.l %a0`, `b288` for
  # `cmp.l %a0,%d1` and `b3c8` for `cmpa.l %a0,%a1`, and MOVE and the ADD/SUB
  # pair take an address register source.
  #
  # MEASURED 2026-08-12 BY DELETING `eaAn` FROM THIS SET. TWENTY-TWO DISTINCT
  # CASES GO RED:
  #
  #   t_ea_masks 13  block (19) 11 - one per mask that names this set, which is
  #                  MOVE, MOVEA, ADDQ, SUBQ, ADD, SUB, ADDA, SUBA, TST, CMP and
  #                  CMPA - and block (16) 2, `opAddq`/`opSubq: the mask accepts
  #                  An`
  #   t_alu       3  `add.l a0,d1 reads the address register`,
  #                  `addq.l #1,a1 wraps and leaves the condition codes alone`,
  #                  `the ADDQ mask admits An`
  #   t_control   3  `tst.w %a0 (4a48) runs: the word form reaches An`,
  #                  `tst %a0 is legal`, `cmp %a0 is legal`
  #   conformance 3  `move_l_a0_to_a1`, `tst_l_address_register`,
  #                  `cmp_l_address_register_source`
  #
  # The three conformance cases each print TWICE - once in their per-group
  # target and once in `mcf5307_conformance_all`, which re-runs the whole
  # corpus - so a reader counting failure LINES and a reader counting CASES get
  # different figures. The count above is CASES.
  #
  # ELEVEN OF THE TWENTY-TWO ARE A WIDER READERSHIP AND NOT BETTER COVERAGE, and
  # the two are easy to confuse. Every operation naming this set contributes its
  # block (19) row, and ADDQ and SUBQ read it only because `eaAlterableModes`
  # was retired into it, so the cases guarding THEIR address-register operand
  # joined a blast radius they were never part of. Measured 2026-08-12 by
  # narrowing the ADDQ/SUBQ ARM ALONE to `eaAllModes - {eaAn}`, configured FRESH
  # and run through `ctest`: SIX red - `t_alu` 2, and `t_ea_masks` 4, which is
  # block (16) 2 and block (19) 2 - and nothing else in the suite moves.
  #
  # THE MASK LEVEL SEES THIS DELETION FOR ALL ELEVEN, AND IT DID NOT USED TO.
  # For MOVE, MOVEA, ADD, SUB, ADDA, SUBA, TST, CMP and CMPA the `t_ea_masks`
  # `coverage` row cites a RESERVED mode-7 encoding as the illegal mode and
  # never `An`, so those nine rows are blind to it; block (19) holds each mask
  # against its literal value and is what covers them. ADDQ and SUBQ are covered
  # twice over, there and in block (16)'s hand-written cells.
  #
  # WIDENING THIS SET IS NOT A MEASURABLE DIRECTION. It already holds all eight
  # members of `EAMode`, so there is no mode to add and no widening mutation to
  # run. Every widening this family admits is a mode-7 one and belongs to the
  # `EA7` sets below.
  eaAllModes* = {eaDn, eaAn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp,
                 eaAnIndex, eaMode7}

  # EVERY VALID MODE-7 SUB-VARIANT, AND THE NAME SAYS SO. `EA7` has eight
  # members; three of them - `ea7Unused5`, `ea7Invalid` and `ea7Unused7` - are
  # encodings this part does not define, and this set is the other five.
  #
  # RENAMED FROM `eaData7` 2026-08-11, VALUE UNCHANGED; `tests/t_ea_masks.nim`
  # block (19) holds every mask that names this set against a literal spelling
  # these five members, so the rename could not move one. Block (17), which held
  # the set itself by name, was deleted 2026-08-12 because it could not red
  # without block (19) reddening too, and the tombstone there carries the runs.
  # The old name claimed the manual's DATA class, and `decode_types.nim`
  # pairs this set with `eaAllModes` for nine operations that ACCEPT `An` -
  # which DATA excludes - so the pair is the widest class and not DATA.
  #
  # THE GENUINE DATA-CLASS MASK IS `eaDataAddressing` in `decode_types.nim`,
  # which pairs `eaDataAlterableModes` - every mode but `An` - with this set.
  # DATA and DATA ALTERABLE differ on this part in their mode-7 sub-variants
  # alone, so a DATA mask is honestly built from the alterable mode list plus
  # the full valid mode-7 set.
  eaValid7* = {ea7AbsW, ea7AbsL, ea7PCDisp, ea7PCIndex, ea7Imm}

  eaControlModes* = {eaAnInd, eaAnDisp, eaAnIndex, eaMode7}

  # THE CONTROL CLASS'S MODE-7 SUB-VARIANTS. All four of them, `(xxx).W`
  # INCLUDED.
  #
  # CFPRM Rev. 3, Table 2-3, "Effective Addressing Modes and Categories", folio
  # 2-10 - PDF PAGE 50, rendered with `pdftoppm -r 200` and read as an IMAGE.
  # Chapter 2's folio-to-page offset is +40 and is NOT the +76 that the
  # chapter 4 instruction folios take. The `Control` column carries an `X` on
  # `(An)`, `(d16,An)`, `(d8,An,Xi*SF)`, `(d16,PC)`, `(d8,PC,Xi*SF)`, `(xxx).W`
  # and `(xxx).L`, and a dash on `Dn`, `An`, `(An)+`, `-(An)` and `#<xxx>`. The
  # four mode-7 rows among the seven are this set.
  #
  # `m68k-elf-as -mcpu=5307` (GNU Binutils 2.47.20260726) ANSWERS THE SAME
  # TWELVE CELLS FOR ALL FOUR READERS, measured 2026-08-11: `jmp`, `jsr`, `lea`
  # and `pea` each accept the seven control rows and reject the other five with
  # "operands mismatch". The absolute-short encodings are `4ef8 1234`,
  # `4eb8 1234`, `41f8 1234` and `4878 1234`.
  #
  # THIS CONSTANT DID NOT EXIST UNTIL 2026-08-11 AND ITS ABSENCE COST TWO
  # REPAIRS. The control class MINUS `(xxx).W` was the declared primitive and
  # the class itself was written down nowhere; `eaJumpTarget` and
  # `eaLeaPeaTarget` each RECONSTRUCTED it as `<that set> + {ea7AbsW}`. LEA and
  # PEA were wired to the narrow set and trapped `lea 0x1234.w,%a0` and
  # `pea 0x1234.w`, forms the pinned assembler emits. A future operand class
  # that really excludes `(xxx).W` belongs at its site as
  # `eaControl7 - {ea7AbsW}`, not back here as a second declaration.
  #
  # THE NARROW SET IS GONE RATHER THAN DERIVED, AND THE MEASURED FACT IS ZERO
  # CODE READERS: once both readers took this set directly, no expression
  # anywhere in `src/` read the old name. THE STATED LIMIT IS THAT THIS IS A
  # CLAIM ABOUT CODE AND NOT ABOUT PROSE - the old name still appears in
  # comment text, and no run can see that. Measured 2026-08-11 by grepping the
  # name over each directory in turn: EIGHT mentions under `src/`, every one of
  # them in `decode_types.nim`; TWO under `tests/`, one each in
  # `t_ea_masks.nim` and `t_move.nim`; and ZERO under `conformance/`. MOVEM
  # reads neither set and carries `{eaAnInd, eaAnDisp}`.
  #
  # WHAT THAT EXPRESSION COSTS IF IT IS EVER WRITTEN ON THIS DECLARATION
  # INSTEAD OF AT A SITE. Measured 2026-08-12 by narrowing THIS set to
  # `{ea7AbsL, ea7PCDisp, ea7PCIndex}`, configured FRESH and run through
  # `ctest`: FOURTEEN distinct cases red -
  #
  #   t_ea_masks   6  `opLea`/`opPea: the mask accepts (xxx).W` and block (19)'s
  #                   four rows for `opLea`, `opPea`, `opJmp` and `opJsr`
  #   t_move       5  the three `lea (xxx).W` cases and the two `pea (xxx).W`
  #   t_control    2  `jmp (xxx).w is legal`, `jsr (xxx).w is legal`
  #   conformance  1  `group=control case=jmp_absolute_short
  #                   instruction="jmp 0x1234.w"`
  #
  # THE CONFORMANCE CASE IS THE ONE A COUNT TAKEN FROM THE `t_*` SUITES ALONE
  # LEAVES OUT, and leaving it out is how the records in this family have been
  # wrong before. Thirteen is the number a reader gets by stopping at `ctest`'s
  # Nim suites; fourteen is the number.
  #
  # JMP AND JSR ARE COVERED BY `tests/t_control.nim` AND NOT BY `t_ea_masks`.
  # Its twelve-row `eaIsLegalFor(opJmp/opJsr, ...)` table is where the two
  # `(xxx).w is legal` cases above come from.
  eaControl7* = {ea7AbsW, ea7AbsL, ea7PCDisp, ea7PCIndex}

  # THE MODE-7 SUB-VARIANTS OF A WRITTEN OPERAND. There is no companion mode
  # set: an ALTERABLE operand may take EVERY mode, so the readers pair this with
  # `eaAllModes` and the whole of the restriction is here.
  #
  # `eaAlterableModes` HELD THAT MODE LIST UNTIL 2026-08-11 AND WAS
  # BYTE-IDENTICAL TO `eaAllModes`. It is gone; the ADDQ and SUBQ arm names
  # `eaAllModes`, which claims no class and is therefore true.
  #
  # WHY THE MODE LIST CANNOT RESTRICT ANYTHING HERE. Seven of the eight modes
  # are alterable outright, and the eighth is mode 7, whose sub-variants split
  # between alterable and not. A mode-level set therefore has to admit mode 7 to
  # let the absolute forms through, at which point it admits all eight and
  # restricts nothing. The split is a property of the register field alone.
  #
  # MEASURED 2026-08-11 WITH `m68k-elf-as -mcpu=5307` (GNU Binutils
  # 2.47.20260726), twelve cells each for ADDQ and SUBQ. ADDQ accepts `%d0`
  # (`5280`), `%a0` (`5288`), `(%a0)` (`5290`), `(%a0)+` (`5298`), `-(%a0)`
  # (`52a0`), `(4,%a0)` (`52a8 0004`), `(4,%a0,%d2)` (`52b0 2804`), `0x1234.w`
  # (`52b8 1234`) and `0x12345678` (`52b9 1234 5678`), and rejects `(4,%pc)`,
  # `(4,%pc,%d2)` and `#5`. SUBQ answers the same twelve - `%a0` is `5388`,
  # `0x1234.w` is `53b8 1234`. Every mode appears among the accepted cells.
  #
  # THE CFPRM'S `Alterable` COLUMN DASHES BOTH MEMBERS OF THIS SET, AND THE
  # ASSEMBLER IS TAKEN AS THE AUTHORITY. Table 2-3, folio 2-10, PDF page 50,
  # read as a rendered image: `(xxx).W` and `(xxx).L` carry an `X` under `Data`,
  # `Memory` and `Control` and a DASH under `Alterable`. An ADDQ to an absolute
  # destination writes memory and the pinned assembler emits it, so the column
  # is read here as a coarse-table artefact. THAT DISAGREEMENT IS RECORDED AND
  # NOT SETTLED; `tests/t_ea_masks.nim` block (16) pins the behaviour so a
  # narrowing that follows the column goes red rather than passing quietly.
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
  # `eaMulDivLong7` IS DEAD FOR THESE OPERATIONS AT RUN TIME. IT RECORDS THE
  # FOLIOS AND IT CONSTRAINS NOTHING THE CORE EVALUATES. `isEaLegal` below
  # returns at `ea.mode notin leg.modes` before it reaches `ea7`, and the mode
  # set on the line above has no `eaMode7`, so the ONLY read of the field
  # anywhere in the core - `EA7(ea.reg) in leg.ea7` - is unreachable through
  # this mask. The emptiness is therefore not what rejects a mode-7 operand
  # here; the absent `eaMode7` is.
  #
  # BOTH HALVES ARE NEVERTHELESS GUARDED NOW, AND THEY DID NOT USED TO BE.
  # `t_ea_masks` block (19) holds the whole `EaLegality` of each mask against a
  # literal, which reads the `ea7` field whether the core ever does or not.
  # Measured 2026-08-12, each mutation configured FRESH and run through `ctest`:
  #
  #   this set widened to all EIGHT sub-variants      4 red, all block (19)
  #   `eaMode7` added to the mode set, this set empty 4 red, all block (19)
  #   BOTH widened together                          32 red, of which 4 are
  #                                                   block (19) and 28 are the
  #                                                   cases that were the whole
  #                                                   of the coverage before it
  #
  # THE TWO SINGLE-HALF MUTATIONS LEFT THE ENTIRE SUITE GREEN before block (19)
  # existed, so a reader who took either line alone for a tested constraint had
  # the same wrong picture that the defect this split was written to close had.
  # That is now a statement about a value pinned in one place and a run-time
  # path reached in another, which is the honest shape of it.
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
