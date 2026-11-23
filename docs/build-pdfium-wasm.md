# Build PDFium as a static WebAssembly archive

This patch bundle builds a `libpdfium.a` for the `wasm32-unknown-unknown`
target. Link it into a WebAssembly application to render PDF bytes in
memory, with bundled and embedded fonts. The final module requires
SIMD128 and a WASI Preview 1 host or shim.

Each version directory under `patches/` contains the build patches,
performance patches, pinned source revisions, and GN flags. PDFium's
pinned DEPS defines the remaining dependencies and build tools. Use 8125
for the validated build. The 7623 series is retained for reference.

## Rebuild

Use an Apple Silicon Mac with the Xcode command-line tools, Git, Python 3,
and [Chromium depot_tools](https://chromium.googlesource.com/chromium/tools/depot_tools.git)
on `PATH`. The reproducibility check used depot_tools at
`e923de63bfc631d5a09ef5324635d008d50dc0ca`. The sync installs the pinned
GN, Ninja, and Chromium Clang through PDFium's DEPS. Reserve several GiB
for the checkout and build outputs.

Clone the build recipe without submodules and set `fork` to its absolute
path.

```sh
git clone --branch codex/pdfium-static-wasm-8125 \
  https://github.com/samsieber/pdfium-static-rust-wasm.git
fork="$PWD/pdfium-static-rust-wasm"
```

Run the following from a new directory dedicated to the upstream checkout
and build.

```sh
export DEPOT_TOOLS_UPDATE=0
gclient config --unmanaged --custom-var checkout_configuration=minimal \
  https://pdfium.googlesource.com/pdfium.git
gclient sync -r pdfium@43d55e429cf72c21e9a1e60475b50feefa16fda9 \
  --no-history --shallow --nohooks

curl -fL -o wasi-sysroot-32.0.tar.gz \
  https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-32/wasi-sysroot-32.0.tar.gz
printf '%s  %s\n' \
  f2537f6e5804f7f24e32dd140e9371e9670a9fd2646b6a813ddb896b29954b12 \
  wasi-sysroot-32.0.tar.gz | shasum -a 256 -c -
# Continue only after the checksum check succeeds.
tar -xzf wasi-sysroot-32.0.tar.gz

python3 "$fork/scripts/build-pdfium-wasm.py" 8125 \
  --source "$PWD/pdfium" --sysroot "$PWD/wasi-sysroot-32.0" \
  --gn "$PWD/pdfium/buildtools/mac/gn" \
  --ninja "$PWD/pdfium/third_party/ninja/ninja" \
  --verify-sha256 d327eb0c4c8a563bf4efb43f7f7fde6a69add70765cc343bdd757849bc03f1a3
```

The command checks the pinned revisions and verifies each patch before
applying it. It reverses the patches it applied on normal exit and on
build errors. Give each concurrent build its own upstream checkout. If
a hard kill interrupts the script, use a clean checkout for the next run.
On success the script writes `pdfium/out/pdfium-wasm-8125/obj/libpdfium.a` and
`pdfium/out/pdfium-wasm-8125/libpdfium.provenance.json` with the source pins,
patch hashes, and archive checksum. For a control build, run the same
command with `--build-only` in place of `--verify-sha256 <hash>`. Its
outputs go under `pdfium/out/pdfium-wasm-8125-control`.

## Link the archive

Use the Wasm archive directory as a native library search path and link
PDFium, libc++, libc++abi, libc, and libm from the matching WASI SDK.
A standalone Rust consumer can use `pdfium-render` with the
`pdfium_8125` and `static` features. The
[static WASM binding patch](../patches/pdfium-render-0.9.5-static-wasm.patch)
applies to upstream 0.9.5 commit
`06952ffbca7d7c9336ac7f0313e84fa259712df6`. Point your Cargo
dependency at your patched checkout or use this public pinned revision.

```toml
[dependencies]
pdfium-render = { git = "https://github.com/samsieber/pdfium-render.git", rev = "5d8e06b07a237da62530dc5d6791411f84d85431", default-features = false, features = ["pdfium_8125", "static"] }
```

Set `build_root` to the absolute directory used for the build above.
From your application's directory, run the following.

```sh
export PDFIUM_STATIC_LIB_PATH_wasm32_unknown_unknown="$build_root/pdfium/out/pdfium-wasm-8125/obj"
runtime="$build_root/wasi-sysroot-32.0/lib/wasm32-wasip1"
export CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_RUSTFLAGS="-Lnative=$runtime -lstatic=c++ -lstatic=c++abi -lstatic=c -lstatic=m -Ctarget-feature=+simd128"
wasm-pack build --target web --release
```

Use `Pdfium::default()` and open documents from byte slices or vectors.
For a browser, resolve the generated JavaScript imports from
`wasi_snapshot_preview1` to a Preview 1 shim such as
`@bjorn3/browser_wasi_shim`. Attach the instance's exported memory to
the shim after instantiation and before running generated startup code
such as `__wbindgen_start()`. For example, with `browser_wasi_shim` 0.4.2,
instantiate a `WASI` object, expose its `wasiImport` functions, and call
`wasi.initialize({ exports: wasm })` from the generated initialization
glue just before that startup call. The imports needed depend on the final
application's link result.

## PDFium 8125 patch review

| Patch | Scope and checks to preserve when porting |
| --- | --- |
| `build-pdfium.patch` | Provides the memory-backed platform layer and PDFium's built-in font fallback. Recheck the file, time, and C library shims when changing the enabled PDFium features or codec call paths. |
| `build-chromium-build.patch` | Adds the GN toolchain, WASI sysroot flags, SIMD switch, and the nonlocal-jump shim. Verify the target triple and that the final browser module can be linked with the matching SDK. |
| `build-abseil.patch` | Substitutes single-threaded process and synchronization behavior, UTC/fixed-offset time zones, and limited logging and entropy. Recheck any new callers before extending guest capabilities. |
| `build-freetype.patch` | Keeps FreeType allocation and memory streams available. File streams return an error. Verify embedded font and bundled font rendering. |
| `build-icu.patch` | Uses built-in ICU data and substitutes file, environment, and wall-clock operations. Verify text handling when rolling ICU. |
| `build-libjpeg-turbo.patch` | Supports PDFium's memory-backed JPEG stream and substitutes stdio operations. Verify JPEG decode, including error handling when changing how the library is invoked. |
| `build-zlib.patch` | Drops gzip file I/O from the target and retains in-memory zlib streams used for PDF data. |
| `pdfium-8125-stretch-simd.patch` | Adds indexed-color two-tap horizontal stretch and opaque vertical stretch. Preserve tap and row-span checks, scalar tails, the fourth destination byte on opaque 32-bit rows, and deadline polling. |
| `pdfium-8125-scanline-simd.patch` | Accelerates BGR expansion and normal BGRA blending. Preserve channel order, the expansion overlap check, the opaque-destination condition for vector blending, and scalar tails. |
| `pdfium-8125-glyph-blend.patch` | Hoists row checks for normalized LCD glyph blending. Preserve the shifted prefix case and integer alpha math. |
| `pdfium-8125-jpeg-idct.patch` | Vectorizes the 8-bit accurate integer inverse DCT. Preserve each rounding step, range-table semantics, and the scalar paths for other configurations. |

The archive is scoped to single-threaded, memory-backed PDF rendering with
bundled and embedded fonts. Its platform shims provide fixed process/time
values and reduced logging, entropy, and filesystem support. In particular,
a codec or FreeType error path that executes the substituted `longjmp`
traps in WebAssembly instead of unwinding through C. The pixel regression
corpus does not establish coverage for those error paths.

## Update the PDFium revision

1. Choose the upstream PDFium revision and matching binding API feature.
2. Sync a clean checkout at that revision. Copy the previous series into a
   new version directory and record the actual commits of the patched
   repositories.
3. Port the build patches first, then the performance patches. Generate
   refreshed diffs against each repository's new base.
4. Build with and without the performance patches. Compare rendered
   dimensions and RGBA bytes for PDFs with embedded fonts and images
   before comparing timings. Retest the final linked module in the host
   where it will run.

PDFium 8125 already has Highway-based packed/indexed grayscale horizontal
stretch kernels, one- and two-tap fast paths, and row-wide vertical
accumulation. The 8125 series keeps those upstream paths and ports the
extra indexed-color and vertical SIMD paths, BGR/BGRA composition, glyph
blending, and JPEG IDCT. FreeType moved LCD filtering into its smooth
renderer's span callbacks. The 7623 bitmap FIR patch is archived with the
original series.
