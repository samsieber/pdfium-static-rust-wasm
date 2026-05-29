#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
crate_dir="$(cd "${script_dir}/.." && pwd)"
repo_dir="$(cd "${crate_dir}/.." && pwd)"

: "${WASI_SYSROOT:=/private/tmp/wasi-sdk-probe/wasi-sysroot-32.0}"
: "${PDFIUM_STATIC_LIB_PATH:=${repo_dir}/pdfium-lib/build/rust-wasm/pdfium/out/wasm32-wasm-release/obj}"

export RUSTFLAGS="-L native=${WASI_SYSROOT}/lib/wasm32-wasip1 -l static=c++ -l static=c++abi -l static=c -l static=m ${RUSTFLAGS:-}"
export PDFIUM_STATIC_LIB_PATH

cd "${crate_dir}"
wasm-pack build --target web --release --out-dir pkg-wasi-probe
