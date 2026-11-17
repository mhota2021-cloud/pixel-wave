//! UI表示文言の多言語辞書（日本語と英語）

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Lang {
    Ja,
    En,
}

impl Lang {
    pub fn from_code(code: &str) -> Self {
        if code == "en" { Self::En } else { Self::Ja }
    }
}

pub struct Strings {
    pub autostart_on: &'static str,
    pub autostart_off: &'static str,
    pub mode_normal: &'static str,
    pub mode_pixel: &'static str,
    pub wallpaper: &'static str,
    pub screensaver: &'static str,
    pub lang_toggle: &'static str,
    pub image_filter: &'static str,
    pub tray_tooltip: &'static str,
    pub tray_open_settings: &'static str,
    pub tray_show: &'static str,
    pub tray_resume: &'static str,
    pub tray_pause: &'static str,
    pub tray_exit: &'static str,
    pub crop_header: &'static str,
    pub crop_reset: &'static str,
    pub crop_cancel: &'static str,
    pub crop_confirm: &'static str,
}

const JA: Strings = Strings {
    autostart_on: "ログイン時起動ON",
    autostart_off: "ログイン時起動OFF",
    mode_normal: "モード:通常画像",
    mode_pixel: "モード:ドット絵",
    wallpaper: "壁紙",
    screensaver: "スクリーンセーバー",
    lang_toggle: "EN",
    image_filter: "画像",
    tray_tooltip: "Pixel Wave - 壁紙",
    tray_open_settings: "設定を開く",
    tray_show: "壁紙を表示",
    tray_resume: "壁紙を再開",
    tray_pause: "壁紙を一時停止",
    tray_exit: "終了",
    crop_header: "切り取り範囲の調整",
    crop_reset: "中央に戻す",
    crop_cancel: "キャンセル",
    crop_confirm: "決定 (Enter)",
};

const EN: Strings = Strings {
    autostart_on: "Auto-start: ON",
    autostart_off: "Auto-start: OFF",
    mode_normal: "Mode: Original",
    mode_pixel: "Mode: Pixel Art",
    wallpaper: "Wallpaper",
    screensaver: "Screensaver",
    lang_toggle: "日本語",
    image_filter: "Images",
    tray_tooltip: "Pixel Wave - Wallpaper",
    tray_open_settings: "Open Settings",
    tray_show: "Show Wallpaper",
    tray_resume: "Resume Wallpaper",
    tray_pause: "Pause Wallpaper",
    tray_exit: "Exit",
    crop_header: "Adjust Crop Area",
    crop_reset: "Reset to Center",
    crop_cancel: "Cancel",
    crop_confirm: "Apply (Enter)",
};

pub fn strings(lang: Lang) -> &'static Strings {
    match lang {
        Lang::Ja => &JA,
        Lang::En => &EN,
    }
}

pub fn solid_title(lang: Lang, hex: &str) -> String {
    match lang {
        Lang::Ja => format!("単色 ({hex})"),
        Lang::En => format!("Solid ({hex})"),
    }
}

pub fn crop_window_title(lang: Lang, aspect: f64) -> String {
    match lang {
        Lang::Ja => format!("切り取り範囲の調整 [画面比率 {aspect:.2}:1] - Pixel Wave"),
        Lang::En => format!("Adjust Crop Area [Aspect {aspect:.2}:1] - Pixel Wave"),
    }
}

pub fn crop_sub(lang: Lang, aspect: f64) -> String {
    match lang {
        Lang::Ja => format!("画面サイズ比率: {aspect:.2}:1 - 枠をドラッグして移動、四隅で拡大縮小"),
        Lang::En => format!("Screen Aspect: {aspect:.2}:1 - Drag to move, drag corners to resize"),
    }
}
