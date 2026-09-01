## `isp1181/report` - the model's whole account as one block of text.
##
## `written` and `retained` are two figures because their difference is the
## number of lines the reader cannot see.
##
## The lines kept are the FIRST ones, not the last. A ring would hold the end
## of a run and lose the first refusal, and the first refusal is what explains
## everything downstream of it.
##
## A configuration slot the firmware never wrote holds `0x00`, and `0x00` is
## also a byte the firmware may write. `configSlotWritten` is what separates
## them, and this text reports never-written and a written `0x00` as two
## different sentences.

import std/strutils

import ./isp1181

const reportBegins* = "isp1181: report begins"
const reportEnds* = "isp1181: report ends"
  ## The teardown hook appends, so one file may hold several reports. A report
  ## that stopped early - a short write, a full disk - has no closing fence.

proc slotEndpointName(slot: int): string =
  ## The endpoint the slot configures. ISP1362 Rev. 06 section 15.1.1 p.107
  ## orders the sixteen slots control OUT, control IN, then endpoints 1 to 14,
  ## and `fifoNames` is in that same order for the five slots this model
  ## carries a buffer for.
  if slot < fifoCount: fifoName(slot)
  else: "endpoint " & $(slot - 1)

proc slotBufferName(slot: int): string =
  if slot < fifoCount: "buffer " & $slot else: "no buffer in this model"

proc reportText*(m: ISP1181): string =
  ## The whole account: the counters, the truncation verdict in words, every
  ## configuration slot, and every retained line with its place in the
  ## sequence.
  ##
  ## A nil model still produces a report: zero of everything and every slot
  ## never written, which is true of a handle that was never driven.
  result = newStringOfCap(4096)

  template line(s: string) =
    result.add(s)
    result.add('\n')

  let written = logWritten(m)
  let retained = logRetained(m)
  let dropped = written - retained

  line(reportBegins)
  line("isp1181: log written=" & $written & " retained=" & $retained &
       " dropped=" & $dropped)
  if dropped == 0:
    line("isp1181: log COMPLETE - every line the model wrote is below")
  else:
    line("isp1181: log TRUNCATED - " & $dropped & " lines the model wrote " &
         "are NOT below. The " & $retained & " retained are the FIRST the " &
         "model wrote and not the last, so the earliest refusal is present " &
         "and what was lost is the tail. The bound is " & $logCapacity &
         " lines.")

  line("isp1181: configuration slots=" & $configSlotCount &
       ", in ISP1362 Rev. 06 section 15.1.1 order. EPDIR is bit 6 (0x" &
       toHex(epdirBit) & ") of DcEndpointConfiguration, Table 110 and Table " &
       "111 p.107, 0=OUT 1=IN, and every bit resets to 0.")
  for slot in 0 ..< configSlotCount:
    let head = "isp1181: config slot " & $slot & " command 0x" &
      toHex(uint8(0x20 + slot)) & " " & slotEndpointName(slot) & " " &
      slotBufferName(slot) & ": "
    if not configSlotWritten(m, slot):
      # No byte is printed: the register holds its reset value, and printing it
      # beside the other slots would offer a byte the firmware never sent as
      # though it had.
      line(head & "NEVER WRITTEN")
    else:
      let value = configSlotValue(m, slot)
      let epdir = (value and epdirBit) != 0
      line(head & "written 0x" & toHex(value) & " EPDIR=" &
           (if epdir: "1 IN" else: "0 OUT") & " at event " &
           $configSlotOrdinal(m, slot))

  line("isp1181: log lines follow, " & $retained & " retained")
  for index in 0 ..< retained:
    line("isp1181: log[" & $index & "] event " & $logOrdinal(m, index) &
         ": " & logLine(m, index))
  line(reportEnds)
