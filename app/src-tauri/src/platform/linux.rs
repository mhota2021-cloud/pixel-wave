//Linux用の処理（壁紙とスクリーンセーバーは作らず、全画面表示だけを使う。電池の判定だけ実装する）
use std::fs;
use std::path::Path;

//壁紙として貼り付ける（引数hwndはウィンドウの識別値、引数xとyとwとhは置く場所と大きさ、Linuxでは未対応で全画面表示を使う）
pub fn wallpaper_attach(_hwnd: isize, _x: i32, _y: i32, _w: i32, _h: i32) -> Result<(), String> {
    Err("このOSでは壁紙は対応していません".to_string())
}

//スクリーンセーバーとして登録する（引数_scr_pathは登録するファイルの場所、Linuxでは未対応）
pub fn set_screensaver_registered(_scr_path: &Path) -> Result<(), String> {
    Err("このOSではスクリーンセーバーは対応していません".to_string())
}

//スクリーンセーバーの設定画面を開く（Linuxでは未対応）
pub fn open_screensaver_settings() -> Result<(), String> {
    Err("このOSではスクリーンセーバーは対応していません".to_string())
}

//電池で動いているか調べる（/sys/class/power_supplyを見て、電池があり交流電源がどれもつながっていないとき真）
pub fn is_battery_powered() -> bool {
    let dir = Path::new("/sys/class/power_supply");
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return false,
    };
    let mut has_battery = false;
    let mut any_online = false;
    for entry in entries.flatten() {
        let base = entry.path();
        let kind = fs::read_to_string(base.join("type"))
            .unwrap_or_default()
            .trim()
            .to_string();
        if kind == "Battery" {
            has_battery = true;
        } else if kind == "Mains" {
            let online = fs::read_to_string(base.join("online"))
                .unwrap_or_default()
                .trim()
                .to_string();
            if online == "1" {
                any_online = true;
            }
        }
    }
    has_battery && !any_online
}

//前面のアプリが全画面か調べる（Linuxでは判定せず常に偽、そのかわり全画面表示の側が入力で終わる）
pub fn foreground_is_fullscreen() -> bool {
    false
}
