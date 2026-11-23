#!/usr/bin/env python3
"""Apply a PDFium patch series and build a static WebAssembly archive."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def run(*args, cwd, capture=False):
    result = subprocess.run(args, cwd=cwd, check=True, text=True, capture_output=capture)
    return result.stdout.strip() if capture else None


def build_archive(source, series, patches, output, gn, ninja):
    applied = []
    try:
        for patch in patches:
            checkout = source / patch["directory"]
            args = (f"-p{patch['strip']}", "--whitespace=nowarn", str(series / patch["file"]))
            print(f"Applying {patch['file']} in {patch['directory']}", flush=True)
            run("git", "apply", "--check", *args, cwd=checkout)
            run("git", "apply", *args, cwd=checkout)
            applied.append((checkout, args))

        run(gn, "gen", str(output), cwd=source)
        run(ninja, "-C", str(output), "obj/libpdfium.a", cwd=source)
    finally:
        # Reverse in dependency order so the same checkout can be used for a retry
        # or a control build without resetting other files in the checkout.
        for checkout, args in reversed(applied):
            run("git", "apply", "--reverse", *args, cwd=checkout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("series", help="Version directory under patches/")
    parser.add_argument("--source", required=True, type=Path, help="Clean gclient PDFium checkout")
    parser.add_argument("--sysroot", required=True, type=Path, help="WASI SDK 32.0 sysroot")
    parser.add_argument("--gn", default="gn")
    parser.add_argument("--ninja", default="ninja")
    parser.add_argument("--build-only", action="store_true", help="Omit the optional performance patches")
    parser.add_argument("--verify-sha256", help="Require this SHA-256 for the raw archive")
    options = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    series = root / "patches" / options.series
    manifest = json.loads((series / "series.json").read_text())
    source = options.source.resolve(strict=True)
    sysroot = options.sysroot.resolve(strict=True)
    if not (sysroot / "lib/wasm32-wasip1/libc++.a").is_file():
        parser.error("Expected a WASI sysroot with wasm32-wasip1 C++ runtime archives")

    for directory, expected in manifest["revisions"].items():
        checkout = source / directory
        actual = run("git", "rev-parse", "HEAD", cwd=checkout, capture=True)
        if actual != expected:
            parser.error(f"{checkout} is at {actual}, expected {expected}")
        if run("git", "status", "--porcelain", "--untracked-files=no", cwd=checkout, capture=True):
            parser.error(f"{checkout} has modified tracked files")

    patches = manifest["build"] + ([] if options.build_only else manifest["performance"])
    suffix = "-control" if options.build_only else ""
    output = source / "out" / f"pdfium-wasm-{options.series}{suffix}"
    output.mkdir(parents=True, exist_ok=True)
    args_gn = (series / "args.gn").read_text()
    (output / "args.gn").write_text(args_gn + f"rust_wasm_sysroot = {json.dumps(str(sysroot))}\n")
    provenance_path = output / "libpdfium.provenance.json"
    provenance_path.unlink(missing_ok=True)
    build_archive(source, series, patches, output, options.gn, options.ninja)

    archive = output / "obj/libpdfium.a"
    archive_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
    if options.verify_sha256 and archive_hash != options.verify_sha256:
        parser.exit(1, f"{archive} has SHA-256 {archive_hash}, expected {options.verify_sha256}\n")
    provenance = {
        "revisions": manifest["revisions"],
        "series": options.series,
        "wasiSdk": manifest["wasiSdk"],
        "archiveSha256": archive_hash,
        "configurationSha256": hashlib.sha256(args_gn.encode()).hexdigest(),
        "patches": [
            dict(patch, sha256=hashlib.sha256((series / patch["file"]).read_bytes()).hexdigest())
            for patch in patches
        ],
    }
    provenance_path.write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"{archive_hash}  {archive}")


if __name__ == "__main__":
    main()
