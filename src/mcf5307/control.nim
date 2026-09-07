## `control` - the control-flow and comparison instruction group of the
## ColdFire ISA_A core.
##
## This module executes Bcc, BRA, BSR, JMP, JSR, RTS, RTE, Scc, TST, CMP,
## CMPA, CMPI and TRAP, and nothing else. NOP has no work to do and `cpu.nim`
## answers it without entering this module. The register file, the board
## accesses, the effective-address evaluation and the exception frame are
## `mcf5307/machine`'s.
##
## Its whole import list is `{decode_types, ea, machine}`. An executor that
## reaches into another executor for a helper rebuilds the decoder-under-
## executor cycle one layer down. The one helper this group needed that no
## earlier group had - the exception stack frame - went down into
## `machine.nim`.
##
## The sizes.
##
##   CMP, CMPA AND CMPI HAVE BYTE AND WORD FORMS ON THIS PART, AND THIS CORE
##   REFUSES THEM ANYWAY. That is a deliberate non-implementation and no longer
##   a statement about the silicon, which is the whole of the change here.
##
##   MCF5407 User's Manual Table 2-8, "User-Level Instruction Set Summary",
##   folio 2-20, gives CMP an operand size of `.B,.W,.L`, CMPI `.B,.W,.L` and
##   CMPA `.W,.L`. Table 2-7, "ColdFire ISA_B Extension Summary", folio 2-19,
##   lists `cmp.{b,w,l}`, `cmpa.w` and `cmpi.{b,w}` among the Revision B
##   additions. The MCF5307's Table 3-7 gave all three an operand size of `32`
##   alone, which is what the old wording here recorded.
##
##   Every byte and word form still TRAPS here, because this core does not
##   implement Revision B at all. See the Revision B note in `AGENTS.md` for
##   why that decision was taken and what would reverse it.
##
##   THE MANUAL AND THE ASSEMBLER DISAGREE ABOUT `cmpa.w`, AND THE
##   DISAGREEMENT IS NOT RESOLVED HERE. Measured with GNU Binutils
##   2.47.20260726: `-mcpu=5407` accepts `cmp.b` (`b200`), `cmp.w` (`b240`),
##   `cmpi.b` (`0c00 0001`) and `cmpi.w` (`0c40 0001`), and REJECTS
##   `cmpa.w %d0,%a1`. `-mcpu=5307` rejects all five. So the assembler agrees
##   with the manual on four of the five Revision B compare forms and
##   contradicts it on the fifth. Table 2-7 and Table 2-8 both say CMPA has a
##   word form; binutils says it does not. Nothing in this repository settles
##   which is right, and nothing in this repository depends on the answer -
##   the encoding traps either way. A reader who needs CMPA.W must settle it
##   against silicon or an erratum, not against this comment.
##
##   Scc is a byte. Table 2-8, folio 2-22, gives `Scc Dx` an operand size of
##   `.B` and the operation "If Condition True, Then 1's -> Destination; Else
##   0's -> Destination", so the write replaces the low byte of the data
##   register and leaves the other three alone. That is `mergeSized` in
##   `machine.nim`, which `eaWrite` already applies.
##
##   TST keeps all three sizes. Table 2-8, folio 2-22, gives it `.B,.W,.L`, and
##   Table 2-14, "One-Operand Instruction Execution Times", folio 2-27, carries
##   a `tst.b` row, a `tst.w` row and a `tst.l` row, each timed under every one
##   of the eight effective-address columns with no dash anywhere.
##   `m68k-elf-as -mcpu=5407` agrees: `tst.b %d0` is `4a00`, `tst.w %d0` is
##   `4a40` and `tst.l #5` is `4abc 0000 0005`.
##
##   Branches carry a displacement and not an operand size, and ON THIS PART it
##   is 8, 16 or 32 bits.
##
## A `Bcc` with an 8-bit displacement of 0xFF still traps, AND THE REASON IS NO
## LONGER THAT THE PART LACKS THE FORM.
##
##   The manual. Table 2-8, folio 2-20, gives `Bcc <label>`, `BRA <label>` and
##   `BSR <label>` an operand size of `.B,.W,.L`. Section 2.9, "ColdFire
##   Instruction Set Architecture Enhancements", prints a page per Revision B
##   instruction with a per-core presence table, and Bcc's, on folio 2-37,
##   reads `Opcode present: V2, V3 Core - Yes; V4 Core - Yes` with
##   `Operand sizes supported: V2, V3 Core - .b, .w; V4 Core - .b, .w, .l`.
##   THIS IS A V4. That page also states the marker this decoder reads: "If the
##   8-bit displacement field is 0, a 16-bit displacement (the word after the
##   instruction) is used. If the 8-bit displacement field is 0xFF, the 32-bit
##   displacement (longword after the instruction) is used."
##
##   The assembler agrees. `m68k-elf-as -mcpu=5407` accepts `bra.l` (`60ff
##   0000 0004`), `bsr.l` (`61ff 0000 0004`) and `beq.l` (`67ff 0000 0004`),
##   and `-mcpu=5307` rejects all three. Measured, both directions.
##
##   So the trap is this core declining to implement a form the part has, in
##   exactly the way it declines TAS. `decode.nim` decodes the word so that the
##   refusal says "this core does not implement the 32-bit branch" rather than
##   "there is no such instruction", and that distinction is now the only thing
##   the trap communicates.
##
##   The disassembler still disagrees and it is still not evidence.
##   `m68k-elf-objdump -m m68k:5307` prints `60ff` as `bras 1` - an ordinary
##   byte branch of -1, to an odd address - while `-m m68k:68020` prints the
##   same bytes as `bral`. That is the disassembler declining to model the
##   marker, the same laxity that makes it print `4690` as `notl %d0` though
##   that word's low six bits are an address-register indirect (see
##   `logic.nim`).
##
## The condition codes, and where each rule comes from.
##
##   Bcc, BRA, BSR, JMP, JSR, Scc, RTS
##       No condition code at all. Table 2-8's operation column for each of
##       them names the program counter, the stack pointer or the destination
##       and no flag. `Bcc` and `Scc` read the condition codes and write none.
##
##   TST
##       "Set Integer Condition Codes" (Table 2-8, folio 2-22) at the operand
##       size: N and Z from the operand, V and C cleared, X untouched. Section
##       2.2.1.5, "Condition Code Register (CCR)", folio 2-9, introduces the
##       bits and Table 2-1, "CCR Field Descriptions", folio 2-10, defines each
##       one: V is set "if an arithmetic overflow occurs" and C "if a carry-out
##       of the data operand msb occurs for an addition or if a borrow occurs
##       in a subtraction", and a test is neither. That is `setNzClearVc`,
##       which `machine.nim` already holds for MOVE.
##
##   CMP, CMPA, CMPI
##       A subtraction with the result discarded. Table 2-8, folio 2-20, reads
##       "Destination - Source" for CMP and for CMPA, and "Destination -
##       Immediate Data" for CMPI. N and Z from the difference, V the signed
##       overflow, C the borrow, and X not written. CFPRM folio 4-28 gives
##       CMP's X as "Not affected".
##
##   RTE
##       The status register is reloaded from the frame and computed from
##       nothing.
##
##   TRAP
##       Section 2.8, "Exception Processing Overview", folio 2-31: the
##       processor copies SR, then sets the S-bit
##       and clears the T-bit. `machine.nim`'s `takeException` carries it.
##
## Cycles. The numbers are not a transcription of the tables. See the block
## above the constants in `cpu.nim`.
##
##   Exact - a row carrying a SINGLE cell that the one return equals, so no
##   effective address can pull them apart. `execScc` returns 1 and MCF5407
##   User's Manual Table 2-14, "One-Operand Instruction Execution Times", folio
##   2-27, gives `scc Dx` 1(0/0); `execTrap` returns 18 and Table 2-16,
##   "Miscellaneous Instruction Execution Times", folio 2-29, gives
##   `trap #imm` 18(1/2).
##
##   `execRte` returns 15, which Table 2-17, "Branch Instruction Execution
##   Times", folio 2-30, gives `rte` as 15(2/0). IT RETURNED 14 WHILE THE
##   TARGET WAS AN MCF5307, whose Table 3-15 read 14(2/0). The number moved
##   because the part moved, and this is one of the few cells in this group
##   that did.
##
##   `execRts` returns 8 and is NO LONGER a single cell. Table 2-17 gives `rts`
##   three times, selected by the V4's hardware return stack: 2(1/0) if the
##   return is predicted correctly, 9(1/0) if it is mispredicted, and 8(1/0) if
##   it is not predicted at all. THIS CORE MODELS NO RETURN STACK, so the
##   not-predicted cell is the one that describes it and 8 is kept for that
##   reason rather than by inheritance. The MCF5307 had one `rts` cell and it
##   was 8(1/0), so the return is unchanged and its justification is not.
##
##   The rest are flattened across the effective address. `execJump` returns 5
##   for every operand; Table 2-17 gives `jmp`/`jsr` 5 for `(An)` and
##   `(d16,An)` but 6 for the indexed forms and 1 for `xxx.wl` - 1(0/0) for
##   `jmp` and 1(0/1) for `jsr`, whose extra write is the return address.
##
##   `execTst` returns 1 for every operand, and on this part that is nearly the
##   whole table rather than a flattening of it. Table 2-14 gives all three
##   `tst` rows - `tst.b`, `tst.w` and `tst.l` alike - 1(0/0) under `Rn`,
##   1(1/0) under `(An)`, `(An)+`, `-(An)`, `(d16,An)` and `xxx.wl`, 1(0/0)
##   under `#xxx`, and 2(1/0) under `(d8,An,Xi*SF)` alone. The one return
##   therefore equals every cell except the indexed one.
##
##   IT USED TO RETURN 1 FOR A REGISTER AND 3 OTHERWISE, and the split is gone
##   because the V4 removed the thing it was modelling. On the MCF5307 the
##   register and memory cells genuinely differed - Table 3-12 read 3(1/0) for
##   `tst.l` on the memory modes and 4(1/0) for `tst.b` and `tst.w` on those
##   same five - so a two-valued return said something true. On the V4 the
##   memory modes cost what the register costs and the size no longer changes
##   the cell, so keeping the split would model a distinction the part does not
##   make.
##
##   `execCompare` returns 1 for all three comparisons, and that also fits this
##   part better than it fitted the last one. Table 2-15, "Two Operand
##   Instruction Execution Times", folio 2-27, gives `cmp.l <ea>,Rx` 1(0/0)
##   under `Rn` and `#xxx`, 1(1/0) under `(An)`, `(An)+`, `-(An)`, `(d16,An)`
##   and `xxx.wl`, and 2(1/0) under `(d8,An,Xi*SF)`; `cmpi.l #imm,Dx` has the
##   single cell 1(0/0). The MCF5307's row read 4(1/0) and 5(1/0) on those
##   memory modes, so the same return that named two cells there names ten
##   here.
##
##   CMPA has no row in Table 2-15, on any of folios 2-27 to 2-29, so its
##   number is invented outright rather than flattened out of a row; `alu.nim`
##   records the same absence for ADDA and SUBA.
##
##   The branch returns sit in no cell on either part. `execBranch` returns 3
##   for BSR and 2 for BRA and Bcc. Table 2-17 gives `bra` and `bsr` a single
##   cell each, both 1(0/1) under `(d16,An)`, each superscripted with note 1,
##   "Assumes branch acceleration", and dashes every other column.
##
##   BCC IS TIMED BY A DIFFERENT TABLE HERE, AND IT IS NOT THE MCF5307'S TABLE
##   RENUMBERED. The V4 adds a branch cache, so Table 2-18, "Bcc Instruction
##   Execution Times", folio 2-30, has FOUR columns where the MCF5307's Table
##   3-17 had three: `bcc` reads 0(0/0) when the branch cache correctly
##   predicts taken, 1(0/0) when the prediction table correctly predicts taken,
##   1(0/0) when it is predicted correctly as not taken, and 8(0/0) when it is
##   predicted incorrectly. The mispredict penalty was 5(0/0) on the MCF5307
##   and the zero-cost branch-cache hit did not exist there at all.
##
##   Neither 3 nor 2 is any of those numbers, and nothing here models a branch
##   cache or a prediction table, so there is no cell to choose. The returns
##   are left where they are and this paragraph is the reason they are not
##   presented as sourced.
##
##   A table's rows and its notes can end on different pages, and a second
##   table on the same subject can follow the notes.
##
## Questions settled against the ColdFire Family Programmer's Reference
## Manual, Rev. 3, whose per-instruction folios give the flag rules and the
## condition tests directly.
##
##   The sixteen condition tests. CFPRM folio 4-13, under `Bcc`, prints the
##   whole table: code, four-bit encoding and boolean test, over CCR[C],
##   CCR[N], CCR[V] and CCR[Z]. It agrees with the M68000 family definition
##   this module implements and with the encodings measured from
##   `m68k-elf-as -mcpu=5407` (`bhi` 0x62, `bls` 0x63, `bcc` 0x64, `bcs` 0x65,
##   `bne` 0x66, `beq` 0x67, `bvc` 0x68, `bvs` 0x69, `bpl` 0x6a, `bmi` 0x6b,
##   `bge` 0x6c, `blt` 0x6d, `bgt` 0x6e, `ble` 0x6f, `st` 0x50c0, `sf` 0x51c0).
##   The User's Manual settles none of it: it gives the condition-code bits in
##   section 2.2.1.5 and Table 2-1, folios 2-9 and 2-10, names the wildcard
##   `cc` as "Logical Condition (example: NE for not equal)" in Table 2-6,
##   "Notational Conventions", folio 2-16, and prints no table of the tests
##   anywhere. Section 2.9's per-instruction Bcc page, folio 2-37, does print a
##   condition table, but it is a list of the sixteen MNEMONICS against their
##   English names and carries neither the encodings nor the boolean tests, so
##   it does not settle this either.
##
##   Whether a comparison writes X. It does not. CFPRM folio 4-28 gives CMP's
##   X as "Not affected".
##
##   THE MCF5407 MANUAL REMOVED THE TYPESETTING DEFECT THAT CREATED THE DOUBT,
##   without removing the doubt. On the MCF5307 the X rule appeared as an
##   unattached sentence at the end of section 3.2.1.5, page 3-9, printed where
##   it read as a floating remark. Here it is a labelled row of Table 2-1,
##   folio 2-10: "X - Extend condition code bit. Assigned the value of the
##   carry bit for arithmetic operations; otherwise not affected or set to a
##   specified result." The row is unambiguous about WHICH bit it describes and
##   still does not say whether a comparison counts as an arithmetic operation,
##   and a comparison is a subtraction. Read the wide way every CMP would write
##   X and would break a multi-precision sequence that compared between its
##   steps. The CFPRM folio remains the authority.
##
## What this module still does not know. The implementation picks a behaviour
## and this list says so.
##
##   1. The exact cycle count of every instruction in this group. `cpu.nim`
##      states the mechanism once, above its cycle constants.
##
##   2. What an `RTE` with a bad format field should do. Table 2-22, "MCF5407
##      Exceptions", folio 2-35, carries an "RTE and Format Error Exceptions"
##      row that is unambiguous: "any attempted execution of an RTE where the
##      format is not equal to {4,5,6,7} generates a format error", and Table
##      2-19, folio 2-32, places that at vector 14 with a stacked program
##      counter of "Fault" - the address of the RTE itself. This module traps instead, because a trap is this
##      core's one observable for "the core refused", the same channel every
##      illegal size and illegal operand in every group uses; `alu.nim`'s
##      header makes the identical statement about a divide by zero.

import mcf5307/decode_types
import mcf5307/ea
import mcf5307/machine

# ---------------------------------------------------------------------------
# Trapping.

proc trap(ctx: MCF5307Ctx): uint32 =
  ## Halt the context with `fault`. Every illegal size, illegal operand mode,
  ## 32-bit branch displacement and malformed exception frame in this module
  ## ends here, so that "the core refused" is one observable and not several.
  ctx.fault = true
  ctx.halted = true
  0'u32

# ---------------------------------------------------------------------------
# The condition table.

proc conditionHolds(sr: uint32; cond: uint8): bool =
  ## The sixteen logical conditions, over the condition-code bits of `sr`.
  ##
  ## Conditions 0 and 1 are reached through `Scc` alone. In a branch word the
  ## same two fields are BRA and BSR - `0110 0000` and `0110 0001` - and
  ## `decode.nim` turns those into `opBra` and `opBsr` before this procedure is
  ## consulted, so `Bt` and `Bf` do not exist and `execBranch` never asks.
  let c = (sr and ccrC) != 0'u32
  let v = (sr and ccrV) != 0'u32
  let z = (sr and ccrZ) != 0'u32
  let n = (sr and ccrN) != 0'u32
  case cond and 0xF'u8
  of 0: true                            # T   always
  of 1: false                           # F   never
  of 2: (not c) and (not z)             # HI  unsigned greater than
  of 3: c or z                          # LS  unsigned less or equal
  of 4: not c                           # CC  carry clear
  of 5: c                               # CS  carry set
  of 6: not z                           # NE  not equal
  of 7: z                               # EQ  equal
  of 8: not v                           # VC  overflow clear
  of 9: v                               # VS  overflow set
  of 10: not n                          # PL  plus
  of 11: n                              # MI  minus
  of 12: n == v                         # GE  signed greater or equal
  of 13: n != v                         # LT  signed less than
  of 14: (not z) and (n == v)           # GT  signed greater than
  else: z or (n != v)                   # LE  signed less or equal

# ---------------------------------------------------------------------------
# The condition codes of a comparison.

proc setCompareCc(ctx: MCF5307Ctx; src, dst, res: uint32; borrow: bool) =
  ## N and Z from the difference, V the signed overflow, C the borrow, and X
  ## left alone.
  ##
  ## The overflow expression is the one `alu.nim`'s `setSubCc` uses, written
  ## out again here rather than imported: that procedure is private to
  ## `alu.nim`. The two differ in exactly one line - `setSubCc` writes X and
  ## this does not.
  let overflow = ((src xor dst) and (dst xor res) and 0x80000000'u32) != 0'u32
  var sr = ctx.sr and not (ccrN or ccrZ or ccrV or ccrC)
  if (res and 0x80000000'u32) != 0'u32: sr = sr or ccrN
  if res == 0'u32: sr = sr or ccrZ
  if overflow: sr = sr or ccrV
  if borrow: sr = sr or ccrC
  ctx.sr = sr

# ---------------------------------------------------------------------------
# BRA, BSR and Bcc.

proc execBranch(ctx: MCF5307Ctx; word: uint16; d: Decoded;
                insnPc: uint32): uint32 =
  ## One branch. `d.size` carries the FORM the decoder read out of the
  ## displacement byte: 1 is the byte displacement in the opcode word, 2 the
  ## 16-bit displacement in the word after it, and 4 the 32-bit form that this
  ## part does not have.
  ##
  ## The base is the address of the word after the opcode, for both forms, and
  ## it is measured: `bra.b .+8` assembles to `6006` and
  ## `bra.w .+0x2000` to `6000 1ffe`, so in each the displacement is the
  ## target minus (the opcode's address + 2). `ctx.pc` is exactly that address
  ## on entry - `step` advanced it past the opcode word and nothing else - and
  ## it is taken into a local BEFORE `fetchExt` moves it, the same way
  ## `eaAddr` takes its PC-relative base.
  ##
  ## The extension word is consumed whether or not the branch is taken. A
  ## not-taken 16-bit branch must leave the program counter after BOTH words,
  ## and a core that consumed the word only on the taken path would resume
  ## inside its own displacement.
  if d.size == 4'u8:
    return trap(ctx)
  let base = ctx.pc
  var target: uint32
  if d.size == 1'u8:
    target = base + uint32(s8(word))
  else:
    target = base + uint32(s16(fetchExt(ctx)))
    if ctx.halted:
      return 0'u32
  if d.op == opBsr:
    # "SP - 4 -> SP; PC -> (SP); PC + dn -> PC" - Table 2-8, folio 2-20. The
    # pushed value is the address after the whole instruction, so the byte
    # form pushes two bytes on and the word form four.
    ctx.sp = ctx.sp - 4'u32
    writeMem(ctx, ctx.sp, 4, ctx.pc)
    if ctx.halted:
      return 0'u32
  if d.op != opBcc or conditionHolds(ctx.sr, d.destReg):
    transferControl(ctx, target, insnPc)
    if ctx.halted:
      return 0'u32
  # NEITHER 2 NOR 3 HAS A SOURCE ON THIS PART, AND THE JUSTIFICATION THEY USED
  # TO HAVE IS GONE RATHER THAN MOVED. No cell of Table 2-17 or Table 2-18
  # carries 2 or 3, and neither do the notes: Table 2-17's four notes on folio
  # 2-30 read "Assumes branch acceleration" and the three hardware-return-stack
  # conditions, and Table 2-18 carries none.
  #
  # The MCF5307 manual DID document a range these two numbers sat inside - its
  # notes said the branch-acceleration decoupling makes the execution time
  # "vary from 1 to 3 cycles", and a second sentence said the same of Bcc's
  # predicted-correctly-as-taken column. The MCF5407 manual prints no such
  # sentence anywhere; searched for both wordings across the whole extraction
  # and found them in the MCF5307 text alone.
  #
  # So these are now this core's own numbers with nothing behind them, which is
  # what the header says and is why they were not changed to imitate a cell.
  if d.op == opBsr: 3'u32 else: 2'u32

# ---------------------------------------------------------------------------
# Scc.

proc execScc(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## `Scc Dx`: ones or zeros into the LOW BYTE of a data register.
  ##
  ## The write goes through `eaWrite`, which applies `mergeSized`, so the other
  ## three bytes of the register survive.
  ##
  ## The operand mask is `{Dn}`, and it is what refuses the 68000 `DBcc` word -
  ## `0101 cccc 11 001 rrr`, which is no instruction at all on this part. See
  ## the `opScc` entry in `decode_types.nim`.
  if not eaIsLegalFor(opScc, d.ea):
    return trap(ctx)
  let value = if conditionHolds(ctx.sr, d.destReg): 0xFF'u32 else: 0x00'u32
  eaWrite(ctx, d.ea, 1, value)
  if ctx.halted:
    return 0'u32
  1'u32

# ---------------------------------------------------------------------------
# TST.

proc execTst(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## `TST.<sz> <ea>`: set N and Z from the operand, clear V and C, leave X.
  ##
  ## A byte operand may not be an address register, and that is a rule about
  ## the size rather than the mode. `m68k-elf-as -mcpu=5407` accepts
  ## `tst.w %a0` (`4a48`) and `tst.l %a0` (`4a88`) and rejects `tst.b %a0`.
  ## The legality table in `decode_types.nim` is keyed on the operation alone
  ## and cannot express a size-dependent mode, exactly as it cannot express
  ## ADD's direction-dependent destination mask, so the rule is here.
  ##
  ## The manual does not separate them. Table 2-14's three `tst` rows on folio
  ## 2-27 carry a time under a column headed `Rn`, and Table 2-6 on folio 2-16
  ## defines `Rn` as "Any Address or Data Register" - so that column cannot
  ## say which of the two a given size admits. The `clr.b` row above uses the
  ## same heading and `m68k-elf-as -mcpu=5407` rejects `clr.b %a0` at every
  ## size, so the column is not evidence either way and the assembler is the
  ## authority here.
  if not eaIsLegalFor(opTst, d.ea):
    return trap(ctx)
  if d.ea.mode == eaAn and d.size == 1'u8:
    return trap(ctx)
  let value = eaRead(ctx, d.ea, d.size)
  if ctx.halted:
    return 0'u32
  setNzClearVc(ctx, value, d.size)
  1'u32

# ---------------------------------------------------------------------------
# CMP, CMPA and CMPI.

proc execCompare(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## One comparison. The difference is computed and discarded; only the
  ## condition codes survive.
  ##
  ## The size and the operand are checked before any extension word is
  ## fetched: a core that consumed the words of an instruction it then refused
  ## would leave the program counter somewhere the instruction stream does not
  ## begin.
  ##
  ## This is where CMPA.W dies. `decode.nim` gives line 1011 opmode 011 a size
  ## of 2 so that it arrives here and is refused on the size, rather than
  ## coming back as an unrecognised word that says nothing about why.
  if d.size != 4'u8:
    return trap(ctx)
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  var src, dst: uint32
  if d.op == opCmpi:
    # The immediate is the two words after the opcode, high half first. The
    # same order `eaRead` uses for `ea7Imm` and `logic.nim` for ANDI, ORI and
    # EORI; `m68k-elf-as -mcpu=5407` emits `0c80 1234 5678` for
    # `cmpi.l #0x12345678,%d0`.
    let hi = fetchExt(ctx)
    let lo = fetchExt(ctx)
    if ctx.halted:
      return 0'u32
    src = (uint32(hi) shl 16) or uint32(lo)
    dst = regD(ctx, d.ea.reg)
  else:
    src = eaRead(ctx, d.ea, 4)
    if ctx.halted:
      return 0'u32
    dst = if d.op == opCmpa: regA(ctx, d.destReg) else: regD(ctx, d.destReg)
  let res = dst - src
  setCompareCc(ctx, src, dst, res, dst < src)
  1'u32

# ---------------------------------------------------------------------------
# JMP and JSR.

proc execJump(ctx: MCF5307Ctx; d: Decoded; insnPc: uint32): uint32 =
  ## `JMP <ea>` and `JSR <ea>`. The operand is a CONTROL address and the
  ## instruction jumps to the ADDRESS ITSELF and never to what is at it -
  ## Table 2-8, folio 2-20, gives JMP as "Address of <ea> -> PC".
  ##
  ## The effective address is evaluated before the return address is pushed,
  ## and that ordering is the whole of what makes `jsr 0x00054320` different
  ## from `jsr (%a0)`. `eaAddr` consumes the operand's extension words, so
  ## `ctx.pc` afterwards is the address after the whole instruction, which is
  ## what "SP - 4 -> SP; PC -> (SP)" (Table 2-8, folio 2-20) means by PC. A
  ## core that pushed before evaluating would push the address of its own
  ## extension words and return into them.
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  let target = eaAddr(ctx, d.ea, 4)
  if ctx.halted:
    return 0'u32
  if d.op == opJsr:
    ctx.sp = ctx.sp - 4'u32
    writeMem(ctx, ctx.sp, 4, ctx.pc)
    if ctx.halted:
      return 0'u32
  transferControl(ctx, target, insnPc)
  if ctx.halted:
    return 0'u32
  5'u32

# ---------------------------------------------------------------------------
# RTS and RTE.

proc execRts(ctx: MCF5307Ctx; insnPc: uint32): uint32 =
  ## "(SP) -> PC; SP + 4 -> SP" - Table 2-8, folio 2-22. The pop is read BEFORE
  ## the stack pointer moves, and the pointer moves only when the read
  ## succeeded.
  let target = readMem(ctx, ctx.sp, 4)
  if ctx.halted:
    return 0'u32
  ctx.sp = ctx.sp + 4'u32
  transferControl(ctx, target, insnPc)
  if ctx.halted:
    return 0'u32
  8'u32

proc execRte(ctx: MCF5307Ctx; insnPc: uint32): uint32 =
  ## The inverse of `takeException`.
  ##
  ## The format field is validated first. Table 2-22's "RTE and Format Error
  ## Exceptions" row, folio 2-35: the
  ## processor "first examines the 4-bit format field to validate the frame
  ## type", and "any attempted execution of an RTE where the format is not
  ## equal to {4,5,6,7} generates a format error". This core traps instead of
  ## taking vector 14; that is unknown 2 in this module's header.
  ##
  ## The stack pointer is `SP + 4 + format` and not `SP + 8`. The same section
  ## says the processor "adjusts the stack pointer by adding the format value
  ## to the auto-incremented address after the fetch of the first longword",
  ## which is SP + 4 plus 4, 5, 6 or 7. That is the inverse of Table 2-20 on
  ## folio 2-33, whose four rows put the handler's A7 at the original A7 minus
  ## 8, 9, 10 or 11. A core that added a fixed 8 restores the wrong pointer
  ## for three of the four frames a misaligned stack produces.
  ##
  ## THE MISPRINT THIS PARAGRAPH USED TO WARN ABOUT IS NOT IN THIS MANUAL. The
  ## MCF5307's Table 3-7 gave `RTE` an operation of "SP + 8 -> PC", which was
  ## wrong twice over - the program counter has just been loaded from (SP+4),
  ## and the row would overwrite it with an address on the stack. The MCF5407's
  ## Table 2-9, "Supervisor-Level Instruction Set Summary", folio 2-23, prints
  ## the row correctly: "(SP+2) -> SR; SP+4 -> SP; (SP) -> PC;
  ## SP + formatfield -> SP". That is the rule this procedure already followed,
  ## so the code does not move; only the reason for distrusting the summary
  ## table does.
  let first = readMem(ctx, ctx.sp, 4)
  if ctx.halted:
    return 0'u32
  let format = (first shr 28) and 0xF'u32
  if format < 4'u32 or format > 7'u32:
    return trap(ctx)
  let target = readMem(ctx, ctx.sp + 4'u32, 4)
  if ctx.halted:
    return 0'u32
  ctx.sr = first and 0xFFFF'u32
  ctx.sp = ctx.sp + 4'u32 + format
  transferControl(ctx, target, insnPc)
  if ctx.halted:
    return 0'u32
  15'u32

# ---------------------------------------------------------------------------
# TRAP.

proc execTrap(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## `TRAP #<vector>`, the four-bit field in the low bits of the opcode.
  ##
  ## THE VECTOR NUMBER IS 32 PLUS THE FIELD. MCF5407 User's Manual Table 2-19,
  ## "Exception Vector Assignments", folio 2-32: vector numbers 32 to 47, at
  ## vector offsets $080 to $0BC, are the "Trap # 0-15 instructions".
  ##
  ## THE STACKED PROGRAM COUNTER IS THE *NEXT* INSTRUCTION AND NOT THIS ONE.
  ## The same table's stacked-program-counter column reads "Next" for those
  ## vectors, and its footnote defines Next as "the PC of the next instruction
  ## that follows the instruction that caused the fault". `ctx.pc` is already
  ## that address:
  ## `step` advanced it past the opcode word and TRAP has no extension words.
  ## The address error stacks the FAULT address instead, which is why the
  ## branch and jump executors carry `insnPc` and this one does not: `ctx.pc`
  ## is the wrong value for that vector and the right one for these.
  takeException(ctx, 32'u8 + (d.destReg and 0xF'u8), ctx.pc)
  if ctx.halted:
    return 0'u32
  18'u32

# ---------------------------------------------------------------------------
# The dispatch entry `step` calls.

proc controlFamily*(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one control-flow or comparison instruction. Called from `step` in
  ## `mcf5307/cpu` with the opcode word and the decoded operation. Returns a
  ## placeholder cycle count excluding the fetch - see the cycle block in
  ## `cpu.nim` - and halts the context with `fault` set on an illegal size, an
  ## illegal effective address, a 32-bit branch displacement or an exception
  ## frame whose format field is not one of the four the part writes.
  # THE ADDRESS OF THE OPCODE WORD, WHICH THE EXECUTORS CANNOT RECOVER FOR
  # THEMSELVES. `step` has advanced `ctx.pc` past the opcode and nothing else
  # yet, so it is one instruction word back from here - but an executor that
  # has consumed an extension word can no longer say that, and each of the four
  # below needs it for the address error's stacked program counter.
  let insnPc = ctx.pc - insWordBytes
  case d.op
  of opBra, opBsr, opBcc: execBranch(ctx, word, d, insnPc)
  of opScc: execScc(ctx, d)
  of opTst: execTst(ctx, d)
  of opCmp, opCmpa, opCmpi: execCompare(ctx, d)
  of opJmp, opJsr: execJump(ctx, d, insnPc)
  of opRts: execRts(ctx, insnPc)
  of opRte: execRte(ctx, insnPc)
  of opTrap: execTrap(ctx, d)
  else: trap(ctx)
