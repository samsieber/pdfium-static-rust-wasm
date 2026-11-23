# Static PDFium for WebAssembly

This repository demonstrates linking PDFium and its Rust bindings into
one browser WebAssembly module. The
[`pdfium-lib` submodule](pdfium-lib) builds `libpdfium.a`, and the
[`pdfium-render` submodule](pdfium-render) supplies the matching bindings.

See the [integration example](wasmpdf/README.md) to build both inputs
and render a PDF in the browser. The [standalone 8125 build recipe](docs/build-pdfium-wasm.md)
records the reference archive used to verify the integrated build.
