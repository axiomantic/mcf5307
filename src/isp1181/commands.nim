## The ISP1181 command set, as a total classification of the command byte.
##
## The classification is total and has three classes, not two. The authority
## gives a list of commands the model needs and a list it does not, and between
## them those two lists leave most of the command byte's range unnamed. A model
## with two classes has to put the rest somewhere, and either choice is wrong in
## a way that is hard to see later: called implemented, they answer plausibly;
## called not-implemented, a real gap in the specification is reported as a
## decision somebody took.
##
## The six data-flow commands - buffer write, buffer read, stall, status,
## validate and clear - are numbered here from Table 109 of the ISP1362 data
## sheet, Rev. 06. That document states that it integrates the ISP1181B
## peripheral controller, which is a claim of integration and not a statement
## that the two command maps are byte-identical, and the ISP1181B data sheet
## itself was not read. Every opcode below is therefore inherited rather than
## read from the part this model names. A firmware that disagrees with one of
## these opcodes is evidence against the inheritance, not a bug in the
## firmware.
##
## `ccUnspecified` is the class of every byte the authority does not number.
## The general commands - error code, unlock, scratch - are numbered by Table
## 109 and not adopted here: adopting a family nothing drives would be
## inheritance without a consumer.
##
## MIT licensed and clean-room with respect to GPL and LGPL code. Nothing here
## is copied from a Philips or NXP document.

type
  CommandClass* = enum
    ## `ccUnspecified` is the class of every command byte the authority does not
    ## number, and it is the default: a byte enters the other two classes only by
    ## appearing in a table below.
    ccUnspecified
    ccImplemented
    ccNotImplemented
    ccIllegal
      ## A byte the authority numbers and forbids. It is kept apart from
      ## `ccUnspecified` because the two are different findings: one is a byte
      ## no document describes, the other is a byte a document describes as
      ## having no legal meaning.

  Command* = object
    class*: CommandClass
    name*: string
    detail*: string
      ## Why `ccIllegal` is illegal, in the authority's own terms. Empty for
      ## every other class.

const unnumberedCommands*: seq[string] = @[]
  ## The commands the authority names and does not number. It is empty and it
  ## is kept: a command that arrives named-but-unnumbered is then an edit to a
  ## list rather than a new mechanism, and the empty case stays asserted rather
  ## than merely absent.

const modelEndpoints = 4
  ## Endpoints 0 to 3, which are the endpoints this model's FIFOs cover. The
  ## authority numbers 0 to 14 in every data-flow family; the rest are numbered
  ## and not carried here.

type Family = object
  ## One command family whose sixteen codes address the sixteen endpoint
  ## buffers in order, as the three pieces every such row has: where the family
  ## starts, which byte (if any) the authority parenthesises as illegal, and
  ## what to call it.
  ##
  ## The ordering is the same for every family. ISP1362 Rev. 06 section 15.1.1
  ## states the endpoint-configuration codes as "20 to 2F - write (control OUT,
  ## control IN, endpoints 1 to 14)", and Table 109 gives the data-flow
  ## families the same shape. Every family here is numbered by this one
  ## procedure, so the ordering cannot drift for one of them alone.
  controlOut: int      ## opcode of the control OUT form, or -1 when illegal
  controlIn: int       ## opcode of the control IN form, or -1 when illegal
  endpointBase: int    ## opcode of endpoint 1's form
  noun: string
  illegalOpcode: int   ## the parenthesised byte, or -1 when the family has none
  illegalName: string
  illegalDetail: string
  allEndpoints: bool
    ## The family is implemented for every endpoint the authority numbers and
    ## not only for the ones this model buffers. It is true for the family
    ## whose target is a register the part carries for all sixteen slots and
    ## false for one whose target is buffer memory. ISP1362 Rev. 06 section
    ## 15.1.1 p.107 states that the buffer memory "takes place only after all
    ## 16 endpoints have been configured in sequence (from endpoint 0 OUT to
    ## endpoint 14)", so a device that refused one of those slots could not
    ## complete the sequence the same section requires of the firmware.

const families: array[8, Family] = [
  Family(controlOut: -1, controlIn: 0x01, endpointBase: 0x02,
         noun: "buffer write", illegalOpcode: 0x00,
         illegalName: "write control OUT buffer",
         illegalDetail: "the endpoint is read-only"),
  Family(controlOut: 0x10, controlIn: -1, endpointBase: 0x12,
         noun: "buffer read", illegalOpcode: 0x11,
         illegalName: "read control IN buffer",
         illegalDetail: "the endpoint is write-only"),
  Family(controlOut: 0x40, controlIn: 0x41, endpointBase: 0x42,
         noun: "stall", illegalOpcode: -1, illegalName: "", illegalDetail: ""),
  Family(controlOut: 0x50, controlIn: 0x51, endpointBase: 0x52,
         noun: "status", illegalOpcode: -1, illegalName: "", illegalDetail: ""),
  Family(controlOut: -1, controlIn: 0x61, endpointBase: 0x62,
         noun: "buffer validate", illegalOpcode: 0x60,
         illegalName: "validate control OUT buffer",
         illegalDetail: "validating an OUT buffer is unpredictable"),
  Family(controlOut: 0x70, controlIn: -1, endpointBase: 0x72,
         noun: "buffer clear", illegalOpcode: 0x71,
         illegalName: "clear control IN buffer",
         illegalDetail: "clearing an IN buffer is unpredictable"),
  Family(controlOut: 0x80, controlIn: 0x81, endpointBase: 0x82,
         noun: "unstall", illegalOpcode: -1, illegalName: "",
         illegalDetail: ""),
  # The one row that is not from Table 109. The endpoint-configuration codes
  # come from ISP1362 Rev. 06 section 15.1.1 and the register they write from
  # Table 110. Both citations are inherited from a part that only claims to
  # integrate the ISP1181B.
  Family(controlOut: 0x20, controlIn: 0x21, endpointBase: 0x22,
         noun: "configuration", illegalOpcode: -1, illegalName: "",
         illegalDetail: "", allEndpoints: true)]

proc classifyFamily(opcode: int): (bool, Command) =
  ## The data-flow families of Table 109. `false` means no family claims the
  ## byte, which is not the same as the byte being unspecified: the caller
  ## still has the register families and the general commands to try.
  ##
  ## A CLASS ANSWERS "IS THERE A BUFFER BEHIND THIS OPCODE", AND NEVER "WHICH
  ## WAY IS IT FACING". The two questions were entangled here while the IN
  ## families were refused for endpoints 1 to 3, and disentangling them is what
  ## let those families be implemented. A class is a property of the opcode, and
  ## `modelEndpoints` - the buffer memory this model carries - is a property of
  ## the opcode too, so the class may depend on it. EPDIR is not: it is a bit
  ## the firmware writes and rewrites at run time, and a classification that
  ## moved with it would answer a different thing at two instants.
  ##
  ## THE AUTHORITY PUTS THE DIRECTION IN THE SAME PLACE. ISP1362 Rev. 06
  ## Table 109 p.105-106 numbers `02` to `0F` and `62` to `6F` for endpoints 1
  ## to 14 with no configuration attached to the CODE, and annotates the
  ## destination "(IN endpoints only)". What happens when the direction is wrong
  ## is stated as BEHAVIOUR and not as a missing code: section 15.2.1 p.114
  ## remarks that "There is no protection against ... writing into an OUT buffer
  ## or reading from an IN buffer. Any of these actions can cause an incorrect
  ## operation", and Table 109 note [4] p.106 gives validating an OUT endpoint
  ## buffer as "unpredictable behavior". So the direction is a RUN-TIME
  ## PRECONDITION of the command, and `src/isp1181/isp1181.nim` refuses it there
  ## by name.
  ##
  ## `ccIllegal` IS STILL RESERVED FOR THE BYTES THE AUTHORITY PARENTHESISES -
  ## `00`, `11`, `60` and `71`. Those are forbidden by the CODE, whatever any
  ## register says, and none of `02` to `0F` or `62` to `6F` is parenthesised.
  for family in families:
    if family.illegalOpcode == opcode:
      return (true, Command(class: ccIllegal, name: family.illegalName,
                            detail: family.illegalDetail))
    if family.controlOut == opcode:
      return (true, Command(class: ccImplemented,
                            name: "control OUT " & family.noun))
    if family.controlIn == opcode:
      return (true, Command(class: ccImplemented,
                            name: "control IN " & family.noun))
    if opcode >= family.endpointBase and opcode < family.endpointBase + 14:
      let endpoint = opcode - family.endpointBase + 1
      let name = "endpoint " & $endpoint & " " & family.noun
      if family.allEndpoints or endpoint < modelEndpoints:
        return (true, Command(class: ccImplemented, name: name))
      return (true, Command(class: ccNotImplemented, name: name))
  (false, Command(class: ccUnspecified, name: ""))

proc classify*(opcode: uint8): Command =
  ## The class and the name of one command byte. THE ONLY PLACE EITHER LIST IS
  ## WRITTEN DOWN.
  let (claimed, dataFlow) = classifyFamily(int(opcode))
  if claimed:
    return dataFlow

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
