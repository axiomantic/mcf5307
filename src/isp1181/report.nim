## `isp1181/report` - the model's whole account as one block of text.
##
## WHY IT EXISTS. The model wrote its answers into `log`, and reading them from
## outside meant a loop over `isp1181_log_line`, one call per line, plus two
## more calls for the counters and no way at all to see the endpoint
## configuration. Every consumer that wanted the account therefore wrote that
## loop itself, and the consumer that mattered - gearmulator's `g2Lib` - could
## only get it by an out-of-tree patch that was hand-applied and hand-reverted
## on each run. A patch applied to a checkout another author is editing
## discards their work, and that came within one measurement of happening.
##
## SO THE ACCOUNT IS ASSEMBLED HERE, WHERE THE DATA IS, and the caller makes
## one call. `isp1181/stub` publishes it as `isp1181_report`, and the
## teardown hook there writes it to a file when one environment variable names
## a path - which is how a consumer gets the account with NO EDIT OF ITS OWN.
##
## TWO PROPERTIES OF THE LOG SURVIVE INTO THE TEXT AND THEY ARE THE REASON THE
## LOG IS SHAPED AS IT IS.
##
## 1. TRUNCATION IS VISIBLE. `written` and `retained` are two figures because
##    their DIFFERENCE is the number of lines the reader cannot see. This text
##    prints all three and then states which of the two cases holds in words,
##    so a reader who never subtracts still cannot mistake a truncated account
##    for a whole one.
## 2. THE LINES KEPT ARE THE FIRST ONES. A ring would hold the end of a run and
##    lose the first refusal, and the first refusal is what explains everything
##    downstream of it. The truncation line says so rather than leaving the
##    reader to know it.
##
## AND ONE PROPERTY THE REGISTER FILE COULD NOT CARRY ON ITS OWN. A
## configuration slot the firmware never wrote holds `0x00`, and `0x00` is also
## a byte the firmware may write. `configSlotWritten` is what separates them,
## and this text reports NEVER WRITTEN and a written `0x00` as two different
## sentences. One sentence for both facts is the defect this device model was
## built to expose.
##
## MIT licensed and clean-room with respect to GPL and LGPL code.

import std/strutils

import ./isp1181

const reportBegins* = "isp1181: report begins"
const reportEnds* = "isp1181: report ends"
  ## THE TWO FENCES ARE PART OF THE CONTRACT AND NOT DECORATION. The teardown
  ## hook APPENDS, so one file may hold several reports, and a reader needs a
  ## mark that says where one ends. A report that stopped early - a short write,
  ## a full disk - is then a report with no closing fence, which is a visible
  ## failure rather than a shorter account that reads as a complete one.

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
  ## A NIL MODEL STILL PRODUCES A REPORT. It reports zero of everything and
  ## sixteen never-written slots, which is true of a handle that was never
  ## driven; returning an empty string would be an account that reads as a
  ## missing one.
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
      # NEVER WRITTEN IS NOT A CONFIGURATION AND NO BYTE IS PRINTED HERE. The
      # register holds its reset value, and printing it beside the other slots
      # would offer a byte the firmware never sent as though it had.
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
