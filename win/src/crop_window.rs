//! 切り取り範囲の調整モーダルウィンドウ

use std::path::Path;

use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::Graphics::Gdi::{BeginPaint, DeleteObject, EndPaint, HFONT, PAINTSTRUCT};
use windows::Win32::UI::Input::KeyboardAndMouse::{EnableWindow, VK_ESCAPE, VK_RETURN};
use windows::Win32::UI::WindowsAndMessaging::{
    DestroyWindow, WM_DESTROY, WM_ERASEBKGND, WM_KEYDOWN, WM_LBUTTONDOWN,
    WM_LBUTTONUP, WM_MOUSEMOVE, WM_PAINT, WS_POPUP, WS_VISIBLE,
};

use crate::dotart::{Crop, Rgb};
use crate::i18n::{self, Lang};
use crate::platform::{
    self, BackBuffer, ClipRect, blit_bgra_rect, draw_text, draw_text_top, make_font, mouse_pos,
    work_area,
};
use crate::settings_layout::Rect;
use crate::wic;
use crate::window::{self, WindowHandler};

const HANDLE_SIZE: i32 = 10;
const BG: Rgb = [24, 24, 28];
const FOOTER_BG: Rgb = [32, 32, 38];
const FG: Rgb = [240, 240, 245];
const SUB: Rgb = [160, 160, 170];
const BORDER: Rgb = [60, 60, 70];
const BTN_BG: Rgb = [45, 45, 55];
const BTN_HOVER: Rgb = [60, 60, 75];
const PRIMARY_BG: Rgb = [40, 120, 220];
const PRIMARY_HOVER: Rgb = [50, 140, 245];
const CROP_BORDER: Rgb = [64, 160, 255];

#[derive(Clone, Copy, PartialEq, Eq)]
enum DragMode {
    Move,
    TopLeft,
    TopRight,
    BottomLeft,
    BottomRight,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum HoverBtn {
    Reset,
    Cancel,
    Confirm,
}

#[derive(Clone, Copy)]
struct CropNorm {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
}

pub struct CropWindow {
    hwnd: HWND,
    lang: Lang,
    screen_aspect: f64,
    width: i32,
    height: i32,
    canvas: Rect,
    thumb_w: i32,
    thumb_h: i32,
    img_x: i32,
    img_y: i32,
    img_aspect: f64,
    bright_bgra: Vec<u8>,
    dark_bgra: Vec<u8>,
    crop: CropNorm,
    dragging: Option<DragMode>,
    drag_start_mouse: (i32, i32),
    drag_start_crop: CropNorm,
    hover: Option<HoverBtn>,
    rect_reset: Rect,
    rect_cancel: Rect,
    rect_confirm: Rect,
    buffer: Option<BackBuffer>,
    font_title: HFONT,
    font_body: HFONT,
    font_btn: HFONT,
    result: Option<Crop>,
}

impl CropWindow {
    pub fn run_modal(
        image_path: &Path,
        initial_crop: Option<&Crop>,
        parent_hwnd: HWND,
        screen_aspect: f64,
        lang: Lang,
    ) -> Option<Crop> {
        let (_, _, work_w, work_h) = work_area();
        let win_w = 980.min((work_w - 40).max(320));
        let win_h = 760.min((work_h - 40).max(320));
        let x = (work_w - win_w) / 2;
        let y = (work_h - win_h) / 2;

        let canvas = Rect::new(24, 60, win_w - 48, win_h - 140);
        let mut bright_bgra = Vec::new();
        let mut dark_bgra = Vec::new();
        let mut thumb_w = 0i32;
        let mut thumb_h = 0i32;
        let mut img_aspect = 1.0;

        if let Some(img) = wic::decode_thumb_bgra(image_path, canvas.w as u32, canvas.h as u32) {
            thumb_w = img.w as i32;
            thumb_h = img.h as i32;
            img_aspect = thumb_w as f64 / thumb_h.max(1) as f64;
            dark_bgra = img
                .bgra
                .chunks_exact(4)
                .flat_map(|px| [
                    (px[0] as f64 * 0.35) as u8,
                    (px[1] as f64 * 0.35) as u8,
                    (px[2] as f64 * 0.35) as u8,
                    px[3],
                ])
                .collect();
            bright_bgra = img.bgra;
        }

        let crop = initial_crop_norm(initial_crop, img_aspect, screen_aspect);
        let btn_w = 130;
        let btn_h = 36;
        let btn_y = win_h - 70 + 17;

        let mut win = Box::new(Self {
            hwnd: HWND::default(),
            lang,
            screen_aspect,
            width: win_w,
            height: win_h,
            canvas,
            thumb_w,
            thumb_h,
            img_x: canvas.x + (canvas.w - thumb_w) / 2,
            img_y: canvas.y + (canvas.h - thumb_h) / 2,
            img_aspect,
            bright_bgra,
            dark_bgra,
            crop,
            dragging: None,
            drag_start_mouse: (0, 0),
            drag_start_crop: crop,
            hover: None,
            rect_reset: Rect::new(24, btn_y, btn_w, btn_h),
            rect_cancel: Rect::new(win_w - 24 - btn_w * 2 - 12, btn_y, btn_w, btn_h),
            rect_confirm: Rect::new(win_w - 24 - btn_w, btn_y, btn_w, btn_h),
            buffer: None,
            font_title: make_font(18, true),
            font_body: make_font(14, false),
            font_btn: make_font(14, true),
            result: None,
        });

        let title = i18n::crop_window_title(lang, screen_aspect);
        let hwnd = window::register_and_create(
            "PixelWaveCropWindowClass",
            &title,
            x,
            y,
            win_w,
            win_h,
            WS_POPUP | WS_VISIBLE,
            Default::default(),
            Some(parent_hwnd),
            &mut *win,
        );
        win.hwnd = hwnd;
        win.buffer = Some(BackBuffer::new(hwnd, win_w, win_h));
        win.redraw_all();
        platform::invalidate_rect(hwnd, None);

        unsafe {
            let _ = EnableWindow(parent_hwnd, false);
        }
        window::run_modal_loop(hwnd);
        unsafe {
            let _ = EnableWindow(parent_hwnd, true);
        }
        platform::bring_to_front(parent_hwnd);
        win.result
    }

    fn crop_pixel_rect(&self) -> Rect {
        if self.thumb_w <= 0 || self.thumb_h <= 0 {
            return Rect::new(0, 0, 0, 0);
        }
        Rect::new(
            self.img_x + (self.thumb_w as f64 * self.crop.x).round() as i32,
            self.img_y + (self.thumb_h as f64 * self.crop.y).round() as i32,
            (self.thumb_w as f64 * self.crop.w).round() as i32,
            (self.thumb_h as f64 * self.crop.h).round() as i32,
        )
    }

    fn redraw_all(&mut self) {
        let Some(buf) = self.buffer.as_mut() else { return };
        buf.fill_all(BG);
        let st = i18n::strings(self.lang);

        // ヘッダー
        draw_text_top(buf.dc, st.crop_header, Rect::new(self.canvas.x, 18, 300, 26), self.font_title, FG);
        let sub = i18n::crop_sub(self.lang, self.screen_aspect);
        draw_text_top(
            buf.dc,
            &sub,
            Rect::new(self.canvas.x + 220, 22, self.width - self.canvas.x - 240, 22),
            self.font_body,
            SUB,
        );

        // キャンバス
        if self.thumb_w > 0 && self.thumb_h > 0 {
            let img_rect = Rect::new(self.img_x, self.img_y, self.thumb_w, self.thumb_h);
            blit_bgra_rect(
                buf.dc,
                img_rect,
                self.thumb_w,
                self.thumb_h,
                0,
                0,
                self.thumb_w,
                self.thumb_h,
                &self.dark_bgra,
            );
            let cr = Rect::new(
                self.img_x + (self.thumb_w as f64 * self.crop.x).round() as i32,
                self.img_y + (self.thumb_h as f64 * self.crop.y).round() as i32,
                (self.thumb_w as f64 * self.crop.w).round() as i32,
                (self.thumb_h as f64 * self.crop.h).round() as i32,
            );
            {
                let _clip = ClipRect::new(buf.dc, cr);
                blit_bgra_rect(
                    buf.dc,
                    img_rect,
                    self.thumb_w,
                    self.thumb_h,
                    0,
                    0,
                    self.thumb_w,
                    self.thumb_h,
                    &self.bright_bgra,
                );
            }
            draw_outline(buf, cr, CROP_BORDER, 2);
            let half = HANDLE_SIZE / 2;
            for (hx, hy) in [
                (cr.x - half, cr.y - half),
                (cr.x + cr.w - half, cr.y - half),
                (cr.x - half, cr.y + cr.h - half),
                (cr.x + cr.w - half, cr.y + cr.h - half),
            ] {
                let hr = Rect::new(hx, hy, HANDLE_SIZE, HANDLE_SIZE);
                buf.fill_rect(hr, [255, 255, 255]);
                draw_outline(buf, hr, BORDER, 1);
            }
        }

        // フッター
        let fy = self.height - 70;
        buf.fill_rect(Rect::new(0, fy, self.width, 70), FOOTER_BG);
        buf.fill_rect(Rect::new(0, fy, self.width, 1), BORDER);

        let buttons = [
            (self.rect_reset, st.crop_reset, self.hover == Some(HoverBtn::Reset), false),
            (self.rect_cancel, st.crop_cancel, self.hover == Some(HoverBtn::Cancel), false),
            (self.rect_confirm, st.crop_confirm, self.hover == Some(HoverBtn::Confirm), true),
        ];
        for (r, label, hov, primary) in buttons {
            let bg = match (primary, hov) {
                (true, true) => PRIMARY_HOVER,
                (true, false) => PRIMARY_BG,
                (false, true) => BTN_HOVER,
                (false, false) => BTN_BG,
            };
            let fg = if primary { [255, 255, 255] } else { FG };
            buf.fill_rect(r, bg);
            draw_outline(buf, r, BORDER, 1);
            draw_text(buf.dc, label, r, self.font_btn, fg, true);
        }
    }

    fn hit_handle(&self, mx: i32, my: i32) -> Option<DragMode> {
        let cr = self.crop_pixel_rect();
        let h = HANDLE_SIZE;
        if (mx - cr.x).abs() <= h && (my - cr.y).abs() <= h {
            return Some(DragMode::TopLeft);
        }
        if (mx - (cr.x + cr.w)).abs() <= h && (my - cr.y).abs() <= h {
            return Some(DragMode::TopRight);
        }
        if (mx - cr.x).abs() <= h && (my - (cr.y + cr.h)).abs() <= h {
            return Some(DragMode::BottomLeft);
        }
        if (mx - (cr.x + cr.w)).abs() <= h && (my - (cr.y + cr.h)).abs() <= h {
            return Some(DragMode::BottomRight);
        }
        if cr.contains(mx, my) {
            return Some(DragMode::Move);
        }
        None
    }

    fn handle_drag(&mut self, mx: i32, my: i32) {
        if self.thumb_w <= 0 || self.thumb_h <= 0 {
            return;
        }
        let Some(mode) = self.dragging else { return };
        let dnx = (mx - self.drag_start_mouse.0) as f64 / self.thumb_w as f64;
        let dny = (my - self.drag_start_mouse.1) as f64 / self.thumb_h as f64;
        let s = self.drag_start_crop;
        let ratio = self.img_aspect / self.screen_aspect;

        match mode {
            DragMode::Move => {
                self.crop.x = (s.x + dnx).clamp(0.0, 1.0 - s.w);
                self.crop.y = (s.y + dny).clamp(0.0, 1.0 - s.h);
            }
            DragMode::BottomRight => {
                let mut nw = (s.w + dnx).clamp(0.08, 1.0 - s.x);
                let mut nh = nw * ratio;
                if s.y + nh > 1.0 {
                    nh = 1.0 - s.y;
                    nw = nh / ratio;
                }
                self.crop.w = nw;
                self.crop.h = nh;
            }
            DragMode::BottomLeft => {
                let mut nw = (s.w - dnx).clamp(0.08, s.x + s.w);
                let mut nh = nw * ratio;
                if s.y + nh > 1.0 {
                    nh = 1.0 - s.y;
                    nw = nh / ratio;
                }
                self.crop.x = s.x + s.w - nw;
                self.crop.w = nw;
                self.crop.h = nh;
            }
            DragMode::TopRight => {
                let mut nw = (s.w + dnx).clamp(0.08, 1.0 - s.x);
                let mut nh = nw * ratio;
                if s.y + s.h - nh < 0.0 {
                    nh = s.y + s.h;
                    nw = nh / ratio;
                }
                self.crop.y = s.y + s.h - nh;
                self.crop.w = nw;
                self.crop.h = nh;
            }
            DragMode::TopLeft => {
                let mut nw = (s.w - dnx).clamp(0.08, s.x + s.w);
                let mut nh = nw * ratio;
                if s.y + s.h - nh < 0.0 {
                    nh = s.y + s.h;
                    nw = nh / ratio;
                }
                self.crop.x = s.x + s.w - nw;
                self.crop.y = s.y + s.h - nh;
                self.crop.w = nw;
                self.crop.h = nh;
            }
        }
        self.crop.w = self.crop.w.clamp(0.05, 1.0);
        self.crop.h = self.crop.h.clamp(0.05, 1.0);
        self.crop.x = self.crop.x.clamp(0.0, 1.0 - self.crop.w);
        self.crop.y = self.crop.y.clamp(0.0, 1.0 - self.crop.h);
    }

    fn confirm(&mut self) {
        self.result = Some(Crop::rect(self.crop.x, self.crop.y, self.crop.w, self.crop.h));
        unsafe {
            let _ = DestroyWindow(self.hwnd);
        }
    }

    fn cancel(&mut self) {
        self.result = None;
        unsafe {
            let _ = DestroyWindow(self.hwnd);
        }
    }
}

impl WindowHandler for CropWindow {
    fn handle_message(&mut self, hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
        match msg {
            WM_PAINT => {
                let mut ps = PAINTSTRUCT::default();
                let hdc = unsafe { BeginPaint(hwnd, &mut ps) };
                if let Some(buf) = &self.buffer {
                    buf.blit_to(hdc);
                }
                unsafe { let _ = EndPaint(hwnd, &ps); }
                Some(LRESULT(0))
            }
            WM_ERASEBKGND => Some(LRESULT(1)),
            WM_LBUTTONDOWN => {
                let (mx, my) = mouse_pos(lparam);
                if self.rect_confirm.contains(mx, my) {
                    self.confirm();
                } else if self.rect_cancel.contains(mx, my) {
                    self.cancel();
                } else if self.rect_reset.contains(mx, my) {
                    self.crop = initial_crop_norm(None, self.img_aspect, self.screen_aspect);
                    self.redraw_all();
                    platform::invalidate_rect(hwnd, None);
                } else if let Some(mode) = self.hit_handle(mx, my) {
                    self.dragging = Some(mode);
                    self.drag_start_mouse = (mx, my);
                    self.drag_start_crop = self.crop;
                }
                Some(LRESULT(0))
            }
            WM_MOUSEMOVE => {
                let (mx, my) = mouse_pos(lparam);
                if self.dragging.is_some() {
                    self.handle_drag(mx, my);
                    self.redraw_all();
                    platform::invalidate_rect(hwnd, None);
                } else {
                    let next = if self.rect_confirm.contains(mx, my) {
                        Some(HoverBtn::Confirm)
                    } else if self.rect_cancel.contains(mx, my) {
                        Some(HoverBtn::Cancel)
                    } else if self.rect_reset.contains(mx, my) {
                        Some(HoverBtn::Reset)
                    } else {
                        None
                    };
                    if next != self.hover {
                        self.hover = next;
                        self.redraw_all();
                        platform::invalidate_rect(hwnd, None);
                    }
                }
                Some(LRESULT(0))
            }
            WM_LBUTTONUP => {
                self.dragging = None;
                Some(LRESULT(0))
            }
            WM_KEYDOWN => {
                let key = wparam.0 as u16;
                if key == VK_RETURN.0 {
                    self.confirm();
                } else if key == VK_ESCAPE.0 {
                    self.cancel();
                }
                Some(LRESULT(0))
            }
            WM_DESTROY => {
                self.buffer = None;
                unsafe {
                    let _ = DeleteObject(self.font_title.into());
                    let _ = DeleteObject(self.font_body.into());
                    let _ = DeleteObject(self.font_btn.into());
                }
                Some(LRESULT(0))
            }
            _ => None,
        }
    }
}

fn draw_outline(buf: &mut BackBuffer, r: Rect, color: Rgb, thickness: i32) {
    buf.fill_rect(Rect::new(r.x, r.y, r.w, thickness), color);
    buf.fill_rect(Rect::new(r.x, r.y + r.h - thickness, r.w, thickness), color);
    buf.fill_rect(Rect::new(r.x, r.y, thickness, r.h), color);
    buf.fill_rect(Rect::new(r.x + r.w - thickness, r.y, thickness, r.h), color);
}

fn initial_crop_norm(crop: Option<&Crop>, img_aspect: f64, screen_aspect: f64) -> CropNorm {
    if let Some(Crop::Rect { x, y, w, h }) = crop {
        let w = w.clamp(0.05, 1.0);
        let h = h.clamp(0.05, 1.0);
        return CropNorm { x: x.clamp(0.0, 1.0 - w), y: y.clamp(0.0, 1.0 - h), w, h };
    }
    let img_asp = if img_aspect > 0.0 { img_aspect } else { 1.0 };
    let scr_asp = if screen_aspect > 0.0 { screen_aspect } else { 16.0 / 9.0 };
    if img_asp > scr_asp {
        let nw = scr_asp / img_asp;
        CropNorm { x: (1.0 - nw) / 2.0, y: 0.0, w: nw, h: 1.0 }
    } else {
        let nh = img_asp / scr_asp;
        CropNorm { x: 0.0, y: (1.0 - nh) / 2.0, w: 1.0, h: nh }
    }
}
