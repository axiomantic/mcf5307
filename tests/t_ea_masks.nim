## `t_ea_masks` - the decoder and effective-address legality masks.
##
## THE MEASUREMENT TRANSCRIPTS THAT ESTABLISH WHAT THIS FILE CATCHES ARE NOT
## HERE. They live in section 24.7, "Execution measurement transcripts - the
## CPU-6 `t_ea_masks` mutation record", of
## `~/.local/spellbook/docs/Users-eek-Development-workspaces-nord-modular-emulator/plans/2026-08-04-nmg2-emulator-impl.md`,
## each with its date and the exact mutation that produced it. That plan's
## section 7.7 carries the standing rule they are filed under: a measurement's
## transcript lives in a numbered plan section and never beside the claim it
## supports. What is kept HERE is the manual citations, the stated limit of
## each assertion, and what a reader of the CODE needs in order to change it.
##
## THE COVERAGE DOMAIN IS THE LEGALITY TABLE ITSELF, AND THAT IS THE WHOLE
## POINT OF THE FILE. `eaLegalityFor` spreads its operations across SIXTEEN
## `of` arms, and the `Check:` line of CPU-6 claims a trap for at least one
## illegal mode for EACH implemented opcode.
##
## THAT ARM COUNT IS HAND-MAINTAINED AND NOTHING CHECKS IT. It read "fifteen"
## until 2026-08-11, when the multiply-and-divide size split added the
## sixteenth arm and no run went red. It is kept because it tells a reader how
## large the table is, and it is LABELLED because this project has measured
## eleven stale hand-written counts, three of them created inside fixes for
## other stale counts. Nothing here can derive it: an `of` arm is a syntactic
## property of another module with no runtime witness, and a count recovered
## by reading that module's TEXT would go silently wrong rather than red the
## first time the file grew a second `case` statement - which is the failure
## this label exists to avoid repeating.
##
## THE OPERATION COUNT IS NOT HAND-MAINTAINED AND IS DELIBERATELY ABSENT FROM
## THIS SENTENCE, which named FORTY-SEVEN of them until the same date. The
## summary line at the foot of this file counts the domain in the run that
## prints it, and the driver reds when an operation joins the domain without a
## coverage entry, so the figure is available from a run and no copy of it is
## kept here to go stale.
##
## THE MECHANISM OF THE MISS IS WORTH MORE THAN THE ARITHMETIC. When `SWAP`
## was implemented, adding `opSwap` to `eaLegalityFor` did not turn this file
## red, because a hand-maintained list makes a new opcode SILENTLY UNCOVERED
## rather than LOUDLY MISSING. The driver below iterates `Operation` and
## requires a coverage entry for every operation whose mask is non-empty, so
## an operation added to the table with no entry makes the run RED in the wave
## that added it. The reverse direction is checked too: an entry for an
## operation whose mask has gone empty is a stale entry and is also RED.
##
## THE SKIP RULE, STATED ONCE. An operation is outside the domain WHEN AND
## ONLY WHEN `eaLegalityFor` returns an EMPTY mask. That is the same test
## `eaIsLegalFor` already makes, and that proc's own doc comment in
## `decode_types.nim` - "THE EMPTY MASK IS THE TEST" - says why a second
## list of the same operations drifts.
##
## NOTHING HERE IS SKIPPED FOR BEING UNREACHABLE FROM THE DECODER, AND THAT
## RESTRICTION IS LOAD-BEARING RATHER THAN DECORATIVE. A skip justified by
## reachability would have skipped `SWAP` - the defect this file exists to
## catch, and the one that `decode.nim`'s PEA mask really was hiding while
## `cpu.nim`'s `opExg, opTas, opNbcd` arm carried the sentence "no arm
## produces `opSwap`". Reachability is not a skip criterion here at any
## strength.
##
##   (4) The extension-word order of absolute long addressing, with its own
##       control. `(xxx).L` carries the high half of the address in the first
##       extension word. No case in `conformance/corpus/` uses an absolute-long
##       operand at all, so nothing else in this project can see a core that
##       reads the two words the other way round. The block near the end of
##       this file says which manual section that is and why the control is
##       there.
##
## THE ILLEGAL MODE OF EACH ENTRY IS SOURCED FROM THE MANUAL AND NEVER FROM
## `eaLegalityFor`, AND THAT IS WHAT KEEPS THE FILE FROM PROVING NOTHING. A
## driver that asked `eaLegalityFor` which mode is outside the mask and then
## asserted `eaIsLegalFor` rejects it would be asserting the mask against
## itself: it would pass against ANY mask, including a wrong one, and a
## widened mask would move the asserted mode with it. Every `illegal` field
## below carries its own citation, so a mask that widens to admit THAT mode
## turns the entry RED instead of moving it. A widening that admits some OTHER
## mode is invisible here, and assertion (1) below carries that limit.
##
## THE WORD "EVERY" IN THAT PARAGRAPH IS ASSERTION (11) AND NOT A PROMISE.
## `why` is required by `cov`, so a row cannot omit a citation but can pass one
## citing nothing; (11) requires each to name a manual table.
##
## FOUR ASSERTIONS PER OPERATION, AND EACH ONE CAN FAIL.
##
##   (1) THE PREDICATE REJECTS THE ILLEGAL MODE. This is the assertion that
##       catches a mask WIDENED TO ADMIT THE MODE THE ENTRY CITES, and it
##       catches that for every operation, the ones assertion (4) cannot
##       attribute included.
##
##       IT CATCHES NO OTHER WIDENING. Each entry names exactly ONE illegal
##       mode, so a mask that widens somewhere else passes (1) unchanged.
##       This is the exact mirror of the narrowing blindness recorded further
##       down, and it has the same single cause: one cited mode per entry.
##       Both directions are measured; the plan section holds both.
##
##   (2) THE PREDICATE ACCEPTS A LEGAL MODE - the positive control. Without
##       it, a mask that rejected everything would report (1) as a pass and
##       "the illegal mode is rejected" would not be separable from "the
##       opcode admits no mode at all".
##
##   (3) THE EXECUTOR RUNS THE LEGAL MODE. It is the control for (4) and it
##       does two jobs: it proves the operand, size and family of the entry
##       are a combination the executor accepts, so that a fault in (4)
##       cannot be blamed on a mis-set size or a mis-routed family, and it
##       proves the refusal in (4) is attributable to the EFFECTIVE ADDRESS,
##       which is the only field that differs between the two runs.
##
##   (4) THE EXECUTOR REFUSES THE ILLEGAL MODE - the TRAP the `Check:` line
##       names. The refusal is asserted as a WHOLE STATE and not as a flag:
##       `fault` set, `halted` set, ZERO cycles returned, ZERO bus accesses,
##       and every data register, address register, stack pointer, program
##       counter and status-register bit unchanged. A refusal that ran part
##       of the instruction first is not a refusal. THE ADDRESS HALF OF THAT
##       IS REAL ONLY BECAUSE `aRegSeed` SEEDS THE ADDRESS REGISTERS
##       DISTINCTLY: while all seven held `ramBase`, an operation that copied
##       one address register into another before refusing passed.
##
## TWO MORE RUN FOR THE TABLE 3-13 ENTRIES ALONE, one per axis of the citation,
## and each holds a DECLARED value against an INDEPENDENT recording of the same
## fact rather than against the value itself. The numbering skips (5) and (6),
## which are the two older assertions described further down; the numbers here
## are the ones the code uses.
##
##   (7) THE PAGE. Derived from the operation's mnemonic through the table's own
##       row ordering and compared against the page the entry declared. The
##       block defining `Table313Page` below carries the argument.
##
##   (8) THE `#xxx` COLUMN. Derived by running the entry twice with different
##       immediates and comparing the two outcomes, which is the operational
##       content of that column. `table313ImmOf` carries the argument, the two
##       measured directions, and the limit.
##
## AND THREE COVER THE TABLE AND THE ENUMERATION RATHER THAN ANY ONE
## OPERATION. Each replaces a sentence this header used to assert by hand.
##
##   (9) `table313LastRowOn328` HELD AGAINST `decode_types.nim`, which records
##       the same page break in its own `table313LastRowOnPage328`. A
##       `static: doAssert`, so the co-edit of the constant and the
##       declarations FAILS THE BUILD; assertion (7) alone was green for it.
##
##  (10) EVERY `Operation` MEMBER NAME BEGINS WITH `op`, the property the
##       mnemonic derivation behind (7) rests on.
##
##  (11) EVERY `coverage` ROW CITES A MANUAL TABLE for its `illegal` mode, which
##       is the "every" the anti-tautology paragraph above rests on.
##
## WHAT ASSERTION (7) CATCHES IS A MIS-DECLARED PAGE HELD AGAINST A FIXED
## BREAK, AND NOT A WRONG PAGE AS SUCH. It is held against
## `table313LastRowOn328`, and the two directions measure differently: a LONE
## mis-declaration is RED, while a CO-EDIT that moves the break constant and
## the twelve declarations together goes green past assertion (7). Assertion
## (9) is what refuses the co-edit, and it refuses it at COMPILE time rather
## than as a case - so (7)'s twelve cases never run. Both directions are
## transcribed in the plan section.
##
## THE BREAK CONSTANT IS ITSELF CHECKED, AND IT IS NOT CHECKED AGAINST THE
## DECLARATIONS IT VALIDATES - that would be the tautology. Assertion (9)
## holds it against a THIRD record, `decode_types.nim`'s own
## `table313LastRowOnPage328`.
##
## ASSERTION (4) IS NOT EQUALLY STRONG FOR EVERY OPERATION, AND THE ENTRIES
## SAY SO RATHER THAN LETTING THE COUNT IMPLY OTHERWISE. ELEVEN operations
## carry a mask WHOSE COMPLEMENT THE MACHINE LAYER ALREADY REFUSES. For those
## eleven the executor does refuse the illegal operand, and the refusal is
## real, but it CANNOT be attributed to the operation's own guard: deleting
## the guard leaves a machine-layer fallback to fault in its place. Those
## eleven carry `discriminating: false`, and assertion (1) is what covers a
## widening TO THE CITED MODE for them - only that one, at the strength
## assertion (1) states above and not a step past it. The other 36 carry
## `discriminating: true`: deleting the operation's guard makes the entry RED.
##
## THE 36 IS A MEASUREMENT AND NOT AN ESTIMATE - guards deleted and run, on the
## date `guardMeasurementDate` below carries. The plan section holds the three
## deletions, the evidence that each reached the compiled artifact, and the
## correction that the widest of them covered 25 of the 27 family-module guards
## rather than all 27.
##
## THE CRITERION IS THE COMPLEMENT OF THE MASK AND NOT A ROSTER OF OPCODE
## NAMES, so a twelfth operation is recognized by reading `ea.nim` rather than
## by remembering this paragraph. Two masks meet it, for two DIFFERENT reasons.
##
##   - MOVE, MOVEA, ADD, SUB, ADDA, SUBA, TST, CMP and CMPA carry
##     `eaAllModes`/`eaValid7`, which admits every addressing mode Table 3-5
##     p.3-21 prints. The only encodings outside it are the RESERVED mode-7
##     ones, and `machine.nim`'s `eaAddr` and `eaRead` fault on those
##     independently of any mask.
##
##   - ADDQ and SUBQ carry `eaAllModes`/`eaAlterable7`, whose mode-7
##     half is `{ea7AbsW, ea7AbsL}`. `machine.nim`'s `eaResolve` accepts
##     EXACTLY those two mode-7 encodings as a destination and faults on every
##     other one, so the complement of this mask and the set `eaResolve`
##     refuses ARE THE SAME SET. `(d16,PC)` is therefore not an unlucky pick:
##     NO choice of illegal operand makes these two entries discriminating,
##     and one chosen to look stronger would only hide that.
##
## THE LATENT DEFECT THE ELEVEN LEAVE OPEN IS RECORDED HERE RATHER THAN
## PAPERED OVER WITH A CASE THAT WOULD LOOK LIKE COVERAGE. Those eleven guards
## are unprotected by anything the repository currently runs. It is not a live
## defect - the machine layer refuses the same operands TODAY, so the two
## behave alike. It is a LATENT one: the day a machine-layer fallback changes,
## nothing here says so. Closing it needs a case whose illegal operand is a
## mode the machine layer would otherwise execute happily, and by the criterion
## above no such mode exists for these eleven masks.
##
## "UNPROTECTED BY ANYTHING THE REPOSITORY CURRENTLY RUNS" IS MEASURED FOR
## FOUR OF THE ELEVEN AND UNCHECKED FOR THE OTHER SEVEN, and the sentence
## above spans the repository while its evidence does not. Only two of the
## guard-deletion runs went suite-wide, and they cover MOVE, MOVEA, ADDQ and
## SUBQ. For ADD, SUB, ADDA, SUBA, TST, CMP and CMPA the claim rests on THIS
## FILE alone: no suite-wide run with those seven guards deleted is recorded,
## and none was made. UNCHECKED, and closing it is one deletion and one full
## run rather than an argument.
##
## A NARROWED MASK IS INVISIBLE TO THIS FILE FOR EVERY ENTRY, AND NOT ONLY FOR
## THE ELEVEN. Each entry names exactly ONE legal mode, so a mask NARROWED to
## that single mode passes all four assertions unchanged: (1) still rejects the
## cited illegal mode, (2) still accepts the one legal mode the entry names,
## and (3) and (4) drive those same two operands and nothing else. Most entries
## name `Dn`, so ONE narrowing to `{eaDn}` is invisible here for all of those at
## once; the control-addressing entries name `(An)`, and a narrowing to
## `{eaAnInd}` is invisible for those. Nothing about the eleven makes narrowing
## worse for them than for the rest - the discriminating flag is about assertion
## (4)'s ATTRIBUTION and says nothing at all about narrowing.
##
## THE MITIGATION IS PARTIAL AND LIVES OUTSIDE THIS FILE. `t_move`, `t_alu`,
## `t_logic`, `t_control` and the conformance corpus assert POSITIVE behaviour
## on legal modes, so a narrowing that removes a mode one of THOSE exercises
## turns them red. A narrowing that removes a mode NOTHING in the repository
## exercises goes unnoticed everywhere, this file included.
##
## ONE NARROWING HAS BEEN MEASURED, AND WHAT CAUGHT IT WAS THE CONFORMANCE
## CORPUS AND NOT THE FAMILY TEST THE PARAGRAPH ABOVE NAMES FIRST. `opMove` and
## `opMovea` narrowed to `{eaDn}`/`{}` left THIS FILE green and `t_move` green,
## and turned `mcf5307_conformance_move` red. `t_move` drives MOVE
## register-to-register only, so it asserts positive MOVE behaviour on the one
## mode that narrowing keeps. The transcript is in the plan section.
##
## ONE NARROWING OF ONE MASK IS NOT THE GENERAL CASE, AND NOTHING HERE CLAIMS
## IT IS. The other masks were NOT mutated. For them the paragraph above
## remains an argument about where coverage happens to fall, and an argument
## and a measurement are not interchangeable.
##
## THE OTHER TWO ASSERTIONS THE FILE HAS ALWAYS CARRIED ARE KEPT.
##
##   (5) THE FIRST NON-ZERO CYCLE RETURN, moved here from CPU-3, driven
##       through the real ABI with a board that returns `MCF5307_BUS_OK` and a
##       `NOP` for every fetch. A core that returns zero cycles cannot loop at
##       all, so this separates "the decoder ran" from "the decoder is not
##       wired in".
##
##   (6) THE DECODER RECOGNIZES A REPRESENTATIVE WORD for each of a handful of
##       opcodes, so that the legality assertions are attached to a decoder
##       that runs and not only to a table.
##
## AND ONE ASSERTION ABOUT THE TABLE ITSELF RATHER THAN ABOUT ANY OPERATION.
## The enumeration takes the FIRST `coverage` row matching each operation, so a
## SECOND row for an operation that already has one runs nothing and reports
## nothing. The count of rows WRITTEN is therefore held against the count of
## rows REACHED, a dead row is RED, and the red NAMES the rows that ran
## nothing.
##
## There is no supervisor and user stack split on ISA_A; the context holds the
## single `sp`.

## THE IMPORTS NAME THE LAYER EACH SYMBOL COMES FROM. `decode` no longer
## re-exports `decode_types`, so each module below supplies exactly the names
## the test takes from it: `cpu` the lifecycle ABI, `decode` the decoder
## (`decodeWord`), `decode_types` the shared types and the legality table,
## `ea` the effective-address decoding, and the four instruction-group modules
## their family entry points, which is the layer assertions (3) and (4) drive.
##
## `machine` supplies the register bridge (`mcf5307_set_reg`,
## `mcf5307_get_reg`) that the absolute-long extension-word case drives.

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
var passCount = 0

## THE FIGURES THE SUMMARY LINE CARRIES, COUNTED WHILE THE ENUMERATION RUNS AND
## NEVER WRITTEN DOWN. A hardcoded "36 of 47" would be the same defect the
## header describes one level up: a stated number that goes stale silently.
## These are incremented by the loop, so they describe THIS run.
##
## THE DOMAIN AND THE COVERED SET ARE COUNTED SEPARATELY BECAUSE THEY COME
## APART EXACTLY WHEN IT MATTERS. `opsInDomain` counts operations with a
## non-empty mask - the population the file claims to cover. `opsCovered`
## counts those an entry actually reached. They are equal in a green run and
## differ in a run where an operation gained a mask and no entry; collapsing
## them into one counter made the summary report a SMALLER domain in precisely
## that run.
var opsInDomain = 0
var opsCovered = 0
var opsDiscriminating = 0

const guardMeasurementDate = "2026-08-10"
  ## The date of the guard-deletion measurement the plan section records. The
  ## summary line carries it so the reader of a bare log can tell how old the
  ## evidence behind `discriminating` is without opening the plan.

proc check(cond: bool; label: string) =
  if cond:
    echo "PASSED  ", label
    inc passCount
  else:
    echo "FAILED  ", label
    failures.add(label)

proc checkDetail(cond: bool; label: string; got: string) =
  if cond:
    echo "PASSED  ", label
    inc passCount
  else:
    echo "FAILED  ", label
    echo "          got  ", got
    failures.add(label)

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
# the shape `t_move` and `t_alu` established. IT COUNTS ITS ACCESSES: a
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
    ## NOT imported from `cpu.nim`: one shared symbol would hide a wrong value.
func aRegSeed(i: int): uint32 = ramBase + uint32(i) * aRegSeedStrideMustBeNonZero
static:
  for i in 0 .. 7: doAssert dRegSeedMustBeNonZero + uint32(i) != 0'u32
  for i in 1 .. 6: doAssert aRegSeed(i) > aRegSeed(i - 1)

## TABLE 3-13 SPANS TWO PAGES, SO THE PAGE IS A PARAMETER AND NOT A DEFAULT.
## The table begins on p.3-28 and CONTINUES on p.3-29, and three of the twelve
## rows cited below - `ori.l`, `subi.l` and `subx.l` - are on the continuation
## page. Both pages were read RENDERED.
##
## ONE SHARED CONSTANT CANNOT HOLD TWO PAGES, and `decode_types.nim` records
## that this codebase already made the mistake once - "An earlier revision of
## this line put all three on 3-28". Two constants would not close it either: a
## thirteenth entry would pick one of them, and picking the wrong one is
## exactly as silent as before.
##
## A REQUIRED PARAMETER IS WHAT CANNOT FLATTEN. The page is not defaultable,
## so an entry cannot INHERIT a page it never stated; and `Table313Page` is an
## enum, so the only two spellings are the two pages the table actually spans
## and a typo is a compile error rather than a wrong citation.
##
## BUT A REQUIRED PARAMETER MAKES THE CHOICE UNAVOIDABLE AND NOT CORRECT, WHICH
## IS WHY ASSERTION (7) EXISTS. Its own objection to two constants - "a
## thirteenth entry would pick one of them" - survives the parameter unaltered:
## a thirteenth entry can write `p313Start` for a row that prints on 3-29 and
## nothing in the parameter says so. That lone mis-declaration was measured
## GREEN before (7) existed and is RED with (7) in place; the plan section
## carries both runs. What (7) does NOT close is the CO-EDIT: move the break
## constant and the declarations together and the two go green past each other,
## which is assertion (9)'s subject.
##
## SO THE PAGE IS DERIVED AND THE DECLARED ONE IS CHECKED AGAINST IT. The
## derivation rests on a property of the table that was read from the RENDERED
## p.3-28 and p.3-29 and NOT from `pdftotext` and NOT from the markdown
## conversion under `datasheets/MCF5307UM-md/`, whose Table 3-13 is known
## wrong:
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
## SPELLING IT IS NOT CHECKING IT, AND ASSERTION (8) IS THE CHECK. IT IS
## TWO-SIDED, which one mutation would not have shown: a check that answered
## `imm313Timed` for everything would catch a timed row declared dashed and
## nothing else. Both directions were mutated - a genuinely timed row declared
## dashed, and a genuinely dashed row declared timed - and both are RED. The
## plan section carries the two transcripts and the evidence that each reached
## the compiled artifact.
##
## WHAT (8) DOES NOT DO IS READ THE MANUAL, and neither does (7). Each holds a
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
# mode-7 encoding: Table 3-5 p.3-21 prints REG. FIELD values 000, 001, 010,
# 011 and 100 under MODE FIELD 111 and no others, so 101 is not an addressing
# mode at all.
const
  mDn = EA(mode: eaDn, reg: 0)
  mAn = EA(mode: eaAn, reg: 0)
  mAnInd = EA(mode: eaAnInd, reg: 0)
  mAnPre = EA(mode: eaAnPre, reg: 0)
  mPcDisp = EA(mode: eaMode7, reg: uint8(ord(ea7PCDisp)))
  mReserved = EA(mode: eaMode7, reg: uint8(ord(ea7Unused5)))

# The citations, named once each so that the entries sharing a manual row
# cannot drift into as many wordings of it. Every one was read from a RENDERED
# page of the MCF5307 User's Manual.
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
  # CONSTANT WHILE `whyDashMemory313` IS A FUNCTION OF THE PAGE. Verified on
  # the RENDERED page: section 3.10 opens Table 3-12 on p.3-27, its last row
  # `tst.l` is on that same page, and p.3-28 opens section 3.11 with Table
  # 3-13. There is therefore NO page for a further 3-12 entry to pick wrongly,
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
  # THESE TWO ARE NON-DISCRIMINATING FOR THE SECOND REASON THE HEADER GIVES.
  # `execAddSubQ` reaches its destination through `eaResolve`, which accepts
  # `{ea7AbsW, ea7AbsL}` and faults on every other mode-7 encoding - the exact
  # complement of `eaAlterable7`. Measured by deleting this operation's guard,
  # which leaves the entry GREEN; the plan section carries the run.
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
  # mask is `{eaDn}` on Table 3-7 p.3-25's `Dn` operand syntax and Table
  # 3-12 p.3-27's `swap Dx` row, timed 1(0/0) under Rn with a dash in all
  # seven other columns, both read from RENDERED pages.
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

  # (7) THE DECLARED TABLE 3-13 PAGE, HELD AGAINST THE DERIVED ONE. This runs
  # for the Table 3-13 entries alone; the block defining `Table313Page` carries
  # the argument, including the measured green this assertion closes.
  if c.page313.isSome:
    let derived = table313PageOf(c.op)
    checkDetail(c.page313.get == derived,
      name & ": its Table 3-13 row is on the page the entry cites",
      "the entry declares p." & $c.page313.get &
      " and the mnemonic derives p." & $derived)

  # (8) THE DECLARED `#xxx` COLUMN, HELD AGAINST THE ONE THE EXECUTOR SHOWS.
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
# (1) to (4) - and (7) where it applies - ENUMERATED OVER `Operation`. The loop
# below, and not the table above, is what makes an opcode that gains a mask
# LOUDLY MISSING.

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
      # THE DOMAIN IS COUNTED HERE AND NOT INSIDE `runCoverage`, BECAUSE THE
      # RUN THAT MOST NEEDS THE FIGURE IS THE RUN WHERE AN ENTRY IS MISSING.
      # See the declaration of `opsInDomain` for why the two counters are
      # separate.
      inc opsInDomain
      if entry < 0:
        check(false,
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
  # The citation STRING and the `page313` field are written by one call but are
  # two different values, so each is a witness for the other: a row citing
  # Table 3-13 with no page, or a page on a row citing something else, is RED.
  # Both directions are measured, and the plan section carries both.
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

  # (10) EVERY `Operation` MEMBER NAME BEGINS WITH `op`. `table313PageOf`
  # asserts this for the twelve members it is called with and CRASHES on a
  # member that breaks it - a crash rather than a case. Checking it for the
  # WHOLE enumeration turns "a misnamed member would crash the derivation" from
  # a sentence about a hypothetical into a property of the enumeration as it
  # stands, and it costs one case rather than twelve.
  var misnamed: seq[string] = @[]
  for op in Operation:
    if not ($op).startsWith("op"): misnamed.add($op)
  checkDetail(misnamed.len == 0,
    "every `Operation` member name begins with `op`, which is what the " &
    "mnemonic derivation behind assertion (7) rests on",
    "these are not: " & $misnamed)

  # (11) EVERY ROW'S `illegal` FIELD CARRIES A MANUAL CITATION. The header
  # rests its whole anti-tautology argument on that, and it was a sentence
  # rather than a check. `why` is a required parameter, so a row cannot omit
  # it, but a row CAN pass a hand-written string that cites nothing; every
  # citation this file uses names a manual table, so that is what is required.
  var uncited: seq[string] = @[]
  for c in coverage:
    if not c.why.startsWith("Table 3-"): uncited.add($c.op)
  checkDetail(uncited.len == 0,
    "every `coverage` row cites a manual table for its `illegal` mode",
    "these do not: " & $uncited)

# ---------------------------------------------------------------------------
# (12) THE MULTIPLY AND DIVIDE CARRY TWO MASKS, ONE PER SIZE, AND THE FOUR
# `coverage` ROWS ABOVE CANNOT SEE THE SPLIT. Those rows cite the `An` row of
# Table 3-5, which is dashed at BOTH sizes, so widening or narrowing either
# mask anywhere else leaves all four green. This block is the guard for the
# split itself.
#
# WHAT COLLAPSING THE ARM ACTUALLY REDS IS A QUARTER OF THIS BLOCK, AND AN
# EARLIER REVISION OF THIS COMMENT CLAIMED ALL OF IT. It read "each assertion
# below goes RED on the single data-alterable mask the four operations shared
# before it existed". Measured 2026-08-11: with the arm collapsed back to that
# single mask, 24 of the 96 cell assertions below go RED and the other 72
# PASS.
#
# THE 24 ARE THE SAME SIX IN EACH OF THE FOUR OPERATIONS: the `.L` REJECTS
# half of `(d8,Ay,Xi)`, `(xxx).W` and `(xxx).L`, and the `.W` accepts half of
# `(d16,PC)`, `(d8,PC,Xi)` and `#<data>`.
#
# THE OTHER 72 CANNOT SEE THE COLLAPSE, for one reason in two shapes. The ten
# shared-mode assertions and the two `Ay` assertions of each operation name
# cells where the collapsed mask AGREES with both real masks, and A MODE BOTH
# MASKS SHARE IS NOT EVIDENCE ABOUT THE SPLIT. Within each of the six split
# pairs the collapsed mask matches exactly ONE column - the three modes it
# holds satisfy the word half, the three it lacks satisfy the long half - so
# one assertion of every pair reds and its partner passes. The four
# size-less-overload assertions at the foot of the block stay green as well,
# because both sides of that equality read whatever single mask the arm
# returns.
#
# THE SOURCE IS THE CFPRM AND THE ASSEMBLER, AND THEY AGREE ON ALL 96 CELLS.
# The "Instruction Fields (Word)" addressing-mode table is on folios 4-32
# (DIVS), 4-34 (DIVU), 4-55 (MULS) and 4-57 (MULU); the "Instruction Fields
# (Longword)" one is on folios 4-32, 4-34, 4-56 (MULS) and 4-58 (MULU). The
# DIVS and DIVU entries carry both tables on one continuation folio; the MULS
# and MULU entries split them, the word table under the WORD instruction
# format on the first folio and the longword table alone on the continuation
# page. Read as RENDERED IMAGES:
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
# (13) MOVEM TAKES `(An)` AND `(d16,An)` AND NOTHING ELSE, AND THE `coverage`
# ROW ABOVE CANNOT SEE THAT. That row cites `-(An)`, which is dashed on the
# folios and outside the mask both before and after this narrowing, so it is
# GREEN over a mask four cells too wide. Every entry names exactly ONE illegal
# mode - the header's assertion (1) states that limit - so the cells this
# block names could not have been added to it, and a second row for `opMovem`
# would be dropped by the first-match lookup and red the reached-row count
# instead of asserting anything.
#
# THE FOUR CELLS THIS BLOCK EXISTS FOR are `(d8,An,Xi)`, `(xxx).L`,
# `(d16,PC)` and `(d8,PC,Xi)`. `eaLegalityFor`'s `opMovem` arm read
# `EaLegality(modes: eaControlModes, ea7: eaControl7NoAbsW)` - a set retired on
# 2026-08-11 and equal to today's `eaControl7 - {ea7AbsW}` - which admits all
# four, while the arm's own comment cited Table 3-14 as timing MOVEM under
# `(An)` and `(d16,An)` alone. The comment was right and the code was wrong.
#
# IT WAS NOT LATENT. Measured 2026-08-11 on the wide mask, before the
# narrowing: `movem.l %d0-%d1,0x400.l` - hand-built as `48f9 0003 0000 0400` -
# reached the executor and COMPLETED ITS STORE, leaving 0xAABBCCDD at 0x400
# and 0x11223344 at 0x404 with `fault` false. `tests/t_move.nim` carries that
# case at the execution level; this block carries the mask level.
#
# THE WIDE MASK REDS THREE `t_move` CASES AND NOT TWO. The sentence above
# accounts for the `(xxx).L` pair only - the `fault` assertion and the
# read-back of the two stored words - and an earlier revision of this record
# left it there. Measured 2026-08-11 by restoring
# `EaLegality(modes: eaControlModes, ea7: eaControl7 - {ea7AbsW})` on the
# `opMovem` arm, configuring FRESH, rebuilding and running through `ctest`:
# `t_move` prints
# `3 of 34 cases failed` - `movem.l to (xxx).L traps`, `movem.l to (xxx).L
# stores nothing before it traps` AND `movem.l to (d8,An,Xi) traps`, the last
# of which the pair above omits. This file prints
# `4 of <caseTotalMustMatchTranscripts> cases failed`, one per cell named
# below. Nothing else in the suite moves. RE-MEASURED 2026-08-11 with block
# (18) in place, because that block is itself a case and moved the
# denominator.
#
# THE DENOMINATOR IS A NAMED CONSTANT AND NOT A NUMBER. Neither copy of this
# transcript spells the figure: both name `caseTotalMustMatchTranscripts`, the
# constant exists once, and block (18) reds the run when it stops describing
# it.
#
# THE REST OF THE TRANSCRIPT IS PROSE IN TWO PLACES - the `4`, the `3 of 34`
# and every citation - because it is duplicated in the `opMovem` arm of
# `src/mcf5307/decode_types.nim`. A change to either copy has to be made in
# both, and nothing reds if only one is made.
#
# THE SOURCE IS THE CFPRM AND BOTH DIRECTIONS AGREE, read as RENDERED IMAGES
# (`pdftoppm -r 200`) and not from any OCR text:
#
#   folio 4-50, "Effective Address field ... for register-to-memory transfers,
#                use the following table for <ea>x"
#   folio 4-51, "Effective Address field (continued) - For memory-to-register
#                transfers, use the following table for <ea>y"
#
# EACH FOLIO PRINTS A MODE AND REGISTER VALUE FOR EXACTLY TWO ROWS - `(Ax)`
# 010 and `(d16,Ax)` 101 - AND A DASH FOR THE OTHER TEN: `Dx`, `Ax`, `(Ax)+`,
# `-(Ax)`, `(d8,Ax,Xi)`, `(xxx).W`, `(xxx).L`, `#<data>`, `(d16,PC)` and
# `(d8,PC,Xi)`. The two tables are the same shape cell for cell, so the mask
# does not depend on the direction and one mask can serve both.
#
# TWO INDEPENDENT TOOLCHAIN ORACLES AGREE, both run 2026-08-11:
#
#   - `m68k-elf-as -mcpu=5307` assembles `movem.l %d0-%d1,(%a0)` (`48d0 0003`)
#     and `movem.l %d0-%d1,(4,%a0)` (`48e8 0003 0004`) and the two
#     memory-to-register forms (`4cd0`, `4ce8`), and REJECTS all ten other
#     rows in both directions with "operands mismatch".
#   - `m68k-elf-objdump -m m68k:5307` decodes `48d0`, `48e8`, `4cd0` and
#     `4ce8` as `moveml` and decodes `48f0`, `48f8`, `48f9`, `48fa`, `48fb`
#     and their `4cxx` partners as `.short`.
#
# THE 68020 CROSS-CHECK SEPARATES EIGHT OF THOSE TEN AND NOT ALL TEN, AND AN
# EARLIER REVISION OF THIS BLOCK CLAIMED ALL TEN. Measured 2026-08-11, each
# encoding disassembled in a file of its own so no mis-decode could cascade:
# `-m m68k:68020` renders `48f0`, `48f8`, `48f9`, `4cf0`, `4cf8`, `4cf9`,
# `4cfa` and `4cfb` as a real `moveml`, and for those eight the ColdFire
# `.short` is therefore a statement about the PART rather than about the
# disassembler. `48fa` and `48fb` come back `.short` on the 68020 TOO. Both
# STORE to a PC-relative destination, which is illegal on every 68k, so those
# two encodings are not a MOVEM on any target and the differential oracle is
# silent about them. The asymmetry is the direction and nothing else: the
# memory-to-register partners `4cfa` and `4cfb` READ from PC-relative, which
# the 68020 permits, and they do discriminate.
#
# THE NARROWING IS NOT WEAKENED BY THAT CORRECTION. Eight encodings still
# discriminate, and the two folios and the pinned assembler each answer all
# ten on their own, so no cell in this block rests on the 68020 alone.
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
# (14) THE `eaLeaPeaTarget` GUARD. The mask is BELIEVED CORRECT and that is not
# why this block exists: an unguarded mask is a latent defect whatever its
# current value, and this project has now measured three of them.
#
# MEASURED 2026-08-11, BEFORE THIS BLOCK EXISTED: widening `eaLeaPeaTarget` to
# `modes: eaControlModes + {eaAnPost}` and `ea7: eaControl7 + {ea7Imm}` -
# admitting `(An)+` and `#<data>` - left the ENTIRE suite green.
# The `coverage` rows for `opLea` and `opPea` cite `Dn`, which stays outside
# the widened mask, so assertion (1) could not see it.
#
# THE SOURCE. `m68k-elf-as -mcpu=5307` REJECTS `lea (%a0)+,%a1`, `lea #4,%a1`,
# `pea (%a0)+` and `pea #4`, all four with "operands mismatch", and accepts
# every mode named in the positive control below. MCF5307 User's Manual Table
# 3-13 p.3-28 dashes the `lea | <ea>,Ax` row under `(An)+` and `#xxx`, and
# Table 3-14 p.3-29 dashes the `pea | <ea>` row under the same two columns.
#
# THE POSITIVE CONTROL INCLUDES `(xxx).W`, which is the cell `eaLeaPeaTarget`
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
# (15) THE `eaJumpTarget` CELL TABLE LIVES IN `tests/t_control.nim`, NOT HERE.
# A block of twenty-four cases mirroring block (14) for `opJmp` and `opJsr`
# stood here until 2026-08-11 and was DELETED as unable to detect anything.
# `t_control.nim`'s twelve-row `eaIsLegalFor(opJmp/opJsr, ...)` table
# enumerates the SAME twelve cells with the SAME verdicts through the SAME
# predicate, so the two computed the same twenty-four booleans and no mutation
# can separate them. Measured 2026-08-11, each mutation configured FRESH and
# run through `ctest`, deleted block against `t_control`:
#
#   eaJumpTarget + {eaAnPost}   `t_control` 4, deleted block 2
#   eaJumpTarget + {eaAn}       `t_control` 3, deleted block 2
#   eaControl7 - {ea7AbsW}      `t_control` 2, deleted block 2
#   eaControl7 + {ea7Imm}       `t_control` 2, deleted block 2
#
# IN NO DIRECTION DID THE DELETED BLOCK RED ALONE. RE-MEASURED AFTER THE
# DELETION: `t_control` reds 4, 3, 2 and 2 as above, unchanged.
#
# IN TWO OF THE FOUR - NOT THREE - `t_control` ALSO REDS AT THE EXECUTOR
# LEVEL, WHICH THE DELETED BLOCK NEVER REACHED. Measured 2026-08-11 by
# classifying every red `t_control` label as an `expectTrap` case or a
# `checkMask` row:
#
#   eaJumpTarget + {eaAnPost}   4 red: 2 executor, 2 `checkMask`
#   eaJumpTarget + {eaAn}       3 red: 1 executor, 2 `checkMask`
#   eaControl7 - {ea7AbsW}      2 red: 0 executor, both `checkMask`
#   eaControl7 + {ea7Imm}       2 red: 0 executor, both `checkMask`
#
# IN THE TWO `eaControl7` DIRECTIONS EVERY `t_control` RED IS A MASK ROW, AND
# THE TWO DIRECTIONS DIFFER IN WHAT IS LEFT ELSEWHERE. Under
# `- {ea7AbsW}` the executor-level evidence lives in other files - `t_move`'s
# five `lea`/`pea (xxx).W` cases and the `jmp_absolute_short` conformance case
# all red, eleven cases in all. Under `+ {ea7Imm}` NOTHING executes: the five
# reds are this file's two block-(14) cases, block (17)'s `eaControl7`
# equality and `t_control`'s two `#imm is illegal` rows, every one of them a
# mask or value assertion. The CFPRM provenance the block carried is on the
# `eaControl7` declaration in `src/mcf5307/ea.nim`, beside the value it cites.
#
# WHY BLOCK (14) SURVIVES THE SAME ARGUMENT. LEA and PEA have no cell table
# anywhere else, which is NOT the same as their being untested: the baseline
# `ctest -V` transcript carries THIRTY-TWO case labels naming LEA or PEA,
# measured 2026-08-11 - 27 in this file (this block's eighteen, the `coverage`
# rows' four assertions for each of `opLea` and `opPea`, and block (6)'s
# `decodes LEA (A0),A0`) and 5 in `t_move`, which EXECUTES `lea (xxx).W` and
# `pea (xxx).W` and reds all five under `eaControl7 - {ea7AbsW}`. What block
# (14) holds alone is the two cells no other case names.
#
# THE MUTATION THAT SHOWS IT IS `eaLeaPeaTarget` WIDENED ON ITS OWN to
# `ea7: eaControl7 + {ea7Imm}`: 2 red in the ENTIRE suite, both this block's
# `the mask REJECTS #<data>` cases, and every other case green. That is the
# criterion the deletion above rests on, met in block (14)'s favour.
#
# WIDENING `eaControl7` ITSELF IS THE WRONG WITNESS FOR THAT CLAIM, because
# the widening moves four operations at once: it reds FIVE - this block's two,
# block (17)'s `eaControl7` equality and `t_control`'s `jmp #imm is illegal`
# and `jsr #imm is illegal` - so under it block (14) does not red alone.
# Block (15) never red alone in any direction.

# ---------------------------------------------------------------------------
# (16) THE ADDQ AND SUBQ MASK, ENUMERATED CELL BY CELL. THIS BLOCK CLOSES A
# MEASURED BLIND SPOT AND THE DIRECTION IS NARROWING, which is the direction
# this file has repeatedly been weakest in.
#
# MEASURED 2026-08-11, EACH MUTATION RUN THROUGH THE WHOLE SUITE:
#
#   eaAlterable7 - {ea7AbsW}   3 red, AND ALL THREE ARE CASES ADDED WITH THIS
#                              BLOCK: the two `the mask accepts (xxx).W` rows
#                              below and block (17)'s `eaAlterable7 is the two
#                              absolute forms and nothing else`. BEFORE they
#                              existed this narrowing left the ENTIRE SUITE
#                              GREEN - ADDQ and SUBQ would have trapped on
#                              `addq.l #1,0x1234.w`, a form the pinned
#                              assembler emits, and nothing would have said so.
#   eaAlterable7 + {ea7PCDisp} 7 red, of which `t_alu` 2 were already there.
#                              The WIDENING direction was already guarded.
#
# THAT ASYMMETRY IS THE POINT. The `coverage` rows for these two declare
# `discriminating: false` because their cited illegal mode `(d16,PC)` is
# refused by `eaResolve` as well - an argument about assertion (4) - and
# assertion (1) does catch a widening onto that one cell. Neither reaches a
# narrowing, because every `coverage` row names an ILLEGAL mode and a narrowing
# removes a LEGAL one.
#
# THE MODE SET IS NOT WHAT THIS BLOCK CLOSES, and saying so would overstate it.
#
# "THE MODE SET" HAS TWO READINGS HERE AND THEY GIVE DIFFERENT NUMBERS, because
# ADDQ and SUBQ NO LONGER HAVE A MODE SET OF THEIR OWN: their arm names
# `eaAllModes`, which ELEVEN operations share. Measured
# 2026-08-11, each mutation configured FRESH and run through `ctest`:
#
#   the ADDQ/SUBQ ARM ALONE - `eaAllModes - {eaAn}` written at that one site:
#     4 red. `t_alu` 2 (`addq.l #1,a1 wraps and leaves the condition codes
#     alone`, `the ADDQ mask admits An`) and this block 2.
#   the SHARED DECLARATION - `eaAn` deleted from `eaAllModes` in `ea.nim`:
#     11 red. `t_alu` 3, `t_control` 3, this block 2 and the conformance
#     corpus 3. Those eleven are the blast radius of the OTHER NINE READERS
#     and not better coverage of ADDQ and SUBQ; `ea.nim` names all eleven.
#
# EITHER READING LEAVES THE CONCLUSION STANDING. `t_alu` reds under both, so
# the mode half had executor-level coverage already and it is the mode-7 half
# that had none in the narrowing direction.
#
# THE MODE SET IS EVERY MODE AND THE RESTRICTION LIVES ENTIRELY IN THE MODE-7
# HALF. That is the whole content of the naming defect this block accompanies:
# a set named for the manual's ALTERABLE class that excludes no mode is not
# restricting anything, and only `eaAlterable7` is.
#
# THE ASSEMBLER TRANSCRIPT BEHIND THESE TWELVE CELLS, AND THE CFPRM
# `Alterable` COLUMN THAT DISAGREES WITH IT ON TWO OF THEM, ARE RECORDED ONCE -
# on the `eaAlterable7` declaration in `src/mcf5307/ea.nim`. That is the site
# whose VALUE the evidence establishes; this block only pins it. The
# disagreement is NOT settled there and is not settled here: a future reader
# who narrows the mask to follow the column reds the two `(xxx).W` and
# `(xxx).L` rows below, and that is the intended conversation.

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
# (17) THE MODE-7 SETS, HELD AGAINST THEIR LITERAL MEMBERSHIP. Every assertion
# above reaches a set through `eaLegalityFor`, so a RENAME is invisible to all
# of them and so is a rename that quietly moved a member. These cases name the
# members, so a rename cannot smuggle a value change past the suite.
#
# THE STATED LIMIT. This block pins the VALUE of each set and says NOTHING
# about whether the NAME describes it. A set renamed truthfully and a set
# renamed to a second lie are indistinguishable here; the manual citations on
# the declarations are what carry that, and no run can check them.
#
# WHY THE FULL VALID SET IS NAMED RATHER THAN THE THREE RESERVED ENCODINGS.
# `EA7` has eight members and only five are encodings this part defines, so
# "every valid sub-variant" is a five-member set and the reserved trio is its
# complement. Asserting the complement instead would pass for a set that had
# also lost a valid member.
#
# THE ADMISSION RULE FOR THIS BLOCK: ONE LITERAL-EQUALITY CASE PER SET, AND
# NOTHING DERIVED FROM THEM. A case whose condition is ENTAILED by the equality
# cases cannot be the sole detector of anything, because two conditions that
# cannot disagree cannot red apart. Three such cases have been written here and
# all three are gone; the rule is stated so a fourth is not.
#
# WHAT THE RULE EXCLUDED, AND WHY EACH EXCLUSION IS SOUND:
#
#   `not ({ea7Unused5, ea7Invalid, ea7Unused7} <= eaValid7)` - entailed by the
#   `eaValid7` equality, since a set equal to the five valid members is
#   disjoint from the three reserved ones. It was also the wrong SHAPE: `not
#   (trio <= s)` is false only when ALL THREE are present, so alone it would
#   have tolerated one or two being admitted. The property wanted is
#   DISJOINTNESS, not "not a superset".
#
#   `eaControl7 == eaValid7 - {ea7Imm}` - entailed by the two equality cases
#   above it. If `eaValid7 == {the five}` and `eaControl7 == {the four}` both
#   hold, then `eaValid7 - {ea7Imm}` IS `{the four}`, so the third condition
#   cannot fail while its two premises pass.
#
# MEASURED 2026-08-11, EACH MUTATION CONFIGURED FRESH AND RUN THROUGH `ctest`,
# WITH THE ENTAILED `eaControl7 == eaValid7 - {ea7Imm}` CASE STILL PRESENT. In
# all three directions it moved WITH a premise and never alone:
#
#   eaValid7 + {ea7Invalid}   the `eaValid7` equality reds, and the entailed
#                             case reds beside it.
#   eaControl7 - {ea7AbsW}    the `eaControl7` equality reds, and the entailed
#                             case reds beside it.
#   eaControl7 + {ea7Imm}     the `eaControl7` equality reds, and the entailed
#                             case reds beside it.
#
# NO CASE TOTAL IS QUOTED FOR THOSE THREE RUNS, because they were measured on a
# file state that no longer exists and a total would not reproduce. What
# reproduces is the CO-MOVEMENT, which is the whole of the claim.
#
# THE MUTATION THAT WOULD SEPARATE THEM DOES NOT EXIST. Any mutation reaching
# the entailed condition falsifies one of its premises first, so deleting it
# removed a case that could never fire on its own. Re-measured after the
# deletion: all three mutations still red an equality case, and nothing else in
# the suite moved that had not moved before.

block:
  check(eaValid7 == {ea7AbsW, ea7AbsL, ea7PCDisp, ea7PCIndex, ea7Imm},
    "eaValid7 is every VALID mode-7 sub-variant and no reserved one" &
    " (CFPRM Rev. 3 Table 2-3 folio 2-10 prints exactly these five rows" &
    " under mode field 111)")
  check(eaControl7 == {ea7AbsW, ea7AbsL, ea7PCDisp, ea7PCIndex},
    "eaControl7 is the FULL control mode-7 class, `(xxx).W` included" &
    " (CFPRM Rev. 3 Table 2-3 folio 2-10, Control column;" &
    " `#<data>` is the one valid mode-7 row it excludes)")
  check(eaAlterable7 == {ea7AbsW, ea7AbsL},
    "eaAlterable7 is the two absolute forms and nothing else")

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


# (18) THIS FILE'S OWN CASE TOTAL, HELD AGAINST THE ONE FIGURE THE TRANSCRIPTS
# QUOTE. Block (13) above and the `opMovem` arm of `decode_types.nim` each
# transcribe a mutation run as "N of <total> cases failed", where that total is
# what the summary line at the foot of this file prints. The denominator moved
# 367 -> 420 -> 419 over three consecutive repairs; on each one a single copy of
# the transcript was updated and the other was left standing, and on the last
# the very repair that corrected the figure invalidated it again by deleting a
# case. Nothing went red, because the denominator was PROSE IN TWO FILES.
#
# THAT TALLY IS CLOSED AT THE POINT THIS BLOCK LANDED AND IS NOT EXTENDED. The
# constant has moved since and will move again; a list that grows by one entry
# per repair is the defect this block exists to end, not a record of it.
#
# THE FIGURE NOW EXISTS ONCE, AS `caseTotalMustMatchTranscripts`, AND BOTH
# TRANSCRIPTS NAME THE CONSTANT RATHER THAN SPELLING A NUMBER. This case is
# what keeps the constant true: it holds the live count of every case this run
# emitted against it, so a block added to or removed from this file is RED here
# until the constant moves - and moving the constant moves both transcripts
# with it, because neither of them carries a second copy to forget.
#
# IT IS A RUN-TIME CASE AND NOT THE `static: doAssert` ASSERTION (9) USES, AND
# THAT IS FORCED RATHER THAN PREFERRED. `passCount` and `failures` are
# accumulated by the enumeration over `Operation` and over the `coverage` seq,
# and both are run-time values. Measured 2026-08-11: appending
# `static: doAssert failures.len + passCount == <any total>` to this file fails
# to COMPILE, with `Error: cannot evaluate at compile time: failures` - the
# right-hand side is not what it objects to - and the
# registered test reports that as a driver error rather than as a case. The
# price of the run-time form is that it fires only when the suite runs; the
# compile-time form is not an option that exists here.
#
# THE `+ 1` IS THIS CASE ITSELF. `checkDetail` below is called exactly once in
# this block and increments one of the two counters whichever way it goes, so
# the figure the summary line goes on to print is one greater than the one read
# here. The constant is the SUMMARY LINE's figure, because that is the figure
# the two transcripts quote.
#
# WHAT IT DOES NOT CATCH, STATED SO THE CONSTANT IS NOT READ AS MORE THAN A
# TOTAL. It pins the COUNT and says nothing about WHICH cases ran: one block
# deleted and another of the same size added in a single change passes. And it
# says nothing about the other figures those transcripts carry - the `4` red
# cases under the wide MOVEM mask, and `t_move`'s own `3 of 34` - which are a
# mutation's blast radius and another file's total, neither of them this run's
# to count.

const caseTotalMustMatchTranscripts = 397
  ## THE TOTAL THE SUMMARY LINE PRINTS, WRITTEN DOWN EXACTLY ONCE IN THIS
  ## REPOSITORY. Both mutation transcripts that need the denominator name this
  ## constant instead of copying its value, so there is one figure to move and
  ## the case below is what refuses to let it be moved wrongly. Measured
  ## through `ctest` on 2026-08-11.

block:
  let totalBeforeThisCase = failures.len + passCount
  checkDetail(totalBeforeThisCase + 1 == caseTotalMustMatchTranscripts,
    "this run emits the case total `caseTotalMustMatchTranscripts` records, " &
    "which is the denominator both mutation transcripts quote - block (13) " &
    "here and the `opMovem` arm of `decode_types.nim`",
    "the constant records " & $caseTotalMustMatchTranscripts &
    " and this run emitted " & $(totalBeforeThisCase + 1) &
    "; a block was added to or removed from this file, so move the constant " &
    "and re-read both transcripts")

# ---------------------------------------------------------------------------
# THE SUMMARY LINE CARRIES THE ATTRIBUTION FIGURE, BECAUSE A BARE COUNT WOULD
# LET THE READER CONCLUDE THAT EVERY OPERATION IS GUARD-COVERED. The attribution
# figure is what says otherwise.
#
# NO COUNT IS WRITTEN DOWN IN THIS COMMENT OR IN THE LINE ITSELF. Every figure
# the line prints is counted by the run that prints it.
#
# WHAT THIS DOES NOT REACH, STATED SO IT IS NOT MISTAKEN FOR A FULL REPAIR. A
# plain `ctest` prints `t_ea_masks ... Passed` and captures this program's
# stdout, so a CI summary shows the NAME and the STATUS and nothing below.
# Nothing this program prints can change that: the registered name and the
# driver both live in `tests/tests_cpu.cmake`, which section 7.4.2 gives to
# CPU-26. The line below serves the reader of `-V`, of a failing run, or of the
# saved log - which is the reader who sees a count at all.
#
# THE DRIVER'S PASS PATTERN STILL MATCHES. It searches for
# `t_ea_masks: <N> cases passed` and is not anchored at the end, so text
# APPENDED after that phrase is safe and text inserted inside it is not.

proc attribution(): string =
  ## BOTH FIGURES ARE COUNTED BY THE RUN, AND THAT IS STILL NOT ENOUGH TO MAKE
  ## THE LINE A MEASUREMENT. `discriminating` is a HAND-DECLARED field; the sum
  ## over it is live, the evidence under it is not. The guard-deletion runs
  ## that established the values are dated in the plan section and do not travel
  ## with this line, so a forty-eighth entry declaring `discriminating: true`
  ## and measuring nothing would raise the numerator with exactly the authority
  ## of a measured one. The line therefore says DECLARE, and carries the date of
  ## the evidence, so that a reader of a bare log can see the gap.
  ##
  ## The denominator is the DOMAIN and not the covered set, so an operation
  ## that joined the domain without an entry enlarges it. Under the old
  ## denominator that operation shrank the figure while going red.
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

if failures.len > 0:
  echo ""
  echo "t_ea_masks: ", failures.len, " of ", failures.len + passCount,
      " cases failed", attribution()
  quit(1)
else:
  echo ""
  echo "t_ea_masks: ", passCount, " cases passed", attribution()
