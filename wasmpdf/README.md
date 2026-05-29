# wasmpdf

Small `wasm-pack`-oriented wrapper crate for experimenting with a statically linked
`pdfium-render` WebAssembly build.

The crate currently depends on the local `../pdfium-render` subtree with its
`static` feature enabled. It pins `pdfium-render` to the `pdfium_7543` API
feature because the current Pdfium checkout is `chromium/7623`; newer
`pdfium_7763` bindings reference APIs not present in the archive.

After building the Pdfium archive prototype, run a Rust-side link probe with:

```sh
PDFIUM_STATIC_LIB_PATH=../pdfium-lib/build/rust-wasm/pdfium/out/wasm32-wasm-release/obj \
  cargo build --target wasm32-unknown-unknown
```

The `pdfium_static_init_probe()` export initializes Pdfium through
`pdfium-render`'s static bindings, which forces the generated `libpdfium.a`
into the final `.wasm` output.

To run the browser smoke page:

```sh
python3 -m http.server 8080
```

Then open `http://127.0.0.1:8080/index.html` from this directory.

Current caveat: the Rust link succeeds and `wasm-pack` produces `pkg/`, but the
browser page currently reports a bare `env` module import. Inspect it with:

```sh
node scripts/audit-wasm-imports.mjs
```

Those imports are the next integration boundary for the static archive. The
current list is runtime-shaped: C allocator/string/math/wide-char helpers and
libc++ ABI/iostream helpers remain as `env` imports.

## WASI shim probe

A WASI-linked probe can collapse the C and C++ runtime imports down to
`wasi_snapshot_preview1` imports that can be satisfied in the browser with
`@bjorn3/browser_wasi_shim`.

First install the browser shim:

```sh
npm install
```

Then build the WASI probe output:

```sh
npm run build:wasi-probe
```

This runs a release `wasm-pack` build. The crate pins `[profile.release]` to
`opt-level = 3` with LTO enabled.

The script expects the local WASI sysroot probe at
`/private/tmp/wasi-sdk-probe/wasi-sysroot-32.0` by default. Override
`WASI_SYSROOT` if using another sysroot.

To inspect the remaining imports:

```sh
node scripts/audit-wasm-imports.mjs pkg-wasi-probe/wasmpdf_bg.wasm
```

To run it in the browser, serve this directory and open
`http://127.0.0.1:8080/index-wasi-probe.html`. The page maps the generated
`wasi_snapshot_preview1` imports to `wasi_snapshot_preview1.js` with an import
map, then loads `pkg-wasi-probe/wasmpdf.js`.
