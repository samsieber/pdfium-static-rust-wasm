# Static PDFium browser example

The root repository pins both inputs. The `pdfium-lib` submodule builds
the PDFium 8125 archive and the `pdfium-render` submodule supplies its
static Rust API bindings. This example links them into one WebAssembly
module and uses a JavaScript WASI Preview 1 shim in the browser.

## Build the PDFium archive

From the repository root, run `git submodule update --init`. Follow the
static WASM build guide at `pdfium-lib/docs/BUILD_STATIC_WASM.md` through
the install step. Keep `RUST_WASM_SYSROOT` set to the absolute path of the
same WASI SDK sysroot used to build the archive.

## Build and run the example

From the repository root with Node.js, Rust, and wasm-pack available, run:

```sh
cd wasmpdf
npm ci
npm run build:wasi-probe
node scripts/smoke-static-wasm.mjs
python3 -m http.server 8080
```

Open `http://localhost:8080/index-wasi-probe.html` and select **Use sample
PDF**. The page counts the seven pages, renders the first page to a canvas,
then counts the pages again using the same instance. You can also test a
local PDF.

The build reads `pdfium-lib/build/static-wasm/release/lib/libpdfium.a` by
default. Set `PDFIUM_STATIC_LIB_PATH` to a different archive directory when
comparing builds. The browser loads `pkg-wasi-probe/wasmpdf_bg.wasm`, its
generated JavaScript, and the shim. It requires SIMD128.
