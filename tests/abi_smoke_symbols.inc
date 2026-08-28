/* tests/abi_smoke_symbols.inc - THE LIST OF PUBLISHED SYMBOLS THE SMOKE TEST
 * TAKES THE ADDRESS OF. It is the only place that list exists.
 *
 * THE FILE IS DATA AND NOT C. Every line of it is blank, is a comment, or is
 * exactly `MCF5307_ABI_FN(<identifier>)`. There is no declaration syntax here
 * at all, and there is no type, no pointer, no attribute and no conditional.
 * That is deliberate: `tests/abi_smoke.cpp` includes this file TWICE with two
 * different definitions of `MCF5307_ABI_FN`, and `cmake/Nim.cmake` step 4a
 * READS THE SAME FILE and compares the names in it against the published set
 * it parses out of `include/mcf5307.h` with a C compiler.
 *
 * WHY A SECOND READER OF THIS FILE IS SAFE WHEN A SECOND READER OF THE
 * CONTRACT HEADER IS NOT. Step 4a says at length why a regular expression may
 * not be trusted to say what a C header declares, and the calibration header
 * in the build tree proves it on every configure run. NONE OF THOSE SHAPES
 * CAN OCCUR HERE. This file's whole grammar is blank lines, comment lines and the one
 * macro form above. The step 4a reader accepts that form ANCHORED at both
 * ends and FAILS THE CONFIGURE STEP over any line it cannot classify,
 * including a line that carries the entry macro with a leading space, a
 * trailing comment or a semicolon - shapes the C++ side would expand and the
 * reader would not.
 *
 * COMMENTING AN ENTRY OUT IS NOT A WAY TO HIDE IT. Both readers skip a
 * comment, so both stop seeing the name, and step 4a then reports it as a
 * symbol the contract publishes and this list does not name. The comparison
 * is against `include/mcf5307.h` and never against a count, so a name this
 * file loses by any means is a name step 4a reports as lost.
 *
 * THE ORDER IS THE ORDER `include/mcf5307.h` DECLARES THEM IN. Nothing reads
 * the order: the C++ side takes an address per line and the CMake side
 * compares sets. It is kept so that a reader can hold the two files side by
 * side.
 *
 * TO ADD A SYMBOL: add its declaration to `include/mcf5307.h`, then add one
 * line here. Doing only the first fails the configure step and names the
 * symbol. Doing only the second fails the configure step and names it too,
 * and would not compile either.
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
MCF5307_ABI_FN(mcf5307_set_irq)
MCF5307_ABI_FN(mcf5307_state_size)
MCF5307_ABI_FN(mcf5307_state_save)
MCF5307_ABI_FN(mcf5307_state_load)
MCF5307_ABI_FN(isp1181_create)
MCF5307_ABI_FN(isp1181_destroy)
MCF5307_ABI_FN(isp1181_read)
MCF5307_ABI_FN(isp1181_write)
MCF5307_ABI_FN(isp1181_rx)
MCF5307_ABI_FN(isp1181_setup)
MCF5307_ABI_FN(isp1181_in_token)
MCF5307_ABI_FN(isp1181_set_backend)
MCF5307_ABI_FN(isp1181_tick)
MCF5307_ABI_FN(isp1181_log_written)
MCF5307_ABI_FN(isp1181_log_retained)
MCF5307_ABI_FN(isp1181_log_line)
MCF5307_ABI_FN(isp1181_config_slots)
MCF5307_ABI_FN(isp1181_config_slot)
MCF5307_ABI_FN(isp1181_slot_buffer)
MCF5307_ABI_FN(isp1181_report)
MCF5307_ABI_FN(isp1181_state_size)
MCF5307_ABI_FN(isp1181_state_save)
MCF5307_ABI_FN(isp1181_state_load)
