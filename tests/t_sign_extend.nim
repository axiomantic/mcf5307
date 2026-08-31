## `t_sign_extend` - the sign-extension helpers of `mcf5307/machine`.
##
## `s16` and `s8` turn a displacement or an immediate value from the
## instruction stream into the signed 32-bit value the address arithmetic
## adds. The boundary values of each helper are asserted with their exact
## results:
##
##   s16  0x0000 -> 0        the low end of the positive half
##        0x7FFF -> 32767    the largest positive value
##        0x8000 -> -32768   the first negative value
##        0xFFFF -> -1       the last negative value
##
##   s8   0x00 -> 0, 0x7F -> 127, 0x80 -> -128, 0xFF -> -1, and the same
##        again for the two values above with a high byte that `s8` must
##        ignore.
##
## The negative half is the point. Sign extension reinterprets the bits of an
## unsigned value as a two's-complement signed value of the same width. A
## checked narrowing conversion (`int16(x)`, `int8(x)`) does something
## different: it rejects each value that the signed type cannot hold. Every
## input from 0x8000 to 0xFFFF - that is, every negative displacement - is
## such a value. The library is built with `--panics:on -d:release`, so a
## checked conversion there does not raise a catchable error; it ends the
## process with a `RangeDefect`. This test compiles with the library's own
## flag set, thus a helper that went back to a checked conversion kills this
## program and the driver reports the failure.
##
## The positive cases are the positive control. Without them a helper that
## returned a constant 0, or a program that cannot run at all, would not be
## separable from a helper that extends the sign correctly.
##
## The helpers are not part of the C ABI and no C caller names
## them. This file uses `include` and not `import`: `include` puts
## the module's text in this program, which gives the test the private names
## WITHOUT adding an export to the module under test. Exporting the two
## helpers to make them testable would enlarge the module's public surface for
## the test's convenience, and the surface is a thing the project controls.
##
## `include` compiles a second copy of the module into this program alone. The
## copy carries the module's `exportc` register accessors, which is harmless
## here: this program is an executable and links nothing else.

include mcf5307/machine

var failures: seq[string]
var passCount = 0

proc check(got: int32; want: int32; label: string) =
  if got == want:
    echo "PASSED  ", label, " = ", want
    inc passCount
  else:
    echo "FAILED  ", label, ": expected ", want, ", got ", got
    failures.add(label)

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

if failures.len > 0:
  echo ""
  echo "t_sign_extend: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_sign_extend: ", passCount, " cases passed"
