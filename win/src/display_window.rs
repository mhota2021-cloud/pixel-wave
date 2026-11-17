//! 表示ウィンドウ（壁紙とスクリーンセーバーで共用。DIB裏画面に直接描く）

use std::cell::RefCell;
use std::rc::Rc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::Graphics::Gdi::{BeginPaint, EndPaint, PAINTSTRUCT};
use windows::Win32::UI::WindowsAndMessaging::{
    DestroyWindow, KillTimer, PostQuitMessage, SetTimer, WM_DESTROY, WM_ERASEBKGND, WM_KEYDOWN,
    WM_LBUTTONDOWN, WM_MOUSEMOVE, WM_PAINT, WM_TIMER, WS_EX_LAYERED, WS_EX_TOOLWINDOW,
    WS_EX_TOPMOST, WS_POPUP, WS_VISIBLE,
};

use crate::dotart::{self, Grid, Rgb};
use crate::engine::{self, BACKGROUND, DOT, FILL, WaveClock, WaveEngine};
use crate::loader::{self, PaintingSpec};
use crate::platform::{
    self, BackBuffer, MemBitmap, WM_APP_LOAD_DONE, attach_wallpaper, invalidate_rect,
    keep_below_icons, mouse_pos, primary_screen, render_normal_wave, show_window, virtual_screen,
};
use crate::settings_layout::Rect;
use crate::wic::BgraImage;
use crate::window::{self, WindowHandler};

const TIMER_TICK: usize = 1;
const TIMER_CHECK: usize = 2;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum DisplayMode {
    Wallpaper,
    Screensaver,
}

enum LoadedPayload {
    Grids { gen_id: u64, grids: Vec<Grid> },
    Normals { gen_id: u64, images: Vec<BgraImage> },
}

pub struct DisplayWindow {
    pub hwnd: HWND,
    mode: DisplayMode,
    width: i32,
    height: i32,
    cols: usize,
    rows: usize,
    clock: Arc<WaveClock>,
    engine: WaveEngine,
    normal_bitmaps: Vec<MemBitmap>,
    is_normal: bool,
    hidden: bool,
    paused: bool,
    pause_on_battery: bool,
    last_normal_cycle: Option<usize>,
    normal_pending: bool,
    mouse_origin: Option<(i32, i32)>,
    buffer: Option<BackBuffer>,
    load_gen: Arc<AtomicU64>,
    pending_payload: Arc<Mutex<Option<LoadedPayload>>>,
    on_destroy_quit: bool,
}

impl DisplayWindow {
    pub fn create(
        mode: DisplayMode,
        paintings: Vec<PaintingSpec>,
        cache_dir: std::path::PathBuf,
        pause_on_battery: bool,
        is_normal: bool,
        clock: Arc<WaveClock>,
        on_destroy_quit: bool,
    ) -> Rc<RefCell<Self>> {
        let (x, y, w, h, ex_style) = match mode {
            DisplayMode::Wallpaper => {
                let (vx, vy, vw, vh) = virtual_screen();
                (vx, vy, vw, vh, WS_EX_LAYERED | WS_EX_TOOLWINDOW)
            }
            DisplayMode::Screensaver => {
                let (sw, sh) = primary_screen();
                (0, 0, sw, sh, WS_EX_TOPMOST)
            }
        };
        let cols = ((w as f64 / DOT as f64).ceil() as usize).max(1);
        let rows = ((h as f64 / DOT as f64).ceil() as usize).max(1);

        let load_gen = Arc::new(AtomicU64::new(0));
        let pending_payload = Arc::new(Mutex::new(None));

        let win = Rc::new(RefCell::new(Self {
            hwnd: HWND::default(),
            mode,
            width: w,
            height: h,
            cols,
            rows,
            clock,
            engine: WaveEngine::new(Vec::new(), cols, rows, DOT, FILL),
            normal_bitmaps: Vec::new(),
            is_normal,
            hidden: false,
            paused: false,
            pause_on_battery,
            last_normal_cycle: None,
            normal_pending: true,
            mouse_origin: None,
            buffer: None,
            load_gen,
            pending_payload,
            on_destroy_quit,
        }));

        let style = if mode == DisplayMode::Screensaver {
            WS_POPUP | WS_VISIBLE
        } else {
            WS_POPUP
        };
        let title = if mode == DisplayMode::Wallpaper {
            "PixelWaveWallpaper"
        } else {
            "PixelWaveSaver"
        };

        // Rcの中身を固定アドレスにするためBoxでラッパーをヒープに置く
        let wrapper = Box::into_raw(Box::new(Rc::clone(&win)));
        let hwnd = window::register_and_create(
            "PixelWaveDisplay",
            title,
            x,
            y,
            w,
            h,
            style,
            ex_style,
            None,
            unsafe { &mut *wrapper },
        );

        {
            let mut d = win.borrow_mut();
            d.hwnd = hwnd;
            let mut buf = BackBuffer::new(hwnd, w, h);
            buf.fill_all(BACKGROUND);
            d.buffer = Some(buf);
            d.reload(paintings, cache_dir, is_normal, pause_on_battery);
            d.schedule_tick();
        }
        if mode == DisplayMode::Wallpaper {
            attach_wallpaper(hwnd, 0, 0, w, h);
            unsafe {
                SetTimer(Some(hwnd), TIMER_CHECK, 2000, None);
            }
        }
        win
    }

    pub fn reload(
        &mut self,
        paintings: Vec<PaintingSpec>,
        cache_dir: std::path::PathBuf,
        is_normal: bool,
        pause_on_battery: bool,
    ) {
        self.is_normal = is_normal;
        self.pause_on_battery = pause_on_battery;
        self.normal_bitmaps.clear();
        self.engine.set_grids(Vec::new());
        self.normal_pending = true;
        self.last_normal_cycle = None;
        if let Some(buf) = self.buffer.as_mut() {
            buf.fill_all(BACKGROUND);
        }

        let gen_id = self.load_gen.fetch_add(1, Ordering::SeqCst) + 1;
        let gen_ref = Arc::clone(&self.load_gen);
        let payload_ref = Arc::clone(&self.pending_payload);
        let hwnd_raw = self.hwnd.0 as isize;
        let (cols, rows, w, h) = (self.cols, self.rows, self.width as u32, self.height as u32);

        std::thread::spawn(move || {
            let hwnd = HWND(hwnd_raw as *mut std::ffi::c_void);
            if is_normal {
                let mut images = Vec::with_capacity(paintings.len());
                for (idx, p) in paintings.iter().enumerate() {
                    if gen_ref.load(Ordering::SeqCst) != gen_id {
                        return;
                    }
                    if let Some(img) = crate::wic::decode_cropped_bgra(&p.path, w, h, &p.crop) {
                        images.push(img);
                        if idx == 1 || idx + 1 == paintings.len() {
                            if let Ok(mut guard) = payload_ref.lock() {
                                *guard = Some(LoadedPayload::Normals { gen_id, images: Vec::new() });
                            }
                            if idx + 1 == paintings.len() {
                                if let Ok(mut guard) = payload_ref.lock() {
                                    *guard = Some(LoadedPayload::Normals { gen_id, images });
                                }
                                platform::post_message(hwnd, WM_APP_LOAD_DONE, gen_id as usize, 0);
                                return;
                            }
                        }
                    }
                }
                if gen_ref.load(Ordering::SeqCst) == gen_id && !images.is_empty() {
                    if let Ok(mut guard) = payload_ref.lock() {
                        *guard = Some(LoadedPayload::Normals { gen_id, images });
                    }
                    platform::post_message(hwnd, WM_APP_LOAD_DONE, gen_id as usize, 0);
                }
            } else {
                let mut grids = Vec::with_capacity(paintings.len());
                for (idx, p) in paintings.iter().enumerate() {
                    if gen_ref.load(Ordering::SeqCst) != gen_id {
                        return;
                    }
                    if let Some(g) = loader::load_grid_one(p, cols, rows, &cache_dir) {
                        grids.push(g);
                        // 2枚目が揃ったら即座にUIへ渡してアニメーション開始、最後に全部渡す
                        if (idx == 1 && paintings.len() > 2) || idx + 1 == paintings.len() {
                            if let Ok(mut guard) = payload_ref.lock() {
                                *guard = Some(LoadedPayload::Grids { gen_id, grids: grids.clone() });
                            }
                            platform::post_message(hwnd, WM_APP_LOAD_DONE, gen_id as usize, 0);
                        }
                    }
                }
            }
        });
    }

    pub fn is_hidden(&self) -> bool {
        self.hidden
    }

    pub fn is_paused(&self) -> bool {
        self.paused
    }

    pub fn hide_wallpaper(rc: &Rc<RefCell<Self>>) {
        let hwnd = {
            let Ok(mut b) = rc.try_borrow_mut() else { return };
            if b.mode != DisplayMode::Wallpaper {
                return;
            }
            b.hidden = true;
            unsafe {
                let _ = KillTimer(Some(b.hwnd), TIMER_TICK);
            }
            b.hwnd
        };
        show_window(hwnd, false);
    }

    pub fn show_wallpaper(rc: &Rc<RefCell<Self>>) {
        let hwnd = {
            let Ok(b) = rc.try_borrow() else { return };
            if b.mode != DisplayMode::Wallpaper {
                return;
            }
            b.hwnd
        };
        show_window(hwnd, true);
        keep_below_icons(hwnd);
        if let Ok(mut b) = rc.try_borrow_mut() {
            b.hidden = false;
            b.clock.trigger_soon();
            if b.is_normal {
                b.normal_pending = true;
            } else {
                b.engine.request_full_redraw();
            }
            b.advance_frame();
            b.schedule_tick();
        }
    }

    pub fn toggle_pause(&mut self) {
        self.paused = !self.paused;
        if self.paused {
            unsafe {
                let _ = KillTimer(Some(self.hwnd), TIMER_TICK);
            }
        } else {
            self.advance_frame();
            self.schedule_tick();
        }
    }

    pub fn close(&self) {
        unsafe {
            let _ = DestroyWindow(self.hwnd);
        }
    }

    fn apply_loaded_payload(&mut self) {
        let cur_gen = self.load_gen.load(Ordering::SeqCst);
        let payload = self.pending_payload.lock().ok().and_then(|mut g| g.take());
        let Some(p) = payload else { return };
        match p {
            LoadedPayload::Grids { gen_id, grids } if gen_id == cur_gen => {
                self.engine.set_grids(grids);
                if let Some(buf) = self.buffer.as_mut() {
                    buf.fill_all(BACKGROUND);
                }
                self.advance_frame();
                self.schedule_tick();
            }
            LoadedPayload::Normals { gen_id, images } if gen_id == cur_gen => {
                let dc = self.buffer.as_ref().map(|b| b.dc);
                if let Some(ref_dc) = dc {
                    self.normal_bitmaps = images
                        .iter()
                        .filter_map(|img| MemBitmap::from_bgra(ref_dc, img.w as i32, img.h as i32, &img.bgra))
                        .collect();
                }
                self.normal_pending = true;
                self.advance_frame();
                self.schedule_tick();
            }
            _ => {}
        }
    }

    fn advance_frame(&mut self) {
        if self.hidden || self.paused {
            return;
        }
        let now = self.clock.now_secs();
        let Some(buf) = self.buffer.as_mut() else { return };

        if self.is_normal {
            let count = self.normal_bitmaps.len();
            if count == 0 {
                return;
            }
            let phase = engine::phase_at(now, count);
            let needs = self.normal_pending
                || phase.progress.is_some()
                || self.last_normal_cycle != Some(phase.cycle);
            if !needs {
                return;
            }
            self.last_normal_cycle = Some(phase.cycle);
            self.normal_pending = false;
            match phase.progress {
                None => {
                    let from = &self.normal_bitmaps[phase.from_idx];
                    unsafe {
                        let _ = windows::Win32::Graphics::Gdi::BitBlt(
                            buf.dc,
                            0,
                            0,
                            self.width,
                            self.height,
                            Some(from.dc),
                            0,
                            0,
                            windows::Win32::Graphics::Gdi::SRCCOPY,
                        );
                    }
                }
                Some(ease) => {
                    let (cx, cy) = engine::cycle_center(phase.cycle, self.width as f64, self.height as f64);
                    let max_d = dotart::farthest_corner_distance(cx, cy, self.width as f64, self.height as f64);
                    let r = (ease * max_d).round() as i32;
                    render_normal_wave(
                        buf.dc,
                        &self.normal_bitmaps[phase.from_idx],
                        &self.normal_bitmaps[phase.to_idx],
                        0,
                        0,
                        self.width,
                        self.height,
                        cx.round() as i32,
                        cy.round() as i32,
                        r,
                    );
                }
            }
            invalidate_rect(self.hwnd, None);
        } else {
            let dot = self.engine.dot;
            let fill = self.engine.fill;
            let inset = (dot - fill) / 2;
            let dirty = self.engine.advance(now, |col, row, rgb: Rgb| {
                let rx = col as i32 * dot + inset;
                let ry = row as i32 * dot + inset;
                buf.fill_rect(Rect::new(rx, ry, fill, fill), rgb);
            });
            if let Some((dx, dy, dw, dh)) = dirty {
                invalidate_rect(self.hwnd, Some(Rect::new(dx, dy, dw, dh)));
            }
        }
    }

    fn schedule_tick(&self) {
        if self.hidden || self.paused {
            unsafe {
                let _ = KillTimer(Some(self.hwnd), TIMER_TICK);
            }
            return;
        }
        let count = if self.is_normal {
            self.normal_bitmaps.len()
        } else {
            self.engine.grids.len()
        };
        let now = self.clock.now_secs();
        let ms = engine::next_timer_ms(now, count, false);
        unsafe {
            SetTimer(Some(self.hwnd), TIMER_TICK, ms, None);
        }
    }
}

impl WindowHandler for Rc<RefCell<DisplayWindow>> {
    fn handle_message(&mut self, hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
        match msg {
            WM_PAINT => {
                let mut ps = PAINTSTRUCT::default();
                let hdc = unsafe { BeginPaint(hwnd, &mut ps) };
                if let Ok(b) = self.try_borrow()
                    && let Some(buf) = &b.buffer
                {
                    buf.blit_to(hdc);
                }
                unsafe {
                    let _ = EndPaint(hwnd, &ps);
                }
                Some(LRESULT(0))
            }
            WM_ERASEBKGND => Some(LRESULT(1)),
            WM_APP_LOAD_DONE => {
                if let Ok(mut b) = self.try_borrow_mut() {
                    b.apply_loaded_payload();
                }
                Some(LRESULT(0))
            }
            WM_TIMER => {
                if wparam.0 == TIMER_CHECK {
                    let should_check = self
                        .try_borrow()
                        .map(|b| b.mode == DisplayMode::Wallpaper && !b.hidden)
                        .unwrap_or(false);
                    if should_check {
                        keep_below_icons(hwnd);
                    }
                } else if let Ok(mut b) = self.try_borrow_mut() {
                    b.advance_frame();
                    b.schedule_tick();
                }
                Some(LRESULT(0))
            }
            WM_KEYDOWN | WM_LBUTTONDOWN => {
                let is_saver = self.try_borrow().map(|b| b.mode == DisplayMode::Screensaver).unwrap_or(false);
                if is_saver {
                    unsafe {
                        let _ = DestroyWindow(hwnd);
                    }
                }
                Some(LRESULT(0))
            }
            WM_MOUSEMOVE => {
                let should_close = if let Ok(mut b) = self.try_borrow_mut() {
                    if b.mode == DisplayMode::Screensaver {
                        let (x, y) = mouse_pos(lparam);
                        if let Some((ox, oy)) = b.mouse_origin {
                            let dx = x - ox;
                            let dy = y - oy;
                            dx * dx + dy * dy > 25
                        } else {
                            b.mouse_origin = Some((x, y));
                            false
                        }
                    } else {
                        false
                    }
                } else {
                    false
                };
                if should_close {
                    unsafe {
                        let _ = DestroyWindow(hwnd);
                    }
                }
                Some(LRESULT(0))
            }
            WM_DESTROY => {
                let quit = if let Ok(mut b) = self.try_borrow_mut() {
                    b.normal_bitmaps.clear();
                    b.buffer = None;
                    b.on_destroy_quit
                } else {
                    false
                };
                if quit {
                    unsafe { PostQuitMessage(0) };
                }
                Some(LRESULT(0))
            }
            _ => None,
        }
    }
}
