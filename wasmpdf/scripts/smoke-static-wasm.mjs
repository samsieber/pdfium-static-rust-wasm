import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import init, { pdfium_page_count, pdfium_render_page_rgba } from "../pkg-wasi-probe/wasmpdf.js";

const bytes = await readFile(new URL("../pkg-wasi-probe/wasmpdf_bg.wasm", import.meta.url));
const module = await WebAssembly.compile(bytes);
const imports = WebAssembly.Module.imports(module);
assert.ok(imports.some(({ module }) => module === "wasi_snapshot_preview1"));
assert.ok(imports.every(({ name }) => !name.startsWith("FPDF")));
await init({ module_or_path: module });

const sample = await readFile(new URL("../files/test1.pdf", import.meta.url));
assert.throws(() => pdfium_page_count(new Uint8Array()));
assert.equal(pdfium_page_count(sample), 7);
const page = pdfium_render_page_rgba(sample, 0, 900);
try {
  const rgba = page.bytes();
  assert.equal(page.width, 900);
  assert.ok(page.height > 0);
  assert.equal(rgba.length, page.width * page.height * 4);
  assert.ok(rgba.some((value) => value < 255));
  console.log(`Rendered a seven-page fixture in one WASM module (${page.width} × ${page.height})`);
} finally {
  page.free();
}
assert.equal(pdfium_page_count(sample), 7);
