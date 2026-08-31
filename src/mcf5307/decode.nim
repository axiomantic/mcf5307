## `decode` - the instruction decoder for ColdFire ISA_A.
##
## This module turns a 16-bit instruction word into an `Operation` plus its
## effective address. It executes nothing, it holds no machine state, and it
## calls no instruction-group executor.
##
## The decoder is a level-2 module beside the executors. Both levels read the
## shared types from `decode_types`, and neither imports the other:
##
##     decode_types            the shared types and the EA legality table
##        ^          ^
##     decode      move, alu
##        ^          ^
##            cpu               `step`, the dispatch, and the lifecycle ABI
##
## `cpu.nim` owns `step` and the `mcf5307_*` lifecycle calls, because `step`
## is the one procedure that needs both the decoder and every executor. A new
## instruction group adds one module, one import in `cpu.nim` and one `case`
## arm there, and no dependency here.
##
## Opcode encoding and the addressing-mode placement are taken from the
## ColdFire Family Programmer's Reference Manual and the MCF5307 User's
## Manual, and from this project's own measurements.

import mcf5307/decode_types
import mcf5307/ea

# ---------------------------------------------------------------------------
# The decoder.

proc sizeField(word: uint16): uint8 =
  ## The size field of the ordinary two-bit encoding in bits 7..6:
  ## 00 byte, 01 word, 10 long. 11 is not a size, and every opcode below that
  ## carries this field either refuses 11 outright or reports it as 0, which
  ## no executor accepts.
  case (word shr 6) and 0x3'u16
  of 0: 1'u8
  of 1: 2'u8
  of 2: 4'u8
  else: 0'u8

proc opmodeSize(opmode: uint16): uint8 =
  ## The size of the register-direction ADD and SUB opmodes: 000 and 100 are
  ## byte, 001 and 101 are word, 010 and 110 are long.
  case opmode and 0x3'u16
  of 0: 1'u8
  of 1: 2'u8
  else: 4'u8

proc decodeAddSub(word: uint16; opBase, opAddr, opExtend: Operation): Decoded =
  ## The shared shape of the ADD family (line 1101) and the SUB family
  ## (line 1001). Bits 11..9 are the data register, bits 8..6 the opmode and
  ## the low six bits the effective address.
  ##
  ##   opmode 000 001 010   `<ea> op Dn -> Dn`, byte word long
  ##   opmode 011           ADDA.W / SUBA.W - the 68000 word form
  ##   opmode 100 101 110   `Dn op <ea> -> <ea>`, byte word long,
  ##                        EXCEPT when bits 5..4 are 00, which is the ADDX
  ##                        and SUBX slot: a `Dn op <ea>` whose destination
  ##                        is a register is not an encodable direction, so
  ##                        the silicon reuses those bits.
  ##   opmode 111           ADDA.L / SUBA.L
  let opmode = (word shr 6) and 0x7'u16
  let dn = uint8((word shr 9) and 0x7'u16)
  let operand = decodeEa(word)
  if opmode == 7'u16 or opmode == 3'u16:
    # ADDA/SUBA. The word form (opmode 011) is decoded and carries size 2, so
    # that the executor rejects it as a word operation rather than leaving it
    # indistinguishable from an unrecognised encoding.
    return Decoded(op: opAddr, ea: operand, destReg: dn,
                   size: (if opmode == 7'u16: 4'u8 else: 2'u8))
  if opmode < 3'u16:
    return Decoded(op: opBase, ea: operand, destReg: dn,
                   size: opmodeSize(opmode), dirToEa: false)
  if (word and 0x0030'u16) == 0'u16:
    return Decoded(op: opExtend, ea: operand, destReg: dn,
                   size: opmodeSize(opmode))
  Decoded(op: opBase, ea: operand, destReg: dn, size: opmodeSize(opmode),
          dirToEa: true)

proc decodeWord*(word: uint16): Decoded =
  ## Decode one 16-bit instruction word into its operation and effective
  ## address. Every EA-bearing family recognized here places its effective
  ## address in the low six bits, which is the canonical placement. The
  ## extension words (displacements, index words, immediates, and the MOVEM
  ## register mask) are NOT fetched here; they live in the instruction
  ## stream after this word and the executor consumes
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
  elif (word and 0xFFF8'u16) == 0x4880'u16:
    # EXT.W Dn: sign-extend the low byte into the low word. The register is
    # the low three bits. This test comes before MOVEM: `0x4880 | <ea>` is
    # MOVEM.W on the 68000, which this part does not have, and `0x48C0 | <ea>`
    # with a mode of 000 is EXT.L and not the MOVEM.L below.
    return Decoded(op: opExt, ea: decodeEa(word), size: 2'u8,
                   destReg: uint8(word and 0x7'u16))
  elif (word and 0xFFF8'u16) == 0x48C0'u16:
    # EXT.L Dn: sign-extend the low word into the whole register.
    return Decoded(op: opExt, ea: decodeEa(word), size: 4'u8,
                   destReg: uint8(word and 0x7'u16))
  elif (word and 0xFFF8'u16) == 0x49C0'u16:
    # EXTB.L Dn: sign-extend the low BYTE into the whole register. A separate
    # instruction from EXT.L and a different result for the same input.
    return Decoded(op: opExtb, ea: decodeEa(word), size: 4'u8,
                   destReg: uint8(word and 0x7'u16))
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
  elif (word and 0xFFC0'u16) == 0x4C00'u16:
    # MULU.L / MULS.L <ea>,Dl. The second word decides signedness, and the
    # decoder sees one word. Bit 11 of that word selects MULS over MULU and
    # bit 10 selects the 68020 64-bit product, which this part does not have.
    # The executor reads the word and makes both calls; this branch says only
    # "the 32-bit multiply family".
    return Decoded(op: opMulu, ea: decodeEa(word), size: 4'u8)
  elif (word and 0xFFC0'u16) == 0x4C40'u16:
    # DIVU.L / DIVS.L / REMU.L / REMS.L <ea>,Dr:Dq. The second word names Dq
    # in bits 15..12 and Dr in bits 2..0, and selects signedness in bit 11.
    # Equal registers are the divide and unequal ones are the remainder; the
    # executor makes that call for the same reason as the multiply above.
    return Decoded(op: opDivu, ea: decodeEa(word), size: 4'u8)
  elif (word and 0xFF00'u16) == 0x4200'u16 and sizeField(word) != 0'u8:
    # CLR.B/.W/.L <data-alterable-ea>. This part keeps all three sizes, which
    # `m68k-elf-as -mcpu=5307` confirms by accepting `clr.b` and `clr.w`.
    # Size 11 is not decoded here: `0x42C0 | <ea>` is MOVE from CCR.
    return Decoded(op: opClr, ea: decodeEa(word), size: sizeField(word))
  elif (word and 0xFF00'u16) == 0x4400'u16 and sizeField(word) != 0'u8:
    return Decoded(op: opNeg, ea: decodeEa(word), size: sizeField(word))
  elif (word and 0xFF00'u16) == 0x4000'u16 and sizeField(word) != 0'u8:
    return Decoded(op: opNegx, ea: decodeEa(word), size: sizeField(word))
  elif (word and 0xFF00'u16) == 0x0600'u16 and sizeField(word) != 0'u8:
    # ADDI.<sz> #imm,<ea>: the immediate follows this word.
    return Decoded(op: opAddi, ea: decodeEa(word), size: sizeField(word))
  elif (word and 0xFF00'u16) == 0x0400'u16 and sizeField(word) != 0'u8:
    return Decoded(op: opSubi, ea: decodeEa(word), size: sizeField(word))
  elif (word and 0xF100'u16) == 0x5000'u16:
    # ADDQ.<sz> #data,<ea>. The data field 000 means eight: the value one to
    # seven encodes itself and zero would be a no-operation, so the encoding
    # spends that slot on the eighth value.
    let data = (word shr 9) and 0x7'u16
    return Decoded(op: opAddq, ea: decodeEa(word), size: sizeField(word),
                   imm: (if data == 0'u16: 8'u8 else: uint8(data)))
  elif (word and 0xF100'u16) == 0x5100'u16:
    let data = (word shr 9) and 0x7'u16
    return Decoded(op: opSubq, ea: decodeEa(word), size: sizeField(word),
                   imm: (if data == 0'u16: 8'u8 else: uint8(data)))
  elif (word and 0xF000'u16) == 0xD000'u16:
    return decodeAddSub(word, opAdd, opAdda, opAddx)
  elif (word and 0xF000'u16) == 0x9000'u16:
    return decodeAddSub(word, opSub, opSuba, opSubx)
  else:
    return Decoded(op: opIllegal)
