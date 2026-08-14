## `t_sign_extend` - the sign-extension helpers of `mcf5307/machine`.
##
## TEN CASES, AND EACH ONE CAN FAIL. `s16` and `s8` turn a displacement or an
## immediate value from the instruction stream into the signed 32-bit value
## the address arithmetic adds. The four boundary values of each helper are
## asserted with their exact results:
##
##   s16  0x0000 -> 0        the low end of the positive half
##        0x7FFF -> 32767    the largest positive value
##        0x8000 -> -32768   THE FIRST NEGATIVE VALUE
##        0xFFFF -> -1       the last negative value
##
##   s8   0x00 -> 0, 0x7F -> 127, 0x80 -> -128, 0xFF -> -1, and the same
##        again for the two values above with a high byte that `s8` must
##        ignore.
##
## WHY THE NEGATIVE HALF IS THE POINT. Sign extension REINTERPRETS the bits of
## an unsigned value as a two's-complement signed value of the same width. A
## checked narrowing conversion (`int16(x)`, `int8(x)`) does something
## different: it rejects each value that the signed type cannot hold. Every
## input from 0x8000 to 0xFFFF - that is, EVERY NEGATIVE DISPLACEMENT - is
## such a value. The library is built with `--panics:on -d:release`, so a
## checked conversion there does not raise a catchable error; it ends the
## process with a `RangeDefect`. This test compiles with THE LIBRARY'S OWN
## FLAG SET, thus a helper that went back to a checked conversion kills this
## program on case 3 and the driver reports the failure.
##
## The positive cases are the POSITIVE CONTROL. Without them a helper that
## returned a constant 0, or a program that cannot run at all, would not be
## separable from a helper that extends the sign correctly.
##
## THE HELPERS FOLLOWED THE CODE THEY SERVE. CPU-7 wrote `s16` and `s8` inside
## `mcf5307/move`; CPU-8 lifted them, with the rest of the machine substrate,
## into `mcf5307/machine`, so this file includes that module instead. The
## boundary values it pins are unchanged, and the reason it pins them is
## unchanged.
##
## They are not part of the C ABI and no C caller names
## them. This file uses `include` and not `import`: `include` puts
## the module's text in this program, which gives the test the private names
## WITHOUT adding an export to the module under test. Exporting the two
## helpers to make them testable would enlarge the module's public surface for
## the test's convenience, and the surface is a thing the project controls.
##
## `include` compiles a second copy of the module into this program alone. The
## copy carries the module's `exportc` register accessors, which is harmless
## here: this program is an executable and links nothing else.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

include mcf5307/machine

var failures: seq[string]
import ./case_sites

var passCount = 0

proc checkImpl(site: int; got: int32; want: int32; label: string) =
  if got == want:
    echo "PASSED  ", label, " = ", want
    inc passCount
    executedSites.add(site)
  else:
    echo "FAILED  ", label, ": expected ", want, ", got ", got
    failures.add(label)
    executedSites.add(site)


template check(got: int32; want: int32; label: string) =
  ## THE CALL SITE IS RECORDED TWICE - once at COMPILE TIME into
  ## `declaredSites` by the `static` below, and once at RUN TIME into
  ## `executedSites`, by the implementation and only when it reaches a
  ## verdict. `tests/case_sites.nim` states what the pair is for and
  ## `tests/case_sites.cmake` states the five rules the driver applies.
  ## The template exists for `instantiationInfo`: a proc cannot see where
  ## it was called from.
  const site = instantiationInfo(-1).line
  static: declaredSites.add(site)
  checkImpl(site, got, want, label)
# ---------------------------------------------------------------------------
# `s16` - the 16-bit displacement of (d16,An), (d16,PC), LINK and the
# absolute-short address, and the .W source of MOVEA.

check(s16(0x0000'u16),      0'i32, "s16(0x0000)")
check(s16(0x7FFF'u16),  32767'i32, "s16(0x7FFF)")
check(s16(0x8000'u16), -32768'i32, "s16(0x8000)")
check(s16(0xFFFF'u16),     -1'i32, "s16(0xFFFF)")

# ---------------------------------------------------------------------------
# `s8` - the 8-bit displacement of an indexed extension word and the immediate
# value of MOVEQ. It takes a whole word and uses the low byte alone, so the
# last two cases carry a high byte that the helper must ignore.

check(s8(0x0000'u16),    0'i32, "s8(0x00)")
check(s8(0x007F'u16),  127'i32, "s8(0x7F)")
check(s8(0x0080'u16), -128'i32, "s8(0x80)")
check(s8(0x00FF'u16),   -1'i32, "s8(0xFF)")
check(s8(0xFF80'u16), -128'i32, "s8(0xFF80), high byte ignored")
check(s8(0x1234'u16),   52'i32, "s8(0x1234), high byte ignored")

# THE THREE REGISTRY LINES. They are DATA AND NOT A VERDICT: this
# program reports what its text declares and what its run adjudicated,
# and the registered test's driver is what compares them - and what
# compares the declared count against the call sites in this file.
# A verdict printed here would be a self-assessment, and a run that
# stopped early would simply not print one.
const declaredCaseSites = declaredSites
const declaredOffGreenPathSites = offGreenPathSites
echo caseSiteLine("declared", "t_sign_extend", declaredCaseSites)
echo caseSiteLine("executed", "t_sign_extend", executedSites)
echo caseSiteLine("off-green-path", "t_sign_extend", declaredOffGreenPathSites)

if failures.len > 0:
  echo ""
  echo "t_sign_extend: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_sign_extend: ", passCount, " cases passed"
