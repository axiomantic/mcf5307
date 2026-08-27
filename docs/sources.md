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
| "Table 109 of the ISP1362 data sheet, Rev. 06" (`src/isp1181/commands.nim`, `src/isp1181/isp1181.nim`, `tests/t_isp1181_command_set.nim`) | ST-NXP Wireless, *ISP1362 — Single-chip USB On-The-Go controller*, Product data sheet, doc id `ISP1362_6`, Rev. 06, 21 January 2009. 149 pages. | **Not in this repository.** Obtain the PDF by its designation and revision. **It is not a document about the part this model names — see "The inherited command map" below before using a value from it.** |

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
gaps those absences produce are carried in the code as unnumbered commands
and as an unassigned interrupt-register bit, rather than as a guess.

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

**What the same pages settle about endpoint direction, and what they do not.**
`queueIn` and `transmit` once refused endpoints 1 to 3 because no source stated
whether a single endpoint buffer carries one direction or both. ISP1362 Rev. 06
pp.51-53 answer that: the `EPDIR` bit of DcEndpointConfiguration selects the
direction, and the document states it as IN meaning input for the USB host, so
a buffer carries exactly one direction. **The refusal stands and its reason has
moved.** Acting on `EPDIR` needs the bit's POSITION inside the byte that
`0x20+n` writes, and no document on this machine gives it; `endpointConfig`
holds that byte undecoded. A bit index chosen here would make the model obey a
firmware configuration write in a way the firmware could not detect as wrong,
which is the class of invention this model refuses everywhere else. **What
would settle it:** read the DcEndpointConfiguration bit map in the ISP1181B
data sheet, or in ISP1362 Rev. 06 Table 110, and decode `endpointConfig` in
`src/isp1181/isp1181.nim`.

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

## Related

- `docs/toolchain.md` — the cross-assembler pin.
- `docs/nim-version.md` — the compiler pin.
- `docs/avoiding-cycles.md` — the layering rule the module headers obey.
- `AGENTS.md` — the clean-room rule that decides what may be taken from a
  source at all.
