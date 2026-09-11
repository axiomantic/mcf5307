## `t_sign_extend` - the sign-extension helpers of `mcf5407/machine`.
##
## The negative half is the point. Sign extension reinterprets the bits of
## an unsigned value as a two's-complement signed value of the same width. A
## checked narrowing conversion (`int16(x)`, `int8(x)`) does something
## different: it rejects each value that the signed type cannot hold. Every
## input from 0x8000 to 0xFFFF - that is, every negative displacement - is
## such a value. The library is built with `--panics:on -d:release`, so a
## checked conversion there does not raise a catchable error; it ends the
## process with a `RangeDefect`. This test compiles with the library's own
## flag set.
##
## The helpers are not part of the C ABI and no C caller names
## them. This file uses `include` and not `import`: `include` puts
## the module's text in this program, which gives the test the private names
## without adding an export to the module under test. Exporting the
## helpers to make them testable would enlarge the module's public surface for
## the test's convenience, and the surface is a thing the project controls.
##
## `include` compiles a second copy of the module into this program alone. The
## copy carries the module's `exportc` register accessors, which is harmless
## here: this program is an executable and links nothing else.

include mcf5407/machine

var failures: seq[string]

var passCount = 0

proc checkImpl(got: int32; want: int32; label: string) =
  if got == want:
    echo "PASSED  ", label, " = ", want
    inc passCount
  else:
    echo "FAILED  ", label, ": expected ", want, ", got ", got
    failures.add(label)


template check(got: int32; want: int32; label: string) =
  checkImpl(got, want, label)
check(s16(0x0000'u16),      0'i32, "s16(0x0000)")
check(s16(0x7FFF'u16),  32767'i32, "s16(0x7FFF)")
check(s16(0x8000'u16), -32768'i32, "s16(0x8000)")
check(s16(0xFFFF'u16),     -1'i32, "s16(0xFFFF)")

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
