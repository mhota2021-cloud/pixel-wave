//ビルド時の処理（Tauriの標準の処理と、名画の一覧をcredits.jsonから作る処理）
use std::path::PathBuf;

fn main() {
    generate_builtins();
    tauri_build::build()
}

//名画の一覧をassets/paintings/credits.jsonから作り、OUT_DIRのbuiltins.rsに書き出す（絵を差し替えるときはcredits.jsonだけを直せばよい）
fn generate_builtins() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let dir = manifest.join("../../assets/paintings").canonicalize().expect("assets/paintingsが見つからない");
    let credits_path = dir.join("credits.json");
    println!("cargo:rerun-if-changed={}", credits_path.display());
    let text = std::fs::read_to_string(&credits_path).expect("credits.jsonを読めない");
    let list: Vec<serde_json::Value> = serde_json::from_str(&text).expect("credits.jsonの形が正しくない");

    let mut ids = String::new();
    let mut infos = String::new();
    for c in &list {
        let id = c["id"].as_str().expect("idが無い");
        let file = c["file"].as_str().expect("fileが無い");
        let crop = c["crop"].as_str().unwrap_or("center");
        let path = dir.join(file);
        println!("cargo:rerun-if-changed={}", path.display());
        ids.push_str(&format!("    {:?},\n", id));
        infos.push_str(&format!(
            "    BuiltinInfo {{ id: {:?}, file: {:?}, crop: {:?}, bytes: include_bytes!({:?}) }},\n",
            id,
            file,
            crop,
            path.to_string_lossy()
        ));
    }
    let n = list.len();
    let code = format!(
        "const BUILTIN_IDS: [&str; {n}] = [\n{ids}];\n\n#[cfg(target_os = \"macos\")]\nconst BUILTINS: [BuiltinInfo; {n}] = [\n{infos}];\n"
    );
    let out = PathBuf::from(std::env::var("OUT_DIR").unwrap()).join("builtins.rs");
    std::fs::write(out, code).expect("builtins.rsを書けない");
}
