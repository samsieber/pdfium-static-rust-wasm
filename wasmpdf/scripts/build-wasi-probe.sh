#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
crate_dir="$(cd "${script_dir}/.." && pwd)"
repo_dir="$(cd "${crate_dir}/.." && pwd)"
: "${RUST_WASM_SYSROOT:?Set RUST_WASM_SYSROOT to the WASI SDK sysroot used to build PDFium}"
: "${PDFIUM_STATIC_LIB_PATH:=$repo_dir/pdfium-lib/build/static-wasm/release/lib}"
test -f "$PDFIUM_STATIC_LIB_PATH/libpdfium.a"
export PDFIUM_STATIC_LIB_PATH

runtime="$RUST_WASM_SYSROOT/lib/wasm32-wasip1"
export CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_RUSTFLAGS="-Lnative=$runtime -lstatic=c++ -lstatic=c++abi -lstatic=c -lstatic=m -Ctarget-feature=+simd128"

cd "$crate_dir"
wasm-pack build --target web --release --out-dir pkg-wasi-probe --locked

# Bind the shim to memory before any generated startup code runs.
node --input-type=module - <<'JS'
import {readFileSync, writeFileSync} from "node:fs";

const path = "pkg-wasi-probe/wasmpdf.js";
const source = readFileSync(path, "utf8");
const wasiImport = /\bfrom "wasi_snapshot_preview1"/g;
const finalize = /^([ \t]*)wasm = instance\.exports;$/gm;
if (![...source.matchAll(wasiImport)].length || [...source.matchAll(finalize)].length !== 1) {
  throw new Error("Unexpected wasm-bindgen import or initializer layout");
}
const glue = source
  .replace(wasiImport, 'from "../wasi_snapshot_preview1.js"')
  .replace(finalize, "$&\n$1initializeWasi(wasm);");
writeFileSync(path, 'import { initializeWasi } from "../wasi_snapshot_preview1.js";\n' + glue);
JS
