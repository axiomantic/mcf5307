## `t_ea_masks` - the decoder and effective-address legality masks. Task
## CPU-6 creates this file. Design section 6.1.
##
## THE COVERAGE DOMAIN IS THE LEGALITY TABLE ITSELF, AND THAT IS THE WHOLE
## POINT OF THE FILE. An earlier revision carried an explicit
## `seq[(Operation, string, EA, EA)]` with FOUR entries - MOVE, ADDQ, SUBQ and
## LEA - while `eaLegalityFor` named FORTY-SEVEN operations across fifteen
## `of` arms. The `Check:` line of CPU-6 claims a trap for at least one
## illegal mode for EACH implemented opcode, and 43 operations carried a mask
## that no case reached.
##
## THE MECHANISM OF THE MISS IS WORTH MORE THAN THE ARITHMETIC. When `SWAP`
## was implemented, adding `opSwap` to `eaLegalityFor` did not turn this file
## red, because a hand-maintained list makes a new opcode SILENTLY UNCOVERED
## rather than LOUDLY MISSING. The driver below iterates `Operation` and
## requires a coverage entry for every operation whose mask is non-empty, so
## an operation added to the table with no entry makes the run RED in the wave
## that added it. The reverse direction is checked too: an entry for an
## operation whose mask has gone empty is a stale entry and is also RED.
## Measurements 4 and 5 below are the mutations behind those two sentences.
##
## THE SKIP RULE, STATED ONCE. An operation is outside the domain WHEN AND
## ONLY WHEN `eaLegalityFor` returns an EMPTY mask. That is the same test
## `eaIsLegalFor` already makes, and `decode_types.nim:534-538` says why a
## second list of the same operations drifts.
##
## NOTHING HERE IS SKIPPED FOR BEING UNREACHABLE FROM THE DECODER, AND THAT
## RESTRICTION IS LOAD-BEARING RATHER THAN DECORATIVE. "No arm produces it" is
## the sentence `cpu.nim:177` carried while `decode.nim`'s PEA mask was eating
## all eight `SWAP` encodings, and Gate 4.4's 65,536-word sweep CONFIRMED that
## sentence - true for the wrong reason. A skip justified by reachability
## would have skipped `SWAP`, which is the defect this file exists to catch,
## so reachability is not a skip criterion here at any strength.
##
## THE ILLEGAL MODE OF EACH ENTRY IS SOURCED FROM THE MANUAL AND NEVER FROM
## `eaLegalityFor`, AND THAT IS WHAT KEEPS THE FILE FROM PROVING NOTHING. A
## driver that asked `eaLegalityFor` which mode is outside the mask and then
## asserted `eaIsLegalFor` rejects it would be asserting the mask against
## itself: it would pass against ANY mask, including a wrong one, and a
## widened mask would move the asserted mode with it. Every `illegal` field
## below carries its own citation, so a mask that widens to admit THAT mode
## turns the entry RED instead of moving it - measurement 6 below. A widening
## that admits some OTHER mode is invisible here, and assertion (1) below
## carries that limit and the measurement for it.
##
## THE WORD "EVERY" IN THAT PARAGRAPH IS ASSERTION (11) AND NOT A PROMISE.
## `why` is required by `cov`, so a row cannot omit a citation but can pass one
## citing nothing; (11) requires each to name a manual table. Measured
## 2026-08-11: `opNot`'s citation replaced with `"a data register only"` gives
## `exit=8`, `1 of 237 cases failed`, `got these do not: @["opNot"]`. EVERY
## `exit=` IN THIS HEADER IS SCOPED `ctest -R t_ea_masks`, 0 GREEN AND 8 RED; a
## FULL-suite run exits 8 as its BASELINE instead, `abi_smoke` Not Run.
##
## FOUR ASSERTIONS PER OPERATION, AND EACH ONE CAN FAIL.
##
##   (1) THE PREDICATE REJECTS THE ILLEGAL MODE. This is the assertion that
##       catches a mask WIDENED TO ADMIT THE MODE THE ENTRY CITES, and it
##       catches that for every operation, the ones assertion (4) cannot
##       attribute included. Measurement 6 below.
##
##       IT CATCHES NO OTHER WIDENING, AND AN EARLIER WORDING HERE SAID
##       "catches a WIDENED MASK" WITH NO SUCH QUALIFIER. Each entry names
##       exactly ONE illegal mode, so a mask that widens somewhere else passes
##       (1) unchanged. MEASURED: the same eight-operation arm measurement 6
##       uses, widened instead from `{eaDn}` to `{eaDn, eaAnPost}` - `(An)+`,
##       a mode NO entry cites - gave `237 cases passed` on 2026-08-11.
##       This is the exact mirror of the narrowing blindness recorded further
##       down, and it has the same single cause: one cited mode per entry.
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
##       of the instruction first is not a refusal. THE ADDRESS HALF WAS A
##       PROMISE UNTIL 2026-08-11: all seven held `ramBase`, so `opLea`
##       refusing after copying A0 into A1 and A2 into A3 was GREEN at `237
##       cases passed`, and is RED at `registersPristine=false` now that
##       `aRegSeed` seeds them distinctly.
##
## TWO MORE RUN FOR THE TABLE 3-13 ENTRIES ALONE, one per axis of the citation,
## and each holds a DECLARED value against an INDEPENDENT recording of the same
## fact rather than against the value itself. The numbering skips (5) and (6),
## which are the two older assertions described further down; the numbers here
## are the ones the code uses, and an earlier revision of this paragraph called
## the page assertion "a fifth assertion" while the code called it (7).
##
##   (7) THE PAGE. Derived from the operation's mnemonic through the table's own
##       row ordering and compared against the page the entry declared. The
##       block defining `Table313Page` below carries the argument.
##
##   (8) THE `#xxx` COLUMN. Derived by running the entry twice with different
##       immediates and comparing the two outcomes, which is the operational
##       content of that column. `table313ImmOf` carries the argument, the two
##       measured directions, and the limit. This axis was DECLARED AND
##       UNCHECKED until 2026-08-11.
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
##       mnemonic derivation behind (7) rests on. MEASURED AT ITS SUBJECT
##       2026-08-11: `opTas` renamed `zzTas` in `decode_types.nim` gives
##       `1 of 237 cases failed`, `got these are not: @["zzTas"]`.
##
##  (11) EVERY `coverage` ROW CITES A MANUAL TABLE for its `illegal` mode, which
##       is the "every" the anti-tautology paragraph above rests on.
##
## WHAT THAT ASSERTION CATCHES IS A MIS-DECLARED PAGE HELD AGAINST A FIXED
## BREAK, AND AN EARLIER WORDING HERE CLAIMED MORE. It said "a wrong page goes
## RED instead of being argued about" without naming what the page is held
## AGAINST. It is held against `table313LastRowOn328`, and the two directions
## measure differently.
##
##   - A LONE MIS-DECLARATION IS RED. `opOri`, whose row is on 3-29, declared
##     `p313Start` with the constant left untouched: 2026-08-11, `ctest
##     exit=8`, `1 of 237 cases failed`, `FAILED opOri: its Table 3-13 row is
##     on the page the entry cites`.
##   - A CO-EDIT OF THE CONSTANT AND THE DECLARATIONS WAS GREEN, AND DOES NOT
##     COMPILE TODAY. `table313LastRowOn328` set to `"cmpi"` and `opEori`,
##     `opLsl` and `opLsr` moved to `p313Cont` IN THE SAME EDIT was measured at
##     `ctest exit=0`, `223 cases passed`, printing `PASSED opEori: ... (Table
##     3-13 p.3-29: ...)` - a false page, green. Re-run 2026-08-11 with (9) a
##     `static: doAssert`, the SAME four-part edit gives `ctest exit=8` and
##     `t_ea_masks ***Failed` with NO case count: the compile aborts with
##     `Error: unhandled exception: ... this file declares "cmpi" and that file
##     records "mulu" [AssertionDefect]`. Assertion (7)'s twelve cases never
##     run, so the blindness the earlier measurement found is refused earlier.
##
## THE BREAK CONSTANT IS CHECKED BY ASSERTION (9), AND AN EARLIER REVISION OF
## THIS PARAGRAPH SAID NOTHING IN THIS FILE COULD CHECK IT. That argument held
## that the constant is the second source, so holding it against the
## declarations it validates would be a tautology. The argument is sound and
## assertion (9) does not do that: it holds the constant against a THIRD
## record, `decode_types.nim`'s own `table313LastRowOnPage328`.
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
## THE CRITERION IS THE COMPLEMENT OF THE MASK AND NOT A ROSTER OF OPCODE
## NAMES, so a twelfth operation is recognized by reading `ea.nim` rather than
## by remembering this paragraph. Two masks meet it, for two DIFFERENT reasons.
##
##   - MOVE, MOVEA, ADD, SUB, ADDA, SUBA, TST, CMP and CMPA carry
##     `eaDataModes`/`eaData7`, which admits every addressing mode Table 3-5
##     p.3-21 prints. The only encodings outside it are the RESERVED mode-7
##     ones, and `machine.nim`'s `eaAddr` and `eaRead` fault on those
##     independently of any mask.
##
##   - ADDQ and SUBQ carry `eaAlterableModes`/`eaAlterable7`, whose mode-7
##     half is `{ea7AbsW, ea7AbsL}`. `machine.nim`'s `eaResolve` accepts
##     EXACTLY those two mode-7 encodings as a destination and faults on every
##     other one, so the complement of this mask and the set `eaResolve`
##     refuses ARE THE SAME SET. `(d16,PC)` is therefore not an unlucky pick:
##     NO choice of illegal operand makes these two entries discriminating,
##     and one chosen to look stronger would only hide that.
##
## READ EVERY NUMBER IN THIS HEADER AS DATED TRANSCRIPT EVIDENCE AND NEVER AS A
## LIVE COUNT, AND WRITE NEW ONES ON THE SAME TERMS. A transcript that has gone
## stale is still a true record of the run that produced it - which is the
## opposite of a stale count, and the reason the counters in the summary line
## below are computed rather than written down. This is put as a RULE for
## whoever edits next; the revision that put it as a FACT about the file was one
## more claim ranging over every figure here with nothing to check it.
##
## MEASURED 2026-08-10 BY DELETING THE GUARDS AND RUNNING, SO THE 36 IS A
## MEASUREMENT AND NOT AN ESTIMATE. Three deletions, each with the masks left
## untouched, and each confirmed to have reached the compiled artifact by
## reading the generated C in `build/tests/t_ea_masks_nimcache/` - the test
## compiles `src/` into ITS OWN nimcache, and `build/nimcache/` is the
## library's and governs the conformance and ABI targets alone.
##
##   1. The `eaIsLegalFor` guard deleted from the `opMove, opMovea` arm of
##      `moveFamily`: THIS FILE GREEN at 209 of 209, and the whole fifteen-test
##      suite green with only the known `abi_smoke` Not Run.
##   2. The guard deleted from `execAddSubQ`: the same result, 209 of 209 and
##      the suite green. That is what moved ADDQ and SUBQ to
##      `discriminating: false`.
##   3. TWENTY-FIVE OF THE TWENTY-SEVEN guards in the four family modules
##      deleted at once - the 24 `eaIsLegalFor` AND the bit operations'
##      `isEaLegal(mask, d.ea)`: 36 of the 47 RED and exactly the eleven above
##      green, the guards being per-operation and independent. RE-RUN
##      2026-08-11, FIRST BY ANYONE: `36 of 237 cases failed`, all on (4).
##
##      THIS LINE SAID "EVERY guard", AND IT WAS 25 OF 27. `alu.nim:135` and
##      `logic.nim:304` are the other two, both
##      `isEaLegal(eaMemoryAlterable, d.ea)`, and both sit on the `dirToEa`
##      branch of `execAddSub` and `execAndOr` - the `Dn op <ea> -> <ea>`
##      direction, whose mask is deliberately not the per-operation one.
##      Every row of `coverage` leaves `dirToEa` at its default `false`, so
##      neither guard is on a path this file drives.
##
##      THE 36 IS UNAFFECTED, AND THAT IS MEASURED RATHER THAN ARGUED FROM
##      THE PARAGRAPH ABOVE. Those TWO guards deleted and nothing else:
##      2026-08-11, `237 cases passed`, no entry moved. Only the word
##      "every" was wrong; every figure the measurement produced stands.
##
## THE FIRST ATTEMPT AT MEASUREMENT 3 REPORTED FIFTEEN, AND THE FOUR EXTRA WERE
## AN ARTEFACT OF THE MUTATION RATHER THAN A PROPERTY OF THE CODE. It deleted
## the guards spelled `eaIsLegalFor` and nothing else, so BTST, BCHG, BCLR and
## BSET kept theirs - `logic.nim` spells that one `isEaLegal(mask, d.ea)` over
## a mask it selects, because the STATIC form reads the narrower `eaBitStatic`.
## The four stayed green because they were never mutated, and a count taken
## there would have moved four entries to `discriminating: false` wrongly.
## Anyone repeating this checks that the generated C for EVERY family module
## lost the call, not the deletion command: 2026-08-11 `exit=8`, `eaIsLegalFor`
## 6/11/6/5 to 0, both survivors intact, red set disjoint from the eleven.
##
## THE ASSERTIONS ABOUT THE ENUMERATION AND THE TABLE WERE MEASURED THE SAME
## WAY AND ON THE SAME DATE, BECAUSE A CLAIM THAT A CHECK CATCHES SOMETHING IS
## WORTH EXACTLY THE MUTATION BEHIND IT AND NOTHING MORE. Each was applied
## ALONE and reverted.
##
## A SENTENCE CLAIMING THAT EVERY CLAIM IN THIS HEADER CITES ITS MUTATION USED
## TO STAND HERE, AND IT IS DELETED RATHER THAN CORRECTED. It asserted a
## property over ALL of this file's claims while nothing checked it, so it went
## stale every time a claim was added - three times in four review rounds, each
## repair writing the next round's defect. The class of sentence is the defect,
## not any particular wording of it: a claim about a claim is not a claim about
## the code, and no care in phrasing makes one maintainable by hand. Where such
## a sentence could be replaced by a check it has been - assertions (9), (10)
## and (11) below are three of those replacements - and where it could not, it
## is gone.
##
##   4. A COVERAGE ROW DELETED - `opSwap`'s: RED, `FAILED opSwap: carries a
##      NON-EMPTY legality mask and NO coverage entry reaches it`. That is the
##      FORWARD direction of the enumeration, and the defect that motivated
##      the whole file.
##   5. A ROW ADDED FOR AN OPERATION WHOSE MASK IS EMPTY - `opNop`'s: RED,
##      `FAILED opNop: carries an EMPTY legality mask and no stale coverage
##      entry`, with the rows-reached check red beside it. That is the REVERSE
##      direction.
##   6. A MASK WIDENED to admit the mode the entries cite as illegal -
##      `{eaDn}` to `{eaDn, eaAnInd}` on the `opAddi, opSubi, opNeg, opNegx,
##      opExt, opExtb, opAddx, opSubx` arm: RED for all EIGHT operations, on
##      assertion (1) AND on assertion (4), sixteen cases in all. That is the
##      measurement behind assertion (1)'s qualified claim above, and the only
##      one of measurements 4 to 8 that touches a mask rather than the table.
##   7. A SECOND ROW for an operation that already has one - `opSwap`'s,
##      duplicated: RED, re-measured 2026-08-11 as `48 rows written and 47
##      reached; these ran nothing: @["42:opSwap"]`. The duplicate runs no
##      assertion of its own, which is why the two counts are compared.
##   8. `cov313` STOPPED SETTING `page313`: RED, and the printed total fell by
##      EXACTLY TWELVE. That is the twelve silently deleted assertions the check
##      exists to refuse. RE-RUN 2026-08-11, because assertion (8) added a third
##      figure to that check's message and the 2026-08-10 wording of it can no
##      longer be printed: `ctest exit=8`, `1 of 225 cases failed`, `12 rows
##      cite Table 3-13, 0 carry a page and 12 carry a `#xxx` column`.
##
##  8b. THE SAME EQUALITY READ THE OTHER WAY - a row carrying a page whose
##      citation names a different table - which measurement 8 does not reach
##      and which was disclosed as unmutated until now. `cov313` made to hand
##      `opCmpi` the Table 3-12 citation while still setting its page: `ctest
##      exit=8`, `1 of 237 cases failed`, `11 rows cite Table 3-13, 12 carry a
##      page and 12 carry a `#xxx` column`. Both directions are now measured.
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
## above spans the repository while its evidence does not. Measurements 1 and
## 2 ran the WHOLE fifteen-test suite and record it green, which covers MOVE,
## MOVEA, ADDQ and SUBQ. Measurement 3 records only THIS file's red-and-green
## split, so for ADD, SUB, ADDA, SUBA, TST, CMP and CMPA the claim rests on
## this file alone: no suite-wide run with those seven guards deleted is
## recorded, and none was made. UNCHECKED, and closing it is one deletion and
## one full run rather than an argument.
##
## A NARROWED MASK IS INVISIBLE TO THIS FILE FOR EVERY ENTRY AND NOT FOR THE
## ELEVEN, AND AN EARLIER WORDING OF THE PARAGRAPH ABOVE FILED NARROWING UNDER
## THE ELEVEN AND SO LET A READER TAKE THE REST AS COVERED AGAINST IT. Each
## entry names exactly ONE legal mode, so a mask NARROWED to that single mode
## passes all four assertions unchanged: (1) still rejects the cited illegal
## mode, (2) still accepts the one legal mode the entry names, and (3) and (4)
## drive those same two operands and nothing else. Most entries name `Dn`, so
## ONE narrowing to `{eaDn}` is invisible here for all of those at once; the
## control-addressing entries name `(An)`, and a narrowing to `{eaAnInd}` is
## invisible for those. Nothing about the eleven makes narrowing worse for
## them than for the rest - the discriminating flag is about assertion (4)'s
## ATTRIBUTION and says nothing at all about narrowing. The paragraph after
## next measures ONE such narrowing rather than leaving the whole of this
## argued.
##
## THE MITIGATION IS PARTIAL AND LIVES OUTSIDE THIS FILE. `t_move`, `t_alu`,
## `t_logic`, `t_control` and the conformance corpus assert POSITIVE behaviour
## on legal modes, so a narrowing that removes a mode one of THOSE exercises
## turns them red. A narrowing that removes a mode NOTHING in the repository
## exercises goes unnoticed everywhere, this file included.
##
## ONE NARROWING HAS NOW BEEN MEASURED, AND IT NAMES A DIFFERENT TEST THAN THE
## SENTENCE ABOVE LEADS WITH. `opMove` and `opMovea` narrowed from
## `eaDataModes`/`eaData7` to `{eaDn}`/`{}`, whole suite built with `-- -k`:
##
##   - THIS FILE GREEN, re-measured 2026-08-11 at `237 cases passed` - the
##     invisibility argued above, confirmed rather than asserted.
##   - `t_move` GREEN. It drives MOVE register-to-register only - `1200`,
##     `3200`, `2200` - so it never exercises a memory source, and the
##     narrowing is invisible there too.
##   - THE CONFORMANCE CORPUS RED: `mcf5307_conformance_move` at `23 cases, 9
##     failed`, and `mcf5307_conformance_all` with it.
##
## SO THE MITIGATION IS REAL AND IT IS THE CORPUS, NOT THE FAMILY TEST THIS
## PARAGRAPH NAMES FIRST. That ordering was the same "accurate and incomplete"
## shape the page citation had: `t_move` does assert positive MOVE behaviour,
## and it asserts it on the one mode a narrowing to `{eaDn}` keeps.
##
## ONE NARROWING OF ONE MASK IS NOT THE GENERAL CASE, AND NOTHING HERE CLAIMS
## IT IS. The other masks were NOT mutated. For them the first paragraph
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
## nothing. Measurement 7 below.
##
## THE ONE A7. There is no supervisor and user stack split on ISA_A; the
## context holds the single `sp`.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

## THE IMPORTS NAME THE LAYER EACH SYMBOL COMES FROM. `decode` no longer
## re-exports `decode_types`, so each module below supplies exactly the names
## the test takes from it: `cpu` the lifecycle ABI, `decode` the decoder
## (`decodeWord`), `decode_types` the shared types and the legality table,
## `ea` the effective-address decoding, and the four instruction-group modules
## their family entry points, which is the layer assertions (3) and (4) drive.

import std/[options, strutils]
import mcf5307/cpu
import mcf5307/decode
import mcf5307/decode_types
import mcf5307/ea
import mcf5307/move
import mcf5307/alu
import mcf5307/logic
import mcf5307/control

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
  ## The date of the guard-deletion measurement the header records. The summary
  ## line carries it so the reader of a bare log can tell how old the evidence
  ## behind `discriminating` is without opening this file.

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
    ## What `mcf5307_reset` leaves in the status register - `cpu.nim:104`, from
    ## the G2 reset vector's `move.w #$2700,%sr`. `runFamily` seeds every other
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
## THIS SHAPE IS A REPAIR OF A DEFECT THIS CODEBASE HAD ALREADY FIXED ONCE.
## `decode_types.nim` records it - "An earlier revision of this line put all
## three on 3-28" - and collapsing twelve citations into ONE SHARED CONSTANT
## re-created it, because one name cannot hold two pages and the wrong page is
## the silent outcome. Two constants would not close it either: a thirteenth
## entry would pick one of them, and picking the wrong one is exactly as
## silent as before.
##
## A REQUIRED PARAMETER IS WHAT CANNOT FLATTEN. The page is not defaultable,
## so an entry cannot INHERIT a page it never stated; and `Table313Page` is an
## enum, so the only two spellings are the two pages the table actually spans
## and a typo is a compile error rather than a wrong citation.
##
## BUT A REQUIRED PARAMETER MAKES THE CHOICE UNAVOIDABLE AND NOT CORRECT, AND
## THE PARAGRAPH ABOVE ARGUED PAST THAT. Its own objection to two constants -
## "a thirteenth entry would pick one of them, and picking the wrong one is
## exactly as silent as before" - survives the change unaltered: a thirteenth
## entry can write `p313Start` for a row that prints on 3-29 and nothing says
## so. MEASURED, AND MEASURED BEFORE ASSERTION (7) EXISTED: `opOri`, whose row
## IS on 3-29, was switched to `p313Start` and the run stayed GREEN - every
## case, including `opOri`'s own four - while printing "p.3-28" in the
## citation. The parameter moved the defect; it did not close it.
##
## THAT SAME MUTATION IS RED TODAY, AND THE PARAGRAPH ABOVE IS KEPT AS THE
## REASON ASSERTION (7) EXISTS RATHER THAN AS A LIVE DESCRIPTION OF THE FILE -
## a reader who met it without this note would conclude the file is still
## blind to a lone wrong page. Re-run 2026-08-11 with (7) in place, the same
## lone switch gives `1 of 237 cases failed`, `FAILED opOri: its Table 3-13
## row is on the page the entry cites`. What (7) does NOT close is the
## CO-EDIT the header records: move the break constant and the declarations
## together and the two go green past each other.
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
##     LOCAL TO THE `m` CLUSTER, and an earlier wording here said it was -
##     true of the one example it gave and wrong about the page. The same
##     rendered p.3-28 also prints `divu.w` before `divs.l`, `mulu.w` before
##     `muls.l`, and `msac.l` before the second `mac.w`. What the derivation
##     needs is not local order anywhere on the page; it is the BREAK, and
##     none of these straddle it.
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
## THE BREAK, and an earlier wording here promised a red for the mismatch
## itself. A member renamed so that its mnemonic still sorts on the SAME side
## of `table313LastRowOn328` derives the page the entry already declares, and
## (7) passes with the name and the row now naming different things.
##
## THE RENAME THAT WOULD MEASURE THAT PARAGRAPH - a member renamed onto the
## SAME side of the break - WAS NOT RUN, so the paragraph above is REASONED
## FROM `table313PageOf`, whose three lines are directly above and whose
## comparison is a single `<=`, and is NOT a transcript. It is also the
## conservative direction: it describes something the assertion does NOT catch,
## so an unmeasured version of it understates the check rather than
## overstating it.
##
## THE SECOND HALF OF THAT PARAGRAPH IS NOW A CHECK INSTEAD OF A SENTENCE. It
## used to add that a member whose name does not begin with `op` fails through
## the `doAssert` in `table313PageOf` - a crash rather than a case. That is
## still true, and a statement about a hypothetical member; assertion (10) makes
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

## THE PAGE AXIS WAS PARAMETERIZED AND THE CLAIM AXIS WAS NOT, WHICH LET ONE
## SENTENCE COVER TWO DIFFERENT MANUAL ROWS. The four shift rows - `asl.l`,
## `asr.l`, `lsl.l`, `lsr.l` - carry `1(0/0)` under `#xxx`; the eight
## immediate-and-register rows dash it. "A dash under every memory column" was
## true of both only by declining to say anything about `#xxx`, which is not a
## memory column - so the citation was accurate and INCOMPLETE, and an entry
## that later needed the `#xxx` fact would have found the constant silent.
## Both facts are now SPELLED by every entry, and neither is defaultable.
##
## SPELLED WAS NOT CHECKED, AND ASSERTION (8) NOW CHECKS IT. `opAsl` switched
## from `imm313Timed` to `imm313Dashed` was GREEN at `223 cases passed` on the
## PRE-(8) revision of this file, which is the run that figure is dated by and
## is not reproducible now - printing `PASSED opAsl: ... and a DASH under #xxx
## as well` for a row the manual times at `1(0/0)`. Re-run 2026-08-11 with (8)
## in place, the same switch gives `1 of 237 cases failed`,
## `FAILED opAsl: its Table 3-13 `#xxx` column is the one the executor shows`,
## `got the entry declares "a DASH under #xxx as well" and varying the
## immediate derives "1(0/0) under #xxx, which is not a memory column"`.
##
## THE CHECK IS TWO-SIDED, WHICH ONE MUTATION WOULD NOT HAVE SHOWN. A check
## that answered `imm313Timed` for everything would have caught that switch and
## nothing else, so the opposite direction was measured too: `opAndi`, a
## genuinely dashed row, switched to `imm313Timed` gives `ctest exit=8`, `1 of
## 237 cases failed`, `got the entry declares "1(0/0) under #xxx, which is not
## a memory column" and varying the immediate derives "a DASH under #xxx as
## well"`. Both mutations were confirmed to have reached the compiled artifact
## by reading the `cov313` call for the mutated row in the generated C.
##
## AN EARLIER REVISION SAID THE REPOSITORY HAD NO SECOND SOURCE FOR THIS AXIS,
## AND IT WAS LOOKING FOR THE WRONG KIND OF ONE. It reasoned that the `#xxx`
## column follows from the row's `<EA>` operand SYNTAX, that nothing carries
## that syntax, and that the only derivation left was a roster of the four
## shift opcodes asserted against itself. The first two steps are correct. The
## conclusion is not, because the syntax is not the only thing the column
## records: a time under `#xxx` is the manual timing the case where the
## effective address IS an immediate, and whether this core's executor accepts
## one is BEHAVIOUR, which a test can drive. `table313ImmOf` drives it. The
## roster objection does not apply to it - it names no opcodes and would answer
## a thirteenth entry it has never seen.
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
  # --- eaDataModes / eaData7: every printed mode is legal, so the only
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

  # --- eaAlterableModes / eaAlterable7: an ADDQ or SUBQ destination is
  # WRITTEN, so it cannot be PC-relative. An address register IS legal here,
  # which is why the class is alterable and not data alterable.
  #
  # THESE TWO ARE NON-DISCRIMINATING FOR THE SECOND REASON THE HEADER GIVES.
  # `execAddSubQ` reaches its destination through `eaResolve`, which accepts
  # `{ea7AbsW, ea7AbsL}` and faults on every other mode-7 encoding - the exact
  # complement of `eaAlterable7`. Measured: deleting this operation's guard
  # leaves the entry GREEN.
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
  # OWN mask over the narrower `eaBitStatic` of the static form. WHAT THE FLAG
  # BUYS IS ASSERTION (4) AND NOT ASSERTION (1), and an earlier wording here
  # claimed both: "without it these four would assert `eaBitStatic` and a
  # widening of their own entry in `eaLegalityFor` would not be seen".
  #
  # MEASURED, AND THE FLAG IS NARROWER THAN THAT SENTENCE. `regOperand`
  # dropped from these four AND the `opEor, opBchg, opBclr, opBset` arm
  # widened to admit `An` - the mode all four cite as illegal - gave, on
  # 2026-08-11, `5 of 237 cases failed`, and the bit-operation reds were
  # `opBchg`, `opBclr` and `opBset` on ASSERTION (1) alone. (1) calls
  # `eaIsLegalFor(c.op, c.illegal)`, which never consults `regOperand`, so a
  # widening of their own entry IS seen with the flag or without it.
  #
  # WHAT IS LOST WITHOUT THE FLAG IS ASSERTION (4)'s SUBJECT. `logic.nim:431`
  # picks `eaBitStatic` for the static form, `eaBitStatic` also rejects `An`,
  # and so the executor keeps trapping and (4) stays GREEN over a widened
  # mask - passing while exercising a mask that is not the entry's own. The
  # flag points assertion (4) at the operation's own mask, and that is the
  # whole of what it does.
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
  # global that every legal run writes through, so "one fresh context per run"
  # was true of the context and false of the memory behind it. Nothing today
  # writes near `execBase` - `ramBase` and `stackBase` are both far from it -
  # so the isolation held BY ARITHMETIC, which is a property of the current
  # constants rather than of the runner, and it was written down nowhere. An
  # entry that moved `ramBase` or widened a run's write would have carried a
  # previous entry's bytes into the next run with nothing to say so.
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
  ## COUNT and `logic.nim:523` reads `uint32(d.imm)` for it. A DASH is the
  ## manual withholding that case, which the other eight rows have: their
  ## `<EA>` syntax is `#imm,Dx` or `Dy,Dx`, the `<ea>` is a register, and the
  ## long immediate those rows do carry is a separate EXTENSION WORD fetched
  ## from the instruction stream - `decode.nim:313` and `decode.nim:372` - so
  ## `d.imm` reaches nothing and the two runs are identical.
  ##
  ## THIS IS A SECOND SOURCE AND AN EARLIER REVISION OF THIS FILE SAID THERE
  ## WAS NONE. It said the only available derivation was "a roster of the four
  ## shift opcodes", which would indeed have asserted a roster against itself.
  ## The executor is not a roster: it is production code written from the
  ## manual, it is independent of every declaration in this file, and it is the
  ## same kind of second source `table313PageOf` uses for the page axis.
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
  # `table313ImmOf` carries the argument and the limit. This is the axis an
  # earlier revision declared UNCHECKED on the ground that the repository had
  # no second source for it.
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
      # Counting it below the `entry < 0` branch made the summary line report
      # the domain as SMALLER in exactly the run where the domain had GROWN -
      # a new operation with a mask and no entry went red and simultaneously
      # shrank the denominator that says how much is covered.
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
  # the same silence this file was built to remove. Measurement 8 in the
  # header is that mutation: the total fell by exactly twelve and this check
  # is what went red.
  #
  # The citation STRING and the `page313` field are written by one call but are
  # two different values, so each is a witness for the other: a row citing
  # Table 3-13 with no page, or a page on a row citing something else, is RED.
  # Measurement 8 is the FIRST of those two directions and measurement 8b is
  # the second; both are transcribed in the header.
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
# THE SUMMARY LINE CARRIES THE ATTRIBUTION FIGURE, BECAUSE A BARE COUNT IS THE
# DEFECT THIS FILE SPENT ITS HEADER CORRECTING. The entries stopped letting the
# count imply that assertion (4) is equally strong everywhere; the summary line
# was the last place that still let it. A reader who sees only a passing case
# count concludes that EVERY operation is guard-covered, and the attribution
# figure is what says otherwise.
#
# NO COUNT IS WRITTEN DOWN IN THIS COMMENT OR IN THE LINE ITSELF, INCLUDING THE
# ONES THAT WOULD MAKE IT EASIER TO READ. An earlier revision of this paragraph
# quoted the case total and the attribution figure as literals, and both went
# stale the moment an assertion was added - a stale count inside a comment about
# stale counts. Every figure the line prints is counted by the run that prints
# it.
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
  ## that established the values are dated in the header and do not travel with
  ## this line, so a forty-eighth entry declaring `discriminating: true` and
  ## measuring nothing would raise the numerator with exactly the authority of
  ## a measured one. The line therefore says DECLARE, and carries the date of
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
