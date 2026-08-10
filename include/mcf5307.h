/* mcf5307.h - the C application binary interface of the MCF5307 ColdFire core
 * and the ISP1181 USB device model.
 *
 * The Nim implementation exports these symbols with `{.exportc, cdecl.}` and
 * both sides include this file. C++ owns the board and calls down into this
 * interface; nothing here calls up into C++ except through the C function
 * pointers the board installs at construction time.
 *
 * What crosses: fixed-width integers, opaque pointers to context objects
 * allocated on the other side, raw byte buffers with an explicit length, and
 * `cdecl` C function pointers.
 *
 * What never crosses: a Nim `string`, `seq`, `ref` or any garbage-collected
 * type; a C++ object, reference or virtual table; a Nim closure; and an
 * exception, in either direction. A fault is reported as a plain integer
 * value through an out-parameter, and never as a thrown object.
 *
 * The two state calls exist so that a scheduler can take a snapshot. The
 * snapshot is a flat byte block of a fixed size with a version word in it,
 * and it holds no pointer.
 */

#ifndef MCF5307_H
#define MCF5307_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---------------------------------------------------------------- CPU core */

/* The core's context. It is allocated by `mcf5307_create` and it is opaque:
 * no caller may see inside it, and its definition never appears here. */
typedef struct mcf5307_ctx mcf5307_ctx;

/* The status of one bus access.
 *
 * On real silicon the MCF5307 reports an access error ONLY for an attempted
 * store to write-protected space; an error on an instruction fetch or on an
 * operand read is not possible on this part. `MCF5307_BUS_UNMAPPED` and
 * `MCF5307_BUS_SIZE_ILLEGAL` are therefore a deliberate emulator-only
 * extension, kept because a board that invented an answer for unmapped space
 * would hide exactly the class of firmware bug this core exists to expose.
 * They are reachable only through a board's own address decode. */
typedef enum {
    MCF5307_BUS_OK           = 0, /* the access completed                    */
    MCF5307_BUS_UNMAPPED     = 1, /* no device answers at this address       */
    MCF5307_BUS_SIZE_ILLEGAL = 2, /* the device answers, the width is not
                                     one it accepts                          */
    MCF5307_BUS_FAULT        = 3  /* the device answers and reports a fault
                                     of its own                              */
} mcf5307_bus_status;

/* The board's two memory handlers.
 *
 * `status` is an out-parameter on both, and the core writes
 * `MCF5307_BUS_OK` into it before every call. A board that models no fault
 * behaves exactly as it did before the parameter existed: silence means
 * success. A board that writes a non-OK value also logs the address, the
 * width and the direction, so that a fault cannot be reported without a
 * trace of it.
 *
 * On a read fault the returned value is ignored by the core. A board should
 * still return zero, so that a board defect does not depend on an
 * uninitialised value. */
typedef uint32_t (*mcf5307_read_fn)(void* user, uint32_t addr, int size,
                                    mcf5307_bus_status* status);
typedef void (*mcf5307_write_fn)(void* user, uint32_t addr, int size,
                                 uint32_t value, mcf5307_bus_status* status);

/* Interrupt acknowledge. The core calls it once, after it has stacked the
 * exception frame and before it fetches the first handler instruction.
 *
 * An edge-triggered source on the board's own side is cleared here; that is
 * what this callback exists for. A level-triggered source at levels 1 to 6
 * is NOT cleared here - the real pin is still asserted at that moment, and
 * the source drops when the device model clears its own condition. A level 7
 * source is not cleared here either, because the core clears its own edge
 * latch when it takes the interrupt. */
typedef void (*mcf5307_iack_fn)(void* user, int level, uint8_t vector);

/* Runs the Nim runtime's initialiser once. It is idempotent, and it is what
 * a C++ caller calls instead of ever naming `NimMain`. */
void mcf5307_runtime_init(void);

mcf5307_ctx* mcf5307_create(void* user,
                            mcf5307_read_fn rd,
                            mcf5307_write_fn wr,
                            mcf5307_iack_fn iack);
void mcf5307_destroy(mcf5307_ctx* ctx);
void mcf5307_reset(mcf5307_ctx* ctx, uint32_t initial_sp, uint32_t initial_pc);

/* Runs at most `max_cycles` cycles and returns the cycles actually spent. */
uint32_t mcf5307_exec(mcf5307_ctx* ctx, uint32_t max_cycles);

/* The register file, indexed by one integer:
 *
 *     0..7   d0..d7
 *     8..15  a0..a7   (a7 is the single stack pointer - there is no
 *                      supervisor and user stack split on ISA_A)
 *     16     the status register (low 16 bits meaningful)
 *     17     the program counter (read-only through this call)
 *
 * `mcf5307_set_reg` returns 1 on success and 0 for an out-of-range index or
 * a nil context; `mcf5307_get_reg` returns the register's value and 0 for an
 * out-of-range index. These are the harness's one register bridge: the
 * conformance runner (CPU-5) sets the `initial` registers through them and
 * reads the `expected` registers back. The core's instruction groups
 * (CPU-7..10) own the register file this accessor exposes. */
int mcf5307_set_reg(mcf5307_ctx* ctx, int index, uint32_t value);
uint32_t mcf5307_get_reg(const mcf5307_ctx* ctx, int index);

/* THE CORE'S RUN STATE, AND THE ONLY WAY TO SEE IT ACROSS THIS INTERFACE.
 *
 * `mcf5307_exec` returns a cycle count and nothing else. A cycle count cannot
 * say WHY the core stopped, so before these two calls existed a caller that
 * went through this header could not tell an instruction that executed from
 * an instruction that trapped. The conformance runner (conformance/runner.cpp)
 * measured exactly that gap: a case whose instruction traps still passed
 * whenever the registers it named happened to hold the expected values, which
 * is every case that expects a register to be UNCHANGED. The Nim-side tests
 * (`tests/t_alu.nim`, `tests/t_move.nim`) assert the same thing through
 * `ctx.fault` because they reach the context directly; a C++ caller cannot,
 * and these two calls are that missing channel.
 *
 * Both return 1 for true and 0 for false, and both return 0 for a nil
 * context - a caller with no context has no halted core and no faulted one.
 *
 * `mcf5307_halted` is 1 when the core has stopped and will run no further
 * instruction until the next `mcf5307_reset`. `mcf5307_exec` returns
 * immediately on a halted context.
 *
 * `mcf5307_faulted` is 1 when the reason for that stop was a FAULT: a bus
 * error on an operand or instruction access, an illegal instruction word, an
 * illegal effective address for the opcode, an illegal operand size, or a
 * divide by zero. THE TWO ARE NOT THE SAME FLAG. A core can be halted without
 * a fault - a valid opcode whose semantics a later task owns halts and does
 * not fault - so a caller that wants "did this instruction trap" must ask
 * `mcf5307_faulted`, and a caller that wants "may I run more" must ask
 * `mcf5307_halted`. A faulted core is always also halted.
 *
 * Neither call changes any state, which is why both take a const context. */
int mcf5307_halted(const mcf5307_ctx* ctx);
int mcf5307_faulted(const mcf5307_ctx* ctx);

/* The named zero of the `level` argument below: no interrupt is pending. */
#define MCF5307_IRQ_NONE 0

/* Presents the board's CURRENT highest-priority pending interrupt. The board
 * owns the pending bit of each source and the arbitration among them; the
 * core owns the mask against the interrupt priority level in the status
 * register, and the exception frame.
 *
 * `level` is `MCF5307_IRQ_NONE` for none, or 1 to 7. `vector` is the vector
 * number when `autovector` is zero; a non-zero `autovector` makes the core
 * use the autovector for `level` and ignore `vector`. The call is
 * IDEMPOTENT, so a board may call it unconditionally after every
 * recomputation.
 *
 * For levels 1 to 6 the core latches nothing: the arguments of the last call
 * are the whole truth until the next call, exactly as hardware compares a
 * level on a pin, and deasserting is a call with a lower level or with
 * `MCF5307_IRQ_NONE`. Level 7 is different - it is edge-triggered and
 * non-maskable on this part, so the core latches a rising edge to level 7,
 * a level 7 held across two calls arms no second interrupt, and the core
 * clears the latch when it takes the interrupt. */
void mcf5307_set_irq(mcf5307_ctx* ctx, int level, uint8_t vector,
                     int autovector);

size_t mcf5307_state_size(void);
void mcf5307_state_save(const mcf5307_ctx* ctx, void* dst);
void mcf5307_state_load(mcf5307_ctx* ctx, const void* src);

/* ------------------------------------------------ ISP1181 USB device model */

typedef struct isp1181_ctx isp1181_ctx;

/* The logical interrupt state of the device, and NOT the pin state. 1 means
 * the device requests service and 0 means it does not. The board owns the
 * inversion to the active-low pin, not this model. The source is
 * level-triggered: it stays 1 until the firmware clears the condition inside
 * the device. */
typedef void (*isp1181_irq_fn)(void* user, int asserted);
typedef void (*isp1181_tx_fn)(void* user, int endpoint,
                              const uint8_t* data, size_t len);

isp1181_ctx* isp1181_create(void* user, isp1181_irq_fn irq, isp1181_tx_fn tx);
void isp1181_destroy(isp1181_ctx* ctx);
uint8_t isp1181_read(isp1181_ctx* ctx, uint32_t addr);
void isp1181_write(isp1181_ctx* ctx, uint32_t addr, uint8_t value);
void isp1181_rx(isp1181_ctx* ctx, int endpoint, const uint8_t* data,
                size_t len);

/* Advances the USB frame counter and the SOFTCT timer by `sof_frames` USB
 * Start-of-Frame frames.
 *
 * One SOF frame is 1 ms. The unit is NOT the 96 kHz audio frame. At a 96 kHz
 * frame rate and a scheduler quantum of one audio frame, one SOF frame spans
 * 96 quanta, and the board calls this with `sof_frames` = 1 once for each
 * virtual millisecond. */
void isp1181_tick(isp1181_ctx* ctx, uint32_t sof_frames);

size_t isp1181_state_size(void);
void isp1181_state_save(const isp1181_ctx* ctx, void* dst);
void isp1181_state_load(isp1181_ctx* ctx, const void* src);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* MCF5307_H */
