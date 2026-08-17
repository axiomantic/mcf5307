## `exception` - the exception stack frame, the fault status codes and the
## vector table. A leaf: every procedure is a function of plain integers, so a
## caller can reach it without an edge to an executor.
##
## THE SOURCES DISAGREE ABOUT VECTOR 5 AND NOTHING RECONCILES IT, so no
## constant below names vector 5, 12 or 13.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The layout,
## the encodings and the vector assignments are facts about Motorola silicon,
## from the MCF5307 User's Manual (1998) and the ColdFire Family Programmer's
## Reference Manual, Rev. 3.

# The defined set for this part. Every other value of the field is reserved.
# CONSTANTS AND NOT AN ENUM BECAUSE THE RESERVED VALUES ARE REAL: a frame read
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
# `FS` IS SPLIT AND ITS HALVES ARE NOT ADJACENT; `1001` is the one defined code
# that separates this layout from a contiguous one.

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

# The vector table is aligned on a 1 MByte boundary and indexed by
# `4 x vector_number` from the vector base register.
#
# VBR[19-0] ARE NOT IMPLEMENTED AND ARE ASSUMED TO BE ZERO, which is what the
# mask below carries. A model that added VBR whole would still be wrong.

const
  vectorTableBytes* = 1024'u32
  vbrImplementedMask* = 0xFFF0_0000'u32  ## VBR[19-0] are not implemented
  vecAccessError* = 2'u8                 ## $008
  vecAddressError* = 3'u8                ## $00C. NOT the same exception.
  vecUserFirst* = 64'u8                  ## $100
  vecUserLast* = 255'u8                  ## $3FC

proc autovectorFor*(level: range[1 .. 7]): uint8 =
  ## Vectors 25 to 31, at `$064`-`$07C`, are the level 1 to 7 autovectored
  ## interrupts.
  uint8(24 + level)

proc vectorAddress*(vbr: uint32; vector: uint8): uint32 =
  (vbr and vbrImplementedMask) + 4'u32 * uint32(vector)
