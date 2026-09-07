## `exception` - the exception stack frame, the fault status codes and the
## vector table.
##
## The two manuals disagree about vector 5 and nothing reconciles it. User's
## Manual Table 3-1, folio 3-13, gives vectors 5 to 7 as "Reserved"; CFPRM
## Rev. 3 Table 11-1, folio 11-2, gives vector 5 to "Divide by zero" and its
## footnote 2 reserves that vector on the 5202, 5204 and 5206 alone - not this
## part. The same tables differ at vectors 12 and 13, where CFPRM footnote 3
## does reconcile them. No constant below names vector 5, 12 or 13.

# User's Manual Table 3-3, section 3.5.1, folio 3-14: these five are the whole
# defined set for this part. CFPRM Table 11-2, folio 11-5, adds codes tagged
# "V4 and beyond, if MMU" that do not apply, and every other value is reserved.
# Constants and not an enum because the reserved values are real: a frame read
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
# same figure. `FS` is split and its halves are not adjacent; `1001` is the one
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

# User's Manual section 3.3, folio 3-12: a "1024-byte vector table aligned on
# any 1 MByte address boundary", 256 vectors of which the first 64 are
# Motorola's, indexed by `4 x vector_number` from the vector base register.
# Only the CFPRM says why it is aligned, section 11.1, folio 11-2: "VBR[19-0]
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
