#![windows_subsystem = "windows"]

mod args;
mod cache;
mod crop_window;
mod display_window;
mod dotart;
mod engine;
mod i18n;
mod loader;
mod platform;
mod settings;
mod settings_layout;
mod settings_window;
mod wic;
mod window;

use std::sync::Arc;

use args::LaunchMode;
use display_window::{DisplayMode, DisplayWindow};
use engine::WaveClock;
use platform::{WM_APP_OPEN_SETTINGS, cache_dir, data_dir, exe_dir, find_window_by_class, post_message, take_single_instance_mutex};
use settings::AppSettings;
use settings_window::{AppController, TrayHost};

fn main() {
    let mode = args::parse_mode(std::env::args().skip(1));
    if mode == LaunchMode::Preview {
        return;
    }

    let ddir = data_dir();
    let cdir = cache_dir();
    let pdir = loader::paintings_dir(&exe_dir());
    let credits = loader::load_credits(&pdir);
    let builtin_ids: Vec<String> = credits.iter().map(|c| c.id.clone()).collect();
    let settings = AppSettings::load(&ddir, &builtin_ids);

    if mode == LaunchMode::Screensaver {
        let mut list = loader::enabled_paintings(&settings, &credits, &pdir, &ddir);
        if list.is_empty() {
            let mut tmp = settings.clone();
            tmp.enabled = builtin_ids;
            list = loader::enabled_paintings(&tmp, &credits, &pdir, &ddir);
        }
        let clock = Arc::new(WaveClock::new());
        let _saver = DisplayWindow::create(
            DisplayMode::Screensaver,
            list,
            cdir,
            false,
            settings.is_normal_mode(),
            clock,
            true,
        );
        window::run_message_loop();
        return;
    }

    // 壁紙・トレイ・設定画面は1プロセスにまとめる
    if take_single_instance_mutex("PixelWaveMainMutex") {
        if mode == LaunchMode::Settings
            && let Some(tray) = find_window_by_class("PixelWaveTrayHelper")
        {
            post_message(tray, WM_APP_OPEN_SETTINGS, 0, 0);
        }
        return;
    }

    let ctrl = AppController::new(ddir, cdir, pdir, credits, settings);
    let _tray_hwnd = TrayHost::create(std::rc::Rc::clone(&ctrl));

    match mode {
        LaunchMode::Wallpaper => {
            {
                let mut b = ctrl.borrow_mut();
                b.settings.wallpaper = true;
                let _ = b.settings.save(&b.data_dir);
            }
            AppController::ensure_wallpaper_running(&ctrl, true);
        }
        LaunchMode::Settings => {
            let should_show_wallpaper = ctrl.borrow().settings.wallpaper;
            if should_show_wallpaper {
                AppController::ensure_wallpaper_running(&ctrl, true);
            }
            AppController::open_settings(&ctrl);
        }
        LaunchMode::Screensaver | LaunchMode::Preview => unreachable!(),
    }

    window::run_message_loop();
}
