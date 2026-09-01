## `t_ea_masks` - the decoder and effective-address legality masks.
##
## The skip rule, stated once. An operation is outside the domain when and
## only when `eaLegalityFor` returns an empty mask. That is the same test
## `eaIsLegalFor` already makes, and that proc's own doc comment in
## `decode_types.nim` says why a second list of the same operations drifts.
## Nothing here is skipped for being unreachable from the decoder: a skip
## justified by reachability would have skipped `SWAP`, which the PEA mask was
## hiding while `cpu.nim` carried the sentence "no arm produces `opSwap`".
##
## The driver iterates `Operation` and requires a coverage entry for every
## operation whose mask is non-empty, so an operation added to the table with
## no entry makes the run red in the wave that added it. The reverse direction
## is checked too: an entry for an operation whose mask has gone empty is a
## stale entry and is also red.
##
##   (4) The extension-word order of absolute long addressing, with its own
##       control. `(xxx).L` carries the high half of the address in the first
##       extension word. No case in `conformance/corpus/` uses an absolute-long
##       operand at all, so nothing else in this project can see a core that
##       reads the two words the other way round. The block near the end of
##       this file says which manual section that is and why the control is
##       there.
##
## The illegal mode of each entry is sourced from the manual and never from
## `eaLegalityFor`, and that is what keeps the file from proving nothing. A
## driver that asked `eaLegalityFor` which mode is outside the mask and then
## asserted `eaIsLegalFor` rejects it would be asserting the mask against
## itself: it would pass against any mask, including a wrong one, and a
## widened mask would move the asserted mode with it. Every `illegal` field
## below carries its own citation, so a mask that widens to admit that mode
## turns the entry red instead of moving it. A widening that admits some other
## mode is invisible to the entry; block (19) covers that direction for the
## whole domain, by holding each mask against a literal rather than by naming
## one mode.
##
## Four assertions per operation, and each one can fail.
##
##   (1) The predicate rejects the illegal mode. This catches a mask widened
##       to admit the mode the entry cites, and nothing else: each entry names
##       exactly one illegal mode, so a mask that widens somewhere else passes
##       (1) unchanged.
##
##   (2) The predicate accepts a legal mode - the positive control. Without
##       it, a mask that rejected everything would report (1) as a pass and
##       "the illegal mode is rejected" would not be separable from "the
##       opcode admits no mode at all".
##
##   (3) The executor runs the legal mode. It is the control for (4) and it
##       does two jobs: it proves the operand, size and family of the entry
##       are a combination the executor accepts, so that a fault in (4)
##       cannot be blamed on a mis-set size or a mis-routed family, and it
##       proves the refusal in (4) is attributable to the effective address,
##       which is the only field that differs between the two runs.
##
##   (4) The executor refuses the illegal mode. The refusal is asserted as a
##       whole state and not as a flag: `fault` set, `halted` set, zero cycles
##       returned, zero bus accesses, and every data register, address
##       register, stack pointer, program counter and status-register bit
##       unchanged. A refusal that ran part of the instruction first is not a
##       refusal. The address half of that is real only because `aRegSeed`
##       seeds the address registers distinctly: while all seven held
##       `ramBase`, an operation that copied one address register into another
##       before refusing passed.
##
## Two more run for the Table 3-13 entries alone, one per axis of the citation,
## and each holds a declared value against an independent recording of the same
## fact rather than against the value itself. The numbering skips (5) and (6),
## which are the two older assertions described further down.
##
##   (7) The page. Derived from the operation's mnemonic through the table's
##       own row ordering and compared against the page the entry declared.
##       The block defining `Table313Page` below carries the argument. What it
##       catches is a mis-declared page held against a fixed break: a lone
##       mis-declaration is red, while a co-edit that moves the break constant
##       and the declarations together goes green past (7), and (9) is what
##       refuses that, at compile time.
##
##   (8) The `#xxx` column. Derived by running the entry twice with different
##       immediates and comparing the two outcomes, which is the operational
##       content of that column. `table313ImmOf` carries the argument, the two
##       measured directions, and the limit.
##
## And three cover the table and the enumeration rather than any one operation.
##
##   (9) `table313LastRowOn328` held against `decode_types.nim`, which records
##       the same page break in its own `table313LastRowOnPage328`. A
##       `static: doAssert`, so a co-edit of the constant and the declarations
##       fails the build. It is not held against the declarations it validates
##       - that would be the tautology - but against that third record.
##
##  (10) Every `Operation` member name begins with `op`, the property the
##       mnemonic derivation behind (7) rests on.
##
##  (11) Every `coverage` row cites a manual table for its `illegal` mode,
##       which is the "every" the anti-tautology paragraph above rests on.
##       `why` is required by `cov`, so a row cannot omit a citation but can
##       pass one citing nothing; (11) requires each to name a manual table.
##
## Assertion (4) is not equally strong for every operation, and the entries say
## so. Some operations carry a mask whose complement the machine layer already
## refuses. For those the executor does refuse the illegal operand, and the
## refusal is real, but it cannot be attributed to the operation's own guard:
## deleting the guard leaves a machine-layer fallback to fault in its place.
## Those carry `discriminating: false`. The rest carry `discriminating: true`:
## deleting the operation's guard makes the entry red.
##
## The criterion is the complement of the mask and not a roster of opcode
## names, so a new such operation is recognized by reading `ea.nim` rather than
## by remembering this paragraph. Two masks meet it, for two different reasons.
##
##   - MOVE, MOVEA, ADD, SUB, ADDA, SUBA, TST, CMP and CMPA carry
##     `eaAllModes`/`eaValid7`, which admits every addressing mode Table 3-5
##     p.3-21 prints. The only encodings outside it are the reserved mode-7
##     ones, and `machine.nim`'s `eaAddr` and `eaRead` fault on those
##     independently of any mask.
##
##   - ADDQ and SUBQ carry `eaAllModes`/`eaAlterable7`, whose mode-7
##     half is `{ea7AbsW, ea7AbsL}`. `machine.nim`'s `eaResolve` accepts
##     exactly those two mode-7 encodings as a destination and faults on every
##     other one, so the complement of this mask and the set `eaResolve`
##     refuses are the same set. `(d16,PC)` is therefore not an unlucky pick:
##     no choice of illegal operand makes these two entries discriminating,
##     and one chosen to look stronger would only hide that.
##
## Those non-discriminating guards are unprotected by anything the repository
## runs. It is not a live defect - the machine layer refuses the same operands
## today - but a latent one: the day a machine-layer fallback changes, nothing
## here says so. Closing it needs a case whose illegal operand is a mode the
## machine layer would otherwise execute happily, and by the criterion above no
## such mode exists for these masks.
##
## A NARROWED MASK IS INVISIBLE TO EVERY `coverage` ENTRY. Each entry names
## exactly ONE legal mode, so a mask NARROWED to
## that single mode passes all four assertions unchanged: (1) still rejects the
## cited illegal mode, (2) still accepts the one legal mode the entry names,
## and (3) and (4) drive those same two operands and nothing else. Most entries
## name `Dn`, so ONE narrowing to `{eaDn}` is invisible here for all of those at
## once; the control-addressing entries name `(An)`, and a narrowing to
## `{eaAnInd}` is invisible for those. The discriminating flag is about
## assertion (4)'s ATTRIBUTION and says nothing at all about narrowing.
##
## The other two assertions the file has always carried are kept.
##
##   (5) The first non-zero cycle return, driven through the real ABI with a
##       board that returns `MCF5307_BUS_OK` and a `NOP` for every fetch. A
##       core that returns zero cycles cannot loop at all, so this separates
##       "the decoder ran" from "the decoder is not wired in".
##
##   (6) The decoder recognizes a representative word for each of a handful of
##       opcodes, so that the legality assertions are attached to a decoder
##       that runs and not only to a table.
##
## And one assertion about the table itself rather than about any operation.
## The enumeration takes the first `coverage` row matching each operation, so a
## second row for an operation that already has one runs nothing and reports
## nothing. The count of rows written is therefore held against the count of
## rows reached, a dead row is red, and the red names the rows that ran
## nothing.
##
## There is no supervisor and user stack split on ISA_A; the context holds the
## single `sp`.

import std/[options, strutils]
import mcf5307/cpu
import mcf5307/decode
import mcf5307/decode_types
import mcf5307/ea
import mcf5307/move
import mcf5307/alu
import mcf5307/logic
import mcf5307/control
import mcf5307/machine

var failures: seq[string]
import ./case_sites

var passCount = 0

## The figures the summary line carries, counted while the enumeration runs
## and never written down: a hardcoded figure goes stale silently. These are
## incremented by the loop, so they describe this run.
##
## The domain and the covered set are counted separately because they come
## apart exactly when it matters. `opsInDomain` counts operations with a
## non-empty mask - the population the file claims to cover. `opsCovered`
## counts those an entry actually reached. They are equal in a green run and
## differ in a run where an operation gained a mask and no entry; collapsing
## them into one counter makes the summary report a smaller domain in
## precisely that run.
var opsInDomain = 0
var opsCovered = 0
var opsDiscriminating = 0

const guardMeasurementDate = "2026-08-10"
  ## The date of the guard-deletion measurement behind `discriminating`. The
  ## summary line carries it so a reader of a bare log can tell how old that
  ## evidence is.

proc checkImpl(site: int; cond: bool; label: string) =
  if cond:
    echo "PASSED  ", label
    inc passCount
    executedSites.add(site)
  else:
    echo "FAILED  ", label
    failures.add(label)
    executedSites.add(site)


template check(cond: bool; label: string) =
  ## THE CALL SITE IS RECORDED TWICE - once at COMPILE TIME into
  ## `declaredSites` by the `static` below, and once at RUN TIME into
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, cond, label)

template checkOffGreenPath(cond: bool; label: string) =
  ## THE ONE SITE IN THIS REPOSITORY A GREEN RUN DOES NOT REACH,
  ## and it is written with its own template so that the exemption
  ## is visible HERE and not in a list the driver keeps. Its only
  ## call reports an operation whose legality mask is non-empty
  ## and for which no `coverage` entry exists: when that call runs
  ## the suite is already failing, so requiring it to have run
  ## would make a healthy tree red. `tests/case_sites.nim` states
  ## the rule the driver applies to the three registries.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  static: offGreenPathSites.add(site)
  checkImpl(site, cond, label)
proc checkDetailImpl(site: int; cond: bool; label: string; got: string) =
  if cond:
    echo "PASSED  ", label
    inc passCount
    executedSites.add(site)
  else:
    echo "FAILED  ", label
    echo "          got  ", got
    failures.add(label)
    executedSites.add(site)


template checkDetail(cond: bool; label: string; got: string) =
  ## THE CALL SITE IS RECORDED TWICE - once at COMPILE TIME into
  ## `declaredSites` by the `static` below, and once at RUN TIME into
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkDetailImpl(site, cond, label, got)
# ---------------------------------------------------------------------------
# The board for the non-zero-cycle run: `MCF5307_BUS_OK` and a NOP for every
# fetch.

proc readNop(user: pointer; address: uint32; size: cint;
             status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  status[] = Mcf5307BusStatus.busOk
  result = 0x4E71'u32   # NOP

proc writeNoop(user: pointer; address: uint32; size: cint; value: uint32;
               status: ptr Mcf5307BusStatus) {.cdecl.} =
  discard

proc iackNoop(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

# ---------------------------------------------------------------------------
# (5) The first non-zero cycle return, driven through the real ABI.

block:
  let ctx = mcf5307_create(nil, readNop, writeNoop, iackNoop)
  mcf5307_reset(ctx, 0x4000000'u32, 0x100'u32)
  let cycles = mcf5307_exec(ctx, 64'u32)
  check(cycles > 0'u32, "exec runs a NOP fetch and returns non-zero cycles")
  mcf5307_destroy(ctx)

# ---------------------------------------------------------------------------
# The board the executor assertions run on. One flat byte array, big-endian,
# the shape `t_move` and `t_alu` established. It counts its accesses: a
# refusal that touched the bus before refusing is not a refusal, and the
# count is what assertion (4) reads to say so.

const memSize = 0x1000

type TestBoard = object
  bytes: array[memSize, uint8]

var board: TestBoard
var busAccesses = 0

proc bRead(user: pointer; address: uint32; size: cint;
           status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  inc busAccesses
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return 0'u32
  status[] = Mcf5307BusStatus.busOk
  for i in 0 ..< int(size):
    result = (result shl 8) or uint32(b.bytes[int(address) + i])

proc bWrite(user: pointer; address: uint32; size: cint; value: uint32;
            status: ptr Mcf5307BusStatus) {.cdecl.} =
  inc busAccesses
  let b = cast[ptr TestBoard](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5307BusStatus.busUnmapped
    return
  status[] = Mcf5307BusStatus.busOk
  for i in 0 ..< int(size):
    b.bytes[int(address) + i] =
      uint8((value shr ((int(size) - 1 - i) * 8)) and 0xFF'u32)

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

const
  execBase = 0x100'u32    ## where the program counter starts
  stackBase = 0x800'u32   ## the single A7, inside the board
  ramBase = 0x400'u32     ## where A0 points, and where the A-seeds start
  dRegSeedMustBeNonZero = 0x00000007'u32
  aRegSeedStrideMustBeNonZero = 0x4'u32
  srAfterResetMustMatchCpuNim = 0x2700'u32
    ## What `mcf5307_reset` leaves in the status register - `cpu.nim`'s
    ## `mcf5307_reset` writes `ctx.sr = 0x2700'u32` - from the G2 reset
    ## vector's `move.w #$2700,%sr`. `runFamily` seeds every other
    ## register `pristine` reads, so this is its one copy of PRODUCTION state.
    ## Not imported from `cpu.nim`: one shared symbol would hide a wrong value.
func aRegSeed(i: int): uint32 = ramBase + uint32(i) * aRegSeedStrideMustBeNonZero
static:
  for i in 0 .. 7: doAssert dRegSeedMustBeNonZero + uint32(i) != 0'u32
  for i in 1 .. 6: doAssert aRegSeed(i) > aRegSeed(i - 1)

## Table 3-13 spans two pages, so the page is a parameter and not a default.
## The table begins on p.3-28 and continues on p.3-29, and three of the rows
## cited below - `ori.l`, `subi.l` and `subx.l` - are on the continuation
## page. Both pages were read rendered.
##
## One shared constant cannot hold two pages. Two constants would not close it
## either: a further entry would pick one of them, and picking the wrong one is
## exactly as silent as before.
##
## A required parameter is what cannot flatten. The page is not defaultable,
## so an entry cannot inherit a page it never stated; and `Table313Page` is an
## enum, so the only two spellings are the two pages the table actually spans
## and a typo is a compile error rather than a wrong citation.
##
## But a required parameter makes the choice unavoidable and not correct, which
## is why assertion (7) exists: an entry can write `p313Start` for a row that
## prints on 3-29 and nothing in the parameter says so. What (7) does not close
## is the co-edit: move the break constant and the declarations together and
## the two go green past each other, which is assertion (9)'s subject.
##
## SO THE PAGE IS DERIVED AND THE DECLARED ONE IS CHECKED AGAINST IT. The
## derivation rests on a property of the table that was read from the RENDERED
## p.3-28 and p.3-29 and NOT from any text extraction of them:
##
##   - The p.3-28 half runs `add.l` to `mulu.l`; the p.3-29 half opens `or.l`
##     and ends `subx.l`, after which section 3.12 begins.
##   - The table is NOT strictly alphabetical, and the derivation does not
##     claim it is: p.3-28 prints `moveq` AFTER `msac`. THE DISORDER IS NOT
##     LOCAL TO THE `m` CLUSTER: the same rendered p.3-28 also prints `divu.w`
##     before `divs.l`, `mulu.w` before `muls.l`, and `msac.l` before the
##     second `mac.w`. What the derivation needs is not local order anywhere
##     on the page; it is the BREAK, and none of these straddle it.
##   - What IS true, and all the derivation needs, is that the page break falls
##     on a LEXICOGRAPHIC boundary: every opcode row on p.3-28 sorts at or
##     before `mulu`, and every opcode row on p.3-29 sorts after it. Checked
##     row by row against both rendered pages.
##
## WHY THIS IS SAFE TO DERIVE FROM THE ENTRY'S OWN MNEMONIC: for all twelve
## entries the `Operation` member name minus its `op` prefix IS the table
## row's opcode with the size suffix removed - `opAndi` against `andi.l`,
## `opSubx` against `subx.l`. Checked entry by entry against both rendered
## pages.
##
## WHERE THAT STOPS HOLDING, THE ENTRY GOES RED ONLY IF THE MISMATCH CROSSES
## THE BREAK. A member renamed so that its mnemonic still sorts on the SAME
## side of `table313LastRowOn328` derives the page the entry already declares,
## and (7) passes with the name and the row now naming different things. THAT
## RENAME WAS NOT RUN: this limit is REASONED from `table313PageOf`, whose
## three lines are directly below and whose comparison is a single `<=`, and it
## is not a transcript. It is also the conservative direction - it describes
## something the assertion does NOT catch - so an unmeasured version of it
## understates the check rather than overstating it.
##
## A MEMBER WHOSE NAME DOES NOT BEGIN WITH `op` fails through the `doAssert` in
## `table313PageOf`, which is a crash rather than a case. Assertion (10) makes
## the absence of such a member a property this run asserts over the WHOLE
## enumeration, not just the twelve members `table313PageOf` is called with.
type
  Table313Page = enum
    p313Start = "3-28"   ## where Table 3-13 begins
    p313Cont = "3-29"    ## the continuation page

const table313LastRowOn328 = "mulu"
  ## The last opcode Table 3-13 prints on p.3-28, read from the rendered page.
  ## The derivation below is a comparison against THIS and nothing else, so a
  ## reprint that moves the break is one edit here.

## (9) THE BREAK CONSTANT, HELD AGAINST `decode_types.nim`'s RECORD OF IT.
## Assertion (7) compares each declaration against a derivation that reads this
## constant, so without this the constant would be the one term in that
## comparison with nothing behind it: moving it and the twelve declarations in
## ONE edit moved them past each other and printed a false page as PASSED. The
## co-edit now has to move a second file. The comparison lives HERE and
## `table313LastRowOnPage328` is EXPORTED for it because this file imports the
## source and the source cannot import this file without shipping test code.
## ITS LIMIT: both records were declared in the same change, so (9) detects
## drift and does not corroborate against an independent authority.
static:
  doAssert table313LastRowOn328 == table313LastRowOnPage328,
    "`table313LastRowOn328` is the last p.3-28 row `decode_types.nim` " &
    "records: this file declares \"" & table313LastRowOn328 &
    "\" and that file records \"" & table313LastRowOnPage328 & "\""

func table313PageOf(op: Operation): Table313Page =
  ## The page Table 3-13 prints this operation's row on, DERIVED. See the block
  ## above for the property of the table this rests on.
  let name = $op
  doAssert name.startsWith("op"),
    "an `Operation` member whose name does not begin with `op` breaks the " &
    "mnemonic derivation: " & name
  let mnemonic = toLowerAscii(name[2 .. ^1])
  if mnemonic <= table313LastRowOn328: p313Start else: p313Cont

## THE PAGE AXIS AND THE `#xxx` AXIS ARE TWO DIFFERENT MANUAL FACTS, AND ONE
## SENTENCE USED TO COVER BOTH. The four shift rows - `asl.l`, `asr.l`,
## `lsl.l`, `lsr.l` - carry `1(0/0)` under `#xxx`; the eight
## immediate-and-register rows dash it. "A dash under every memory column" was
## true of both only by declining to say anything about `#xxx`, which is not a
## memory column - so the citation was accurate and INCOMPLETE, and an entry
## that later needed the `#xxx` fact would have found the constant silent.
## Both facts are now SPELLED by every entry, and neither is defaultable.
##
## Spelling it is not checking it, and assertion (8) is the check. It is
## two-sided, which one mutation would not have shown: a check that answered
## `imm313Timed` for everything would catch a timed row declared dashed and
## nothing else. Both directions are red - a genuinely timed row declared
## dashed, and a genuinely dashed row declared timed.
##
## What (8) does not do is read the manual, and neither does (7). Each holds a
## declaration against one independent recording of the same fact;
## `table313ImmOf` states that limit and the shape of the executor error that
## would defeat it. `decode_types.nim` and `logic.nim` record the
## same twelve-row split in prose, and they corroborate the four shift rows and
## five of the eight dashed ones. They are NOT what (8) reads, and they do not
## cover `addi`, `addx` or `subx` at all.
type
  Table313Imm = enum
    imm313Dashed = "a DASH under #xxx as well"
    imm313Timed = "1(0/0) under #xxx, which is not a memory column"

func whyDashMemory313(page: Table313Page; imm: Table313Imm): string =
  "Table 3-13 p." & $page & ": the row carries Rn 1(0/0), a DASH under (An), " &
  "(An)+, -(An), (d16,An), (d8,An,Xi*SF) and xxx.wl, and " & $imm

# ---------------------------------------------------------------------------
# The coverage table.
#
# EVERY FIELD OF EVERY ENTRY IS DECLARED AND NONE IS DERIVED FROM THE CODE
# UNDER TEST. `illegal` in particular is read from the manual and never from
# `eaLegalityFor`; `why` carries the row it is read from. See the header for
# why deriving it from `eaLegalityFor` would make the whole file tautological.
#
# `page313` IS DECLARED TOO, AND THE DERIVATION THAT CHECKS IT IS NOT AN
# EXCEPTION TO THAT RULE. `table313PageOf` reads the MANUAL's own row ordering,
# not `eaLegalityFor` and not any other production symbol, so the comparison
# holds a declaration against an independent second source rather than against
# the thing being asserted. A field derived from the code under test would
# assert nothing; a field cross-checked against the manual asserts the
# citation.

type
  Family = enum
    famMove, famAlu, famLogic, famControl

  Coverage = object
    op: Operation
    family: Family
    size: uint8
    legal: EA          ## a mode the manual gives this opcode
    illegal: EA        ## a mode the manual withholds from this opcode
    why: string        ## the manual row the `illegal` field is read from
    discriminating: bool  ## see the header: can assertion (4) attribute the
                          ## refusal to this operation's own guard?
    page313: Option[Table313Page]
      ## SET FOR THE TABLE 3-13 ENTRIES AND FOR NOTHING ELSE, so that the page
      ## the entry declared can be held against the page `table313PageOf`
      ## derives. `none` means the entry cites some other table and the
      ## comparison does not apply - it is not a way to opt out, because
      ## `cov313` is the only constructor that reaches a 3-13 citation and it
      ## always sets this.
    imm313: Option[Table313Imm]
      ## THE `#xxx` COLUMN THE ENTRY DECLARES, KEPT AS A FIELD AND NOT ONLY
      ## FOLDED INTO `why`. Assertion (8) holds it against the column
      ## `table313ImmOf` derives from the executor, and a string built for a
      ## human reader is not a value an assertion can compare. Set by `cov313`
      ## and by nothing else, on the same terms as `page313`.
    dirToEa: bool
    regOperand: bool
    destMode: uint8
    destReg: uint8

# The addressing modes the entries below name. `ea7Unused5` is the reserved
# mode-7 encoding: the manual prints REG. FIELD values 000, 001, 010, 011 and
# 100 under MODE FIELD 111 and no others, so 101 is not an addressing mode at
# all.
const
  mDn = EA(mode: eaDn, reg: 0)
  mAn = EA(mode: eaAn, reg: 0)
  mAnInd = EA(mode: eaAnInd, reg: 0)
  mAnPre = EA(mode: eaAnPre, reg: 0)
  mPcDisp = EA(mode: eaMode7, reg: uint8(ord(ea7PCDisp)))
  mReserved = EA(mode: eaMode7, reg: uint8(ord(ea7Unused5)))

# The citations, named once each so that the entries sharing a manual row
# cannot drift into as many wordings of it.
const
  whyReserved =
    "Table 3-5 p.3-21 prints no REG. FIELD 101 under MODE FIELD 111, so the " &
    "reserved mode-7 encoding is not an addressing mode"
  whyAnNotData =
    "Table 3-5 p.3-21, DATA column, An row: a dash. An address register is " &
    "not a DATA operand"
  whyPcNotAlterable =
    "Table 3-5 p.3-21, ALTERABLE column, (d16,PC) row: a dash. A written " &
    "destination cannot be PC-relative"
  whyDnNotControl =
    "Table 3-5 p.3-21, CONTROL column, Dn row: a dash. A control address is " &
    "not a register"
  whyPredecNotControl =
    "Table 3-5 p.3-21, CONTROL column, -(An) row: a dash; Table 3-14 p.3-29 " &
    "times both movem.l rows under (An) and (d16,An) alone"
  # TABLE 3-12 DOES NOT SPAN, WHICH IS THE WHOLE REASON THIS ONE IS A SHARED
  # CONSTANT WHILE `whyDashMemory313` IS A FUNCTION OF THE PAGE. Table 3-12
  # opens and ends on one page. There is therefore NO page for a further 3-12
  # entry to pick wrongly,
  # and the asymmetry between the two is a property of the MANUAL and not a
  # lapse in this file.
  #
  # RECORDED RATHER THAN LEFT TO BE RE-DERIVED, because an asymmetry with no
  # written reason is exactly how the 3-13 defect entered: the reader who does
  # not know why one of the pair is parameterized concludes that neither needs
  # to be. THE DERIVATION `table313PageOf` PERFORMS DOES NOT GENERALISE HERE,
  # AND ADDING IT WOULD BE A GREEN MIRAGE - on a table that occupies one page
  # the derived page is a constant, so the comparison could not fail for any
  # input and would assert nothing while looking exactly like assertion (7).
  whyDashMemory312 =
    "Table 3-12 p.3-27: the row carries Rn 1(0/0) and a DASH under (An), " &
    "(An)+, -(An), (d16,An), (d8,An,Xi*SF), xxx.wl and #xxx"

proc cov(op: Operation; family: Family; legal, illegal: EA; why: string;
         discriminating = true; size: uint8 = 4; dirToEa = false;
         regOperand = false; destMode: uint8 = 0;
         destReg: uint8 = 1): Coverage =
  Coverage(op: op, family: family, size: size, legal: legal, illegal: illegal,
           why: why, discriminating: discriminating, dirToEa: dirToEa,
           regOperand: regOperand, destMode: destMode, destReg: destReg)

proc cov313(op: Operation; family: Family; page: Table313Page;
            imm: Table313Imm): Coverage =
  ## THE TABLE 3-13 ENTRIES, WHOSE PAGE IS STATED EXACTLY ONCE. Routing the
  ## citation string and the checked field through one parameter is what stops
  ## the two from drifting apart, which a second `page313 = ...` argument
  ## alongside a `whyDashMemory313(...)` argument would have invited.
  ##
  ## Every one of these rows is a `{eaDn}` mask whose cited illegal mode is
  ## `(An)`, so `legal` and `illegal` are fixed here rather than repeated
  ## twelve times. An entry needing a different pair does not belong to this
  ## constructor and must state its own citation through `cov`.
  result = cov(op, family, mDn, mAnInd, whyDashMemory313(page, imm))
  result.page313 = some(page)
  result.imm313 = some(imm)

let coverage: seq[Coverage] = @[
  # --- eaAllModes / eaValid7: every printed mode is legal, so the only
  # illegal operand is a reserved mode-7 encoding, which `machine.nim` also
  # refuses on its own. These nine are NINE OF THE ELEVEN non-discriminating
  # entries; ADDQ and SUBQ below are the other two, by a different mechanism.
  cov(opMove, famMove, mDn, mReserved, whyReserved, discriminating = false),
  cov(opMovea, famMove, mDn, mReserved, whyReserved, discriminating = false,
      destMode = 1),
  cov(opAdd, famAlu, mDn, mReserved, whyReserved, discriminating = false),
  cov(opSub, famAlu, mDn, mReserved, whyReserved, discriminating = false),
  cov(opAdda, famAlu, mDn, mReserved, whyReserved, discriminating = false),
  cov(opSuba, famAlu, mDn, mReserved, whyReserved, discriminating = false),
  cov(opTst, famControl, mDn, mReserved, whyReserved, discriminating = false),
  cov(opCmp, famControl, mDn, mReserved, whyReserved, discriminating = false),
  cov(opCmpa, famControl, mDn, mReserved, whyReserved,
      discriminating = false),

  # --- eaAllModes / eaAlterable7: an ADDQ or SUBQ destination is
  # WRITTEN, so it cannot be PC-relative. An address register IS legal here,
  # which is why the class is alterable and not data alterable.
  #
  # These two are non-discriminating for the second reason the header gives.
  # `execAddSubQ` reaches its destination through `eaResolve`, which accepts
  # `{ea7AbsW, ea7AbsL}` and faults on every other mode-7 encoding - the exact
  # complement of `eaAlterable7`. Deleting this operation's guard leaves the
  # entry green.
  cov(opAddq, famAlu, mDn, mPcDisp, whyPcNotAlterable,
      discriminating = false),
  cov(opSubq, famAlu, mDn, mPcDisp, whyPcNotAlterable,
      discriminating = false),

  # --- eaDataAlterableModes / eaDataAlterable7 and the DATA class: an
  # address register is outside both.
  cov(opClr, famAlu, mDn, mAn, whyAnNotData),
  cov(opMulu, famAlu, mDn, mAn, whyAnNotData),
  cov(opMuls, famAlu, mDn, mAn, whyAnNotData),
  cov(opDivu, famAlu, mDn, mAn, whyAnNotData),
  cov(opDivs, famAlu, mDn, mAn, whyAnNotData),
  cov(opAnd, famLogic, mDn, mAn, whyAnNotData),
  cov(opOr, famLogic, mDn, mAn, whyAnNotData),
  # The four bit operations take `regOperand`, which selects the operation's
  # OWN mask over the narrower `eaBitStatic` of the static form.
  #
  # WHAT THE FLAG BUYS IS ASSERTION (4) AND NOT ASSERTION (1). Assertion (1)
  # calls `eaIsLegalFor(c.op, c.illegal)`, which never consults `regOperand`,
  # so a widening of their own entry IS seen with the flag or without it -
  # measured by dropping the flag and widening the arm together, and the plan
  # section carries the run.
  #
  # WHAT IS LOST WITHOUT THE FLAG IS ASSERTION (4)'s SUBJECT. `logic.nim`'s
  # `execBitOp` picks `eaBitStatic` for the static form, `eaBitStatic` also
  # rejects `An`, and so the executor keeps trapping and (4) stays GREEN over
  # a widened mask - passing while exercising a mask that is not the entry's
  # own. The flag points assertion (4) at the operation's own mask, and that
  # is the whole of what it does.
  cov(opBtst, famLogic, mDn, mAn, whyAnNotData, regOperand = true),
  cov(opBchg, famLogic, mDn, mAn, whyAnNotData, regOperand = true),
  cov(opBclr, famLogic, mDn, mAn, whyAnNotData, regOperand = true),
  cov(opBset, famLogic, mDn, mAn, whyAnNotData, regOperand = true),
  cov(opEor, famLogic, mDn, mAn, whyAnNotData),

  # --- {eaDn}: a data register and nothing else. The manual dashes every
  # memory column of each of these rows, so `(An)` is the cited illegal mode.
  cov(opNot, famLogic, mDn, mAnInd, whyDashMemory312),
  # The Table 3-13 rows. `imm313Timed` marks the four shift rows, which are the
  # only ones of the twelve whose `#xxx` column is timed rather than dashed.
  cov313(opAndi, famLogic, p313Start, imm313Dashed),
  cov313(opOri, famLogic, p313Cont, imm313Dashed),
  cov313(opEori, famLogic, p313Start, imm313Dashed),
  cov313(opAsl, famLogic, p313Start, imm313Timed),
  cov313(opAsr, famLogic, p313Start, imm313Timed),
  cov313(opLsl, famLogic, p313Start, imm313Timed),
  cov313(opLsr, famLogic, p313Start, imm313Timed),
  cov313(opAddi, famAlu, p313Start, imm313Dashed),
  cov313(opSubi, famAlu, p313Cont, imm313Dashed),
  cov(opNeg, famAlu, mDn, mAnInd, whyDashMemory312),
  cov(opNegx, famAlu, mDn, mAnInd, whyDashMemory312),
  cov(opExt, famAlu, mDn, mAnInd, whyDashMemory312),
  cov(opExtb, famAlu, mDn, mAnInd, whyDashMemory312),
  cov313(opAddx, famAlu, p313Start, imm313Dashed),
  cov313(opSubx, famAlu, p313Cont, imm313Dashed),
  cov(opScc, famControl, mDn, mAnInd, whyDashMemory312),
  cov313(opCmpi, famControl, p313Start, imm313Dashed),

  # SWAP is the opcode whose arrival exposed the hand-maintained list. Its
  # mask is `{eaDn}`: the operand syntax is `Dn` and the `swap Dx` row is timed
  # 1(0/0) under Rn with a dash in every other column.
  cov(opSwap, famMove, mDn, mAnInd, whyDashMemory312),

  # --- control addressing: a register is not a control address.
  cov(opJmp, famControl, mAnInd, mDn, whyDnNotControl),
  cov(opJsr, famControl, mAnInd, mDn, whyDnNotControl),
  cov(opLea, famMove, mAnInd, mDn, whyDnNotControl),
  cov(opPea, famMove, mAnInd, mDn, whyDnNotControl),
  # MOVEM's own narrowing is ordered separately and is NOT asserted here;
  # `-(An)` is outside the mask the file carries today and outside the one
  # the plan orders, so this entry is stable across that repair.
  cov(opMovem, famMove, mAnInd, mAnPre, whyPredecNotControl),
]

# ---------------------------------------------------------------------------
# The runner. One fresh context AND one fresh board per run, so that neither a
# fault nor a byte left by one run can be read as belonging to the next.

type RunResult = object
  cycles: uint32
  fault: bool
  halted: bool
  accesses: int
  dRegs: array[8, uint32]
  aRegs: array[7, uint32]
  sp: uint32
  pc: uint32
  sr: uint32

proc runFamily(c: Coverage; operand: EA; imm: uint8 = 1'u8): RunResult =
  ## THE IMMEDIATE IS A PARAMETER SO THAT ASSERTION (8) CAN VARY IT, and its
  ## default is the `1` every other call used before that assertion existed, so
  ## assertions (3) and (4) drive exactly the run they always drove.
  # THE BOARD IS RESET TOO, AND NOT ONLY THE CONTEXT. `board` is a single
  # global that every legal run writes through. Nothing today writes near
  # `execBase` - `ramBase` and `stackBase` are both far from it - so the
  # isolation would hold BY ARITHMETIC even without this, which is a property
  # of the current constants rather than of the runner. An entry that moved
  # `ramBase` or widened a run's write would carry a previous entry's bytes
  # into the next run with nothing to say so.
  zeroMem(addr board, sizeof(TestBoard))
  let ctx = mcf5307_create(addr board, bRead, bWrite, bIack)
  mcf5307_reset(ctx, stackBase, execBase)
  for i in 0 .. 7:
    ctx.dRegs[i] = dRegSeedMustBeNonZero + uint32(i)
  for i in 0 .. 6:
    ctx.aRegs[i] = aRegSeed(i)
  let d = Decoded(op: c.op, ea: operand, size: c.size, destReg: c.destReg,
                  destMode: c.destMode, memDir: false, dirToEa: c.dirToEa,
                  imm: imm, regOperand: c.regOperand)
  busAccesses = 0
  let cycles =
    case c.family
    of famMove: moveFamily(ctx, 0'u16, d)
    of famAlu: aluFamily(ctx, 0'u16, d)
    of famLogic: logicFamily(ctx, 0'u16, d)
    of famControl: controlFamily(ctx, 0'u16, d)
  result = RunResult(cycles: cycles, fault: ctx.fault, halted: ctx.halted,
                     accesses: busAccesses, dRegs: ctx.dRegs,
                     aRegs: ctx.aRegs, sp: ctx.sp, pc: ctx.pc, sr: ctx.sr)
  mcf5307_destroy(ctx)

proc pristine(r: RunResult): bool =
  ## The register file exactly as `runFamily` seeded it. A refusal writes
  ## nothing, so anything else means part of the instruction ran.
  for i in 0 .. 7:
    if r.dRegs[i] != dRegSeedMustBeNonZero + uint32(i): return false
  for i in 0 .. 6:
    if r.aRegs[i] != aRegSeed(i): return false
  r.sp == stackBase and r.pc == execBase and r.sr == srAfterResetMustMatchCpuNim

proc table313ImmOf(c: Coverage): Option[Table313Imm] =
  ## THE `#xxx` COLUMN, DERIVED FROM THE EXECUTOR AND NOT FROM THIS FILE. The
  ## entry is run twice on its LEGAL operand with two different immediates and
  ## nothing else changed. If the two runs differ, the executor consumed the
  ## immediate AS THIS INSTRUCTION'S `<ea>` OPERAND; if they do not, the
  ## immediate is not an operand this instruction has.
  ##
  ## THAT IS THE OPERATIONAL CONTENT OF THE `#xxx` COLUMN. A time under `#xxx`
  ## is the manual timing the case where the effective address IS an immediate,
  ## which the four shift rows have - `<ea>,Dx`, where the `<ea>` is the shift
  ## COUNT and `logic.nim`'s `execShift` reads `uint32(d.imm)` for it. A DASH
  ## is the manual withholding that case, which the other eight rows have:
  ## their `<EA>` syntax is `#imm,Dx` or `Dy,Dx`, the `<ea>` is a register,
  ## and the long immediate those rows do carry is a separate EXTENSION WORD
  ## fetched from the instruction stream - `decode.nim`'s `opAddi` and `opOri`
  ## arms, each commented "immediate follows this word" - so `d.imm` reaches
  ## nothing and the two runs are identical.
  ##
  ## THIS IS A SECOND SOURCE AND NOT A ROSTER ASSERTED AGAINST ITSELF. The
  ## executor is production code written from the manual, it is independent of
  ## every declaration in this file, it names no opcodes, and it would answer a
  ## thirteenth entry it has never seen.
  ##
  ## WHAT IT HOLDS THE DECLARATION AGAINST IS THE EXECUTOR AND NOT THE MANUAL'S
  ## INK, AND THAT LIMIT IS THE PRICE OF HAVING A CHECK AT ALL. An executor
  ## that wrongly consumed `d.imm` for a dashed row would make this assertion
  ## ratify the wrong declaration - the same shape as assertion (7)'s limit,
  ## where a member renamed onto the same side of the break derives the page it
  ## already declares. Neither assertion reads the manual; each holds one
  ## declaration against one independent recording of it. The manual citations
  ## themselves are checked by `m68k-elf-as` measurements recorded in
  ## `decode_types.nim` and `logic.nim`, not here.
  let low = runFamily(c, c.legal, imm = 1'u8)
  if low.fault or low.cycles == 0'u32: return none(Table313Imm)
  let high = runFamily(c, c.legal, imm = 3'u8)
  if high.fault or high.cycles == 0'u32: return none(Table313Imm)
  some(if low == high: imm313Dashed else: imm313Timed)

proc runCoverage(c: Coverage) =
  let name = $c.op
  inc opsCovered
  if c.discriminating: inc opsDiscriminating

  # (1) The predicate rejects the independently-cited illegal mode. This is
  # the assertion a WIDENED MASK fails, and it fails for every operation.
  check(not eaIsLegalFor(c.op, c.illegal),
    name & ": the mask rejects " & $c.illegal.mode & "/" & $c.illegal.reg &
    " (" & c.why & ")")

  # (2) The positive control: the mask is not simply empty.
  check(eaIsLegalFor(c.op, c.legal),
    name & ": the mask accepts a legal " & $c.legal.mode & " operand")

  # (3) The executor runs the legal operand. The control for (4).
  let ok = runFamily(c, c.legal)
  checkDetail(not ok.fault and ok.cycles > 0'u32,
    name & ": the executor runs a legal " & $c.legal.mode & " operand",
    "fault=" & $ok.fault & " cycles=" & $ok.cycles)

  # (4) The executor REFUSES the illegal operand, and refuses it whole.
  let bad = runFamily(c, c.illegal)
  checkDetail(bad.fault and bad.halted and bad.cycles == 0'u32 and
              bad.accesses == 0 and pristine(bad),
    name & ": the executor traps an illegal " & $c.illegal.mode &
    " operand" & (if c.discriminating: "" else: " [not attributable]"),
    "fault=" & $bad.fault & " halted=" & $bad.halted &
    " cycles=" & $bad.cycles & " busAccesses=" & $bad.accesses &
    " registersPristine=" & $pristine(bad))

  # (7) The declared Table 3-13 page, held against the derived one. This runs
  # for the Table 3-13 entries alone; the block defining `Table313Page` carries
  # the argument.
  if c.page313.isSome:
    let derived = table313PageOf(c.op)
    checkDetail(c.page313.get == derived,
      name & ": its Table 3-13 row is on the page the entry cites",
      "the entry declares p." & $c.page313.get &
      " and the mnemonic derives p." & $derived)

  # (8) The declared `#xxx` column, held against the one the executor shows.
  # `table313ImmOf` carries the argument and the limit.
  if c.imm313.isSome:
    let derivedImm = table313ImmOf(c)
    checkDetail(derivedImm.isSome and c.imm313.get == derivedImm.get,
      name & ": its Table 3-13 `#xxx` column is the one the executor shows",
      "the entry declares \"" & $c.imm313.get & "\" and varying the immediate " &
      (if derivedImm.isSome: "derives \"" & $derivedImm.get & "\""
       else: "derives nothing: the legal operand never executed") &
      " - EITHER the citation is wrong OR the executor consumes `d.imm` for " &
      "a row the manual dashes; read the family module before editing it")

# ---------------------------------------------------------------------------
# (1) to (4) - and (7) where it applies - enumerated over `Operation`. The loop
# below, and not the table above, is what makes an opcode that gains a mask
# loudly missing.

block:
  var reached = newSeq[bool](coverage.len)
  for op in Operation:
    let mask = eaLegalityFor(op)
    var entry = -1
    for i, c in coverage:
      if c.op == op:
        entry = i
        break
    if card(mask.modes) == 0:
      check(entry < 0,
        $op & ": carries an EMPTY legality mask and no stale coverage entry")
    else:
      # The domain is counted here and not inside `runCoverage`, because the
      # run that most needs the figure is the run where an entry is missing.
      # See the declaration of `opsInDomain` for why the two counters are
      # separate.
      inc opsInDomain
      if entry < 0:
        checkOffGreenPath(false,
          $op & ": carries a NON-EMPTY legality mask and NO coverage entry " &
          "reaches it - add one to `coverage`, with an illegal mode read " &
          "from the manual and not from `eaLegalityFor`")
      else:
        reached[entry] = true
        runCoverage(coverage[entry])

  # EVERY `coverage` ROW MUST HAVE BEEN REACHED, AND NOTHING SAID SO. The
  # lookup above stops at the FIRST row whose `op` matches, so a SECOND row for
  # an already-covered operation is dropped without a word - it runs no
  # assertion, fails nothing, and reads at the call site exactly like coverage.
  # `reached` is what lets the red NAME such a row rather than only count it.
  #
  # `opsCovered` counts rows REACHED and `coverage.len` counts rows WRITTEN, so
  # this compares the table against the enumeration that consumes it. A stale
  # row for an emptied mask also lands here, which is a true statement about
  # that row and duplicates the more specific red the loop already prints.
  var deadRows: seq[string] = @[]
  for i, c in coverage:
    if not reached[i]: deadRows.add($i & ":" & $c.op)
  checkDetail(coverage.len == opsCovered,
    "every `coverage` row is reached by the enumeration - a row that is " &
    "neither the first for its operation nor for an operation with a " &
    "non-empty mask runs NO assertion",
    $coverage.len & " rows written and " & $opsCovered &
    " reached; these ran nothing: " & $deadRows)

  # AND EVERY TABLE 3-13 CITATION MUST CARRY A PAGE FOR (7) TO CHECK. That
  # assertion runs only where `page313` is set, so a `cov313` that stopped
  # setting it would DELETE twelve assertions and print a smaller total with no
  # red anywhere - the case count is printed and nothing asserts it, which is
  # the same silence this file was built to remove.
  #
  # The citation string and the `page313` field are written by one call but are
  # two different values, so each is a witness for the other: a row citing
  # Table 3-13 with no page, or a page on a row citing something else, is red.
  # Both counts falling to ZERO is the remaining way out - twelve entries
  # rewritten to hand-built strings - so that is refused as well.
  #
  # `carriesImm` JOINS THE SAME EQUALITY, because assertion (8) runs exactly
  # where `imm313` is set and a `cov313` that stopped setting it would delete
  # twelve assertions the same silent way.
  var cited313 = 0
  var carriesPage = 0
  var carriesImm = 0
  for c in coverage:
    if c.why.startsWith("Table 3-13 p."): inc cited313
    if c.page313.isSome: inc carriesPage
    if c.imm313.isSome: inc carriesImm
  check(cited313 == carriesPage and cited313 == carriesImm and cited313 > 0,
    "every Table 3-13 citation carries a page for assertion (7) and a `#xxx` " &
    "column for assertion (8) to hold it against: " & $cited313 &
    " rows cite Table 3-13, " & $carriesPage & " carry a page and " &
    $carriesImm & " carry a `#xxx` column, and no figure may be zero")

  # (10) Every `Operation` member name begins with `op`. `table313PageOf`
  # asserts this for the members it is called with and crashes on a
  # member that breaks it - a crash rather than a case. Checking it for the
  # whole enumeration turns "a misnamed member would crash the derivation" from
  # a sentence about a hypothetical into a property of the enumeration as it
  # stands, and it costs one case rather than twelve.
  var misnamed: seq[string] = @[]
  for op in Operation:
    if not ($op).startsWith("op"): misnamed.add($op)
  checkDetail(misnamed.len == 0,
    "every `Operation` member name begins with `op`, which is what the " &
    "mnemonic derivation behind assertion (7) rests on",
    "these are not: " & $misnamed)

  # (11) Every row's `illegal` field carries a manual citation. The header
  # rests its anti-tautology argument on that. `why` is a required parameter,
  # so a row cannot omit
  # it, but a row can pass a hand-written string that cites nothing; every
  # citation this file uses names a manual table, so that is what is required.
  var uncited: seq[string] = @[]
  for c in coverage:
    if not c.why.startsWith("Table 3-"): uncited.add($c.op)
  checkDetail(uncited.len == 0,
    "every `coverage` row cites a manual table for its `illegal` mode",
    "these do not: " & $uncited)

# ---------------------------------------------------------------------------
# (12) The multiply and divide carry two masks, one per size, and the four
# `coverage` rows above cannot see the split. Those rows cite the `An` row of
# Table 3-5, which is dashed at both sizes, so widening or narrowing either
# mask anywhere else leaves all four green. This block is the guard for the
# split itself.
#
# Collapsing the arm to one data-alterable mask reds a quarter of this block
# and not all of it. What reds is the same six cells in each of the four
# operations: the `.L` rejects half of `(d8,Ay,Xi)`, `(xxx).W` and `(xxx).L`,
# and the `.W` accepts half of `(d16,PC)`, `(d8,PC,Xi)` and `#<data>`.
#
# The rest cannot see the collapse, for one reason in two shapes. The ten
# shared-mode assertions and the two `Ay` assertions of each operation name
# cells where the collapsed mask agrees with both real masks, and a mode both
# masks share is not evidence about the split. Within each of the six split
# pairs the collapsed mask matches exactly one column - the three modes it
# holds satisfy the word half, the three it lacks satisfy the long half - so
# one assertion of every pair reds and its partner passes. The four
# size-less-overload assertions at the foot of the block stay green as well,
# because both sides of that equality read whatever single mask the arm
# returns.
#
# THE MANUAL AND THE ASSEMBLER AGREE ON EVERY CELL. Each operation carries an
# "Instruction Fields (Word)" addressing-mode table and an "Instruction Fields
# (Longword)" one:
#
#   WORD     every mode but `Ay` - `(xxx).W`, `(xxx).L`, `#<data>`,
#            `(d16,PC)` and `(d8,PC,Xi)` all carry a mode and register value.
#            That is the manual's DATA class exactly.
#   LONGWORD `Dy`, `(Ay)`, `(Ay)+`, `-(Ay)` and `(d16,Ay)` ONLY. `Ay`,
#            `(d8,Ay,Xi)` and EVERY mode-7 sub-variant are dashed.
#
# `m68k-elf-as -mcpu=5307` (GNU Binutils 2.47.20260726) was offered all twelve
# modes of all eight forms and answered the same 96 cells.
#
# `(d8,Ay,Xi)` IS THE CELL THE BRIEF FOR THIS WORK DID NOT NAME. The long form
# was described as data-alterable-minus-absolute; the manual and the assembler
# both drop the INDEXED mode as well, so the long mask is narrower again than
# that. It is asserted here because a mask corrected only as far as the
# description would still be wrong and nothing else would say so.

block:
  const
    wordSize = 2'u8
    longSize = 4'u8
    mulDivOps = [opMulu, opMuls, opDivu, opDivs]
    # The five modes both sizes share, as the LONGWORD table prints them.
    sharedLegal = [
      ("Dy", EA(mode: eaDn, reg: 0)),
      ("(Ay)", EA(mode: eaAnInd, reg: 1)),
      ("(Ay)+", EA(mode: eaAnPost, reg: 1)),
      ("-(Ay)", EA(mode: eaAnPre, reg: 1)),
      ("(d16,Ay)", EA(mode: eaAnDisp, reg: 1))]
    # The modes the WORD table carries and the LONGWORD table dashes.
    wordOnly = [
      ("(d8,Ay,Xi)", EA(mode: eaAnIndex, reg: 1)),
      ("(xxx).W", EA(mode: eaMode7, reg: uint8(ord(ea7AbsW)))),
      ("(xxx).L", EA(mode: eaMode7, reg: uint8(ord(ea7AbsL)))),
      ("(d16,PC)", EA(mode: eaMode7, reg: uint8(ord(ea7PCDisp)))),
      ("(d8,PC,Xi)", EA(mode: eaMode7, reg: uint8(ord(ea7PCIndex)))),
      ("#<data>", EA(mode: eaMode7, reg: uint8(ord(ea7Imm))))]

  for op in mulDivOps:
    let name = $op

    # The five shared modes are legal at BOTH sizes. This is the positive
    # control: a mask emptied at either size fails here rather than passing
    # the negatives below by vacuous refusal.
    for (label, ea) in sharedLegal:
      check(eaIsLegalFor(op, ea, wordSize),
        name & ".W: the mask accepts " & label &
        " (folio word table: a mode and register value)")
      check(eaIsLegalFor(op, ea, longSize),
        name & ".L: the mask accepts " & label &
        " (folio longword table: a mode and register value)")

    # THE SPLIT. Each of these six is LEGAL at the word size and ILLEGAL at
    # the long one, and the single shared mask could satisfy at most one
    # column of the pair.
    for (label, ea) in wordOnly:
      check(eaIsLegalFor(op, ea, wordSize),
        name & ".W: the mask accepts " & label &
        " (folio word table carries it; the longword table dashes it)")
      check(not eaIsLegalFor(op, ea, longSize),
        name & ".L: the mask REJECTS " & label &
        " (folio longword table: a dash)")

    # `Ay` is dashed on BOTH tables, which is what the four `coverage` rows
    # above cite. Repeated here at both sizes so that the split cannot be
    # implemented by widening the word mask to EVERY mode.
    let ay = EA(mode: eaAn, reg: 1)
    check(not eaIsLegalFor(op, ay, wordSize),
      name & ".W: the mask REJECTS Ay (folio word table: a dash)")
    check(not eaIsLegalFor(op, ay, longSize),
      name & ".L: the mask REJECTS Ay (folio longword table: a dash)")

  # THE SIZE-LESS ENTRY POINT ANSWERS THE LONG MASK, and that is asserted
  # rather than left to the reader of `decode_types.nim`. Every one of the
  # twenty-odd call sites that does not pass a size reaches this overload, so
  # which of the two masks it picks is a property the tests must pin: the
  # narrow one traps a word operand it should have allowed, which is loud,
  # and the wide one executes a long operand the silicon rejects, which is
  # silent.
  for op in mulDivOps:
    check(eaLegalityFor(op) == eaLegalityFor(op, 4'u8),
      $op & ": the size-less `eaLegalityFor` answers the LONGWORD mask")

# ---------------------------------------------------------------------------
# (13) MOVEM takes `(An)` and `(d16,An)` and nothing else, and the `coverage`
# ROW ABOVE CANNOT SEE THAT. That row cites `-(An)`, which is dashed on the
# folios and outside the mask both before and after this narrowing, so it is
# GREEN over a mask four cells too wide. Every entry names exactly ONE illegal
# mode - the header's assertion (1) states that limit - so the cells this
# block names could not have been added to it, and a second row for `opMovem`
# would be dropped by the first-match lookup and red the reached-row count
# instead of asserting anything.
#
# The four cells this block exists for are `(d8,An,Xi)`, `(xxx).L`,
# `(d16,PC)` and `(d8,PC,Xi)`. A control-class mask on `eaLegalityFor`'s
# `opMovem` arm admits all four, while the arm's own comment cites Table 3-14
# as timing MOVEM under `(An)` and `(d16,An)` alone.
#
# IT WAS NOT LATENT. Measured on the wide mask, before the
# narrowing: `movem.l %d0-%d1,0x400.l` - hand-built as `48f9 0003 0000 0400` -
# reached the executor and COMPLETED ITS STORE, leaving 0xAABBCCDD at 0x400
# and 0x11223344 at 0x404 with `fault` false. `tests/t_move.nim` carries that
# case at the execution level; this block carries the mask level.
#
# The source is the CFPRM and both directions agree, read as rendered images
# (`pdftoppm -r 200`) and not from any OCR text:
#
# EACH PRINTS A MODE AND REGISTER VALUE FOR EXACTLY TWO ROWS - `(Ax)`
# 010 and `(d16,Ax)` 101 - AND A DASH FOR THE OTHER TEN: `Dx`, `Ax`, `(Ax)+`,
# `-(Ax)`, `(d8,Ax,Xi)`, `(xxx).W`, `(xxx).L`, `#<data>`, `(d16,PC)` and
# `(d8,PC,Xi)`. The two tables are the same shape cell for cell, so the mask
# does not depend on the direction and one mask can serve both.
#
# TWO INDEPENDENT TOOLCHAIN ORACLES AGREE:
#
#   - `m68k-elf-as -mcpu=5307` assembles `movem.l %d0-%d1,(%a0)` (`48d0 0003`)
#     and `movem.l %d0-%d1,(4,%a0)` (`48e8 0003 0004`) and the two
#     memory-to-register forms (`4cd0`, `4ce8`), and REJECTS all ten other
#     rows in both directions with "operands mismatch".
#   - `m68k-elf-objdump -m m68k:5307` decodes `48d0`, `48e8`, `4cd0` and
#     `4ce8` as `moveml` and decodes `48f0`, `48f8`, `48f9`, `48fa`, `48fb`
#     and their `4cxx` partners as `.short`.
#
# The 68020 cross-check separates eight of those ten. Each encoding was
# disassembled in a file of its own so no mis-decode could cascade:
# `-m m68k:68020` renders `48f0`, `48f8`, `48f9`, `4cf0`, `4cf8`, `4cf9`,
# `4cfa` and `4cfb` as a real `moveml`, and for those eight the ColdFire
# `.short` is a statement about the part rather than about the
# disassembler. `48fa` and `48fb` come back `.short` on the 68020 too. Both
# store to a PC-relative destination, which is illegal on every 68k, so those
# two encodings are not a MOVEM on any target and the differential oracle is
# silent about them. The asymmetry is the direction: the memory-to-register
# partners `4cfa` and `4cfb` read from PC-relative, which the 68020 permits,
# and they do discriminate. The two folios and the pinned assembler each
# answer all ten on their own, so no cell in this block rests on the 68020
# alone.
#
# `(xxx).W` IS ASSERTED HERE AND WAS ALREADY RIGHT. It is in the block so that
# a repair of the four cells cannot be written as a widening that admits it.

block:
  const
    movemLegal = [
      ("(An)", EA(mode: eaAnInd, reg: 1)),
      ("(d16,An)", EA(mode: eaAnDisp, reg: 1))]
    # THE FOUR CELLS THE WIDE MASK ADMITTED, then the six that were already
    # outside it. Both groups are asserted so that the narrowing cannot be
    # implemented by moving the error somewhere else.
    movemIllegalWrongly = [
      ("(d8,An,Xi)", EA(mode: eaAnIndex, reg: 1)),
      ("(xxx).L", EA(mode: eaMode7, reg: uint8(ord(ea7AbsL)))),
      ("(d16,PC)", EA(mode: eaMode7, reg: uint8(ord(ea7PCDisp)))),
      ("(d8,PC,Xi)", EA(mode: eaMode7, reg: uint8(ord(ea7PCIndex))))]
    movemIllegalAlready = [
      ("Dn", EA(mode: eaDn, reg: 1)),
      ("An", EA(mode: eaAn, reg: 1)),
      ("(An)+", EA(mode: eaAnPost, reg: 1)),
      ("-(An)", EA(mode: eaAnPre, reg: 1)),
      ("(xxx).W", EA(mode: eaMode7, reg: uint8(ord(ea7AbsW)))),
      ("#<data>", EA(mode: eaMode7, reg: uint8(ord(ea7Imm))))]

  # THE POSITIVE CONTROL FIRST. Without it a mask emptied outright would pass
  # every negative below by refusing everything, which is the failure shape
  # this file's header calls a vacuous refusal.
  for (label, ea) in movemLegal:
    check(eaIsLegalFor(opMovem, ea),
      "movem: the mask accepts " & label &
      " (folios 4-50 and 4-51 both print a mode and register value)")

  for (label, ea) in movemIllegalWrongly:
    check(not eaIsLegalFor(opMovem, ea),
      "movem: the mask REJECTS " & label &
      " (folios 4-50 and 4-51: a dash in both directions)")

  for (label, ea) in movemIllegalAlready:
    check(not eaIsLegalFor(opMovem, ea),
      "movem: the mask REJECTS " & label &
      " (folios 4-50 and 4-51: a dash in both directions)")

# ---------------------------------------------------------------------------
# (14) The `eaLeaPeaTarget` guard. An unguarded mask is a latent defect
# whatever its current value: without this block, widening `eaLeaPeaTarget` to
# `modes: eaControlModes + {eaAnPost}` and `ea7: eaControl7 + {ea7Imm}` -
# admitting `(An)+` and `#<data>` - leaves the entire suite green, because the
# `coverage` rows for `opLea` and `opPea` cite `Dn`, which stays outside the
# widened mask, so assertion (1) cannot see it.
#
# The source. `m68k-elf-as -mcpu=5307` rejects `lea (%a0)+,%a1`, `lea #4,%a1`,
# `pea (%a0)+` and `pea #4`, all four with "operands mismatch", and accepts
# every mode named in the positive control below. The manual dashes the
# `lea | <ea>,Ax` row and the `pea | <ea>` row under `(An)+` and `#xxx`.
#
# The positive control includes `(xxx).W`, which is the cell `eaLeaPeaTarget`
# was created to admit and the one MOVEM must not have. A repair of block (13)
# written by widening a shared constant reds there and here at once.

block:
  const
    leaPeaOps = [opLea, opPea]
    leaPeaLegal = [
      ("(An)", EA(mode: eaAnInd, reg: 1)),
      ("(d16,An)", EA(mode: eaAnDisp, reg: 1)),
      ("(d8,An,Xi)", EA(mode: eaAnIndex, reg: 1)),
      ("(xxx).W", EA(mode: eaMode7, reg: uint8(ord(ea7AbsW)))),
      ("(xxx).L", EA(mode: eaMode7, reg: uint8(ord(ea7AbsL)))),
      ("(d16,PC)", EA(mode: eaMode7, reg: uint8(ord(ea7PCDisp)))),
      ("(d8,PC,Xi)", EA(mode: eaMode7, reg: uint8(ord(ea7PCIndex))))]
    # THE TWO CELLS THE WIDENING ADDED. These are the guard.
    leaPeaIllegal = [
      ("(An)+", EA(mode: eaAnPost, reg: 1)),
      ("#<data>", EA(mode: eaMode7, reg: uint8(ord(ea7Imm))))]

  for op in leaPeaOps:
    let name = $op
    for (label, ea) in leaPeaLegal:
      check(eaIsLegalFor(op, ea),
        name & ": the mask accepts " & label &
        " (Table 3-13 p.3-28 and Table 3-14 p.3-29 time the column)")
    for (label, ea) in leaPeaIllegal:
      check(not eaIsLegalFor(op, ea),
        name & ": the mask REJECTS " & label &
        " (Table 3-13 p.3-28 and Table 3-14 p.3-29 dash the column; " &
        "`m68k-elf-as -mcpu=5307` answers \"operands mismatch\")")

# ---------------------------------------------------------------------------
# (15) The `eaJumpTarget` cell table lives in `tests/t_control.nim`, not here.
# A block mirroring block (14) for `opJmp` and `opJsr` stood here and was
# deleted as unable to detect anything: `t_control.nim`'s twelve-row
# `eaIsLegalFor(opJmp/opJsr, ...)` table enumerates the same cells with the
# same verdicts through the same predicate, so the two compute the same
# booleans and no mutation can separate them.
#
# Block (14) is not the same case. LEA and PEA have no cell table anywhere
# else, and block (19) does not replace it either: block (19) compares
# `eaLegalityFor`'s answer against a literal, while this block asks
# `eaIsLegalFor` about a cell, which runs `isEaLegal` on top of that answer.
# With `isEaLegal` made to answer true unconditionally, block (14) reds and
# block (19) does not, so neither is reachable only through the other.
#
# The CFPRM provenance the deleted block carried is on the `eaControl7`
# declaration in `src/mcf5307/ea.nim`, beside the value it cites.

# ---------------------------------------------------------------------------
# (16) The ADDQ and SUBQ mask, enumerated cell by cell. This block closes a
# measured blind spot and the direction is narrowing, which is the direction
# this file has repeatedly been weakest in: without this block and block (19),
# `eaAlterable7 - {ea7AbsW}` leaves the entire suite green, and ADDQ and SUBQ
# would trap on `addq.l #1,0x1234.w`, a form the pinned assembler emits. The
# widening direction was already guarded.
#
# That asymmetry is the point. The `coverage` rows for these two declare
# `discriminating: false` because their cited illegal mode `(d16,PC)` is
# refused by `eaResolve` as well - an argument about assertion (4) - and
# assertion (1) does catch a widening onto that one cell. Neither reaches a
# narrowing, because every `coverage` row names an illegal mode and a narrowing
# removes a legal one.
#
# The mode set is not what this block closes. ADDQ and SUBQ have no mode set of
# their own: their arm names `eaAllModes`, which several operations share, and
# `t_alu` reds when it is narrowed. It is the mode-7 half that had no coverage
# in the narrowing direction.
#
# The mode set is every mode and the restriction lives entirely in the mode-7
# half: a set named for the manual's ALTERABLE class that excludes no mode is
# not restricting anything, and only `eaAlterable7` is.
#
# The assembler transcript behind these twelve cells, and the CFPRM
# `Alterable` column that disagrees with it on two of them, are recorded once -
# on the `eaAlterable7` declaration in `src/mcf5307/ea.nim`. That is the site
# whose value the evidence establishes; this block only pins it. The
# disagreement is not settled there and is not settled here: a reader who
# narrows the mask to follow the column reds the two `(xxx).W` and `(xxx).L`
# rows below, and that is the intended conversation.

block:
  const
    addqOps = [opAddq, opSubq]
    addqLegal = [
      ("Dn", EA(mode: eaDn, reg: 1)),
      ("An", EA(mode: eaAn, reg: 1)),
      ("(An)", EA(mode: eaAnInd, reg: 1)),
      ("(An)+", EA(mode: eaAnPost, reg: 1)),
      ("-(An)", EA(mode: eaAnPre, reg: 1)),
      ("(d16,An)", EA(mode: eaAnDisp, reg: 1)),
      ("(d8,An,Xi)", EA(mode: eaAnIndex, reg: 1)),
      ("(xxx).W", EA(mode: eaMode7, reg: uint8(ord(ea7AbsW)))),
      ("(xxx).L", EA(mode: eaMode7, reg: uint8(ord(ea7AbsL))))]
    addqIllegal = [
      ("(d16,PC)", EA(mode: eaMode7, reg: uint8(ord(ea7PCDisp)))),
      ("(d8,PC,Xi)", EA(mode: eaMode7, reg: uint8(ord(ea7PCIndex)))),
      ("#<data>", EA(mode: eaMode7, reg: uint8(ord(ea7Imm))))]

  for op in addqOps:
    let name = $op
    for (label, ea) in addqLegal:
      check(eaIsLegalFor(op, ea),
        name & ": the mask accepts " & label &
        " (`m68k-elf-as -mcpu=5307` emits it, measured 2026-08-11)")
    for (label, ea) in addqIllegal:
      check(not eaIsLegalFor(op, ea),
        name & ": the mask REJECTS " & label &
        " (a written destination is not PC-relative and not an immediate;" &
        " `m68k-elf-as -mcpu=5307` answers \"operands mismatch\")")

# ---------------------------------------------------------------------------
# (17) The mode-7 sets held against their literal membership stood here and
# was deleted. Three cases pinned `eaValid7`, `eaControl7` and `eaAlterable7`
# against the members spelled out in them. Each of the three sets is read by an
# arm of `eaLegalityFor` whose mask block (19) below holds against a literal,
# so no value change to any of them can red block (17) alone.
#
# The block's own admission rule is what condemns it: "a case whose condition
# is entailed by the equality cases cannot be the sole detector of anything,
# because two conditions that cannot disagree cannot red apart". With block
# (19) in place each of the three equalities is itself entailed one level up -
# `eaLegalityFor(opMove, 4)` held against a literal whose mode-7 half spells
# `eaValid7`'s five members entails that `eaValid7` has those five members.
#
# The readability argument is real and is not enough: a failing log without
# those cases names the operations and never names `eaValid7`, which is a worse
# read. Block (15) had the same localisation argument available and was deleted
# anyway, so an exception granted here would license re-adding it.
#
# What the deletion does not lose: the manual citations the three cases carried
# - CFPRM Rev. 3 Table 2-3 folio 2-10 for all three - are on the declarations
# in `src/mcf5307/ea.nim`, beside the values that evidence establishes.

# ---------------------------------------------------------------------------
# (19) Every mask in the domain, held against its literal value. One case per
# operation-and-size mask, each holding the whole `EaLegality` against members
# spelled out below.
#
# The admission rule, which block (17) stated and this block inherited with the
# idiom: one literal-equality case per mask, and nothing derived from them. A
# case whose condition is entailed by the equality cases cannot be the sole
# detector of anything, because two conditions that cannot disagree cannot red
# apart.
#
# The direction that forced it is narrowing, which the `coverage` table
# structurally cannot see: every row there names one illegal mode, and a
# narrowing removes a legal one. Block (16) closed that for ADDQ and SUBQ by
# hand; a sweep found it open nearly everywhere else. Deleting any one legal
# cell from any one operation's mask reds exactly one case in this block, and
# for a large minority of cells it reds nothing else anywhere.
#
# Equality is strictly stronger than a cell table, and that is why the shape is
# this one. A cell table pins the cells someone enumerated; an equality pins
# the mask, so it catches widening as well as narrowing and catches both for
# cells nobody listed. Two widenings that are otherwise silent in the whole
# repository - `eaLeaPeaTarget` accepting an address register, and the
# `opScc`/`opCmpi` arm accepting postincrement - red here and nowhere else.
#
# It obsoletes nothing, which is the objection block (15) was deleted for.
# Blocks (12), (13), (14) and (16) reach the table through `eaIsLegalFor`;
# these cases compare the table itself, so the two layers red apart. With
# `isEaLegal` made to answer true unconditionally those four blocks red and
# every case in this one stays green.
#
# A correct narrowing now has to be made in two places, and the cost is
# proportional: one operation's arm narrowed by one cell reds one case here,
# while narrowing a shared declaration in `ea.nim` reds one row per mask that
# reads the set. A form that charged less would be pinning fewer masks.
#
# What this block is not. It pins the value of each mask and carries no
# provenance of its own. What makes a cell legal is recorded on the
# declarations the mask is built from - `eaAllModes` and `eaValid7`,
# `eaDataAlterableModes` and `eaDataAlterable7`, `eaDataAddressing`,
# `eaBitDynamic`, `eaJumpTarget`, `eaLeaPeaTarget`, `eaMulDivLongModes` - each
# carrying its manual folios and its `m68k-elf-as` transcript beside the value
# that evidence establishes. It also cannot fail because the decoder handed the
# wrong operation or size to a word, which reaches the right mask under the
# wrong key, and it cannot fail if a literal below was mis-transcribed at
# authoring time from an already-wrong mask - the sharpest limit of any guard
# whose expected value is copied from its own subject.
#
# The execution-level limit, and it is the wider half of the gap. A mask case
# proves the mask still admits the cell. It does not prove the emulator
# executes that instruction correctly, and for the cells this block was written
# for nothing anywhere does - which is why deleting them reds nothing. The ADD
# corpus cases are `add.l %d0,%d1`, `0x2000.w`, `0x00030004`, `(0x1e,%pc)` and
# `(4,%pc,%d2)`, exactly the complement of the `(An)`-family cells that were
# silent; SUB carries `sub.l %d0,%d1` alone; and the only OR cases beyond
# `or.l %d0,%d1` are the `Dn -> <ea>` direction, which `logic.nim` masks with
# `eaMemoryAlterable` directly and which never reaches `eaLegalityFor(opOr)`.
#
# The decay this shape dissolves, and the residue it does not. A cell table is
# membership defined by a measurement: delete the `add_l_*` corpus cases later
# and the cells they caught go silent again while the table does not grow. An
# equality does not depend on what else covers a cell. What remains is the
# operation axis: an operation joining the domain, or an existing one becoming
# size-dependent, needs a row here. The row count below is held against the
# domain so that is red rather than silent.

block:
  # THE MEMBERS ARE SPELLED HERE AND NOT NAMED FROM `ea.nim`. A row reading
  # `eaAllModes` would move with the declaration it exists to pin, and so would
  # assert nothing about it.
  const
    everyMode = {eaDn, eaAn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp, eaAnIndex,
                 eaMode7}
    everyModeButAn = {eaDn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp, eaAnIndex,
                      eaMode7}
    controlModes = {eaAnInd, eaAnDisp, eaAnIndex, eaMode7}
    mulDivLongModes = {eaDn, eaAnInd, eaAnPost, eaAnPre, eaAnDisp}
    movemModes = {eaAnInd, eaAnDisp}
    dnOnly = {eaDn}
    every7 = {ea7AbsW, ea7AbsL, ea7PCDisp, ea7PCIndex, ea7Imm}
    every7ButImm = {ea7AbsW, ea7AbsL, ea7PCDisp, ea7PCIndex}
    abs7 = {ea7AbsW, ea7AbsL}
    no7: set[EA7] = {}
    wordSize = 2'u8
    longSize = 4'u8

  # THE SIZE COLUMN IS THE KEY THE TABLE IS INDEXED BY AND THE SUFFIX IS THE
  # LABEL. A size-independent mask carries an empty suffix and is asserted at
  # the long size, which is what the size-less overload forwards to; the four
  # multiply-and-divide operations carry a row per size and say which.
  let masks: seq[(Operation, uint8, string, EaLegality)] = @[
    (opMove,  longSize, "", EaLegality(modes: everyMode, ea7: every7)),
    (opMovea, longSize, "", EaLegality(modes: everyMode, ea7: every7)),
    (opMovem, longSize, "", EaLegality(modes: movemModes, ea7: no7)),
    (opLea,   longSize, "", EaLegality(modes: controlModes, ea7: every7ButImm)),
    (opPea,   longSize, "", EaLegality(modes: controlModes, ea7: every7ButImm)),
    (opAddq,  longSize, "", EaLegality(modes: everyMode, ea7: abs7)),
    (opSubq,  longSize, "", EaLegality(modes: everyMode, ea7: abs7)),
    (opAdd,   longSize, "", EaLegality(modes: everyMode, ea7: every7)),
    (opSub,   longSize, "", EaLegality(modes: everyMode, ea7: every7)),
    (opAdda,  longSize, "", EaLegality(modes: everyMode, ea7: every7)),
    (opSuba,  longSize, "", EaLegality(modes: everyMode, ea7: every7)),
    (opAddi,  longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opSubi,  longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opClr,   longSize, "", EaLegality(modes: everyModeButAn, ea7: abs7)),
    (opExt,   longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opNeg,   longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opMulu,  wordSize, ".W",
      EaLegality(modes: everyModeButAn, ea7: every7)),
    (opMulu,  longSize, ".L",
      EaLegality(modes: mulDivLongModes, ea7: no7)),
    (opMuls,  wordSize, ".W",
      EaLegality(modes: everyModeButAn, ea7: every7)),
    (opMuls,  longSize, ".L",
      EaLegality(modes: mulDivLongModes, ea7: no7)),
    (opDivu,  wordSize, ".W",
      EaLegality(modes: everyModeButAn, ea7: every7)),
    (opDivu,  longSize, ".L",
      EaLegality(modes: mulDivLongModes, ea7: no7)),
    (opDivs,  wordSize, ".W",
      EaLegality(modes: everyModeButAn, ea7: every7)),
    (opDivs,  longSize, ".L",
      EaLegality(modes: mulDivLongModes, ea7: no7)),
    (opAnd,   longSize, "", EaLegality(modes: everyModeButAn, ea7: every7)),
    (opOr,    longSize, "", EaLegality(modes: everyModeButAn, ea7: every7)),
    (opNot,   longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opSwap,  longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opTst,   longSize, "", EaLegality(modes: everyMode, ea7: every7)),
    (opBtst,  longSize, "",
      EaLegality(modes: everyModeButAn, ea7: every7ButImm)),
    (opBchg,  longSize, "", EaLegality(modes: everyModeButAn, ea7: abs7)),
    (opBclr,  longSize, "", EaLegality(modes: everyModeButAn, ea7: abs7)),
    (opBset,  longSize, "", EaLegality(modes: everyModeButAn, ea7: abs7)),
    (opScc,   longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opAddx,  longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opSubx,  longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opNegx,  longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opExtb,  longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opEor,   longSize, "", EaLegality(modes: everyModeButAn, ea7: abs7)),
    (opAndi,  longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opOri,   longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opEori,  longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opAsl,   longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opAsr,   longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opLsl,   longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opLsr,   longSize, "", EaLegality(modes: dnOnly, ea7: no7)),
    (opJmp,   longSize, "", EaLegality(modes: controlModes, ea7: every7ButImm)),
    (opJsr,   longSize, "", EaLegality(modes: controlModes, ea7: every7ButImm)),
    (opCmp,   longSize, "", EaLegality(modes: everyMode, ea7: every7)),
    (opCmpa,  longSize, "", EaLegality(modes: everyMode, ea7: every7)),
    (opCmpi,  longSize, "", EaLegality(modes: dnOnly, ea7: no7))]

  for (op, size, suffix, expected) in masks:
    let actual = eaLegalityFor(op, size)
    checkDetail(actual == expected,
      $op & suffix & ": the legality mask is exactly the members this block " &
      "spells - a narrowing removes one and a widening adds one, and both " &
      "are RED here (measured 2026-08-12)",
      "expected " & $expected & " and got " & $actual)

  # THE KEY SET, HELD AGAINST THE DOMAIN, AND NOT THE ROW COUNT. Without this
  # an operation that gained a mask, or an existing one that gained a second
  # mask by becoming size-dependent, would be SILENTLY unpinned here - the same
  # shape of miss the `coverage` enumeration exists to turn LOUD one level up.
  #
  # A COUNT IS NOT A KEY SET, AND A TRANSCRIPTION SLIP IS WHAT SEPARATES THEM.
  # Measured with the count form in place: replacing the `opCmpi` row
  # with a DUPLICATE `opMove` row held the count at 51 and the case total at its
  # constant, the whole suite stayed green, and a two-mode widening of `opCmpi`
  # then red NOTHING ANYWHERE - 0 cases, the baseline exactly. The comparison
  # below is between SETS, so the duplicate and the omission are each named.
  #
  # AND THE SIZE AXIS IS WALKED OVER EVERY SIZE THE KEY ADMITS, NOT OVER TWO.
  # The count form asked `eaLegalityFor` at the word and long sizes alone, so a
  # mask that differed at BYTE size alone was pinned by no row and missed by the
  # count: measured, `opAnd` split from `opOr` at byte size only red
  # 0 cases across the suite and left the row count where it was. Nothing
  # branches on byte today, which is what makes that latent rather than live -
  # the bit operations are the obvious future case - and the key is a `uint8`,
  # so every value of one is what the loop below walks. Deriving the domain from
  # `eaLegalityFor` is sound because what is derived is WHICH ROWS ARE REQUIRED
  # and never the value of any row.
  var declaredKeys: seq[(Operation, uint8)] = @[]
  var duplicateKeys: seq[string] = @[]
  for row in masks:
    let key = (row[0], row[1])
    if key in declaredKeys: duplicateKeys.add($row[0] & " at size " & $row[1])
    else: declaredKeys.add(key)

  var declaredMasks: seq[(Operation, EaLegality)] = @[]
  for (op, size) in declaredKeys:
    let pinned = (op, eaLegalityFor(op, size))
    if pinned notin declaredMasks: declaredMasks.add(pinned)

  var domainMasks: seq[(Operation, EaLegality)] = @[]
  for op in Operation:
    for sizeIndex in int(low(uint8)) .. int(high(uint8)):
      let answered = eaLegalityFor(op, uint8(sizeIndex))
      if card(answered.modes) == 0: continue
      if (op, answered) notin domainMasks: domainMasks.add((op, answered))

  var unpinned: seq[string] = @[]
  for entry in domainMasks:
    if entry notin declaredMasks: unpinned.add($entry[0] & " " & $entry[1])
  var stale: seq[string] = @[]
  for entry in declaredMasks:
    if entry notin domainMasks: stale.add($entry[0] & " " & $entry[1])

  checkDetail(duplicateKeys.len == 0 and unpinned.len == 0 and
              stale.len == 0 and masks.len == domainMasks.len,
    "this block carries one row per operation-and-size mask in the domain, " &
    "held as a KEY SET rather than as a row count",
    $masks.len & " rows written and " & $domainMasks.len &
    " masks in the domain; duplicate keys: " & $duplicateKeys &
    "; masks no row pins: " & $unpinned &
    "; rows the domain does not carry: " & $stale)

# ---------------------------------------------------------------------------
# (6) The decoder recognizes each implemented opcode from a representative
# word, so the legality assertions above are attached to a decoder that runs.

block:
  let words: seq[(uint16, Operation, string)] = @[
    (0x4E71'u16, opNop,   "NOP"),
    (0x3010'u16, opMove,  "MOVE.L (A0),D0"),
    (0x5000'u16, opAddq,  "ADDQ"),
    (0x5100'u16, opSubq,  "SUBQ"),
    (0x41D0'u16, opLea,   "LEA (A0),A0"),
    (0x7000'u16, opMoveq, "MOVEQ"),
  ]
  for (word, opx, name) in words:
    check(decodeWord(word).op == opx,
      "decodes " & name & " (0x" & word.toHex(4) & ")")

# ---------------------------------------------------------------------------
# (4) The extension-word order of absolute long addressing, and a control for
#     it.
#
# ColdFire Family Programmer's Reference Manual, Rev. 3, section 2.2.11 and
# Figure 2-13: `(xxx).L` occupies two extension words, and "the first
# extension word contains the high-order part of the address; the second
# contains the low-order part." A core that reads them the other way round
# assembles 0x00123456 as 0x34560012 and every absolute-long operand reads the
# wrong place.
#
# No corpus case reaches this. `conformance/corpus/` holds no `(xxx).L`
# operand in any group, so a swap is invisible to every registered conformance
# test. This case is what makes it visible.
#
# The case runs through the shipped C entry points and not through `eaAddr`
# reached around the back, so it asserts the path the corpus runner drives.
#
# The second assertion is the control. The board answers the swapped address
# with a different value rather than with a fault, so the first assertion
# fails on a wrong value and not on a bus error the core would have reported
# for any number of unrelated reasons. Asserting that the swapped address was
# never presented to the board is what separates "the address was assembled
# correctly" from "the read happened to land somewhere that answered".

const
  absLProgramBase = 0x100'u32
  absLTargetAddr = 0x00123456'u32
  absLSwappedAddr = 0x34560012'u32
  absLTargetValue = 0xCAFEBABE'u32
  absLDecoyValue = 0x0BADC0DE'u32

var absLSawSwapped = false

# `move.l (0x00123456).L,%d0`. Source mode 111 register 001 is absolute long;
# destination mode 000 register 000 is D0; bits 13..12 of 0b10 are the long
# size. Assembled by hand from the encoding in the manual, and the two
# extension words below are the manual's order: high first.
proc readAbsL(user: pointer; address: uint32; size: cint;
              status: ptr Mcf5307BusStatus): uint32 {.cdecl.} =
  status[] = Mcf5307BusStatus.busOk
  if address == absLSwappedAddr:
    absLSawSwapped = true
    return absLDecoyValue
  case address
  of absLProgramBase: 0x2039'u32          # move.l (xxx).L,%d0
  of absLProgramBase + 2: 0x0012'u32      # first extension word:  high half
  of absLProgramBase + 4: 0x3456'u32      # second extension word: low half
  of absLTargetAddr: absLTargetValue
  else: 0'u32

block:
  let ctx = mcf5307_create(nil, readAbsL, writeNoop, iackNoop)
  discard mcf5307_set_reg(ctx, 0, 0'u32)
  mcf5307_reset(ctx, 0x4000000'u32, absLProgramBase)
  discard mcf5307_exec(ctx, 64'u32)
  let d0 = mcf5307_get_reg(ctx, 0)
  check(d0 == absLTargetValue,
    "move.l (0x00123456).L,%d0 reads the address whose HIGH half is the " &
    "first extension word (got 0x" & d0.toHex(8) & ")")
  check(not absLSawSwapped,
    "the word-swapped address 0x34560012 is never presented to the board")
  mcf5307_destroy(ctx)


# (18) This file's own case total, held against the one figure the other sites
# quote. Block (13) above, the `opMovem` arm of `decode_types.nim` and
# `cpu.nim`'s per-suite BASELINE line each name the total the summary line at
# the foot of this file prints. When that figure was prose in two files it went
# stale repeatedly and nothing went red.
#
# The figure now exists once, as `caseTotalMustMatchTranscripts`, and the other
# sites name the constant rather than spelling a number. This case is what
# keeps the constant true: it holds the live count of every case this run
# emitted against it, so a block added to or removed from this file is red here
# until the constant moves.
#
# It is a run-time case and not the `static: doAssert` assertion (9) uses, and
# that is forced rather than preferred. `passCount` and `failures` are
# accumulated by the enumeration over `Operation` and over the `coverage` seq,
# and both are run-time values: appending
# `static: doAssert failures.len + passCount == <any total>` to this file fails
# to compile, with `Error: cannot evaluate at compile time: failures`, and the
# registered test reports that as a driver error rather than as a case.
#
# The `+ 1` is this case itself. `checkDetail` below is called exactly once in
# this block and increments one of the two counters whichever way it goes, so
# the figure the summary line goes on to print is one greater than the one read
# here. The constant is the summary line's figure, because that is the figure
# the other sites quote.
#
# What it does not catch: it pins the count and says nothing about which cases
# ran, so one block deleted and another of the same size added in a single
# change passes.

const caseTotalMustMatchTranscripts = 451
  ## The total the summary line prints. Its value is written down once in this
  ## repository - here - and the sites that need the denominator name the
  ## constant instead of copying it. The case below is what refuses to let it
  ## be moved wrongly.
  ##
  ## The limit is the symbol and not the value, and it is uncloseable from here.
  ## Those sites name this constant as text inside a comment, and nothing
  ## links the text to the symbol: renaming or deleting the constant leaves
  ## them stale with nothing red. An import cannot close it - `src/` does not
  ## import `tests/`, and this constant is not exported - and exporting it
  ## would not help, because a comment cannot reference a symbol at all.

block:
  let totalBeforeThisCase = failures.len + passCount
  checkDetail(totalBeforeThisCase + 1 == caseTotalMustMatchTranscripts,
    "this run emits the case total `caseTotalMustMatchTranscripts` records, " &
    "which is the figure all three sites quote - block (13) here, the " &
    "`opMovem` arm of `decode_types.nim`, and the BASELINE line in `cpu.nim`",
    "the constant records " & $caseTotalMustMatchTranscripts &
    " and this run emitted " & $(totalBeforeThisCase + 1) &
    "; a block was added to or removed from this file, so move the constant " &
    "and re-read all three sites")

# ---------------------------------------------------------------------------
# The summary line carries the attribution figure, because a bare count would
# let the reader conclude that every operation is guard-covered.
#
# No count is written down in this comment or in the line itself. Every figure
# the line prints is counted by the run that prints it.
#
# A plain `ctest` prints `t_ea_masks ... Passed` and captures this program's
# stdout, so a CI summary shows the name and the status and nothing below.
# Nothing this program prints can change that: the registered name and the
# driver both live in `tests/tests_cpu.cmake`. The line below serves the reader
# of `-V`, of a failing run, or of the saved log.
#
# The driver's pass pattern still matches. It searches for
# `t_ea_masks: <N> cases passed` and is not anchored at the end, so text
# appended after that phrase is safe and text inserted inside it is not.

proc attribution(): string =
  ## Both figures are counted by the run, and that is still not enough to make
  ## the line a measurement. `discriminating` is a hand-declared field; the sum
  ## over it is live, the evidence under it is not. A new entry declaring
  ## `discriminating: true` and measuring nothing raises the numerator with
  ## exactly the authority of a measured one. The line therefore says DECLARE,
  ## and carries the date of the evidence.
  ##
  ## The denominator is the domain and not the covered set, so an operation
  ## that joined the domain without an entry enlarges it rather than shrinking
  ## the figure.
  result = " (guard attribution: " & $opsDiscriminating & " of the " &
    $opsInDomain & " operations in the domain DECLARE `discriminating: true`" &
    " - a sum over a hand-declared field, not a measurement this run makes;" &
    " the guard-deletion evidence behind those declarations is dated " &
    guardMeasurementDate & " in the header and an entry added since then" &
    " declares its value rather than measures it"
  if opsCovered != opsInDomain:
    result.add("; for " & $(opsInDomain - opsCovered) & " of those operations" &
      " no coverage entry exists - they are RED above, and their attribution" &
      " is UNKNOWN rather than false")
  result.add(")")

# THE REGISTRY LINES. They are DATA AND NOT A VERDICT: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_ea_masks", declaredCaseSites)
echo caseSiteLine("executed", "t_ea_masks", executedSites)
echo caseSiteLine("off-green-path", "t_ea_masks", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_ea_masks: ", failures.len, " of ", failures.len + passCount,
      " cases failed", attribution()
  quit(1)
else:
  echo ""
  echo "t_ea_masks: ", passCount, " cases passed", attribution()
