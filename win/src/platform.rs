//! Windows API連携（DIB裏画面、壁紙貼り付け、トレイ、ショートカット、ダイアログ、レジストリ）

use std::ffi::c_void;
use std::fs;
use std::path::{Path, PathBuf};

use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, MAX_PATH, POINT, RECT, WPARAM};
use windows::Win32::Globalization::GetUserDefaultUILanguage;
use windows::Win32::Graphics::Gdi::{
    BI_RGB, BITMAPINFO, BITMAPINFOHEADER, BitBlt, CombineRgn, CreateCompatibleBitmap, CreateCompatibleDC,
    CreateDIBSection, CreateEllipticRgn, CreateFontW, CreatePen, CreateRectRgn, CreateSolidBrush,
    DIB_RGB_COLORS, DT_CENTER, DT_NOPREFIX, DT_SINGLELINE, DT_VCENTER, DeleteDC, DeleteObject,
    DrawTextW, Ellipse, FONT_CHARSET, FONT_CLIP_PRECISION, FONT_OUTPUT_PRECISION, FONT_QUALITY,
    GetDC, GetStockObject, GetTextExtentPoint32W, HBITMAP, HDC, HFONT, HGDIOBJ,
    InvalidateRect, NULL_BRUSH, NULL_PEN, PS_SOLID, RGN_AND, ReleaseDC, RoundRect, SRCCOPY,
    SelectClipRgn, SelectObject, SetBkMode, SetTextColor, StretchDIBits, TRANSPARENT,
};
use windows::Win32::System::Com::{
    CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED, CoCreateInstance, CoInitializeEx, IPersistFile,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Registry::{
    HKEY_CURRENT_USER, KEY_READ, KEY_WRITE, REG_SZ, RegCreateKeyExW, RegOpenKeyExW,
    RegQueryValueExW, RegSetValueExW,
};
use windows::Win32::System::Threading::CreateMutexW;
use windows::Win32::UI::Controls::Dialogs::{
    CC_FULLOPEN, CC_RGBINIT, CHOOSECOLORW, ChooseColorW, GetOpenFileNameW, OFN_ALLOWMULTISELECT,
    OFN_EXPLORER, OFN_FILEMUSTEXIST, OPENFILENAMEW,
};
use windows::Win32::UI::Shell::{
    CSIDL_STARTUP, IShellLinkW, NIF_ICON, NIF_MESSAGE, NIF_TIP, NIM_ADD, NIM_DELETE,
    NOTIFYICONDATAW, SHGetSpecialFolderPathW, Shell_NotifyIconW, ShellLink,
};
use windows::Win32::UI::WindowsAndMessaging::{
    AppendMenuW, CreatePopupMenu, DestroyMenu, EnumWindows, FindWindowExW, FindWindowW,
    GW_HWNDNEXT, GWL_EXSTYLE, GWL_STYLE, GetClientRect, GetCursorPos,
    GetSystemMetrics, GetWindow, GetWindowLongPtrW, HICON,
    IMAGE_ICON, LR_DEFAULTSIZE, LR_LOADFROMFILE, LoadIconW, LoadImageW, MF_SEPARATOR, MF_STRING,
    PostMessageW, SM_CXSCREEN, SM_CXVIRTUALSCREEN, SM_CYSCREEN, SM_CYVIRTUALSCREEN,
    SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN, SPI_GETWORKAREA, SPI_SETSCREENSAVEACTIVE, SPIF_SENDCHANGE,
    SW_HIDE, SW_RESTORE, SW_SHOW, SW_SHOWNORMAL, SWP_FRAMECHANGED, SWP_NOACTIVATE, SWP_NOMOVE,
    SWP_NOSIZE, SWP_SHOWWINDOW, SendMessageTimeoutW, SetForegroundWindow, SetLayeredWindowAttributes,
    SetParent, SetWindowLongPtrW, SetWindowPos, ShowWindow, SystemParametersInfoW, TPM_RETURNCMD,
    TPM_RIGHTBUTTON, TrackPopupMenu, WS_CAPTION, WS_CHILD, WS_EX_LAYERED, WS_POPUP, WS_THICKFRAME,
    WS_VISIBLE, LWA_ALPHA, SMTO_NORMAL,
};
use windows::core::{BOOL, Interface, PCWSTR, PWSTR};

use crate::dotart::Rgb;
use crate::settings_layout::Rect;

pub const WM_TRAYICON: u32 = 0x8001;
pub const WM_APP_OPEN_SETTINGS: u32 = 0x8010;
pub const WM_APP_LOAD_DONE: u32 = 0x8011;

pub fn wide_null(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

pub fn colorref(rgb: Rgb) -> COLORREF {
    COLORREF((rgb[0] as u32) | ((rgb[1] as u32) << 8) | ((rgb[2] as u32) << 16))
}

pub fn data_dir() -> PathBuf {
    let base = std::env::var_os("APPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    let dir = base.join("PixelWave");
    let _ = fs::create_dir_all(&dir);
    dir
}

pub fn cache_dir() -> PathBuf {
    let dir = data_dir().join("cache");
    let _ = fs::create_dir_all(&dir);
    dir
}

pub fn exe_path() -> PathBuf {
    std::env::current_exe().unwrap_or_else(|_| PathBuf::from("PixelWave.exe"))
}

pub fn exe_dir() -> PathBuf {
    exe_path().parent().map(Path::to_path_buf).unwrap_or_else(|| PathBuf::from("."))
}

pub fn default_lang_code() -> &'static str {
    let lang_id = unsafe { GetUserDefaultUILanguage() } & 0x03FF;
    if lang_id == 0x11 { "ja" } else { "en" }
}

pub fn virtual_screen() -> (i32, i32, i32, i32) {
    unsafe {
        (
            GetSystemMetrics(SM_XVIRTUALSCREEN),
            GetSystemMetrics(SM_YVIRTUALSCREEN),
            GetSystemMetrics(SM_CXVIRTUALSCREEN).max(1),
            GetSystemMetrics(SM_CYVIRTUALSCREEN).max(1),
        )
    }
}

pub fn primary_screen() -> (i32, i32) {
    unsafe { (GetSystemMetrics(SM_CXSCREEN).max(1), GetSystemMetrics(SM_CYSCREEN).max(1)) }
}

pub fn work_area() -> (i32, i32, i32, i32) {
    unsafe {
        let mut r = RECT::default();
        if SystemParametersInfoW(SPI_GETWORKAREA, 0, Some(&mut r as *mut _ as *mut c_void), Default::default()).is_ok() {
            return (r.left, r.top, (r.right - r.left).max(1), (r.bottom - r.top).max(1));
        }
    }
    (0, 0, 1280, 720)
}

pub fn client_size(hwnd: HWND) -> (i32, i32) {
    unsafe {
        let mut r = RECT::default();
        if GetClientRect(hwnd, &mut r).is_ok() {
            return ((r.right - r.left).max(1), (r.bottom - r.top).max(1));
        }
    }
    (0, 0)
}

/// シングルインスタンス用ミューテックス。既に起動していれば true
pub fn take_single_instance_mutex(name: &str) -> bool {
    unsafe {
        let w = wide_null(name);
        let h = CreateMutexW(None, false, PCWSTR(w.as_ptr()));
        let err = windows::Win32::Foundation::GetLastError();
        let _ = h;
        err == windows::Win32::Foundation::ERROR_ALREADY_EXISTS
    }
}

pub fn find_window_by_class(class_name: &str) -> Option<HWND> {
    unsafe {
        let w = wide_null(class_name);
        let h = FindWindowW(PCWSTR(w.as_ptr()), PCWSTR::null()).ok()?;
        if h.is_invalid() { None } else { Some(h) }
    }
}

pub fn post_message(hwnd: HWND, msg: u32, wparam: usize, lparam: isize) {
    unsafe {
        let _ = PostMessageW(Some(hwnd), msg, WPARAM(wparam), LPARAM(lparam));
    }
}

pub fn bring_to_front(hwnd: HWND) {
    unsafe {
        let _ = ShowWindow(hwnd, SW_RESTORE);
        let _ = ShowWindow(hwnd, SW_SHOWNORMAL);
        let _ = SetForegroundWindow(hwnd);
    }
}

pub fn invalidate_rect(hwnd: HWND, rect: Option<Rect>) {
    unsafe {
        match rect {
            Some(r) => {
                let wr = RECT { left: r.x, top: r.y, right: r.x + r.w, bottom: r.y + r.h };
                let _ = InvalidateRect(Some(hwnd), Some(&wr), false);
            }
            None => {
                let _ = InvalidateRect(Some(hwnd), None, false);
            }
        }
    }
}

/// 32bpp トップダウン DIB セクションによる裏画面（ピクセル配列への直接書き込みが可能）
pub struct BackBuffer {
    pub dc: HDC,
    bitmap: HBITMAP,
    old_bitmap: HGDIOBJ,
    bits: *mut u8,
    pub width: i32,
    pub height: i32,
}

impl BackBuffer {
    pub fn new(hwnd: HWND, width: i32, height: i32) -> Self {
        let w = width.max(1);
        let h = height.max(1);
        unsafe {
            let screen_dc = GetDC(Some(hwnd));
            let dc = CreateCompatibleDC(Some(screen_dc));
            let bmi = BITMAPINFO {
                bmiHeader: BITMAPINFOHEADER {
                    biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                    biWidth: w,
                    biHeight: -h,
                    biPlanes: 1,
                    biBitCount: 32,
                    biCompression: BI_RGB.0,
                    ..Default::default()
                },
                ..Default::default()
            };
            let mut bits: *mut c_void = std::ptr::null_mut();
            let bitmap = CreateDIBSection(Some(screen_dc), &bmi, DIB_RGB_COLORS, &mut bits, None, 0)
                .expect("CreateDIBSection failed");
            let old_bitmap = SelectObject(dc, bitmap.into());
            ReleaseDC(Some(hwnd), screen_dc);
            Self { dc, bitmap, old_bitmap, bits: bits as *mut u8, width: w, height: h }
        }
    }

    pub fn fill_all(&mut self, rgb: Rgb) {
        self.fill_rect(Rect::new(0, 0, self.width, self.height), rgb);
    }

    /// ピクセル配列に直接書き込む（GDIブラシ生成ゼロ）
    pub fn fill_rect(&mut self, rect: Rect, rgb: Rgb) {
        let x0 = rect.x.max(0);
        let y0 = rect.y.max(0);
        let x1 = (rect.x + rect.w).min(self.width);
        let y1 = (rect.y + rect.h).min(self.height);
        if x0 >= x1 || y0 >= y1 || self.bits.is_null() {
            return;
        }
        let pixel = u32::from_le_bytes([rgb[2], rgb[1], rgb[0], 0xFF]);
        let stride = self.width as usize;
        let slice = unsafe { std::slice::from_raw_parts_mut(self.bits as *mut u32, stride * self.height as usize) };
        for y in y0..y1 {
            let row = &mut slice[(y as usize * stride + x0 as usize)..(y as usize * stride + x1 as usize)];
            row.fill(pixel);
        }
    }

    pub fn blit_to(&self, target_dc: HDC) {
        unsafe {
            let _ = BitBlt(target_dc, 0, 0, self.width, self.height, Some(self.dc), 0, 0, SRCCOPY);
        }
    }
}

impl Drop for BackBuffer {
    fn drop(&mut self) {
        unsafe {
            if !self.dc.is_invalid() {
                SelectObject(self.dc, self.old_bitmap);
                let _ = DeleteObject(self.bitmap.into());
                let _ = DeleteDC(self.dc);
            }
        }
    }
}

/// メモリDC上に保持したビットマップ（通常画像モード用）
pub struct MemBitmap {
    pub dc: HDC,
    bitmap: HBITMAP,
    old_bitmap: HGDIOBJ,
}

impl MemBitmap {
    pub fn from_bgra(ref_dc: HDC, width: i32, height: i32, bgra: &[u8]) -> Option<Self> {
        let w = width.max(1);
        let h = height.max(1);
        unsafe {
            let dc = CreateCompatibleDC(Some(ref_dc));
            let bitmap = CreateCompatibleBitmap(ref_dc, w, h);
            let old_bitmap = SelectObject(dc, bitmap.into());
            let bmi = BITMAPINFO {
                bmiHeader: BITMAPINFOHEADER {
                    biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                    biWidth: w,
                    biHeight: -h,
                    biPlanes: 1,
                    biBitCount: 32,
                    biCompression: BI_RGB.0,
                    biSizeImage: (w * h * 4) as u32,
                    ..Default::default()
                },
                ..Default::default()
            };
            StretchDIBits(
                dc,
                0,
                0,
                w,
                h,
                0,
                0,
                w,
                h,
                Some(bgra.as_ptr() as *const c_void),
                &bmi,
                DIB_RGB_COLORS,
                SRCCOPY,
            );
            Some(Self { dc, bitmap, old_bitmap })
        }
    }
}

impl Drop for MemBitmap {
    fn drop(&mut self) {
        unsafe {
            if !self.dc.is_invalid() {
                SelectObject(self.dc, self.old_bitmap);
                let _ = DeleteObject(self.bitmap.into());
                let _ = DeleteDC(self.dc);
            }
        }
    }
}

/// 通常画像モードの波切り替え描画（円形リージョン＋光輪）
pub fn render_normal_wave(
    target_dc: HDC,
    from: &MemBitmap,
    to: &MemBitmap,
    offset_x: i32,
    offset_y: i32,
    w: i32,
    h: i32,
    cx: i32,
    cy: i32,
    r: i32,
) {
    unsafe {
        let _ = BitBlt(target_dc, offset_x, offset_y, w, h, Some(from.dc), 0, 0, SRCCOPY);
        if r <= 0 {
            return;
        }
        let rect_rgn = CreateRectRgn(offset_x, offset_y, offset_x + w, offset_y + h);
        let ellip_rgn = CreateEllipticRgn(offset_x + cx - r, offset_y + cy - r, offset_x + cx + r, offset_y + cy + r);
        let clip_rgn = CreateRectRgn(0, 0, 0, 0);
        CombineRgn(Some(clip_rgn), Some(rect_rgn), Some(ellip_rgn), RGN_AND);

        SelectClipRgn(target_dc, Some(clip_rgn));
        let _ = BitBlt(target_dc, offset_x, offset_y, w, h, Some(to.dc), 0, 0, SRCCOPY);

        SelectClipRgn(target_dc, Some(rect_rgn));
        let band_w = ((w as f64 / 500.0).round() as i32).max(2);
        let pen = CreatePen(PS_SOLID, band_w, colorref([255, 255, 255]));
        let null_brush = GetStockObject(NULL_BRUSH);
        let old_pen = SelectObject(target_dc, pen.into());
        let old_brush = SelectObject(target_dc, null_brush);
        let _ = Ellipse(target_dc, offset_x + cx - r, offset_y + cy - r, offset_x + cx + r, offset_y + cy + r);
        SelectObject(target_dc, old_pen);
        SelectObject(target_dc, old_brush);
        let _ = DeleteObject(pen.into());

        SelectClipRgn(target_dc, None);
        let _ = DeleteObject(clip_rgn.into());
        let _ = DeleteObject(ellip_rgn.into());
        let _ = DeleteObject(rect_rgn.into());
    }
}

/// GDI描画ヘルパー（角丸・テキスト）
pub fn fill_round_rect(dc: HDC, r: Rect, radius: i32, fill: Rgb, border: Rgb) {
    unsafe {
        let brush = CreateSolidBrush(colorref(fill));
        let pen = CreatePen(PS_SOLID, 1, colorref(border));
        let old_b = SelectObject(dc, brush.into());
        let old_p = SelectObject(dc, pen.into());
        let _ = RoundRect(dc, r.x, r.y, r.x + r.w, r.y + r.h, radius, radius);
        SelectObject(dc, old_b);
        SelectObject(dc, old_p);
        let _ = DeleteObject(brush.into());
        let _ = DeleteObject(pen.into());
    }
}

pub fn draw_border_round_rect(dc: HDC, r: Rect, radius: i32, border: Rgb) {
    unsafe {
        let null_brush = GetStockObject(NULL_BRUSH);
        let pen = CreatePen(PS_SOLID, 1, colorref(border));
        let old_b = SelectObject(dc, null_brush);
        let old_p = SelectObject(dc, pen.into());
        let _ = RoundRect(dc, r.x, r.y, r.x + r.w, r.y + r.h, radius, radius);
        SelectObject(dc, old_b);
        SelectObject(dc, old_p);
        let _ = DeleteObject(pen.into());
    }
}

pub fn draw_toggle_pill(dc: HDC, r: Rect, anim_pos: f64) {
    let off = [60.0, 60.0, 70.0];
    let on = [11.0, 92.0, 173.0];
    let lerp = |i: usize| (off[i] + (on[i] - off[i]) * anim_pos).round().clamp(0.0, 255.0) as u8;
    let track_rgb = [lerp(0), lerp(1), lerp(2)];
    unsafe {
        let brush = CreateSolidBrush(colorref(track_rgb));
        let null_pen = GetStockObject(NULL_PEN);
        let old_b = SelectObject(dc, brush.into());
        let old_p = SelectObject(dc, null_pen);
        let _ = RoundRect(dc, r.x, r.y, r.x + r.w, r.y + r.h, r.h, r.h);

        let pad = 3;
        let knob_d = r.h - pad * 2;
        let travel = r.w - knob_d - pad * 2;
        let kx = r.x + pad + (travel as f64 * anim_pos).round() as i32;
        let ky = r.y + pad;
        let knob_brush = CreateSolidBrush(colorref([255, 255, 255]));
        SelectObject(dc, knob_brush.into());
        let _ = Ellipse(dc, kx, ky, kx + knob_d, ky + knob_d);

        SelectObject(dc, old_b);
        SelectObject(dc, old_p);
        let _ = DeleteObject(brush.into());
        let _ = DeleteObject(knob_brush.into());
    }
}

pub fn make_font(px: i32, bold: bool) -> HFONT {
    let name = wide_null("Yu Gothic UI");
    unsafe {
        CreateFontW(
            -px,
            0,
            0,
            0,
            if bold { 700 } else { 400 },
            0,
            0,
            0,
            FONT_CHARSET(1),
            FONT_OUTPUT_PRECISION(0),
            FONT_CLIP_PRECISION(0),
            FONT_QUALITY(0),
            0,
            PCWSTR(name.as_ptr()),
        )
    }
}

pub fn draw_text(dc: HDC, text: &str, r: Rect, font: HFONT, rgb: Rgb, center: bool) {
    unsafe {
        SelectObject(dc, font.into());
        SetTextColor(dc, colorref(rgb));
        SetBkMode(dc, TRANSPARENT);
        let mut w = wide_null(text);
        let len = w.len() - 1;
        let mut wr = RECT { left: r.x, top: r.y, right: r.x + r.w, bottom: r.y + r.h };
        let mut flags = DT_SINGLELINE | DT_NOPREFIX;
        if center {
            flags |= DT_CENTER | DT_VCENTER;
        } else {
            flags |= DT_VCENTER;
        }
        DrawTextW(dc, &mut w[..len], &mut wr, flags);
    }
}

pub fn draw_text_top(dc: HDC, text: &str, r: Rect, font: HFONT, rgb: Rgb) {
    unsafe {
        SelectObject(dc, font.into());
        SetTextColor(dc, colorref(rgb));
        SetBkMode(dc, TRANSPARENT);
        let mut w = wide_null(text);
        let len = w.len() - 1;
        let mut wr = RECT { left: r.x, top: r.y, right: r.x + r.w, bottom: r.y + r.h };
        DrawTextW(dc, &mut w[..len], &mut wr, DT_SINGLELINE | DT_NOPREFIX);
    }
}

pub fn text_width(dc: HDC, font: HFONT, text: &str) -> i32 {
    unsafe {
        SelectObject(dc, font.into());
        let w: Vec<u16> = text.encode_utf16().collect();
        let mut sz = windows::Win32::Foundation::SIZE::default();
        let _ = GetTextExtentPoint32W(dc, &w, &mut sz);
        sz.cx
    }
}

pub fn blit_bgra_rect(dc: HDC, dst: Rect, src_w: i32, src_h: i32, sx: i32, sy: i32, sw: i32, sh: i32, bgra: &[u8]) {
    unsafe {
        let bmi = BITMAPINFO {
            bmiHeader: BITMAPINFOHEADER {
                biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                biWidth: src_w,
                biHeight: -src_h,
                biPlanes: 1,
                biBitCount: 32,
                biCompression: BI_RGB.0,
                biSizeImage: (src_w * src_h * 4) as u32,
                ..Default::default()
            },
            ..Default::default()
        };
        StretchDIBits(
            dc,
            dst.x,
            dst.y,
            dst.w,
            dst.h,
            sx,
            sy,
            sw,
            sh,
            Some(bgra.as_ptr() as *const c_void),
            &bmi,
            DIB_RGB_COLORS,
            SRCCOPY,
        );
    }
}

/// クリップ領域を設定・解除するRAIIガード
pub struct ClipRect {
    dc: HDC,
    rgn: windows::Win32::Graphics::Gdi::HRGN,
}

impl ClipRect {
    pub fn new(dc: HDC, r: Rect) -> Self {
        unsafe {
            let rgn = CreateRectRgn(r.x, r.y, r.x + r.w, r.y + r.h);
            SelectClipRgn(dc, Some(rgn));
            Self { dc, rgn }
        }
    }
}

impl Drop for ClipRect {
    fn drop(&mut self) {
        unsafe {
            SelectClipRgn(self.dc, None);
            let _ = DeleteObject(self.rgn.into());
        }
    }
}

// --- 壁紙の貼り付け（Windows 11 24H2/26H2 + Windows 10対応） ---

struct WorkerSearch {
    target_workerw: HWND,
}

unsafe extern "system" fn enum_workerw_proc(top_hwnd: HWND, lparam: LPARAM) -> BOOL {
    let search = unsafe { &mut *(lparam.0 as *mut WorkerSearch) };
    let def_w = wide_null("SHELLDLL_DefView");
    let worker_w = wide_null("WorkerW");
    let defview = unsafe { FindWindowExW(Some(top_hwnd), None, PCWSTR(def_w.as_ptr()), PCWSTR::null()) };
    if let Ok(dv) = defview && !dv.is_invalid() {
        if let Ok(next) = unsafe { FindWindowExW(None, Some(top_hwnd), PCWSTR(worker_w.as_ptr()), PCWSTR::null()) } && !next.is_invalid() {
            search.target_workerw = next;
            return BOOL(0);
        }
    }
    BOOL(1)
}

pub fn find_workerw() -> Option<HWND> {
    let progman_w = wide_null("Progman");
    let worker_w = wide_null("WorkerW");
    let mut progman = HWND::default();
    for _ in 0..5 {
        if let Ok(h) = unsafe { FindWindowW(PCWSTR(progman_w.as_ptr()), PCWSTR::null()) } && !h.is_invalid() {
            progman = h;
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(80));
    }
    if progman.is_invalid() {
        return None;
    }

    let mut res = 0usize;
    unsafe {
        let _ = SendMessageTimeoutW(progman, 0x052C, WPARAM(0xD), LPARAM(0), SMTO_NORMAL, 1000, Some(&mut res));
        let _ = SendMessageTimeoutW(progman, 0x052C, WPARAM(0xD), LPARAM(1), SMTO_NORMAL, 1000, Some(&mut res));
    }

    for _ in 0..5 {
        if let Ok(w) = unsafe { FindWindowExW(Some(progman), None, PCWSTR(worker_w.as_ptr()), PCWSTR::null()) } && !w.is_invalid() {
            return Some(w);
        }
        std::thread::sleep(std::time::Duration::from_millis(40));
    }

    let mut search = WorkerSearch { target_workerw: HWND::default() };
    unsafe {
        let _ = EnumWindows(Some(enum_workerw_proc), LPARAM(&mut search as *mut _ as isize));
    }
    if !search.target_workerw.is_invalid() {
        return Some(search.target_workerw);
    }
    Some(progman)
}

pub fn attach_wallpaper(hwnd: HWND, x: i32, y: i32, w: i32, h: i32) {
    let Some(host) = find_workerw() else { return };
    let progman_w = wide_null("Progman");
    let defview_w = wide_null("SHELLDLL_DefView");
    let Ok(progman) = (unsafe { FindWindowW(PCWSTR(progman_w.as_ptr()), PCWSTR::null()) }) else { return };
    let Ok(defview) = (unsafe { FindWindowExW(Some(progman), None, PCWSTR(defview_w.as_ptr()), PCWSTR::null()) }) else { return };
    if progman.is_invalid() || defview.is_invalid() {
        return;
    }
    unsafe {
        let style = GetWindowLongPtrW(hwnd, GWL_STYLE);
        let new_style = (style & !(WS_POPUP.0 as isize) & !(WS_CAPTION.0 as isize) & !(WS_THICKFRAME.0 as isize))
            | (WS_CHILD.0 as isize)
            | (WS_VISIBLE.0 as isize)
            | 0x0400_0000;
        SetWindowLongPtrW(hwnd, GWL_STYLE, new_style);
        let _ = SetParent(hwnd, Some(progman));
        let ex_style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex_style | (WS_EX_LAYERED.0 as isize));
        let _ = SetLayeredWindowAttributes(hwnd, COLORREF(0), 255, LWA_ALPHA);
        let _ = SetWindowPos(hwnd, Some(defview), x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
        if host != progman {
            let _ = SetWindowPos(host, Some(hwnd), 0, 0, 0, 0, SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
        }
        let _ = InvalidateRect(Some(hwnd), None, true);
    }
}

pub fn keep_below_icons(hwnd: HWND) {
    let progman_w = wide_null("Progman");
    let defview_w = wide_null("SHELLDLL_DefView");
    let worker_w = wide_null("WorkerW");
    unsafe {
        let Ok(progman) = FindWindowW(PCWSTR(progman_w.as_ptr()), PCWSTR::null()) else { return };
        let Ok(defview) = FindWindowExW(Some(progman), None, PCWSTR(defview_w.as_ptr()), PCWSTR::null()) else { return };
        if progman.is_invalid() || defview.is_invalid() {
            return;
        }
        if GetWindow(defview, GW_HWNDNEXT) == Ok(hwnd) {
            return;
        }
        let _ = SetWindowPos(hwnd, Some(defview), 0, 0, 0, 0, SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
        if let Ok(workerw) = FindWindowExW(Some(progman), None, PCWSTR(worker_w.as_ptr()), PCWSTR::null()) && !workerw.is_invalid() {
            let _ = SetWindowPos(workerw, Some(hwnd), 0, 0, 0, 0, SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
        }
    }
}

pub fn show_window(hwnd: HWND, visible: bool) {
    unsafe {
        let _ = ShowWindow(hwnd, if visible { SW_SHOW } else { SW_HIDE });
    }
}

// --- タスクトレイ ---

fn app_icon() -> HICON {
    unsafe {
        let hmod = GetModuleHandleW(PCWSTR::null()).unwrap_or_default();
        if let Ok(ic) = LoadIconW(Some(hmod.into()), PCWSTR(1 as *const u16)) && !ic.is_invalid() {
            return ic;
        }
        let ico = exe_dir().join("assets").join("icon.ico");
        if ico.exists() {
            let w = wide_null(&ico.to_string_lossy());
            if let Ok(h) = LoadImageW(None, PCWSTR(w.as_ptr()), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE) {
                return HICON(h.0);
            }
        }
        LoadIconW(None, windows::Win32::UI::WindowsAndMessaging::IDI_APPLICATION).unwrap_or_default()
    }
}

fn build_notify_icon_data(hwnd: HWND, tip: &str) -> NOTIFYICONDATAW {
    let mut nid = NOTIFYICONDATAW {
        cbSize: std::mem::size_of::<NOTIFYICONDATAW>() as u32,
        hWnd: hwnd,
        uID: 1,
        uFlags: NIF_MESSAGE | NIF_ICON | NIF_TIP,
        uCallbackMessage: WM_TRAYICON,
        hIcon: app_icon(),
        ..Default::default()
    };
    let wide: Vec<u16> = tip.encode_utf16().take(nid.szTip.len() - 1).collect();
    nid.szTip[..wide.len()].copy_from_slice(&wide);
    nid
}

pub fn add_tray_icon(hwnd: HWND, tip: &str) {
    let nid = build_notify_icon_data(hwnd, tip);
    unsafe {
        let _ = Shell_NotifyIconW(NIM_ADD, &nid);
    }
}

pub fn remove_tray_icon(hwnd: HWND) {
    let nid = build_notify_icon_data(hwnd, "");
    unsafe {
        let _ = Shell_NotifyIconW(NIM_DELETE, &nid);
    }
}

pub fn show_tray_menu(hwnd: HWND, open_label: &str, toggle_label: &str, exit_label: &str) -> u32 {
    unsafe {
        let Ok(menu) = CreatePopupMenu() else { return 0 };
        let w_open = wide_null(open_label);
        let w_toggle = wide_null(toggle_label);
        let w_exit = wide_null(exit_label);
        let _ = AppendMenuW(menu, MF_STRING, 101, PCWSTR(w_open.as_ptr()));
        let _ = AppendMenuW(menu, MF_SEPARATOR, 0, PCWSTR::null());
        let _ = AppendMenuW(menu, MF_STRING, 102, PCWSTR(w_toggle.as_ptr()));
        let _ = AppendMenuW(menu, MF_SEPARATOR, 0, PCWSTR::null());
        let _ = AppendMenuW(menu, MF_STRING, 103, PCWSTR(w_exit.as_ptr()));

        let mut pt = POINT::default();
        let _ = GetCursorPos(&mut pt);
        let _ = SetForegroundWindow(hwnd);
        let cmd = TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_RETURNCMD, pt.x, pt.y, None, hwnd, None);
        let _ = DestroyMenu(menu);
        cmd.0 as u32
    }
}

// --- スタートアップショートカット（COM IShellLinkW） ---

fn startup_shortcut_path() -> Option<PathBuf> {
    unsafe {
        let mut buf = [0u16; MAX_PATH as usize];
        if SHGetSpecialFolderPathW(None, &mut buf, CSIDL_STARTUP as i32, false).as_bool() {
            let len = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
            let dir = PathBuf::from(String::from_utf16_lossy(&buf[..len]));
            return Some(dir.join("Pixel Wave.lnk"));
        }
    }
    None
}

pub fn create_startup_shortcut(target: &Path, args: &str) -> bool {
    let Some(lnk_path) = startup_shortcut_path() else { return false };
    unsafe {
        let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
        let Ok(link): Result<IShellLinkW, _> = CoCreateInstance(&ShellLink, None, CLSCTX_INPROC_SERVER) else {
            return false;
        };
        let target_w = wide_null(&target.to_string_lossy());
        let args_w = wide_null(args);
        let work_w = wide_null(&target.parent().unwrap_or(Path::new(".")).to_string_lossy());
        let _ = link.SetPath(PCWSTR(target_w.as_ptr()));
        let _ = link.SetArguments(PCWSTR(args_w.as_ptr()));
        let _ = link.SetWorkingDirectory(PCWSTR(work_w.as_ptr()));
        let Ok(pf): Result<IPersistFile, _> = link.cast() else { return false };
        let lnk_w = wide_null(&lnk_path.to_string_lossy());
        pf.Save(PCWSTR(lnk_w.as_ptr()), true).is_ok()
    }
}

pub fn delete_startup_shortcut() {
    if let Some(p) = startup_shortcut_path() {
        let _ = fs::remove_file(p);
    }
}

// --- スクリーンセーバー（レジストリ） ---

pub fn screensaver_path() -> Option<PathBuf> {
    let exe = exe_path();
    let dir = exe.parent()?;
    let scr = dir.join("PixelWave.scr");
    if !scr.exists() {
        let _ = fs::copy(&exe, &scr);
    }
    scr.exists().then_some(scr)
}

fn reg_read_string(subkey: &str, name: &str) -> Option<String> {
    unsafe {
        let sub_w = wide_null(subkey);
        let name_w = wide_null(name);
        let mut hkey = Default::default();
        if RegOpenKeyExW(HKEY_CURRENT_USER, PCWSTR(sub_w.as_ptr()), None, KEY_READ, &mut hkey).is_err() {
            return None;
        }
        let mut buf = [0u16; 512];
        let mut byte_len = (buf.len() * 2) as u32;
        let ok = RegQueryValueExW(
            hkey,
            PCWSTR(name_w.as_ptr()),
            None,
            None,
            Some(buf.as_mut_ptr() as *mut u8),
            Some(&mut byte_len),
        )
        .is_ok();
        let _ = windows::Win32::System::Registry::RegCloseKey(hkey);
        if !ok || byte_len < 2 {
            return None;
        }
        let u16_len = (byte_len as usize / 2).min(buf.len());
        let s = String::from_utf16_lossy(&buf[..u16_len]);
        Some(s.trim_end_matches('\0').to_string())
    }
}

fn reg_write_string(subkey: &str, name: &str, val: &str) -> bool {
    unsafe {
        let sub_w = wide_null(subkey);
        let name_w = wide_null(name);
        let val_w = wide_null(val);
        let mut hkey = Default::default();
        if RegCreateKeyExW(HKEY_CURRENT_USER, PCWSTR(sub_w.as_ptr()), None, None, Default::default(), KEY_WRITE, None, &mut hkey, None).is_err() {
            return false;
        }
        let bytes = std::slice::from_raw_parts(val_w.as_ptr() as *const u8, val_w.len() * 2);
        let ok = RegSetValueExW(hkey, PCWSTR(name_w.as_ptr()), None, REG_SZ, Some(bytes)).is_ok();
        let _ = windows::Win32::System::Registry::RegCloseKey(hkey);
        ok
    }
}

pub fn screensaver_active() -> bool {
    let sub = "Control Panel\\Desktop";
    let Some(scr) = reg_read_string(sub, "SCRNSAVE.EXE") else { return false };
    let active = reg_read_string(sub, "ScreenSaveActive").unwrap_or_default();
    active == "1"
        && Path::new(&scr)
            .file_name()
            .and_then(|n| n.to_str())
            .is_some_and(|n| n.eq_ignore_ascii_case("pixelwave.scr"))
}

pub fn enable_screensaver() -> bool {
    let Some(scr) = screensaver_path() else { return false };
    let sub = "Control Panel\\Desktop";
    reg_write_string(sub, "SCRNSAVE.EXE", &scr.to_string_lossy());
    reg_write_string(sub, "ScreenSaveActive", "1");
    if reg_read_string(sub, "ScreenSaveTimeOut").is_none() {
        reg_write_string(sub, "ScreenSaveTimeOut", "600");
    }
    unsafe {
        let _ = SystemParametersInfoW(SPI_SETSCREENSAVEACTIVE, 1, None, SPIF_SENDCHANGE);
    }
    true
}

pub fn disable_screensaver() -> bool {
    let sub = "Control Panel\\Desktop";
    reg_write_string(sub, "ScreenSaveActive", "0");
    unsafe {
        let _ = SystemParametersInfoW(SPI_SETSCREENSAVEACTIVE, 0, None, SPIF_SENDCHANGE);
    }
    true
}

// --- ダイアログ ---

pub fn open_image_dialog(hwnd: HWND, filter_label: &str) -> Vec<PathBuf> {
    let mut filter = wide_null(filter_label);
    filter.pop();
    filter.push(0);
    filter.extend(wide_null("*.jpg;*.jpeg;*.png"));
    filter.push(0);

    let mut file_buf = vec![0u16; 32768];
    let mut ofn = OPENFILENAMEW {
        lStructSize: std::mem::size_of::<OPENFILENAMEW>() as u32,
        hwndOwner: hwnd,
        lpstrFilter: PCWSTR(filter.as_ptr()),
        lpstrFile: PWSTR(file_buf.as_mut_ptr()),
        nMaxFile: file_buf.len() as u32,
        Flags: OFN_ALLOWMULTISELECT | OFN_FILEMUSTEXIST | OFN_EXPLORER,
        ..Default::default()
    };
    if unsafe { !GetOpenFileNameW(&mut ofn).as_bool() } {
        return Vec::new();
    }
    let mut parts = Vec::new();
    let mut start = 0;
    for i in 0..file_buf.len() {
        if file_buf[i] == 0 {
            if i == start {
                break;
            }
            parts.push(String::from_utf16_lossy(&file_buf[start..i]));
            start = i + 1;
        }
    }
    if parts.len() <= 1 {
        parts.into_iter().map(PathBuf::from).collect()
    } else {
        let dir = PathBuf::from(&parts[0]);
        parts[1..].iter().map(|name| dir.join(name)).collect()
    }
}

pub fn choose_color_dialog(hwnd: HWND) -> Option<Rgb> {
    let mut cust = [COLORREF(0x00FF_FFFF); 16];
    let mut cc = CHOOSECOLORW {
        lStructSize: std::mem::size_of::<CHOOSECOLORW>() as u32,
        hwndOwner: hwnd,
        lpCustColors: cust.as_mut_ptr(),
        Flags: CC_RGBINIT | CC_FULLOPEN,
        ..Default::default()
    };
    if unsafe { !ChooseColorW(&mut cc).as_bool() } {
        return None;
    }
    let c = cc.rgbResult.0;
    Some([(c & 0xFF) as u8, ((c >> 8) & 0xFF) as u8, ((c >> 16) & 0xFF) as u8])
}

/// ウィンドウメッセージ処理用の共通ユーティリティ（lparamから符号付き座標を取り出す）
pub fn mouse_pos(lparam: LPARAM) -> (i32, i32) {
    let v = lparam.0 as u32;
    let x = (v & 0xFFFF) as i16 as i32;
    let y = ((v >> 16) & 0xFFFF) as i16 as i32;
    (x, y)
}

pub fn wheel_delta(wparam: WPARAM) -> i32 {
    ((wparam.0 >> 16) & 0xFFFF) as i16 as i32
}
