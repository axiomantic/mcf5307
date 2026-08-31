"""Check every pinned source line still exists, for every mechanism that pins one.

TWO mechanisms in this repository read source text and fail when it moves,
and they have different shapes:

  * ``tests/t_claims.cmake`` registers comment SENTENCES by file.
  * ``tests/reach.sh``'s selftest holds a comment line and a code line as its
    known-negative and known-positive CONTROLS -- change either and the
    control stops proving what it exists to prove.

The general rule is not "check the registry" but "grep for any mechanism
that reads this text", so this checks both and is written to be extended.

The comment-stripping equality check used by prose passes CANNOT see this:
it removes the very lines the registry reads, reports IDENTICAL, and the
registry then fails at configure time. Run this after any prose pass that
touches a registered file.

    python3 tests/verify_claims.py [<ref> ...]     # default: WORKTREE

Pass WORKTREE (the default) to check UNCOMMITTED edits -- a pass that checks
only HEAD cannot see the change it is about to commit.

Exit status is non-zero when a registered sentence is missing, so this is
usable as a gate rather than only as a report.
"""
import pathlib
import re, subprocess, sys

_FILE = re.compile(r'set\(CLAIM_(\w+)_CLAIM_FILE\s+"([^"]+)"\)')
_TEXT = re.compile(r'set\(CLAIM_(\w+)_CLAIM_TEXT\s+"([^"]+)"\)')


def registry(ref):
    """Return (name, path, sentence) for every claim the registry pins.

    Returns ``None`` when the registry FILE is absent, which is different
    from parsing to nothing: the registry arrives partway up this stack, so
    a branch below it has no claims to keep rather than a reader that failed.
    """
    proc = subprocess.run(['git', 'show', f'{ref}:tests/t_claims.cmake'],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    src = proc.stdout
    files = dict(_FILE.findall(src))
    texts = dict(_TEXT.findall(src))
    return [(n, files[n], texts[n]) for n in files if n in texts]


def _read(ref, path):
    """The file's content at ``ref``, or from the working tree for WORKTREE."""
    if ref == 'WORKTREE':
        try:
            return pathlib.Path(path).read_text()
        except OSError:
            return ''
    return subprocess.run(['git', 'show', f'{ref}:{path}'],
                          capture_output=True, text=True).stdout


# The assignments sit indented inside a `case` arm, so the anchor allows
# leading whitespace: a pattern requiring column zero matched nothing and
# reported a clean zero, which is the failure this whole file exists to catch.
_REACH = re.compile(r"^\s*(CMT_OLD|POS_OLD)=(?:'([^']*)'|\"([^\"]*)\")", re.M)


def reach_controls(ref):
    """Return (name, path, line) for each control ``reach.sh`` pins.

    ``None`` when the file is absent, matching ``registry``'s contract.
    """
    proc = subprocess.run(['git', 'show', f'{ref}:tests/reach.sh'],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    # Both controls quote from control.nim; the script names it in the same
    # invocation, so the path is read rather than assumed.
    path = 'src/mcf5307/control.nim'
    return [(n, path, sq or dq) for n, sq, dq in _REACH.findall(proc.stdout)]


def check(ref):
    claims = registry('HEAD' if ref == 'WORKTREE' else ref)
    if claims is None:
        print(f'{ref}: no claim registry on this ref -- nothing to check')
        return 0, 0
    if not claims:
        # An empty registry is a parse failure, not a clean result: the
        # file exists and pins sentences, so reading none means the reader
        # is broken and every "missing: 0" below it would be vacuous.
        print(f'{ref}: NO CLAIMS PARSED -- the reader is broken, not the tree')
        return 1, 0
    controls = reach_controls('HEAD' if ref == 'WORKTREE' else ref)
    if controls:
        claims = claims + controls
    missing = 0
    for name, path, text in claims:
        body = _read(ref, path)
        if not body:
            print(f'MISSING FILE {ref}: {path} (claim {name})')
            missing += 1
        elif text not in body:
            print(f'MISSING TEXT {ref}: {path} :: {text[:60]}')
            missing += 1
    return missing, len(claims)


def main(refs):
    # An empty ref list checked nothing, and returning 0 for it would be this
    # file's own subject: a verdict whose population is empty reporting
    # success. The CLI defaults to WORKTREE so this cannot happen from the
    # command line, but a caller passing [] gets a refusal rather than a pass.
    if not refs:
        print('no refs given -- nothing was checked, which is not a pass')
        return 1
    total_missing = 0
    for ref in refs:
        missing, count = check(ref)
        print(f'{ref}: {count} claims checked, {missing} missing')
        total_missing += missing
    return 1 if total_missing else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:] or ['WORKTREE']))
