## `exception` - the exception stack frame, the fault status codes and the
## vector table. Task CPU-14. Design sections 6.1 and 5.2.1. A leaf: every
## procedure is a function of plain integers, so CPU-11, CPU-15 and CPU-17 can
## reach it without an edge to an executor.
##
## THREE LIMITS, EACH CLOSED BY A LATER TASK:
##
##   1. IT TAKES NO EXCEPTION. `machine.nim`'s `takeException` does, one layer
##      BELOW this module where it cannot import it, so the frame's first
##      longword has TWO expressions in this tree. `tests/t_exception.nim`
##      holds both against the same hand-derived numbers; nothing else keeps
##      them from drifting apart in silence.
##   2. NOTHING PRODUCES A NON-ZERO `FS` YET. The MCF5307 raises an access
##      error only on a store to write-protected space; CPU-15 owns that path
##      and is the first caller of `fsWriteProtected`.
##   3. THERE IS NO VBR TO PASS IN YET. The context holds no such field, and
##      CPU-11's `MOVEC` is the only thing that could write one.
##
## THE TWO MANUALS DISAGREE ABOUT VECTOR 5 AND NOTHING RECONCILES IT, read as
## page images 2026-08-12: User's Manual Table 3-1, folio 3-13, gives vectors 5
## to 7 as "Reserved"; CFPRM Rev. 3 Table 11-1, folio 11-2, gives vector 5 to
## "Divide by zero" and its footnote 2 reserves that vector on the 5202, 5204
## and 5206 alone - not this part. The same tables differ at vectors 12 and 13,
## where CFPRM footnote 3 DOES reconcile them. Recorded, not resolved: no
## constant below names vector 5, 12 or 13.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The layout,
## the encodings and the vector assignments are facts about Motorola silicon,
## from the MCF5307 User's Manual (1998) and the ColdFire Family Programmer's
## Reference Manual, Rev. 3.

# User's Manual Table 3-3, section 3.5.1, folio 3-14: these five are the whole
# defined set for this part. CFPRM Table 11-2, folio 11-5, adds codes tagged
# "V4 and beyond, if MMU" that do not apply, and every other value is reserved.
# CONSTANTS AND NOT AN ENUM BECAUSE THE RESERVED VALUES ARE REAL: a frame read
# back from memory can hold any of the sixteen, and converting one to an enum
# with holes under `--panics:on` ends the process instead of reporting it.

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
# the fields, and User's Manual section 3.4, Figure 3-7, folio 3-13, prints the
# same figure. `FS` IS SPLIT AND ITS HALVES ARE NOT ADJACENT; `1001` is the one
# defined code that separates this layout from a contiguous one, and
# `tests/t_exception.nim` pins it.

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

# User's Manual section 3.3, folio 3-12: a "1024-byte vector table aligned on
# any 1 MByte address boundary", 256 vectors of which the first 64 are
# Motorola's, indexed by `4 x vector_number` from the vector base register.
# ONLY THE CFPRM SAYS WHY IT IS ALIGNED, section 11.1, folio 11-2: "VBR[19-0]
# are not implemented and are assumed to be zero". A model that added VBR whole
# would satisfy the User's Manual sentence and still be wrong.

const
  vectorTableBytes* = 1024'u32
  vbrImplementedMask* = 0xFFF0_0000'u32  ## VBR[19-0] are not implemented
  vecAccessError* = 2'u8                 ## $008, Table 3-1
  vecAddressError* = 3'u8                ## $00C. NOT the same exception.
  vecUserFirst* = 64'u8                  ## $100
  vecUserLast* = 255'u8                  ## $3FC

proc autovectorFor*(level: range[1 .. 7]): uint8 =
  ## Table 3-1 gives vectors 25 to 31, at `$064`-`$07C`, to the level 1 to 7
  ## autovectored interrupts.
  uint8(24 + level)

proc vectorAddress*(vbr: uint32; vector: uint8): uint32 =
  (vbr and vbrImplementedMask) + 4'u32 * uint32(vector)
