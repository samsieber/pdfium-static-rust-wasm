use pdfium_render::prelude::Pdfium;
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub fn wasmpdf_version() -> String {
    format!("wasmpdf {}", env!("CARGO_PKG_VERSION"))
}

#[wasm_bindgen]
pub fn pdfium_static_init_probe() -> bool {
    let _pdfium = Pdfium::default();
    true
}
