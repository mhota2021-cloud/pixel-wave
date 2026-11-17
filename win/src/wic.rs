//! Windows Imaging Component (WIC) による画像読み込み・切り取り・縮小

use std::path::Path;

use windows::Win32::Graphics::Imaging::{
    CLSID_WICImagingFactory, GUID_WICPixelFormat32bppBGRA, IWICBitmapSource, IWICImagingFactory,
    WICBitmapDitherTypeNone, WICBitmapInterpolationModeFant, WICBitmapPaletteTypeCustom,
    WICDecodeMetadataCacheOnDemand, WICRect,
};
use windows::Win32::System::Com::{CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED, CoCreateInstance, CoInitializeEx};
use windows::core::HSTRING;

use crate::dotart::{self, Crop, Rgb};

pub struct BgraImage {
    pub w: u32,
    pub h: u32,
    pub bgra: Vec<u8>,
}

fn create_factory() -> windows::core::Result<IWICImagingFactory> {
    unsafe {
        let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
        CoCreateInstance(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER)
    }
}

fn open_first_frame(factory: &IWICImagingFactory, path: &Path) -> windows::core::Result<IWICBitmapSource> {
    unsafe {
        let hpath = HSTRING::from(path.as_os_str());
        let decoder = factory.CreateDecoderFromFilename(
            &hpath,
            None,
            windows::Win32::Foundation::GENERIC_READ,
            WICDecodeMetadataCacheOnDemand,
        )?;
        let frame = decoder.GetFrame(0)?;
        Ok(frame.into())
    }
}

fn to_bgra(factory: &IWICImagingFactory, source: &IWICBitmapSource) -> windows::core::Result<BgraImage> {
    unsafe {
        let converter = factory.CreateFormatConverter()?;
        converter.Initialize(
            source,
            &GUID_WICPixelFormat32bppBGRA,
            WICBitmapDitherTypeNone,
            None,
            0.0,
            WICBitmapPaletteTypeCustom,
        )?;
        let mut w = 0u32;
        let mut h = 0u32;
        converter.GetSize(&mut w, &mut h)?;
        let stride = w * 4;
        let mut bgra = vec![0u8; (stride * h) as usize];
        converter.CopyPixels(std::ptr::null(), stride, &mut bgra)?;
        Ok(BgraImage { w, h, bgra })
    }
}

/// 切り取り＋縮小した画像をBGRAで返す（通常画像モード用）
pub fn decode_cropped_bgra(path: &Path, target_w: u32, target_h: u32, crop: &Crop) -> Option<BgraImage> {
    let factory = create_factory().ok()?;
    let frame = open_first_frame(&factory, path).ok()?;
    let (mut src_w, mut src_h) = (0u32, 0u32);
    unsafe { frame.GetSize(&mut src_w, &mut src_h).ok()? };
    let (cx, cy, cw, ch) = dotart::croprect(src_w, src_h, target_w, target_h, crop);

    unsafe {
        let clipper = factory.CreateBitmapClipper().ok()?;
        let rc = WICRect { X: cx as i32, Y: cy as i32, Width: cw as i32, Height: ch as i32 };
        clipper.Initialize(&frame, &rc).ok()?;

        let scaler = factory.CreateBitmapScaler().ok()?;
        scaler
            .Initialize(&clipper, target_w.max(1), target_h.max(1), WICBitmapInterpolationModeFant)
            .ok()?;

        to_bgra(&factory, &scaler.into()).ok()
    }
}

/// ドット絵化用に切り取り＋(cols, rows) へ縮小したRGB配列を返す（WICのFant縮小を使うため高速）
pub fn decode_dots_rgb(path: &Path, cols: u32, rows: u32, crop: &Crop) -> Option<Vec<Rgb>> {
    let img = decode_cropped_bgra(path, cols, rows, crop)?;
    Some(
        img.bgra
            .chunks_exact(4)
            .map(|px| [px[2], px[1], px[0]])
            .collect(),
    )
}

/// サムネイルやCropWindow用に縦横比を保って縮小したBGRAを返す
pub fn decode_thumb_bgra(path: &Path, max_w: u32, max_h: u32) -> Option<BgraImage> {
    let factory = create_factory().ok()?;
    let frame = open_first_frame(&factory, path).ok()?;
    let (mut src_w, mut src_h) = (0u32, 0u32);
    unsafe { frame.GetSize(&mut src_w, &mut src_h).ok()? };
    if src_w == 0 || src_h == 0 {
        return None;
    }
    let scale = (max_w as f64 / src_w as f64)
        .min(max_h as f64 / src_h as f64)
        .min(1.0);
    let tw = ((src_w as f64 * scale).round() as u32).max(1);
    let th = ((src_h as f64 * scale).round() as u32).max(1);

    unsafe {
        let scaler = factory.CreateBitmapScaler().ok()?;
        scaler.Initialize(&frame, tw, th, WICBitmapInterpolationModeFant).ok()?;
        to_bgra(&factory, &scaler.into()).ok()
    }
}
