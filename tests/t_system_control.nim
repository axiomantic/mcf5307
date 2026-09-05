## `t_system_control` - the ColdFire system-control instruction group: the SR
## and CCR transfers.

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

const
  execBase = 0x100'u32     ## where the instruction words are placed
  stackBase = 0x800'u32
  srSuper = 0x2700'u32     ## supervisor, interrupt mask 7 - the reset value
  srSuperFlags = 0x2709'u32 ## supervisor with N and C set
  srUser = 0x0700'u32      ## USER state with the same interrupt mask
  srUserFlags = 0x0709'u32 ## user state with N and C set
  handlerBase = 0x400'u32  ## where the seeded vector-8 entry points
  memSize = 0x1000

const dirtyD: array[8, uint32] = [
  0x1234_5678'u32, 0x1111_1111'u32, 0x2222_2222'u32, 0x3333_3333'u32,
  0xDEAD_BEEF'u32, 0x5555_5555'u32, 0x6666_6666'u32, 0x7777_7777'u32]

const dirtyA: array[8, uint32] = [
  0x0BAD_C0DE'u32, 0x0A11_0A11'u32, 0x0B22_0B22'u32, 0x0C33_0C33'u32,
  0x0D44_0D44'u32, 0x0E55_0E55'u32, 0x0F66_0F66'u32, stackBase]
  ## A7 IS `stackBase` AND NOT A DIRTY VALUE, because `mcf5307_reset` writes it
  ## and a seeded value would simply be overwritten.

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
  ran: bool
    ## DID THE INSTRUCTION RUN? It is `mcf5307_exec(ctx, 1) > 0`, and it is a
    ## BOOLEAN because that is all the call can tell this suite. The return is
    ## the whole retired cost of the instruction - `cpu.nim`'s header block is
    ## the contract - and that cost differs per encoding, so an expectation
    ## written here would be a per-row cycle LITERAL transcribed beside the
    ## executor that computes it. This suite has no second way to derive one:
    ## the rows that take an exception leave the machine inside a handler, so
    ## a generous-budget reference run does not stop after one instruction.
    ##
    ## THE COST ITSELF IS NOT PINNED HERE. What this field carries is the
    ## ran-or-trapped bit the rows below actually turn on, under a name that
    ## says so.
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
  # earlier write would be overwritten.
  discard mcf5307_set_reg(ctx, 16, sr)

  result.ran = mcf5307_exec(ctx, 1'u32) > 0'u32
  result.fault = ctx.fault
  result.halted = ctx.halted
  for i in 0 ..< 8:
    result.d[i] = mcf5307_get_reg(ctx, cint(i))
  for i in 0 ..< 8:
    result.a[i] = mcf5307_get_reg(ctx, cint(8 + i))
  result.sr = mcf5307_get_reg(ctx, 16)
  result.pc = mcf5307_get_reg(ctx, 17)

proc whole(o: Outcome): auto =
  (ran: o.ran, fault: o.fault, halted: o.halted, pc: o.pc,
   d: o.d, a: o.a, sr: o.sr)

proc dWith(reg: int; value: uint32): array[8, uint32] =
  result = dirtyD
  result[reg] = value

proc wordInto(reg: int; value: uint32): array[8, uint32] =
  ## The seeded data registers after a WORD-SIZED write of `value` into `reg`.
  dWith(reg, (dirtyD[reg] and 0xFFFF_0000'u32) or (value and 0xFFFF'u32))


check(whole(runIns([0x40C4'u16], srSuper)),
    (ran: true, fault: false, halted: false, pc: execBase + 2'u32,
     d: wordInto(4, srSuper), a: dirtyA, sr: srSuper),
    "move.w %sr,%d4 in supervisor state transfers the status register")

block:
  let o = runIns([0x40C4'u16], srUser,
                 mem = @[(4'u32 * 8'u32, handlerBase)])
  let got = (ran: o.ran, fault: o.fault, halted: o.halted, pc: o.pc,
             sr: o.sr, d: o.d, a: o.a,
             fv: boardReadValue(board, stackBase - 8'u32, 4),
             stackedPc: boardReadValue(board, stackBase - 4'u32, 4))
  # `fv` is FORMAT 4 (A7 was already longword aligned), FS 0 (this is not an
  # access error), VECTOR 8, and the status register AS IT WAS BEFORE the
  # exception changed it. The handler runs with S set and T clear.
  var wantA = dirtyA
  wantA[7] = stackBase - 8'u32
  let want = (ran: true, fault: false, halted: false, pc: handlerBase,
              sr: 0x2700'u32, d: dirtyD, a: wantA,
              fv: 0x4020_0700'u32,
              stackedPc: execBase)
  check(got, want,
      "move.w %sr,%d4 in USER state takes the vector-8 privilege violation")


block:
  let o = runIns([0x46FC'u16, 0x2700'u16], srUser,
                 mem = @[(4'u32 * 8'u32, handlerBase)])
  let got = (ran: o.ran, fault: o.fault, halted: o.halted, pc: o.pc,
             sr: o.sr, d: o.d, a: o.a,
             fv: boardReadValue(board, stackBase - 8'u32, 4),
             stackedPc: boardReadValue(board, stackBase - 4'u32, 4))
  var wantA = dirtyA
  wantA[7] = stackBase - 8'u32
  let want = (ran: true, fault: false, halted: false, pc: handlerBase,
              sr: 0x2700'u32, d: dirtyD, a: wantA,
              fv: 0x4020_0700'u32,
              stackedPc: execBase)
  check(got, want,
      "move.w #$2700,%sr in USER state takes the vector-8 privilege violation")


check(whole(runIns([0x42C0'u16], srUserFlags)),
    (ran: true, fault: false, halted: false, pc: execBase + 2'u32,
     d: wordInto(0, 0x0009'u32), a: dirtyA, sr: srUserFlags),
    "move.w %ccr,%d0 in USER state does not trap and zero-extends the CCR")

check(whole(runIns([0x44C0'u16], srUser)),
    (ran: true, fault: false, halted: false, pc: execBase + 2'u32,
     d: dirtyD, a: dirtyA, sr: (srUser and not 0x1F'u32) or 0x18'u32),
    "move.w %d0,%ccr in USER state does not trap and writes X/N/Z/V/C")

check(whole(runIns([0x42C0'u16], srSuperFlags)),
    (ran: true, fault: false, halted: false, pc: execBase + 2'u32,
     d: wordInto(0, 0x0009'u32), a: dirtyA, sr: srSuperFlags),
    "move.w %ccr,%d0 in supervisor state transfers the same value")

# ---------------------------------------------------------------------------

check(whole(runIns([0x44FC'u16, 0xFFFF'u16], srSuper)),
    (ran: true, fault: false, halted: false, pc: execBase + 4'u32,
     d: dirtyD, a: dirtyA, sr: 0x271F'u32),
    "move.w #$FFFF,%ccr sets X/N/Z/V/C and touches no other status bit")

check(whole(runIns([0x44FC'u16, 0x0000'u16], srSuperFlags)),
    (ran: true, fault: false, halted: false, pc: execBase + 4'u32,
     d: dirtyD, a: dirtyA, sr: 0x2700'u32),
    "move.w #$0000,%ccr clears X/N/Z/V/C and touches no other status bit")

# ---------------------------------------------------------------------------

check(whole(runIns([0x46FC'u16, 0x2000'u16], srSuper)),
    (ran: true, fault: false, halted: false, pc: execBase + 4'u32,
     d: dirtyD, a: dirtyA, sr: 0x2000'u32),
    "0x3001B41E move.w #8192,%sr writes the whole status register")


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

check(whole(runIns([0x46FC'u16, 0x0700'u16], srSuper)),
    (ran: true, fault: false, halted: false, pc: execBase + 4'u32,
     d: dirtyD, a: dirtyA, sr: 0x0700'u32),
    "move.w #$0700,%sr clears S and leaves the one A7 where it was")


const rejected = (ran: false, fault: true, halted: true,
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


check(whole(runIns([0x4AC0'u16], srSuper)), rejected,
    "0x4AC0 stays illegal: TAS is not on this part")

# ---------------------------------------------------------------------------

check(whole(runIns([0x40C0'u16], srSuper)),
    (ran: true, fault: false, halted: false, pc: execBase + 2'u32,
     d: wordInto(0, srSuper), a: dirtyA, sr: srSuper),
    "move.w %sr,%d0 writes d0 and no other register")

check(whole(runIns([0x40C7'u16], srSuper)),
    (ran: true, fault: false, halted: false, pc: execBase + 2'u32,
     d: wordInto(7, srSuper), a: dirtyA, sr: srSuper),
    "move.w %sr,%d7 writes d7 and no other register")

check(whole(runIns([0x42C4'u16], srSuperFlags)),
    (ran: true, fault: false, halted: false, pc: execBase + 2'u32,
     d: wordInto(4, 0x0009'u32), a: dirtyA, sr: srSuperFlags),
    "move.w %ccr,%d4 writes d4 and no other register")

check(whole(runIns([0x44C4'u16], srSuper)),
    (ran: true, fault: false, halted: false, pc: execBase + 2'u32,
     d: dirtyD, a: dirtyA, sr: (srSuper and not 0x1F'u32) or 0x0F'u32),
    "move.w %d4,%ccr reads d4 and no other register")

check(whole(runIns([0x46C4'u16], srSuper)),
    (ran: true, fault: false, halted: false, pc: execBase + 2'u32,
     d: dirtyD, a: dirtyA, sr: dirtyD[4] and 0xFFFF'u32),
    "move.w %d4,%sr writes the whole status register from d4")

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
