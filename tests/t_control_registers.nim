## `t_control_registers` - the control registers AS CHANNELS: the vector base a
## dispatch consults, and the register file a snapshot carries across a save,
## a run and a load.
##
## WHAT THIS FILE COVERS AND WHAT IT DOES NOT, STATED AT THE TOP BECAUSE A
## GREEN RUN OF A PARTIAL SUITE READS EXACTLY LIKE A GREEN RUN OF A COMPLETE
## ONE. FOUR CLAUSES ARE IN QUESTION AND THIS FILE CARRIES TWO OF THEM:
##
##   CLAUSE 1, the vector base. Covered below, end to end: the base arrives by
##   `MOVEC`, the exception is raised by running an instruction through
##   `mcf5307_exec`, and the handler address adjudicates.
##
##   CLAUSE 4, the serialized fields. Covered below: the seven registers
##   survive a save, a run and a load, and a byte perturbed inside the register
##   region of the block is refused BY NAME.
##
##   CLAUSE 2, the module base as a channel to the board, IS NOT COVERED HERE
##   and no case below stands in for it. It needs a declaration this core's
##   published header does not carry and a consumer that lives in another
##   repository.
##
##   CLAUSE 3, the write-protect refusal, IS NOT COVERED HERE either. This core
##   has no consumer of RAMBAR0, and the operand-write path that would have to
##   raise the access error is in a module this file does not reach.
##
## THE READ-BACK IS NEVER THE VERDICT IN BLOCK 1. A core that stores a value in
## a field no dispatch consults fails IDENTICALLY to one that discards it, and
## passes every read-back assertion. So the read-back is carried in each tuple
## as DESCRIPTION and the handler address is what adjudicates.
##
## The vector numbers, the 1 MByte vector-table alignment and the unimplemented
## low bits of VBR are facts about Motorola silicon, from the MCF5307 User's
## Manual (1998) and the ColdFire Family Programmer's Reference Manual, Rev. 3.

import mcf5307/cpu
import mcf5307/decode_types
import mcf5307/exception
import mcf5307/machine
import mcf5307/state

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
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, got, want, label)

# ---------------------------------------------------------------------------
# The board. One flat byte array, big-endian, as `t_exception`'s and
# `t_movec`'s.
#
# IT RECORDS EVERY READ INSIDE EITHER VECTOR TABLE AND NOTHING ELSE. Two tables
# are in play - the zero-based one and the one at `vbrTableBase` - and a read of
# EITHER is recorded, so a core that read the wrong table names the address it
# read rather than leaving an empty list. `execBase` is above the whole
# 1024-byte zero-based table, so no instruction fetch enters the log.

const
  vbrTableBase = 0x0010_0000'u32
    ## 1 MByte, THE SMALLEST NON-ZERO BASE THIS PART CAN HOLD. VBR[19-0] are
    ## not implemented, so a base whose set bits all fall in the low twenty
    ## would dispatch from zero and a case built on it would pass against a
    ## core that ignored the register entirely.
  memSize = int(vbrTableBase) + 0x1000
  execBase = 0x400'u32      ## above the whole 1024-byte zero-based table
  stackBase = 0x800'u32
  frameBase = stackBase - 8'u32
  srSuper = 0x2700'u32      ## supervisor, interrupt mask 7 - the reset value
  vecTrap0 = 32'u8          ## `trap #0` is vector 32, at $080
  opTrap0 = 0x4E40'u16      ## `trap #0`, m68k-elf-as -mcpu=5307
  opMovec = 0x4E7B'u16
  vbrHandler = 0x0010_0400'u32
    ## Where the VBR-based vector-32 slot points.
  decoyHandler = 0x0000_0500'u32
    ## Where the ZERO-BASED vector-32 slot points. THE DECOY IS WHAT SEPARATES
    ## "read the wrong base" FROM "read nothing at all": without it a core
    ## dispatching from zero would fetch a zero and the case would fail with a
    ## handler address that names no table.

type TestBoard = object
  bytes: array[memSize, uint8]

var board: TestBoard
var vectorReads: seq[uint32]

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
  if address < vectorTableBytes or
     (address >= vbrTableBase and address - vbrTableBase < vectorTableBytes):
    vectorReads.add(address)
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

proc freshBoard(words: openArray[uint16]) =
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  for i in 0 ..< words.len:
    boardWrite(board, execBase + 2'u32 * uint32(i), 2, uint32(words[i]))
  vectorReads = @[]

# The register-file indices the ABI publishes. `include/mcf5307.h` states the
# whole map; these are the entries this file reads.
const
  ixD0 = 0
  ixD1 = 1
  ixD2 = 2
  ixD4 = 4
  ixD6 = 6
  ixA3 = 11
  ixA5 = 13
  ixA6 = 14
  ixSp = 15
  ixPc = 17
  ixVbr = 18
  ixCacr = 19
  ixAcr0 = 20
  ixAcr1 = 21
  ixRambar0 = 22
  ixRambar1 = 23
  ixMbar = 24

# ---------------------------------------------------------------------------
# BLOCK 1. THE VECTOR BASE, DRIVEN THROUGH THE PUBLISHED PATH.
#
# The base arrives by `MOVEC` and the exception is raised by RUNNING `trap #0`
# through `mcf5307_exec`, so nothing here reaches around the back of the core
# to call the dispatch directly. `movec %d4,VBR` is `0x4E7B 0x4801`.
#
# THE SOURCE VALUE CARRIES LOW BITS THAT ARE NOT PART OF THE BASE. VBR[19-0]
# are not implemented: the field keeps what the instruction wrote and the
# dispatch drops the low bits, which separates a core that stores the written
# value from one that stores a masked value.

const vbrSource = vbrTableBase or 0x0801'u32

type Dispatched = tuple[ran: bool, vbrReadBack: uint32, pc: uint32,
                        sp: uint32, halted: bool, fault: bool,
                        stackedPc: uint32, reads: seq[uint32]]

proc runMovecVbrThenTrap(source: uint32): Dispatched =
  ## `movec %d4,VBR` then `trap #0`, both through `mcf5307_exec`.
  freshBoard([opMovec, 0x4801'u16, opTrap0])
  boardWrite(board, vectorAddress(vbrTableBase, vecTrap0), 4, vbrHandler)
  boardWrite(board, vectorAddress(0'u32, vecTrap0), 4, decoyHandler)

  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, stackBase, execBase)
  discard mcf5307_set_reg(ctx, ixD4, source)
  let movecRan = mcf5307_exec(ctx, 1'u32) > 0'u32
  discard mcf5307_exec(ctx, 1'u32)
  result = (ran: movecRan,
            vbrReadBack: mcf5307_get_reg(ctx, ixVbr),
            pc: mcf5307_get_reg(ctx, ixPc),
            sp: mcf5307_get_reg(ctx, ixSp),
            halted: mcf5307_halted(ctx) != 0,
            fault: mcf5307_faulted(ctx) != 0,
            stackedPc: boardReadValue(board, frameBase + 4'u32, 4),
            reads: vectorReads)
  mcf5307_destroy(ctx)

# THE STACKED PROGRAM COUNTER IS `execBase + 6`. `MOVEC` is two words and
# `trap #0` is one, and a trap stacks the address after the instruction that
# caused it.

check(runMovecVbrThenTrap(vbrSource),
      (ran: true, vbrReadBack: vbrSource, pc: vbrHandler, sp: frameBase,
       halted: false, fault: false, stackedPc: execBase + 6'u32,
       reads: @[vbrTableBase + 0x080'u32]),
      "movec to VBR then trap #0: the handler comes from the relocated table")

# A ZERO BASE STILL DISPATCHES FROM THE ZERO-BASED TABLE. Without this case a
# core that hardcoded the dispatch at `vbrTableBase` - the mutation's mirror
# image - would satisfy the case above and nothing here would say so.

check(runMovecVbrThenTrap(0'u32),
      (ran: true, vbrReadBack: 0'u32, pc: decoyHandler, sp: frameBase,
       halted: false, fault: false, stackedPc: execBase + 6'u32,
       reads: @[0x080'u32]),
      "movec 0 to VBR then trap #0: the handler comes from $080")

# ---------------------------------------------------------------------------
# BLOCK 2. THE SEVEN REGISTERS ACROSS A SAVE, A RUN AND A LOAD.
#
# EVERY REGISTER CARRIES A DIFFERENT VALUE AND EVERY SOURCE IS A DIFFERENT
# REGISTER. Two fields wired to each other's slot then leave BOTH read-backs
# holding a value that belongs to the other; a single shared value would let a
# swap pass.
#
# THE RUN BETWEEN THE SAVE AND THE LOAD IS `movec %d0,VBR`, which OVERWRITES a
# register the block carries. A load that restored nothing would leave the new
# value in place, and a load that restored a zeroed block would leave zero;
# both are red against the tuple below.

const
  cacrSeed = 0xC1C1_0002'u32
  acr0Seed = 0xA0A0_0004'u32
  acr1Seed = 0xA1A1_0005'u32
  rambar0Seed = 0xB0B0_0C04'u32
  rambar1Seed = 0xB1B1_0C05'u32
  mbarSeed = 0xB2B2_0C0F'u32
  vbrAfterRun = 0x0020_0000'u32
    ## The base `movec %d0,VBR` writes AFTER the save. It differs from
    ## `vbrSource` in an IMPLEMENTED bit, so a load that failed to restore VBR
    ## is visible rather than masked away at the dispatch.

  # `movec %d1,CACR`, `%d2,ACR0`, `%a3,ACR1`, `%d4,VBR`, `%a5,RAMBAR0`,
  # `%d6,RAMBAR1`, `%a6,MBAR`, then `%d0,VBR` as the run after the save.
  controlProgram = [
    opMovec, 0x1002'u16,
    opMovec, 0x2004'u16,
    opMovec, 0xB005'u16,
    opMovec, 0x4801'u16,
    opMovec, 0xDC04'u16,
    opMovec, 0x6C05'u16,
    opMovec, 0xEC0F'u16,
    opMovec, 0x0801'u16]
  writeCount = 7
    ## The instructions ahead of the save.

type ControlFile = tuple[cacr, acr0, acr1, vbr, rambar0, rambar1, mbar: uint32]

const seededFile: ControlFile =
  (cacr: cacrSeed, acr0: acr0Seed, acr1: acr1Seed, vbr: vbrSource,
   rambar0: rambar0Seed, rambar1: rambar1Seed, mbar: mbarSeed)

proc controlFileOf(ctx: MCF5307Ctx): ControlFile =
  (cacr: mcf5307_get_reg(ctx, ixCacr),
   acr0: mcf5307_get_reg(ctx, ixAcr0),
   acr1: mcf5307_get_reg(ctx, ixAcr1),
   vbr: mcf5307_get_reg(ctx, ixVbr),
   rambar0: mcf5307_get_reg(ctx, ixRambar0),
   rambar1: mcf5307_get_reg(ctx, ixRambar1),
   mbar: mcf5307_get_reg(ctx, ixMbar))

proc seededCtx(): MCF5307Ctx =
  freshBoard(controlProgram)
  result = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(result, stackBase, execBase)
  discard mcf5307_set_reg(result, ixD0, vbrAfterRun)
  discard mcf5307_set_reg(result, ixD1, cacrSeed)
  discard mcf5307_set_reg(result, ixD2, acr0Seed)
  discard mcf5307_set_reg(result, ixA3, acr1Seed)
  discard mcf5307_set_reg(result, ixD4, vbrSource)
  discard mcf5307_set_reg(result, ixA5, rambar0Seed)
  discard mcf5307_set_reg(result, ixD6, rambar1Seed)
  discard mcf5307_set_reg(result, ixA6, mbarSeed)
  for _ in 1 .. writeCount:
    discard mcf5307_exec(result, 1'u32)

proc be32(bytes: seq[uint8]; at: int): uint32 =
  (uint32(bytes[at]) shl 24) or (uint32(bytes[at + 1]) shl 16) or
    (uint32(bytes[at + 2]) shl 8) or uint32(bytes[at + 3])

var savedBlock = newSeq[uint8](int(mcf5307_state_size()))
var afterFirstRun: ControlFile
var pcAfterFirstRun = 0'u32

block:
  let ctx = seededCtx()
  let atSave = controlFileOf(ctx)
  let pcAtSave = mcf5307_get_reg(ctx, ixPc)
  mcf5307_state_save(ctx, addr savedBlock[0])

  discard mcf5307_exec(ctx, 1'u32)
  afterFirstRun = controlFileOf(ctx)
  pcAfterFirstRun = mcf5307_get_reg(ctx, ixPc)

  let status = stateLoad(ctx, addr savedBlock[0])
  let restored = controlFileOf(ctx)
  let pcRestored = mcf5307_get_reg(ctx, ixPc)

  discard mcf5307_exec(ctx, 1'u32)
  let afterSecondRun = controlFileOf(ctx)
  let pcAfterSecondRun = mcf5307_get_reg(ctx, ixPc)
  mcf5307_destroy(ctx)

  check((ctl: atSave, pc: pcAtSave),
        (ctl: seededFile, pc: execBase + 4'u32 * uint32(writeCount)),
        "the seven writes land before the save")

  # THE RUN BETWEEN THE SAVE AND THE LOAD REALLY CHANGES THE STATE. Without
  # this case the round trip below would pass against a core whose `MOVEC` did
  # nothing at all after the save, and the load would have restored a state it
  # never left.
  check((ctl: afterFirstRun, pc: pcAfterFirstRun),
        (ctl: (cacr: cacrSeed, acr0: acr0Seed, acr1: acr1Seed,
               vbr: vbrAfterRun, rambar0: rambar0Seed, rambar1: rambar1Seed,
               mbar: mbarSeed),
         pc: execBase + 4'u32 * uint32(writeCount + 1)),
        "the run after the save overwrites VBR")

  check((status: status, ctl: restored, pc: pcRestored),
        (status: stateOk, ctl: seededFile,
         pc: execBase + 4'u32 * uint32(writeCount)),
        "the load restores the seven registers and the program counter")

  check((ctl: afterSecondRun, pc: pcAfterSecondRun),
        (ctl: afterFirstRun, pc: pcAfterFirstRun),
        "the re-run after the load ends in the state the first run reached")

# THE REGISTER REGION OF THE BLOCK IS LOCATED BY READING IT, and not by
# trusting an offset written here. The header is 12 bytes and `state.nim`'s
# walk puts the control registers after the program counter, the stack
# pointer, the status register, the two register files and the two flags. The
# two cases below are what make the perturbation site below a REGISTER byte
# rather than an address this file hopes is one.

const
  vbrByteOffset = 86
  mbarByteOffset = 110

check(be32(savedBlock, vbrByteOffset), vbrSource,
      "the block carries VBR at byte 86")
check(be32(savedBlock, mbarByteOffset), mbarSeed,
      "the block carries MBAR at byte 110")

# A PERTURBED BYTE IN THE REGISTER REGION IS REFUSED BY NAME, AND THE CONTEXT
# IS LEFT ALONE. A load that accepted the block would report `stateOk` and
# carry a register value nothing wrote; a load that refused it but decoded
# first would leave the context half restored.

proc loadPerturbed(at: int): tuple[status: StateStatus, ctl: ControlFile] =
  var damaged = savedBlock
  damaged[at] = damaged[at] xor 0x01'u8
  let ctx = seededCtx()
  discard mcf5307_exec(ctx, 1'u32)
  let status = stateLoad(ctx, addr damaged[0])
  result = (status: status, ctl: controlFileOf(ctx))
  mcf5307_destroy(ctx)

check(loadPerturbed(vbrByteOffset),
      (status: stateBadChecksum, ctl: afterFirstRun),
      "a perturbed VBR byte is refused as a bad checksum, context untouched")

check(loadPerturbed(mbarByteOffset),
      (status: stateBadChecksum, ctl: afterFirstRun),
      "a perturbed MBAR byte is refused as a bad checksum, context untouched")

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_control_registers", declaredCaseSites)
echo caseSiteLine("executed", "t_control_registers", executedSites)
echo caseSiteLine("off-green-path", "t_control_registers",
                  declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_control_registers: ", failures.len, " of ",
      failures.len + passCount, " cases failed"
  quit(1)
else:
  echo ""
  echo "t_control_registers: ", passCount, " cases passed"
