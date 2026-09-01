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

proc decodeLogicLine(word: uint16; opBase: Operation): Decoded =
  ## The shared shape of the AND family (line 1100) and the OR family
  ## (line 1000). It is `decodeAddSub`'s shape with the address and extended
  ## slots removed, because neither line has them:
  ##
  ##   opmode 000 001 010   `<ea> op Dn -> Dn`, byte word long
  ##   opmode 100 101 110   `Dn op <ea> -> <ea>`, byte word long
  ##   opmode 011 111       The word multiply and divide, which this part has.
  ##                        Line 1100 gives MULU.W (011) and MULS.W (111);
  ##                        line 1000 gives DIVU.W (011) and DIVS.W (111).
  ##
  ## THE SIZE IS 2 AND THAT IS WHAT THE EXECUTOR BRANCHES ON. The word form is
  ## ONE word: Dx is bits 11..9 of this word and signedness is bits 8..6,
  ## where the long form takes both from a second word it fetches. An executor
  ## that fetched an extension word here would consume the next instruction.
  ##
  ## The byte and word opmodes are decoded and they carry their own size.
  ## They are not instructions on this part - `m68k-elf-as -mcpu=5307` rejects
  ## `and.b %d0,%d1` - and the executor traps them on the size, which is the
  ## same channel `alu.nim` uses for byte and word arithmetic. Decoding them
  ## as an unrecognised word instead would report "no such instruction" for an
  ## encoding that is a real AND on a 68000, which says less about why the
  ## core refused.
  ##
  ## The 68000 slots inside the `Dn op <ea>` opmodes come out as traps too.
  ## `1100 rrr 1 00 00 rrr` is ABCD and `1100 rrr 1 01 00 rrr` is EXG on that
  ## part, and both are byte or word opmodes here, so both trap on the size.
  ## `1100 rrr 1 10 001 rrr` is `EXG Dn,An`, a long opmode whose effective
  ## address is an address register, and the memory-alterable destination mask
  ## rejects it.
  let opmode = (word shr 6) and 0x7'u16
  if opmode == 3'u16 or opmode == 7'u16:
    # The line selects the family and the opmode selects the sign. `opBase` is
    # the only thing distinguishing the two lines here, exactly as it is for
    # the logic opmodes below.
    let signed = opmode == 7'u16
    let op =
      if opBase == opAnd: (if signed: opMuls else: opMulu)
      else: (if signed: opDivs else: opDivu)
    return Decoded(op: op, ea: decodeEa(word), size: 2'u8,
                   destReg: uint8((word shr 9) and 0x7'u16))
  Decoded(op: opBase, ea: decodeEa(word),
          destReg: uint8((word shr 9) and 0x7'u16),
          size: opmodeSize(opmode), dirToEa: opmode >= 4'u16)

proc decodeShift(word: uint16): Decoded =
  ## Line 1110: ASL, ASR, LSL and LSR. Bit 8 is the direction (1 left, 0
  ## right) and bits 4..3 the type: 00 arithmetic, 01 logical, 10 and 11 the
  ## two ROTATES, which this part does not have.
  ##
  ## The register form and the memory form put different things in the same
  ## bits, which is why they are decoded apart. In the register form bits 7..6
  ## are the size, bits 11..9 a count or a count register, bit 5 says which of
  ## those two, and bits 2..0 are the destination data register - bits 5..3
  ## are not an effective address, so `decodeEa` must not be asked. In the
  ## memory form bits 7..6 are 11, bits 10..9 are the type, and the low six
  ## bits are an effective address.
  ##
  ## The memory form is decoded and it traps in the executor. Every shift on
  ## this part is register-only, and the `{Dn}` mask in `decode_types` is what
  ## refuses the memory operand. Decoding it here rather than calling it an
  ## unrecognised word keeps the "which operands may this opcode reach"
  ## question in the one table that answers it for every other opcode.
  let shiftType = (word shr 3) and 0x3'u16
  let toLeft = (word and 0x0100'u16) != 0'u16
  if (word and 0x00C0'u16) == 0x00C0'u16:
    # The memory form: `1110 0tt d 11 <ea>`, one bit position per shift, word
    # sized. Bit 11 is not part of the encoding and must be zero.
    let memType = (word shr 9) and 0x3'u16
    if (word and 0x0800'u16) != 0'u16 or memType > 1'u16:
      return Decoded(op: opIllegal)
    let op = if memType == 0'u16: (if toLeft: opAsl else: opAsr)
             else: (if toLeft: opLsl else: opLsr)
    return Decoded(op: op, ea: decodeEa(word), size: 2'u8, imm: 1'u8)
  if shiftType > 1'u16:
    return Decoded(op: opIllegal)
  let op = if shiftType == 0'u16: (if toLeft: opAsl else: opAsr)
           else: (if toLeft: opLsl else: opLsr)
  let countField = uint8((word shr 9) and 0x7'u16)
  let inRegister = (word and 0x0020'u16) != 0'u16
  # The count field 000 means eight, the same spend of the unusable zero slot
  # that ADDQ and SUBQ make. It applies to the immediate form alone: in the
  # register form the field names d0 and a count of zero is a real count.
  Decoded(op: op, ea: EA(mode: eaDn, reg: uint8(word and 0x7'u16)),
          size: sizeField(word), destReg: countField,
          regOperand: inRegister,
          imm: (if inRegister: 0'u8
                elif countField == 0'u8: 8'u8
                else: countField))

proc decodeBitOp(word: uint16): Decoded =
  ## The bit operations, in both of their forms. Bits 7..6 select the
  ## operation - 00 BTST, 01 BCHG, 10 BCLR, 11 BSET - and bit 8 selects the
  ## form: 1 is dynamic, whose bit number is in the data register named by
  ## bits 11..9, and 0 is static, whose bit number is the extension word after
  ## the opcode. The caller has already established that this is a bit
  ## operation.
  ##
  ## The operand size is decided by the operand. A data register is 32 bits
  ## wide and every memory operand is 8. The bit number is taken
  ## modulo that width by the executor.
  let operand = decodeEa(word)
  let op = case (word shr 6) and 0x3'u16
    of 0: opBtst
    of 1: opBchg
    of 2: opBclr
    else: opBset
  Decoded(op: op, ea: operand,
          size: (if operand.mode == eaDn: 4'u8 else: 1'u8),
          destReg: uint8((word shr 9) and 0x7'u16),
          regOperand: (word and 0x0100'u16) != 0'u16)

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
    # long; 00 is the immediate-logic group, which is not MOVE). The
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
  elif (word and 0xFFF8'u16) == 0x4840'u16:
    # SWAP Dn: the halves of a data register exchange. THIS TEST COMES BEFORE
    # PEA AND THE ORDER IS LOAD-BEARING, exactly as EXT comes before MOVEM
    # above and for the same reason. `0x4840 | <ea>` is PEA, and the eight
    # words `4840`-`4847` are the sub-range whose mode field is 000 - a data
    # register, which is not control addressing and so is no PEA operand at
    # all. PEA's mask `word and 0xFFC0 == 0x4840` spans `4840`-`487f` and
    # covers all eight, and `eaLegalityFor(opPea)` excludes `Dn`.
    #
    # If this arm is moved below the PEA arm, or its mask widened back to
    # `0xFFC0`, the `swap` cases in `tests/t_move.nim` go red.
    return Decoded(op: opSwap, ea: decodeEa(word), size: 4'u8,
                   destReg: uint8(word and 0x7'u16))
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
  elif (word and 0xFFF8'u16) == 0x40C0'u16:
    # MOVE from SR: `0100 0000 11 000 rrr`. PRIVILEGED, and
    # `movec.nim` is where that is decided - this arm only names the opcode.
    return Decoded(op: opMoveFromSr, size: 2'u8,
                   destReg: uint8(word and 0x7'u16))
  elif (word and 0xFFF8'u16) == 0x42C0'u16:
    # MOVE from CCR: `0100 0010 11 000 rrr`. UNPRIVILEGED: no supervisor
    # test.
    return Decoded(op: opMoveFromCcr, size: 2'u8,
                   destReg: uint8(word and 0x7'u16))
  elif (word and 0xFFF8'u16) == 0x44C0'u16 or word == 0x44FC'u16:
    # MOVE to CCR: `Dy` or `#<data>` and NOTHING ELSE.
    # `0x44FC` is mode 7 sub-variant 4, the immediate, whose extension word
    # `movec.nim` reads through `eaRead` and this module does not fetch.
    return Decoded(op: opMoveToCcr, ea: decodeEa(word), size: 2'u8)
  elif (word and 0xFFF8'u16) == 0x46C0'u16 or word == 0x46FC'u16:
    # MOVE to SR: `Dy` or `#<data>` and NOTHING ELSE, and PRIVILEGED.
    return Decoded(op: opMoveToSr, ea: decodeEa(word), size: 2'u8)
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
  elif (word and 0xF100'u16) == 0x5000'u16 and sizeField(word) != 0'u8:
    # ADDQ.<sz> #data,<ea>. The data field 000 means eight: the value one to
    # seven encodes itself and zero would be a no-operation, so the encoding
    # spends that slot on the eighth value.
    #
    # SIZE 11 IS NOT DECODED HERE, exactly as it is not for CLR, NEG, NEGX and
    # NOT: `0101 cccc 11 <ea>` is the Scc space, and claiming those words as an
    # ADDQ whose size is wrong would take the encodings away from it.
    let data = (word shr 9) and 0x7'u16
    return Decoded(op: opAddq, ea: decodeEa(word), size: sizeField(word),
                   imm: (if data == 0'u16: 8'u8 else: uint8(data)))
  elif (word and 0xF100'u16) == 0x5100'u16 and sizeField(word) != 0'u8:
    let data = (word shr 9) and 0x7'u16
    return Decoded(op: opSubq, ea: decodeEa(word), size: sizeField(word),
                   imm: (if data == 0'u16: 8'u8 else: uint8(data)))
  elif (word and 0xF000'u16) == 0xD000'u16:
    return decodeAddSub(word, opAdd, opAdda, opAddx)
  elif (word and 0xF000'u16) == 0x9000'u16:
    return decodeAddSub(word, opSub, opSuba, opSubx)

  # ---------------------------------------------------------------------------
  # The logic, bit-operation and shift lines.
  #
  # The line-0 branches sit after ADDI and SUBI and that is safe. Line 0 is
  # crowded - ORI, ANDI, EORI, SUBI, ADDI and both forms of the bit operations
  # share it - and no two of the tests below can match the same word. The
  # immediate-logic opcodes differ from each other in bits 11..8 (0000 ORI,
  # 0010 ANDI, 0100 SUBI, 0110 ADDI, 1000 the static bit operations, 1010
  # EORI), and every one of them has bit 8 clear, while a dynamic bit
  # operation is exactly the line-0 word whose bit 8 is set.
  #
  # The MOVE branch above cannot swallow them. It requires bits 13..12 to be
  # non-zero and every word here has them zero.
  elif (word and 0xF1C0'u16) == 0x0100'u16 or
       (word and 0xF1C0'u16) == 0x0140'u16 or
       (word and 0xF1C0'u16) == 0x0180'u16 or
       (word and 0xF1C0'u16) == 0x01C0'u16:
    # The dynamic bit operations: `0000 rrr 1 tt <ea>`.
    return decodeBitOp(word)
  elif (word and 0xFF00'u16) == 0x0800'u16 and
       ((word shr 6) and 0x3'u16) <= 3'u16:
    # The static bit operations: `0000 1000 tt <ea>`. All four values of the
    # two-bit field are operations, so the guard is a statement that the field
    # is fully covered and never a filter.
    return decodeBitOp(word)
  elif (word and 0xFF00'u16) == 0x0000'u16 and sizeField(word) != 0'u8:
    # ORI.<sz> #imm,Dn. The long immediate follows this word.
    return Decoded(op: opOri, ea: decodeEa(word), size: sizeField(word))
  elif (word and 0xFF00'u16) == 0x0200'u16 and sizeField(word) != 0'u8:
    return Decoded(op: opAndi, ea: decodeEa(word), size: sizeField(word))
  elif (word and 0xFF00'u16) == 0x0A00'u16 and sizeField(word) != 0'u8:
    return Decoded(op: opEori, ea: decodeEa(word), size: sizeField(word))
  elif (word and 0xFF00'u16) == 0x4600'u16 and sizeField(word) != 0'u8:
    # NOT.<sz> Dn. Size 11 is not decoded here, exactly as it is not for CLR:
    # `0x46C0 | <ea>` is MOVE to SR.
    return Decoded(op: opNot, ea: decodeEa(word), size: sizeField(word))
  elif (word and 0xF000'u16) == 0xC000'u16:
    return decodeLogicLine(word, opAnd)
  elif (word and 0xF000'u16) == 0x8000'u16:
    return decodeLogicLine(word, opOr)
  elif (word and 0xF000'u16) == 0xB000'u16 and
       ((word shr 6) and 0x7'u16) in 4'u16 .. 6'u16:
    # EOR.<sz> Dn,<ea>. The other opmodes of line 1011 are CMP (000, 001 and
    # 010), CMPA.W (011) and CMPA.L (111). They stay unrecognised here rather
    # than be claimed and trapped.
    #
    # THE RANGE IS 100 TO 110 AND NOT "100 OR ABOVE". 111 is CMPA.L, and
    # a `>= 4` predicate would claim it SILENTLY: `opmodeSize(7)`
    # answers 4, so `cmpa.l %d0,%a1` (`b3c0`) would decode as a well-formed
    # long EOR and execute as one, writing a register CMPA must not touch and
    # computing no comparison.
    #
    # `1011 rrr 1 ss 001 rrr` is CMPM on a 68000: a byte or word opmode whose
    # effective address is an address register. It traps on the size and on
    # the operand both.
    return Decoded(op: opEor, ea: decodeEa(word),
                   destReg: uint8((word shr 9) and 0x7'u16),
                   size: opmodeSize((word shr 6) and 0x7'u16))
  elif (word and 0xF000'u16) == 0xE000'u16:
    return decodeShift(word)

  # ---------------------------------------------------------------------------
  # Control flow and comparison.
  #
  # Where this block sits in the chain matters for exactly one pair of arms,
  # and the fix is not the order. Scc is `0101 cccc 11 <ea>` and ADDQ and SUBQ
  # are `0101 ddd s ss <ea>`; the two overlap wherever the size field is the
  # illegal `11`. Putting the Scc arm above them would work and would leave a
  # trap that a reordering could spring, so the ADDQ and SUBQ arms carry a
  # `sizeField(word) != 0` guard instead - the same guard CLR, NEG, NEGX and
  # NOT already carried - and this arm is safe wherever it sits.
  elif (word and 0xF000'u16) == 0x6000'u16:
    # `0110 cccc dddddddd`. Condition 0000 is BRA and 0001 is BSR; the rest
    # are the conditional branches.
    #
    # The displacement field carries the form as well as the value. A byte of
    # 0x00 means "a 16-bit displacement follows"; a byte of 0xFF means "a
    # 32-bit displacement follows", which is ISA_B and not on this part -
    # Table 3-7, page 3-23, gives Bcc, BRA and BSR an operand size of "8,16"
    # and no third value. The word is decoded here and the executor traps it,
    # so the core says "this part has no 32-bit branch" where an unrecognised
    # word would say "there is no such instruction".
    #
    # `size` carries the form: 1 is the byte displacement, 2 the word
    # displacement, and 4 the 32-bit form that must trap. `imm` is not used - a
    # displacement is signed and 16 or 32 bits wide, and `imm` is an unsigned
    # byte.
    let cond = uint8((word shr 8) and 0xF'u16)
    let disp8 = word and 0xFF'u16
    let form = if disp8 == 0x00'u16: 2'u8
               elif disp8 == 0xFF'u16: 4'u8
               else: 1'u8
    let op = if cond == 0'u8: opBra
             elif cond == 1'u8: opBsr
             else: opBcc
    return Decoded(op: op, size: form, destReg: cond)
  elif (word and 0xF0C0'u16) == 0x50C0'u16 and
       word != 0x51FA'u16 and word != 0x51FB'u16 and word != 0x51FC'u16:
    # `0101 cccc 11 <ea>`: Scc, and the TRAPF words this arm must not take.
    # The condition is bits 11..8 and the operand is the low six bits.
    #
    # What the 1024 words of this space are. Sixteen conditions times
    # sixty-four effective-address values.
    #
    # TRAPF IS NOT IMPLEMENTED HERE, and the excluded words are left unclaimed
    # rather than decoded: deciding they were Scc would execute a TRAPF as a
    # byte write into a data register.
    return Decoded(op: opScc, ea: decodeEa(word), size: 1'u8,
                   destReg: uint8((word shr 8) and 0xF'u16))
  elif (word and 0xFF00'u16) == 0x4A00'u16 and sizeField(word) != 0'u8:
    # TST.B/.W/.L <ea>. All three sizes exist here, which makes TST the one
    # instruction in this group that keeps the byte and word forms the rest of
    # the core traps.
    #
    # SIZE 11 IS NOT DECODED HERE: `0x4AC0 | <ea>` is TAS, which is not on
    # this part.
    return Decoded(op: opTst, ea: decodeEa(word), size: sizeField(word))
  elif (word and 0xFFC0'u16) == 0x4EC0'u16:
    return Decoded(op: opJmp, ea: decodeEa(word))
  elif (word and 0xFFC0'u16) == 0x4E80'u16:
    return Decoded(op: opJsr, ea: decodeEa(word))
  elif word == 0x4E75'u16:
    return Decoded(op: opRts)
  elif word == 0x4E73'u16:
    return Decoded(op: opRte)
  elif word == 0x4E7B'u16:
    # MOVEC.L Ry,Rc. The register numbers are in a second word, which
    # `movec.nim` reads and this module does not fetch.
    #
    # The test is an equality and not a mask, which is why it can sit here
    # beside RTS and RTE rather than ahead of the JMP and JSR arms above:
    # `0x4E7A` is MOVEC-from-control-register, a 68000 instruction that this
    # part does not have, and a mask over `0x4E78`-`0x4E7F` would claim it.
    #
    # `size: 4` is the instruction's own and not an operand's: the transfer is
    # always 32 bits even though a control register may be implemented with
    # fewer.
    return Decoded(op: opMovec, size: 4'u8)
  elif (word and 0xFFF0'u16) == 0x4E40'u16:
    # TRAP #<vector>, the vector in the low four bits. Every value of that
    # field is an instruction.
    return Decoded(op: opTrap, destReg: uint8(word and 0xF'u16))
  elif (word and 0xFF00'u16) == 0x0C00'u16 and sizeField(word) != 0'u8:
    # CMPI.<sz> #imm,Dx. The immediate follows this word. The byte and word
    # sizes are decoded and carry their own size so the executor traps them
    # on the size, exactly as `decodeLogicLine` does for AND and OR; size 11 is
    # the 68020 `CMP2`/`CHK2` and is not claimed.
    return Decoded(op: opCmpi, ea: decodeEa(word), size: sizeField(word))
  elif (word and 0xF000'u16) == 0xB000'u16:
    # Line 1011, the five opmodes the EOR arm above leaves unclaimed. That arm
    # takes 100, 101 and 110, so by the time control reaches here the opmode
    # is 000, 001, 010, 011 or 111.
    #
    #   opmode 000 001 010   CMP.B / CMP.W / CMP.L  `<ea> compared with Dn`
    #   opmode 011           CMPA.W - the form this part does not have
    #   opmode 111           CMPA.L
    #
    # The byte and word forms are decoded and they carry their own size, and
    # so does CMPA.W. Table 3-7, page 3-23, gives CMP, CMPA and CMPI an
    # operand size column of `32` alone, so all three of those encodings trap
    # on the size in `control.nim`. Decoding them as unrecognised words
    # instead would report "no such instruction" for encodings that are a real
    # CMP and a real CMPA on a 68000, which says less about why the core
    # refused - the same argument `decodeAddSub` makes for ADDA.W and
    # `decodeLogicLine` makes for the byte and word AND. CMPA.W is opmode 011,
    # and this arm decodes it so that the executor can refuse it by size.
    let opmode = (word shr 6) and 0x7'u16
    let dn = uint8((word shr 9) and 0x7'u16)
    if opmode == 7'u16 or opmode == 3'u16:
      return Decoded(op: opCmpa, ea: decodeEa(word), destReg: dn,
                     size: (if opmode == 7'u16: 4'u8 else: 2'u8))
    return Decoded(op: opCmp, ea: decodeEa(word), destReg: dn,
                   size: opmodeSize(opmode))
  else:
    return Decoded(op: opIllegal)
