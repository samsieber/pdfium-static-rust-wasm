#!/usr/bin/env node

import { execFileSync } from "node:child_process";

const wasmPath = process.argv[2] ?? "pkg/wasmpdf_bg.wasm";

const output = execFileSync("wasm-objdump", ["-x", wasmPath], {
  encoding: "utf8",
  maxBuffer: 32 * 1024 * 1024,
});

const imports = [...output.matchAll(/<([^>]+)> <- ([^.]+)\.(.+)$/gm)].map(
  ([, symbol, module, field]) => ({ symbol, module, field }),
);

const groups = new Map([
  ["wasm-bindgen/web-sys", []],
  ["C runtime", []],
  ["C++ runtime", []],
  ["Pdfium API", []],
  ["other env", []],
  ["other", []],
]);

const cRuntime = new Set([
  "abort",
  "atoi",
  "calloc",
  "free",
  "frexpf",
  "isprint",
  "iswdigit",
  "isxdigit",
  "lrintf",
  "malloc",
  "memchr",
  "posix_memalign",
  "qsort",
  "rand",
  "realloc",
  "snprintf",
  "strcmp",
  "strcpy",
  "strncmp",
  "strncpy",
  "strstr",
  "strtol",
  "swprintf",
  "tolower",
  "toupper",
  "vsnprintf",
  "wcschr",
  "wcslen",
  "wmemcmp",
  "wmemchr",
]);

for (const item of imports) {
  if (item.module === "./wasmpdf_bg.js") {
    groups.get("wasm-bindgen/web-sys").push(item);
  } else if (item.field.startsWith("FPDF")) {
    groups.get("Pdfium API").push(item);
  } else if (
    item.field.startsWith("_Z") ||
    item.field.startsWith("__cxa") ||
    item.field.includes("St3__")
  ) {
    groups.get("C++ runtime").push(item);
  } else if (cRuntime.has(item.field)) {
    groups.get("C runtime").push(item);
  } else if (item.module === "env") {
    groups.get("other env").push(item);
  } else {
    groups.get("other").push(item);
  }
}

console.log(`Imports: ${imports.length}`);
for (const [name, items] of groups) {
  if (items.length === 0) continue;
  console.log(`\n${name}: ${items.length}`);
  for (const item of items) {
    console.log(`  ${item.module}.${item.field}`);
  }
}
