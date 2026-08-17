## `t_system_control` - the ColdFire system-control instruction group: the SR
## and CCR transfers. Task CPU-30. Design section 6.1.
##
## WHAT THIS SUITE ASSERTS, AND WHY EACH GROUP EXISTS.
##
##   THE PRIVILEGE, IN BOTH DIRECTIONS. `MOVE from SR` and `MOVE to SR` are
##   supervisor-only on this part and `MOVE from CCR` and `MOVE to CCR` are
##   NOT. Both halves are asserted: the SR pair takes a vector-8 privilege
##   violation with S clear and completes with S set, and the CCR pair
##   COMPLETES WITH S CLEAR. A suite that ran the CCR pair in supervisor state
##   only would pass against a correct core AND against one that privileged
##   them, so the S-clear cases are what make that half an assertion at all.
##
##   THE OPERAND MASKS. Every memory mode, both absolute forms and both
##   PC-relative forms are asserted NOT TO DECODE. A 68000-derived
##   `MOVE to CCR` takes a general data effective address; this part takes
##   `Dy` or `#<data>` and nothing else, so a permissive core would execute an
##   addressing mode the silicon rejects and report nothing.
##
##   THE BANNER-PATH WORDS, NAMED BY ADDRESS. `0x3001B41E movew #8192,%sr` and
##   `0x3005834A movew %sr,%d4` are the two words the firmware could not
##   execute. They are the acceptance cases and they are asserted as
##   instructions rather than as decodes.
##
##   A7 UNDER A CLEARED S BIT. `move.w #$0700,%sr` executed in supervisor
##   state clears S, and A7 MUST NOT MOVE. There is one A7 on ISA_A and no
##   USP: `MOVE to USP` and `MOVE from USP` are ISA_B (CFPRM folios 8-10 and
##   8-12), and CFPRM Table 1-6, folio 1-11, makes OTHER_A7 conditional on
##   ISA_A+, which this part is not. So NOTHING happens to A7 when software
##   clears S - there is no second stack pointer to swap in. `cpu.nim:34` and
##   `include/mcf5307.h:186` both state the one-A7 rule in prose; the case
##   below is what makes it a run-time assertion.
##
## THE THREE 68000 DIVERGENCES EACH HAVE A CASE, because a 68000-derived core
## is wrong in three different directions and only one of them is loud.
##
##   (1) `MOVE from SR` is PRIVILEGED here and unprivileged on the 68000. The
##       S-clear case is the one that catches a core that let user code read
##       the SR - no trap, no wrong value and nothing to notice.
##   (2) `MOVE from CCR` DOES NOT EXIST on the 68000 (68010 and later), so a
##       68000 reference yields an illegal instruction for `42Cx` - and this
##       firmware uses that encoding.
##   (3) `MOVE to CCR` takes a general data `<ea>` on the 68000 and `Dy` or
##       `#<data>` only here.
##
## THE SIZE READING THIS SUITE TAKES IS WORD, and the disagreement is real:
## CFPRM folio 4-54 gives `MOVE to CCR` as "Size = Byte" with the syntax
## `MOVE.B Dy,CCR`, while CFPRM's own summary at folio 3-9 and MCF5307 User's
## Manual Table 3-14 both give WORD, and the pinned assembler accepts `move.w`
## and rejects `move.b`. Both readings agree on the encoding, on the extension
## word's 16-bit width and on the observable effect, so no case here
## discriminates between them; WORD is taken because two of the three sources
## and the assembler say so. `src/mcf5307/movec.nim` records the same reading
## at the executor.
##
## `STOP` IS NOT IN THIS SUITE and its absence is deliberate rather than an
## omission. The part has it - CFPRM Table 3-16, ISA_A - and zero `4E72` words
## occur at any 16-bit-aligned position in either image this core executes, so
## it is excluded from the first implementation and the plan records the
## triggers that reopen it.
##
## WHERE THE EXPECTED VALUES COME FROM. The encodings, the privilege rules and
## the operand masks are read from the ColdFire Family Programmer's Reference
## Manual Rev. 3 as page images, at the folios `src/mcf5307/movec.nim` names
## beside each rule. The markdown transcription under `MCF5307UM-md/` is not a
## source for any value here.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import mcf5307/machine
import mcf5307/cpu
import mcf5307/decode_types

var failures: seq[string]
import ./case_sites

var passCount = 0

proc checkImpl[T](site: int; got: T; want: T; label: string) =
  if got == want:
    echo "PASSED  ", label
    inc passCount
    executedSites.add(site)
  else:
    echo "FAILED  ", label, ": expected ", want, ", got ", got
    failures.add(label)
    executedSites.add(site)

template check(got: untyped; want: untyped; label: string) =
  ## THE CALL SITE IS RECORDED TWICE - once at COMPILE TIME into
  ## `declaredSites` by the `static` below, and once at RUN TIME into
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, got, want, label)

# ---------------------------------------------------------------------------
# The board, and the one instruction it runs.
#
# EVERY CASE BELOW DRIVES THE PUBLISHED ENTRY POINTS - `mcf5307_create`,
# `mcf5307_reset`, `mcf5307_set_reg`, `mcf5307_exec` and `mcf5307_get_reg` -
# AND NOT THE DECODER. A suite that called `decodeWord` directly would answer
# the same way whether or not `cpu.nim` dispatched the opcode, so a full pass
# of decoder cases alone is consistent with an instruction that decodes and
# never executes.

const
  execBase = 0x100'u32     ## where the instruction words are placed
  stackBase = 0x800'u32
  srSuper = 0x2700'u32     ## supervisor, interrupt mask 7 - the reset value
  srSuperFlags = 0x2709'u32
    ## supervisor with N and C set. THE FLAGS ARE NOT ZERO IN ANY CASE THAT
    ## READS THEM: a `MOVE from CCR` that answered a constant zero would pass
    ## every case whose source flags were clear.
  srUser = 0x0700'u32      ## USER state with the same interrupt mask, so that
                           ## a wrong bit read is red rather than green by
                           ## coincidence
  srUserFlags = 0x0709'u32 ## user state with N and C set
  handlerBase = 0x400'u32  ## where the seeded vector-8 entry points
  memSize = 0x1000

const dirtyD: array[8, uint32] = [
  0x1234_5678'u32, 0x1111_1111'u32, 0x2222_2222'u32, 0x3333_3333'u32,
  0xDEAD_BEEF'u32, 0x5555_5555'u32, 0x6666_6666'u32, 0x7777_7777'u32]
  ## EVERY DATA REGISTER CARRIES A DISTINCT VALUE, so a transfer that reached
  ## the wrong register is red rather than green by coincidence.
  ##
  ## THE LOW FIVE BITS OF `%d0` AND `%d4` DIFFER, AND THAT IS WHAT THE
  ## `MOVE to CCR` SOURCE CASES REST ON: `0x78 and 0x1F` is `0x18`, which is X
  ## and N, and `0xEF and 0x1F` is `0x0F`, which is N, Z, V and C. Neither is
  ## zero and neither is all five, so a core that wrote a constant in either
  ## direction is red.

const dirtyA: array[8, uint32] = [
  0x0BAD_C0DE'u32, 0x0A11_0A11'u32, 0x0B22_0B22'u32, 0x0C33_0C33'u32,
  0x0D44_0D44'u32, 0x0E55_0E55'u32, 0x0F66_0F66'u32, stackBase]
  ## A7 IS `stackBase` AND NOT A DIRTY VALUE, because `mcf5307_reset` writes it
  ## and a seeded value would simply be overwritten. It is in this array so
  ## that the A7-under-cleared-S case reads it through the same comparison as
  ## every other register.

type TestBoard = object
  bytes: array[memSize, uint8]

var board: TestBoard

proc boardWrite(b: var TestBoard; address: uint32; size: int; value: uint32) =
  for i in 0 ..< size:
    b.bytes[int(address) + i] =
      uint8((value shr ((size - 1 - i) * 8)) and 0xFF'u32)

proc boardReadValue(b: TestBoard; address: uint32; size: int): uint32 =
  for i in 0 ..< size:
    result = (result shl 8) or uint32(b.bytes[int(address) + i])

proc bRead(user: pointer; address: uint32; size: cint;
           status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return 0'u32
  status[] = Mcf5307BusStatus.busOk
  boardReadValue(b[], address, int(size))

proc bWrite(user: pointer; address: uint32; size: cint; value: uint32;
            status: ptr Mcf5307BusStatus) {.cdecl.} =
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return
  status[] = Mcf5307BusStatus.busOk
  boardWrite(b[], address, int(size), value)

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

type Outcome = object
  cycles: uint32
    ## `mcf5307_exec(ctx, 1)` SATURATES AT ITS BUDGET, so this is 1 for an
    ## instruction that ran and 0 for one that halted before spending
    ## anything. `cpu.nim`'s header block says why it is not a cycle count.
  fault: bool
  halted: bool
  d: array[8, uint32]
  a: array[8, uint32]
  sr: uint32
  pc: uint32

proc runIns(words: openArray[uint16]; sr: uint32;
            mem: seq[(uint32, uint32)] = @[]): Outcome =
  ## Place `words` at `execBase`, seed every data and address register, run
  ## ONE `mcf5307_exec`, and report the whole machine state.
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  for i in 0 ..< words.len:
    boardWrite(board, execBase + 2'u32 * uint32(i), 2, uint32(words[i]))
  for (address, value) in mem:
    boardWrite(board, address, 4, value)

  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, stackBase, execBase)
  for i in 0 ..< 8:
    discard mcf5307_set_reg(ctx, cint(i), dirtyD[i])
  for i in 0 ..< 8:
    discard mcf5307_set_reg(ctx, cint(8 + i), dirtyA[i])
  # The status register is set LAST, because `mcf5307_reset` writes it and an
  # earlier write would be overwritten - which would run every user-state case
  # in supervisor state and pass.
  discard mcf5307_set_reg(ctx, 16, sr)

  result.cycles = mcf5307_exec(ctx, 1'u32)
  result.fault = ctx.fault
  result.halted = ctx.halted
  for i in 0 ..< 8:
    result.d[i] = mcf5307_get_reg(ctx, cint(i))
  for i in 0 ..< 8:
    result.a[i] = mcf5307_get_reg(ctx, cint(8 + i))
  result.sr = mcf5307_get_reg(ctx, 16)
  result.pc = mcf5307_get_reg(ctx, 17)

proc whole(o: Outcome): auto =
  ## THE WHOLE MACHINE AND NOT THE ONE FIELD THE CASE IS ABOUT. Every case
  ## below compares this tuple against a literal, so a transfer that reached
  ## the right destination and ALSO moved a register it must not touch is red.
  ## The program counter is in it because a core that consumed the wrong
  ## number of words leaves the pc behind and decodes an operand as the next
  ## instruction.
  (cycles: o.cycles, fault: o.fault, halted: o.halted, pc: o.pc,
   d: o.d, a: o.a, sr: o.sr)

proc dWith(reg: int; value: uint32): array[8, uint32] =
  ## The seeded data registers with ONE of them replaced. The other seven are
  ## carried unchanged, which is what makes a stray write to any of them red.
  result = dirtyD
  result[reg] = value

proc wordInto(reg: int; value: uint32): array[8, uint32] =
  ## The seeded data registers after a WORD-SIZED write of `value` into `reg`.
  ## THE HIGH HALF SURVIVES: `mergeSized` replaces the low `size` bytes and
  ## nothing else, so a core that wrote a LONGWORD clears the seeded high half
  ## and every case built on this helper goes red.
  dWith(reg, (dirtyD[reg] and 0xFFFF_0000'u32) or (value and 0xFFFF'u32))

# ---------------------------------------------------------------------------
# CLAUSE 1 - THE PRIVILEGE PREDICATE HAS ONE HOME AND THESE CASES PROVE IT IN
# BOTH DIRECTIONS.
#
# CFPRM folio 8-9 gives `MOVE from SR` as "If Supervisor State Then SR ->
# Destination Else Privilege Violation Exception", and MCF5307 User's Manual
# Table 3-1, folio 3-13, assigns VECTOR 8 at offset `$020` to "Privilege
# violation" with a STACKED PROGRAM COUNTER column of "Fault" - which that
# table's own footnote defines as "the PC of the instruction that caused the
# exception". So the stacked value is `execBase` and NOT the address after the
# word: an `RTE` from the handler re-executes the instruction.
#
# THE SUPERVISOR CASE IS THE OTHER HALF AND IT IS NOT DECORATION. A core that
# took the privilege violation unconditionally would pass the user case alone.

check(whole(runIns([0x40C4'u16], srSuper)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 2'u32,
     d: wordInto(4, srSuper), a: dirtyA, sr: srSuper),
    "move.w %sr,%d4 in supervisor state transfers the status register")

block:
  let o = runIns([0x40C4'u16], srUser,
                 mem = @[(4'u32 * 8'u32, handlerBase)])
  let got = (cycles: o.cycles, fault: o.fault, halted: o.halted, pc: o.pc,
             sr: o.sr, d: o.d, a: o.a,
             fv: boardReadValue(board, stackBase - 8'u32, 4),
             stackedPc: boardReadValue(board, stackBase - 4'u32, 4))
  # `fv` is FORMAT 4 (A7 was already longword aligned), FS 0 (this is not an
  # access error), VECTOR 8, and the status register AS IT WAS BEFORE the
  # exception changed it. The handler runs with S set and T clear.
  #
  # THE DATA REGISTERS ARE UNCHANGED, WHICH IS THE HALF THAT MATTERS MOST. A
  # core that read the SR into `%d4` AND THEN took the exception would pass a
  # case that only checked the vector; `d: dirtyD` is what rejects it.
  var wantA = dirtyA
  wantA[7] = stackBase - 8'u32
  let want = (cycles: 1'u32, fault: false, halted: false, pc: handlerBase,
              sr: 0x2700'u32, d: dirtyD, a: wantA,
              fv: 0x4020_0700'u32,
              stackedPc: execBase)
  check(got, want,
      "move.w %sr,%d4 in USER state takes the vector-8 privilege violation")

# `MOVE to SR` IS THE OTHER PRIVILEGED MEMBER AND IT TAKES THE SAME VECTOR.
# CFPRM folio 8-11 gives the same "If Supervisor State Then ... Else Privilege
# Violation Exception" operation. THE STACKED PC IS THE OPCODE WORD AND NOT
# THE EXTENSION WORD, because the privilege is tested BEFORE the extension
# word is fetched - the order `movec.nim` already states and this case pins.

block:
  let o = runIns([0x46FC'u16, 0x2700'u16], srUser,
                 mem = @[(4'u32 * 8'u32, handlerBase)])
  let got = (cycles: o.cycles, fault: o.fault, halted: o.halted, pc: o.pc,
             sr: o.sr, d: o.d, a: o.a,
             fv: boardReadValue(board, stackBase - 8'u32, 4),
             stackedPc: boardReadValue(board, stackBase - 4'u32, 4))
  var wantA = dirtyA
  wantA[7] = stackBase - 8'u32
  let want = (cycles: 1'u32, fault: false, halted: false, pc: handlerBase,
              sr: 0x2700'u32, d: dirtyD, a: wantA,
              fv: 0x4020_0700'u32,
              stackedPc: execBase)
  check(got, want,
      "move.w #$2700,%sr in USER state takes the vector-8 privilege violation")

# ---------------------------------------------------------------------------
# CLAUSE 2 - THE CCR PAIR IS UNPRIVILEGED AND THESE CASES ASSERT THE ABSENCE
# OF A TRAP.
#
# CFPRM places both in chapter 4, the USER instructions, at folios 4-53 and
# 4-54, with no supervisor test in either and no entry in Table 3-12's
# privileged list. BOTH RUN WITH S CLEAR HERE. A case that only ran them in
# supervisor state would pass against a correct core AND against one that
# privileged them, and would therefore satisfy nothing in this clause.

check(whole(runIns([0x42C0'u16], srUserFlags)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 2'u32,
     d: wordInto(0, 0x0009'u32), a: dirtyA, sr: srUserFlags),
    "move.w %ccr,%d0 in USER state does not trap and zero-extends the CCR")

# THE ZERO-EXTENSION IS THE CLAIM, AND `0x0009` IS WHAT MAKES IT ONE. The
# status register is `0x0709` here, so a core that moved the whole SR would
# write `0x0709` instead. Only the condition-code byte zero-extended to a word
# gives `0x0009`.

check(whole(runIns([0x44C0'u16], srUser)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 2'u32,
     d: dirtyD, a: dirtyA, sr: (srUser and not 0x1F'u32) or 0x18'u32),
    "move.w %d0,%ccr in USER state does not trap and writes X/N/Z/V/C")

# THE INTERRUPT MASK AND THE S BIT ARE UNTOUCHED. `MOVE to CCR` writes five
# bits, so a core that wrote the whole status register would clear the mask
# and leave user state - which the `sr` field of this tuple catches.

check(whole(runIns([0x42C0'u16], srSuperFlags)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 2'u32,
     d: wordInto(0, 0x0009'u32), a: dirtyA, sr: srSuperFlags),
    "move.w %ccr,%d0 in supervisor state transfers the same value")

# ---------------------------------------------------------------------------
# THE CONDITION-CODE SOURCE IS FIVE BITS WIDE AND NOT SIXTEEN.
#
# CFPRM folios 4-54 and 8-11 give the source of `MOVE to CCR` as bits 4 to 0.
# An immediate of `0xFFFF` is what separates a five-bit write from a
# whole-word one: under the correct rule the status register becomes `0x271F`
# and under a word-wide write it becomes `0xFFFF`.

check(whole(runIns([0x44FC'u16, 0xFFFF'u16], srSuper)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 4'u32,
     d: dirtyD, a: dirtyA, sr: 0x271F'u32),
    "move.w #$FFFF,%ccr sets X/N/Z/V/C and touches no other status bit")

check(whole(runIns([0x44FC'u16, 0x0000'u16], srSuperFlags)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 4'u32,
     d: dirtyD, a: dirtyA, sr: 0x2700'u32),
    "move.w #$0000,%ccr clears X/N/Z/V/C and touches no other status bit")

# THE PROGRAM COUNTER IS `execBase + 4` IN BOTH CASES ABOVE, which is the
# EXTENSION WORD CONSUMED. A core that fetched no extension word would leave
# the pc at `execBase + 2` and decode `0xFFFF` as the next instruction.

# ---------------------------------------------------------------------------
# CLAUSE 4 - THE BANNER-PATH WORDS, NAMED BY ADDRESS.
#
# `0x3001B41E movew #8192,%sr` sits on the banner path and UNMASKS INTERRUPTS
# twenty-six bytes before the banner call: `8192` is `0x2000`, which is S set
# and an interrupt mask of ZERO. The firmware then faults at `0x3005834A` on
# the word `40c4`, `movew %sr,%d4`. These two are what the blocker actually
# is.

check(whole(runIns([0x46FC'u16, 0x2000'u16], srSuper)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 4'u32,
     d: dirtyD, a: dirtyA, sr: 0x2000'u32),
    "0x3001B41E move.w #8192,%sr writes the whole status register")

# THE INTERRUPT MASK IS READ BACK AS A FIELD OF ITS OWN, because a status
# register compared whole would not say WHICH bits the case is about. Bits 10
# to 8 are the mask (User's Manual section 3.2.2.1, folio 3-10) and `#8192`
# drives them to zero from the reset value of seven, which is the effect the
# firmware is after twenty-six bytes before the banner call.

block:
  let o = runIns([0x46FC'u16, 0x2000'u16], srSuper)
  check((mask: (o.sr shr 8) and 0x7'u32,
         supervisor: (o.sr and srSupervisor) != 0'u32,
         fault: o.fault),
      (mask: 0'u32, supervisor: true, fault: false),
      "0x3001B41E move.w #8192,%sr unmasks interrupts and stays supervisor")

check(whole(runIns([0x40C4'u16], srSuper)).fault, false,
    "0x3005834A move.w %sr,%d4 no longer faults")

# ---------------------------------------------------------------------------
# A7 UNDER A CLEARED S BIT, WHICH IS THE QUESTION `cpu.nim:34` ANSWERS IN
# PROSE AND THIS CASE ANSWERS IN A RUN.
#
# `move.w #$0700,%sr` executed in SUPERVISOR state is the transition that
# would swap stack pointers on a part that had two. ISA_A has ONE A7 and no
# USP - `MOVE to USP` and `MOVE from USP` are ISA_B, CFPRM folios 8-10 and
# 8-12 - so A7 must still read `stackBase` after it. `a: dirtyA` carries that
# expectation, because `dirtyA[7]` IS `stackBase`.

check(whole(runIns([0x46FC'u16, 0x0700'u16], srSuper)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 4'u32,
     d: dirtyD, a: dirtyA, sr: 0x0700'u32),
    "move.w #$0700,%sr clears S and leaves the one A7 where it was")

# ---------------------------------------------------------------------------
# CLAUSE 3 - THE OPERAND MASKS REJECT EVERY MODE THE PER-INSTRUCTION TABLES
# DASH.
#
# The CFPRM `Effective Address field` table of each of the four instructions
# DASHES every memory mode, `(xxx).W`, `(xxx).L` and both PC-relative forms.
# The pinned assembler - GNU Binutils 2.47.20260726, `-mcpu=5307` - agrees:
# it rejects `move.w %sr,%a0`, `move.w %sr,(%a0)`, `move.w (%a0),%sr`,
# `move.w %ccr,(%a0)` and `move.w (%a0),%ccr`.
#
# THE REJECTED WORD MUST NOT DECODE AT ALL, which on this core is `fault` set
# and `halted` set with no cycles spent.
#
# THIS IS THE THIRD 68000 DIVERGENCE AND IT IS THE PERMISSIVE ONE. `MOVE to
# CCR` takes a general data `<ea>` on the 68000, so a 68000-derived mask
# accepts `move.w (%a0),%ccr` and executes an addressing mode the silicon
# rejects.

const rejected = (cycles: 0'u32, fault: true, halted: true,
                  pc: execBase + 2'u32,
                  d: dirtyD, a: dirtyA, sr: srSuper)

check(whole(runIns([0x40D0'u16], srSuper)), rejected,
    "move.w %sr,(%a0) does not decode")
check(whole(runIns([0x40C8'u16], srSuper)), rejected,
    "move.w %sr,%a0 does not decode")
check(whole(runIns([0x40F9'u16], srSuper)), rejected,
    "move.w %sr,(xxx).l does not decode")
check(whole(runIns([0x42D0'u16], srSuper)), rejected,
    "move.w %ccr,(%a0) does not decode")
check(whole(runIns([0x42F8'u16], srSuper)), rejected,
    "move.w %ccr,(xxx).w does not decode")
check(whole(runIns([0x42C8'u16], srSuper)), rejected,
    "move.w %ccr,%a0 does not decode")
check(whole(runIns([0x44D0'u16], srSuper)), rejected,
    "move.w (%a0),%ccr does not decode")
check(whole(runIns([0x44FA'u16], srSuper)), rejected,
    "move.w (d16,%pc),%ccr does not decode")
check(whole(runIns([0x44C8'u16], srSuper)), rejected,
    "move.w %a0,%ccr does not decode")
check(whole(runIns([0x46D0'u16], srSuper)), rejected,
    "move.w (%a0),%sr does not decode")
check(whole(runIns([0x46D8'u16], srSuper)), rejected,
    "move.w (%a0)+,%sr does not decode")
check(whole(runIns([0x46E0'u16], srSuper)), rejected,
    "move.w -(%a0),%sr does not decode")
check(whole(runIns([0x46E8'u16], srSuper)), rejected,
    "move.w (d16,%a0),%sr does not decode")
check(whole(runIns([0x46F0'u16], srSuper)), rejected,
    "move.w (d8,%a0,%xi),%sr does not decode")
check(whole(runIns([0x46F8'u16], srSuper)), rejected,
    "move.w (xxx).w,%sr does not decode")
check(whole(runIns([0x46F9'u16], srSuper)), rejected,
    "move.w (xxx).l,%sr does not decode")
check(whole(runIns([0x46FA'u16], srSuper)), rejected,
    "move.w (d16,%pc),%sr does not decode")
check(whole(runIns([0x46FB'u16], srSuper)), rejected,
    "move.w (d8,%pc,%xi),%sr does not decode")
check(whole(runIns([0x46C8'u16], srSuper)), rejected,
    "move.w %a0,%sr does not decode")

# THE NEIGHBOURING SIZE-11 WORD THIS GROUP DOES NOT CLAIM. `0x4AC0` is TAS,
# which section 3.9 of the User's Manual does not leave on this part. It is
# asserted so that a recogniser written as a mask over line 4 rather than as
# four narrow tests is red rather than green.

check(whole(runIns([0x4AC0'u16], srSuper)), rejected,
    "0x4AC0 stays illegal: TAS is not on this part")

# ---------------------------------------------------------------------------
# THE REGISTER FIELD IS READ AT THE RIGHT OFFSET, ASSERTED ON MORE THAN ONE
# REGISTER SO THAT AN OFF-BY-ONE OR A CONSTANT IS RED.

check(whole(runIns([0x40C0'u16], srSuper)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 2'u32,
     d: wordInto(0, srSuper), a: dirtyA, sr: srSuper),
    "move.w %sr,%d0 writes d0 and no other register")

check(whole(runIns([0x40C7'u16], srSuper)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 2'u32,
     d: wordInto(7, srSuper), a: dirtyA, sr: srSuper),
    "move.w %sr,%d7 writes d7 and no other register")

check(whole(runIns([0x42C4'u16], srSuperFlags)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 2'u32,
     d: wordInto(4, 0x0009'u32), a: dirtyA, sr: srSuperFlags),
    "move.w %ccr,%d4 writes d4 and no other register")

check(whole(runIns([0x44C4'u16], srSuper)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 2'u32,
     d: dirtyD, a: dirtyA, sr: (srSuper and not 0x1F'u32) or 0x0F'u32),
    "move.w %d4,%ccr reads d4 and no other register")

# `%d4` IS `0xDEADBEEF`, WHOSE LOW FIVE BITS ARE `01111` - N, Z, V and C and
# NOT X - a different set from `%d0`'s `0x18`, so a core that read the wrong
# source register is red rather than green by coincidence.

check(whole(runIns([0x46C4'u16], srSuper)),
    (cycles: 1'u32, fault: false, halted: false, pc: execBase + 2'u32,
     d: dirtyD, a: dirtyA, sr: dirtyD[4] and 0xFFFF'u32),
    "move.w %d4,%sr writes the whole status register from d4")

# THE REGISTER FORM OF `MOVE to SR` IS ASSERTED AS WELL AS THE IMMEDIATE ONE,
# because the two reach the source through different paths and the firmware
# word on the banner path is the immediate. `0xDEADBEEF` low word is `0xBEEF`,
# which has S SET - so this case leaves the machine supervisor and does not
# depend on a second instruction to observe.

# ---------------------------------------------------------------------------
# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_system_control", declaredCaseSites)
echo caseSiteLine("executed", "t_system_control", executedSites)
echo caseSiteLine("off-green-path", "t_system_control",
    declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_system_control: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_system_control: ", passCount, " cases passed"
