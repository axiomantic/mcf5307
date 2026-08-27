/* tests/abi_smoke_symbols.inc - the committed expectation of the exported ABI.
 *
 * It names the published symbols this project intends the library to define
 * and export. It is not the published set of `include/mcf5307.h`, which is
 * larger: a published name that is not implemented yet is declared and not
 * defined, and it does not belong here until it is.
 *
 * `cmake/Nim.cmake` step 4a measures which published names the library
 * actually defines and exports, with `nm` over a real shared object, and
 * `tests/tests_cpu.cmake` generates the address set of `tests/abi_smoke.cpp`
 * from that measurement.
 *
 * A measurement alone has a silent failure. It cannot report an ABI addition
 * nobody intended: the measured set simply grows, the generated address set
 * grows with it, the link still succeeds, and the check reports success over
 * an export that should never have shipped. A committed list alone has the
 * opposite silent failure: it goes stale the first time somebody forgets to
 * update it.
 *
 * So the two are compared, and a mismatch in either direction fails the
 * configure step and names the symbols. An export that was expected and
 * disappeared - a renamed definition, a dropped one, a changed `exportc`
 * name - is caught by this file and by nothing else, because the generated
 * address set shrank with the ABI and linked clean.
 *
 * The file is data and not C, and nothing compiles it. Every line of it is
 * blank, is a comment, or is exactly `MCF5307_ABI_FN(<identifier>)`. There is
 * no declaration syntax here at all, and no type, no pointer, no attribute
 * and no conditional. That is what lets step 4a read it with no C parser and
 * no preprocessor. The reader accepts the entry form anchored at both ends
 * and fails the configure step over any line it cannot classify, including a
 * line that carries the entry macro with a leading space, a trailing comment
 * or a semicolon.
 *
 * Commenting an entry out is not a way to hide it. The reader skips a
 * comment, so it stops seeing the name, and step 4a then reports that name as
 * an ABI symbol the library exports and this list does not expect.
 *
 * The order is the order `include/mcf5307.h` declares them in. Nothing reads
 * the order: step 4a compares sets. It is kept so that a reader can hold the
 * two files side by side.
 *
 * To bring a symbol under the smoke test: implement it, so the library
 * defines and exports it, then add one line here. Doing only the first fails
 * the configure step and names the symbol as an unexpected ABI addition.
 * Doing only the second fails the configure step and names it as an expected
 * symbol the ABI does not carry.
 *
 * Do not write a semicolon in this file, in a comment or anywhere else. The
 * step 4a reader splits the text into lines with CMake list semantics.
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
MCF5307_ABI_FN(mcf5307_set_irq)
MCF5307_ABI_FN(mcf5307_state_size)
MCF5307_ABI_FN(mcf5307_state_save)
MCF5307_ABI_FN(mcf5307_state_load)
MCF5307_ABI_FN(isp1181_create)
MCF5307_ABI_FN(isp1181_destroy)
MCF5307_ABI_FN(isp1181_read)
MCF5307_ABI_FN(isp1181_write)
MCF5307_ABI_FN(isp1181_rx)
MCF5307_ABI_FN(isp1181_in_token)
MCF5307_ABI_FN(isp1181_set_backend)
MCF5307_ABI_FN(isp1181_tick)
MCF5307_ABI_FN(isp1181_state_size)
MCF5307_ABI_FN(isp1181_state_save)
MCF5307_ABI_FN(isp1181_state_load)
