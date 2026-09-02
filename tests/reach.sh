#!/bin/zsh
# `reach.sh` - the mutation reach gate. A developer tool, not a test.
#
# It is deliberately not wired into ctest. It rewrites source files and runs a
# whole second CMake configure-and-build for every mutation, so a run takes
# minutes rather than the seconds the suite takes. It is run by hand, when a
# test row's justification is being written or being doubted.
#
# ---------------------------------------------------------------------------
# What "reached" means, and the limit on it. Read this before trusting a result.
#
#   REACHED means the edit changed the generated C. It does not mean the edit
#   changed what the program does. The two are different claims and only the
#   first one is measured here. A `case` arm split into two arms applying the
#   same mask is a behavioural no-op whose generated C changes, so it reports
#   REACHED and could not have failed any test.
#
#   Therefore: a mutation that reports REACHED and then leaves every suite
#   green is not yet evidence of a coverage hole. It is evidence of one of two
#   things, and a human has to say which:
#       (a) the mutation is behaviourally vacuous, and the suites are right to
#           stay green; or
#       (b) the mutation does change behaviour and nothing tests it, which is
#           the coverage hole worth writing a row for.
#   A green reach line is a floor, not a verdict.
#
# ---------------------------------------------------------------------------
# Why the fixed path is load-bearing.
#
#   Nim derives part of its name mangling from the module's full path, so a
#   mutant tree extracted to a new absolute path produces different generated
#   C than a reference built at a different absolute path even with zero source
#   changes. A harness that compares across two paths can report REACHED and
#   nothing else, which is the same as not checking.
#
#   Every build therefore happens at one fixed absolute path, `$W`. Reference
#   and mutant are extracted to the same directory in turn, so the only
#   remaining thing that can change the generated C is the source. A
#   zero-change run must produce byte-identical C.
#
#   Do not change `MCF5307_REACH_ROOT` between building the reference and
#   running a mutation. That reintroduces exactly that confound.
#
#   The gate's whole value is that it can fail, so prove that it still can:
#   `reach.sh selftest` runs its controls and checks each verdict.
#       NULL          zero source changes  -> must report NOT REACHED
#       COMMENT_ONLY  a comment changed    -> must report NOT REACHED
#       POSITIVE      one semantic token   -> must report REACHED
#   If any control disagrees, the gate is broken and no result from it counts.
#
# ---------------------------------------------------------------------------
# USAGE
#   reach.sh ref                       build the reference tree at $W
#   reach.sh run NAME FILE OLD NEW     apply one mutation and measure it
#                                      (NEW="" makes it the null control)
#   reach.sh null                      the null control on its own
#   reach.sh selftest                  ref + the controls, with verdicts
#
#   FILE is repository-relative, e.g. `src/mcf5307/control.nim`. OLD must occur
#   exactly once in it or the run aborts rather than mutate the wrong line.
#
#   Exit status of `run`:  0 = REACHED,  2 = NOT REACHED,  1 = harness error.
#
# Requires: zsh, CMake, python3, and the Nim toolchain this project already
# needs. macOS `md5` is used when present and `md5sum` otherwise.
set -u

SELF=${0:A}
SRC=${${0:A:h}:h}
REACH_ROOT=${MCF5307_REACH_ROOT:-/tmp/mcf5307-reach}
R=$REACH_ROOT
W=$R/w
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

# The suites the measurement reports on. `t0_abi_smoke` is left out on purpose:
# it takes the address of every published symbol and asserts no core behaviour.
# That is a property of what it asserts, not of whether it builds.
SUITES='^(t_control|t_logic|t_alu|t_move|t_ea_masks|t_sign_extend|mcf5307_conformance_all)$'

if command -v md5 > /dev/null 2>&1; then
  hashof () { md5 -r "$@" }
else
  hashof () { md5sum "$@" | awk '{print $1, $2}' }
fi

populate () {
  rm -rf $W; mkdir -p $W
  # `-o --exclude-standard` matters: the module under measurement may not be
  # committed yet, and a reference tree missing it would measure nothing.
  cd $SRC && git ls-files -z -c -o --exclude-standard | tar --null -T - -cf - \
    | tar -x -C $W
}

configure () {  # $1 = log file
  cd $W && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release > $1 2>&1
}

hashc () {  # $1 = output file. One line per generated C unit: "hash name".
  cd $W/build/nimcache || return 1
  local units=( @mmcf5307@s*.nim.c(N) )
  if (( ${#units} == 0 )); then
    echo "NO GENERATED C UNITS FOUND in $W/build/nimcache" >&2; return 1
  fi
  hashof ${units[@]} | sort -k2 > $1
}

usage () {
  print -r -- "reach.sh ref                    build the reference tree at \$W"
  print -r -- "reach.sh run NAME FILE OLD NEW  one mutation (NEW=\"\" -> null)"
  print -r -- "reach.sh null                   the null control on its own"
  print -r -- "reach.sh selftest               ref + all three controls"
  print -r -- "Read the header of this file before trusting a REACHED result."
  exit 1
}

[ $# -ge 1 ] || usage

case "$1" in
ref)
  populate
  configure $R/ref.cfg.log || {
    echo "REF CONFIGURE FAILED"; tail -25 $R/ref.cfg.log; exit 1; }
  hashc $R/ref.md5 || exit 1
  cp $W/build/nimcache/"@mmcf5307@scontrol.nim.c" $R/ref.control.c
  echo "REFERENCE BUILT at $W"; cat $R/ref.md5
  ;;
run)
  [ $# -eq 5 ] || usage
  NAME=$2; FILE=$3; OLD=$4; NEW=$5
  [ -f $R/ref.md5 ] || { echo "NO REFERENCE. Run: reach.sh ref"; exit 1; }
  D=$R/out/$NAME; rm -rf $D; mkdir -p $D
  populate
  if [ -n "$NEW" ]; then
    python3 - "$W/$FILE" "$OLD" "$NEW" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
n = s.count(old)
if n != 1:
    sys.stderr.write("MUTATION-APPLY-FAIL: %d occurrences\n" % n); sys.exit(3)
open(p, 'w').write(s.replace(old, new, 1))
PY
    [ $? -ne 0 ] && { echo "$NAME: APPLY FAILED"; exit 1; }
  else
    echo "$NAME: NULL CONTROL - no source change applied"
  fi
  configure $D/cfg.log || {
    echo "$NAME: CONFIGURE FAILED"; tail -25 $D/cfg.log; exit 1; }
  hashc $D/mut.md5 || exit 1
  if diff -q $R/ref.md5 $D/mut.md5 > /dev/null; then
    echo "$NAME: REACH = NOT REACHED (generated C byte-identical to the reference)"
    exit 2
  fi
  echo "$NAME: REACH = REACHED. Changed compile units:"
  awk 'NR==FNR {h[$2] = $1; next} h[$2] != $1 {print "    " $2}' \
    $R/ref.md5 $D/mut.md5
  # A second, independent reach signal: the mutated text itself in the C.
  diff $R/ref.control.c $W/build/nimcache/"@mmcf5307@scontrol.nim.c" \
    > $D/control.c.diff
  echo "  control.nim.c diff lines: $(wc -l < $D/control.c.diff)"
  # REACHED only says the C changed. What follows says whether anything noticed.
  cd $W && cmake --build build -j6 -- -k > $D/build.log 2>&1
  ctest --test-dir build --no-tests=error -R $SUITES -V > $D/ctest.log 2>&1
  echo "=== $NAME MEASUREMENT ==="
  grep -E "t_[a-z_]+: ([0-9]+ of )?[0-9]+ cases (failed|passed)" $D/ctest.log \
    | sed 's/^[0-9]*: //' | sort -u
  # The conformance runner prints "N cases, M failed" per group when it is
  # clean and "N cases run, failures above" when it is not, so both forms have
  # to be matched or a failing conformance group reports as silence.
  grep -E "mcf5307_conformance_[a-z]+: [0-9]+ cases, [0-9]+ failed|runner: [0-9]+ cases" \
    $D/ctest.log | sed 's/^[0-9]*: //' | sort -u
  grep -E "^[0-9]+: +FAILED" $D/ctest.log | sed 's/^[0-9]*: //' | head -10
  echo "  (REACHED means the C changed, NOT that the edit is behavioural."
  echo "   All-green here needs a human verdict - see the header.)"
  ;;
null)
  $SELF run NULL_CONTROL x x ""
  ;;
selftest)
  # The three controls. Each one names the verdict it must produce, so a gate
  # that has stopped being able to fail is caught here rather than trusted.
  CMT_OLD='## `Scc Dx`: ones or zeros into the LOW BYTE of a data register.'
  CMT_NEW='## `Scc Dx`: ones or zeros into the low byte of a data register.'
  POS_OLD="conditionHolds(ctx.sr, d.destReg): 0xFF'u32"
  POS_NEW="conditionHolds(ctx.sr, d.destReg): 0xFE'u32"
  rc=0
  $SELF ref || exit 1
  echo
  $SELF run NULL_CONTROL x x ""; s=$?
  [ $s -eq 2 ] && echo "SELFTEST NULL: PASS (NOT REACHED, as required)" \
               || { echo "SELFTEST NULL: FAIL (expected NOT REACHED)"; rc=1 }
  echo
  $SELF run COMMENT_ONLY src/mcf5307/control.nim "$CMT_OLD" "$CMT_NEW"; s=$?
  [ $s -eq 2 ] && echo "SELFTEST COMMENT_ONLY: PASS (NOT REACHED, as required)" \
               || { echo "SELFTEST COMMENT_ONLY: FAIL (expected NOT REACHED)"; rc=1 }
  echo
  $SELF run POSITIVE src/mcf5307/control.nim "$POS_OLD" "$POS_NEW"; s=$?
  [ $s -eq 0 ] && echo "SELFTEST POSITIVE: PASS (REACHED, as required)" \
               || { echo "SELFTEST POSITIVE: FAIL (expected REACHED)"; rc=1 }
  echo
  [ $rc -eq 0 ] && echo "SELFTEST: ALL THREE CONTROLS BEHAVED. The gate can fail." \
               || echo "SELFTEST: A CONTROL MISBEHAVED. Trust no result from this gate."
  exit $rc
  ;;
*)
  usage
  ;;
esac
