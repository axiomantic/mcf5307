/* tests/abi_smoke_symbols.inc - THE COMMITTED EXPECTATION OF THE EXPORTED ABI.
 *
 * IT NAMES THE PUBLISHED SYMBOLS THIS PROJECT INTENDS THE LIBRARY TO DEFINE
 * AND EXPORT. It is not the published set of `include/mcf5307.h`, which is
 * larger: a published name a later cpu task has not implemented yet is
 * declared and not defined, and it does not belong here until it is.
 *
 * WHY THIS FILE EXISTS BESIDE A MEASUREMENT. `cmake/Nim.cmake` step 4a
 * measures which published names the library actually defines and exports,
 * with `nm` over a real shared object, and `tests/tests_cpu.cmake` generates
 * the address set of `tests/abi_smoke.cpp` from that measurement. The
 * measurement is the FACT, and it is what keeps the smoke test buildable and
 * growing on its own.
 *
 * A MEASUREMENT ALONE HAS A SILENT FAILURE. It cannot report an ABI addition
 * nobody intended: the measured set simply grows, the generated address set
 * grows with it, the link still succeeds, and the check reports success over
 * an export that should never have shipped.
 *
 * A COMMITTED LIST ALONE HAS THE OPPOSITE SILENT FAILURE. It goes stale the
 * first time somebody forgets to update it, and a roster amended from memory
 * is not a rule.
 *
 * SO THE TWO ARE COMPARED, AND A MISMATCH IN EITHER DIRECTION FAILS THE
 * CONFIGURE STEP AND NAMES THE SYMBOLS. An export that reached the library
 * unintentionally stops the build AND appears here as a diff a reviewer
 * reads. An export that was expected and disappeared - a renamed definition,
 * a dropped one, a changed `exportc` name - is caught by this file and by
 * nothing else, because the generated address set shrank with the ABI and
 * linked clean.
 *
 * THE FILE IS DATA AND NOT C, AND NOTHING COMPILES IT. Every line of it is
 * blank, is a comment, or is exactly `MCF5307_ABI_FN(<identifier>)`. There is
 * no declaration syntax here at all, and no type, no pointer, no attribute
 * and no conditional. That is what lets step 4a read it with no C parser and
 * no preprocessor - the reason step 4a may not trust a regular expression to
 * say what `include/mcf5307.h` declares does not apply to a grammar this
 * small. The reader accepts the entry form ANCHORED at both ends and FAILS
 * THE CONFIGURE STEP over any line it cannot classify, including a line that
 * carries the entry macro with a leading space, a trailing comment or a
 * semicolon. A line it would have to guess at is refused.
 *
 * COMMENTING AN ENTRY OUT IS NOT A WAY TO HIDE IT. The reader skips a
 * comment, so it stops seeing the name, and step 4a then reports that name as
 * an ABI symbol the library exports and this list does not expect. The
 * comparison is against the measurement and never against a count, so a name
 * this file loses by any means is a name step 4a reports as lost.
 *
 * THE ORDER IS THE ORDER `include/mcf5307.h` DECLARES THEM IN. Nothing reads
 * the order: step 4a compares sets. It is kept so that a reader can hold the
 * two files side by side.
 *
 * TO BRING A SYMBOL UNDER THE SMOKE TEST: implement it, so the library
 * defines and exports it, then add one line here. Doing only the first fails
 * the configure step and names the symbol as an unexpected ABI addition.
 * Doing only the second fails the configure step and names it as an expected
 * symbol the ABI does not carry.
 *
 * Do not write a semicolon in this file, in a comment or anywhere else. The
 * step 4a reader splits the text into lines with CMake list semantics.
 *
 * MIT licensed and clean-room with respect to GPL and LGPL code.
 */
MCF5307_ABI_FN(mcf5307_runtime_init)
MCF5307_ABI_FN(mcf5307_create)
MCF5307_ABI_FN(mcf5307_destroy)
MCF5307_ABI_FN(mcf5307_reset)
MCF5307_ABI_FN(mcf5307_exec)
MCF5307_ABI_FN(mcf5307_set_reg)
MCF5307_ABI_FN(mcf5307_get_reg)
MCF5307_ABI_FN(mcf5307_halted)
MCF5307_ABI_FN(mcf5307_faulted)
