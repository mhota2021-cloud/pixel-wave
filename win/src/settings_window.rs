//! 設定画面（GDI描画、プレビュー、カード一覧、トグルアニメーション、非同期ロード）

use std::cell::RefCell;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::Graphics::Gdi::{BeginPaint, DeleteObject, EndPaint, HFONT, PAINTSTRUCT};
use windows::Win32::UI::WindowsAndMessaging::{
    DestroyWindow, KillTimer, PostQuitMessage, SetTimer, ShowWindow, SW_SHOWNORMAL, WM_CLOSE,
    WM_DESTROY, WM_ERASEBKGND, WM_LBUTTONDOWN, WM_LBUTTONUP, WM_MOUSEMOVE, WM_MOUSEWHEEL,
    WM_PAINT, WM_SIZE, WM_TIMER, WS_OVERLAPPEDWINDOW,
};

use crate::crop_window::CropWindow;
use crate::display_window::{DisplayMode, DisplayWindow};
use crate::dotart::{self, Crop, Grid, Rgb};
use crate::engine::{self, WaveClock, WaveEngine};
use crate::i18n::{self, Lang};
use crate::loader::{self, CreditItem, PaintingSpec, UiItem};
use crate::platform::{
    self, BackBuffer, ClipRect, MemBitmap, WM_APP_LOAD_DONE, WM_APP_OPEN_SETTINGS, WM_TRAYICON,
    add_tray_icon, bring_to_front, choose_color_dialog, client_size, create_startup_shortcut,
    default_lang_code, delete_startup_shortcut, disable_screensaver, draw_border_round_rect,
    draw_text, draw_text_top, draw_toggle_pill, enable_screensaver, exe_path, fill_round_rect,
    invalidate_rect, make_font, mouse_pos, open_image_dialog, primary_screen, remove_tray_icon,
    render_normal_wave, screensaver_active, show_tray_menu, text_width, wheel_delta, work_area,
};
use crate::settings::{AppSettings, UserImage};
use crate::settings_layout::{self, HitTarget, Layout, Rect};
use crate::wic::{self, BgraImage};
use crate::window::{self, WindowHandler};

const TIMER_TICK: usize = 1;
const BG: Rgb = [24, 24, 28];
const SURFACE: Rgb = [40, 40, 47];
const SURFACE_HOVER: Rgb = [56, 56, 65];
const FG: Rgb = [238, 238, 242];
const SUB: Rgb = [178, 178, 190];
const ACCENT: Rgb = [11, 92, 173];
const ACCENT_HOVER: Rgb = [16, 108, 199];
const PREVIEW_BG: Rgb = [20, 20, 24];
const PREVIEW_DOT: i32 = 8;
const PREVIEW_FILL: i32 = 7;

struct Thumb {
    w: i32,
    h: i32,
    bgra: Vec<u8>,
}

enum PreviewPayload {
    Grids { gen_id: u64, grids: Vec<Grid> },
    Normals { gen_id: u64, images: Vec<BgraImage> },
}

/// 1プロセス統合コントローラ（トレイ・壁紙・設定画面の橋渡し）
pub struct AppController {
    pub data_dir: PathBuf,
    pub cache_dir: PathBuf,
    pub paintings_dir: PathBuf,
    pub credits: Vec<CreditItem>,
    pub settings: AppSettings,
    pub clock: Arc<WaveClock>,
    pub tray_hwnd: HWND,
    pub display: Option<Rc<RefCell<DisplayWindow>>>,
    pub settings_win: Option<Rc<RefCell<SettingsWindow>>>,
}

impl AppController {
    pub fn new(
        data_dir: PathBuf,
        cache_dir: PathBuf,
        paintings_dir: PathBuf,
        credits: Vec<CreditItem>,
        settings: AppSettings,
    ) -> Rc<RefCell<Self>> {
        Rc::new(RefCell::new(Self {
            data_dir,
            cache_dir,
            paintings_dir,
            credits,
            settings,
            clock: Arc::new(WaveClock::new()),
            tray_hwnd: HWND::default(),
            display: None,
            settings_win: None,
        }))
    }

    pub fn current_lang(&self) -> Lang {
        let code = self.settings.lang.as_deref().unwrap_or_else(|| default_lang_code());
        Lang::from_code(code)
    }

    pub fn active_paintings(&self) -> Vec<PaintingSpec> {
        let mut list = loader::enabled_paintings(&self.settings, &self.credits, &self.paintings_dir, &self.data_dir);
        if list.is_empty() {
            let ids: Vec<String> = self.credits.iter().map(|c| c.id.clone()).collect();
            let mut tmp = self.settings.clone();
            tmp.enabled = ids;
            list = loader::enabled_paintings(&tmp, &self.credits, &self.paintings_dir, &self.data_dir);
        }
        list
    }

    pub fn ensure_wallpaper_running(rc: &Rc<RefCell<Self>>, show: bool) {
        let (has_display, list, cache_dir, pause_batt, is_normal, clock) = {
            let b = rc.borrow();
            (
                b.display.is_some(),
                b.active_paintings(),
                b.cache_dir.clone(),
                b.settings.pause_on_battery,
                b.settings.is_normal_mode(),
                Arc::clone(&b.clock),
            )
        };
        let existing_disp = rc.borrow().display.as_ref().cloned();
        if !has_display {
            let disp = DisplayWindow::create(
                DisplayMode::Wallpaper,
                list,
                cache_dir,
                pause_batt,
                is_normal,
                clock,
                false,
            );
            if !show {
                DisplayWindow::hide_wallpaper(&disp);
            } else {
                DisplayWindow::show_wallpaper(&disp);
            }
            rc.borrow_mut().display = Some(disp);
        } else if let Some(disp) = existing_disp {
            if show {
                DisplayWindow::show_wallpaper(&disp);
            } else {
                DisplayWindow::hide_wallpaper(&disp);
            }
        }
    }

    pub fn reload_wallpaper(&self) {
        if let Some(disp) = &self.display
            && let Ok(mut d) = disp.try_borrow_mut()
        {
            let list = self.active_paintings();
            d.reload(
                list,
                self.cache_dir.clone(),
                self.settings.is_normal_mode(),
                self.settings.pause_on_battery,
            );
        }
    }

    pub fn apply_autostart(&self) {
        if self.settings.autostart && self.settings.wallpaper {
            create_startup_shortcut(&exe_path(), "--wallpaper");
        } else {
            delete_startup_shortcut();
        }
    }

    pub fn open_settings(rc: &Rc<RefCell<Self>>) {
        let existing_win = rc.borrow().settings_win.as_ref().cloned();
        if let Some(win) = existing_win {
            let hwnd = win.borrow().hwnd;
            bring_to_front(hwnd);
            return;
        }
        let win = SettingsWindow::create(Rc::clone(rc));
        rc.borrow_mut().settings_win = Some(win);
    }

    pub fn shutdown(rc: &Rc<RefCell<Self>>) {
        let (win, disp, tray_hwnd) = {
            let Ok(mut b) = rc.try_borrow_mut() else {
                unsafe { PostQuitMessage(0) };
                return;
            };
            let tray = b.tray_hwnd;
            b.tray_hwnd = HWND::default();
            (b.settings_win.take(), b.display.take(), tray)
        };
        if let Some(w) = win
            && let Ok(wb) = w.try_borrow()
        {
            unsafe { let _ = DestroyWindow(wb.hwnd); }
        }
        if let Some(d) = disp
            && let Ok(db) = d.try_borrow()
        {
            db.close();
        }
        if !tray_hwnd.is_invalid() {
            remove_tray_icon(tray_hwnd);
            unsafe { let _ = DestroyWindow(tray_hwnd); }
        }
        unsafe { PostQuitMessage(0) };
    }
}

/// トレイアイコン・シングルインスタンス通知を受け取る不可視トップレベルウィンドウ
pub struct TrayHost {
    ctrl: Rc<RefCell<AppController>>,
}

impl TrayHost {
    pub fn create(ctrl: Rc<RefCell<AppController>>) -> HWND {
        let host = Box::into_raw(Box::new(Self { ctrl: Rc::clone(&ctrl) }));
        let hwnd = window::register_and_create(
            "PixelWaveTrayHelper",
            "PixelWaveTray",
            0,
            0,
            0,
            0,
            windows::Win32::UI::WindowsAndMessaging::WS_POPUP,
            windows::Win32::UI::WindowsAndMessaging::WS_EX_TOOLWINDOW,
            None,
            unsafe { &mut *host },
        );
        ctrl.borrow_mut().tray_hwnd = hwnd;
        let lang = ctrl.borrow().current_lang();
        add_tray_icon(hwnd, i18n::strings(lang).tray_tooltip);
        hwnd
    }
}

impl WindowHandler for TrayHost {
    fn handle_message(&mut self, hwnd: HWND, msg: u32, _wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
        match msg {
            WM_APP_OPEN_SETTINGS => {
                AppController::open_settings(&self.ctrl);
                Some(LRESULT(0))
            }
            WM_TRAYICON => {
                let code = (lparam.0 as u32) & 0xFFFF;
                if code == 0x0202 || code == 0x0203 {
                    AppController::open_settings(&self.ctrl);
                } else if code == 0x0205 || code == 0x007B {
                    let (lang, hidden, paused) = {
                        let b = self.ctrl.borrow();
                        let hidden = b.display.as_ref().map(|d| d.borrow().is_hidden()).unwrap_or(true);
                        let paused = b.display.as_ref().map(|d| d.borrow().is_paused()).unwrap_or(false);
                        (b.current_lang(), hidden, paused)
                    };
                    let st = i18n::strings(lang);
                    let toggle_label = if hidden {
                        st.tray_show
                    } else if paused {
                        st.tray_resume
                    } else {
                        st.tray_pause
                    };
                    match show_tray_menu(hwnd, st.tray_open_settings, toggle_label, st.tray_exit) {
                        101 => AppController::open_settings(&self.ctrl),
                        102 => {
                            if hidden {
                                {
                                    let mut b = self.ctrl.borrow_mut();
                                    b.settings.wallpaper = true;
                                    let _ = b.settings.save(&b.data_dir);
                                }
                                AppController::ensure_wallpaper_running(&self.ctrl, true);
                                let sw = self.ctrl.borrow().settings_win.as_ref().cloned();
                                if let Some(sw) = sw
                                    && let Ok(mut s) = sw.try_borrow_mut()
                                {
                                    s.sync_from_settings();
                                }
                            } else {
                                let disp = self.ctrl.borrow().display.as_ref().cloned();
                                if let Some(disp) = disp
                                    && let Ok(mut d) = disp.try_borrow_mut()
                                {
                                    d.toggle_pause();
                                }
                            }
                        }
                        103 => {
                            AppController::shutdown(&self.ctrl);
                        }
                        _ => {}
                    }
                }
                Some(LRESULT(0))
            }
            WM_DESTROY => {
                remove_tray_icon(hwnd);
                Some(LRESULT(0))
            }
            _ => None,
        }
    }
}

pub struct SettingsWindow {
    pub hwnd: HWND,
    ctrl: Rc<RefCell<AppController>>,
    width: i32,
    height: i32,
    screen_w: i32,
    screen_h: i32,
    screen_aspect: f64,
    buffer: Option<BackBuffer>,
    font_body: HFONT,
    font_button: HFONT,
    thumbs: HashMap<String, Option<Thumb>>,
    scroll: i32,
    hover: Option<HitTarget>,
    pressed: Option<HitTarget>,
    anim_autostart: f64,
    anim_wallpaper: f64,
    anim_saver: f64,
    last_tick: Instant,
    engine: WaveEngine,
    normal_bitmaps: Vec<MemBitmap>,
    last_normal_cycle: Option<usize>,
    normal_pending: bool,
    preview_cols: usize,
    preview_rows: usize,
    dot_colors: Vec<Option<Rgb>>,
    load_gen: Arc<AtomicU64>,
    pending_payload: Arc<Mutex<Option<PreviewPayload>>>,
}

impl SettingsWindow {
    pub fn create(ctrl: Rc<RefCell<AppController>>) -> Rc<RefCell<Self>> {
        let (wx, wy, work_w, work_h) = work_area();
        let w = 880.min(work_w);
        let h = 780.min(work_h);
        let x = wx + ((work_w - w) / 2).max(0);
        let y = wy + ((work_h - h) / 2).max(0);
        let (sw, sh) = primary_screen();
        let aspect = sw as f64 / sh.max(1) as f64;

        let (autostart, wallpaper) = {
            let b = ctrl.borrow();
            (b.settings.autostart, b.settings.wallpaper)
        };

        let win = Rc::new(RefCell::new(Self {
            hwnd: HWND::default(),
            ctrl: Rc::clone(&ctrl),
            width: w,
            height: h,
            screen_w: sw,
            screen_h: sh,
            screen_aspect: aspect,
            buffer: None,
            font_body: make_font(16, false),
            font_button: make_font(18, false),
            thumbs: HashMap::new(),
            scroll: 0,
            hover: None,
            pressed: None,
            anim_autostart: if autostart { 1.0 } else { 0.0 },
            anim_wallpaper: if wallpaper { 1.0 } else { 0.0 },
            anim_saver: if screensaver_active() { 1.0 } else { 0.0 },
            last_tick: Instant::now(),
            engine: WaveEngine::new(Vec::new(), 1, 1, PREVIEW_DOT, PREVIEW_FILL),
            normal_bitmaps: Vec::new(),
            last_normal_cycle: None,
            normal_pending: true,
            preview_cols: 1,
            preview_rows: 1,
            dot_colors: Vec::new(),
            load_gen: Arc::new(AtomicU64::new(0)),
            pending_payload: Arc::new(Mutex::new(None)),
        }));

        let wrapper = Box::into_raw(Box::new(Rc::clone(&win)));
        let hwnd = window::register_and_create(
            "PixelWaveSettings",
            "Pixel Wave",
            x,
            y,
            w,
            h,
            WS_OVERLAPPEDWINDOW,
            Default::default(),
            None,
            unsafe { &mut *wrapper },
        );

        {
            let mut s = win.borrow_mut();
            s.hwnd = hwnd;
            let (cw, ch) = client_size(hwnd);
            s.width = cw;
            s.height = ch;
            s.buffer = Some(BackBuffer::new(hwnd, cw, ch));
            s.build_preview();
            s.redraw_all();
            s.schedule_tick(false);
        }
        unsafe {
            let _ = ShowWindow(hwnd, SW_SHOWNORMAL);
        }
        bring_to_front(hwnd);
        invalidate_rect(hwnd, None);
        win
    }

    pub fn sync_from_settings(&mut self) {
        self.redraw_all();
        invalidate_rect(self.hwnd, None);
        self.schedule_tick(true);
    }

    fn items(&self) -> Vec<UiItem> {
        let b = self.ctrl.borrow();
        let lang = b.current_lang();
        loader::ui_items(&b.settings, &b.credits, &b.paintings_dir, &b.data_dir, lang)
    }

    fn layout(&self, item_count: usize) -> Layout {
        settings_layout::layout(self.width, self.height, item_count, self.scroll, self.screen_aspect)
    }

    fn build_preview(&mut self) {
        let (list, cache_dir, is_normal) = {
            let b = self.ctrl.borrow();
            (b.active_paintings(), b.cache_dir.clone(), b.settings.is_normal_mode())
        };
        let l = self.layout(self.items().len());
        let ps = l.preview_screen;

        self.normal_bitmaps.clear();
        self.normal_pending = true;
        self.last_normal_cycle = None;

        let cols = ((ps.w as f64 / PREVIEW_DOT as f64).ceil() as usize).max(1);
        let rows = ((ps.h as f64 / PREVIEW_DOT as f64).ceil() as usize).max(1);
        self.preview_cols = cols;
        self.preview_rows = rows;
        self.dot_colors = vec![None; cols * rows];
        self.engine = WaveEngine::new(Vec::new(), cols, rows, PREVIEW_DOT, PREVIEW_FILL);

        let gen_id = self.load_gen.fetch_add(1, Ordering::SeqCst) + 1;
        let gen_ref = Arc::clone(&self.load_gen);
        let payload_ref = Arc::clone(&self.pending_payload);
        let hwnd_raw = self.hwnd.0 as isize;
        let (sw, sh) = (ps.w as u32, ps.h as u32);

        std::thread::spawn(move || {
            let hwnd = HWND(hwnd_raw as *mut std::ffi::c_void);
            if is_normal {
                let mut images = Vec::with_capacity(list.len());
                for (idx, p) in list.iter().enumerate() {
                    if gen_ref.load(Ordering::SeqCst) != gen_id {
                        return;
                    }
                    if let Some(img) = wic::decode_cropped_bgra(&p.path, sw, sh, &p.crop) {
                        images.push(img);
                        if idx + 1 == list.len() {
                            if let Ok(mut guard) = payload_ref.lock() {
                                *guard = Some(PreviewPayload::Normals { gen_id, images });
                            }
                            platform::post_message(hwnd, WM_APP_LOAD_DONE, gen_id as usize, 0);
                            return;
                        }
                    }
                }
                if gen_ref.load(Ordering::SeqCst) == gen_id && !images.is_empty() {
                    if let Ok(mut guard) = payload_ref.lock() {
                        *guard = Some(PreviewPayload::Normals { gen_id, images });
                    }
                    platform::post_message(hwnd, WM_APP_LOAD_DONE, gen_id as usize, 0);
                }
            } else {
                let mut grids = Vec::with_capacity(list.len());
                for (idx, p) in list.iter().enumerate() {
                    if gen_ref.load(Ordering::SeqCst) != gen_id {
                        return;
                    }
                    if let Some(g) = loader::load_grid_one(p, cols, rows, &cache_dir) {
                        grids.push(g);
                        if (idx == 1 && list.len() > 2) || idx + 1 == list.len() {
                            if let Ok(mut guard) = payload_ref.lock() {
                                *guard = Some(PreviewPayload::Grids { gen_id, grids: grids.clone() });
                            }
                            platform::post_message(hwnd, WM_APP_LOAD_DONE, gen_id as usize, 0);
                        }
                    }
                }
            }
        });
    }

    fn apply_loaded_payload(&mut self) {
        let cur_gen = self.load_gen.load(Ordering::SeqCst);
        let payload = self.pending_payload.lock().ok().and_then(|mut g| g.take());
        let Some(p) = payload else { return };
        match p {
            PreviewPayload::Grids { gen_id, grids } if gen_id == cur_gen => {
                self.engine.set_grids(grids);
                self.dot_colors.fill(None);
                self.advance_preview();
                self.redraw_all();
                invalidate_rect(self.hwnd, None);
                self.schedule_tick(false);
            }
            PreviewPayload::Normals { gen_id, images } if gen_id == cur_gen => {
                if let Some(buf) = &self.buffer {
                    self.normal_bitmaps = images
                        .iter()
                        .filter_map(|img| MemBitmap::from_bgra(buf.dc, img.w as i32, img.h as i32, &img.bgra))
                        .collect();
                }
                self.normal_pending = true;
                self.redraw_all();
                invalidate_rect(self.hwnd, None);
                self.schedule_tick(false);
            }
            _ => {}
        }
    }

    fn advance_preview(&mut self) {
        let is_normal = self.ctrl.borrow().settings.is_normal_mode();
        let now = self.ctrl.borrow().clock.now_secs();
        let l = self.layout(self.items().len());
        let ps = l.preview_screen;

        if is_normal {
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
            if let Some(buf) = self.buffer.as_mut() {
                match phase.progress {
                    None => unsafe {
                        let _ = windows::Win32::Graphics::Gdi::BitBlt(
                            buf.dc,
                            ps.x,
                            ps.y,
                            ps.w,
                            ps.h,
                            Some(self.normal_bitmaps[phase.from_idx].dc),
                            0,
                            0,
                            windows::Win32::Graphics::Gdi::SRCCOPY,
                        );
                    },
                    Some(ease) => {
                        let (cx, cy) = engine::cycle_center(phase.cycle, ps.w as f64, ps.h as f64);
                        let max_d = dotart::farthest_corner_distance(cx, cy, ps.w as f64, ps.h as f64);
                        let r = (ease * max_d).round() as i32;
                        render_normal_wave(
                            buf.dc,
                            &self.normal_bitmaps[phase.from_idx],
                            &self.normal_bitmaps[phase.to_idx],
                            ps.x,
                            ps.y,
                            ps.w,
                            ps.h,
                            cx.round() as i32,
                            cy.round() as i32,
                            r,
                        );
                    }
                }
                draw_border_round_rect(buf.dc, ps, 4, [20, 20, 26]);
            }
            invalidate_rect(self.hwnd, Some(l.preview_bezel));
        } else {
            let cols = self.preview_cols;
            let inset = (PREVIEW_DOT - PREVIEW_FILL) / 2;
            let Some(buf) = self.buffer.as_mut() else { return };
            let dirty = self.engine.advance(now, |col, row, rgb| {
                if let Some(slot) = self.dot_colors.get_mut(row * cols + col) {
                    *slot = Some(rgb);
                }
                let dx = col as i32 * PREVIEW_DOT + inset;
                let dy = row as i32 * PREVIEW_DOT + inset;
                if dx + PREVIEW_FILL <= ps.w && dy + PREVIEW_FILL <= ps.h {
                    buf.fill_rect(Rect::new(ps.x + dx, ps.y + dy, PREVIEW_FILL, PREVIEW_FILL), rgb);
                }
            });
            if let Some((dx, dy, dw, dh)) = dirty {
                invalidate_rect(self.hwnd, Some(Rect::new(ps.x + dx, ps.y + dy, dw, dh)));
            }
        }
    }

    fn update_switch_animations(&mut self, dt: f64) -> bool {
        let (auto_t, wall_t, saver_t) = {
            let b = self.ctrl.borrow();
            (
                if b.settings.autostart { 1.0 } else { 0.0 },
                if b.settings.wallpaper { 1.0 } else { 0.0 },
                if screensaver_active() { 1.0 } else { 0.0 },
            )
        };
        let step = dt * 9.0;
        let mut moving = false;
        for (cur, tgt) in [
            (&mut self.anim_autostart, auto_t),
            (&mut self.anim_wallpaper, wall_t),
            (&mut self.anim_saver, saver_t),
        ] {
            let diff = tgt - *cur;
            if diff.abs() <= step {
                if *cur != tgt {
                    *cur = tgt;
                    moving = true;
                }
            } else {
                *cur += if diff > 0.0 { step } else { -step };
                moving = true;
            }
        }
        moving
    }

    fn schedule_tick(&self, anim_moving: bool) {
        let (is_normal, now) = {
            let b = self.ctrl.borrow();
            (b.settings.is_normal_mode(), b.clock.now_secs())
        };
        let count = if is_normal {
            self.normal_bitmaps.len()
        } else {
            self.engine.grids.len()
        };
        let ms = engine::next_timer_ms(now, count, anim_moving);
        unsafe {
            SetTimer(Some(self.hwnd), TIMER_TICK, ms, None);
        }
    }

    fn redraw_all(&mut self) {
        let items = self.items();
        let l = self.layout(items.len());
        let (lang, is_autostart, is_normal, enabled_ids) = {
            let b = self.ctrl.borrow();
            (
                b.current_lang(),
                b.settings.autostart,
                b.settings.is_normal_mode(),
                b.settings.enabled.clone(),
            )
        };
        let st = i18n::strings(lang);

        // 先に全サムネイルをキャッシュ（借用競合を避ける）
        for &(idx, _) in &l.cards {
            if let Some(item) = items.get(idx) {
                self.ensure_thumb(item);
            }
        }

        let now = self.ctrl.borrow().clock.now_secs();
        let Some(buf) = self.buffer.as_mut() else { return };
        buf.fill_all(BG);

        // プレビューベゼルと中身
        let ps = l.preview_screen;
        let pb = l.preview_bezel;
        fill_round_rect(buf.dc, Rect::new(pb.x, pb.y + 3, pb.w, pb.h), 8, [12, 12, 16], [12, 12, 16]);
        fill_round_rect(buf.dc, pb, 8, [36, 36, 44], [68, 68, 82]);
        buf.fill_rect(ps, PREVIEW_BG);
        if is_normal && !self.normal_bitmaps.is_empty() {
            let phase = engine::phase_at(now, self.normal_bitmaps.len());
            match phase.progress {
                None => unsafe {
                    let _ = windows::Win32::Graphics::Gdi::BitBlt(
                        buf.dc,
                        ps.x,
                        ps.y,
                        ps.w,
                        ps.h,
                        Some(self.normal_bitmaps[phase.from_idx].dc),
                        0,
                        0,
                        windows::Win32::Graphics::Gdi::SRCCOPY,
                    );
                },
                Some(ease) => {
                    let (cx, cy) = engine::cycle_center(phase.cycle, ps.w as f64, ps.h as f64);
                    let max_d = dotart::farthest_corner_distance(cx, cy, ps.w as f64, ps.h as f64);
                    let r = (ease * max_d).round() as i32;
                    render_normal_wave(
                        buf.dc,
                        &self.normal_bitmaps[phase.from_idx],
                        &self.normal_bitmaps[phase.to_idx],
                        ps.x,
                        ps.y,
                        ps.w,
                        ps.h,
                        cx.round() as i32,
                        cy.round() as i32,
                        r,
                    );
                }
            }
        } else {
            let inset = (PREVIEW_DOT - PREVIEW_FILL) / 2;
            for (i, slot) in self.dot_colors.iter().enumerate() {
                if let Some(rgb) = slot {
                    let col = (i % self.preview_cols) as i32;
                    let row = (i / self.preview_cols) as i32;
                    let dx = col * PREVIEW_DOT + inset;
                    let dy = row * PREVIEW_DOT + inset;
                    if dx + PREVIEW_FILL <= ps.w && dy + PREVIEW_FILL <= ps.h {
                        buf.fill_rect(Rect::new(ps.x + dx, ps.y + dy, PREVIEW_FILL, PREVIEW_FILL), *rgb);
                    }
                }
            }
        }
        draw_border_round_rect(buf.dc, ps, 4, [20, 20, 26]);

        // 区切り線（設定エリアと絵の一覧の間）
        buf.fill_rect(
            Rect::new(settings_layout::MARGIN, l.divider_y, self.width - settings_layout::MARGIN * 2, 1),
            [52, 52, 62],
        );

        // カード一覧
        {
            let _clip = ClipRect::new(buf.dc, l.grid);
            for &(idx, r) in &l.cards {
                if r.y + r.h <= l.grid.y || r.y >= l.grid.y + l.grid.h {
                    continue;
                }
                if let Some(item) = items.get(idx) {
                    let card_hover = matches!(
                        self.hover,
                        Some(HitTarget::Card(i) | HitTarget::Crop(i) | HitTarget::Delete(i)) if i == idx
                    );
                    if let Some(clipped) = r.intersect(l.grid) {
                        buf.fill_rect(clipped, if card_hover { SURFACE_HOVER } else { SURFACE });
                    }

                    if let Some(Some(thumb)) = self.thumbs.get(&item.id) {
                        let (sx, sy, sw, sh) = dotart::croprect(
                            thumb.w as u32,
                            thumb.h as u32,
                            self.screen_w as u32,
                            self.screen_h as u32,
                            &item.crop,
                        );
                        platform::blit_bgra_rect(
                            buf.dc,
                            Rect::new(r.x, r.y, r.w, settings_layout::THUMB_H),
                            thumb.w,
                            thumb.h,
                            sx as i32,
                            sy as i32,
                            sw as i32,
                            sh as i32,
                            &thumb.bgra,
                        );
                    }

                    let checked = enabled_ids.contains(&item.id);
                    draw_checkbox(
                        buf.dc,
                        Rect::new(r.x + 7, r.y + 7, 24, 24),
                        checked,
                        card_hover,
                        self.pressed == Some(HitTarget::Card(idx)),
                        self.font_body,
                    );
                    draw_icon_btn(
                        buf.dc,
                        Rect::new(r.x + r.w - 31, r.y + 7, 24, 24),
                        "×",
                        self.hover == Some(HitTarget::Delete(idx)),
                        self.pressed == Some(HitTarget::Delete(idx)),
                        true,
                        self.font_body,
                    );
                    if !item.id.starts_with("solid_") {
                        draw_icon_btn(
                            buf.dc,
                            Rect::new(r.x + r.w - 61, r.y + 7, 24, 24),
                            "✂",
                            self.hover == Some(HitTarget::Crop(idx)),
                            self.pressed == Some(HitTarget::Crop(idx)),
                            false,
                            self.font_body,
                        );
                    }

                    let lines = wrap_text(buf.dc, self.font_body, &item.title, r.w - 12, 2);
                    for (li, line) in lines.iter().enumerate() {
                        draw_text_top(
                            buf.dc,
                            line,
                            Rect::new(r.x + 6, r.y + settings_layout::THUMB_H + 4 + li as i32 * 19, r.w - 12, 19),
                            self.font_body,
                            FG,
                        );
                    }
                    if !item.artist.is_empty() {
                        let art = fit_text(buf.dc, self.font_body, &item.artist, r.w - 12);
                        draw_text_top(
                            buf.dc,
                            &art,
                            Rect::new(
                                r.x + 6,
                                r.y + settings_layout::THUMB_H + 4 + lines.len() as i32 * 19,
                                r.w - 12,
                                19,
                            ),
                            self.font_body,
                            SUB,
                        );
                    }
                }
            }
        }

        // 操作ボタン類
        let auto_label = if is_autostart { st.autostart_on } else { st.autostart_off };
        draw_toggle_btn(
            buf.dc,
            l.autostart,
            auto_label,
            self.anim_autostart,
            self.hover == Some(HitTarget::Autostart),
            self.pressed == Some(HitTarget::Autostart),
            self.font_body,
            self.font_button,
        );
        let mode_label = if is_normal { st.mode_normal } else { st.mode_pixel };
        draw_3d_btn(buf.dc, l.mode, mode_label, self.hover == Some(HitTarget::Mode), self.pressed == Some(HitTarget::Mode), self.font_body);
        draw_3d_btn(buf.dc, l.lang, st.lang_toggle, self.hover == Some(HitTarget::Lang), self.pressed == Some(HitTarget::Lang), self.font_body);
        draw_3d_btn(buf.dc, l.solid, "🎨", self.hover == Some(HitTarget::Solid), self.pressed == Some(HitTarget::Solid), self.font_button);
        draw_3d_btn(buf.dc, l.add, "＋", self.hover == Some(HitTarget::Add), self.pressed == Some(HitTarget::Add), self.font_button);
        draw_toggle_btn(
            buf.dc,
            l.wallpaper,
            st.wallpaper,
            self.anim_wallpaper,
            self.hover == Some(HitTarget::Wallpaper),
            self.pressed == Some(HitTarget::Wallpaper),
            self.font_body,
            self.font_button,
        );
        draw_toggle_btn(
            buf.dc,
            l.saver,
            st.screensaver,
            self.anim_saver,
            self.hover == Some(HitTarget::Saver),
            self.pressed == Some(HitTarget::Saver),
            self.font_body,
            self.font_button,
        );
    }

    fn ensure_thumb(&mut self, item: &UiItem) {
        if self.thumbs.contains_key(&item.id) {
            return;
        }
        let thumb = wic::decode_thumb_bgra(
            &item.path,
            (settings_layout::CARD_W * 2) as u32,
            (settings_layout::THUMB_H * 2) as u32,
        )
        .map(|img| Thumb { w: img.w as i32, h: img.h as i32, bgra: img.bgra });
        self.thumbs.insert(item.id.clone(), thumb);
    }

    fn persist_and_refresh(&mut self, trigger_wave: bool) {
        {
            let b = self.ctrl.borrow();
            let _ = b.settings.save(&b.data_dir);
            if trigger_wave {
                b.clock.trigger_soon();
            }
            b.reload_wallpaper();
        }
        self.build_preview();
        self.redraw_all();
        invalidate_rect(self.hwnd, None);
    }

    fn on_click_target(rc: &Rc<RefCell<Self>>, target: HitTarget) {
        let (hwnd, screen_aspect, ctrl, items) = {
            let Ok(b) = rc.try_borrow() else { return };
            (b.hwnd, b.screen_aspect, Rc::clone(&b.ctrl), b.items())
        };
        match target {
            HitTarget::Autostart => {
                {
                    let mut b = ctrl.borrow_mut();
                    b.settings.autostart = !b.settings.autostart;
                    b.apply_autostart();
                    let _ = b.settings.save(&b.data_dir);
                }
                if let Ok(mut s) = rc.try_borrow_mut() {
                    s.redraw_all();
                    invalidate_rect(hwnd, None);
                    s.schedule_tick(true);
                }
            }
            HitTarget::Mode => {
                {
                    let mut b = ctrl.borrow_mut();
                    b.settings.mode = if b.settings.is_normal_mode() {
                        "dotart".into()
                    } else {
                        "normal".into()
                    };
                }
                if let Ok(mut s) = rc.try_borrow_mut() {
                    s.persist_and_refresh(true);
                }
            }
            HitTarget::Lang => {
                {
                    let mut b = ctrl.borrow_mut();
                    let next = if b.current_lang() == Lang::En { "ja" } else { "en" };
                    b.settings.lang = Some(next.into());
                    let _ = b.settings.save(&b.data_dir);
                }
                if let Ok(mut s) = rc.try_borrow_mut() {
                    s.redraw_all();
                    invalidate_rect(hwnd, None);
                }
            }
            HitTarget::Solid => Self::add_solid_color(rc, hwnd, &ctrl),
            HitTarget::Add => Self::add_images(rc, hwnd, screen_aspect, &ctrl),
            HitTarget::Wallpaper => {
                let next_on = {
                    let mut b = ctrl.borrow_mut();
                    b.settings.wallpaper = !b.settings.wallpaper;
                    b.apply_autostart();
                    let _ = b.settings.save(&b.data_dir);
                    b.settings.wallpaper
                };
                AppController::ensure_wallpaper_running(&ctrl, next_on);
                if let Ok(mut s) = rc.try_borrow_mut() {
                    s.redraw_all();
                    invalidate_rect(hwnd, None);
                    s.schedule_tick(true);
                }
            }
            HitTarget::Saver => {
                if screensaver_active() {
                    disable_screensaver();
                } else {
                    enable_screensaver();
                }
                if let Ok(mut s) = rc.try_borrow_mut() {
                    s.redraw_all();
                    invalidate_rect(hwnd, None);
                    s.schedule_tick(true);
                }
            }
            HitTarget::Card(idx) => {
                if let Some(item) = items.get(idx) {
                    let mut changed = false;
                    {
                        let mut b = ctrl.borrow_mut();
                        if b.settings.enabled.contains(&item.id) {
                            if b.settings.enabled.len() > 1 {
                                b.settings.enabled.retain(|id| id != &item.id);
                                changed = true;
                            }
                        } else {
                            b.settings.enabled.push(item.id.clone());
                            changed = true;
                        }
                    }
                    if changed && let Ok(mut s) = rc.try_borrow_mut() {
                        s.persist_and_refresh(true);
                    }
                }
            }
            HitTarget::Crop(idx) => {
                if let Some(item) = items.get(idx)
                    && !item.id.starts_with("solid_")
                {
                    let lang = ctrl.borrow().current_lang();
                    if let Some(crop) = CropWindow::run_modal(&item.path, Some(&item.crop), hwnd, screen_aspect, lang) {
                        {
                            let mut b = ctrl.borrow_mut();
                            if item.builtin {
                                b.settings.builtin_crop.insert(item.id.clone(), crop);
                            } else if let Some(u) = b.settings.user_images.iter_mut().find(|u| u.id == item.id) {
                                u.crop = crop;
                            }
                        }
                        if let Ok(mut s) = rc.try_borrow_mut() {
                            s.thumbs.remove(&item.id);
                            s.persist_and_refresh(true);
                        }
                    }
                }
            }
            HitTarget::Delete(idx) => {
                if let Some(item) = items.get(idx) {
                    {
                        let mut b = ctrl.borrow_mut();
                        if item.builtin {
                            if !b.settings.hidden_builtin.contains(&item.id) {
                                b.settings.hidden_builtin.push(item.id.clone());
                            }
                        } else {
                            b.settings.user_images.retain(|u| u.id != item.id);
                            let _ = fs::remove_file(&item.path);
                        }
                        b.settings.enabled.retain(|id| id != &item.id);
                    }
                    if let Ok(mut s) = rc.try_borrow_mut() {
                        s.thumbs.remove(&item.id);
                        let remaining = s.items();
                        {
                            let mut b = ctrl.borrow_mut();
                            if b.settings.enabled.is_empty()
                                && let Some(first) = remaining.first()
                            {
                                b.settings.enabled.push(first.id.clone());
                            }
                        }
                        s.persist_and_refresh(true);
                    }
                }
            }
        }
    }

    fn add_solid_color(rc: &Rc<RefCell<Self>>, hwnd: HWND, ctrl: &Rc<RefCell<AppController>>) {
        let Some([r, g, b]) = choose_color_dialog(hwnd) else { return };
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0) % 10000;
        let id = format!("solid_{r:02x}{g:02x}{b:02x}_{stamp:04x}");
        let file = format!("{id}.bmp");
        let (data_dir, lang) = {
            let c = ctrl.borrow();
            (c.data_dir.clone(), c.current_lang())
        };
        let dest_dir = data_dir.join("user-images");
        let _ = fs::create_dir_all(&dest_dir);
        let _ = fs::write(dest_dir.join(&file), create_solid_bmp(r, g, b));
        let title = i18n::solid_title(lang, &format!("#{r:02X}{g:02X}{b:02X}"));
        {
            let mut c = ctrl.borrow_mut();
            c.settings.user_images.insert(0, UserImage {
                id: id.clone(),
                file,
                title,
                crop: Crop::default(),
            });
            c.settings.enabled.insert(0, id);
        }
        if let Ok(mut s) = rc.try_borrow_mut() {
            s.persist_and_refresh(true);
        }
    }

    fn add_images(rc: &Rc<RefCell<Self>>, hwnd: HWND, screen_aspect: f64, ctrl: &Rc<RefCell<AppController>>) {
        let (data_dir, lang) = {
            let c = ctrl.borrow();
            (c.data_dir.clone(), c.current_lang())
        };
        let paths = open_image_dialog(hwnd, i18n::strings(lang).image_filter);
        let mut added = false;
        for path in paths {
            let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
            if !matches!(ext.as_str(), "jpg" | "jpeg" | "png") {
                continue;
            }
            let Some(crop) = CropWindow::run_modal(&path, None, hwnd, screen_aspect, lang) else {
                continue;
            };
            let stamp = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_micros()).unwrap_or(0) % 0xFF_FFFF;
            let id = format!("user_{stamp:06x}");
            let file = format!("{id}.{ext}");
            let dest_dir = data_dir.join("user-images");
            let _ = fs::create_dir_all(&dest_dir);
            if fs::copy(&path, dest_dir.join(&file)).is_ok() {
                let title = path.file_stem().and_then(|s| s.to_str()).unwrap_or("image").to_string();
                let mut c = ctrl.borrow_mut();
                c.settings.user_images.insert(0, UserImage { id: id.clone(), file, title, crop });
                c.settings.enabled.insert(0, id);
                added = true;
            }
        }
        if added && let Ok(mut s) = rc.try_borrow_mut() {
            s.persist_and_refresh(true);
        }
    }
}

impl WindowHandler for Rc<RefCell<SettingsWindow>> {
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
                unsafe { let _ = EndPaint(hwnd, &ps); }
                Some(LRESULT(0))
            }
            WM_ERASEBKGND => Some(LRESULT(1)),
            WM_APP_LOAD_DONE => {
                if let Ok(mut b) = self.try_borrow_mut() {
                    b.apply_loaded_payload();
                }
                Some(LRESULT(0))
            }
            WM_SIZE => {
                let (cw, ch) = client_size(hwnd);
                if let Ok(mut b) = self.try_borrow_mut()
                    && cw > 0
                    && ch > 0
                    && (cw != b.width || ch != b.height)
                {
                    b.width = cw;
                    b.height = ch;
                    b.buffer = Some(BackBuffer::new(hwnd, cw, ch));
                    b.build_preview();
                    b.redraw_all();
                    invalidate_rect(hwnd, None);
                }
                Some(LRESULT(0))
            }
            WM_TIMER => {
                if let Ok(mut b) = self.try_borrow_mut() {
                    let now = Instant::now();
                    let dt = now.duration_since(b.last_tick).as_secs_f64().min(0.1);
                    b.last_tick = now;
                    let anim_moving = b.update_switch_animations(dt);
                    if anim_moving {
                        b.redraw_all();
                        invalidate_rect(hwnd, None);
                    } else {
                        b.advance_preview();
                    }
                    b.schedule_tick(anim_moving);
                }
                Some(LRESULT(0))
            }
            WM_MOUSEMOVE => {
                let (mx, my) = mouse_pos(lparam);
                if let Ok(mut b) = self.try_borrow_mut() {
                    let items = b.items();
                    let l = b.layout(items.len());
                    let mut hover = settings_layout::hit_test(&l, mx, my);
                    if let Some(HitTarget::Crop(idx)) = hover
                        && items.get(idx).is_some_and(|it| it.id.starts_with("solid_"))
                    {
                        hover = Some(HitTarget::Card(idx));
                    }
                    if hover != b.hover {
                        b.hover = hover;
                        b.redraw_all();
                        invalidate_rect(hwnd, None);
                    }
                }
                Some(LRESULT(0))
            }
            WM_LBUTTONDOWN => {
                let (mx, my) = mouse_pos(lparam);
                if let Ok(mut b) = self.try_borrow_mut() {
                    let items = b.items();
                    let l = b.layout(items.len());
                    let target = settings_layout::hit_test(&l, mx, my);
                    if target != b.pressed {
                        b.pressed = target;
                        b.redraw_all();
                        invalidate_rect(hwnd, None);
                    }
                }
                Some(LRESULT(0))
            }
            WM_LBUTTONUP => {
                let (mx, my) = mouse_pos(lparam);
                let target = if let Ok(mut b) = self.try_borrow_mut() {
                    b.pressed = None;
                    let items = b.items();
                    let l = b.layout(items.len());
                    settings_layout::hit_test(&l, mx, my)
                } else {
                    None
                };
                if let Some(t) = target {
                    SettingsWindow::on_click_target(self, t);
                } else if let Ok(mut b) = self.try_borrow_mut() {
                    b.redraw_all();
                    invalidate_rect(hwnd, None);
                }
                Some(LRESULT(0))
            }
            WM_MOUSEWHEEL => {
                let delta = wheel_delta(wparam);
                if let Ok(mut b) = self.try_borrow_mut() {
                    let count = b.items().len();
                    let l = b.layout(count);
                    let max_s = settings_layout::max_scroll(&l, count);
                    b.scroll = (b.scroll - (delta / 120) * 40).clamp(0, max_s);
                    b.redraw_all();
                    invalidate_rect(hwnd, None);
                }
                Some(LRESULT(0))
            }
            WM_CLOSE => {
                unsafe {
                    let _ = KillTimer(Some(hwnd), TIMER_TICK);
                    let _ = DestroyWindow(hwnd);
                }
                Some(LRESULT(0))
            }
            WM_DESTROY => {
                let ctrl = if let Ok(mut b) = self.try_borrow_mut() {
                    b.normal_bitmaps.clear();
                    b.buffer = None;
                    unsafe {
                        let _ = DeleteObject(b.font_body.into());
                        let _ = DeleteObject(b.font_button.into());
                    }
                    Some(Rc::clone(&b.ctrl))
                } else {
                    None
                };
                if let Some(ctrl) = ctrl {
                    let should_shutdown = if let Ok(mut c) = ctrl.try_borrow_mut() {
                        c.settings_win = None;
                        !c.display.as_ref().is_some_and(|d| !d.borrow().is_hidden())
                    } else {
                        false
                    };
                    if should_shutdown {
                        AppController::shutdown(&ctrl);
                    }
                }
                Some(LRESULT(0))
            }
            _ => None,
        }
    }
}

fn draw_3d_btn(
    dc: windows::Win32::Graphics::Gdi::HDC,
    r: Rect,
    label: &str,
    hover: bool,
    pressed: bool,
    font: HFONT,
) {
    let btn_y = if pressed { r.y + 2 } else { r.y };
    let btn_h = r.h - 3;
    fill_round_rect(dc, Rect::new(r.x, r.y + 2, r.w, r.h - 2), 6, [14, 14, 18], [14, 14, 18]);
    let bg = if pressed { [36, 36, 44] } else if hover { [56, 56, 68] } else { [44, 44, 54] };
    let border = if hover { [90, 90, 115] } else { [65, 65, 80] };
    fill_round_rect(dc, Rect::new(r.x, btn_y, r.w, btn_h), 6, bg, border);
    draw_text(dc, label, Rect::new(r.x, btn_y, r.w, btn_h), font, [240, 240, 245], true);
}

fn draw_checkbox(
    dc: windows::Win32::Graphics::Gdi::HDC,
    r: Rect,
    checked: bool,
    hover: bool,
    pressed: bool,
    font: HFONT,
) {
    let btn_y = if pressed { r.y + 2 } else { r.y };
    let btn_h = r.h - 2;
    let shadow = if checked { [8, 48, 90] } else { [10, 10, 14] };
    fill_round_rect(dc, Rect::new(r.x, r.y + 2, r.w, r.h - 2), 6, shadow, shadow);
    let (bg, border) = if checked {
        (
            if pressed { [9, 74, 140] } else if hover { ACCENT_HOVER } else { ACCENT },
            if hover { [70, 165, 255] } else { [38, 130, 225] },
        )
    } else {
        (
            if pressed { [24, 24, 30] } else if hover { [42, 42, 54] } else { [30, 30, 38] },
            if hover { [180, 180, 205] } else { [80, 80, 96] },
        )
    };
    fill_round_rect(dc, Rect::new(r.x, btn_y, r.w, btn_h), 6, bg, border);
    if checked {
        draw_text(dc, "✓", Rect::new(r.x, btn_y, r.w, btn_h), font, [255, 255, 255], true);
    }
}

fn draw_icon_btn(
    dc: windows::Win32::Graphics::Gdi::HDC,
    r: Rect,
    icon: &str,
    hover: bool,
    pressed: bool,
    danger: bool,
    font: HFONT,
) {
    let btn_y = if pressed { r.y + 2 } else { r.y };
    let btn_h = r.h - 2;
    fill_round_rect(dc, Rect::new(r.x, r.y + 2, r.w, r.h - 2), 6, [10, 10, 14], [10, 10, 14]);
    let (bg, border) = if danger {
        (
            if pressed { [140, 30, 30] } else if hover { [185, 42, 42] } else { [32, 32, 40] },
            if hover { [225, 80, 80] } else { [80, 80, 95] },
        )
    } else {
        (
            if pressed { [9, 74, 140] } else if hover { ACCENT } else { [32, 32, 40] },
            if hover { [38, 130, 225] } else { [80, 80, 95] },
        )
    };
    let fg = if hover || pressed { [255, 255, 255] } else { [220, 220, 230] };
    fill_round_rect(dc, Rect::new(r.x, btn_y, r.w, btn_h), 6, bg, border);
    draw_text(dc, icon, Rect::new(r.x, btn_y, r.w, btn_h), font, fg, true);
}

#[allow(clippy::too_many_arguments)]
fn draw_toggle_btn(
    dc: windows::Win32::Graphics::Gdi::HDC,
    r: Rect,
    label: &str,
    anim_pos: f64,
    hover: bool,
    pressed: bool,
    font_body: HFONT,
    font_btn: HFONT,
) {
    let btn_y = if pressed { r.y + 2 } else { r.y };
    let btn_h = r.h - 3;
    fill_round_rect(dc, Rect::new(r.x, r.y + 2, r.w, r.h - 2), 6, [14, 14, 18], [14, 14, 18]);
    let bg = if pressed { [34, 34, 42] } else if hover { SURFACE_HOVER } else { SURFACE };
    let border = if hover { [85, 85, 105] } else { [60, 60, 72] };
    fill_round_rect(dc, Rect::new(r.x, btn_y, r.w, btn_h), 6, bg, border);

    let track_h = if r.h >= 48 { 26 } else { 22 };
    let track_w = (track_h as f64 * 1.85).round() as i32;
    let track_y = btn_y + (btn_h - track_h) / 2;
    let track_x = r.x + r.w - track_w - 14;
    let font = if r.h >= 48 { font_btn } else { font_body };
    let text_col = if hover { [255, 255, 255] } else { FG };
    draw_text(dc, label, Rect::new(r.x + 14, btn_y, track_x - r.x - 20, btn_h), font, text_col, false);
    draw_toggle_pill(dc, Rect::new(track_x, track_y, track_w, track_h), anim_pos);
}

fn fit_text(dc: windows::Win32::Graphics::Gdi::HDC, font: HFONT, text: &str, max_w: i32) -> String {
    if text_width(dc, font, text) <= max_w {
        return text.to_string();
    }
    let mut chars: Vec<char> = text.chars().collect();
    while chars.len() > 1 {
        chars.pop();
        let cand: String = chars.iter().collect::<String>() + "…";
        if text_width(dc, font, &cand) <= max_w {
            return cand;
        }
    }
    "…".to_string()
}

fn wrap_text(dc: windows::Win32::Graphics::Gdi::HDC, font: HFONT, text: &str, max_w: i32, max_lines: usize) -> Vec<String> {
    let mut lines = Vec::new();
    let mut rest = text.to_string();
    while lines.len() < max_lines && !rest.is_empty() {
        if text_width(dc, font, &rest) <= max_w {
            lines.push(rest);
            break;
        }
        let chars: Vec<char> = rest.chars().collect();
        let mut cut = chars.len();
        while cut > 1 {
            let sub: String = chars[..cut].iter().collect();
            if text_width(dc, font, &sub) <= max_w {
                break;
            }
            cut -= 1;
        }
        if lines.len() == max_lines - 1 {
            lines.push(fit_text(dc, font, &rest, max_w));
            break;
        }
        lines.push(chars[..cut].iter().collect());
        rest = chars[cut..].iter().collect();
    }
    lines
}

fn create_solid_bmp(r: u8, g: u8, b: u8) -> Vec<u8> {
    let (w, h) = (16u32, 9u32);
    let row_bytes = (w * 3 + 3) & !3;
    let img_size = row_bytes * h;
    let file_size = 54 + img_size;
    let mut out = Vec::with_capacity(file_size as usize);
    out.extend_from_slice(b"BM");
    out.extend_from_slice(&file_size.to_le_bytes());
    out.extend_from_slice(&0u16.to_le_bytes());
    out.extend_from_slice(&0u16.to_le_bytes());
    out.extend_from_slice(&54u32.to_le_bytes());
    out.extend_from_slice(&40u32.to_le_bytes());
    out.extend_from_slice(&(w as i32).to_le_bytes());
    out.extend_from_slice(&(h as i32).to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&24u16.to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes());
    out.extend_from_slice(&img_size.to_le_bytes());
    out.extend_from_slice(&2835i32.to_le_bytes());
    out.extend_from_slice(&2835i32.to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes());
    let pad = (row_bytes - w * 3) as usize;
    for _ in 0..h {
        for _ in 0..w {
            out.extend_from_slice(&[b, g, r]);
        }
        out.extend(std::iter::repeat_n(0u8, pad));
    }
    out
}
