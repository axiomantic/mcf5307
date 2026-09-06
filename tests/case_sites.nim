## `case_sites` - the run-time half of the check that a vanished case fails its
## suite. Every `t_*` Nim suite in this directory imports it.
##
## THE EXPECTATION IS DERIVED, in ways that do not share a path:
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
## Nothing here is a fact about Motorola silicon.

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
  ## that drifts away from the code it exempts.

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
