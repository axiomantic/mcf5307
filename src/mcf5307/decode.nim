## `decode` - the instruction decoder for ColdFire ISA_A. Task CPU-6 creates
## this file. Design section 6.1.
##
## THIS MODULE DOES ONE THING. It turns a 16-bit instruction word into an
## `Operation` plus its effective address. It executes nothing, it holds no
## machine state, and it calls no instruction-group executor.
##
## THE LAYERING. The decoder is a level-2 module beside the executors
## (`move.nim`, and later `alu.nim`, `logic.nim`, `control.nim`). Both levels
## read the shared types from `decode_types`, and neither imports the other:
##
##     decode_types            the shared types and the EA legality table
##        ^          ^
##     decode      move (and later alu, logic, control)
##        ^          ^
##            cpu               `step`, the dispatch, and the lifecycle ABI
##
## `cpu.nim` owns `step` and the `mcf5307_*` lifecycle calls, because `step`
## is the one procedure that needs both the decoder and every executor. This
## module held `step` before, and therefore imported `move`. That inversion
## made the decoder depend on an executor and it added one import for each
## new instruction group. A new group (CPU-8 to CPU-10) now adds one module,
## one import in `cpu.nim` and one `case` arm there. It adds no dependency
## here.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Opcode
## encoding and the addressing-mode placement are facts about Motorola
## silicon; they are taken from the ColdFire Family Programmer's Reference
## Manual and the MCF5307 User's Manual (AGENTS.md section 11) and from this
## project's own measurements.

import mcf5307/decode_types
import mcf5307/ea

# ---------------------------------------------------------------------------
# The decoder.
#
# CPU-6 recognizes the instruction families that carry the effective-address
# legality demonstration, together with the two instructions that have no
# effective address. The full opcode table with per-group semantics is the
# work of CPU-7 to CPU-12; the decoder is structured so those tasks extend
# the `case` below and the legality table rather than rewrite it.


proc decodeWord*(word: uint16): Decoded =
  ## Decode one 16-bit instruction word into its operation and effective
  ## address. Every EA-bearing family recognized here places its effective
  ## address in the low six bits, which is the canonical placement. The
  ## extension words (displacements, index words, immediates, and the MOVEM
  ## register mask) are NOT fetched here; they live in the instruction
  ## stream after this word and the executor (CPU-7 `move.nim`) consumes
  ## them as it walks the operand.
  if word == 0x4E71'u16:
    return Decoded(op: opNop)
  elif (word and 0xFFF8'u16) == 0x4E50'u16:
    # LINK An,#<d16>: the register in the low three bits, the signed
    # displacement in the following word.
    return Decoded(op: opLink, destReg: uint8(word and 0x7'u16))
  elif (word and 0xFFF8'u16) == 0x4E58'u16:
    return Decoded(op: opUnlk, destReg: uint8(word and 0x7'u16))
  elif (word and 0xF100'u16) == 0x7000'u16:
    # MOVEQ #imm,Dn: the register in bits 11..9, the sign-extended byte
    # immediate in the low byte.
    return Decoded(op: opMoveq, destReg: uint8((word shr 9) and 0x7'u16))
  elif (word and 0xC000'u16) == 0x0000'u16 and
      ((word shr 12) and 0x3'u16) != 0'u16:
    # `00` prefix: MOVE. The size is bits 13..12 (01 byte, 11 word, 10
    # long; 00 is the immediate-logic group, which is not MOVE and must
    # fall through to illegal until the logic task decodes it). The
    # destination mode is bits 8..6: 000 data register, 001 address
    # register (MOVEA), and the alterable memory modes. The destination
    # register is bits 11..9 and the source EA is the low six bits.
    let size = case (word shr 12) and 0x3'u16
      of 1: 1'u8
      of 2: 4'u8
      of 3: 2'u8
      else: 0'u8
    let destMode = uint8((word shr 6) and 0x7'u16)
    let destReg = uint8((word shr 9) and 0x7'u16)
    let opx = if destMode == 1'u8: opMovea else: opMove
    return Decoded(op: opx, ea: decodeEa(word), size: size,
                   destReg: destReg, destMode: destMode)
  elif (word and 0xF1C0'u16) == 0x41C0'u16:
    # LEA <control-ea>,An: the destination in bits 11..9, the EA in the low
    # six bits, bits 8..6 fixed at 111.
    return Decoded(op: opLea, ea: decodeEa(word),
                   destReg: uint8((word shr 9) and 0x7'u16))
  elif (word and 0xFFC0'u16) == 0x4840'u16:
    return Decoded(op: opPea, ea: decodeEa(word))
  elif (word and 0xFFC0'u16) == 0x48C0'u16:
    # MOVEM.L regs,<control-ea>: the register mask is the FOLLOWING word,
    # then the EA's own extension words.
    return Decoded(op: opMovem, ea: decodeEa(word), memDir: false)
  elif (word and 0xFFC0'u16) == 0x4CC0'u16:
    return Decoded(op: opMovem, ea: decodeEa(word), memDir: true)
  elif (word and 0xF100'u16) == 0x5000'u16:
    return Decoded(op: opAddq, ea: decodeEa(word))
  elif (word and 0xF100'u16) == 0x5100'u16:
    return Decoded(op: opSubq, ea: decodeEa(word))
  else:
    return Decoded(op: opIllegal)
