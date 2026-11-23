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

export function initializeWasi(exports) {
  wasi.initialize({ exports });
}
