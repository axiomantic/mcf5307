## `bus` - the bus-fault channel: the one mapping from a board's bus status to
## the fault status code the exception frame carries.
##
## The `FS` codes are imported rather than spelled a second time, so the
## mapping and the frame layout cannot drift apart.

import mcf5407/decode_types
import mcf5407/exception

type
  BusAccess* = enum
    ## The direction of the access that faulted. MCF5407 User's Manual Table
    ## 2-21, "Fault Status Encodings", folio 2-33: an operand read and an
    ## operand write each carry their own code.
    operandRead
    operandWrite

# Only `busFault` has a hardware producer on this part, and the other two rows
# are this emulator's own extension rather than an encoding of silicon
# behaviour. MCF5407 User's Manual Table 2-22, "MCF5407 Exceptions", folio
# 2-34, Access Error row, verbatim: "Access errors are reported only in
# conjunction with an attempted store to write-protected memory. Thus, access
# errors associated with instruction fetch or operand read accesses are not
# possible." The MCF5307 manual said the same thing in its section 3.5.1, so
# this rule did not change with the part - only where the manual prints it. The
# one documented producer is the RAMBAR write-protect bit, section 4.5.1,
# "SRAM Initialization Code", folio 4-4: "else Signal a write-protect access
# error".
#
# THE SAME ROW ADDS A SENTENCE THE MCF5307'S DID NOT: "The Version 4 processor,
# unlike the Version 2 and 3 processors, updates the condition code register if
# a write-protect error occurs during a CLR or MOV3Q operation to memory." This
# is a V4, so a faulting `CLR` to write-protected memory leaves the condition
# codes written. MOV3Q is a Revision B opcode this core does not decode at all,
# so only the `CLR` half is reachable. The manual does not say WHAT value the
# register takes; the block above `execClr` in `alu.nim` names the value this
# core chose and argues for it, and `machine.nim`'s `pendingWriteFaultTakesCc`
# is what puts it in the frame.
#
# The extension rows borrow the hardware codes rather than inventing one.
# Table 3-3 reserves every value outside its five, so a code of this module's
# own choosing would be a reserved value in a field a firmware handler decodes.

proc isEmulatorExtension*(status: Mcf5407BusStatus): bool =
  ## Whether a status is one this part cannot raise.
  ##
  ## The class is a value and not a comment, so that a reader who takes an
  ## extension row for silicon behaviour can be contradicted by a case.
  status == Mcf5407BusStatus.busUnmapped or
    status == Mcf5407BusStatus.busSizeIllegal

proc faultStatusFor*(status: Mcf5407BusStatus; access: BusAccess): uint32 =
  ## The `FS` code for a status and a direction.
  ##
  ## Total over the enumeration, and `busOk` is mapped rather than rejected: a
  ## partial mapping would need a caller to prove it had excluded `busOk`
  ## first, and Table 3-3's `0000` already means "not an access or address
  ## error", which is what a completed access is.
  ##
  ## `busFault` takes the same code in both directions. Its row names a store
  ## to write-protected space, which is the only access that raises it on
  ## silicon; a board that reports it on a read is outside the manual either
  ## way, and a second code would say something the manual does not.
  case status
  of Mcf5407BusStatus.busOk: fsNotAnAccessError
  of Mcf5407BusStatus.busFault: fsWriteProtected
  of Mcf5407BusStatus.busUnmapped, Mcf5407BusStatus.busSizeIllegal:
    case access
    of operandRead: fsOperandRead
    of operandWrite: fsOperandWrite
