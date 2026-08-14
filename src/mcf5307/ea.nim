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
  # Every addressing mode. This set holds all eight values of `EAMode`, `eaAn`
  # included, so it is not the manual's DATA class. The DATA class is
  # `eaDataAlterableModes` below, reached through `eaDataAddressing`.
  #
  # The `eaAn` membership is load-bearing and is not an oversight to tidy.
  # `m68k-elf-as -mcpu=5307` emits `4a88` for `tst.l %a0`, `b288` for
  # `cmp.l %a0,%d1` and `b3c8` for `cmpa.l %a0,%a1`, and MOVE and the ADD/SUB
  # pair take an address register source.
  eaAllModes* = {eaDn, eaAn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp,
                 eaAnIndex, eaMode7}

  # Every valid mode-7 sub-variant. `EA7` has eight members; three of them -
  # `ea7Unused5`, `ea7Invalid` and `ea7Unused7` - are encodings this part does
  # not define, and this set is the other five.
  #
  # This set is not the manual's DATA class: `decode_types.nim` pairs it with
  # `eaAllModes` for nine operations that accept `An`, which DATA excludes. The
  # genuine DATA-class mask is `eaDataAddressing` in `decode_types.nim`, which
  # pairs `eaDataAlterableModes` - every mode but `An` - with this set. DATA and
  # DATA ALTERABLE differ on this part in their mode-7 sub-variants alone.
  eaValid7* = {ea7AbsW, ea7AbsL, ea7PCDisp, ea7PCIndex, ea7Imm}

  eaControlModes* = {eaAnInd, eaAnDisp, eaAnIndex, eaMode7}

  # The control class's mode-7 sub-variants. All four of them, `(xxx).W`
  # included.
  #
  # CFPRM Rev. 3, Table 2-3, "Effective Addressing Modes and Categories", folio
  # 2-10 - PDF PAGE 50, rendered with `pdftoppm -r 200` and read as an IMAGE.
  # Chapter 2's folio-to-page offset is +40 and is NOT the +76 that the
  # chapter 4 instruction folios take. The `Control` column carries an `X` on
  # `(An)`, `(d16,An)`, `(d8,An,Xi*SF)`, `(d16,PC)`, `(d8,PC,Xi*SF)`, `(xxx).W`
  # and `(xxx).L`, and a dash on `Dn`, `An`, `(An)+`, `-(An)` and `#<xxx>`. The
  # four mode-7 rows among the seven are this set.
  #
  # `m68k-elf-as -mcpu=5307` (GNU Binutils 2.47.20260726) answers the same
  # twelve cells for all four readers: `jmp`, `jsr`, `lea`
  # and `pea` each accept the seven control rows and reject the other five with
  # "operands mismatch". The absolute-short encodings are `4ef8 1234`,
  # `4eb8 1234`, `41f8 1234` and `4878 1234`.
  #
  # An operand class that really excludes `(xxx).W` belongs at its site as
  # `eaControl7 - {ea7AbsW}`, not here as a second declaration. LEA and PEA
  # were once wired to such a narrow set and trapped `lea 0x1234.w,%a0` and
  # `pea 0x1234.w`, forms the pinned assembler emits.
  eaControl7* = {ea7AbsW, ea7AbsL, ea7PCDisp, ea7PCIndex}

  # The mode-7 sub-variants of a written operand. There is no companion mode
  # set: an alterable operand may take every mode, so the readers pair this with
  # `eaAllModes` and the whole of the restriction is here.
  #
  # Why the mode list cannot restrict anything here. Seven of the eight modes
  # are alterable outright, and the eighth is mode 7, whose sub-variants split
  # between alterable and not. A mode-level set therefore has to admit mode 7 to
  # let the absolute forms through, at which point it admits all eight and
  # restricts nothing. The split is a property of the register field alone.
  #
  # Measured with `m68k-elf-as -mcpu=5307` (GNU Binutils 2.47.20260726),
  # twelve cells each for ADDQ and SUBQ. ADDQ accepts `%d0`
  # (`5280`), `%a0` (`5288`), `(%a0)` (`5290`), `(%a0)+` (`5298`), `-(%a0)`
  # (`52a0`), `(4,%a0)` (`52a8 0004`), `(4,%a0,%d2)` (`52b0 2804`), `0x1234.w`
  # (`52b8 1234`) and `0x12345678` (`52b9 1234 5678`), and rejects `(4,%pc)`,
  # `(4,%pc,%d2)` and `#5`. SUBQ answers the same twelve - `%a0` is `5388`,
  # `0x1234.w` is `53b8 1234`. Every mode appears among the accepted cells.
  #
  # The CFPRM's `Alterable` column dashes both members of this set, and the
  # assembler is taken as the authority. Table 2-3, folio 2-10, PDF page 50,
  # read as a rendered image: `(xxx).W` and `(xxx).L` carry an `X` under `Data`,
  # `Memory` and `Control` and a dash under `Alterable`. An ADDQ to an absolute
  # destination writes memory and the pinned assembler emits it, so the column
  # is read here as a coarse-table artefact. THAT DISAGREEMENT IS RECORDED AND
  # NOT SETTLED.
  eaAlterable7* = {ea7AbsW, ea7AbsL}

  # Data alterable: alterable without An. CLR takes this class - measured
  # against `m68k-elf-as -mcpu=5307`, which rejects `clr.l %a0` and accepts
  # every other mode this set names.
  #
  # The multiply and divide do not take this class at either size: the
  # assembler also rejects `mulu.l 0x1234.w,%d1`, `mulu.l 0x12345678,%d1` and
  # `mulu.l (4,%a0,%d2),%d1`. The two masks those four operations carry are
  # below.
  eaDataAlterableModes* = {eaDn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp,
                           eaAnIndex, eaMode7}
  eaDataAlterable7* = {ea7AbsW, ea7AbsL}

  # The source of the longword multiply and divide. Narrower than data
  # alterable by the indexed mode and by the whole of mode 7, so its `ea7` set
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
