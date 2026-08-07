# src/mcf5307_decode.nim - ColdFire v3 Instruction Decode Table & JSON Determinism Export (M-9)

import std/json
import std/strutils

type
  OpcodeKind* = enum
    opIllegal,
    opAdd, opAdda, opAddi, opAddq, opAddx,
    opAnd, opAndi,
    opAsl, opAsr,
    opBcc, opBchg, opBclr, opBset, opBtst,
    opClr, opCmp, opCmpa, opCmpi,
    opDivs, opDivu,
    opEor, opEori, opExt, opExtb,
    opHalt, opJmp, opJsr, opLea, opPea,
    opLsl, opLsr,
    opMac, opMove, opMovea, opMoveFromSr, opMoveToCcr, opMoveToSr,
    opMovec, opMovem, opMoveq,
    opMuls, opMulu, opMvs, opMvz,
    opNeg, opNegx, opNop, opNot,
    opOr, opOri,
    opRem, opRemu, opRte, opRts,
    opScc, opStop,
    opSub, opSuba, opSubi, opSubq, opSubx,
    opSwap, opTrap, opTst, opWdebug

  OpcodeEntry* = object
    opcode*: uint16
    mask*: uint16
    match*: uint16
    kind*: OpcodeKind
    mnemonic*: string

  DecodeTable* = array[65536, OpcodeEntry]

proc decodeSingleOpcode*(opcode: uint16): OpcodeEntry =
  result.opcode = opcode

  # Match specific 16-bit opcodes first
  if opcode == 0x4E71u16:
    return OpcodeEntry(opcode: opcode, mask: 0xFFFFu16, match: 0x4E71u16, kind: opNop, mnemonic: "NOP")
  elif opcode == 0x4AC8u16:
    return OpcodeEntry(opcode: opcode, mask: 0xFFFFu16, match: 0x4AC8u16, kind: opHalt, mnemonic: "HALT")
  elif opcode == 0x4E73u16:
    return OpcodeEntry(opcode: opcode, mask: 0xFFFFu16, match: 0x4E73u16, kind: opRte, mnemonic: "RTE")
  elif opcode == 0x4E75u16:
    return OpcodeEntry(opcode: opcode, mask: 0xFFFFu16, match: 0x4E75u16, kind: opRts, mnemonic: "RTS")
  elif opcode == 0x4E72u16:
    return OpcodeEntry(opcode: opcode, mask: 0xFFFFu16, match: 0x4E72u16, kind: opStop, mnemonic: "STOP")
  elif opcode == 0x4E7Bu16:
    return OpcodeEntry(opcode: opcode, mask: 0xFFFFu16, match: 0x4E7Bu16, kind: opMovec, mnemonic: "MOVEC")

  # Line 0 (0x0...): Immediate arithmetic & Bit manipulation
  if (opcode and 0xF000u16) == 0x0000u16:
    if (opcode and 0xFF00u16) == 0x0000u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x0000u16, kind: opOri, mnemonic: "ORI")
    elif (opcode and 0xFF00u16) == 0x0200u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x0200u16, kind: opAndi, mnemonic: "ANDI")
    elif (opcode and 0xFF00u16) == 0x0400u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x0400u16, kind: opSubi, mnemonic: "SUBI")
    elif (opcode and 0xFF00u16) == 0x0600u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x0600u16, kind: opAddi, mnemonic: "ADDI")
    elif (opcode and 0xFF00u16) == 0x0A00u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x0A00u16, kind: opEori, mnemonic: "EORI")
    elif (opcode and 0xFF00u16) == 0x0C00u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x0C00u16, kind: opCmpi, mnemonic: "CMPI")
    elif (opcode and 0xF1C0u16) == 0x0800u16 or (opcode and 0xF1C0u16) == 0x0000u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF1C0u16, match: (opcode and 0xF1C0u16), kind: opBtst, mnemonic: "BTST")
    elif (opcode and 0xF1C0u16) == 0x0840u16 or (opcode and 0xF1C0u16) == 0x0040u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF1C0u16, match: (opcode and 0xF1C0u16), kind: opBchg, mnemonic: "BCHG")
    elif (opcode and 0xF1C0u16) == 0x0880u16 or (opcode and 0xF1C0u16) == 0x0080u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF1C0u16, match: (opcode and 0xF1C0u16), kind: opBclr, mnemonic: "BCLR")
    elif (opcode and 0xF1C0u16) == 0x08C0u16 or (opcode and 0xF1C0u16) == 0x00C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF1C0u16, match: (opcode and 0xF1C0u16), kind: opBset, mnemonic: "BSET")

  # Line 1, 2, 3: MOVE (byte, long, word)
  if (opcode and 0xC000u16) == 0x1000u16 or (opcode and 0xC000u16) == 0x2000u16 or (opcode and 0xC000u16) == 0x3000u16:
    if (opcode and 0x2CF8u16) == 0x2CF8u16 and (opcode and 0xFFF8u16) == 0x2CF8u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFFF8u16, match: 0x2CF8u16, kind: opWdebug, mnemonic: "WDEBUG")
    return OpcodeEntry(opcode: opcode, mask: 0xC000u16, match: (opcode and 0xC000u16), kind: opMove, mnemonic: "MOVE")

  # Line 4: Misc
  if (opcode and 0xF000u16) == 0x4000u16:
    if (opcode and 0xFFC0u16) == 0x40C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFFC0u16, match: 0x40C0u16, kind: opMoveFromSr, mnemonic: "MOVE_FROM_SR")
    elif (opcode and 0xFFC0u16) == 0x44C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFFC0u16, match: 0x44C0u16, kind: opMoveToCcr, mnemonic: "MOVE_TO_CCR")
    elif (opcode and 0xFFC0u16) == 0x46C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFFC0u16, match: 0x46C0u16, kind: opMoveToSr, mnemonic: "MOVE_TO_SR")
    elif (opcode and 0xFF00u16) == 0x4000u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x4000u16, kind: opNegx, mnemonic: "NEGX")
    elif (opcode and 0xFF00u16) == 0x4200u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x4200u16, kind: opClr, mnemonic: "CLR")
    elif (opcode and 0xFF00u16) == 0x4400u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x4400u16, kind: opNeg, mnemonic: "NEG")
    elif (opcode and 0xFF00u16) == 0x4600u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x4600u16, kind: opNot, mnemonic: "NOT")
    elif (opcode and 0xFF00u16) == 0x4A00u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x4A00u16, kind: opTst, mnemonic: "TST")
    elif (opcode and 0xF1C0u16) == 0x41C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF1C0u16, match: 0x41C0u16, kind: opLea, mnemonic: "LEA")
    elif (opcode and 0xFFF0u16) == 0x4E40u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFFF0u16, match: 0x4E40u16, kind: opTrap, mnemonic: "TRAP")
    elif (opcode and 0xFFF0u16) == 0x4E80u16 or (opcode and 0xFFC0u16) == 0x4E80u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFFC0u16, match: 0x4E80u16, kind: opJsr, mnemonic: "JSR")
    elif (opcode and 0xFFF0u16) == 0x4ED0u16 or (opcode and 0xFFC0u16) == 0x4ED0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFFC0u16, match: 0x4ED0u16, kind: opJmp, mnemonic: "JMP")
    elif (opcode and 0xFFF8u16) == 0x4840u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFFF8u16, match: 0x4840u16, kind: opSwap, mnemonic: "SWAP")
    elif (opcode and 0xFFC0u16) == 0x4840u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFFC0u16, match: 0x4840u16, kind: opPea, mnemonic: "PEA")
    elif (opcode and 0xFF38u16) == 0x4880u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF38u16, match: 0x4880u16, kind: opExt, mnemonic: "EXT")
    elif (opcode and 0xFF38u16) == 0x4980u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF38u16, match: 0x4980u16, kind: opExtb, mnemonic: "EXTB")
    elif (opcode and 0xFB80u16) == 0x4880u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFB80u16, match: 0x4880u16, kind: opMovem, mnemonic: "MOVEM")

  # Line 5: ADDQ, SUBQ, Scc
  if (opcode and 0xF000u16) == 0x5000u16:
    if (opcode and 0xF100u16) == 0x5000u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF100u16, match: 0x5000u16, kind: opAddq, mnemonic: "ADDQ")
    elif (opcode and 0xF100u16) == 0x5100u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF100u16, match: 0x5100u16, kind: opSubq, mnemonic: "SUBQ")
    elif (opcode and 0xF0C0u16) == 0x50C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF0C0u16, match: 0x50C0u16, kind: opScc, mnemonic: "SCC")

  # Line 6: Bcc / BRA / BSR
  if (opcode and 0xF000u16) == 0x6000u16:
    return OpcodeEntry(opcode: opcode, mask: 0xF000u16, match: 0x6000u16, kind: opBcc, mnemonic: "Bcc")

  # Line 7: MOVEQ, MVS, MVZ
  if (opcode and 0xF000u16) == 0x7000u16:
    if (opcode and 0xFF00u16) == 0x7100u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x7100u16, kind: opMvs, mnemonic: "MVS")
    elif (opcode and 0xFF00u16) == 0x7140u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFF00u16, match: 0x7140u16, kind: opMvz, mnemonic: "MVZ")
    elif (opcode and 0xF100u16) == 0x7000u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF100u16, match: 0x7000u16, kind: opMoveq, mnemonic: "MOVEQ")

  # Line 8: OR, DIVU, DIVS
  if (opcode and 0xF000u16) == 0x8000u16:
    if (opcode and 0xF1C0u16) == 0x80C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF1C0u16, match: 0x80C0u16, kind: opDivu, mnemonic: "DIVU")
    elif (opcode and 0xF1C0u16) == 0x81C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF1C0u16, match: 0x81C0u16, kind: opDivs, mnemonic: "DIVS")
    else:
      return OpcodeEntry(opcode: opcode, mask: 0xF000u16, match: 0x8000u16, kind: opOr, mnemonic: "OR")

  # Line 9: SUB, SUBA, SUBX
  if (opcode and 0xF000u16) == 0x9000u16:
    if (opcode and 0xF0C0u16) == 0x90C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF0C0u16, match: 0x90C0u16, kind: opSuba, mnemonic: "SUBA")
    elif (opcode and 0xF130u16) == 0x9100u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF130u16, match: 0x9100u16, kind: opSubx, mnemonic: "SUBX")
    else:
      return OpcodeEntry(opcode: opcode, mask: 0xF000u16, match: 0x9000u16, kind: opSub, mnemonic: "SUB")

  # Line A: MAC / EMAC
  if (opcode and 0xF000u16) == 0xA000u16:
    return OpcodeEntry(opcode: opcode, mask: 0xF000u16, match: 0xA000u16, kind: opMac, mnemonic: "MAC")

  # Line B: CMP, CMPA, EOR
  if (opcode and 0xF000u16) == 0xB000u16:
    if (opcode and 0xF0C0u16) == 0xB0C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF0C0u16, match: 0xB0C0u16, kind: opCmpa, mnemonic: "CMPA")
    elif (opcode and 0xF100u16) == 0xB100u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF100u16, match: 0xB100u16, kind: opEor, mnemonic: "EOR")
    else:
      return OpcodeEntry(opcode: opcode, mask: 0xF000u16, match: 0xB000u16, kind: opCmp, mnemonic: "CMP")

  # Line C: AND, MULU, MULS
  if (opcode and 0xF000u16) == 0xC000u16:
    if (opcode and 0xF1C0u16) == 0xC0C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF1C0u16, match: 0xC0C0u16, kind: opMulu, mnemonic: "MULU")
    elif (opcode and 0xF1C0u16) == 0xC1C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF1C0u16, match: 0xC1C0u16, kind: opMuls, mnemonic: "MULS")
    elif (opcode and 0xFFC0u16) == 0x4C00u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFFC0u16, match: 0x4C00u16, kind: opRem, mnemonic: "REM")
    elif (opcode and 0xFFC0u16) == 0x4C40u16:
      return OpcodeEntry(opcode: opcode, mask: 0xFFC0u16, match: 0x4C40u16, kind: opRemu, mnemonic: "REMU")
    else:
      return OpcodeEntry(opcode: opcode, mask: 0xF000u16, match: 0xC000u16, kind: opAnd, mnemonic: "AND")

  # Line D: ADD, ADDA, ADDX
  if (opcode and 0xF000u16) == 0xD000u16:
    if (opcode and 0xF0C0u16) == 0xD0C0u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF0C0u16, match: 0xD0C0u16, kind: opAdda, mnemonic: "ADDA")
    elif (opcode and 0xF130u16) == 0xD100u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF130u16, match: 0xD100u16, kind: opAddx, mnemonic: "ADDX")
    else:
      return OpcodeEntry(opcode: opcode, mask: 0xF000u16, match: 0xD000u16, kind: opAdd, mnemonic: "ADD")

  # Line E: Shift & Rotate
  if (opcode and 0xF000u16) == 0xE000u16:
    if (opcode and 0xF118u16) == 0xE000u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF118u16, match: 0xE000u16, kind: opAsr, mnemonic: "ASR")
    elif (opcode and 0xF118u16) == 0xE100u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF118u16, match: 0xE100u16, kind: opAsl, mnemonic: "ASL")
    elif (opcode and 0xF118u16) == 0xE008u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF118u16, match: 0xE008u16, kind: opLsr, mnemonic: "LSR")
    elif (opcode and 0xF118u16) == 0xE108u16:
      return OpcodeEntry(opcode: opcode, mask: 0xF118u16, match: 0xE108u16, kind: opLsl, mnemonic: "LSL")

  return OpcodeEntry(opcode: opcode, mask: 0x0000u16, match: 0x0000u16, kind: opIllegal, mnemonic: "ILLEGAL")

proc buildDecodeTable*(): DecodeTable =
  for i in 0..65535:
    result[i] = decodeSingleOpcode(uint16(i))

# Global 65536-entry decode table
var defaultDecodeTable*: DecodeTable
var isTableInitialized = false

proc getDecodeTable*(): ptr DecodeTable =
  if not isTableInitialized:
    defaultDecodeTable = buildDecodeTable()
    isTableInitialized = true
  return addr(defaultDecodeTable)

# JSON Determinism Export per M-9
proc exportDecodeTableJson*(table: openArray[OpcodeEntry]): string =
  var root = newJObject()
  root["architecture"] = %"ColdFire_v3"
  root["determinism_version"] = %"M-9"
  root["total_opcodes"] = %(table.len)

  var listNode = newJArray()
  for i, entry in table:
    var item = newJObject()
    item["index"] = %i
    item["opcode"] = %("0x" & toHex(int64(entry.opcode), 4))
    item["kind"] = %($entry.kind)
    item["mnemonic"] = %entry.mnemonic
    item["mask"] = %("0x" & toHex(int64(entry.mask), 4))
    item["match"] = %("0x" & toHex(int64(entry.match), 4))
    listNode.add(item)

  root["table"] = listNode
  return pretty(root)

proc exportDecodeTableJson*(): string =
  let tbl = getDecodeTable()
  return exportDecodeTableJson(tbl[])

proc exportDeterminismJson*(): string =
  return exportDecodeTableJson()
