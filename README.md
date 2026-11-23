# Static PDFium for WebAssembly

Build a standalone `libpdfium.a` that can be linked into a WebAssembly
application at compile time. The versioned [patch series](patches/) includes
the static toolchain and platform changes, optional performance patches,
and a separate static binding patch for Rust applications.

See the [build, linking, and upgrade guide](docs/build-pdfium-wasm.md) for
the validated PDFium 8125 recipe and target requirements. The archive
builder uses a clean upstream PDFium checkout and requires no Git
submodules from this repository.

The repository also contains the [original Rust prototype](docs/static-wasm-usage.md).
