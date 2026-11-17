//! 設定ファイル（settings.json）の読み書き（旧Ruby版と互換）

use std::collections::HashMap;
use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::dotart::Crop;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct UserImage {
    pub id: String,
    pub file: String,
    pub title: String,
    #[serde(default)]
    pub crop: Crop,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    #[serde(default)]
    pub enabled: Vec<String>,
    #[serde(default)]
    pub user_images: Vec<UserImage>,
    #[serde(default)]
    pub wallpaper: bool,
    #[serde(default = "default_true")]
    pub pause_on_battery: bool,
    #[serde(default = "default_true")]
    pub autostart: bool,
    #[serde(default)]
    pub builtin_crop: HashMap<String, Crop>,
    #[serde(default)]
    pub hidden_builtin: Vec<String>,
    #[serde(default = "default_mode")]
    pub mode: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lang: Option<String>,
}

fn default_true() -> bool {
    true
}

fn default_mode() -> String {
    "dotart".to_string()
}

impl AppSettings {
    pub fn defaults(builtin_ids: &[String]) -> Self {
        Self {
            enabled: builtin_ids.to_vec(),
            user_images: Vec::new(),
            wallpaper: false,
            pause_on_battery: true,
            autostart: true,
            builtin_crop: HashMap::new(),
            hidden_builtin: Vec::new(),
            mode: default_mode(),
            lang: None,
        }
    }

    pub fn is_normal_mode(&self) -> bool {
        self.mode == "normal"
    }

    /// 設定を読む。壊れていたら退避して初期値を返す
    pub fn load(dir: &Path, builtin_ids: &[String]) -> Self {
        let path = dir.join("settings.json");
        let Ok(raw) = fs::read_to_string(&path) else {
            return Self::defaults(builtin_ids);
        };
        match serde_json::from_str::<AppSettings>(&raw) {
            Ok(mut s) => {
                if s.mode != "normal" {
                    s.mode = "dotart".to_string();
                }
                s
            }
            Err(_) => {
                let _ = fs::rename(&path, dir.join("settings.broken.json"));
                Self::defaults(builtin_ids)
            }
        }
    }

    pub fn save(&self, dir: &Path) -> std::io::Result<()> {
        fs::create_dir_all(dir)?;
        let json = serde_json::to_string(self)?;
        let tmp = dir.join("settings.json.tmp");
        fs::write(&tmp, json)?;
        fs::rename(tmp, dir.join("settings.json"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn load_missing_returns_defaults() {
        let dir = std::env::temp_dir().join("pw_test_settings_missing");
        let _ = fs::remove_dir_all(&dir);
        let ids = vec!["a".into(), "b".into()];
        let s = AppSettings::load(&dir, &ids);
        assert_eq!(s.enabled, ids);
        assert!(s.autostart);
        assert!(!s.wallpaper);
        assert_eq!(s.mode, "dotart");
    }

    #[test]
    fn load_corrupt_backs_up_and_returns_defaults() {
        let dir = std::env::temp_dir().join("pw_test_settings_corrupt");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("settings.json"), "{broken").unwrap();
        let s = AppSettings::load(&dir, &["x".into()]);
        assert_eq!(s.enabled, vec!["x"]);
        assert!(dir.join("settings.broken.json").exists());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn save_and_reload_round_trip() {
        let dir = std::env::temp_dir().join("pw_test_settings_rt");
        let _ = fs::remove_dir_all(&dir);
        let mut s = AppSettings::defaults(&["hokusai".into()]);
        s.wallpaper = true;
        s.mode = "normal".into();
        s.lang = Some("en".into());
        s.builtin_crop.insert("hokusai".into(), Crop::rect(0.1, 0.2, 0.7, 0.6));
        s.save(&dir).unwrap();
        let loaded = AppSettings::load(&dir, &["hokusai".into()]);
        assert_eq!(s, loaded);
        let _ = fs::remove_dir_all(&dir);
    }
}
