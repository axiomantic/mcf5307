## `control` - the control-flow and comparison instruction group of the
## ColdFire ISA_A core. Task CPU-10 creates this file. Design section 6.1.
##
## This module executes Bcc, BRA, BSR, JMP, JSR, RTS, RTE, Scc, TST, CMP,
## CMPA, CMPI and TRAP, AND NOTHING ELSE. NOP has no work to do and `cpu.nim`
## answers it without entering this module. The register file, the board
## accesses, the effective-address evaluation and the exception frame are
## `mcf5307/machine`'s.
##
## THIS MODULE IS A SIBLING OF `move.nim`, `alu.nim`, `logic.nim` AND
## `decode.nim`. It imports none of them and none of them imports it; its whole
## import list is `{decode_types, ea, machine}`. Adding this group cost one new
## module, one `import` line in `cpu.nim` and one arm of the `case` there, and
## `decode.nim` gained the opcodes and NO import. The rule and the reason are
## in `~/Desktop/avoiding-cycles.md`: an executor that reaches into another
## executor for a helper rebuilds the decoder-under-executor cycle one layer
## down, and a shape that is merely awkward at two siblings is unworkable at
## five. The one helper this group needed that no earlier group had - the
## exception stack frame - went DOWN into `machine.nim`, where CPU-14's
## `exception.nim` will be able to reach it as a sibling.
##
## THE SIZES, AND THE ONE INSTRUCTION THAT KEEPS ALL THREE.
##
##   CMP, CMPA, CMPI are 32-BIT AND THERE IS NO OTHER SIZE. MCF5307 User's
##   Manual Table 3-7, "Instruction Set Summary", page 3-23, gives all three an
##   OPERAND SIZE column of `32` alone. `m68k-elf-as -mcpu=5307` rejects
##   `cmp.b`, `cmp.w`, `cmpa.w`, `cmpi.b` and `cmpi.w`, and
##   `m68k-elf-objdump -m m68k:5307` decodes `b2c0` - which is `cmpaw %d0,%a1`
##   under `-m m68k:68020` - as `.short 0xb2c0`. Every byte and word form
##   TRAPS here.
##
##   Scc IS A BYTE. Table 3-7, page 3-25, gives `Scc Dx` an OPERAND SIZE of 8
##   and the operation "If Condition True, Then 1's -> Destination; Else 0's ->
##   Destination", so the write REPLACES THE LOW BYTE of the data register and
##   leaves the other three alone. That is `mergeSized` in `machine.nim`, which
##   `eaWrite` already applies.
##
##   TST KEEPS ALL THREE SIZES, and it is the only instruction in this group
##   that does. Table 3-7, page 3-25, gives it "8,16,32", and Table 3-12, "One
##   Operand Instruction Execution Times", page 3-27, carries a `tst.b` row, a
##   `tst.w` row AND a `tst.l` row, each timed under every one of the eight
##   effective-address columns with no dash anywhere. `m68k-elf-as -mcpu=5307`
##   agrees: `tst.b %d0` is `4a00`, `tst.w %d0` is `4a40` and `tst.l #5` is
##   `4abc 0000 0005`.
##
##   BRANCHES CARRY A DISPLACEMENT AND NOT AN OPERAND SIZE, and it is 8 or 16
##   bits. See the block on the 32-bit displacement below.
##
## A `Bcc` WITH AN 8-BIT DISPLACEMENT OF 0xFF MUST TRAP, AND THAT IS THE ONE
## SENTENCE CPU-10'S PLAN ROW WRITES IN BOLD.
##
##   THE MANUAL. Table 3-7, page 3-23, gives `Bcc <label>`, `BRA <label>` and
##   `BSR <label>` an OPERAND SIZE column of "8,16" AND NO THIRD VALUE. A
##   displacement byte of 0x00 selects the 16-bit form and a byte of 0xFF
##   selects the 32-bit one; the 32-bit one is ISA_B and this part is ISA_A.
##
##   THE ASSEMBLER. `m68k-elf-as` REJECTS `bra.l`, `beq.l` and `bsr.l` under
##   `-mcpu=5307` and ACCEPTS all three under `-m68020`, where `bra.l`
##   assembles to `60ff 0000 0008`. So 0xFF is the marker, and the ColdFire
##   tables of the same assembler refuse it.
##
##   THE DISASSEMBLER DISAGREES AND IT IS NOT EVIDENCE.
##   `m68k-elf-objdump -m m68k:5307` prints `60ff` as `bras 1` - an ordinary
##   byte branch of -1, to an ODD address - while `-m m68k:68020` prints the
##   same bytes as `bral`. That is the disassembler declining to model the
##   marker, the same laxity that makes it print `4690` as `notl %d0` though
##   that word's low six bits are an address-register indirect (see
##   `logic.nim`). `tests/t_control.nim` asserts the trap for all three of
##   BRA, Bcc and BSR, and asserts a displacement of 0xFE and one of 0x00 as
##   the controls that keep it from becoming "every branch traps".
##
## THE CONDITION CODES, AND WHERE EACH RULE COMES FROM.
##
##   Bcc, BRA, BSR, JMP, JSR, Scc, RTS
##       NO CONDITION CODE AT ALL. Table 3-7's OPERATION column for each of
##       them names the program counter, the stack pointer or the destination
##       and no flag. `Bcc` and `Scc` READ the condition codes and write none.
##
##   TST
##       "Set Integer Condition Codes" (Table 3-7, page 3-25) at the operand
##       size: N and Z from the operand, V and C cleared, X UNTOUCHED. Section
##       3.2.1.5 STARTS on page 3-8 and defines the individual bits on page
##       3-9, where V is an ARITHMETIC overflow and C is a carry out of an
##       addition or a borrow in a subtraction, and a test is neither. That is
##       exactly `setNzClearVc`, which `machine.nim` already holds for MOVE and
##       which this module calls rather than write a second copy.
##
##   CMP, CMPA, CMPI
##       A SUBTRACTION WITH THE RESULT DISCARDED. Table 3-7, page 3-23, reads
##       "Destination - Source" for CMP and for CMPA, and "Destination -
##       Immediate Data" for CMPI, which is the same operation named for the
##       only source CMPI can have. N and Z from the difference, V the signed
##       overflow, C the borrow, and X NOT WRITTEN. The X rule is uncertainty
##       2 below.
##
##   RTE
##       The status register is RELOADED from the frame and computed from
##       nothing.
##
##   TRAP
##       Section 3.3, page 3-11: the processor copies SR, then sets the S-bit
##       and clears the T-bit. `machine.nim`'s `takeException` carries it.
##
## CYCLES ARE NOMINAL, for the reason `move.nim`, `alu.nim`, `logic.nim` and
## `cpu.nim` all give: the per-instruction budget needs the clock work of open
## question 6 in AGENTS.md and no exact cost is asserted anywhere. Uncertainty
## 3 below gives the mechanism: `Outcome.cycles` is the return of
## `mcf5307_exec(ctx, 1)`, which SATURATES at its budget, so it reports 1 for an
## instruction that ran and 0 for one that trapped and CANNOT SEE A COUNT AT
## ALL. Every number in this module is therefore a PLACEHOLDER, and nothing in
## the tree would notice if it were wrong.
##
## THEY ARE NOT A TRANSCRIPTION OF THE TABLES, and this header used to say they
## were. Read on the rendered pages, against what the code returns:
##
##   THE BRANCH NUMBERS ARE IN NO TABLE AT ALL. `execBranch` returns 3 for BSR
##   and 2 for BRA and Bcc. Table 3-16, page 3-30, gives `bra` 1(0/0) taken in
##   either direction and `Bcc` 5(0/0) or 1(0/0) depending on whether the static
##   prediction held; Table 3-15, page 3-30, gives `bsr` 1(0/1). NEITHER 2 NOR 3
##   APPEARS IN EITHER TABLE. They are invented, and the inline comment at the
##   foot of `execBranch` is the honest one.
##
##   THE EA-DEPENDENT ONES ARE FLATTENED, and there are THREE of them.
##   `execJump` returns 5 for every effective address; Table 3-15 gives
##   `jmp`/`jsr` 5 for `(An)` and `(d16,An)` but 6 for the indexed forms and 1
##   for `xxx.wl` - 1(0/0) for `jmp` and 1(0/1) for `jsr`, whose extra write is
##   the return address. `execTst` returns 1 for a register and 3 otherwise,
##   and the flat 3 matches FIVE of the SEVEN non-register cells of the `tst.l`
##   row of Table 3-12 on page 3-27 - `(An)`, `(An)+`, `-(An)`, `(d16,An)` and
##   `xxx.wl` are each 3(1/0) - but NOT the whole row: `(d8,An,Xi*SF)` is
##   4(1/0) and `#xxx` is 1(0/0). `tst.b` and `tst.w` on `(An)` are 4(1/0)
##   there too. `execCompare` returns 1 for all three comparisons; Table 3-13,
##   "Two Operand Instruction Execution Times", page 3-28, gives `cmpi.l
##   #imm,Dx` ONE cell and it is 1(0/0), so the flat 1 is exact for CMPI, but
##   its `cmp.l <ea>,Rx` row is 1(0/0) under `Rn` and `#xxx` ALONE and reads
##   4(1/0) under `(An)`, `(An)+`, `-(An)`, `(d16,An)` and `xxx.wl` and 5(1/0)
##   under `(d8,An,Xi*SF)`. CMPA HAS NO ROW IN THAT TABLE at all, on either of
##   its pages 3-28 and 3-29, so CMPA's number is invented the way the branch
##   numbers are.
##
##   FOUR HAPPEN TO MATCH EXACTLY - four whose table row carries a SINGLE cell
##   and whose one return is that cell, which is why no effective address can
##   pull them apart the way it pulls `execJump`, `execTst` and `execCompare`
##   apart. It is worth saying so rather than overcorrecting: `execRts`
##   returns 8 and Table 3-15 gives `rts` 8(1/0);
##   `execRte` returns 14 and Table 3-15 gives `rte` 14(2/0); `execTrap`
##   returns 18 and Table 3-14, page 3-29, gives `trap #imm` 18(1/2). `execScc`
##   returns 1 and Table 3-12 gives `scc Dx` 1(0/0). A matching number is still
##   a placeholder - nothing measures it - but it was not invented.
##
## A plausible number is no worse than an invented one for a budget nothing
## checks. Uncertainty 3.
##
## WHAT THIS MODULE DOES NOT KNOW. Four things, and the rule for every one is
## the one `logic.nim` established: THE IMPLEMENTATION PICKS A BEHAVIOUR AND
## THIS LIST SAYS SO. The document that would settle numbers 1, 2 and 4 is the
## ColdFire Family Programmer's Reference Manual, whose per-instruction pages
## give the flag rules and the condition tests directly. AGENTS.md section 11
## names it and gives a download location for it. IT WAS NOT AVAILABLE WHEN
## THIS GROUP WAS WRITTEN - searched for by name and by content, and the only
## ColdFire document that search found was the MCF5307 User's Manual
## (MCF5307UM/AD) - and the network is closed, so it could not be fetched
## either. Both halves of that are why this list exists.
##
##   1. THE BOOLEAN TEST OF EACH OF THE SIXTEEN CONDITIONS. The four-bit
##      ENCODING is measured and is not in doubt: `m68k-elf-as -mcpu=5307` put
##      `bhi` at 0x62, `bls` at 0x63, `bcc` at 0x64, `bcs` at 0x65, `bne` at
##      0x66, `beq` at 0x67, `bvc` at 0x68, `bvs` at 0x69, `bpl` at 0x6a,
##      `bmi` at 0x6b, `bge` at 0x6c, `blt` at 0x6d, `bgt` at 0x6e and `ble`
##      at 0x6f, and `st` at 0x50c0 and `sf` at 0x51c0. THE TESTS THEMSELVES
##      ARE THE M68000 FAMILY DEFINITION AND NO DOCUMENT ON THIS MACHINE
##      STATES THEM. The User's Manual gives the condition-code BITS in
##      section 3.2.1.5 (pages 3-8 and 3-9) and names the wildcard `cc` as
##      "Logical Condition (example: NE for not equal)" in Table 3-6 (page
##      3-21), and it prints no table of the sixteen tests anywhere.
##
##      THIS ONE IS ASSERTED, and heavily, because a condition must be one
##      thing or another and a branch nothing measures is a branch nothing
##      holds. `tests/t_control.nim` runs all sixteen conditions over all
##      sixteen condition-code words, for `Bcc` and again for `Scc`, and
##      compares each against a LITERAL 16-bit vector. A future reader who
##      reverses one condition must change that vector, and the corpus cases
##      that sample it.
##
##   2. WHETHER A COMPARISON WRITES X. This module leaves X alone, which is
##      the M68000 Family rule for CMP, CMPA and CMPI. CUTTING THE OTHER WAY,
##      section 3.2.1.5 ENDS, on page 3-9, with the unattached sentence "Set
##      to the value of the C-bit for arithmetic operations; otherwise not
##      affected". That sentence is printed AFTER the C-bit paragraph and the
##      section's `X` bullet carries no text of its own, so it reads as the X
##      rule; and a comparison IS a subtraction. Read literally it would
##      have every CMP write X and would break a multi-precision sequence that
##      compared between its steps. The manual states it as a property of the
##      X BIT and not as a per-instruction rule, Table 3-7 gives CMP no flag
##      column at all, and this module follows the family rule.
##
##      THIS ONE IS ASSERTED TOO. Every CMP, CMPA and CMPI case in
##      `conformance/corpus/control_00.json` enters with X SET and expects it
##      SET, so a reader who reverses this reading must change all of them.
##
##   3. THE EXACT CYCLE COUNT of every instruction in this group. Nothing
##      asserts it, and `tests/t_control.nim`'s `cycles` field is not a
##      counter-case though its name reads like one: it is the return of
##      `mcf5307_exec(ctx, 1)`, which SATURATES at its budget, so the value is
##      1 for an instruction that ran and 0 for one that trapped and it cannot
##      see a count at all. `logic.nim`'s uncertainty 2 measured the same
##      thing for its own group by replacing all nine of its cycle returns
##      with wrong numbers and watching every case stay green.
##
##   4. WHAT AN `RTE` WITH A BAD FORMAT FIELD SHOULD DO. Section 3.5.7, "RTE
##      and Format Error Exceptions", page 3-16, is unambiguous that it
##      "generates a format error", which Table 3-1 on page 3-13 places at
##      vector 14 with a stacked program counter of "Fault" - the address of
##      the RTE itself. THIS MODULE TRAPS INSTEAD. The exception model is
##      CPU-14's and a trap is this core's one observable for "the core
##      refused", the same channel every illegal size and illegal operand in
##      every group uses; `alu.nim`'s header makes the identical statement
##      about a divide by zero. What `tests/t_control.nim` asserts is the
##      DISCRIMINATION - a format of 3 is refused and a format of 4 is not -
##      and not the shape of the refusal.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Instruction
## semantics, the condition-code rules and the encodings are facts about
## Motorola silicon; they are taken from the ColdFire Family Programmer's
## Reference Manual and the MCF5307 User's Manual (AGENTS.md section 11) and
## from this project's own measurements with the pinned cross assembler. No
## expression was taken from any copyleft source.

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
  ## THE ENCODING IS MEASURED AND THE TESTS ARE THE FAMILY DEFINITION; see
  ## uncertainty 1 in this module's header for the full list of assembled
  ## mnemonics and for what would overturn the tests.
  ##
  ## CONDITIONS 0 AND 1 ARE REACHED THROUGH `Scc` ALONE. In a branch word the
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
  ## N and Z from the difference, V the SIGNED overflow, C the borrow, and X
  ## LEFT ALONE.
  ##
  ## THE OVERFLOW EXPRESSION IS THE ONE `alu.nim`'s `setSubCc` USES, and it is
  ## written out again here rather than reached for: that procedure is private
  ## to `alu.nim`, and an executor that imported another executor for it would
  ## be the inversion this module's header refuses. The two differ in exactly
  ## one line - `setSubCc` writes X and this does not - so folding them would
  ## need a flag parameter that says which caller it is, and the difference is
  ## uncertainty 2 rather than a detail.
  let overflow = ((src xor dst) and (dst xor res) and 0x80000000'u32) != 0'u32
  var sr = ctx.sr and not (ccrN or ccrZ or ccrV or ccrC)
  if (res and 0x80000000'u32) != 0'u32: sr = sr or ccrN
  if res == 0'u32: sr = sr or ccrZ
  if overflow: sr = sr or ccrV
  if borrow: sr = sr or ccrC
  ctx.sr = sr

# ---------------------------------------------------------------------------
# BRA, BSR and Bcc.

proc execBranch(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## One branch. `d.size` carries the FORM the decoder read out of the
  ## displacement byte: 1 is the byte displacement in the opcode word, 2 the
  ## 16-bit displacement in the word after it, and 4 the 32-bit form that this
  ## part does not have.
  ##
  ## THE BASE IS THE ADDRESS OF THE WORD AFTER THE OPCODE, FOR BOTH FORMS, and
  ## it is measured rather than assumed: `bra.b .+8` assembles to `6006` and
  ## `bra.w .+0x2000` to `6000 1ffe`, so in each the displacement is the
  ## target minus (the opcode's address + 2). `ctx.pc` is exactly that address
  ## on entry - `step` advanced it past the opcode word and nothing else - and
  ## it is taken into a local BEFORE `fetchExt` moves it, the same way
  ## `eaAddr` takes its PC-relative base.
  ##
  ## THE EXTENSION WORD IS CONSUMED WHETHER OR NOT THE BRANCH IS TAKEN. A
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
  # `ctx.pc` is now the address after the whole instruction, which is what BSR
  # pushes and where a not-taken branch resumes.
  if d.op == opBsr:
    # "SP - 4 -> SP; PC -> (SP); PC + dn -> PC" - Table 3-7, page 3-23. The
    # pushed value is the address after the WHOLE instruction, so the byte
    # form pushes two bytes on and the word form four.
    ctx.sp = ctx.sp - 4'u32
    writeMem(ctx, ctx.sp, 4, ctx.pc)
    if ctx.halted:
      return 0'u32
  if d.op != opBcc or conditionHolds(ctx.sr, d.destReg):
    ctx.pc = target
  # Table 3-16, page 3-30, gives `Bcc` 1 or 5 cycles depending on whether the
  # static prediction was right; it gives `bra` 1(0/0) taken in either
  # direction, with no prediction in it, and it has no `bsr` row at all -
  # Table 3-15 on the same page gives `bsr` 1(0/1). Neither 2 nor 3 is any of
  # those. Nominal; see uncertainty 3.
  if d.op == opBsr: 3'u32 else: 2'u32

# ---------------------------------------------------------------------------
# Scc.

proc execScc(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## `Scc Dx`: ones or zeros into the LOW BYTE of a data register.
  ##
  ## THE WRITE GOES THROUGH `eaWrite`, which applies `mergeSized`, so the other
  ## three bytes of the register survive. That is one copy of the sized-write
  ## rule and not a second; `machine.nim`'s note on `mergeSized` records the
  ## defect that two copies of it produced.
  ##
  ## THE OPERAND MASK IS `{Dn}` AND IT IS WHAT REFUSES THE 68000 `DBcc` WORD -
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
  ## A BYTE OPERAND MAY NOT BE AN ADDRESS REGISTER, AND THAT IS A RULE ABOUT
  ## THE SIZE RATHER THAN THE MODE. `m68k-elf-as -mcpu=5307` accepts
  ## `tst.w %a0` (`4a48`) and `tst.l %a0` (`4a88`) and REJECTS `tst.b %a0`.
  ## The legality table in `decode_types.nim` is keyed on the operation alone
  ## and cannot express a size-dependent mode, exactly as it cannot express
  ## ADD's direction-dependent destination mask, so the rule is here.
  ##
  ## THE MANUAL DOES NOT SEPARATE THEM. Table 3-12's three `tst` rows on page
  ## 3-27 carry a time under a column headed `Rn`, and Table 3-6 on page 3-21
  ## defines `Rn` as "Any Address or Data Register" - so that column cannot
  ## say which of the two a given size admits. The `clr.b` row above uses the
  ## same heading and `m68k-elf-as -mcpu=5307` rejects `clr.b %a0` at every
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
  if d.ea.mode == eaDn or d.ea.mode == eaAn: 1'u32 else: 3'u32

# ---------------------------------------------------------------------------
# CMP, CMPA and CMPI.

proc execCompare(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## One comparison. The difference is computed and DISCARDED; only the
  ## condition codes survive, so no case in this procedure writes a register.
  ##
  ## THE SIZE AND THE OPERAND ARE CHECKED BEFORE ANY EXTENSION WORD IS
  ## FETCHED, which is the order `logic.nim`'s `execImmediate` gives the reason
  ## for: a core that consumed the words of an instruction it then refused
  ## would leave the program counter somewhere the instruction stream does not
  ## begin.
  ##
  ## THIS IS WHERE CMPA.W DIES. `decode.nim` gives line 1011 opmode 011 a size
  ## of 2 so that it arrives here and is refused on the size, rather than
  ## coming back as an unrecognised word that says nothing about why.
  if d.size != 4'u8:
    return trap(ctx)
  if not eaIsLegalFor(d.op, d.ea):
    return trap(ctx)
  var src, dst: uint32
  if d.op == opCmpi:
    # THE IMMEDIATE IS THE TWO WORDS AFTER THE OPCODE, HIGH HALF FIRST. The
    # same order `eaRead` uses for `ea7Imm` and `logic.nim` for ANDI, ORI and
    # EORI; `m68k-elf-as -mcpu=5307` emits `0c80 1234 5678` for
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

proc execJump(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## `JMP <ea>` and `JSR <ea>`. The operand is a CONTROL address and the
  ## instruction jumps to the ADDRESS ITSELF and never to what is at it -
  ## Table 3-7, page 3-23, gives JMP as "Address of <ea> -> PC".
  ##
  ## THE EFFECTIVE ADDRESS IS EVALUATED BEFORE THE RETURN ADDRESS IS PUSHED,
  ## and that ordering is the whole of what makes `jsr 0x00054320` different
  ## from `jsr (%a0)`. `eaAddr` consumes the operand's extension words, so
  ## `ctx.pc` afterwards is the address after the WHOLE instruction, which is
  ## what "SP - 4 -> SP; PC -> (SP)" (Table 3-7, page 3-24) means by PC. A
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
  ctx.pc = target
  5'u32

# ---------------------------------------------------------------------------
# RTS and RTE.

proc execRts(ctx: MCF5307Ctx): uint32 =
  ## "(SP) -> PC; SP + 4 -> SP" - Table 3-7, page 3-25. The pop is read BEFORE
  ## the stack pointer moves, and the pointer moves only when the read
  ## succeeded.
  let target = readMem(ctx, ctx.sp, 4)
  if ctx.halted:
    return 0'u32
  ctx.sp = ctx.sp + 4'u32
  ctx.pc = target
  8'u32

proc execRte(ctx: MCF5307Ctx): uint32 =
  ## The inverse of `takeException`.
  ##
  ## THE FORMAT FIELD IS VALIDATED FIRST. Section 3.5.7, page 3-16: the
  ## processor "first examines the 4-bit format field to validate the frame
  ## type", and "any attempted execution of an RTE where the format is not
  ## equal to {4,5,6,7} generates a format error". This core TRAPS instead of
  ## taking vector 14; that is uncertainty 4 in this module's header.
  ##
  ## THE STACK POINTER IS `SP + 4 + FORMAT` AND NOT `SP + 8`. The same section
  ## says the processor "adjusts the stack pointer by adding the format value
  ## to the auto-incremented address after the fetch of the first longword",
  ## which is SP + 4 plus 4, 5, 6 or 7. That is the inverse of Table 3-2 on
  ## page 3-14, whose four rows put the handler's A7 at the original A7 minus
  ## 8, 9, 10 or 11. A core that added a fixed 8 restores the wrong pointer
  ## for three of the four frames a misaligned stack produces.
  ##
  ## TABLE 3-7's `RTE` ROW READS "SP + 8 -> PC" AND THAT IS A MISPRINT. The
  ## program counter has just been loaded from (SP+4) and the row would
  ## overwrite it with an address on the stack. Section 3.5.7 is the passage
  ## that states the rule properly and it is what this follows.
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
  ctx.pc = target
  14'u32

# ---------------------------------------------------------------------------
# TRAP.

proc execTrap(ctx: MCF5307Ctx; d: Decoded): uint32 =
  ## `TRAP #<vector>`, the four-bit field in the low bits of the opcode.
  ##
  ## THE VECTOR NUMBER IS 32 PLUS THE FIELD. MCF5307 User's Manual Table 3-1,
  ## "Exception Vector Assignments", page 3-13: vector numbers 32 to 47, at
  ## vector offsets $080 to $0BC, are the "Trap # 0-15 instructions".
  ##
  ## THE STACKED PROGRAM COUNTER IS THE *NEXT* INSTRUCTION AND NOT THIS ONE.
  ## The same table's STACKED PROGRAM COUNTER column reads "Next" for those
  ## sixteen vectors, and its footnote defines Next as "the PC of the next
  ## instruction that follows the instruction that caused the fault". `ctx.pc`
  ## is already that address: `step` advanced it past the opcode word and TRAP
  ## has no extension words. The rows that read "Fault" instead - the access
  ## error, the address error, the illegal instruction - belong to CPU-14 and
  ## CPU-15.
  takeException(ctx, 32'u8 + (d.destReg and 0xF'u8), ctx.pc)
  if ctx.halted:
    return 0'u32
  18'u32

# ---------------------------------------------------------------------------
# The dispatch entry `step` calls.

proc controlFamily*(ctx: MCF5307Ctx; word: uint16; d: Decoded): uint32 =
  ## Execute one control-flow or comparison instruction. Called from `step` in
  ## `mcf5307/cpu` with the opcode word and the decoded operation. Returns the
  ## instruction's nominal cycles excluding the fetch; halts the context with
  ## `fault` set on an illegal size, an illegal effective address, a 32-bit
  ## branch displacement or an exception frame whose format field is not one
  ## of the four the part writes.
  case d.op
  of opBra, opBsr, opBcc: execBranch(ctx, word, d)
  of opScc: execScc(ctx, d)
  of opTst: execTst(ctx, d)
  of opCmp, opCmpa, opCmpi: execCompare(ctx, d)
  of opJmp, opJsr: execJump(ctx, d)
  of opRts: execRts(ctx)
  of opRte: execRte(ctx)
  of opTrap: execTrap(ctx, d)
  else: trap(ctx)
