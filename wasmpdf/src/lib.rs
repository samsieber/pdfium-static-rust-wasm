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

#[wasm_bindgen]
pub fn pdfium_page_count(bytes: Vec<u8>) -> Result<i32, String> {
    let pdfium = Pdfium::default();
    let document = pdfium
        .load_pdf_from_byte_vec(bytes, None)
        .map_err(|error| error.to_string())?;

    Ok(document.pages().len())
}
