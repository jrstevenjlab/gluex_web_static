#!/usr/bin/env python3
"""
Copy ONLY the latest version of each DocDB document while preserving layout:
<SRC>/<first4>/<docid6>/<ver3>/...  ->  <DEST>/<first4>/<docid6>/<ver3>/...
Assumes directory names have no spaces; filenames may have spaces.
Skips any files or directories that the user cannot access.
"""

import argparse
import os
import shutil
from pathlib import Path

def is_digits(p: Path, n: int) -> bool:
    """Check if path is a directory with exactly n digits in its name."""
    try:
        return p.is_dir() and len(p.name) == n and p.name.isdigit()
    except PermissionError:
        print(f"[SKIP] Permission denied: {p}")
        return False

def gather_dirs(src: Path, digits: int):
    """Yield subdirectories matching the digit length pattern."""
    try:
        for child in src.iterdir():
            if is_digits(child, digits):
                yield child
    except PermissionError:
        print(f"[SKIP] Cannot list directory: {src}")

def parse_exts(exts_str: str):
    """Parse comma-separated extensions into a lowercase set."""
    exts = []
    for e in (exts_str or "").split(","):
        e = e.strip().lower()
        if e:
            exts.append(e)
    return set(exts)

def should_copy_file(path: Path, exts: set) -> bool:
    """Return True if file should be copied (matches allowed extensions)."""
    if not exts:
        return True
    ext = path.suffix.lower().lstrip(".")
    return ext in exts

def safe_walk(top: Path):
    """
    A permission-safe os.walk generator that skips unreadable dirs.
    Yields (root, dirs, files) like os.walk.
    """
    for root, dirs, files in os.walk(top, topdown=True, onerror=None):
        # remove directories we can't access
        accessible_dirs = []
        for d in list(dirs):
            subdir = Path(root) / d
            if os.access(subdir, os.R_OK | os.X_OK):
                accessible_dirs.append(d)
            else:
                print(f"[SKIP] No access to directory: {subdir}")
        dirs[:] = accessible_dirs
        yield root, dirs, files

def main():
    ap = argparse.ArgumentParser(description="DocDB latest-only export (permission-safe)")
    ap.add_argument("src", nargs="?", default="/group/halld/www/halldweb/html/DocDB", help="DocDB source root")
    ap.add_argument("dest", nargs="?", default="site/halldweb.jlab.org/DocDB-latest", help="Destination root")
    ap.add_argument("--exts", default="pdf,png,gif,ppt,pptx,xls,xlsx,key", help="Comma-separated extensions to include (default: pdf). Empty = all")
    ap.add_argument("--dry-run", action="store_true", help="Preview actions without copying")
    args = ap.parse_args()

    src = Path(args.src).resolve()
    dest = Path(args.dest).resolve()
    exts = parse_exts(args.exts)

    dest.mkdir(parents=True, exist_ok=True)
    print(f">>> DocDB latest-only export (permission-safe)")
    print(f"    Source: {src}")
    print(f"    Dest:   {dest}")
    print(f"    Exts:   {', '.join(sorted(exts)) if exts else '(all)'}")
    print(f"    DryRun: {args.dry_run}")

    # iterate <first4> dirs
    for first4 in gather_dirs(src, 4):
        # iterate <docid6> dirs
        for docid_dir in gather_dirs(first4, 6):
            # collect <ver3> dirs
            try:
                vers = [v for v in docid_dir.iterdir() if is_digits(v, 3)]
            except PermissionError:
                print(f"[SKIP] Cannot list versions for: {docid_dir}")
                continue
            if not vers:
                continue

            # pick highest numeric version (handles zero-padded)
            latest = sorted(vers, key=lambda p: int(p.name))[-1]
            out_ver_dir = dest / first4.name / docid_dir.name / latest.name

            if args.dry_run:
                print(f"[DRYRUN] Would create: {out_ver_dir}")
            else:
                out_ver_dir.mkdir(parents=True, exist_ok=True)

            # walk files under latest version
            for root, _, files in safe_walk(latest):
                root_path = Path(root)
                for fname in files:
                    src_file = root_path / fname
                    if not should_copy_file(src_file, exts):
                        continue
                    # skip unreadable files
                    if not os.access(src_file, os.R_OK):
                        print(f"[SKIP] No permission to read file: {src_file}")
                        continue

                    rel = src_file.relative_to(latest)   # relative path under <ver3>/
                    dest_file = out_ver_dir / rel

                    if args.dry_run:
                        print(f"[DRYRUN] {src_file} -> {dest_file}")
                    else:
                        dest_file.parent.mkdir(parents=True, exist_ok=True)
                        try:
                            shutil.copy2(src_file, dest_file)
                        except PermissionError:
                            print(f"[SKIP] Cannot copy (permission denied): {src_file}")
                        except OSError as e:
                            print(f"[SKIP] Failed to copy {src_file}: {e}")

    # write landing page
    if not args.dry_run:
        try:
            (dest / "index.html").write_text(
                """<!doctype html><meta charset="utf-8"><title>DocDB — Latest Only</title>
<style>body{font-family:system-ui;margin:2rem}code{background:#f5f5f7;padding:.1rem .3rem;border-radius:.25rem}</style>
<h1>DocDB — Latest Versions (Preserved Directory Layout)</h1>
<p>Only the highest version per document is included, keeping <code>0054/005416/003/</code> paths so existing links work.</p>
""",
                encoding="utf-8"
            )
        except Exception as e:
            print(f"[SKIP] Cannot write index.html: {e}")

    print(f">>> Done → {dest}")

if __name__ == "__main__":
    main()

