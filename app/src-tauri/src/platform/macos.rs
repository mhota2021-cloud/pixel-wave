//macOS用の処理（デスクトップ階層の壁紙、スクリーンセーバーの設置、電源と全画面の判定）
use std::ffi::{c_char, c_void, CString};
use std::fs;
use std::path::Path;

//Objective-Cの実行時関数の宣言（ウィンドウの階層と振る舞いを設定するために使う）
type Id = *mut c_void;
type Sel = *mut c_void;

#[link(name = "objc", kind = "dylib")]
extern "C" {
    fn sel_registerName(name: *const c_char) -> Sel;
    fn objc_msgSend();
}

//セレクタを作る（引数nameはメソッドの名前）
unsafe fn sel(name: &str) -> Sel {
    let text = CString::new(name).expect("セレクタの名前");
    sel_registerName(text.as_ptr())
}

//整数を渡すメソッドを呼ぶ（引数objは対象、引数selectorはメソッド、引数valueは値）
unsafe fn send_i64(obj: Id, selector: Sel, value: i64) {
    let f: unsafe extern "C" fn(Id, Sel, i64) =
        std::mem::transmute(objc_msgSend as *const c_void);
    f(obj, selector, value);
}

//符号なし整数を渡すメソッドを呼ぶ（引数objは対象、引数selectorはメソッド、引数valueは値）
unsafe fn send_usize(obj: Id, selector: Sel, value: usize) {
    let f: unsafe extern "C" fn(Id, Sel, usize) =
        std::mem::transmute(objc_msgSend as *const c_void);
    f(obj, selector, value);
}

//壁紙として貼り付ける（引数hwndはNSWindowへのポインタ、置く場所と大きさはウィンドウ生成時に指定済みなので使わない）
//階層をkCGDesktopWindowLevel（値はマイナス2147483623）にしてアイコンより奥に置き、全てのSpacesに出してMissionControlで動かないようにする
pub fn wallpaper_attach(hwnd: isize, _x: i32, _y: i32, _w: i32, _h: i32) -> Result<(), String> {
    let window = hwnd as Id;
    if window.is_null() {
        return Err("ウィンドウがありません".to_string());
    }
    unsafe {
        send_i64(window, sel("setLevel:"), -2147483623);
        //collectionBehaviorの内訳はcanJoinAllSpaces（1）とstationary（16）とignoresCycle（64）
        send_usize(window, sel("setCollectionBehavior:"), 1 | 16 | 64);
    }
    Ok(())
}

//CoreFoundationとIOKitの宣言（電源の状態を読むために使う）
#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFRelease(value: *const c_void);
    fn CFArrayGetCount(array: *const c_void) -> isize;
    fn CFArrayGetValueAtIndex(array: *const c_void, index: isize) -> *const c_void;
    fn CFDictionaryGetValue(dict: *const c_void, key: *const c_void) -> *const c_void;
    fn CFEqual(first: *const c_void, second: *const c_void) -> u8;
    fn CFNumberGetValue(number: *const c_void, kind: i32, out: *mut c_void) -> u8;
    fn CFStringCreateWithCString(
        alloc: *const c_void,
        text: *const c_char,
        encoding: u32,
    ) -> *const c_void;
}

#[link(name = "IOKit", kind = "framework")]
extern "C" {
    fn IOPSCopyPowerSourcesInfo() -> *const c_void;
    fn IOPSCopyPowerSourcesList(blob: *const c_void) -> *const c_void;
    fn IOPSGetPowerSourceDescription(
        blob: *const c_void,
        source: *const c_void,
    ) -> *const c_void;
    static kIOPSPowerSourceStateKey: *const c_void;
    static kIOPSACPowerValue: *const c_void;
}

//電池で動いているか調べる（電池があり、交流電源につながっていないとき真、電池の無い機種では偽）
pub fn is_battery_powered() -> bool {
    unsafe {
        let blob = IOPSCopyPowerSourcesInfo();
        if blob.is_null() {
            return false;
        }
        let list = IOPSCopyPowerSourcesList(blob);
        let mut on_battery = false;
        if !list.is_null() {
            let count = CFArrayGetCount(list);
            for i in 0..count {
                let source = CFArrayGetValueAtIndex(list, i);
                if source.is_null() {
                    continue;
                }
                let description = IOPSGetPowerSourceDescription(blob, source);
                if description.is_null() {
                    continue;
                }
                let state = CFDictionaryGetValue(description, kIOPSPowerSourceStateKey);
                if !state.is_null() && CFEqual(state, kIOPSACPowerValue) == 0 {
                    on_battery = true;
                }
            }
            CFRelease(list);
        }
        CFRelease(blob);
        on_battery
    }
}

//CoreGraphicsの宣言（前面のウィンドウと画面の大きさを比べるために使う）
#[repr(C)]
struct CGPointF {
    x: f64,
    y: f64,
}

#[repr(C)]
struct CGSizeF {
    width: f64,
    height: f64,
}

#[repr(C)]
struct CGRectF {
    origin: CGPointF,
    size: CGSizeF,
}

#[link(name = "CoreGraphics", kind = "framework")]
extern "C" {
    fn CGWindowListCopyWindowInfo(options: u32, relative_to: u32) -> *const c_void;
    fn CGMainDisplayID() -> u32;
    fn CGDisplayBounds(display: u32) -> CGRectF;
    static kCGWindowLayer: *const c_void;
    static kCGWindowOwnerPID: *const c_void;
    static kCGWindowBounds: *const c_void;
}

//辞書から数値を読む（引数dictは辞書、引数keyはキー文字列、読めなければ偽を返す）
unsafe fn number_value(dict: *const c_void, key: &str, out: &mut f64) -> bool {
    let text = CString::new(key).expect("キーの文字列");
    let key_ref = CFStringCreateWithCString(std::ptr::null(), text.as_ptr(), 0x08000100);
    if key_ref.is_null() {
        return false;
    }
    let value = CFDictionaryGetValue(dict, key_ref);
    let ok = !value.is_null()
        && CFNumberGetValue(value, 13, out as *mut f64 as *mut c_void) != 0;
    CFRelease(key_ref);
    ok
}

//辞書から整数を読む（引数dictは辞書、引数keyはキー、読めなければ偽を返す）
unsafe fn int_value(dict: *const c_void, key: *const c_void, out: &mut i32) -> bool {
    let value = CFDictionaryGetValue(dict, key);
    !value.is_null() && CFNumberGetValue(value, 3, out as *mut i32 as *mut c_void) != 0
}

//前面のアプリが全画面か調べる（前面から順に並ぶ一覧で、通常の階層の最初の他人のウィンドウが画面全体を占めるとき真）
pub fn foreground_is_fullscreen() -> bool {
    unsafe {
        let display = CGDisplayBounds(CGMainDisplayID());
        //引数1は画面に出ているウィンドウだけを前面から順に取る指定
        let list = CGWindowListCopyWindowInfo(1, 0);
        if list.is_null() {
            return false;
        }
        let own_pid = std::process::id() as i32;
        let count = CFArrayGetCount(list);
        let mut result = false;
        for i in 0..count {
            let info = CFArrayGetValueAtIndex(list, i);
            if info.is_null() {
                continue;
            }
            let mut layer: i32 = -1;
            let mut pid: i32 = -1;
            if !int_value(info, kCGWindowLayer, &mut layer) || layer != 0 {
                continue;
            }
            if !int_value(info, kCGWindowOwnerPID, &mut pid) || pid == own_pid {
                continue;
            }
            let bounds = CFDictionaryGetValue(info, kCGWindowBounds);
            if bounds.is_null() {
                continue;
            }
            let (mut x, mut y, mut w, mut h) = (0.0f64, 0.0f64, 0.0f64, 0.0f64);
            if number_value(bounds, "X", &mut x)
                && number_value(bounds, "Y", &mut y)
                && number_value(bounds, "Width", &mut w)
                && number_value(bounds, "Height", &mut h)
            {
                result = x <= display.origin.x
                    && y <= display.origin.y
                    && x + w >= display.origin.x + display.size.width
                    && y + h >= display.origin.y + display.size.height;
            }
            break;
        }
        CFRelease(list);
        result
    }
}

//フォルダを中身ごと写す（引数srcは写す元、引数dstは写す先）
fn copy_dir_all(src: &Path, dst: &Path) -> Result<(), String> {
    fs::create_dir_all(dst).map_err(|e| e.to_string())?;
    for entry in fs::read_dir(src).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if entry.file_type().map_err(|e| e.to_string())?.is_dir() {
            copy_dir_all(&from, &to)?;
        } else {
            fs::copy(&from, &to).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

//スクリーンセーバーとして登録する（引数scr_pathはアプリに入っている.saverの場所、ホームの下のScreenSaversへ写す）
pub fn set_screensaver_registered(scr_path: &Path) -> Result<(), String> {
    let home = std::env::var("HOME").map_err(|e| e.to_string())?;
    let dir = Path::new(&home).join("Library").join("Screen Savers");
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let name = scr_path
        .file_name()
        .ok_or_else(|| "セーバーの名前が分かりません".to_string())?;
    let dest = dir.join(name);
    if dest.exists() {
        fs::remove_dir_all(&dest).map_err(|e| e.to_string())?;
    }
    copy_dir_all(scr_path, &dest)
}

//スクリーンセーバーの設定画面を開く（新しいシステム設定の識別子を試し、だめなら古い識別子にする）
pub fn open_screensaver_settings() -> Result<(), String> {
    let newer = std::process::Command::new("open")
        .arg("x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")
        .status();
    if let Ok(status) = newer {
        if status.success() {
            return Ok(());
        }
    }
    let older = std::process::Command::new("open")
        .arg("x-apple.systempreferences:com.apple.preference.desktopscreeneffect")
        .status()
        .map_err(|e| e.to_string())?;
    if older.success() {
        Ok(())
    } else {
        Err("スクリーンセーバーの設定画面を開けませんでした".to_string())
    }
}
