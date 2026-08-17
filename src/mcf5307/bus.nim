## `bus` - the bus-fault channel: the one mapping from a board's bus status to
## the fault status code the exception frame carries.
##
## A leaf: every procedure is a function of a status value and a direction, so
## nothing here needs an edge to an executor.
##
## THE `FS` CODES ARE NAMED AND NOT RESTATED. This module imports them rather
## than spelling the bit patterns a second time, so the mapping and the layout
## cannot drift apart.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. The fault
## status encodings are facts about Motorola silicon, from the MCF5307 User's
## Manual (1998).

import mcf5307/decode_types
import mcf5307/exception

type
  BusAccess* = enum
    ## The direction of the access that faulted. An operand read and an operand
    ## write each carry their own code.
    operandRead
    operandWrite

# ONLY `busFault` HAS A HARDWARE PRODUCER ON THIS PART, and the remaining rows
# are this emulator's own extension rather than an encoding of silicon
# behaviour. The one documented producer is the RAMBAR write-protect bit.
#
# THE EXTENSION ROWS BORROW THE HARDWARE CODES RATHER THAN INVENTING ONE. Every
# value outside the documented set is reserved, so a code of this module's own
# choosing would be a reserved value in a field a firmware handler decodes.

proc isEmulatorExtension*(status: Mcf5307BusStatus): bool =
  ## Whether a status is one this part cannot raise.
  ##
  ## THE CLASS IS A VALUE AND NOT A COMMENT, so that a reader who takes an
  ## extension row for silicon behaviour can be contradicted by a case.
  status == Mcf5307BusStatus.busUnmapped or
    status == Mcf5307BusStatus.busSizeIllegal

proc faultStatusFor*(status: Mcf5307BusStatus; access: BusAccess): uint32 =
  ## The `FS` code for a status and a direction.
  ##
  ## TOTAL OVER THE ENUMERATION, and `busOk` is mapped rather than rejected: a
  ## partial mapping would need a caller to prove it had excluded `busOk`
  ## first, and the `0000` code already means "not an access or address error",
  ## which is what a completed access is.
  ##
  ## `busFault` TAKES THE SAME CODE IN BOTH DIRECTIONS. Its row names a store
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
