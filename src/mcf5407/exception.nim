## `exception` - the exception stack frame, the fault status codes and the
## vector table.
##
## Vector 5 was an open disagreement and the part settles it. The MCF5307
## User's Manual Table 3-1, folio 3-13, gives vectors 5 to 7 as "Reserved",
## while CFPRM Rev. 3 Table 11-1, folio 11-2, gives vector 5 to "Divide by
## zero"; the disagreement stood only because the MCF5307 manual is for a
## different part. This is an MCF5407, whose User's Manual Table 2-22, section
## 2.8.2, folio 2-34, reads "Attempted division by zero causes an exception
## (vector 5, offset = 0x014)". The CFPRM reading is the right one and
## `alu.nim` states it correctly. The same tables differ at vectors 12 and 13,
## where CFPRM footnote 3 does reconcile them. No constant below names vector
## 5, 12 or 13.

# ---------------------------------------------------------------------------
# FOUR PLACES WHERE THIS CORE PARTS COMPANY WITH A V3 BECAUSE THE PART IS A V4.
#
# None of them is a Revision B opcode - they are exception semantics, so the
# decision not to implement Revision B does not cover them. All four come from
# the MCF5407 User's Manual and all four say "Version 4 differs from Version 2
# and 3" in so many words. Each is implemented where the behaviour lives, and
# this list is the map from the sentence to the module.
#
#   1. THE STACKED PC OF AN ACCESS ERROR. Section 4.9.5.1, "Cache Filling",
#      folio 4-17: "Note that unlike Version 2 and Version 3 access errors, the
#      program counter stored on the exception stack frame points to the
#      faulting instruction." `cpu.nim`'s `step` holds that address and passes
#      it to `machine.nim`'s `takePendingWriteFault`; a V2 or V3 stacks the
#      program counter as the store found it, mid-instruction.
#
#   2. AN ADDRESS ERROR ON JSR. Table 2-22, folio 2-34: "If an address error
#      occurs on a JSR instruction, the Version 4 processor first pushes the
#      return address onto the stack and then calculates the target address. On
#      Version 2 and 3 processors, these functions are reversed."
#      `control.nim`'s `execJump` moves A7 before it evaluates the operand.
#
#   3. AN ADDRESS ERROR ON RTS. Table 2-22, folio 2-34: "If an address error
#      occurs on an RTS instruction, the Version 4 processor preserves the
#      original return PC and writes the exception stack frame above this
#      value. On Version 2 and 3 processors, the faulting return PC is
#      overwritten by the address error stack frame." `control.nim`'s `execRts`
#      leaves A7 at its entry value when the popped address is odd.
#
#   4. THE CONDITION CODES AFTER A WRITE-PROTECT FAULT. Table 2-22, folio 2-34:
#      "The Version 4 processor, unlike the Version 2 and 3 processors, updates
#      the condition code register if a write-protect error occurs during a CLR
#      or MOV3Q operation to memory." MOV3Q is Revision B and is not decoded
#      here, so `alu.nim`'s `execClr` is the whole of the reachable half.
#
#      ITEM 4 IS NOT LIKE THE OTHER THREE. The manual states that the register
#      is updated and states nowhere what it is updated TO, so the value this
#      core writes is a CHOICE and not a reading. The block above `execClr` in
#      `alu.nim` names the value, argues for it as reasoning rather than
#      evidence, and says what run would settle it.

# MCF5407 User's Manual Table 2-21, "Fault Status Encodings", folio 2-33: the
# defined set for this part. CFPRM Table 11-2, folio 11-5, adds codes tagged
# "V4 and beyond, if MMU" that do not apply, and every other value of the field
# is reserved.
#
# THE DEFINED SET IS WIDER ON THIS PART THAN ON THE MCF5307, and no constant
# below moves because of it. Table 2-21 defines `0010` as "Interrupt during a
# debug service routine", where the MCF5307's Table 3-3 left `0010` reserved,
# and it widens `0000` to "Not an access or address error nor an interrupted
# debug service routine". This core raises neither a debug interrupt nor an
# interrupted debug service routine, so it never writes `0010` and never needs
# to read it; the four codes below are still the whole of what it produces.
# Constants and not an enum because the reserved values are real: a frame read
# back from memory can hold any value the field can carry, and converting one to
# an enum with holes under `--panics:on` ends the process instead of reporting
# it.

const
  fsNotAnAccessError* = 0b0000'u32  ## nor an address error
  fsInstructionFetch* = 0b0100'u32
  fsOperandWrite* = 0b1000'u32
  fsWriteProtected* = 0b1001'u32    ## write to write-protected space
  fsOperandRead* = 0b1100'u32

# The 8-byte frame:
#
#   +0x00  FORMAT 31:28 | FS[3:2] 27:26 | VEC[7:0] 25:18 | FS[1:0] 17:16 |
#          status register 15:0
#   +0x04  program counter
#
# CFPRM section 11.1.2, Figure 11-1, folio 11-4, prints those bit numbers over
# the fields, and MCF5407 User's Manual section 2.8.1, "Exception Stack Frame
# Definition", Figure 2-1, "Exception Stack Frame Form", folio 2-33, prints the
# same figure. Cite that figure by TITLE and folio: the manual gives the number
# 2-1 to two different figures, this one and "ColdFire Enhanced Pipeline" on
# folio 2-3. `FS` IS SPLIT AND ITS HALVES ARE NOT ADJACENT; `1001` is the one
# defined code that separates this layout from a contiguous one.

proc frameFirstLongword*(format: uint32; fs: uint32; vector: uint8;
                         sr: uint32): uint32 =
  ((format and 0xF'u32) shl 28) or
    (((fs shr 2) and 0x3'u32) shl 26) or
    (uint32(vector) shl 18) or
    ((fs and 0x3'u32) shl 16) or
    (sr and 0xFFFF'u32)

proc frameFormat*(longword: uint32): uint32 =
  (longword shr 28) and 0xF'u32

proc frameFaultStatus*(longword: uint32): uint32 =
  ## The four bits, rejoined from the two fields that hold them.
  (((longword shr 26) and 0x3'u32) shl 2) or ((longword shr 16) and 0x3'u32)

proc frameVector*(longword: uint32): uint8 =
  uint8((longword shr 18) and 0xFF'u32)

proc frameStatusRegister*(longword: uint32): uint32 =
  longword and 0xFFFF'u32

# MCF5407 User's Manual section 2.8, "Exception Processing Overview", folio
# 2-31: "ColdFire processors support a 1024-byte vector table aligned on any
# 1-Mbyte address boundary", indexed by `4 x vector_number` from the vector
# base register.
#
# THIS MANUAL SAYS WHY IT IS ALIGNED, WHERE THE MCF5307'S DID NOT. Section
# 2.2.2.2, "Vector Base Register (VBR)", folio 2-12: "VBR[19-0] are not
# implemented and are assumed to be zero, forcing the vector table to be
# aligned on a 0-modulo-1-Mbyte boundary." That is what the mask below carries,
# and it now comes from the part's own manual rather than from the CFPRM alone.
# CFPRM section 11.1, folio 11-2, says the same thing and is no longer the only
# witness. A model that added VBR whole would satisfy the alignment sentence
# and still be wrong.

const
  vectorTableBytes* = 1024'u32
  vbrImplementedMask* = 0xFFF0_0000'u32  ## VBR[19-0] are not implemented
  vecAccessError* = 2'u8                 ## $008, Table 2-19
  vecAddressError* = 3'u8                ## $00C. NOT the same exception.
  vecUserFirst* = 64'u8                  ## $100
  vecUserLast* = 255'u8                  ## $3FC

proc autovectorFor*(level: range[1 .. 7]): uint8 =
  ## Table 2-19, folio 2-32, gives vectors 25 to 31, at `$064`-`$07C`, to the
  ## level 1 to 7 autovectored interrupts.
  uint8(24 + level)

proc vectorAddress*(vbr: uint32; vector: uint8): uint32 =
  (vbr and vbrImplementedMask) + 4'u32 * uint32(vector)
