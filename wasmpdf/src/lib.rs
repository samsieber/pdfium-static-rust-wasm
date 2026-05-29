use pdfium_render::prelude::{PdfRenderConfig, Pdfium};
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct RenderedPdfPage {
    width: u32,
    height: u32,
    bytes: Vec<u8>,
}

#[wasm_bindgen]
impl RenderedPdfPage {
    #[wasm_bindgen(getter)]
    pub fn width(&self) -> u32 {
        self.width
    }

    #[wasm_bindgen(getter)]
    pub fn height(&self) -> u32 {
        self.height
    }

    pub fn bytes(&self) -> Vec<u8> {
        self.bytes.clone()
    }
}

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

#[wasm_bindgen]
pub fn pdfium_render_page_rgba(
    bytes: Vec<u8>,
    page_index: i32,
    target_width: i32,
) -> Result<RenderedPdfPage, String> {
    let pdfium = Pdfium::default();
    let document = pdfium
        .load_pdf_from_byte_vec(bytes, None)
        .map_err(|error| error.to_string())?;
    let page = document
        .pages()
        .get(page_index)
        .map_err(|error| error.to_string())?;
    let bitmap = page
        .render_with_config(&PdfRenderConfig::new().set_target_width(target_width))
        .map_err(|error| error.to_string())?;

    Ok(RenderedPdfPage {
        width: bitmap.width() as u32,
        height: bitmap.height() as u32,
        bytes: bitmap.as_rgba_bytes(),
    })
}
