# Avoiding cycles

The rule that decides where a helper goes when two modules need it.

## The rule

| # | Rule |
|---|---|
| 1 | A module imports only modules BELOW its own level. Never its own level, never above. |
| 2 | The instruction-group executors are one level, and they are SIBLINGS. No executor imports another executor. |
| 3 | The decoder is a sibling of the executors. It imports no executor, and no executor imports it. |
| 4 | A helper that two siblings both need moves DOWN — to the level that holds the shared types, the effective-address table and the machine substrate. It never moves sideways. |
| 5 | `cpu.nim` is the one module that names both the decoder and the executors. Dispatch is its job and nobody else's. |

The levels, by role and not by file list — read the `import` lines for the
edges, because they answer and stay right:

```
    the effective-address helpers, the exception frame     level 0
    the shared types and the legality table                level 1
    the board access, the state record                     level 2
    the machine substrate                                  level 3
    the decoder | the instruction-group executors          level 4
    dispatch and the lifecycle ABI                         level 5
    the library entry point                                level 6
```

## Why the rule is stricter than the compiler

Nim rejects a true import cycle at compile time, and the compile is a
configure step, so a cycle cannot reach a build.

**The cycle is not the shape that gets built.** The shape that gets built is
legal: one executor importing another executor for a helper. That import is
acyclic, it compiles, and it rebuilds the coupling the layering exists to
prevent — one layer further down, where nothing objects.

So the rule forbids more than the compiler does, and rule 4 is the whole of
the difference. A helper that two siblings need is not a fact about either of
them.

## What breaks if you break it

- **Adding an instruction group stops being a local change.** Under the rule
  a new group is one module, one import in `cpu.nim`, and one arm of the
  dispatch there. Once one executor imports another, a new group has to know
  which siblings own which helpers.
- **The helper acquires a caller.** A pure function over the shared types
  works for every executor. The same function reached through a sibling
  carries that sibling's assumptions, and the next caller inherits them.
- **The decoder becomes reachable from an executor.** Once executors import
  each other, the path from an executor back to the decoder is one import
  away, and then the compiler does object — at the point where the design is
  already wrong.

## Why this is a document and not a comment in each module

The rule is one rule. Written into each module header it becomes several
texts, and several texts drift into several meanings; the weakest is the one
an implementer reads. A module header states what THAT module's position
costs it. The rule itself is here.

## What enforces it

| Property | Enforced by | When it fires |
|---|---|---|
| No import cycle | The Nim compiler | Configure time, as a compile error |
| No sibling import among executors, no executor import in the decoder | **Nothing** | Never |

The second row is the honest one. An invariant with no mechanism is a
comment, and this one has no mechanism.

## Unverified

| Claim | What would settle it |
|---|---|
| No executor imports another executor, and the decoder imports none of them | A registered test that reads each module's `import` lines and asserts them against the level table above |
| Level 4 is the only level whose members are mutually independent | The same test, asserting the level of every module rather than the executors alone |

## Related

- `AGENTS.md` — the comment rules, including the one that sends a claim about
  the rest of the tree out of a comment and into a check.
- `tests/t0_no_local_paths.c` — the guard that keeps a citation of this
  document from naming a path that exists on one machine.
