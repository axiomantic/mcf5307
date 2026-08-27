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
| "the authority" (`src/isp1181/`) | **UNNAMED.** See below. | Unknown. |

**ColdFire condition codes differ from the 68000.** The CFPRM is the
authority for them, and a 68000 reference is not. `AGENTS.md` states the same
rule beside the clean-room rule, which is where an implementer meets it
first.

**A machine conversion of a scanned manual is not the manual.** A markdown or
OCR derivative may be used to FIND a page. The value goes into code only
after the page it names is read in the original. A scanned source carries
table errors that look completely normal on the page.

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
