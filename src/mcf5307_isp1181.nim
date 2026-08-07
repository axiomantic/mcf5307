# src/mcf5307_isp1181.nim - ISP1181 USB Device Controller CS3 Bridge implementation

type
  Isp1181IrqFn* = proc(user: pointer, asserted: cint) {.cdecl.}
  Isp1181TxFn* = proc(user: pointer, endpoint: cint, data: ptr uint8, len: csize_t) {.cdecl.}

  EndpointFifo = object
    data: array[256, uint8]
    head: uint16
    tail: uint16
    count: uint16

  Isp1181CtxObj* = object
    user*: pointer
    irqFn*: Isp1181IrqFn
    txFn*: Isp1181TxFn
    currentReg*: uint8
    addressReg*: uint8
    modeReg*: uint16
    intEnableReg*: uint32
    intStatusReg*: uint32
    frameNumber*: uint16
    selectedEp*: uint8
    irqAsserted*: bool
    outFifos*: array[16, EndpointFifo]
    inFifos*: array[16, EndpointFifo]

  Isp1181Snapshot* {.packed.} = object
    magic*: uint32             # 0x11815307
    version*: uint32           # 1
    currentReg*: uint8
    addressReg*: uint8
    modeReg*: uint16
    intEnableReg*: uint32
    intStatusReg*: uint32
    frameNumber*: uint16
    selectedEp*: uint8
    irqAsserted*: uint8
    reserved*: array[3, uint8]
    fifosData*: array[32 * 256, uint8] # 16 out + 16 in
    fifosCount*: array[32, uint16]

proc fifoPush(fifo: var EndpointFifo, val: uint8) =
  if fifo.count < 256:
    fifo.data[fifo.tail] = val
    fifo.tail = (fifo.tail + 1) and 0xFFu16
    fifo.count += 1

proc fifoPop(fifo: var EndpointFifo): uint8 =
  if fifo.count > 0:
    result = fifo.data[fifo.head]
    fifo.head = (fifo.head + 1) and 0xFFu16
    fifo.count -= 1
  else:
    result = 0u8

proc fifoClear(fifo: var EndpointFifo) =
  fifo.head = 0
  fifo.tail = 0
  fifo.count = 0

proc checkIrq(ctx: ptr Isp1181CtxObj) =
  let pending = (ctx.intStatusReg and ctx.intEnableReg) != 0u32
  if pending != ctx.irqAsserted:
    ctx.irqAsserted = pending
    if ctx.irqFn != nil:
      ctx.irqFn(ctx.user, if pending: cint(1) else: cint(0))

proc createIsp1181Ctx*(user: pointer, irq: Isp1181IrqFn, tx: Isp1181TxFn): ptr Isp1181CtxObj =
  var ctx = createShared(Isp1181CtxObj)
  ctx.user = user
  ctx.irqFn = irq
  ctx.txFn = tx
  ctx.currentReg = 0u8
  ctx.addressReg = 0u8
  ctx.modeReg = 0u16
  ctx.intEnableReg = 0u32
  ctx.intStatusReg = 0u32
  ctx.frameNumber = 0u16
  ctx.selectedEp = 0u8
  ctx.irqAsserted = false
  for i in 0..15:
    fifoClear(ctx.outFifos[i])
    fifoClear(ctx.inFifos[i])
  return ctx

proc destroyIsp1181Ctx*(ctx: ptr Isp1181CtxObj) =
  if ctx != nil:
    freeShared(ctx)

proc readIsp1181Reg*(ctx: ptr Isp1181CtxObj, `addr`: uint32): uint8 =
  if ctx == nil: return 0u8

  let isCommandPort = (`addr` and 1u32) != 0u32 or (`addr` and 2u32) != 0u32
  if isCommandPort:
    return ctx.currentReg
  else:
    case ctx.currentReg
    of 0x00u8..0x05u8, 0x07u8, 0x09u8, 0x0Bu8, 0x0Du8, 0x0Fu8, 0x20u8..0x2Fu8: # Endpoint buffer read
      let ep = int(ctx.currentReg and 0x0Fu8)
      result = fifoPop(ctx.outFifos[ep])
      if ctx.outFifos[ep].count == 0:
        ctx.intStatusReg = ctx.intStatusReg and (not (1u32 shl ep))
        checkIrq(ctx)
    of 0x70u8, 0xB0u8: # Chip ID
      result = 0x11u8
    of 0xB1u8, 0x0Cu8: # Mode register low
      result = uint8(ctx.modeReg and 0xFFu16)
    of 0xB2u8, 0x0Eu8: # Interrupt enable low
      result = uint8(ctx.intEnableReg and 0xFFu32)
    of 0xB4u8, 0x08u8: # Interrupt status low (clears on read)
      result = uint8(ctx.intStatusReg and 0xFFu32)
      ctx.intStatusReg = ctx.intStatusReg and 0xFFFFFF00u32
      checkIrq(ctx)
    of 0xB6u8, 0x0Au8: # SOF frame number low
      result = uint8(ctx.frameNumber and 0xFFu16)
    of 0xD0u8, 0x06u8: # Address register
      result = ctx.addressReg
    else:
      result = 0u8

proc writeIsp1181Reg*(ctx: ptr Isp1181CtxObj, `addr`: uint32, value: uint8) =
  if ctx == nil: return

  let isCommandPort = (`addr` and 1u32) != 0u32 or (`addr` and 2u32) != 0u32
  if isCommandPort:
    ctx.currentReg = value
    if value == 0xF4u8 or value == 0xFFu8: # Soft reset
      ctx.addressReg = 0u8
      ctx.modeReg = 0u16
      ctx.intEnableReg = 0u32
      ctx.intStatusReg = 0u32
      ctx.frameNumber = 0u16
      ctx.irqAsserted = false
      for i in 0..15:
        fifoClear(ctx.outFifos[i])
        fifoClear(ctx.inFifos[i])
      checkIrq(ctx)
    elif (value and 0xF0u8) == 0x10u8: # Select & validate IN Endpoint for TX
      let ep = int(value and 0x0Fu8)
      ctx.selectedEp = uint8(ep)
      if ctx.inFifos[ep].count > 0 and ctx.txFn != nil:
        var buf: array[256, uint8]
        let len = ctx.inFifos[ep].count
        for i in 0..<int(len):
          buf[i] = fifoPop(ctx.inFifos[ep])
        ctx.txFn(ctx.user, cint(ep), addr buf[0], csize_t(len))
  else:
    case ctx.currentReg
    of 0x00u8..0x05u8, 0x07u8, 0x09u8, 0x0Bu8, 0x0Du8, 0x0Fu8, 0x20u8..0x2Fu8: # Endpoint buffer write
      let ep = int(ctx.currentReg and 0x0Fu8)
      fifoPush(ctx.inFifos[ep], value)
    of 0xB1u8, 0x0Cu8: # Mode register
      ctx.modeReg = uint16(value)
    of 0xB2u8, 0x0Eu8: # Interrupt enable
      ctx.intEnableReg = uint32(value)
      checkIrq(ctx)
    of 0xB4u8, 0x08u8: # Interrupt status clear
      ctx.intStatusReg = ctx.intStatusReg and (not uint32(value))
      checkIrq(ctx)
    of 0xD0u8, 0x06u8: # Address register
      ctx.addressReg = value
    else:
      discard

proc rxIsp1181Data*(ctx: ptr Isp1181CtxObj, endpoint: cint, data: ptr uint8, len: csize_t) =
  if ctx == nil or endpoint < 0 or endpoint > 15 or data == nil or len == 0: return

  let ep = int(endpoint)
  let p = cast[ptr UncheckedArray[uint8]](data)
  for i in 0..<int(len):
    fifoPush(ctx.outFifos[ep], p[i])

  ctx.intStatusReg = ctx.intStatusReg or (1u32 shl ep)
  checkIrq(ctx)

proc tickIsp1181*(ctx: ptr Isp1181CtxObj, sof_frames: uint32) =
  if ctx == nil or sof_frames == 0: return

  ctx.frameNumber = uint16((uint32(ctx.frameNumber) + sof_frames) and 0xFFFFu32)
  ctx.intStatusReg = ctx.intStatusReg or (1u32 shl 16)
  checkIrq(ctx)

proc isp1181SnapshotSize*(): csize_t =
  return csize_t(sizeof(Isp1181Snapshot))

proc isp1181SnapshotSave*(ctx: ptr Isp1181CtxObj, dst: pointer) =
  if ctx == nil or dst == nil: return

  var snap = cast[ptr Isp1181Snapshot](dst)
  snap.magic = 0x11815307u32
  snap.version = 1u32
  snap.currentReg = ctx.currentReg
  snap.addressReg = ctx.addressReg
  snap.modeReg = ctx.modeReg
  snap.intEnableReg = ctx.intEnableReg
  snap.intStatusReg = ctx.intStatusReg
  snap.frameNumber = ctx.frameNumber
  snap.selectedEp = ctx.selectedEp
  snap.irqAsserted = if ctx.irqAsserted: 1u8 else: 0u8

  for i in 0..15:
    let outIdx = i
    let inIdx = 16 + i
    snap.fifosCount[outIdx] = ctx.outFifos[i].count
    for j in 0..<int(ctx.outFifos[i].count):
      let pos = (ctx.outFifos[i].head + uint16(j)) and 0xFFu16
      snap.fifosData[outIdx * 256 + j] = ctx.outFifos[i].data[pos]

    snap.fifosCount[inIdx] = ctx.inFifos[i].count
    for j in 0..<int(ctx.inFifos[i].count):
      let pos = (ctx.inFifos[i].head + uint16(j)) and 0xFFu16
      snap.fifosData[inIdx * 256 + j] = ctx.inFifos[i].data[pos]

proc isp1181SnapshotLoad*(ctx: ptr Isp1181CtxObj, src: pointer) =
  if ctx == nil or src == nil: return

  let snap = cast[ptr Isp1181Snapshot](src)
  if snap.magic != 0x11815307u32 or snap.version != 1u32: return

  ctx.currentReg = snap.currentReg
  ctx.addressReg = snap.addressReg
  ctx.modeReg = snap.modeReg
  ctx.intEnableReg = snap.intEnableReg
  ctx.intStatusReg = snap.intStatusReg
  ctx.frameNumber = snap.frameNumber
  ctx.selectedEp = snap.selectedEp
  ctx.irqAsserted = snap.irqAsserted != 0u8

  for i in 0..15:
    fifoClear(ctx.outFifos[i])
    let outIdx = i
    let outCount = snap.fifosCount[outIdx]
    for j in 0..<int(outCount):
      fifoPush(ctx.outFifos[i], snap.fifosData[outIdx * 256 + j])

    fifoClear(ctx.inFifos[i])
    let inIdx = 16 + i
    let inCount = snap.fifosCount[inIdx]
    for j in 0..<int(inCount):
      fifoPush(ctx.inFifos[i], snap.fifosData[inIdx * 256 + j])

  checkIrq(ctx)
