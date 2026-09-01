## `bus` - the bus-fault channel: the one mapping from a board's bus status to
## the fault status code the exception frame carries.
##
## The `FS` codes are imported rather than spelled a second time, so the
## mapping and the frame layout cannot drift apart.

import mcf5307/decode_types
import mcf5307/exception

type
  BusAccess* = enum
    ## The direction of the access that faulted. An operand read and an operand
    ## write each carry their own code.
    operandRead
    operandWrite

# Only `busFault` has a hardware producer on this part, and the other two rows
# are this emulator's own extension rather than an encoding of silicon
# behaviour. The one documented producer is the RAMBAR write-protect bit.
#
# The extension rows borrow the hardware codes rather than inventing one.
# Table 3-3 reserves every value outside its five, so a code of this module's
# own choosing would be a reserved value in a field a firmware handler decodes.

proc isEmulatorExtension*(status: Mcf5307BusStatus): bool =
  ## Whether a status is one this part cannot raise.
  ##
  ## The class is a value and not a comment, so that a reader who takes an
  ## extension row for silicon behaviour can be contradicted by a case.
  status == Mcf5307BusStatus.busUnmapped or
    status == Mcf5307BusStatus.busSizeIllegal

proc faultStatusFor*(status: Mcf5307BusStatus; access: BusAccess): uint32 =
  ## The `FS` code for a status and a direction.
  ##
  ## Total over the enumeration, and `busOk` is mapped rather than rejected: a
  ## partial mapping would need a caller to prove it had excluded `busOk`
  ## first, and the `0000` code already means "not an access or address error",
  ## which is what a completed access is.
  ##
  ## `busFault` takes the same code in both directions. Its row names a store
  ## to write-protected space, which is the only access that raises it on
  ## silicon; a board that reports it on a read is outside the manual either
  ## way, and a second code would say something the manual does not.
  case status
  of Mcf5307BusStatus.busOk: fsNotAnAccessError
  of Mcf5307BusStatus.busFault: fsWriteProtected
  of Mcf5307BusStatus.busUnmapped, Mcf5307BusStatus.busSizeIllegal:
    case access
    of operandRead: fsOperandRead
    of operandWrite: fsOperandWrite
