# wasmpdf

Small `wasm-pack`-oriented wrapper crate for experimenting with a statically linked
`pdfium-render` WebAssembly build.

The crate currently depends on the local `../pdfium-render` subtree with its
`static` feature enabled.

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
wasm-objdump -x pkg/wasmpdf_bg.wasm
```

Those imports are the next integration boundary for the static archive.
