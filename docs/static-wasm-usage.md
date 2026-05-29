# Using the static Pdfium WASM build

This note describes how to use this `pdfium-render` fork with a statically linked
`libpdfium.a` in a browser project that currently uses the separate dynamic
Pdfium WASM module.

The current prototype target is:

- Rust target: `wasm32-unknown-unknown`
- JS packaging: `wasm-pack --target web`
- Pdfium archive: `pdfium-lib/build/rust-wasm/pdfium/out/wasm32-wasm-release/obj/libpdfium.a`
- Runtime shim: WASI imports mapped to `@bjorn3/browser_wasi_shim`

## Cargo dependency

Point the consuming crate at this fork and enable static Pdfium bindings. Pin the
Pdfium API feature to the archive you built; the current local archive comes from
Pdfium `chromium/7623`, so this repo uses `pdfium_7543`.

```toml
[dependencies]
pdfium-render = {
  path = "../pdfium-bundle/pdfium-render",
  default-features = false,
  features = [
    "pdfium_7543",
    "image_latest",
    "static",
    "console_log",
  ],
}
wasm-bindgen = "0"
```

For a non-path dependency later, replace `path = ...` with the fork git URL or an
upstream release that includes the static WASM changes.

## Rust initialization

Use `Pdfium::default()` or `Pdfium::new(Pdfium::bind_to_statically_linked_library()?)`.
Do not call `initialize_pdfium_render()` from JavaScript; that is for the old
dynamic two-module browser setup.

```rust
use pdfium_render::prelude::{PdfRenderConfig, Pdfium};
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub fn page_count(bytes: Vec<u8>) -> Result<i32, String> {
    let pdfium = Pdfium::default();
    let document = pdfium
        .load_pdf_from_byte_vec(bytes, None)
        .map_err(|error| error.to_string())?;

    Ok(document.pages().len())
}

#[wasm_bindgen]
pub fn render_page_rgba(
    bytes: Vec<u8>,
    page_index: i32,
    target_width: i32,
) -> Result<Vec<u8>, String> {
    let pdfium = Pdfium::default();
    let document = pdfium
        .load_pdf_from_byte_vec(bytes, None)
        .map_err(|error| error.to_string())?;
    let page = document
        .pages()
        .get(page_index)
        .map_err(|error| error.to_string())?;

    page.render_with_config(&PdfRenderConfig::new().set_target_width(target_width))
        .map_err(|error| error.to_string())
        .map(|bitmap| bitmap.as_rgba_bytes())
}
```

## Build the WASI-linked package

The final link needs both the Pdfium static archive and WASI SDK runtime archives
for libc, libc++, libc++abi, and libm.

```sh
export PDFIUM_STATIC_LIB_PATH=/absolute/path/to/pdfium-bundle/pdfium-lib/build/rust-wasm/pdfium/out/wasm32-wasm-release/obj
export WASI_SYSROOT=/absolute/path/to/wasi-sysroot-32.0

export RUSTFLAGS="-L native=${WASI_SYSROOT}/lib/wasm32-wasip1 -l static=c++ -l static=c++abi -l static=c -l static=m"
```

Use release mode and set an explicit release profile in the consuming crate:

```toml
[profile.release]
opt-level = 3
lto = true
codegen-units = 1
```

```sh
wasm-pack build --target web --release --out-dir pkg-wasi
```

For this repo's probe crate, the same build is wrapped by:

```sh
cd wasmpdf
npm install
npm run build:wasi-probe
```

After building, the generated JS will contain bare imports from
`"wasi_snapshot_preview1"`. That is expected for this prototype.

## Browser shim files

Install the shim package in the consuming web project:

```sh
npm install @bjorn3/browser_wasi_shim
```

Include a module named `wasi_snapshot_preview1.js` next to the generated
`wasm-pack` package, or adjust paths to match your app layout:

```js
import {
  ConsoleStdout,
  File,
  OpenFile,
  WASI,
} from "./node_modules/@bjorn3/browser_wasi_shim/dist/index.js";

export const wasi = new WASI([], [], [
  new OpenFile(new File([])),
  ConsoleStdout.lineBuffered((line) => console.log(`[wasi stdout] ${line}`)),
  ConsoleStdout.lineBuffered((line) => console.warn(`[wasi stderr] ${line}`)),
]);

export const {
  environ_get,
  environ_sizes_get,
  fd_close,
  fd_fdstat_get,
  fd_prestat_dir_name,
  fd_prestat_get,
  fd_seek,
  fd_write,
  proc_exit,
} = wasi.wasiImport;
```

## HTML initialization

Use an import map so the browser can resolve wasm-pack's bare
`"wasi_snapshot_preview1"` imports:

```html
<script type="importmap">
  {
    "imports": {
      "wasi_snapshot_preview1": "./wasi_snapshot_preview1.js"
    }
  }
</script>
```

Then initialize the generated wasm-pack module normally:

```html
<script type="module">
  import init, { page_count, render_page_rgba } from "./pkg-wasi/my_crate.js";

  await init();

  const file = document.querySelector("input[type=file]").files[0];
  const bytes = new Uint8Array(await file.arrayBuffer());
  const pages = page_count(bytes);

  const renderBytes = new Uint8Array(await file.arrayBuffer());
  const rgba = render_page_rgba(renderBytes, 0, 900);

  // If your Rust function also returns width and height, paint RGBA bytes with:
  // canvas.getContext("2d").putImageData(
  //   new ImageData(new Uint8ClampedArray(rgba), width, height),
  //   0,
  //   0,
  // );
  // const dataUrl = canvas.toDataURL("image/png");
</script>
```

## Files to ship

For the static WASI prototype, a browser deployment needs:

- `pkg-wasi/*.js`, `pkg-wasi/*.wasm`, and generated TypeScript files if used.
- `wasi_snapshot_preview1.js`.
- A way to serve or bundle `@bjorn3/browser_wasi_shim/dist/*.js`.
- An HTML import map, or a bundler alias, that maps
  `"wasi_snapshot_preview1"` to the shim module.

It does not need the old separate Pdfium WASM binary or a JavaScript call to
`initialize_pdfium_render()`.

## Known caveats

- This path currently depends on a WASI sysroot at link time and a browser WASI
  shim at runtime.
- The generated wasm-pack JS uses bare static imports for
  `"wasi_snapshot_preview1"`, so direct browser use needs an import map. Bundled
  apps can use an equivalent resolver alias.
- Keep the `pdfium-render` API feature aligned with the Pdfium archive. Using a
  newer API feature than the archive can introduce missing Pdfium symbols.
- The current probe returns raw RGBA bytes for rendering; browser code can paint
  those bytes to a canvas and then call `canvas.toDataURL("image/png")` or
  `canvas.toBlob()`.
