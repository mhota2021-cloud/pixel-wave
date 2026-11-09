//Rust側とのやり取りをまとめたファイル（Tauriの外では仮の実装で動く）
import { convertFileSrc, invoke } from "@tauri-apps/api/core";

//追加した画像の情報（idは識別子、fileはデータフォルダ内のファイル名、titleは表示名）
export interface UserImage {
  id: string;
  file: string;
  title: string;
}

//設定の中身（enabledは使う絵のidの一覧、userImagesは追加した画像、wallpaperは壁紙の状態）
export interface SettingsData {
  enabled: string[];
  userImages: UserImage[];
  wallpaper: boolean;
}

//Tauriの中で動いているかどうか
export function isTauri(): boolean {
  return "__TAURI_INTERNALS__" in window;
}

//仮の設定（Tauriの外で画面を確認するときに使う）
let mockSettings: SettingsData = { enabled: [], userImages: [], wallpaper: false };
let mockDataDir = "";

//設定の初期値を入れる（引数sは初期設定、Tauriの外のときだけ使う）
export function setMockSettings(s: SettingsData): void {
  mockSettings = s;
}

//設定を読む
export async function getSettings(): Promise<SettingsData> {
  if (!isTauri()) return mockSettings;
  return invoke<SettingsData>("get_settings");
}

//設定を保存する（引数sは設定）
export async function saveSettings(s: SettingsData): Promise<void> {
  if (!isTauri()) {
    mockSettings = s;
    return;
  }
  await invoke("save_settings", { settings: s });
}

//データフォルダの場所を読む
export async function getDataDir(): Promise<string> {
  if (!isTauri()) return mockDataDir;
  return invoke<string>("get_data_dir");
}

//動いているOSを読む（windowsかmacosかlinuxのどれか、URLの引数があればそれを優先する）
export async function getPlatform(): Promise<string> {
  const fromUrl = new URLSearchParams(window.location.search).get("platform");
  if (fromUrl) return fromUrl;
  if (!isTauri()) return "windows";
  return invoke<string>("get_platform");
}

//全画面表示を止める（Linux用、表示ウィンドウを閉じて設定側のボタン表示も戻す）
export async function stopFullscreen(): Promise<void> {
  if (!isTauri()) return;
  await invoke("set_wallpaper", { on: false });
}

//起動モードを読む（settingsかwallpaperかscreensaverのどれか、URLの引数があればそれを優先する）
export async function getMode(): Promise<string> {
  const fromUrl = new URLSearchParams(window.location.search).get("mode");
  if (fromUrl) return fromUrl;
  if (!isTauri()) return "settings";
  return invoke<string>("get_mode");
}

//画像を追加する（引数pathは元の画像の場所、データフォルダへ写して登録する）
export async function addUserImage(path: string): Promise<UserImage> {
  return invoke<UserImage>("add_user_image", { path });
}

//画像を削除する（引数idは画像の識別子）
export async function removeUserImage(id: string): Promise<void> {
  await invoke("remove_user_image", { id });
}

//壁紙の開始と停止（引数onは開始するなら真）
export async function setWallpaper(on: boolean): Promise<void> {
  if (!isTauri()) {
    mockSettings = { ...mockSettings, wallpaper: on };
    return;
  }
  await invoke("set_wallpaper", { on });
}

//スクリーンセーバーとして登録する
export async function registerScreensaver(): Promise<void> {
  await invoke("register_screensaver");
}

//アプリを終了する
export async function exitApp(): Promise<void> {
  if (!isTauri()) return;
  await invoke("exit_app");
}

//追加した画像の表示用URLを作る（引数dataDirはデータフォルダ、引数fileはファイル名）
export function userImageSrc(dataDir: string, file: string): string {
  if (!isTauri()) return file;
  return convertFileSrc(`${dataDir}/user-images/${file}`);
}
