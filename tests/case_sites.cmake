# `case_sites.cmake` - the driver half of the check that a vanished case fails
# its suite. Every generated `t_*` driver in
# `tests/tests_cpu.cmake` includes this file and calls BOTH of its functions
# exactly once:
# `mcf5307_check_case_sites`, whose rules are stated below, and
# `mcf5307_check_case_total`, which fails on a table that got shorter. That
# every driver carries both is not left to the reader: `tests/tests_cpu.cmake`
# compares, at configure time, the set of suites carrying the run-time half
# against the set of generated drivers calling each function, and a driver
# carrying one of the two is a hard error there.
#
# WHY THE COMPARISON IS HERE AND NOT IN THE TEST PROGRAM. The program prints
# its registries and judges none of them; this function judges. A program
# that graded its own coverage would be graded by the same edit that broke it,
# and a program that stopped early would print no grade at all - which this
# function reads as the failure it is, because a missing registry line is a
# hard error here.
#
# THE PER-DRIVER `[1-9][0-9]*` ANCHOR IS KEPT BESIDE THIS CHECK rather than
# replaced by it: it is the cheaper test and it fails on a differently-shaped
# defect.
#
# NO EXPECTED COUNT IS WRITTEN DOWN BY RULES 1 TO 4. The registries those
# rules compare are all derived - by the compiler and the run, and by
# reading the suite's own text - so adding a case updates the expectation and
# nothing has to be maintained.
#
# RULE 5's OFF-GREEN-PATH COUNT AND `mcf5307_check_case_total`'s CASE TOTAL ARE
# TYPED. Both
# are recorded in the driver template beside the suite they govern, and each
# states its own trade where it is defined.
#
# A FURTHER TYPED FIGURE MUST BE ARGUED FOR AS HARD AS THESE TWO WERE.

# THE RULES, and each one fails on a different defect:
#
#   1. Every registry line the program should print IS printed. A run that
#      stopped before the tail prints none of them.
#   2. The number of call sites the SOURCE carries equals the number the
#      COMPILER recorded. This is the only rule whose two sides do not share a
#      path: it fails when the declared registry is short of the text.
#   3. Every declared site was either EXECUTED or is declared off the green
#      path. This is the vanished-case rule.
#   4. Every site that CLAIMS the off-green-path exemption asserts the literal
#      `false`. This is the rule that keeps rule 3's escape hatch from being a
#      way out of rule 3.
#   5. The number of sites claiming the exemption is the number the driver
#      records. This one figure is typed; rules 1-4 derive everything.
#
# RULES 4 AND 5 EXIST BECAUSE NOTHING OTHERWISE CONSTRAINS WHICH SITES MAY
# CLAIM THE EXEMPTION. An
# author who met rule 3's red - "this site never ran" - would otherwise have a
# one-word repair
# available: change `check(` to `checkOffGreenPath(` and the case leaves the
# rule's reach without leaving the file.
#
# RULE 4 IS WHAT MAKES THE EXEMPTION SAFE, and it is derived from the source
# text, not typed. A site that legitimately holds it - a
# report of an operation with a non-empty legality mask and no coverage entry -
# passes the LITERAL `false`: reaching it is itself the failure, so exempting it
# from "must have run" cannot silence anything. A site that could PASS is a case,
# and a case that has stopped running is what rule 3 is for. So the exemption is
# open only to calls that cannot pass, and the one-word repair above no longer
# compiles past this check.
#
# RULE 5 CATCHES THE OTHER DIRECTION, which rule 4 cannot see: DELETING the
# defect-report. Its site never runs on a green tree, so rule 3 says nothing,
# the case total says nothing, and rules 1 and 2 stay balanced. Only a recorded
# count notices. The figure is typed for the same reason the case total is, and
# the trade is stated once, at `mcf5307_check_case_total` below.
function(mcf5307_check_case_sites suite source run_output
        off_green_path_expected)
    # ---- the source side of rule 2 ------------------------------------------
    # THE FILE IS SPLIT BY HAND AND NOT WITH `file(STRINGS)`. These suites are
    # full of semicolons - `proc check(ok: bool; label: string)` - and every
    # semicolon in a `file(STRINGS)` result splits one line into two list
    # elements, which would take the `#` off the front of a comment and the
    # `proc` off the front of a definition.
    file(READ "${source}" source_text)
    string(REPLACE ";" "\\;" source_text "${source_text}")
    string(REPLACE "\n" ";" source_text "${source_text}")

    set(source_sites 0)
    set(unsafe_exemptions "")
    foreach(line IN LISTS source_text)
        # A COMMENT LINE IS NOT A CALL SITE. A suite may quote a
        # `check<Name>(...)` call inside a comment, and without the rule the
        # source side counts one site the
        # compiler never saw and every run of that suite is red.
        #
        # THE RULE IS WHOLE-LINE AND NOT TRAILING-COMMENT, deliberately. A `#`
        # inside a STRING LITERAL is ordinary in these suites - a case label
        # may spell an immediate operand - so a rule that stripped from the
        # first `#` would cut the line at that label and lose any call site
        # written after it, and the source side would fall SHORT of the
        # compiler. What the whole-line rule costs instead is that a TRAILING
        # comment naming `check<Name>(` counts as a site the compiler never saw
        # and rule 2 goes RED. Both mistakes are possible and only one of them
        # is loud, so the rule is written to make the loud one.
        if(line MATCHES "^[ \t]*#")
            continue()
        endif()
        # A DEFINITION IS NOT A CALL SITE either.
        if(line MATCHES "^(proc|template) check")
            continue()
        endif()
        # `check<Name>Impl(` IS NOT A CALL SITE. It is the renamed
        # implementation the template calls, and it appears exactly once inside
        # each template body; counting it would put the source side one ahead
        # of the compiler for every template in the file.
        string(REGEX MATCHALL "check[A-Za-z]*\\(" hits "${line}")
        foreach(hit IN LISTS hits)
            if(NOT hit MATCHES "Impl\\($")
                math(EXPR source_sites "${source_sites}+1")
            endif()
        endforeach()
        # ---- the source side of rule 4 --------------------------------------
        # A CALL THAT CLAIMS THE EXEMPTION MUST ASSERT THE LITERAL `false`, and
        # the argument is read HERE rather than at run time because a call the
        # green run never reaches has no run-time argument to read. That is the
        # whole difficulty: the sites this rule governs are exactly the sites
        # nothing executes.
        #
        # IT IS READ ON ONE LINE, so a `checkOffGreenPath(` whose `false` wraps
        # to the line below is reported as unsafe and the run is RED. That is
        # the fail-safe direction for this rule as well: an exemption this rule
        # cannot read is REFUSED and never granted.
        if(line MATCHES "checkOffGreenPath\\(" AND
                NOT line MATCHES "checkOffGreenPath\\(false[ \t]*[,)]")
            string(STRIP "${line}" stripped_line)
            list(APPEND unsafe_exemptions "${stripped_line}")
        endif()
    endforeach()

    if(NOT unsafe_exemptions STREQUAL "")
        string(REPLACE ";" "\n    " unsafe_text "${unsafe_exemptions}")
        message(FATAL_ERROR
            "${suite}: a call in ${source}\n  claims the off-green-path "
            "exemption without asserting the literal `false`:\n    "
            "${unsafe_text}\n"
            "  THE EXEMPTION IS OPEN ONLY TO A CALL THAT CANNOT PASS. Its "
            "purpose is to carry a report of a defect - a site reached only "
            "when the suite is already failing - and requiring such a site to "
            "have run would make a healthy tree red. A call that could pass is "
            "a CASE, and a case that stopped running is what rule 3 above "
            "exists to fail on. Changing `check(` to `checkOffGreenPath(` is "
            "not a repair for a rule-3 red.")
    endif()

    # ---- rule 1 -------------------------------------------------------------
    _mcf5307_case_site_registry("${suite}" "declared" "${run_output}" declared)
    _mcf5307_case_site_registry("${suite}" "executed" "${run_output}" executed)
    _mcf5307_case_site_registry("${suite}" "off-green-path" "${run_output}"
        off_green_path)

    list(LENGTH declared declared_count)

    # ---- rule 2 -------------------------------------------------------------
    if(NOT declared_count EQUAL source_sites)
        message(FATAL_ERROR
            "${suite}: the run declared ${declared_count} check call sites and "
            "${source}\n  carries ${source_sites}. The two are derived by "
            "different paths - the compiler's `declaredSites` and a count of "
            "`check<Name>(` in the file's own text - so a disagreement means "
            "either that a call site is not reaching the compiler or that the "
            "text-side rule in `tests/case_sites.cmake` no longer matches how "
            "the suite is written. NEITHER may be resolved by relaxing this "
            "check.")
    endif()

    # ---- rule 3 -------------------------------------------------------------
    set(missing "")
    foreach(site IN LISTS declared)
        if(NOT site IN_LIST executed)
            if(NOT site IN_LIST off_green_path)
                list(APPEND missing "${site}")
            endif()
        endif()
    endforeach()
    # ---- rule 5 -------------------------------------------------------------
    list(LENGTH off_green_path off_green_path_count)
    if(NOT off_green_path_count EQUAL off_green_path_expected)
        string(REPLACE ";" " " off_green_path_text "${off_green_path}")
        message(FATAL_ERROR
            "${suite}: ${off_green_path_count} site(s) claim the "
            "off-green-path exemption and the driver in "
            "tests/tests_cpu.cmake records ${off_green_path_expected}. The "
            "claiming lines are: ${off_green_path_text}\n"
            "  A SITE ADDED HERE LEAVES RULE 3's REACH and a site removed here "
            "removes a report of a defect that nothing else in this file can "
            "miss: its call never runs on a green tree, so rule 3 is silent "
            "about it, the case total is silent about it, and rules 1 and 2 "
            "stay balanced whichever way it goes. Only this figure notices. "
            "Move it deliberately or not at all.")
    endif()

    if(NOT missing STREQUAL "")
        list(LENGTH missing missing_count)
        string(REPLACE ";" " " missing_text "${missing}")
        message(FATAL_ERROR
            "${suite}: ${missing_count} of the ${declared_count} check call "
            "sites in ${source}\n  never ran, at lines: ${missing_text}\n"
            "  A CASE THAT DOES NOT RUN IS NOT A CASE THAT PASSED. The run "
            "exited 0 and reported its own count, which is exactly what a "
            "suite reduced to one case does. If a site is reachable only when "
            "the suite is already failing, write it with the suite's "
            "`checkOffGreenPath` template so the exemption is visible at the "
            "call site.")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# THE CASE TOTAL. The rules above catch a case that stops RUNNING. They do not
# catch a TABLE THAT GETS SHORTER, and the comment at the head of
# `tests/case_sites.nim` says so: a site inside a loop is ONE site however many
# rows the loop carries.
#
# A TABLE SHORTENED TO FEWER ROWS TAKES ITS ASSERTIONS WITH IT while every rule
# above stays satisfied, because every call site still ran.
#
# THE TRADE, STATED PLAINLY BECAUSE IT CUTS AGAINST EVERYTHING ELSE IN THIS
# FILE. Every other figure here is DERIVED and this one is TYPED. A typed total
# is one more number that can drift.
# It is accepted anyway, because the two failure modes are not
# the same size: a typed total that goes stale FAILS LOUDLY on the next run and
# names the suite, the old figure and the new one, whereas a shortened table
# fails NOT AT ALL. The cost is an edit that must accompany a deliberate change
# in the number of cases; the thing bought is that an undeliberate one cannot
# pass.
#
# A TRANSCRIPT IN `src/` IS NOT A DERIVATION - it is written down too - but it
# is written down in PRODUCTION SOURCE, by another task, for another reason, and
# a figure with two keepers cannot be moved by editing one of them.
# `tests/tests_cpu.cmake` holds a transcript it finds against the generated
# driver's figure at configure time and stops the configure when the two
# disagree.
#
# THE ROWS OF THESE TABLES
# are HAND-WRITTEN DATA and are their own specification, so any figure compared
# against the run's count has to be written down somewhere. Counting the rows
# out of the source text - the trick rule 2 uses for call sites - works for a
# table written as an array literal and not for `for i in 0 ..< n`, and a rule
# that covers some loops and silently passes the others would be worse than a
# figure, because its silence would read as coverage. A compile-time `doAssert`
# cannot see the counters at all - `Error: cannot evaluate at compile time:
# failures`.
#
# IT IS DRIVER-SIDE AND NOT A CASE INSIDE EACH SUITE, for two reasons. The
# first is this file's
# own principle: the program reports and the driver judges, so a mutation that
# breaks the suite cannot also grade it. The second is that adding a case
# to a suite MOVES THAT SUITE'S PRINTED TOTAL, and a suite's total may be
# quoted as a transcript inside `src/mcf5307/`, which a test
# may not edit. Closing a drift hole by creating new drifts in production
# source is not a repair. A driver-side comparison adds no case and moves no
# total.
#
# `t_ea_masks` KEEPS ITS IN-FILE CASE AND ALSO GETS THIS ONE, rather than being
# exempted here. An exemption list is a second thing to maintain and a place for
# a suite to hide. The two copies of the figure cannot silently disagree: both
# are compared against the SAME live run, so a drift in either is red on the
# next run.
#
# WHAT IT DOES NOT REACH. It pins the COUNT and not WHICH cases ran, so one
# block deleted and another of the same size added in a single change passes -
# the same limit `t_ea_masks.nim` states for its own constant. And it says
# nothing about whether a case ASSERTS anything: see `tests/case_sites.nim`,
# under the heading `THE ONE THING NONE OF IT REACHES`.
function(mcf5307_check_case_total suite run_output expected)
    string(REGEX MATCH "${suite}: ([0-9]+) cases passed" matched "${run_output}")
    if(matched STREQUAL "")
        message(FATAL_ERROR
            "${suite}: the run exited 0 and printed no "
            "`${suite}: <N> cases passed` line, so there is no total to "
            "compare. A run that reached this check and printed no summary "
            "did not run to the end.")
    endif()
    set(reported "${CMAKE_MATCH_1}")
    if(NOT reported EQUAL expected)
        message(FATAL_ERROR
            "${suite}: the run emitted ${reported} cases and the driver in "
            "tests/tests_cpu.cmake records ${expected}.\n"
            "  A COUNT THAT FELL IS ASSERTIONS THAT ARE GONE, and the rules "
            "above cannot see it: a table shortened from many rows to one "
            "keeps every call site executed. MEASURED 2026-08-13, "
            "`tests/t_logic.nim`'s three-row bit-operation table cut to one "
            "row took six assertions with it and printed 68 for 74, exit 0, "
            "`Passed`.\n"
            "  If the change was deliberate, move the figure in the driver "
            "template beside this suite's `mcf5307_check_case_total` call and "
            "say in the commit what the cases were. If it was not, the cases "
            "are missing. THE FIGURE IS TYPED; `tests/case_sites.cmake` states "
            "why that trade was taken, and `tests/tests_cpu.cmake` holds the "
            "moved figure against any transcript of this suite it finds in "
            "`src/`.")
    endif()
endfunction()

# One registry line out of the run's output, as a list of line numbers. A
# missing line is FATAL: it is what a run that stopped early looks like.
function(_mcf5307_case_site_registry suite kind run_output out)
    string(REGEX MATCH "${suite}: check sites ${kind}:([^\n]*)"
        matched "${run_output}")
    if(matched STREQUAL "")
        message(FATAL_ERROR
            "${suite}: the run exited 0 and printed no "
            "`${suite}: check sites ${kind}:` line. That line is printed at "
            "the very end of the suite, so a run which stopped before it has "
            "not run to the end - whatever count it reported on the way.")
    endif()
    string(REGEX MATCHALL "[0-9]+" sites "${CMAKE_MATCH_1}")
    set(${out} "${sites}" PARENT_SCOPE)
endfunction()
