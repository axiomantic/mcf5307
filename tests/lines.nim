## `lines` - the line-A and line-F opcode spaces.
##
## This module classifies and decides nothing: every procedure here is a
## function of one instruction word, so it can be asserted value by value
## without a machine to run. What the core does with a word these predicates
## accept is the executor's decision.
##
## Why line-A is not decoded. The MCF5307 has a MAC unit in silicon - MCF5307
## User's Manual section 3.9, folio 3-21, closes its instruction-set summary
## with "In addition, nine new MAC instructions have been added", and Table 3-7,
## folio 3-24, carries the MAC, MACL, MSAC and MSACL rows and the moves to and
## from ACC, MACSR and MASK. The core does not model it, and the reason is the
## firmware rather than the part: the measurement is that the shipped operating
## system reaches no MAC instruction, and that claim is scoped to OS v1.62.
## Refusing the whole space is what makes a later firmware version fail loudly
## instead of executing something this core invented.
##
## `MOV3Q` and EMAC fall inside the same refusal and neither is on this part.
## CFPRM Rev. 3 folio 4-46 prints `MOV3Q` with the heading `First appeared in
## ISA_B` over a bit diagram whose top nibble is line-A, and this part is ISA_A.
## The MCF5307 User's Manual names EMAC nowhere at all, so the part has no EMAC
## encoding to decode; the CFPRM carries EMAC because it is a family manual.
##
## Why line-F is refused rather than accepted and discarded. Line-F on this
## part is cache and debug: CFPRM folio 8-2 gives `CPUSHL` a bit diagram whose
## top nibble is line-F, folio 8-18 gives `WDEBUG` another, and MCF5307 User's
## Manual Table 3-7, folio 3-25, carries the `WDDATA` and `WDEBUG` rows. This
## core models neither the cache nor the debug module, and both of those CFPRM
## folios give the operation as "If Supervisor State Then ... Else Privilege
## Violation Exception". A core that accepted and discarded would therefore
## succeed at a supervisor-only instruction executed in user state, and would
## report nothing about the cache or the debug write that did not happen.
## Refusing says which of the two the core is.
##
## The two manuals agree that these spaces have their own vectors, and this
## core takes neither. MCF5307 User's Manual Table 3-1, folio 3-13, and CFPRM
## Table 11-1, folio 11-2, both assign vector 10 to "Unimplemented line-a
## opcode" and vector 11 to "Unimplemented line-f opcode", separately from
## vector 4, "Illegal instruction". This core takes no vector for a refused
## word: it halts and sets its fault bit. No constant here names vector 10 or
## vector 11, because a constant no caller reads is a destination that looks
## like a decision and is not one.
##
## The manuals were read as page images: the MCF5307 User's Manual (1998) and
## the ColdFire Family Programmer's Reference Manual, Rev. 3.

proc opcodeLine(word: uint16): uint16 =
  ## The top nibble, which is what names a line.
  (word shr 12) and 0xF'u16

proc isLineA*(word: uint16): bool =
  opcodeLine(word) == 0xA'u16

proc isLineF*(word: uint16): bool =
  opcodeLine(word) == 0xF'u16
