# src/mcf5307_registers.nim - MCF5307 ColdFire v3 Register Set implementation

type
  Mcf5307Registers* = object
    d*: array[8, uint32]       # Data registers d0..d7
    a*: array[8, uint32]       # Address registers a0..a7
    pc*: uint32                # Program Counter
    sr*: uint16                # Status Register
    vbr*: uint32               # Vector Base Register
    mbar*: uint32              # Module Base Address Register
    rambar0*: uint32           # RAM Base Address Register 0
    rambar1*: uint32           # RAM Base Address Register 1
    cacr*: uint32              # Cache Control Register
    acr0*: uint32              # Access Control Register 0
    acr1*: uint32              # Access Control Register 1

# Stack Pointer (sp) template alias for a[7]
template sp*(regs: Mcf5307Registers): uint32 = regs.a[7]
template `sp=`*(regs: var Mcf5307Registers, val: uint32) = regs.a[7] = val

# Convenient individual data register getters/setters
proc d0*(regs: Mcf5307Registers): uint32 {.inline.} = regs.d[0]
proc d1*(regs: Mcf5307Registers): uint32 {.inline.} = regs.d[1]
proc d2*(regs: Mcf5307Registers): uint32 {.inline.} = regs.d[2]
proc d3*(regs: Mcf5307Registers): uint32 {.inline.} = regs.d[3]
proc d4*(regs: Mcf5307Registers): uint32 {.inline.} = regs.d[4]
proc d5*(regs: Mcf5307Registers): uint32 {.inline.} = regs.d[5]
proc d6*(regs: Mcf5307Registers): uint32 {.inline.} = regs.d[6]
proc d7*(regs: Mcf5307Registers): uint32 {.inline.} = regs.d[7]

proc `d0=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.d[0] = val
proc `d1=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.d[1] = val
proc `d2=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.d[2] = val
proc `d3=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.d[3] = val
proc `d4=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.d[4] = val
proc `d5=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.d[5] = val
proc `d6=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.d[6] = val
proc `d7=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.d[7] = val

# Convenient individual address register getters/setters
proc a0*(regs: Mcf5307Registers): uint32 {.inline.} = regs.a[0]
proc a1*(regs: Mcf5307Registers): uint32 {.inline.} = regs.a[1]
proc a2*(regs: Mcf5307Registers): uint32 {.inline.} = regs.a[2]
proc a3*(regs: Mcf5307Registers): uint32 {.inline.} = regs.a[3]
proc a4*(regs: Mcf5307Registers): uint32 {.inline.} = regs.a[4]
proc a5*(regs: Mcf5307Registers): uint32 {.inline.} = regs.a[5]
proc a6*(regs: Mcf5307Registers): uint32 {.inline.} = regs.a[6]
proc a7*(regs: Mcf5307Registers): uint32 {.inline.} = regs.a[7]

proc `a0=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.a[0] = val
proc `a1=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.a[1] = val
proc `a2=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.a[2] = val
proc `a3=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.a[3] = val
proc `a4=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.a[4] = val
proc `a5=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.a[5] = val
proc `a6=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.a[6] = val
proc `a7=`*(regs: var Mcf5307Registers, val: uint32) {.inline.} = regs.a[7] = val

# Condition Code Register (CCR) masks in SR
const
  FLAG_C* = 0x01u16  # Carry
  FLAG_V* = 0x02u16  # Overflow
  FLAG_Z* = 0x04u16  # Zero
  FLAG_N* = 0x08u16  # Negative
  FLAG_X* = 0x10u16  # Extend
  FLAG_S* = 0x2000u16 # Supervisor mode

proc ccr*(regs: Mcf5307Registers): uint8 {.inline.} =
  uint8(regs.sr and 0xFFu16)

proc `ccr=`*(regs: var Mcf5307Registers, val: uint8) {.inline.} =
  regs.sr = (regs.sr and 0xFF00u16) or uint16(val)

proc getCarry*(regs: Mcf5307Registers): bool {.inline.} = (regs.sr and FLAG_C) != 0
proc getOverflow*(regs: Mcf5307Registers): bool {.inline.} = (regs.sr and FLAG_V) != 0
proc getZero*(regs: Mcf5307Registers): bool {.inline.} = (regs.sr and FLAG_Z) != 0
proc getNegative*(regs: Mcf5307Registers): bool {.inline.} = (regs.sr and FLAG_N) != 0
proc getExtend*(regs: Mcf5307Registers): bool {.inline.} = (regs.sr and FLAG_X) != 0
proc getSupervisor*(regs: Mcf5307Registers): bool {.inline.} = (regs.sr and FLAG_S) != 0

proc setCarry*(regs: var Mcf5307Registers, val: bool) {.inline.} =
  if val: regs.sr = regs.sr or FLAG_C else: regs.sr = regs.sr and (not FLAG_C)

proc setOverflow*(regs: var Mcf5307Registers, val: bool) {.inline.} =
  if val: regs.sr = regs.sr or FLAG_V else: regs.sr = regs.sr and (not FLAG_V)

proc setZero*(regs: var Mcf5307Registers, val: bool) {.inline.} =
  if val: regs.sr = regs.sr or FLAG_Z else: regs.sr = regs.sr and (not FLAG_Z)

proc setNegative*(regs: var Mcf5307Registers, val: bool) {.inline.} =
  if val: regs.sr = regs.sr or FLAG_N else: regs.sr = regs.sr and (not FLAG_N)

proc setExtend*(regs: var Mcf5307Registers, val: bool) {.inline.} =
  if val: regs.sr = regs.sr or FLAG_X else: regs.sr = regs.sr and (not FLAG_X)

proc setSupervisor*(regs: var Mcf5307Registers, val: bool) {.inline.} =
  if val: regs.sr = regs.sr or FLAG_S else: regs.sr = regs.sr and (not FLAG_S)

# Control Register Access (MOVEC opcodes)
proc readControlRegister*(regs: Mcf5307Registers, cr: uint16): uint32 =
  case cr
  of 0x000u16: regs.cacr
  of 0x002u16: regs.vbr
  of 0x004u16: regs.acr0
  of 0x005u16: regs.acr1
  of 0xC04u16: regs.rambar0
  of 0xC05u16: regs.rambar1
  of 0xC0Fu16: regs.mbar
  else: 0u32

proc writeControlRegister*(regs: var Mcf5307Registers, cr: uint16, val: uint32) =
  case cr
  of 0x000u16: regs.cacr = val
  of 0x002u16: regs.vbr = val
  of 0x004u16: regs.acr0 = val
  of 0x005u16: regs.acr1 = val
  of 0xC04u16: regs.rambar0 = val
  of 0xC05u16: regs.rambar1 = val
  of 0xC0Fu16: regs.mbar = val
  else: discard

# Reset register set
proc reset*(regs: var Mcf5307Registers, initialSp: uint32, initialPc: uint32) =
  for i in 0..7:
    regs.d[i] = 0u32
    regs.a[i] = 0u32
  regs.sp = initialSp
  regs.pc = initialPc
  regs.sr = 0x2700u16  # Supervisor mode (S=1), IPL=7
  regs.vbr = 0u32
  regs.mbar = 0u32
  regs.rambar0 = 0u32
  regs.rambar1 = 0u32
  regs.cacr = 0u32
  regs.acr0 = 0u32
  regs.acr1 = 0u32
