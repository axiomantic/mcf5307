## The ISP1181's endpoint buffers. Task CPU-22. Design section 9.2,
## `AGENTS.md` section 3.8.
##
## A BUFFER COUNT IS A BEHAVIOUR AND NOT A SIZE, which is why it is a field
## here rather than a comment. A single-buffered endpoint holds ONE packet and
## refuses the next until the first is taken; a double-buffered one holds two.
## CPU-22's block states the consequence of getting it wrong in the generous
## direction: a model with one buffer too many accepts a second packet the
## hardware would have NAKed, and the firmware then sees a transfer the device
## never made.
##
## A PACKET IS ACCEPTED WHOLE OR REFUSED WHOLE. Truncating an oversized packet
## to the buffer's size would hand the firmware a short packet with nothing to
## mark it short, which is the plausible wrong answer this model refuses.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

type
  Fifo* = object
    capacityBytes: int
    bufferCount: int
    packets: seq[seq[uint8]]

proc initFifo*(capacity: int; buffers: int): Fifo =
  Fifo(capacityBytes: capacity, bufferCount: buffers, packets: @[])

proc capacity*(f: Fifo): int = f.capacityBytes
proc buffers*(f: Fifo): int = f.bufferCount
proc pending*(f: Fifo): int = f.packets.len
proc isEmpty*(f: Fifo): bool = f.packets.len == 0
proc isFull*(f: Fifo): bool = f.packets.len >= f.bufferCount

proc accept*(f: var Fifo; data: openArray[uint8]): bool =
  ## `false` is the NAK. The two refusals are kept separate in the caller's
  ## log, because a full buffer is ordinary flow control and an oversized
  ## packet is a fault in whoever produced it.
  if f.isFull or data.len > f.capacityBytes:
    return false
  var packet = newSeq[uint8](data.len)
  for i in 0 ..< data.len:
    packet[i] = data[i]
  f.packets.add(packet)
  true

proc peek*(f: Fifo): tuple[ok: bool, value: uint8] =
  ## The first byte of the oldest packet, without consuming it. An empty
  ## buffer reports `ok: false` rather than a byte, so the caller cannot
  ## mistake a real zero for an absent packet.
  if f.packets.len == 0 or f.packets[0].len == 0:
    return (ok: false, value: 0'u8)
  (ok: true, value: f.packets[0][0])

proc take*(f: var Fifo): seq[uint8] =
  if f.packets.len == 0:
    return @[]
  result = f.packets[0]
  f.packets.delete(0)

proc clear*(f: var Fifo) =
  f.packets.setLen(0)
