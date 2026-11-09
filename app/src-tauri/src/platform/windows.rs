//Windows用の処理（WorkerWを使う壁紙、スクリーンセーバーの登録、電源と全画面の判定）
use std::path::Path;
use windows_sys::Win32::Foundation::{BOOL, HWND, LPARAM, RECT, TRUE};
use windows_sys::Win32::System::Power::{GetSystemPowerStatus, SYSTEM_POWER_STATUS};
use windows_sys::Win32::System::Registry::{
    RegCloseKey, RegCreateKeyW, RegSetValueExW, HKEY, HKEY_CURRENT_USER, REG_SZ,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    EnumWindows, FindWindowExW, FindWindowW, GetClassNameW, GetForegroundWindow, GetSystemMetrics,
    GetWindowRect, SendMessageTimeoutW, SetParent, SetWindowPos, SMTO_NORMAL, SM_CXSCREEN,
    SM_CYSCREEN, SWP_NOACTIVATE, SWP_SHOWWINDOW,
};

//文字列をヌル終端のUTF-16にする（引数sは文字列）
fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

//ウィンドウのクラス名を読む（引数hwndはウィンドウ）
unsafe fn class_name(hwnd: HWND) -> String {
    let mut buf = [0u16; 128];
    let len = GetClassNameW(hwnd, buf.as_mut_ptr(), buf.len() as i32);
    if len <= 0 {
        return String::new();
    }
    String::from_utf16_lossy(&buf[..len as usize])
}

//WorkerWを探すための状態（defview_parentはデスクトップアイコンを持つウィンドウ、workerwsはWorkerWの一覧と列挙順）
struct HostSearch {
    defview_parent: HWND,
    defview_index: usize,
    counter: usize,
    workerws: Vec<(usize, HWND)>,
}

//ウィンドウ列挙の受け手（引数hwndはウィンドウ、引数lparamはHostSearchへのポインタ）
extern "system" fn enum_callback(hwnd: HWND, lparam: LPARAM) -> BOOL {
    unsafe {
        let search = &mut *(lparam as *mut HostSearch);
        let index = search.counter;
        search.counter += 1;
        let defview = FindWindowExW(
            hwnd,
            std::ptr::null_mut(),
            wide("SHELLDLL_DefView").as_ptr(),
            std::ptr::null(),
        );
        if !defview.is_null() {
            search.defview_parent = hwnd;
            search.defview_index = index;
        }
        if class_name(hwnd) == "WorkerW" {
            search.workerws.push((index, hwnd));
        }
        TRUE
    }
}

//壁紙として貼り付ける（引数hwndは自ウィンドウ、引数xとyとwとhはディスプレイ上の場所と大きさ）
//Progmanへ0x052Cを送ってWorkerWを作らせ、アイコンを持つウィンドウの後ろにあるWorkerWの子にする
pub fn wallpaper_attach(hwnd: isize, x: i32, y: i32, w: i32, h: i32) -> Result<(), String> {
    unsafe {
        let progman = FindWindowW(wide("Progman").as_ptr(), std::ptr::null());
        if progman.is_null() {
            return Err("Progmanが見つかりません".to_string());
        }
        let mut result: usize = 0;
        //0x052CはWorkerWを作らせる合図で、Windows11の24H2での構造変更に備えて引数の組み合わせを2通り送る
        SendMessageTimeoutW(
            progman,
            0x052C,
            0xD,
            0,
            SMTO_NORMAL,
            1000,
            &mut result,
        );
        SendMessageTimeoutW(
            progman,
            0x052C,
            0xD,
            1,
            SMTO_NORMAL,
            1000,
            &mut result,
        );

        let mut search = HostSearch {
            defview_parent: std::ptr::null_mut(),
            defview_index: usize::MAX,
            counter: 0,
            workerws: Vec::new(),
        };
        EnumWindows(
            Some(enum_callback),
            &mut search as *mut HostSearch as LPARAM,
        );

        let host = search
            .workerws
            .iter()
            .find(|(index, _)| *index > search.defview_index)
            .map(|(_, hwnd)| *hwnd)
            .or_else(|| {
                search
                    .workerws
                    .iter()
                    .map(|(_, hwnd)| *hwnd)
                    .find(|hwnd| *hwnd != search.defview_parent)
            })
            .unwrap_or(progman);

        let child = hwnd as HWND;
        SetParent(child, host);
        SetWindowPos(
            child,
            std::ptr::null_mut(),
            x,
            y,
            w,
            h,
            SWP_NOACTIVATE | SWP_SHOWWINDOW,
        );
        Ok(())
    }
}

//レジストリに値を書く（引数keyは開いたキー、引数nameは値の名前、引数valueは値）
unsafe fn set_registry_value(key: HKEY, name: &str, value: &str) -> Result<(), String> {
    let name_w = wide(name);
    let value_w = wide(value);
    let status = RegSetValueExW(
        key,
        name_w.as_ptr(),
        0,
        REG_SZ,
        value_w.as_ptr() as *const u8,
        (value_w.len() * 2) as u32,
    );
    if status != 0 {
        return Err(format!("レジストリへの書き込みに失敗しました（{}）", status));
    }
    Ok(())
}

//スクリーンセーバーとして登録する（引数scr_pathは.scrファイルの場所、HKCUへ書くので管理者権限は使わない）
pub fn set_screensaver_registered(scr_path: &Path) -> Result<(), String> {
    unsafe {
        let key_path = wide("Control Panel\\Desktop");
        let mut key: HKEY = std::ptr::null_mut();
        let status = RegCreateKeyW(HKEY_CURRENT_USER, key_path.as_ptr(), &mut key);
        if status != 0 {
            return Err(format!("レジストリを開けませんでした（{}）", status));
        }
        let path_text = scr_path.to_string_lossy().to_string();
        let result = set_registry_value(key, "SCRNSAVE.EXE", &path_text)
            .and_then(|_| set_registry_value(key, "ScreenSaveActive", "1"));
        RegCloseKey(key);
        result
    }
}

//スクリーンセーバーの設定画面を開く
pub fn open_screensaver_settings() -> Result<(), String> {
    std::process::Command::new("control")
        .arg("desk.cpl,,@screensaver")
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

//電池で動いているか調べる（交流電源につながっていないとき真）
pub fn is_battery_powered() -> bool {
    unsafe {
        let mut status: SYSTEM_POWER_STATUS = std::mem::zeroed();
        if GetSystemPowerStatus(&mut status) == 0 {
            return false;
        }
        status.ACLineStatus == 0
    }
}

//前面のアプリが全画面か調べる（前面ウィンドウが画面全体を占め、シェルのウィンドウでないとき真）
pub fn foreground_is_fullscreen() -> bool {
    unsafe {
        let fg = GetForegroundWindow();
        if fg.is_null() {
            return false;
        }
        let name = class_name(fg);
        if name == "Progman"
            || name == "WorkerW"
            || name == "Shell_TrayWnd"
            || name == "Shell_SecondaryTrayWnd"
        {
            return false;
        }
        let mut rect: RECT = std::mem::zeroed();
        if GetWindowRect(fg, &mut rect) == 0 {
            return false;
        }
        let sw = GetSystemMetrics(SM_CXSCREEN);
        let sh = GetSystemMetrics(SM_CYSCREEN);
        rect.left <= 0 && rect.top <= 0 && rect.right >= sw && rect.bottom >= sh
    }
}
