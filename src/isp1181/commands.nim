## The ISP1181 command set, as a total classification of the command byte.
## Task CPU-22. Design section 9.2.
##
## THE CLASSIFICATION IS TOTAL AND HAS THREE CLASSES, NOT TWO. Design section
## 9.2 gives a list of commands the model needs and a list it does not, and
## between them those two lists number only 33 of the 256 command bytes. A
## model with two classes has to put the remaining 223 somewhere, and either
## choice is wrong in a way that is hard to see later: called implemented, they
## answer plausibly; called not-implemented, a real gap in the specification is
## reported as a decision somebody took.
##
## THE GAP, STATED WHERE IT LIVES. Design section 9.2 and `AGENTS.md` section
## 3.8 both name SIX commands with no opcode at all - buffer write, buffer
## read, stall, status, validate and clear. Both documents give an opcode for
## every other command they name. No ISP1181 datasheet and no ISP1362 driver
## header exists on this machine, and design section 9.2 records that no
## open-source ISP1181 emulation exists anywhere either. So there is no source
## from which those six opcodes could be read, and this file assigns them
## none: an opcode chosen here would be a guess that the firmware would obey.
## `unnumberedCommands` below carries the six by name so that closing the gap
## is an edit to a list.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Nothing here
## is copied from a Philips or NXP document.

type
  CommandClass* = enum
    ## `ccUnspecified` is the class of every command byte the authority does
    ## not number, and it is the DEFAULT: a byte enters the other two classes
    ## only by appearing in a table below.
    ccUnspecified
    ccImplemented
    ccNotImplemented

  Command* = object
    class*: CommandClass
    name*: string

const unnumberedCommands*: array[6, string] = [
  "buffer write", "buffer read", "stall", "status", "validate", "clear"]
  ## THE COMMANDS THE AUTHORITY NAMES AND DOES NOT NUMBER. They are not
  ## implemented, and they are not "not implemented" either: nothing decided
  ## against them. This array is the whole of what is known about them.

const
  epConfigBase = 0x20'u8
    ## Design section 9.2: endpoint configuration is `0x20+idx`. It is the one
    ## command family the authority gives a base for.
  epConfigImplemented = 4
    ## Endpoints 0 to 3, which are the endpoints the five FIFOs cover. Design
    ## section 9.2 places endpoints 4 to 14 in the not-needed list.
  epConfigNumbered = 15
    ## `0x20+14` is the last endpoint the authority names in either direction.
    ## `0x2F` is numbered by neither list and falls to `ccUnspecified`.

proc classify*(opcode: uint8): Command =
  ## The class and the name of one command byte. THE ONLY PLACE EITHER LIST IS
  ## WRITTEN DOWN.
  if opcode >= epConfigBase and
      int(opcode) < int(epConfigBase) + epConfigNumbered:
    let index = int(opcode) - int(epConfigBase)
    if index < epConfigImplemented:
      return Command(class: ccImplemented,
                     name: "endpoint " & $index & " configuration")
    return Command(class: ccNotImplemented,
                   name: "endpoint " & $index & " configuration")

  case opcode
  of 0xF6'u8: Command(class: ccImplemented, name: "reset")
  of 0xBA'u8: Command(class: ccImplemented, name: "write hardware configuration")
  of 0xBB'u8: Command(class: ccImplemented, name: "read hardware configuration")
  of 0xB8'u8: Command(class: ccImplemented, name: "write mode")
  of 0xB9'u8: Command(class: ccImplemented, name: "read mode")
  of 0xB6'u8: Command(class: ccImplemented, name: "write device address")
  of 0xB7'u8: Command(class: ccImplemented, name: "read device address")
  of 0xD2'u8: Command(class: ccImplemented, name: "peek")
  of 0xC0'u8: Command(class: ccImplemented, name: "read interrupt register")
  of 0xC2'u8: Command(class: ccImplemented, name: "write interrupt enable")
  of 0xC3'u8: Command(class: ccImplemented, name: "read interrupt enable")
  of 0xF4'u8: Command(class: ccImplemented, name: "acknowledge setup")
  of 0xF0'u8, 0xF1'u8, 0xF2'u8, 0xF3'u8:
    Command(class: ccNotImplemented, name: "DMA")
  of 0xB5'u8: Command(class: ccNotImplemented, name: "chip identifier")
  of 0xB4'u8: Command(class: ccNotImplemented, name: "frame number")
  else: Command(class: ccUnspecified, name: "")
