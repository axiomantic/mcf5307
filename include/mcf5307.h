/* mcf5307.h - the C application binary interface of the MCF5307 ColdFire core
 * and the ISP1181 USB device model.
 *
 * The Nim implementation exports these symbols with
 * `{.exportc: "<c name>", cdecl, dynlib.}` and both sides include this file.
 * C++ owns the board and calls down into this interface; nothing here calls
 * up into C++ except through the C function pointers the board installs at
 * construction time.
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
 * `status` IS AN OUT-PARAMETER ON BOTH, and the core writes
 * `MCF5307_BUS_OK` into it before every call. A board that models no fault
 * behaves exactly as it did before the parameter existed: silence means
 * success. A board that writes a non-OK value also logs the address, the
 * width and the direction, so that a fault cannot be reported without a
 * trace of it.
 *
 * On a read fault the returned value is ignored by the core. A board should
 * still return zero, so that a board defect does not depend on an
 * uninitialised value. */
/* `size` is a count of bytes: 1, 2 or 4. */
typedef uint32_t (*mcf5307_read_fn)(void* user, uint32_t addr, int size,
                                    mcf5307_bus_status* status);
/* `size` is a count of bytes: 1, 2 or 4. */
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

/* What a board may call back into while the core is inside its callbacks, and
 * what `mcf5307_reset` does to interrupt state.
 *
 * The acknowledge callback may call `mcf5307_get_reg` and `mcf5307_set_irq`,
 * which is what a chained controller needs. The frame is already stacked when
 * it runs, so the registers it reads are the machine as the handler will find
 * it: a7 holding the address OF the 8-byte frame and not an address below it -
 * the frame's first longword is AT a7 and the stacked program counter at
 * `a7+4` - the program counter register at the handler's first instruction,
 * and the status register already carrying the interrupt priority mask raised
 * to the level being acknowledged.
 *
 * The level-7 arm is decided against the presentation the call has not yet
 * overwritten. `mcf5307_set_irq` arms an edge only on a transition to level 7
 * from a lower presented level, and the level it compares against is the one
 * in effect at entry to that call - the board's own last presentation, which
 * taking an interrupt does not disturb. A board that presents level 7 while
 * level 7 is already the presented level therefore arms nothing; to raise a
 * fresh edge it must present a lower level, or `MCF5307_IRQ_NONE`, and then
 * level 7.
 *
 * The write callback may call `mcf5307_set_irq` as well, and the core reaches
 * that callback while it is stacking the exception frame. An edge armed there
 * arrives before the frame is complete and survives the take in progress, for
 * a different reason on each side of the level split: a take of level 7 clears
 * its own edge latch before it begins stacking, so an edge armed during the
 * stacking is later than that clear; a take of levels 1 to 6 never touches the
 * latch at all. It is taken at the next instruction boundary, which is after
 * the first handler instruction has executed, and it carries the vector and
 * the autovector flag of the presentation that armed it.
 *
 * `mcf5307_reset` inhibits interrupt sampling for the first instruction at
 * `initial_pc`. Reset is an exception, and sampling is inhibited during the
 * first instruction of every exception handler.
 *
 * `mcf5307_reset` also raises the interrupt priority mask to 7 - section
 * 3.5.11, folio 3-17, "sets the processor's interrupt priority mask in the SR
 * to the highest level (level 7)". A board that presents a level 1 to 6
 * interrupt immediately after `mcf5307_reset` does not get it taken at any
 * boundary at all: the mask inhibits every level at or below itself, so
 * nothing under 7 is taken until the program lowers the mask itself. Level 7
 * is therefore the only interrupt the inhibition above can defer, because it
 * is the only one a mask of 7 leaves takeable at all.
 *
 * `mcf5307_reset` ALSO CLEARS THE LATCHED LEVEL-7 EDGE AND THEN RE-OBSERVES
 * THE BOARD'S LAST PRESENTATION. A level 7 request must be held until the
 * second interrupt-acknowledge bus cycle has begun, so an edge whose pin has
 * since been released has nothing left to acknowledge. The
 * presentation itself survives the call: it is the board's state and reset has
 * no newer answer for it. A level 7 STILL PRESENTED across `mcf5307_reset` is
 * armed again, carrying the vector and the autovector flag of that
 * presentation; one the board had already lowered is not. */

/* `MCF5307_MUST_CHECK` marks a return value a caller should not drop. It is a
 * compiler diagnostic and not a mechanism: a toolchain that does not know the
 * attribute expands it to nothing and says so in no way at all, which is the
 * silent-success shape this project refuses to rest anything on. It is here
 * because it costs nothing and catches the mistake early on gcc and clang.
 * What actually protects a caller who
 * ignores the status is described at `mcf5307_runtime_init` below. */
#if defined(__GNUC__) || defined(__clang__)
#  define MCF5307_MUST_CHECK __attribute__((warn_unused_result))
#else
#  define MCF5307_MUST_CHECK
#endif

/* Runs the Nim runtime's initialiser once. It is idempotent, and it is what
 * a C++ caller calls instead of ever naming `NimMain`.
 *
 * Returns 1 when the runtime is initialised and the library is usable, and 0
 * when it is not. It is a truth value and not a POSIX-style error code, which
 * is the convention every other `int` in this header already uses:
 * `mcf5307_set_reg`, `mcf5307_halted`, `isp1181_setup` and
 * `isp1181_set_backend` all answer 1 for yes. Two conventions inside one
 * contract is a footgun a caller reads once and gets backwards.
 *
 * The only way it answers 0 is a stalled one-time latch. The call is
 * idempotent because a latch admits exactly one initialising thread and makes
 * every other caller wait for it. A wait that reaches its deadline gives up,
 * marks the latch abandoned and answers 0 here, and every later call answers 0
 * as well: the state is terminal. One line of diagnosis goes to standard error
 * the first time it happens.
 *
 * This path must never abort. A library has no business killing its host: a
 * plugin that aborts takes the digital audio workstation with it, and the
 * user loses unsaved work that has nothing to do with this core.
 *
 * What happens to a caller that ignores this status, which C permits and no
 * attribute can prevent. `mcf5307_create` and `isp1181_create` ask the same
 * latch themselves, and both return null once it is abandoned. Every remaining
 * call in this header already documents its answer for a nil context - 0, a
 * refusal, or nothing at all - so a caller that dropped the status gets a
 * library that does nothing, and never one that answers out of a runtime that
 * was never initialised. That refusal is the mechanism; this status is the
 * advice that lets a host report the fault instead of guessing at it. */
MCF5307_MUST_CHECK int mcf5307_runtime_init(void);

/* Allocates a core context, or returns null when `mcf5307_runtime_init` has
 * reported a stall. The allocation needs the runtime this call refuses to
 * assume, and a null context is a value every other core call above already
 * answers for. See `mcf5307_runtime_init`. */
mcf5307_ctx* mcf5307_create(void* user,
                            mcf5307_read_fn rd,
                            mcf5307_write_fn wr,
                            mcf5307_iack_fn iack);
void mcf5307_destroy(mcf5307_ctx* ctx);
void mcf5307_reset(mcf5307_ctx* ctx, uint32_t initial_sp, uint32_t initial_pc);

/* Runs until at least `max_cycles` cycles have been spent, and returns the
 * cycles actually spent.
 *
 * THE RETURN MAY BE GREATER THAN `max_cycles`, by up to the cost of one
 * instruction. The budget is tested only at an instruction boundary, so an
 * instruction that starts inside the budget runs to completion and its whole
 * cost is reported. A caller that must not lose the difference carries
 * `spent - max_cycles` forward into its next budget.
 *
 * It returns 0 when nothing ran: a nil or already-halted context, a budget of
 * zero, or a first instruction that trapped. */
uint32_t mcf5307_exec(mcf5307_ctx* ctx, uint32_t max_cycles);

/* The register file, indexed by one integer:
 *
 *     0..7   d0..d7
 *     8..15  a0..a7   (a7 is the single stack pointer - there is no
 *                      supervisor and user stack split on ISA_A)
 *     16     the status register (low 16 bits meaningful)
 *     17     the program counter (read-only through this call)
 *     18     VBR, the vector base register
 *     19     CACR, the cache control register
 *     20     ACR0
 *     21     ACR1
 *     22     RAMBAR0
 *     23     RAMBAR1
 *     24     MBAR
 *
 * INDICES 18 AND ABOVE ARE CONTROL REGISTERS AND NOT PART OF THE REGISTER
 * FILE. `MOVEC` is the machine's own way to write them and it reaches nothing
 * outside a running program, so this call is the only channel a host has: a
 * host that must place the machine at a vector table before the firmware has
 * written one, or that must see where a `MOVEC` put its value, has no other
 * door. Of the seven, only VBR changes what the core does - it bases the
 * exception vector table. The other six hold what was written and are
 * consumed by nothing: this core models neither the cache, nor the access
 * control regions, nor the on-chip SRAM, nor the peripheral base.
 *
 * `mcf5307_reset` sets all seven to zero.
 *
 * `mcf5307_set_reg` returns 1 on success and 0 for an out-of-range index or
 * a nil context; `mcf5307_get_reg` returns the register's value and 0 for an
 * out-of-range index. */
int mcf5307_set_reg(mcf5307_ctx* ctx, int index, uint32_t value);
uint32_t mcf5307_get_reg(const mcf5307_ctx* ctx, int index);

/* The core's run state, and the only way to see it across this interface.
 *
 * `mcf5307_exec` returns a cycle count and nothing else. A cycle count cannot
 * say WHY the core stopped, so these two calls are what tells an instruction
 * that executed from an instruction that trapped.
 *
 * Both return 1 for true and 0 for false, and both return 0 for a nil
 * context - a caller with no context has no halted core and no faulted one.
 *
 * `mcf5307_halted` is 1 when the core has stopped and will run no further
 * instruction until the next `mcf5307_reset`. `mcf5307_exec` returns
 * immediately on a halted context.
 *
 * `mcf5307_faulted` is 1 when the reason for that stop was a fault: a bus
 * error on an operand or instruction access, an illegal instruction word, an
 * illegal effective address for the opcode, an illegal operand size, or a
 * divide by zero. The two are not the same flag. A core can be halted without
 * a fault - a valid opcode that has no executor yet halts and does not
 * fault - so a caller that wants "did this instruction trap" must ask
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

/* Allocates a device handle, or returns null when `mcf5307_runtime_init` has
 * reported a stall, for the reason `mcf5307_create` gives. */
isp1181_ctx* isp1181_create(void* user, isp1181_irq_fn irq, isp1181_tx_fn tx);
void isp1181_destroy(isp1181_ctx* ctx);
uint8_t isp1181_read(isp1181_ctx* ctx, uint32_t addr);
void isp1181_write(isp1181_ctx* ctx, uint32_t addr, uint8_t value);
void isp1181_rx(isp1181_ctx* ctx, int endpoint, const uint8_t* data,
                size_t len);

/* A SET-UP packet from the host, which on the bus is a SETUP token followed
 * by its data stage. It is a separate entry point from `isp1181_rx` and not a
 * flag on it, because a SETUP token is not an ordinary OUT packet: its arrival
 * flushes the control IN buffer, unstalls both control endpoints, and disables
 * the Validate Buffer and Clear Buffer commands on both of them until the
 * firmware issues acknowledge set up.
 *
 * It carries no endpoint argument. A SETUP token is defined only for a control
 * endpoint and this model has exactly one it can receive on, so an endpoint
 * parameter here would have a single legal value - one a computed endpoint
 * could miss with nothing to catch it.
 *
 * Returns 1 when the packet was accepted into the control OUT buffer and 0
 * otherwise. A 0 is not an error code: it is what the device answers for a nil
 * handle, for a zero-length packet, when the stub backend is selected, and
 * when the control OUT buffer already holds an unacknowledged set-up packet -
 * the case the device reports in the OVERWRITE bit, which this model does not
 * track and therefore refuses rather than silently overwriting. */
int isp1181_setup(isp1181_ctx* ctx, const uint8_t* data, size_t len);

/* The host asks the device for a packet, which on the bus is an IN token.
 * `isp1181_rx` is the host handing a packet TO the device and this is its
 * other half, so the two directions are driven the same way: by the host, at
 * the moment the host chooses, with no schedule inside this model.
 *
 * Returns 1 when a packet was handed to `isp1181_tx_fn` before this call
 * returned, and 0 otherwise. The callback is synchronous: a return of 1 means
 * the host has already seen the bytes, and the pointer it was given does not
 * outlive the call.
 *
 * A return of 0 is the NAK and it is not an error code. It is what the device
 * answers when the endpoint has nothing validated, when this model carries no
 * IN buffer for that endpoint, when the handle carries no transmit callback,
 * and for a nil handle. A packet the device could not hand over stays in the
 * buffer, so a later token still collects it: a 0 costs the packet nothing. */
int isp1181_in_token(isp1181_ctx* ctx, int endpoint);

/* The implementation standing behind `isp1181_read`, `isp1181_write` and
 * `isp1181_rx`.
 *
 * The stub is the default and a fresh handle selects it. The stub is a device
 * that is present in the CS3 window and inert: every read answers 0x00,
 * nothing a write leaves becomes readable, no interrupt is raised and neither
 * callback is ever called. The full model is a different device - it answers
 * reads from its register file, keeps the packets `isp1181_rx` delivers, and
 * may call back. */
#define MCF5307_ISP1181_BACKEND_STUB 0
#define MCF5307_ISP1181_BACKEND_FULL_MODEL 1

/* Returns 1 when the handle moved and 0 when the call was refused. A nil
 * handle and a `backend` value neither macro above names are both refused,
 * and a refusal moves nothing. */
int isp1181_set_backend(isp1181_ctx* ctx, int backend);

/* Advances the USB frame number by `sof_frames` USB Start-of-Frame frames.
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
