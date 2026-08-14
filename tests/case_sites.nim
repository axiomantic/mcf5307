## `case_sites` - the run-time half of the check that a VANISHED CASE fails its
## suite. Every `t_*` Nim suite in this directory imports it. Task CPU-28.
##
## WHAT IT IS FOR, AND THE MEASUREMENT THAT MADE IT NECESSARY. MEASURED
## 2026-08-13: every registered `t_*` driver in `tests/tests_cpu.cmake` anchors
## its pass on `<suite>: [1-9][0-9]* cases passed`, which rejects a run of ZERO
## cases and accepts every other count.
##
## THAT SENTENCE WAS FALSE, AND UNDATED, WHEN THIS FILE FIRST CARRIED IT, and it
## is recorded here rather than quietly repaired. FOUR of the eight drivers
## anchored on `[0-9]+`, which accepts a run of zero: `t_ea_masks`,
## `t_sign_extend`, `t_alu` and `t_move`. MEASURED 2026-08-13 with
## `t_ea_masks`'s two `check*Impl` procs returning at their first line:
## `t_ea_masks: 0 cases passed`, exit 0, and the anchor accepted it. All eight
## were strengthened that day. THE DEFECT WORTH REMEMBERING IS NOT THE FOUR
## REGEXES: it is that a file describing a mechanism stated a property of eight
## files that held for four of them, and nothing anywhere compared the sentence
## with the code.
##
## SO A SENTENCE ABOUT THE TREE CARRIES A DATE HERE, OR IT IS NOT WRITTEN. A
## dated measurement claims what was true when it was taken and nothing about
## the tree the reader has in front of them, which is the only claim of that
## shape a comment can keep. An undated one has nothing holding it, and this
## file has already produced one.
##
## MEASURED 2026-08-13 against `t_irq`, whose whole case list was reduced to
## one by adding `if passCount >= 1: return` to the head of its `check`: the
## program printed `t_irq: 1 cases passed`, exited 0, and
## `ctest -R ^t_irq$` reported `Passed`. EVERY OTHER CASE VANISHED IN SILENCE.
## The same driver shape carried every other suite, so the same silence did.
##
## WHAT IT REPLACES THE RANGE WITH IS A COMPARISON, AND THE COMPARISON IS
## DERIVED. A count written down in a file is one more figure that drifts, and
## this project has lost days to drifting figures. So the expectation is
## DERIVED, three ways that do not share a path:
##
##   1. THE COMPILE-TIME REGISTRY, `declaredSites`. Every `check` family
##      template adds its own call-site line to this sequence during semantic
##      analysis, so it holds every site the SOURCE carries, including the
##      sites a green run never reaches.
##   2. THE RUN-TIME REGISTRY, `executedSites`. The same template adds the same
##      line when the call actually runs.
##   3. THE SOURCE ITSELF. The driver counts the `check<Name>(` call sites in
##      the suite's own text and requires that count to equal the length of
##      `declaredSites`.
##
## NOT EVERY FIGURE HERE IS DERIVED, and an earlier revision of this comment
## said they all were. The suite's CASE TOTAL and its OFF-GREEN-PATH COUNT are
## TYPED, both recorded in the driver template beside the suite, and
## `tests/case_sites.cmake` states at each of them why it is typed and what is
## compared against it. The three registries above are derived.
##
## The suite PRINTS both registries and JUDGES NEITHER. The comparison is the
## driver's, because a program that graded its own coverage would be graded by
## the same mutation that broke it - and because a run that stopped early would
## print no verdict at all, which the driver reads as the failure it is.
##
## THE PROPERTY THIS BUYS: adding a case adds a call site, which enters
## `declaredSites` with no file edited anywhere else; and removing a case's
## EXECUTION leaves its site in `declaredSites` and out of `executedSites`,
## which is the failure. Neither direction needs a number to be maintained.
##
## WHAT IT DOES NOT REACH, STATED SO ITS SILENCE IS NOT READ AS COVERAGE. A
## site inside a loop is ONE site however many rows the loop carries, so a
## mutation that shortens a table from 444 rows to one keeps the site executed
## and this check stays green. It catches a case that stops RUNNING, not a
## table that gets shorter. That second shape is guarded by
## `mcf5307_check_case_total` in `tests/case_sites.cmake`, which every driver
## calls and which compares the suite's printed total against a figure recorded
## beside the driver. That file states the trade a TYPED figure takes, and
## `tests/tests_cpu.cmake` holds the same figure against any transcript of the
## same suite it finds in `src/`.
##
## THE ONE THING NONE OF IT REACHES, AND IT IS A TRUE LIMIT AND NOT A GAP TO BE
## CLOSED LATER. Every rule here counts or locates CALLS. Not one of them reads
## what a call ASSERTS. So an edit that keeps the number and the position of the
## executed calls and empties what they say is outside the reach of all of it.
##
## MEASURED 2026-08-13, and this is the measurement rather than a worry. In
## `tests/t_irq.nim` the call at line 375,
## `check(got == want, "mask 3 inhibits level 3", $got, $want)`, was replaced by
## `check(true, "mask 3 inhibits level 3", "", "")` - the same site, the same
## label, no assertion. The suite printed the SAME declared registry, the SAME
## executed registry, an empty off-green-path registry and its FULL case count
## passed; `ctest` reported `Passed` with rc 0; and the test's entire output
## was BYTE-IDENTICAL to the healthy run's. There is no channel on which the two
## differ.
##
## THE NEIGHBOURING EDIT IS NOT INVISIBLE, AND THE DIFFERENCE IS THE POINT.
## DELETING that same call outright - which rules 1 to 3 also cannot see, since
## the source count and the declared count fall together - prints ONE CASE
## FEWER and `mcf5307_check_case_total` fails it against the recorded total.
## Deletion moves a number. SUBSTITUTION MOVES NOTHING, and a mechanism that
## compares numbers has nothing to compare.
##
## WHAT WOULD CATCH IT IS MUTATION TESTING OF THE CORE, WHICH THIS IS NOT.
## Breaking the thing an assertion asserts and requiring the assertion to go red
## is the only check that reads through to the assertion's content. This
## repository has that in a narrow registered form - the `suite-red` kind in
## `tests/t_claims.cmake`, which applies a named mutation to `src/` and counts a
## suite's red cases. MEASURED 2026-08-13: it would not catch the substitution
## above, because both registered `suite-red` claims name level-7 latch
## mutations and both EXPECT ZERO red, so neither reads anything through line
## 375. Extending `t_claims` with a mutation each suite is expected to catch
## would be the repair, and it is not one this file can make: a site-counting
## mechanism cannot become a coverage mechanism by counting more carefully.
##
## MIT licensed. Nothing here is a fact about Motorola silicon.

import std/algorithm

var declaredSites* {.compileTime.}: seq[int]
  ## THE CALL SITES THE SOURCE CARRIES, filled during semantic analysis. It is
  ## a compile-time sequence, so a suite reads it into a `const` at the END of
  ## its own file, after the last template has been instantiated. Reading it
  ## earlier would report a prefix and would report it as a total.

var offGreenPathSites* {.compileTime.}: seq[int]
  ## THE SITES A GREEN RUN IS NOT EXPECTED TO REACH. A suite may carry a call
  ## whose only purpose is to REPORT a defect - `check(false, ...)` in the arm
  ## that runs when a table entry is missing - and such a site is unexecuted in
  ## every run that passes. Without this registry the check below would be RED
  ## on a healthy tree, and the only repairs available would be to delete the
  ## report or to weaken the rule. A site enters here by being written with the
  ## suite's `checkOffGreenPath` template rather than its `check` template, so
  ## the exemption is VISIBLE AT THE CALL SITE and is not a driver-side list
  ## that drifts away from the code it exempts. Across the eight suites exactly
  ## ONE site is of this kind, in `t_ea_masks.nim`.
  ##
  ## THAT FIGURE WAS PROSE WITH NOTHING CHECKING IT UNTIL 2026-08-13, and prose
  ## is what the exemption could have grown behind: an author meeting rule 3's
  ## "this site never ran" had a one-word repair available - change `check(` to
  ## `checkOffGreenPath(` - and the case would have left the rule's reach
  ## without leaving the file. Two driver-side rules now hold it. RULE 4 admits
  ## only a call that asserts the literal `false`, so the exemption is open only
  ## to a call that CANNOT PASS and cannot silence a case. RULE 5 compares the
  ## number of claiming sites against a figure recorded beside the driver, which
  ## is the only thing that notices a defect-report being deleted: its call
  ## never runs on a green tree, so rule 3, the case total and rules 1 and 2 are
  ## all silent about it either way. `tests/case_sites.cmake` states both.

var executedSites*: seq[int]
  ## THE CALL SITES THE RUN REACHED. A site that ran a thousand times appears a
  ## thousand times here and `caseSiteLine` prints it once; the check is
  ## reached-at-least-once and nothing finer.

proc caseSiteLine*(kind: string; suite: string; sites: seq[int]): string =
  ## One registry, sorted, de-duplicated and printed as
  ## `<suite>: check sites <kind>: <line> <line> ...`.
  ##
  ## THE LINES ARE SORTED SO THAT THE TWO REGISTRIES ARE COMPARABLE AS TEXT.
  ## `declaredSites` is filled in instantiation order and `executedSites` in
  ## execution order, and neither order is the other's; a driver that compared
  ## the raw sequences would report a difference that is not one.
  var ordered = sites
  ordered.sort()
  result = suite & ": check sites " & kind & ":"
  var previous = -1
  for line in ordered:
    if line != previous:
      result.add(" " & $line)
      previous = line
