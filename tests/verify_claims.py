"""Check every t_claims-registered sentence still exists in its source file.

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
    """Return (name, path, sentence) for every claim the registry pins."""
    src = subprocess.run(['git', 'show', f'{ref}:tests/t_claims.cmake'],
                         capture_output=True, text=True).stdout
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


def check(ref):
    claims = registry('HEAD' if ref == 'WORKTREE' else ref)
    if not claims:
        # An empty registry is a parse failure, not a clean result: the
        # file exists and pins sentences, so reading none means the reader
        # is broken and every "missing: 0" below it would be vacuous.
        print(f'{ref}: NO CLAIMS PARSED -- the reader is broken, not the tree')
        return 1, 0
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
    total_missing = 0
    for ref in refs:
        missing, count = check(ref)
        print(f'{ref}: {count} claims checked, {missing} missing')
        total_missing += missing
    return 1 if total_missing else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:] or ['WORKTREE']))
