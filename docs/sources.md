# Sources

Every external document a source header in `src/` or `include/` cites, and
where that document lives.

## Why this register records no filesystem path

A path is true on one machine. A reader on any other machine reaches a
citation and cannot follow it, and the citation looks like a working
reference the whole time.

So a source header cites a document by **title and revision** and never by a
path, and this file states the document's identity — publisher, designation,
and where a copy is checked against — rather than a location on somebody's
disk. `tests/t0_no_local_paths.c` is the registered check that keeps the first
half true; nothing checks the second half except this file.

**Identity is stated as a hash where a hash is known.** A title and a
revision name an edition. A hash names the copy a measurement was taken
against, which is the thing a later reader actually has to reproduce.

## The documents

| Cited in a header as | Document | Where it lives |
|---|---|---|
| "the ColdFire Family Programmer's Reference Manual", "…, Rev. 3" | *CFPRM, ColdFire® Family Programmer's Reference Manual*, Freescale Semiconductor. Vendor designation `CFPRM`. Revision 3. | **Not in this repository.** Obtain the PDF from the vendor archive by its designation. |
| "the MCF5307 User's Manual", "… (1998)", "the manual's timing tables" | Motorola, *MCF5307 ColdFire Integrated Microprocessor User's Manual*, `MCF5307UM/AD`, 1998. 456 pages, scanned paper. SHA-256 `86cbcc8c9caa933fe10275a975a78d914df86771df9f0bc22d03de8b1aff91fa`. | **Not in this repository.** Obtain the PDF by its designation and check the hash before using a value from it. |
| "the authority" (`src/isp1181/`), for everything except the data-flow command opcodes | **UNNAMED.** See below. | Unknown. |
| "Table 109 of the ISP1362 data sheet, Rev. 06", "ISP1362 Rev. 06 Table 143", "ISP1362 Rev. 06 p.53" (`src/isp1181/commands.nim`, `src/isp1181/isp1181.nim`, `tests/t_isp1181.nim`, `tests/t_isp1181_command_set.nim`) | ST-NXP Wireless, *ISP1362 — Single-chip USB On-The-Go controller*, Product data sheet, doc id `ISP1362_6`, Rev. 06, 21 January 2009. 149 pages. SHA-256 `4deba3293e2c10bd3e93c159c50a3ba111d138f389a1456e8484a361e307a856`, 4,264,300 bytes. | **Not in this repository.** Obtain the PDF by its designation and revision, and check the hash before using a value from it. **It is not a document about the part this model names — see "The inherited command map" below before using a value from it.** |
| Not yet cited in any header. Corroborates the DcEndpointConfiguration, DcEndpointStatus and DcInterrupt readings recorded below. | Philips Semiconductors, *ISP1362 Embedded Programming Guide*, application note `AN10008-01`, internal Rev. 0.9, June 2002. 99 pages. SHA-256 `77ce2e5c3cd82969f1465b068e36ffb7335fe99823ef69479d59d3ab15d34aa3`. | **Not in this repository.** Obtain by its designation and check the hash. **It is an APPLICATION NOTE and not a data sheet, and it is about the ISP1362 and not the ISP1181B — the inheritance limit below applies to it unchanged.** |

**ColdFire condition codes differ from the 68000.** The CFPRM is the
authority for them, and a 68000 reference is not. `AGENTS.md` states the same
rule beside the clean-room rule, which is where an implementer meets it
first.

**A machine conversion of a scanned manual is not the manual.** A markdown or
OCR derivative may be used to FIND a page. The value goes into code only
after the page it names is read in the original. A scanned source carries
table errors that look completely normal on the page.

## The inherited command map

**The data-flow command opcodes in `src/isp1181/` were not read from an ISP1181
document.** They are taken from Table 109 (pp.105-106) of the ISP1362 data
sheet, Rev. 06, and they are recorded here as **inherited**, which is a weaker
thing than cited.

**The integration claim, in the document's own words** (p.1): the ISP1362 "is a
single-chip USB On-The-Go (OTG) controller integrated with the advanced ST-NXP
Wireless slave host controller and the ST-NXP Wireless ISP1181B peripheral
controller."

**THE LIMIT. That is a manufacturer's statement of INTEGRATION. It is not a
statement that the register and command maps are byte-identical.** The document
says elsewhere (p.51) only that the peripheral controller's functionality "is
similar to the ISP1181B in 16-bit bus mode". Similar is not identical, and this
repository has no document that closes the difference.

**The ISP1181B data sheet itself was NOT retrieved.** The target is
`ISP1181B`, Rev. 02, roughly 70 pages. Five fetch attempts against the
distributor host timed out. Until that document is read, every opcode in the
seven data-flow families is inherited and unverified against the part.

**Corroboration is weak and is labelled weak.** A search result for an
**ISP1181A** page appeared to match the low-nibble scheme. That page returned
HTTP 403 and **was never read**, so it corroborates nothing and is recorded
only so that a later reader does not mistake it for a second source.

**AND `ISP1160` IS NOT THIS PART.** An `ISP1160` data sheet may be found beside
the ISP1362 one. It is a USB HOST controller, not a peripheral controller, and
nothing in this repository cites it. It is named here only so that a later reader
meets the difference rather than adopting a value from it.

**What would settle it.** Read the ISP1181B data sheet's own command overview
table and compare it, opcode by opcode, against the literals in
`tests/t_isp1181_command_set.nim`. That suite types every opcode out by hand
for exactly this reason: a part whose map differs turns it red rather than
letting the difference pass.

**What is NOT inherited from ISP1362.** Only the seven data-flow families -
buffer write, buffer read, stall, status, validate, clear and unstall - and the
four codes that table parenthesises as illegal. The register families, the peek
command and the interrupt behaviour still cite the unnamed authority below, and
the general commands that table numbers (error code, unlock, scratch) were
**not** adopted: inheriting a family nothing drives would spend the same
uncertainty for no consumer.

## The interrupt-register bit assignment

**The five endpoint-completion bits are assigned, and they are the only bits
that are.** The assignment lives in `interruptBitOfFifo` in
`src/isp1181/isp1181.nim`: bit 8 for endpoint 0 OUT, bit 9 for endpoint 0 IN,
and bits 10, 11 and 12 for endpoints 1, 2 and 3.

**TWO SOURCES AGREE ON THAT RANGE, AND ONE OF THEM IS THIS MACHINE'S OWN
FIRMWARE.** That is a stronger position than anything else in `src/isp1181/`
holds, and it is still not a citation.

| Source | What it says | What it is worth |
|---|---|---|
| The emulated firmware's service routine at `CODE:0x30053C38` | Reads four status bytes, returns at once when they are zero, dispatches bits 0, 1 and 2 to bus routines, bits 8 and 9 to fixed routines, and bits 10 to 16 through a table of per-endpoint function pointers at `0x30119C62`. Its enable write, command `0xC2` with `0x00001F07`, arms bits 0, 1, 2 and 8 to 12 at three call sites. | A **measurement of the program this model has to satisfy**. It is not a statement about the part, and a different firmware image could dispatch differently. |
| ISP1362 Rev. 06, Tables 142 and 143, p.121 | Bit 0 `RESET`, 1 `RESUME`, 2 `SUSPND`, 3 `EOT`, 4 `SOF`, 5 `PSOF`, 6 `SP_EOT`, 7 `BUSTATUS`, 8 `EP0OUT`, 9 `EP0IN`, 10 to 23 `EP1` to `EP14`. | **INHERITED, exactly as the command map is.** The ISP1181B data sheet was not retrieved, and the integration claim recorded above is not a claim of a byte-identical register map. |

The agreement covers bit 0, bits 8 and 9 as the two control-endpoint
directions, and bits 10 and upwards as one bit per endpoint in order. The
firmware's enable arms bits 8 to 12 and this model carries exactly five
buffers, which is the same five.

**THE AGREEMENT ON BITS 11 AND 12 IS REACHED TWICE, BY ROUTES THAT SHARE NO
STEP, AND THAT IS THE STRONGEST CORROBORATION THIS PROJECT HOLDS.** The
firmware's own dispatch table, read off the booted machine, gives bit 11 the
TRANSMIT handler and bit 12 the RECEIVE handler. Table 142 gives bit 11 as `EP2`
and bit 12 as `EP3`, and the configuration bytes the firmware writes — recorded
below — make endpoint 2 IN and endpoint 3 OUT. IN is device to host, which is
transmit; OUT is host to device, which is receive. **Neither derivation used the
other**: one is a handler-address table, the other is a register bit map plus
three data bytes.

**WHERE THE TWO SOURCES DISAGREE, NOTHING IS ASSIGNED.** The firmware
dispatches bit 1 to suspend and bit 2 to resume; the inherited table calls bit
1 `RESUME` and bit 2 `SUSPND`. The two are swapped, and this repository has no
document that settles which is right.

**A SECOND ISP1362 DOCUMENT TAKES THE TABLE'S SIDE, AND IT DOES NOT SETTLE IT.**
`AN10008-01` §11.6.2, p.63, instructs the reader to *"Detect the suspend
interrupt (bit 2 of the DcInterrupt register)"*. That is two ISP1362 documents
against one firmware image, and the firmware is the only one of the three that
describes the part this model actually has to satisfy. **Weight of documents is
not evidence about a different part.** The disagreement stands.

**AND IT IS NOT A DEFECT IN THIS MODEL.** `interruptBitOfFifo` is the only thing
in `src/isp1181/isp1181.nim` that ever raises an interrupt bit, and it holds
`[8, 9, 10, 11, 12]`. Bits 0, 1 and 2 are never set by any route, so no code here
takes a side on the swap and no repair is owed while the disagreement is open.

**`AN10008-01` CORROBORATES THE SOURCE SET AND SUPPLIES NO OTHER POSITION.** Its
Figure 12-3, p.69, gives a worked service routine that tests bus reset, suspend,
EOT and SOF-or-pseudo-SOF as an exclusive chain and then the endpoint sources
`EP0IN`, `EP0OUT`, `EP01`, `EP02`, `EP03` and `EP0E`, all by symbolic name. **Its
Table 12-2 is a graphic and carries no extractable text**, so apart from the
suspend sentence above the numbers come from the data sheet and not from the
guide.

**What is deliberately NOT assigned, and why:**

| Bits | Why not |
|---|---|
| 0, 1, 2 — bus reset, suspend, resume | The sources disagree on 1 and 2, **and** this model's API carries no bus event at all: `isp1181_rx` delivers an endpoint and bytes, and `isp1181_setup` delivers a set-up packet. A bit nothing can set is a latch that never fires. **The set-up interlock was once the other example of this shape and is no longer**: it was cited here as a second case of a latch with nothing to set it, and `isp1181_setup` is the route that sets it. These three bits keep the shape on their own. |
| 3 to 7 — EOT, SOF, PSOF, SP\_EOT, BUSTATUS | The firmware's enable arms none of them and its service routine dispatches none of them, so the second source stands alone. The model has no end-of-transfer, no DMA and no frame source of its own — the frame counter lives in `src/isp1181/stub.nim` and is advanced by the caller. |
| 13 to 23 — EP4 to EP14 | This model carries no buffer for those endpoints, so no event here could set one. |

**The clearing route, and the hang it is there to prevent.** The interrupt
register does **not** clear when the firmware reads it with `0xC0`: the read
reports the register and leaves it, which is the behaviour a registered case in
`tests/t_isp1181.nim` already pinned before any bit could be set. The
firmware's service routine reads four status bytes and never writes them back,
so **a bit with no other route out of the register would leave the emulated
machine spinning in its own handler.** The route taken is a read of the owning
endpoint's status register, `0x50+n`.

**That route is INHERITED too**, from ISP1362 Rev. 06 p.53, which states that
the endpoint interrupt bit is cleared by reading `DcEndpointStatus` and that
the `D0`-`DF` *Check* forms of the same read explicitly do not clear it. The
model clears at the COMMAND rather than at the data-port read, because the
document separates the clearing form from the non-clearing one by the opcode.

**`AN10008-01` STATES THE SAME ROUTE IN WORDS**, p.73: the Read Endpoint Status
command, *"code 0x50"*, *"clears the control OUT interrupt bit of the Interrupt
register, and at the same time returns status information"*, and *"This clears
the corresponding endpoint interrupt."* **That is a second ISP1362 source for the
ROUTE and no source at all for the OPEN QUESTION**, which is whether the emulated
firmware actually issues `0x50` to `0x54`. A document cannot answer a question
about a program, so the `Unverified` row for it stands unchanged. It also says
nothing about clearing SETUPT itself — consistent with the inference recorded
below, and not a statement of it.

**`0xD2` is not treated as a Check form here.** ISP1362 numbers `D0`-`DF` as
check endpoint status; this model's `0xD2` is peek, from the unnamed authority
below. The two sources disagree about that byte, nothing in this change touches
it, and it is recorded so that a later reader meets the conflict rather than
discovering it.

**What would settle it.** Read the interrupt-register table and the
`DcEndpointStatus` description in the ISP1181B data sheet itself. Failing that,
run the emulated firmware against this model and observe whether its
per-endpoint handler issues `0x50` to `0x54`. **If it does not, the clearing
route is wrong and the machine will spin** — the model would then need a
different route, and inventing one without a source is what this file exists to
prevent.

## Two facts that were recorded as the authority's and are the firmware's

`src/isp1181/isp1181.nim` carried "endpoint 1 is 16 bytes" and "endpoint 3 is
single-buffered" as though they were fixed properties of the part. **Per ISP1362
Rev. 06 Table 110 (p.107), Table 111 (p.107) and Table 16 (p.52), both are
firmware-programmable**, so neither is a hardware fact:

| Recorded as | What it actually is |
|---|---|
| endpoint 1 holds 16 bytes | The buffer size is selected by `FFOSZ[3:0]` in the DcEndpointConfiguration register. Table 111 gives that field only as "Selects the buffer memory size according to Table 16"; **Table 16, p.52, is where the sizes are**, and it gives `0001` as 16 bytes for a non-isochronous endpoint. 16 bytes is a **configuration**, not a size the part has. |
| endpoint 3 is single-buffered | Buffering is selected per endpoint by the `DBLBUF` bit of the same register. Single-buffered is a **configuration**. |

**The observation is kept and only its label moves.** They are measurements of
THIS firmware and good evidence for what `fifoShape` should hold, not statements
about the silicon, and the difference matters the day a different firmware image
is run. **Where the values came from is no longer a supposition** — the section
below records the three configuration bytes the firmware writes, read out of the
booted machine.

## The endpoint directions the firmware configures

**MEASURED, in the consuming emulator, from the firmware's OWN endpoint-
configuration writes.** The recorder pairs each `0x20+slot` command with the data
byte that follows it, so these are bytes the G2 firmware writes at boot and not a
value any document supplies:

| Slot | Endpoint | Byte written | Bit 6 `EPDIR` | Direction |
|---|---|---|---|---|
| 2 | 1 | `0xE1` | 1 | IN — device to host |
| 3 | 2 | `0xE3` | 1 | IN — device to host |
| 4 | 3 | `0x83` | 0 | OUT — host to device |

Slot to endpoint is §15.1.1's own ordering — control OUT, control IN, then
endpoints 1 to 14 — which is the ordering the rest of this file already records
and `endpointConfig` is already indexed by.

**THE CONSEQUENCE, and it is why this measurement was owed.** Endpoint 2 is the
firmware's TRANSMIT endpoint. **A patch delivered to endpoint 2 has nowhere to
land**; a host must deliver it to **endpoint 3**. This model already refuses the
wrong one — `deliver` rejects an endpoint whose `EPDIR` says IN — so the
correction landed in the consuming emulator, which had carried the opposite
assumption.

**WHAT IS MEASURED, WHAT THIS MODEL ASSERTS, AND WHAT IS ONLY DECODED. Keeping
those three apart is what this file is for.**

| | Standing |
|---|---|
| The three bytes above | **MEASURED** from firmware behaviour. |
| `EPDIR` is bit 6 | **ASSERTED BY THIS MODEL.** `epdirBit = 0x40` in `src/isp1181/isp1181.nim`. `tests/t_isp1181.nim` drives both outcomes on one handle and `tests/t_isp1181_command_set.nim` reaches the same decode from the command side, and **moving `epdirBit` to any of the other seven bits turns the suite red** — measured by moving it to each of them in turn, not argued. **WHAT THAT PINS IS THE BIT POSITION THIS MODEL READS, AND NOTHING ELSE.** No test in this repository loads a firmware image; every configuration byte a test writes is the test's own. A part that carried the direction somewhere else would be modelled wrongly and the suite would stay green. That is weaker than pinning the firmware and stronger than the row below, where nothing constrains the value at all. |
| `DBLBUF` is bit 5; `FFOSZ` `0001` is 16 bytes and `0011` is 64 bytes | **DECODED ONLY.** Nothing in this model reads either field out of `endpointConfig` — `fifoShape` is a constant — so no test can go red on them. Read from ISP1362 Rev. 06 Table 110/111 (p.107) and Table 16 (p.52), and INHERITED in exactly the sense every other ISP1362 value here is. `FFOISO` is 0 in all three bytes, so Table 16's non-isochronous column is the one that applies. **TWO ISP1362 DOCUMENTS AGREE ON BOTH**, which is stated below; two agreeing ISP1362 documents are still not an ISP1181B document. |

**`fifoShape` AGREES WITH ALL THREE BYTES, AND THE AGREEMENT IS CONSISTENT
RATHER THAN PINNED.**

| Endpoint | Byte | `DBLBUF` | `FFOSZ` | Decodes to | `fifoShape` row |
|---|---|---|---|---|---|
| 1 | `0xE1` | 1 | `0001` | 16 bytes, double | `(16, 2)` |
| 2 | `0xE3` | 1 | `0011` | 64 bytes, double | `(64, 2)` |
| 3 | `0x83` | 0 | `0011` | 64 bytes, single | `(64, 1)` |

So the receive endpoint genuinely does hold ONE 64-byte buffer, and that row was
right for a reason nobody had checked. **The agreement is an observation made
once, by hand, in this file.** Nothing reads a configuration byte back into
`fifoShape`, so an image that configured different sizes would leave the table
untouched and nothing would report it. That is the same gap the section above
already names, and it is carried below as `Unverified` rather than closed here.

**A SECOND ISP1362 DOCUMENT GIVES THE SAME FIELDS, AND THE FIRMWARE FOLLOWS ITS
RECIPE FOR IN AND DEPARTS FROM IT FOR OUT.** `AN10008-01`, Table 12-5 and Figure
12-15 (pp.77-78), recommends a bulk endpoint as bit 7 enable, bit 6 `0` for OUT
and `1` for IN, **bit 5 double buffering — set for BOTH directions**, bit 4 `0`
for bulk, and `FFOSZ` `0011` for 64 bytes; Figure 12-15 gives the same values as
C constants, `EPCNFG_FIFO_EN 0x80`, `EPCNFG_IN_EN 0x40`, `EPCNFG_DBLBUF_EN 0x20`
and `EPCNFG_NONISOSZ_64 0x03`, and passes `EPCNFG_DBLBUF_EN` in the bulk OUT call
exactly as it does in the bulk IN one. So the two recommended bytes are
`0x80|0x20|0x03` = **`0xA3` for bulk OUT** and `0x80|0x40|0x20|0x03` = **`0xE3`
for bulk IN**.

| Endpoint | Recommended for its direction | Byte the firmware writes | Agreement |
|---|---|---|---|
| 2 — IN | `0xE3` | `0xE3` | Every bit. |
| 1 — IN | `0xE3` | `0xE1` | Every bit except `FFOSZ`, which is `0001` for 16 bytes rather than `0011` for 64. Bit 5 agrees. |
| 3 — OUT | `0xA3` | `0x83` | Every bit **except bit 5**. The firmware clears `DBLBUF` where the note sets it. |

**THE DISAGREEMENT IS THE USEFUL PART, AND IT IS A SECOND ROUTE TO THE `(64, 1)`
ROW.** `fifoShape` already says endpoint 3 holds ONE 64-byte buffer, and until now
that row rested on the decode of `0x83` alone. The note supplies an independent
expectation to weigh it against: double buffering is what a bulk OUT endpoint is
recommended to get, and this firmware does not take it. The two accounts of
endpoint 3 were reached by different routes and agree.

**WHAT IS MEASURED IS THAT BIT 5 IS 0 IN THE BYTE THE FIRMWARE WRITES.** That the
clearing was a DELIBERATE choice is INFERRED, from the fact that the byte matches
a published recipe in every other bit and differs in this one. Nothing in this
repository establishes what the firmware's author intended, and a reader who
wants the weaker reading — that the bit was simply never set — is not contradicted
by any evidence here.

**That raises the standing of the decode and does NOT move the inheritance.**
Both documents are about the ISP1362; the ISP1181B data sheet is still the one
owed, and the `Unverified` row below is unchanged.

**A tension the same page raised, now settled by a run.** §15.1.1 states that
buffer memory allocation "takes place only after all 16 endpoints have been
configured in sequence", that control endpoints "must be included in the
initialization sequence", and that allocation "starts when endpoint 14 has been
configured". An earlier recorder observed **three** writes, and this file
recorded that it could not tell whether the firmware made more or whether the
part imposed no such sequence.

**It makes more.** With the model refusing `0x25` to `0x2F` and writing a line
per refusal, a boot of the Clavia firmware in the consuming emulator produced
one line for each of `0x25`, `0x26`, `0x27`, `0x28`, `0x29`, `0x2A`, `0x2B`,
`0x2C`, `0x2D`, `0x2E` and `0x2F`, in that order, each followed by exactly one
operand byte. That is **eleven** writes covering endpoints 4 to 14, and the
first of them arrived while `0x24` was still the pending command, so `0x24` was
written too. The firmware follows §15.1.1's sequence; the earlier recorder saw
part of it.

**What the same run says about the eleven slots' contents.** With all sixteen
slots accepted, the model writes a line for a slot at or above `fifoCount` whose
operand sets FIFOEN, and the boot produced **no such line**. Every one of slots
5 to 15 is therefore configured with FIFOEN clear: the firmware includes them in
the sequence the document requires and enables none of them. That is consistent
with the interrupt enable `0x00001F07`, which arms five endpoint bits, and it is
an observation about THIS image and not a property of the part.

**Slots 0 to 3 are not covered by this run.** They are accepted silently, so the
log says nothing about whether they were written or with what.

## The unnamed authority

`src/isp1181/commands.nim` and `src/isp1181/isp1181.nim` cite "the authority"
for the ISP1181 command set, the register widths, the endpoint buffer sizes
and the interrupt-enable value. **No header names that document, and this
register cannot name it either.**

The same headers record what is known to be absent: the ISP1181 datasheet
itself, an ISP1362 driver header, and any open-source ISP1181 emulation. The
gaps those absences produce are carried in the code as unnumbered commands and
as unassigned interrupt-register bits, rather than as a guess. The bits that
ARE assigned are the five the firmware and the inherited table agree on, and
the section above states what that agreement is worth.

This is a real gap in the citation chain, not a formatting problem. A reader
cannot check a single ISP1181 fact in this repository against anything.

**What the gap used to block, and no longer does.** `buffer write` and
`validate` were two of the six commands the unnamed authority named without
numbering, and they are the firmware's only route into an endpoint's IN buffer.
`src/isp1181/isp1181.nim` carried the device-to-host path with nothing reaching
it. Those six are now numbered from ISP1362 Rev. 06 as recorded above, and the
firmware reaches `queueIn` through `0x01` then `0x61`. **The connection is only
as good as the inheritance**, which is the open item at the top of this
section. The other end is `isp1181_in_token`, the published entry point through
which a host collects a validated packet; nothing about it is inherited, since
an IN token is a property of USB and not of this part's command map.

**What the same pages settle about endpoint direction.** `queueIn` and
`transmit` once refused endpoints 1 to 3 because no source stated whether a
single endpoint buffer carries one direction or both. ISP1362 Rev. 06 pp.51-53
answer that: the `EPDIR` bit of DcEndpointConfiguration selects the direction,
and the document states it as IN meaning input for the USB host, so a buffer
carries exactly one direction. **The bit's POSITION is now read and no longer
missing.** ISP1362 Rev. 06, Table 110, "DcEndpointConfiguration register: bit
allocation", gives the byte that `0x20+n` writes as:

| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|
| Symbol | FIFOEN | EPDIR | DBLBUF | FFOISO | `FFOSZ[3:0]` | | | |
| Reset | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Access | R/W | R/W | R/W | R/W | R/W | R/W | R/W | R/W |

Table 111 gives bit 6 as: "EPDIR   This bit defines the endpoint direction
(0 = OUT, 1 = IN); it also determines the DMA transfer direction (0 = read,
1 = write)." `src/isp1181/isp1181.nim` decodes bit 6 out of `endpointConfig`,
and an endpoint the firmware configured IN may now be queued and transmitted.

**THE POSITION IS INHERITED AND THE LIMIT IS UNCHANGED.** ISP1362 Rev. 06
states on p.1 that it integrates the ISP1181B peripheral controller, and p.51
weakens even that to "similar to the ISP1181B in 16-bit bus mode". **The
ISP1181B data sheet itself was never retrieved.** Table 110 is therefore an
INHERITED bit map, exactly as Table 109's opcodes are, and this citation does
not raise the confidence of anything in this section. A firmware image that
disagrees with bit 6 is evidence against the inheritance, not a bug in the
firmware. **What would settle it:** the DcEndpointConfiguration bit map in an
ISP1181B or ISP1181 data sheet.

**What Table 110's own section settles, and which this model now follows
throughout.** Section 15.1.1 states the write codes as "20 to 2F - write
(control OUT, control IN, endpoints 1 to 14)", and states that the sixteen
configurations are programmed "in sequence (from endpoint 0 OUT to endpoint
14)". So slot `0x20+k` is endpoint 0 OUT for k = 0, endpoint 0 IN for k = 1,
and endpoint k - 1 for k >= 2 - the same ordering the stall, status,
buffer-read and buffer-clear families already use, whose endpoint 1 form is
base + 2.

The endpoint-configuration family was the one family that instead read `0x20+k`
as endpoint k. It is now numbered by the same procedure as every other family
in `src/isp1181/commands.nim`, so the ordering cannot drift for one family
alone; `0x24` is endpoint 3's slot, and `0x2F` is endpoint 14's. Three things
followed from the reconciliation, and each is an operator decision rather than
a repair:

- **`0x24` joined the implemented class.** This model carries a buffer for
  endpoint 3, so its configuration slot is one the model can honour, and
  endpoint 3 may now be configured IN. `queueIn` and `transmit` no longer have
  an endpoint whose EPDIR bit they cannot read, and the direction enum lost the
  case that reported one.
- **`0x2F` left `ccUnspecified`.** It leaves that class by being NUMBERED by
  section 15.1.1 and not by any reclassification. The opcode partition the
  command-set suite pins moved with it, and the suite records the reason beside
  the pinned figure.
- **The peek selector reads its operand as a SLOT.** `0x20+k` selects buffer k
  directly, because section 15.1.1's slot ordering is the order the model's own
  buffers are in. The older reading passed `k` through an endpoint-to-buffer
  table, so `0x21` - endpoint 0's IN buffer - selected endpoint 1's buffer
  instead, and every slot from 1 upward named a neighbour.

**All sixteen slots are now accepted, and the ground is the same section.**
§15.1.1 makes buffer-memory allocation conditional on "all 16 endpoints" being
configured in sequence, so a model that refused one of the sixteen would report
a step the document REQUIRES of the firmware as a step the part cannot take.
The DcEndpointConfiguration register is accepted and recorded for every slot;
`fifoCount` is unchanged, and the data-flow families still refuse an endpoint
this model carries no buffer for, by name. The remaining gap is narrower and is
reported where it occurs: a slot at or above `fifoCount` whose operand sets
FIFOEN — Table 110/111 p.107, bit 7 — is buffer memory the firmware asked for
and this model does not have, and it writes one line saying so.

**The IN half of endpoints 1 to 3 is implemented, and the DIRECTION is a
run-time precondition rather than a class.** Write endpoint n buffer (`02` to
`0F`) and Validate endpoint n buffer (`62` to `6F`) were `ccNotImplemented` for
endpoints 1 to 3 while the class was made to carry the direction: a single
buffer faces the way EPDIR points it, EPDIR is a bit the firmware rewrites at
run time, and a classification that moved with it would answer differently at
two instants. Three readings settle where the direction belongs, and all three
are INHERITED on the terms this file states throughout:

| Where | What it says |
|---|---|
| Table 109, pp.105-106 | The codes are numbered for endpoints 1 to 14 with no configuration attached to the CODE. The direction appears in the DESTINATION column as an annotation - "buffer memory endpoint 1 to 14 (IN endpoints only)" - and not as a separate or withheld opcode. |
| §15.2.1 Remark, p.114 | *"There is no protection against writing or reading past a buffer's boundary, against writing into an OUT buffer or reading from an IN buffer. Any of these actions can cause an incorrect operation."* |
| Table 109 notes [4] and [5], p.106 | *"Validating an OUT endpoint buffer causes unpredictable behavior of the peripheral controller."* and *"Clearing an IN endpoint buffer causes unpredictable behavior of the peripheral controller."* |

So the part does NOT refuse a wrong-direction access; it performs it and
corrupts. **That is an outcome this model may not imitate**, because carrying it
out would mean inventing one of the results the document declines to name, and
doing nothing silently would report the firmware's mistake as a success. The
model therefore refuses at the command, and the line names the endpoint, the
direction the command needs and the direction the register holds. The same
guard runs on the OUT half - Read and Clear endpoint n buffer - because the two
notes above are symmetric; the control endpoints pass it always, since §15.1.1
p.107 gives them fixed configurations.

**`ccIllegal` is unchanged and still means a byte the authority
parenthesises** - `00`, `11`, `60`, `71`. Those are forbidden by the CODE
whatever any register says. None of `02` to `0F` or `62` to `6F` is
parenthesised, which is the distinction that keeps the two findings apart.

**What this does NOT settle: the zero-length IN packet.** The emulated
firmware's `0x03` carries a two-byte length prefix of `00 00` and no payload,
so the packet it validates on endpoint 2 is ZERO BYTES long, and `queueIn`
still refuses it by name. ISP1362 Rev. 06 §15.1.2 p.107 does contemplate the
firmware "sending an empty packet to the host" after a Write Device Address
command, which is evidence that an empty IN packet is a thing the part
transmits; it is NOT a statement of what the endpoint buffer holds for one, nor
of what `isp1181_in_token`'s callback should receive for a packet with no first
byte. **That decision is open** and is recorded here rather than taken. Until it
is taken, `transmit` refuses a zero-length packet by name instead of taking the
address of an element that is not there.

**A refused command abandons the transfer in progress, and that is READ.**
Rev. 06 p.14 describes the command as "the index of a register" whose purpose is
"to inform the ISP1362 about the register that will be accessed at the data
phase", and §15 p.104 gives the command phase as an unconditional interpretation
of the lower byte of the bus as a command code. Neither sentence admits a path
by which an earlier command survives a later command-port write. This was
previously recorded in `src/isp1181/isp1181.nim` as a SEQUENCING CHOICE the
authority did not settle, with the opposite behaviour; the two sentences settle
it, and the module head now cites them instead. **This is inherited on the same
terms as every other ISP1362 value here** — the ISP1181B data sheet is still the
document owed.

**The direction decode always followed the DOCUMENT's ordering**, because a
decode on the other ordering would read a neighbouring endpoint's byte and the
firmware could not detect it. The rest of the model has now been brought onto
it.

**EPDIR refuses in both directions.** A single endpoint buffer faces one way,
so a host packet arriving at an endpoint the firmware configured IN has nowhere
to land, and `deliver` refuses it by name for the same reason `queueIn` refuses
an endpoint configured OUT.

**The set-up interlock is implemented, and the route it was missing is now
published.** ISP1362 Rev. 06 §12.3.6, p.53, states that a set-up packet flushes
the IN buffer and disables Validate and Clear on both control endpoints until
the firmware sends Acknowledge set up (`0xF4`) to both, and §15.2.7, p.117,
gives `0xF4` the matching effect. This model once did not implement any of it,
and the reason recorded here was a **missing route** rather than a decision to
skip: `isp1181_rx` delivers an endpoint and bytes and carries no set-up flag,
so the latch had nothing to set it. **The operator took the API decision**:
`isp1181_setup` is a new published symbol — the twenty-fifth — and it is a
SEPARATE entry point rather than a flag on `isp1181_rx` or a sentinel endpoint
value, so no existing caller's signature moved and no computed endpoint can
reach the set-up path by accident.

**SETUPT is bit 2, and that position is READ.** ISP1362 Rev. 06, Table 126,
"DcEndpointStatus register: bit allocation", p.114, gives bits 7 down to 1 as
EPSTAL, EPFULL1, EPFULL0, DATA_PID, OVERWRITE, SETUPT, CPUBUF with bit 0
reserved, and Table 127, p.115, gives bit 2 as *"SETUPT   Logic 1 indicates
that the buffer contains a set-up packet."* It is INHERITED in the same sense
every Table-109 opcode is — ISP1362 states that it integrates the ISP1181B and
the ISP1181B document was never retrieved — but it is a reading of the
DOCUMENT and **not** a reading of firmware behaviour. A note elsewhere in this
project's records attributes the position to the emulated firmware's control-OUT
handler; that attribution is wrong, and the table above is where the bit comes
from.

**A SECOND DOCUMENT STATES IT TOO.** `AN10008-01`, p.73, describes the control
OUT handler and names *"SETUPT bit (bit 2) of the DcEndpointStatus register"*.
The same page's pseudo-code tests `EP_Status & 0x20` as *"whether the primary
buffer is full"*, which puts `EPFULL0` at bit 5 — the position `statusByte`
already composes. Two documents state bit 2, and both are ISP1362 documents, so
**the position is DOCUMENTED rather than inferred and remains INHERITED.**

**What the document does NOT settle is when SETUPT CLEARS, and the model's rule
is an INFERENCE FROM TABLE 127's OWN WORDING.** Table 127 gives no clearing
rule for bit 2. In the same table bit 3 OVERWRITE is spelled out — *"a read
back of this register clears this bit"* — so the authority demonstrably knows
how to write a read-to-clear bit and did not write one for bit 2. Bit 2's text
is a statement about buffer CONTENT, so the model takes the bit away when the
buffer stops holding the packet: at the Clear Buffer command, which §12.3.6 has
just re-enabled by way of `0xF4`. The resulting sequence is the one §12.3.6
describes — set-up arrives, the packet *"stays in the buffer"*, the firmware
acknowledges, the firmware clears. **The clearing rule is therefore
DATASHEET-DERIVED BY INFERENCE and is not a sentence in the document.** No
firmware trace on this machine was consulted for it, and none is needed for the
sequence to close. **What would settle it:** the `DcEndpointStatus` description
in an ISP1181B or ISP1181 data sheet, which is the same document owed for the
clearing route above.

**OVERWRITE (bit 3) is the one part of §12.3.6 this model still does not
carry.** The authority gives bit 3 to a set-up packet that landed on an
unacknowledged one. The model tracks no such bit, so `isp1181_setup` REFUSES a
set-up packet arriving at a full control OUT buffer, by name and with a log
line, rather than overwriting silently. An overwrite with no bit to report it
is the plausible wrong outcome the model refuses everywhere else.


**`isp1181_tx_fn` carries no contract of its own in `include/mcf5307.h`.** Its
sibling `isp1181_irq_fn` has a paragraph; the transmit callback has none, so
what a zero-length transmit would mean to a host is unstated. `queueIn` refuses
an empty packet for that reason rather than choosing a meaning. What the header
does now state, at `isp1181_in_token`, is when the callback is reached and how
long its pointer lives - facts about the model's own entry point rather than
about the callback's meaning to a host.

## The rule for a new citation

1. Cite the document by title and revision in the header. No path, no URL to
   a personal store.
2. Add a row here if the document is not already listed.
3. If the document has no name, that is a finding. Record it as one instead
   of writing "the authority".

## Instruments

An instrument is not a document, and a header that cites one is recording a
measurement rather than an authority. `m68k-elf-as` and `m68k-elf-objdump`
are cited in the core headers as the thing that confirms which operand sizes
ISA_A accepts. Their pin is in `docs/toolchain.md`.

## Unverified

| Claim | What would settle it |
|---|---|
| The table above is complete — every external document any header cites has a row | A registered check that extracts document-shaped citations from `src/` and `include/` and asserts each one has a row here |
| The `MCF5307UM/AD` hash above identifies the copy every manual-derived value in this tree was taken from | Re-read one value per citing module against a PDF with that hash |
| The CFPRM revision every header means is 3 | Two headers name Rev. 3 and the rest name the manual alone; re-read one value per citing module against Rev. 3 |
| A read of `0x50+n` is the route by which the emulated firmware clears an endpoint interrupt, so its service routine terminates | Run the firmware against this model in the consuming emulator and observe whether the per-endpoint handler issues `0x50` to `0x54`. A handler that does not would spin, and the route would have to move |
| The interrupt-register bit layout the emulated firmware obeys is the one ISP1362 Rev. 06 Table 143 (p.121) gives | Read the interrupt-register table in the ISP1181B data sheet. The two sources already disagree on bits 1 and 2, which are unassigned for that reason. `AN10008-01` §11.6.2 p.63 also puts suspend at bit 2, which is a second ISP1362 document and not a second part |
| Every row of `fifoShape` is the size and buffering scheme the emulated firmware configures. All three of endpoints 1 to 3 AGREE with the configuration bytes recorded above, but the agreement is CONSISTENT and not PINNED: nothing reads `endpointConfig` back into `fifoShape`, so a firmware image configuring different sizes would leave the table standing and report nothing | Derive `fifoShape` from the configuration writes, or add a registered check that decodes each observed byte and asserts it against the corresponding row, so a disagreeing image turns the suite red. Endpoints 0 OUT and 0 IN are not covered by the three bytes at all and would need their own observation |
| `DBLBUF` is bit 5, and `FFOSZ` `0001` and `0011` select 16 and 64 bytes for a non-isochronous endpoint | Read from ISP1362 Rev. 06 Table 110/111 (p.107) and Table 16 (p.52), and INHERITED exactly as every other ISP1362 value here is. Unlike `EPDIR` at bit 6, neither field is read by this model, so no test constrains it. Read the DcEndpointConfiguration bit map and the buffer-memory size table in an ISP1181B or ISP1181 data sheet |
| The buffer-memory sizes and buffering schemes the firmware writes into slots 0 to 3 | The boot run named above resolves slots 4 to 15 and says nothing about the first four, which the model accepts silently. Record the operand byte of each accepted `0x20` to `0x23` and decode it against Table 110/111 |
| SETUPT is taken away by the Clear Buffer command that empties the control OUT buffer. INFERRED from Table 127's wording — bit 2 describes buffer content and, unlike bit 3, carries no read-to-clear sentence | Read the `DcEndpointStatus` description in an ISP1181B or ISP1181 data sheet. Failing that, run the emulated firmware against this model and observe whether its control handler re-reads `0x50` after `0x70` and finds bit 2 low. `AN10008-01` p.73 says `0x50` clears the INTERRUPT bit and is silent on bit 2, which is corroboration of the inference and not proof of it |

## Related

- `docs/toolchain.md` — the cross-assembler pin.
- `docs/nim-version.md` — the compiler pin.
- `docs/avoiding-cycles.md` — the layering rule the module headers obey.
- `AGENTS.md` — the clean-room rule that decides what may be taken from a
  source at all.
