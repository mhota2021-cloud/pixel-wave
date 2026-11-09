//PixelWaveの本体（起動モードの振り分けとコマンドと常駐アイコンと壁紙の管理）
mod args;
mod platform;
mod settings;

use args::{parse_mode, RunMode};
use settings::{Settings, UserImage};
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_autostart::ManagerExt;

//素材の絵の情報（idは識別子、fileはファイル名、cropは切り抜く位置、bytesは画像の中身でmacOSのセーバーへ渡すために埋め込む）
#[cfg(target_os = "macos")]
struct BuiltinInfo {
    id: &'static str,
    file: &'static str,
    crop: &'static str,
    bytes: &'static [u8],
}

//素材の絵のidの一覧（BUILTIN_IDS、初期設定で使う順番）と、macOS用の画像の埋め込み（BUILTINS）。build.rsがassets/paintings/credits.jsonから作る
include!(concat!(env!("OUT_DIR"), "/builtins.rs"));

//macOSのセーバーが読める場所へ設定と絵を書き出す（引数stateは状態、セーバーはサンドボックスの中で動くためアプリのデータフォルダを読めない）
#[cfg(target_os = "macos")]
fn export_saver_payload(state: &AppState) -> Result<(), String> {
    let home = std::env::var("HOME").map_err(|e| e.to_string())?;
    let dir = PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("PixelWave");
    let images = dir.join("images");
    fs::create_dir_all(&images).map_err(|e| e.to_string())?;
    let settings = state.settings.lock().expect("設定のロック").clone();
    let mut paintings = Vec::new();
    for id in &settings.enabled {
        if let Some(info) = BUILTINS.iter().find(|b| b.id == id) {
            fs::write(images.join(info.file), info.bytes).map_err(|e| e.to_string())?;
            paintings.push(serde_json::json!({
                "src": format!("images/{}", info.file),
                "crop": info.crop,
            }));
        } else if let Some(user) = settings.user_images.iter().find(|u| &u.id == id) {
            fs::copy(
                state.data_dir.join("user-images").join(&user.file),
                images.join(&user.file),
            )
            .map_err(|e| e.to_string())?;
            paintings.push(serde_json::json!({
                "src": format!("images/{}", user.file),
                "crop": "center",
            }));
        }
    }
    let payload = serde_json::json!({ "paintings": paintings });
    fs::write(
        dir.join("saver-settings.json"),
        serde_json::to_string_pretty(&payload).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

//アプリの状態（modeは起動モード、data_dirはデータフォルダ、settingsは設定、quittingは終了中かどうか、wallpaper_labelsは壁紙ウィンドウの一覧）
struct AppState {
    mode: RunMode,
    data_dir: PathBuf,
    settings: Mutex<Settings>,
    quitting: AtomicBool,
    wallpaper_labels: Mutex<Vec<String>>,
    power_thread_started: AtomicBool,
    tray_available: AtomicBool,
}

//設定を読む（画面からの呼び出し）
#[tauri::command]
fn get_settings(state: State<'_, AppState>) -> Settings {
    state.settings.lock().expect("設定のロック").clone()
}

//設定を保存する（画面からの呼び出し、引数settingsは新しい設定）
#[tauri::command]
fn save_settings(state: State<'_, AppState>, settings: Settings) -> Result<(), String> {
    *state.settings.lock().expect("設定のロック") = settings.clone();
    settings::save(&state.data_dir, &settings)?;
    #[cfg(target_os = "macos")]
    {
        let _ = export_saver_payload(&state);
    }
    Ok(())
}

//データフォルダの場所を返す（画面からの呼び出し）
#[tauri::command]
fn get_data_dir(state: State<'_, AppState>) -> String {
    state.data_dir.to_string_lossy().to_string()
}

//動いているOSを返す（画面からの呼び出し、windowsかmacosかlinuxのどれか）
#[tauri::command]
fn get_platform() -> String {
    std::env::consts::OS.to_string()
}

//起動モードを返す（画面からの呼び出し、screensaverかsettingsのどちらか）
#[tauri::command]
fn get_mode(state: State<'_, AppState>) -> String {
    match state.mode {
        RunMode::Screensaver => "screensaver".to_string(),
        _ => "settings".to_string(),
    }
}

//画像を追加する（画面からの呼び出し、引数pathは元の画像の場所、データフォルダへ写して設定に加える）
#[tauri::command]
fn add_user_image(state: State<'_, AppState>, path: String) -> Result<UserImage, String> {
    let source = PathBuf::from(&path);
    let ext = source
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    if !["jpg", "jpeg", "png", "webp"].contains(&ext.as_str()) {
        return Err("対応していない画像の形式です".to_string());
    }
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let id = format!("user_{:x}", (nanos % 0xffff_ffff) as u32);
    let file = format!("{}.{}", id, ext);
    let dir = state.data_dir.join("user-images");
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    fs::copy(&source, dir.join(&file)).map_err(|e| e.to_string())?;
    let title = source
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| id.clone());
    let image = UserImage {
        id: id.clone(),
        file,
        title,
    };
    let mut settings = state.settings.lock().expect("設定のロック");
    settings.user_images.push(image.clone());
    if !settings.enabled.contains(&id) {
        settings.enabled.push(id);
    }
    settings::save(&state.data_dir, &settings)?;
    drop(settings);
    #[cfg(target_os = "macos")]
    {
        let _ = export_saver_payload(&state);
    }
    Ok(image)
}

//画像を削除する（画面からの呼び出し、引数idは画像の識別子、ファイルも消す）
#[tauri::command]
fn remove_user_image(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let mut settings = state.settings.lock().expect("設定のロック");
    if let Some(pos) = settings.user_images.iter().position(|u| u.id == id) {
        let image = settings.user_images.remove(pos);
        let _ = fs::remove_file(state.data_dir.join("user-images").join(&image.file));
    }
    settings.enabled.retain(|e| e != &id);
    settings::save(&state.data_dir, &settings)?;
    drop(settings);
    #[cfg(target_os = "macos")]
    {
        let _ = export_saver_payload(&state);
    }
    Ok(())
}

//壁紙ウィンドウをすべて閉じる（引数appはアプリ、引数stateは状態）
fn close_wallpaper_windows(app: &AppHandle, state: &AppState) {
    let labels: Vec<String> = {
        let mut guard = state.wallpaper_labels.lock().expect("壁紙のロック");
        std::mem::take(&mut *guard)
    };
    for label in labels {
        if let Some(window) = app.get_webview_window(&label) {
            let _ = window.close();
        }
    }
}

//電源の状態を見張るスレッドを始める（引数appはアプリ、全画面か電池のとき壁紙のエンジンを止める通知を送る）
fn start_power_thread(app: AppHandle) {
    std::thread::spawn(move || {
        let mut last_paused = false;
        loop {
            std::thread::sleep(std::time::Duration::from_secs(2));
            let state = app.state::<AppState>();
            if state.quitting.load(Ordering::SeqCst) {
                break;
            }
            let labels: Vec<String> = state
                .wallpaper_labels
                .lock()
                .expect("壁紙のロック")
                .clone();
            if labels.is_empty() {
                last_paused = false;
                continue;
            }
            let paused = platform::foreground_is_fullscreen() || platform::is_battery_powered();
            if paused != last_paused {
                last_paused = paused;
                for label in &labels {
                    let _ = app.emit_to(label.as_str(), "pixelwave-power", paused);
                }
            }
        }
    });
}

//壁紙を始める（引数appはアプリ、引数stateは状態、ディスプレイごとにウィンドウを作ってWorkerWへ貼る）
fn start_wallpaper(app: &AppHandle, state: &AppState) -> Result<(), String> {
    close_wallpaper_windows(app, state);
    let monitors = app.available_monitors().map_err(|e| e.to_string())?;
    let mut labels = Vec::new();
    for (i, monitor) in monitors.iter().enumerate() {
        let label = format!("wallpaper-{}", i);
        let scale = monitor.scale_factor();
        let pos = monitor.position();
        let size = monitor.size();
        #[cfg(target_os = "linux")]
        let page = "display.html?mode=fullscreen";
        #[cfg(not(target_os = "linux"))]
        let page = "display.html?mode=wallpaper";
        let window = WebviewWindowBuilder::new(app, &label, WebviewUrl::App(page.into()))
        .title("Pixel Wave")
        .decorations(false)
        .skip_taskbar(true)
        .resizable(false)
        .shadow(false)
        .focused(false)
        .position(pos.x as f64 / scale, pos.y as f64 / scale)
        .inner_size(size.width as f64 / scale, size.height as f64 / scale)
        .build()
        .map_err(|e| e.to_string())?;
        let _ = window.set_ignore_cursor_events(true);
        #[cfg(target_os = "linux")]
        {
            let _ = window.set_fullscreen(true);
        }
        #[cfg(windows)]
        {
            if let Ok(hwnd) = window.hwnd() {
                let _ = platform::wallpaper_attach(
                    hwnd.0 as isize,
                    pos.x,
                    pos.y,
                    size.width as i32,
                    size.height as i32,
                );
            }
        }
        #[cfg(target_os = "macos")]
        {
            if let Ok(ns_window) = window.ns_window() {
                let _ = platform::wallpaper_attach(
                    ns_window as isize,
                    pos.x,
                    pos.y,
                    size.width as i32,
                    size.height as i32,
                );
            }
        }
        labels.push(label);
    }
    *state.wallpaper_labels.lock().expect("壁紙のロック") = labels;
    if !state.power_thread_started.swap(true, Ordering::SeqCst) {
        start_power_thread(app.clone());
    }
    Ok(())
}

//壁紙の開始と停止（画面からの呼び出し、引数onは開始するなら真、自動起動の登録も連動させる）
//asyncにしている理由：Windowsでは、同期のコマンドの中でウィンドウを作るとデッドロックし、処理が返ってこない
#[tauri::command]
async fn set_wallpaper(app: AppHandle, state: State<'_, AppState>, on: bool) -> Result<(), String> {
    if on {
        start_wallpaper(&app, &state)?;
        #[cfg(not(target_os = "linux"))]
        {
            let _ = app.autolaunch().enable();
        }
    } else {
        close_wallpaper_windows(&app, &state);
        #[cfg(not(target_os = "linux"))]
        {
            let _ = app.autolaunch().disable();
        }
    }
    {
        let mut settings = state.settings.lock().expect("設定のロック");
        settings.wallpaper = on;
        settings::save(&state.data_dir, &settings)?;
    }
    let _ = app.emit_to("settings", "pixelwave-wallpaper", on);
    Ok(())
}

//スクリーンセーバーとして登録する（画面からの呼び出し、OSごとに実装を分ける）
#[tauri::command]
fn register_screensaver(app: AppHandle, state: State<'_, AppState>) -> Result<(), String> {
    register_screensaver_impl(&app, &state)
}

//Windowsでの登録（実行ファイルを.scrとして写し、レジストリへ書き、設定画面を開く）
#[cfg(target_os = "windows")]
fn register_screensaver_impl(_app: &AppHandle, state: &AppState) -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let dest = state.data_dir.join("PixelWave.scr");
    fs::copy(&exe, &dest).map_err(|e| e.to_string())?;
    platform::set_screensaver_registered(&dest)?;
    platform::open_screensaver_settings()
}

//macOSでの登録（セーバーが読める場所へ設定と絵を書き出し、アプリに入っている.saverを設置して設定画面を開く）
#[cfg(target_os = "macos")]
fn register_screensaver_impl(app: &AppHandle, state: &AppState) -> Result<(), String> {
    export_saver_payload(state)?;
    let resource_dir = app.path().resource_dir().map_err(|e| e.to_string())?;
    let saver = resource_dir.join("PixelWaveSaver.saver");
    if !saver.exists() {
        return Err(
            "スクリーンセーバーの部品がアプリに入っていません（macOS用ビルドで作られます）"
                .to_string(),
        );
    }
    platform::set_screensaver_registered(&saver)?;
    platform::open_screensaver_settings()
}

//その他のOSでの登録（未対応）
#[cfg(not(any(target_os = "windows", target_os = "macos")))]
fn register_screensaver_impl(_app: &AppHandle, _state: &AppState) -> Result<(), String> {
    Err("このOSではスクリーンセーバーはまだ対応していません".to_string())
}

//アプリを終了する（画面からの呼び出し、壁紙ウィンドウを片付けてから終わる）
#[tauri::command]
fn exit_app(app: AppHandle, state: State<'_, AppState>) {
    state.quitting.store(true, Ordering::SeqCst);
    close_wallpaper_windows(&app, &state);
    app.exit(0);
}

//設定ウィンドウを作る（引数appはアプリ）
fn create_settings_window(app: &AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("settings") {
        let _ = window.show();
        let _ = window.set_focus();
        return Ok(());
    }
    WebviewWindowBuilder::new(app, "settings", WebviewUrl::App("index.html".into()))
        .title("Pixel Wave")
        .inner_size(880.0, settings_window_height(app))
        .min_inner_size(640.0, 560.0)
        .center()
        .build()
        .map_err(|e| e.to_string())?;
    Ok(())
}

//設定ウィンドウの高さを決める（引数appはアプリ。760を上限にし、画面の高さからタスクバーとタイトルバーの分として80を引いた高さに収める）
fn settings_window_height(app: &AppHandle) -> f64 {
    const WANTED: f64 = 760.0;
    const MIN: f64 = 560.0;
    match app.primary_monitor() {
        Ok(Some(m)) => {
            let screen = m.size().height as f64 / m.scale_factor();
            (screen - 80.0).clamp(MIN, WANTED)
        }
        _ => WANTED,
    }
}

//常駐アイコンを作る（引数appはアプリ、メニューは設定と終了だけ）
fn build_tray(app: &AppHandle) -> Result<(), String> {
    let settings_item = MenuItem::with_id(app, "settings", "設定", true, None::<&str>)
        .map_err(|e| e.to_string())?;
    let quit_item =
        MenuItem::with_id(app, "quit", "終了", true, None::<&str>).map_err(|e| e.to_string())?;
    let menu = Menu::with_items(app, &[&settings_item, &quit_item]).map_err(|e| e.to_string())?;
    let icon = app
        .default_window_icon()
        .ok_or_else(|| "アイコンがありません".to_string())?
        .clone();
    TrayIconBuilder::with_id("main")
        .icon(icon)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "settings" => {
                let _ = create_settings_window(app);
            }
            "quit" => {
                let state = app.state::<AppState>();
                state.quitting.store(true, Ordering::SeqCst);
                close_wallpaper_windows(app, &state);
                app.exit(0);
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                let _ = create_settings_window(tray.app_handle());
            }
        })
        .build(app)
        .map_err(|e| e.to_string())?;
    Ok(())
}

//入口（引数のモードで動きを変え、プレビューのときはすぐ終了する）
pub fn run() {
    let argv: Vec<String> = std::env::args().collect();
    let mode = parse_mode(&argv);
    if mode == RunMode::Preview {
        return;
    }

    let mut builder = tauri::Builder::default();
    //設定画面としての起動は1つだけにする（2回目の起動では、動いている方の設定画面を前に出して終わる）
    //スクリーンセーバー（/s）はWindowsが常駐中のアプリとは別に起動するので、対象にしない
    if mode == RunMode::Settings {
        builder = builder.plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            let _ = create_settings_window(app);
        }));
    }
    let result = builder
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .invoke_handler(tauri::generate_handler![
            get_settings,
            save_settings,
            get_data_dir,
            get_mode,
            get_platform,
            add_user_image,
            remove_user_image,
            set_wallpaper,
            register_screensaver,
            exit_app
        ])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                if window.label() == "settings" {
                    let state = window.state::<AppState>();
                    if state.quitting.load(Ordering::SeqCst) {
                        //終了中なのでそのまま閉じる
                    } else if state.tray_available.load(Ordering::SeqCst) {
                        api.prevent_close();
                        let _ = window.hide();
                    } else {
                        //常駐アイコンを出せない環境では、設定画面を閉じたら終了する
                        state.quitting.store(true, Ordering::SeqCst);
                        close_wallpaper_windows(window.app_handle(), &state);
                        window.app_handle().exit(0);
                    }
                }
            }
        })
        .setup(move |app| {
            let handle = app.handle().clone();
            let data_dir = handle
                .path()
                .app_data_dir()
                .map_err(|e| e.to_string())?;
            fs::create_dir_all(data_dir.join("user-images")).map_err(|e| e.to_string())?;
            let defaults: Vec<String> = BUILTIN_IDS.iter().map(|s| s.to_string()).collect();
            let loaded = settings::load(&data_dir, defaults);
            let wallpaper_was_on = loaded.wallpaper;
            app.manage(AppState {
                mode,
                data_dir,
                settings: Mutex::new(loaded),
                quitting: AtomicBool::new(false),
                wallpaper_labels: Mutex::new(Vec::new()),
                power_thread_started: AtomicBool::new(false),
                tray_available: AtomicBool::new(true),
            });

            #[cfg(target_os = "linux")]
            {
                //Linuxの全画面表示は再起動後に自動で開かない（記録だけ初期化する）
                let state = handle.state::<AppState>();
                let mut current = state.settings.lock().expect("設定のロック");
                if current.wallpaper {
                    current.wallpaper = false;
                    let snapshot = current.clone();
                    drop(current);
                    let _ = settings::save(&state.data_dir, &snapshot);
                }
            }

            #[cfg(target_os = "macos")]
            {
                //Dockにアイコンを出さず、メニューバーの常駐アイコンだけで動かす
                app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            }

            match mode {
                RunMode::Screensaver => {
                    let monitors = handle.available_monitors()?;
                    for (i, monitor) in monitors.iter().enumerate() {
                        let scale = monitor.scale_factor();
                        let pos = monitor.position();
                        let size = monitor.size();
                        let window = WebviewWindowBuilder::new(
                            &handle,
                            format!("saver-{}", i),
                            WebviewUrl::App("display.html?mode=screensaver".into()),
                        )
                        .title("Pixel Wave")
                        .decorations(false)
                        .skip_taskbar(true)
                        .resizable(false)
                        .shadow(false)
                        .position(pos.x as f64 / scale, pos.y as f64 / scale)
                        .inner_size(size.width as f64 / scale, size.height as f64 / scale)
                        .build()?;
                        window.set_fullscreen(true)?;
                    }
                }
                _ => {
                    create_settings_window(&handle).map_err(|e| e)?;
                    if let Err(e) = build_tray(&handle) {
                        //常駐アイコンを出せない環境でも設定画面から操作できるように、失敗しても続ける
                        eprintln!("常駐アイコンを作れませんでした: {}", e);
                        handle
                            .state::<AppState>()
                            .tray_available
                            .store(false, Ordering::SeqCst);
                    }
                    #[cfg(not(target_os = "linux"))]
                    {
                        if wallpaper_was_on {
                            let state = handle.state::<AppState>();
                            let _ = start_wallpaper(&handle, &state);
                        }
                    }
                }
            }
            Ok(())
        })
        .build(tauri::generate_context!());

    if let Ok(app) = result {
        app.run(|_, _| {});
    }
}
