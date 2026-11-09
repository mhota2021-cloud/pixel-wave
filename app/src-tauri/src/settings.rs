//設定ファイルの読み書き（settings.jsonを1つだけ使い、壊れていたら退避して初期設定で動く）
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

//追加した画像の情報（idは識別子、fileはデータフォルダ内のファイル名、titleは表示名）
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserImage {
    pub id: String,
    pub file: String,
    pub title: String,
}

//設定の中身（enabledは使う絵のidの一覧、user_imagesは追加した画像、wallpaperは壁紙の状態）
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub enabled: Vec<String>,
    pub user_images: Vec<UserImage>,
    pub wallpaper: bool,
}

impl Settings {
    //初期設定を作る（引数default_enabledは素材の絵のidの一覧）
    pub fn defaults(default_enabled: Vec<String>) -> Settings {
        Settings {
            enabled: default_enabled,
            user_images: Vec::new(),
            wallpaper: false,
        }
    }
}

//設定ファイルの場所を返す（引数dirはデータフォルダ）
pub fn settings_path(dir: &Path) -> PathBuf {
    dir.join("settings.json")
}

//設定を読む（引数dirはデータフォルダ、引数default_enabledは素材の絵のidの一覧、無いときと壊れているときは初期設定を返し、壊れたファイルはsettings.broken.jsonへ退避する）
pub fn load(dir: &Path, default_enabled: Vec<String>) -> Settings {
    let path = settings_path(dir);
    let text = match fs::read_to_string(&path) {
        Ok(text) => text,
        Err(_) => return Settings::defaults(default_enabled),
    };
    match serde_json::from_str::<Settings>(&text) {
        Ok(settings) => settings,
        Err(_) => {
            let broken = dir.join("settings.broken.json");
            let _ = fs::rename(&path, &broken);
            Settings::defaults(default_enabled)
        }
    }
}

//設定を書く（引数dirはデータフォルダ、引数settingsは設定、フォルダが無ければ作る）
pub fn save(dir: &Path, settings: &Settings) -> Result<(), String> {
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let text = serde_json::to_string_pretty(settings).map_err(|e| e.to_string())?;
    fs::write(settings_path(dir), text).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    //テスト用の一時フォルダを作る（引数nameは識別用の名前）
    fn temp_dir(name: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let dir = std::env::temp_dir().join(format!("pixelwave_{}_{}", name, nanos));
        fs::create_dir_all(&dir).expect("一時フォルダを作れる");
        dir
    }

    #[test]
    fn 保存して読み直すと一致する() {
        let dir = temp_dir("roundtrip");
        let mut settings = Settings::defaults(vec!["a".to_string(), "b".to_string()]);
        settings.user_images.push(UserImage {
            id: "user_1".to_string(),
            file: "user_1.jpg".to_string(),
            title: "写真".to_string(),
        });
        settings.wallpaper = true;
        save(&dir, &settings).expect("保存できる");
        let loaded = load(&dir, vec!["x".to_string()]);
        assert_eq!(loaded, settings);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn ファイルが無いときは初期設定() {
        let dir = temp_dir("missing");
        let loaded = load(&dir, vec!["a".to_string()]);
        assert_eq!(loaded.enabled, vec!["a".to_string()]);
        assert!(!loaded.wallpaper);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn 壊れたファイルは退避して初期設定() {
        let dir = temp_dir("broken");
        fs::write(settings_path(&dir), "{これは壊れたJSON").expect("書ける");
        let loaded = load(&dir, vec!["a".to_string()]);
        assert_eq!(loaded.enabled, vec!["a".to_string()]);
        assert!(dir.join("settings.broken.json").exists());
        assert!(!settings_path(&dir).exists());
        let _ = fs::remove_dir_all(&dir);
    }
}
