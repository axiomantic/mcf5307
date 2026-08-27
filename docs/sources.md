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
| "Table 109 of the ISP1362 data sheet, Rev. 06", "ISP1362 Rev. 06 Table 143", "ISP1362 Rev. 06 p.53" (`src/isp1181/commands.nim`, `src/isp1181/isp1181.nim`, `tests/t_isp1181.nim`, `tests/t_isp1181_command_set.nim`) | ST-NXP Wireless, *ISP1362 — Single-chip USB On-The-Go controller*, Product data sheet, doc id `ISP1362_6`, Rev. 06, 21 January 2009. 149 pages. | **Not in this repository.** Obtain the PDF by its designation and revision. **It is not a document about the part this model names — see "The inherited command map" below before using a value from it.** |

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
| ISP1362 Rev. 06, Tables 142 and 143 | Bit 0 `RESET`, 1 `RESUME`, 2 `SUSPND`, 3 `EOT`, 4 `SOF`, 5 `PSOF`, 6 `SP_EOT`, 7 `BUSTATUS`, 8 `EP0OUT`, 9 `EP0IN`, 10 to 23 `EP1` to `EP14`. | **INHERITED, exactly as the command map is.** The ISP1181B data sheet was not retrieved, and the integration claim recorded above is not a claim of a byte-identical register map. |

The agreement covers bit 0, bits 8 and 9 as the two control-endpoint
directions, and bits 10 and upwards as one bit per endpoint in order. The
firmware's enable arms bits 8 to 12 and this model carries exactly five
buffers, which is the same five.

**WHERE THE TWO SOURCES DISAGREE, NOTHING IS ASSIGNED.** The firmware
dispatches bit 1 to suspend and bit 2 to resume; the inherited table calls bit
1 `RESUME` and bit 2 `SUSPND`. The two are swapped, and this repository has no
document that settles which is right.

**What is deliberately NOT assigned, and why:**

| Bits | Why not |
|---|---|
| 0, 1, 2 — bus reset, suspend, resume | The sources disagree on 1 and 2, **and** this model's API carries no bus event at all: `isp1181_rx` delivers an endpoint and bytes. A bit nothing can set is a latch that never fires, which is the same case as the set-up interlock below. |
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
Rev. 06 pp.51-53 and its Table 110, both are firmware-programmable**, so
neither is a hardware fact:

| Recorded as | What it actually is |
|---|---|
| endpoint 1 holds 16 bytes | The buffer size is selected by `FFOSZ[3:0]` in the DcEndpointConfiguration register. `0001` selects 16 bytes for a non-isochronous endpoint. 16 bytes is a **configuration**, not a size the part has. |
| endpoint 3 is single-buffered | Buffering is selected per endpoint by the `DBLBUF` bit of the same register. Single-buffered is a **configuration**. |

**The observation is kept and only its label moves.** The values almost
certainly came from reading the emulated firmware's own configuration writes,
which makes them a measurement of THIS firmware and good evidence for what
`fifoShape` should hold. They are simply not statements about the silicon, and
the difference matters the day a different firmware image is run.

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

**The direction decode always followed the DOCUMENT's ordering**, because a
decode on the other ordering would read a neighbouring endpoint's byte and the
firmware could not detect it. The rest of the model has now been brought onto
it.

**EPDIR refuses in both directions.** A single endpoint buffer faces one way,
so a host packet arriving at an endpoint the firmware configured IN has nowhere
to land, and `deliver` refuses it by name for the same reason `queueIn` refuses
an endpoint configured OUT.

**What is still open in the set-up interlock.** ISP1362 p.53 states that a
set-up packet flushes the IN buffer and disables Validate and Clear on both
control endpoints until the firmware sends Acknowledge set up (`0xF4`) to both.
**This model does not implement that**, and the reason is a missing route
rather than a decision to skip it: `isp1181_rx` delivers an endpoint and bytes
and carries no set-up flag, so the latch would have nothing to set it. Adding a
set-up delivery route is a change to the published C API and is an operator
decision, not a repair.


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
| The interrupt-register bit layout the emulated firmware obeys is the one ISP1362 Rev. 06 Table 143 gives | Read the interrupt-register table in the ISP1181B data sheet. The two sources already disagree on bits 1 and 2, which are unassigned for that reason |

## Related

- `docs/toolchain.md` — the cross-assembler pin.
- `docs/nim-version.md` — the compiler pin.
- `docs/avoiding-cycles.md` — the layering rule the module headers obey.
- `AGENTS.md` — the clean-room rule that decides what may be taken from a
  source at all.
