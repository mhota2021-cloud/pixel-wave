//実行ファイルの入口（本体はライブラリ側にある）
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    pixel_wave_lib::run()
}
