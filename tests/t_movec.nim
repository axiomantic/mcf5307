## `t_movec` - the `MOVEC` encoding and the control-register map of
## `mcf5307/movec`.
##
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import mcf5307/movec
import mcf5307/machine
import mcf5307/cpu
import mcf5307/decode_types

var failures: seq[string]
import ./case_sites

var passCount = 0

proc checkImpl[T](site: int; got: T; want: T; label: string) =
  if got == want:
    echo "PASSED  ", label, " = ", want
    inc passCount
    executedSites.add(site)
  else:
    echo "FAILED  ", label, ": expected ", want, ", got ", got
    failures.add(label)
    executedSites.add(site)

template check(got: untyped; want: untyped; label: string) =
  ## The call site is recorded twice - once at compile time into
  ## `declaredSites` by the `static` below, and once at run time into
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, got, want, label)

# ---------------------------------------------------------------------------
# The opcode word.
#
# The two negative cases are not decoration. `0x4E7A` is the word
# `tests/t_control.nim` asserts is illegal on this part, and `0x4E73` is `RTE`,
# which `decode.nim` already answers. A recogniser written as a mask over
# line 4 rather than as an equality claims both of them.

check(isMovec(0x4E7B'u16),  true, "isMovec(0x4E7B)")
check(isMovec(0x4E7A'u16), false, "isMovec(0x4E7A) - not MOVEC")
check(isMovec(0x4E73'u16), false, "isMovec(0x4E73) - RTE is not MOVEC")

# ---------------------------------------------------------------------------
# The extension word fields.
#
# Each field is read twice, once with its neighbours clear and once with them
# set, so that a field taken one bit too wide is red rather than green.

check(movecControlField(0x0801'u16), 0x801'u16,
    "movecControlField(0x0801) - neighbours clear")
check(movecControlField(0xF801'u16), 0x801'u16,
    "movecControlField(0xF801) - A/D and Ry excluded")

check(movecSourceIsAddressRegister(0x0801'u16), false,
    "movecSourceIsAddressRegister(0x0801) - a data register")
check(movecSourceIsAddressRegister(0x8801'u16), true,
    "movecSourceIsAddressRegister(0x8801) - an address register")

check(movecSourceRegister(0x0801'u16), 0'u8,
    "movecSourceRegister(0x0801)")
check(movecSourceRegister(0x7801'u16), 7'u8,
    "movecSourceRegister(0x7801)")
check(movecSourceRegister(0x8801'u16), 0'u8,
    "movecSourceRegister(0x8801) - the A/D bit is not part of Ry")

# ---------------------------------------------------------------------------
# The privilege.
#
# The interrupt mask is set in one case of each pair. A predicate that read the
# wrong status-register bit would answer both of the S-clear cases correctly by
# accident if every other bit were clear in both.

check(movecPrivilegeViolation(0x0000'u32), true,
    "movecPrivilegeViolation(user state)")
check(movecPrivilegeViolation(0x0700'u32), true,
    "movecPrivilegeViolation(user state, interrupt mask set)")
check(movecPrivilegeViolation(srSupervisor), false,
    "movecPrivilegeViolation(supervisor state)")
check(movecPrivilegeViolation(0x2700'u32), false,
    "movecPrivilegeViolation(supervisor state, interrupt mask set)")

# ---------------------------------------------------------------------------
# The control registers the firmware writes.

check(controlRegisterFor(0x002'u16), crCacr,    "0x002 is CACR")
check(controlRegisterFor(0x004'u16), crAcr0,    "0x004 is ACR0")
check(controlRegisterFor(0x801'u16), crVbr,     "0x801 is VBR")
check(controlRegisterFor(0xC04'u16), crRambar0, "0xC04 is RAMBAR0")
check(controlRegisterFor(0xC05'u16), crRambar1, "0xC05 is RAMBAR1")
check(controlRegisterFor(0xC0F'u16), crMbar,    "0xC0F is MBAR")

# ---------------------------------------------------------------------------
# ACR1. The firmware does not write it and this part implements it, so a map
# built from the firmware's own set alone would answer every case above and
# fail this one.

check(controlRegisterFor(0x005'u16), crAcr1, "0x005 is ACR1")

# ---------------------------------------------------------------------------
# The aliased numbers, read through the extension word. These are the numbers
# a decoder that kept the 68k map answers with a different register, and the
# collision is the number one hazard.
#
#   0x004 and 0x005 are ITT0 and ITT1 on the 68040 and ACR0 and ACR1 here.
#   0x800 is USP on the 68040 and names no register of this part.

check(controlRegisterFor(movecControlField(0x0004'u16)), crAcr0,
    "extension word 0x0004 selects ACR0 and not ITT0")
check(controlRegisterFor(movecControlField(0x0005'u16)), crAcr1,
    "extension word 0x0005 selects ACR1 and not ITT1")
check(controlRegisterFor(movecControlField(0x0800'u16)), crUnimplemented,
    "extension word 0x0800 selects no register and is not USP")

# ---------------------------------------------------------------------------
# A number the ColdFire family assigns and this part does not implement.
# RAMBAR1 is the one number this core accepts on the family table alone, and
# without this case a map that accepted every family number would look the same
# as one that accepted the part's own.

check(controlRegisterFor(0x006'u16), crUnimplemented,
    "0x006 is ACR2 on the family and is not implemented here")

# ---------------------------------------------------------------------------
# The instruction driven through the shipped path.
#
# Every case above is a function of its arguments and not one of them reaches a
# machine. A suite that calls `controlRegisterFor` directly answers the same way
# whether or not any instruction can reach it, so a full pass of those cases
# alone is consistent with `MOVEC` decoding to nothing and trapping as an
# illegal opcode. The cases below run the encoding through `mcf5307_reset`,
# `mcf5307_set_reg`, `mcf5307_exec` and `mcf5307_get_reg` - four of the calls
# `include/mcf5307.h` publishes - so that the map above is asserted on the path
# a boot loader takes.
#
# This suite still compiles the core from source through `--path:src` and never
# links `libmcf5307.a`, so it cannot see a module that the entry module's import
# graph fails to reach. `conformance/runner.cpp` is what links the archive.

const
  execBase = 0x100'u32     ## where the instruction words are placed
  stackBase = 0x800'u32
  srSuper = 0x2700'u32     ## supervisor, interrupt mask 7 - the reset value
  srUser = 0x0700'u32      ## USER state with the same mask, so that a wrong
                           ## bit read is red rather than green by coincidence
  dirtyD = 0x12345678'u32
  dirtyA = 0x0BADC0DE'u32
  handlerBase = 0x400'u32  ## where the seeded vector-8 entry points
  vbrTableBase = 0x0010_0000'u32
    ## THE BASE IS ABOVE THE IMPLEMENTED-BIT BOUNDARY AND NOT AN ARBITRARY
    ## ADDRESS. `exception.nim` masks the vector base with `vbrImplementedMask`,
    ## so a base whose set bits all fall in the low twenty would dispatch from
    ## zero and a case built on it would pass against a core that ignored the
    ## register entirely.
  vbrHandlerBase = 0x0010_0400'u32
    ## Where the VBR-based vector-8 slot points.
  memSize = 0x0010_1000

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
    ## THE COST ITSELF IS PINNED, and not here. `tests/t_exec_budget.nim`
    ## holds the return of a budgeted call against a cost it MEASURES, for
    ## every budget in a sweep. What this field carries is the ran-or-trapped
    ## bit the rows below actually turn on, under a name that says so.
  fault: bool
  halted: bool
  d0: uint32
  a0: uint32
  sr: uint32
  pc: uint32
  a7: uint32

proc runIns(words: openArray[uint16]; sr: uint32;
            mem: seq[(uint32, uint32)] = @[]): Outcome =
  ## Place `words` at `execBase`, seed d0 and a0, run one `mcf5307_exec`, and
  ## report the whole machine state.
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  for i in 0 ..< words.len:
    boardWrite(board, execBase + 2'u32 * uint32(i), 2, uint32(words[i]))
  for (address, value) in mem:
    boardWrite(board, address, 4, value)

  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, stackBase, execBase)
  discard mcf5307_set_reg(ctx, 0, dirtyD)
  discard mcf5307_set_reg(ctx, 8, dirtyA)
  # The status register is set last, because `mcf5307_reset` writes it and an
  # earlier write would be overwritten - which would run every user-state case
  # in supervisor state and pass.
  discard mcf5307_set_reg(ctx, 16, sr)

  result.ran = mcf5307_exec(ctx, 1'u32) > 0'u32
  result.fault = ctx.fault
  result.halted = ctx.halted
  result.d0 = mcf5307_get_reg(ctx, 0)
  result.a0 = mcf5307_get_reg(ctx, 8)
  result.sr = mcf5307_get_reg(ctx, 16)
  result.pc = mcf5307_get_reg(ctx, 17)
  result.a7 = mcf5307_get_reg(ctx, 15)

proc ranAndConsumedBothWords(o: Outcome): auto =
  ## The shape every accepted `MOVEC` must produce. The program counter is the
  ## discriminating field: `MOVEC` is two words, so a core that consumed only
  ## the opcode word would leave the pc at `execBase + 2` and decode the
  ## extension word as the next instruction.
  (ran: o.ran, fault: o.fault, halted: o.halted, pc: o.pc,
   d0: o.d0, a0: o.a0, sr: o.sr, a7: o.a7)

const accepted = (ran: true, fault: false, halted: false,
                  pc: execBase + 4'u32, d0: dirtyD, a0: dirtyA,
                  sr: srSuper, a7: stackBase)
  ## Nothing architectural changes. The control registers this part carries are
  ## not modelled by this core, so an accepted `MOVEC` advances the program
  ## counter and touches no register the ABI can read.

# The numbers the firmware writes, plus ACR1, each driven as a whole instruction
# rather than as a bare register number. The pair of lists is the point: the
# identity cases above assert what
# the map says, and these assert that the machine consults it.

check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0002'u16], srSuper)),
    accepted, "movec %d0,CACR (0x002) executes")
check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0004'u16], srSuper)),
    accepted, "movec %d0,ACR0 (0x004) executes")
check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0005'u16], srSuper)),
    accepted, "movec %d0,ACR1 (0x005) executes")
check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0801'u16], srSuper)),
    accepted, "movec %d0,VBR (0x801) executes")
check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0C05'u16], srSuper)),
    accepted, "movec %d0,RAMBAR1 (0xC05) executes")
check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0C0F'u16], srSuper)),
    accepted, "movec %d0,MBAR (0xC0F) executes")

# The A/D bit is exercised once, and it is exercised through the machine. The
# extension word `0x8C04` names address register 0 as the source. The identity
# cases above assert that `movecSourceIsAddressRegister` reads bit 15; this
# asserts that an instruction carrying that bit still executes rather than
# being refused as a malformed encoding.

check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x8C04'u16], srSuper)),
    accepted, "movec %a0,RAMBAR0 (0xC04) executes with A/D set")

# A NUMBER THIS PART DOES NOT CARRY HALTS THE CORE, AND IT HALTS WITHOUT A
# FAULT. An access to unimplemented control register space produces undefined
# results, so the encoding is a valid `MOVEC` with only the destination absent
# from this part, which is the `opExg`/`opTas`/`opNbcd` shape `cpu.nim` already
# states: `halted` set and `fault` clear. A core that accepted these instead
# would run on with a register write that reached nothing.

const refused = (ran: false, fault: false, halted: true,
                 pc: execBase + 4'u32, d0: dirtyD, a0: dirtyA,
                 sr: srSuper, a7: stackBase)

check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0006'u16], srSuper)),
    refused, "movec %d0,0x006 halts: ACR2 is not on this part")

# `0x800` IS ASSIGNED TO NOTHING ON THIS PART. A fork that restored the 68k
# reading would make this number a register and this case is what goes red.

check(ranAndConsumedBothWords(runIns([0x4E7B'u16, 0x0800'u16], srSuper)),
    refused, "movec %d0,0x800 halts: it names no register of this part")

# THE PRIVILEGE, TAKEN AS AN EXCEPTION AND NOT AS A HALT. The privilege
# violation stacks the PC of the instruction that caused it, so the stacked
# value is `execBase` and NOT the address after either word: an `RTE` from the
# handler re-executes the whole instruction.

block:
  let o = runIns([0x4E7B'u16, 0x0C0F'u16], srUser,
                 mem = @[(4'u32 * 8'u32, handlerBase)])
  let got = (ran: o.ran, fault: o.fault, halted: o.halted, pc: o.pc,
             sr: o.sr, a7: o.a7, d0: o.d0,
             fv: boardReadValue(board, stackBase - 8'u32, 4),
             stackedPc: boardReadValue(board, stackBase - 4'u32, 4))
  # `fv` is format 4 (A7 was already longword aligned), FS 0 (this is not an
  # access error), vector 8, and the status register as it was before the
  # exception changed it. The handler runs with S set and T clear.
  let want = (ran: true, fault: false, halted: false, pc: handlerBase,
              sr: 0x2700'u32, a7: stackBase - 8'u32, d0: dirtyD,
              fv: 0x4020_0700'u32,
              stackedPc: execBase)
  check(got, want, "movec in user state takes the vector-8 privilege violation")

# ---------------------------------------------------------------------------
# THE VALUE THE INSTRUCTION CARRIES, READ BACK THROUGH THE ONLY CHANNEL A HOST
# HAS.
#
# EVERY REGISTER IS WRITTEN FROM A DIFFERENT SOURCE REGISTER AND EVERY SOURCE
# CARRIES A DIFFERENT VALUE. Two stores wired to each other's destination then
# leave BOTH read-backs holding a value that belongs to the other, and both
# cases go red; a single shared value would let a swap pass. The A/D bit and
# Ry are varied across the seven for the same reason: a store that read `d0`
# whatever the extension word named would answer every case that used `d0`.
#
# THE WHOLE CONTROL FILE IS ASSERTED PER CASE AND NOT ONLY THE REGISTER UNDER
# TEST. A store that wrote its value into every field would satisfy a
# single-field read-back.

const
  dSeed: array[8, uint32] = [
    0xD000_5A5A'u32, 0xD111_5A5A'u32, 0xD222_5A5A'u32, 0xD333_5A5A'u32,
    vbrTableBase or 0x0801'u32,
    0xD555_5A5A'u32, 0xD666_5A5A'u32, 0xD777_5A5A'u32]
      ## `d4` CARRIES A USABLE VECTOR BASE because it is the VBR case's source
      ## and the consumer case below dispatches through what it writes. Its low
      ## bits are set and are NOT part of the base: `vbrImplementedMask` drops
      ## them at the dispatch and the field keeps them, which is what separates
      ## a core that stores the written value from one that stores the masked
      ## one.
  aSeed: array[7, uint32] = [
    0xA000_5A5A'u32, 0xA111_5A5A'u32, 0xA222_5A5A'u32, 0xA333_5A5A'u32,
    0xA444_5A5A'u32, 0xA555_5A5A'u32, 0xA666_5A5A'u32]

type ControlFile = tuple[cacr, acr0, acr1, vbr, rambar0, rambar1, mbar: uint32]

const
  # The register-file indices the ABI publishes for the control registers.
  ixVbr = 18
  ixCacr = 19
  ixAcr0 = 20
  ixAcr1 = 21
  ixRambar0 = 22
  ixRambar1 = 23
  ixMbar = 24

  noControlRegisterWritten: ControlFile =
    (cacr: 0'u32, acr0: 0'u32, acr1: 0'u32, vbr: 0'u32,
     rambar0: 0'u32, rambar1: 0'u32, mbar: 0'u32)

proc controlFileOf(ctx: MCF5307Ctx): ControlFile =
  (cacr: mcf5307_get_reg(ctx, ixCacr),
   acr0: mcf5307_get_reg(ctx, ixAcr0),
   acr1: mcf5307_get_reg(ctx, ixAcr1),
   vbr: mcf5307_get_reg(ctx, ixVbr),
   rambar0: mcf5307_get_reg(ctx, ixRambar0),
   rambar1: mcf5307_get_reg(ctx, ixRambar1),
   mbar: mcf5307_get_reg(ctx, ixMbar))

proc seedContext(ctx: MCF5307Ctx) =
  ## Every data and address register carries a value no other register carries.
  for n in 0 .. 7:
    discard mcf5307_set_reg(ctx, cint(n), dSeed[n])
  for n in 0 .. 6:
    discard mcf5307_set_reg(ctx, cint(8 + n), aSeed[n])

proc freshSeededCtx(words: openArray[uint16];
                    mem: seq[(uint32, uint32)] = @[]): MCF5307Ctx =
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  for i in 0 ..< words.len:
    boardWrite(board, execBase + 2'u32 * uint32(i), 2, uint32(words[i]))
  for (address, value) in mem:
    boardWrite(board, address, 4, value)
  result = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(result, stackBase, execBase)
  seedContext(result)
  discard mcf5307_set_reg(result, 16, srSuper)

proc runControlWrite(ext: uint16): tuple[ctl: ControlFile, halted: bool,
                                         fault: bool, pc: uint32] =
  ## Execute one `movec` and report the whole control file behind it.
  let ctx = freshSeededCtx([0x4E7B'u16, ext])
  discard mcf5307_exec(ctx, 1'u32)
  (ctl: controlFileOf(ctx), halted: ctx.halted, fault: ctx.fault,
   pc: mcf5307_get_reg(ctx, 17))

proc landed(ext: uint16): auto =
  ## The shape an accepted `movec` produced: the whole control file, and the
  ## run state that says the instruction ran both its words.
  let o = runControlWrite(ext)
  (ctl: o.ctl, halted: o.halted, fault: o.fault, pc: o.pc)

proc onlyAt(position: int; value: uint32): ControlFile =
  ## The control file in which ONE register holds `value` and every other holds
  ## its reset value. `position` counts along `ControlFile`'s own order.
  var slots: array[7, uint32]
  slots[position] = value
  (cacr: slots[0], acr0: slots[1], acr1: slots[2], vbr: slots[3],
   rambar0: slots[4], rambar1: slots[5], mbar: slots[6])

proc landedWant(want: ControlFile): auto =
  (ctl: want, halted: false, fault: false, pc: execBase + 4'u32)

check(landed(0x1002'u16), landedWant(onlyAt(0, dSeed[1])),
      "movec %d1,CACR (0x002) stores d1 into CACR and nothing else")

check(landed(0x2004'u16), landedWant(onlyAt(1, dSeed[2])),
      "movec %d2,ACR0 (0x004) stores d2 into ACR0 and nothing else")

check(landed(0xB005'u16), landedWant(onlyAt(2, aSeed[3])),
      "movec %a3,ACR1 (0x005) stores a3 into ACR1 and nothing else")

check(landed(0x4801'u16), landedWant(onlyAt(3, dSeed[4])),
      "movec %d4,VBR (0x801) stores d4 unmasked into VBR and nothing else")

check(landed(0xDC04'u16), landedWant(onlyAt(4, aSeed[5])),
      "movec %a5,RAMBAR0 (0xC04) stores a5 into RAMBAR0 and nothing else")

check(landed(0x6C05'u16), landedWant(onlyAt(5, dSeed[6])),
      "movec %d6,RAMBAR1 (0xC05) stores d6 into RAMBAR1 and nothing else")

check(landed(0xEC0F'u16), landedWant(onlyAt(6, aSeed[6])),
      "movec %a6,MBAR (0xC0F) stores a6 into MBAR and nothing else")

# THE REFUSAL PATH WRITES NOTHING, AND IT IS ASSERTED AND NOT ASSUMED. A store
# placed ahead of the unimplemented-register test would leave the halt intact
# and this case is what separates the two orders.

block:
  let o = runControlWrite(0x0006'u16)
  check((ctl: o.ctl, halted: o.halted, fault: o.fault),
        (ctl: noControlRegisterWritten, halted: true, fault: false),
        "movec %d0,0x006 halts and writes no control register")

# ---------------------------------------------------------------------------
# RESET.
#
# THE CASE CARRIES THE STATE BEFORE THE RESET AS WELL AS THE STATE AFTER IT. A
# case that asserted only the zeros would pass against a core that never stored
# anything, which is the whole defect this file is closing.

block:
  let ctx = freshSeededCtx([0x4E7B'u16, 0x1002'u16,
                            0x4E7B'u16, 0x2004'u16,
                            0x4E7B'u16, 0xB005'u16,
                            0x4E7B'u16, 0x4801'u16,
                            0x4E7B'u16, 0xDC04'u16,
                            0x4E7B'u16, 0x6C05'u16,
                            0x4E7B'u16, 0xEC0F'u16])
  for _ in 0 .. 6:
    discard mcf5307_exec(ctx, 1'u32)
  let before = controlFileOf(ctx)
  mcf5307_reset(ctx, stackBase, execBase)
  let after = controlFileOf(ctx)
  # THE RESET VALUES ARE THE MANUAL'S. The MCF5307 User's Manual gives VBR
  # `$00000000` at reset, and gives the CACR and the ACRs all zeros. It gives
  # the RAMBARs and the MBAR only their valid bit cleared and calls the rest
  # uninitialised, so zero is a value that satisfies what the manual states
  # rather than one it states; `cpu.nim` carries the same note at the site.
  check((before: before, after: after),
        (before: (cacr: dSeed[1], acr0: dSeed[2], acr1: aSeed[3],
                  vbr: dSeed[4], rambar0: aSeed[5], rambar1: dSeed[6],
                  mbar: aSeed[6]),
         after: noControlRegisterWritten),
        "reset clears every control register the seven writes had filled")

# ---------------------------------------------------------------------------
# THE CONSUMER.
#
# STORING IS NOT THE DELIVERABLE. A core that kept the value in a field no
# dispatch consulted would pass every case above and would fail identically to
# one that discarded it. VBR is the one register of the seven this core
# consumes, so its case runs an exception AFTER the write and asserts that the
# handler address came from the base the instruction supplied.
#
# THE ZERO-BASED SLOT IS SEEDED WITH A DIFFERENT ADDRESS. A core that dispatched
# from zero would then reach a plausible handler rather than address zero, so
# the case separates "read the wrong base" from "read nothing at all".

const decoyHandler = 0x0000_0700'u32

block:
  let ctx = freshSeededCtx(
    [0x4E7B'u16, 0x4801'u16,   # movec %d4,VBR
     0x46FC'u16, 0x0700'u16,   # move.w #$0700,%sr - leave supervisor state
     0x4E7B'u16, 0xEC0F'u16],  # movec %a6,MBAR - privileged, so it violates
    mem = @[(vbrTableBase + 4'u32 * 8'u32, vbrHandlerBase),
            (4'u32 * 8'u32, decoyHandler)])
  for _ in 0 .. 2:
    discard mcf5307_exec(ctx, 1'u32)
  check((pc: mcf5307_get_reg(ctx, 17), vbr: mcf5307_get_reg(ctx, ixVbr),
         halted: ctx.halted, fault: ctx.fault,
         mbar: mcf5307_get_reg(ctx, ixMbar)),
        (pc: vbrHandlerBase, vbr: dSeed[4], halted: false, fault: false,
         mbar: 0'u32),
        "the exception after movec to VBR dispatches from the base it wrote")

# The registry lines. They are data and not a verdict: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_movec", declaredCaseSites)
echo caseSiteLine("executed", "t_movec", executedSites)
echo caseSiteLine("off-green-path", "t_movec", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_movec: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_movec: ", passCount, " cases passed"
