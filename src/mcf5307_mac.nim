# src/mcf5307_mac.nim - MCF5307 MAC / EMAC Unit implementation

type
  Mcf5307Mac* = object
    acc*: uint32
    macsr*: uint32
    mask*: uint32

proc reset*(mac: var Mcf5307Mac) =
  mac.acc = 0u32
  mac.macsr = 0u32
  mac.mask = 0xFFFFFFFFu32

proc mpyW*(mac: var Mcf5307Mac, val1: uint16, val2: uint16, isSigned: bool = true) =
  if isSigned:
    let s1 = int32(int16(val1))
    let s2 = int32(int16(val2))
    mac.acc = uint32(s1 * s2)
  else:
    let u1 = uint32(val1)
    let u2 = uint32(val2)
    mac.acc = u1 * u2

proc mpyL*(mac: var Mcf5307Mac, val1: uint32, val2: uint32, isSigned: bool = true) =
  if isSigned:
    let s1 = int64(int32(val1))
    let s2 = int64(int32(val2))
    mac.acc = uint32(s1 * s2)
  else:
    mac.acc = val1 * val2

proc macW*(mac: var Mcf5307Mac, val1: uint16, val2: uint16, isSigned: bool = true) =
  var prod: uint32
  if isSigned:
    let s1 = int32(int16(val1))
    let s2 = int32(int16(val2))
    prod = uint32(s1 * s2)
  else:
    prod = uint32(val1) * uint32(val2)
  mac.acc = mac.acc + prod

proc macL*(mac: var Mcf5307Mac, val1: uint32, val2: uint32, isSigned: bool = true) =
  var prod: uint32
  if isSigned:
    let s1 = int64(int32(val1))
    let s2 = int64(int32(val2))
    prod = uint32(s1 * s2)
  else:
    prod = val1 * val2
  mac.acc = mac.acc + prod

proc msacW*(mac: var Mcf5307Mac, val1: uint16, val2: uint16, isSigned: bool = true) =
  var prod: uint32
  if isSigned:
    let s1 = int32(int16(val1))
    let s2 = int32(int16(val2))
    prod = uint32(s1 * s2)
  else:
    prod = uint32(val1) * uint32(val2)
  mac.acc = mac.acc - prod

proc msacL*(mac: var Mcf5307Mac, val1: uint32, val2: uint32, isSigned: bool = true) =
  var prod: uint32
  if isSigned:
    let s1 = int64(int32(val1))
    let s2 = int64(int32(val2))
    prod = uint32(s1 * s2)
  else:
    prod = val1 * val2
  mac.acc = mac.acc - prod

proc readMacRegister*(mac: Mcf5307Mac, regId: uint8): uint32 =
  case regId and 0x3u8
  of 0u8: mac.macsr
  of 1u8: mac.mask
  of 3u8: mac.acc
  else: 0u32

proc writeMacRegister*(mac: var Mcf5307Mac, regId: uint8, val: uint32) =
  case regId and 0x3u8
  of 0u8: mac.macsr = val
  of 1u8: mac.mask = val
  of 3u8: mac.acc = val
  else: discard
