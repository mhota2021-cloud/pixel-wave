//! 素材情報（credits.json）の読み込みと、バックグラウンドでの画像ロード

use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use serde::Deserialize;

use crate::cache;
use crate::dotart::{self, Crop, Grid};
use crate::i18n::Lang;
use crate::settings::AppSettings;
use crate::wic;

#[derive(Clone, Debug, Deserialize)]
pub struct CreditItem {
    pub id: String,
    pub file: String,
    pub title: String,
    #[serde(default)]
    pub title_en: Option<String>,
    #[serde(default)]
    pub artist: String,
    #[serde(default)]
    pub artist_en: Option<String>,
    #[serde(default)]
    pub crop: Crop,
}

#[derive(Clone, Debug)]
pub struct PaintingSpec {
    pub id: String,
    pub path: PathBuf,
    pub crop: Crop,
}

#[derive(Clone, Debug)]
pub struct UiItem {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub path: PathBuf,
    pub crop: Crop,
    pub builtin: bool,
}

pub fn paintings_dir(exe_dir: &Path) -> PathBuf {
    let candidates = [
        exe_dir.join("assets").join("paintings"),
        exe_dir.join("..").join("assets").join("paintings"),
        exe_dir.join("..").join("..").join("assets").join("paintings"),
        exe_dir.join("..").join("..").join("..").join("assets").join("paintings"),
    ];
    for c in &candidates {
        if c.join("credits.json").exists() {
            return c.clone();
        }
    }
    candidates[0].clone()
}

pub fn load_credits(paintings_dir: &Path) -> Vec<CreditItem> {
    let Ok(raw) = fs::read_to_string(paintings_dir.join("credits.json")) else {
        return Vec::new();
    };
    serde_json::from_str(&raw).unwrap_or_default()
}

pub fn enabled_paintings(
    settings: &AppSettings,
    credits: &[CreditItem],
    paintings_dir: &Path,
    data_dir: &Path,
) -> Vec<PaintingSpec> {
    let mut out = Vec::new();
    for u in &settings.user_images {
        if !settings.enabled.contains(&u.id) {
            continue;
        }
        let path = data_dir.join("user-images").join(&u.file);
        if path.exists() {
            out.push(PaintingSpec { id: u.id.clone(), path, crop: u.crop.clone() });
        }
    }
    for c in credits {
        if settings.hidden_builtin.contains(&c.id) || !settings.enabled.contains(&c.id) {
            continue;
        }
        let path = paintings_dir.join(&c.file);
        if path.exists() {
            let crop = settings.builtin_crop.get(&c.id).cloned().unwrap_or_else(|| c.crop.clone());
            out.push(PaintingSpec { id: c.id.clone(), path, crop });
        }
    }
    out
}

pub fn ui_items(
    settings: &AppSettings,
    credits: &[CreditItem],
    paintings_dir: &Path,
    data_dir: &Path,
    lang: Lang,
) -> Vec<UiItem> {
    let mut out = Vec::new();
    for u in &settings.user_images {
        out.push(UiItem {
            id: u.id.clone(),
            title: u.title.clone(),
            artist: String::new(),
            path: data_dir.join("user-images").join(&u.file),
            crop: u.crop.clone(),
            builtin: false,
        });
    }
    let en = lang == Lang::En;
    for c in credits {
        if settings.hidden_builtin.contains(&c.id) {
            continue;
        }
        let crop = settings.builtin_crop.get(&c.id).cloned().unwrap_or_else(|| c.crop.clone());
        let title = if en { c.title_en.as_ref().unwrap_or(&c.title) } else { &c.title }.clone();
        let artist = if en { c.artist_en.as_ref().unwrap_or(&c.artist) } else { &c.artist }.clone();
        out.push(UiItem {
            id: c.id.clone(),
            title,
            artist,
            path: paintings_dir.join(&c.file),
            crop,
            builtin: true,
        });
    }
    out
}

pub fn crop_key(crop: &Crop) -> String {
    match crop {
        Crop::Named(s) => s.clone(),
        Crop::Rect { x, y, w, h } => format!("{x:.4}_{y:.4}_{w:.4}_{h:.4}"),
    }
}

fn file_mtime_secs(path: &Path) -> u64 {
    fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub fn load_grid_one(spec: &PaintingSpec, cols: usize, rows: usize, cache_dir: &Path) -> Option<Grid> {
    let mtime = file_mtime_secs(&spec.path);
    let cache_id = format!("{}_{}", spec.id, crop_key(&spec.crop));
    if let Some(g) = cache::read(cache_dir, &cache_id, mtime, cols, rows) {
        return Some(g);
    }
    let dots = wic::decode_dots_rgb(&spec.path, cols as u32, rows as u32, &spec.crop)?;
    let grid = dotart::kmeans(&dots, 16, 42);
    let _ = cache::write(cache_dir, &cache_id, mtime, cols, rows, &grid);
    Some(grid)
}
