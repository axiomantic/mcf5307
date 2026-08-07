import std/strutils
import mcf5307_decode, mcf5307_registers, mcf5307_mac, mcf5307_exec, mcf5307_isp1181

proc NimMain*() {.importc, cdecl.}

type
  mcf5307_ctx* = mcf5307_ctx_obj
  isp1181_ctx* = Isp1181CtxObj

  mcf5307_bus_status* = mcf5307_exec.mcf5307_bus_status
  mcf5307_read_fn* = mcf5307_exec.mcf5307_read_fn
  mcf5307_write_fn* = mcf5307_exec.mcf5307_write_fn
  mcf5307_iack_fn* = mcf5307_exec.mcf5307_iack_fn

  isp1181_irq_fn* = mcf5307_isp1181.Isp1181IrqFn
  isp1181_tx_fn* = mcf5307_isp1181.Isp1181TxFn

# Public C interface procedures exported with {.exportc, cdecl.}

proc mcf5307_runtime_init*() {.exportc, cdecl.} =
  NimMain()
  discard getDecodeTable()

proc mcf5307_create*(user: pointer, rd: mcf5307_read_fn, wr: mcf5307_write_fn, iack: mcf5307_iack_fn): ptr mcf5307_ctx {.exportc, cdecl.} =
  var ctx = createShared(mcf5307_ctx)
  ctx.user = user
  ctx.rd = rd
  ctx.wr = wr
  ctx.iack = iack
  ctx.irqLevel = 0
  ctx.irqVector = 0
  ctx.irqAutovector = 0
  ctx.irqNmiLatched = false
  ctx.halted = false
  ctx.cycles = 0
  reset(ctx.regs, 0u32, 0u32)
  reset(ctx.mac)
  return ctx

proc mcf5307_destroy*(ctx: ptr mcf5307_ctx) {.exportc, cdecl.} =
  if ctx != nil:
    freeShared(ctx)

proc mcf5307_reset*(ctx: ptr mcf5307_ctx, initial_sp: uint32, initial_pc: uint32) {.exportc, cdecl.} =
  if ctx != nil:
    reset(ctx.regs, initial_sp, initial_pc)
    reset(ctx.mac)
    ctx.irqLevel = 0
    ctx.irqVector = 0
    ctx.irqAutovector = 0
    ctx.irqNmiLatched = false
    ctx.halted = false
    ctx.cycles = 0

proc mcf5307_exec*(ctx: ptr mcf5307_ctx, max_cycles: uint32): uint32 {.exportc, cdecl.} =
  return execMcf5307Loop(ctx, max_cycles)

proc mcf5307_set_irq*(ctx: ptr mcf5307_ctx, level: cint, vector: uint8, autovector: cint) {.exportc, cdecl.} =
  setMcf5307IrqState(ctx, level, vector, autovector)

proc mcf5307_state_size*(): csize_t {.exportc, cdecl.} =
  return mcf5307CoreStateSize()

proc mcf5307_state_save*(ctx: ptr mcf5307_ctx, dst: pointer) {.exportc, cdecl.} =
  mcf5307CoreStateSave(ctx, dst)

proc mcf5307_state_load*(ctx: ptr mcf5307_ctx, src: pointer) {.exportc, cdecl.} =
  mcf5307CoreStateLoad(ctx, src)

proc isp1181_create*(user: pointer, irq: isp1181_irq_fn, tx: isp1181_tx_fn): ptr isp1181_ctx {.exportc, cdecl.} =
  return createIsp1181Ctx(user, irq, tx)

proc isp1181_destroy*(ctx: ptr isp1181_ctx) {.exportc, cdecl.} =
  destroyIsp1181Ctx(ctx)

proc isp1181_read*(ctx: ptr isp1181_ctx, `addr`: uint32): uint8 {.exportc, cdecl.} =
  return readIsp1181Reg(ctx, `addr`)

proc isp1181_write*(ctx: ptr isp1181_ctx, `addr`: uint32, value: uint8) {.exportc, cdecl.} =
  writeIsp1181Reg(ctx, `addr`, value)

proc isp1181_rx*(ctx: ptr isp1181_ctx, endpoint: cint, data: ptr uint8, len: csize_t) {.exportc, cdecl.} =
  rxIsp1181Data(ctx, endpoint, data, len)

proc isp1181_tick*(ctx: ptr isp1181_ctx, sof_frames: uint32) {.exportc, cdecl.} =
  tickIsp1181(ctx, sof_frames)

proc isp1181_state_size*(): csize_t {.exportc, cdecl.} =
  return isp1181SnapshotSize()

proc isp1181_state_save*(ctx: ptr isp1181_ctx, dst: pointer) {.exportc, cdecl.} =
  isp1181SnapshotSave(ctx, dst)

proc isp1181_state_load*(ctx: ptr isp1181_ctx, src: pointer) {.exportc, cdecl.} =
  isp1181SnapshotLoad(ctx, src)

# Internal test & evaluation helpers exported for test drivers
proc mcf5307_export_decode_json*(): cstring {.exportc, cdecl.} =
  return cstring(exportDeterminismJson())

proc mcf5307_test_registers_eval*(): cint {.exportc, cdecl.} =
  var regs: Mcf5307Registers
  reset(regs, 0x20000u32, 0x1000u32)
  if regs.sp != 0x20000u32 or regs.pc != 0x1000u32: return 1
  regs.d0 = 0x12345678u32
  if regs.d[0] != 0x12345678u32: return 2
  regs.d7 = 0x11121314u32
  if regs.d[7] != 0x11121314u32: return 3
  regs.a0 = 0x87654321u32
  if regs.a[0] != 0x87654321u32: return 4
  regs.sp = 0x30000u32
  if regs.a7 != 0x30000u32 or regs.a[7] != 0x30000u32: return 5
  writeControlRegister(regs, 0x002u16, 0x10000000u32) # VBR
  if readControlRegister(regs, 0x002u16) != 0x10000000u32 or regs.vbr != 0x10000000u32: return 6
  writeControlRegister(regs, 0xC0Fu16, 0x40000000u32) # MBAR
  if readControlRegister(regs, 0xC0Fu16) != 0x40000000u32 or regs.mbar != 0x40000000u32: return 7
  writeControlRegister(regs, 0xC04u16, 0x20000000u32) # RAMBAR0
  if regs.rambar0 != 0x20000000u32: return 8
  writeControlRegister(regs, 0xC05u16, 0x20000001u32) # RAMBAR1
  if regs.rambar1 != 0x20000001u32: return 9
  writeControlRegister(regs, 0x000u16, 0x01000000u32) # CACR
  if regs.cacr != 0x01000000u32: return 10
  writeControlRegister(regs, 0x004u16, 0x02000000u32) # ACR0
  if regs.acr0 != 0x02000000u32: return 11
  writeControlRegister(regs, 0x005u16, 0x03000000u32) # ACR1
  if regs.acr1 != 0x03000000u32: return 12
  setZero(regs, true)
  setCarry(regs, true)
  if not getZero(regs) or not getCarry(regs): return 13
  return 0

proc mcf5307_test_decode_eval*(): cint {.exportc, cdecl.} =
  let tbl = getDecodeTable()
  if tbl[0x4E71].kind != opNop: return 1
  if tbl[0x4E75].kind != opRts: return 2
  if tbl[0x4AC8].kind != opHalt: return 3
  if tbl[0x4E7B].kind != opMovec: return 4
  if tbl[0x7000].kind != opMoveq: return 5
  if tbl[0x41C0].kind != opLea: return 6
  if tbl[0x4200].kind != opClr: return 7
  let json1 = exportDeterminismJson()
  let json2 = exportDeterminismJson()
  if json1 != json2: return 8
  if not json1.contains("\"architecture\": \"ColdFire_v3\""): return 9
  if not json1.contains("\"determinism_version\": \"M-9\""): return 10
  if not json1.contains("\"total_opcodes\": 65536"): return 11
  return 0
