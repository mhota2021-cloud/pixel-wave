//! ドット絵化結果のバイナリキャッシュ（2回目以降は即座に読み込む）

use std::fs;
use std::path::{Path, PathBuf};

use crate::dotart::Grid;

const MAGIC: &[u8; 4] = b"PWC1";

pub fn file_name(id: &str, mtime_secs: u64, cols: usize, rows: usize) -> String {
    let safe: String = id
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '_' || c == '-' { c } else { '_' })
        .collect();
    format!("{safe}_{mtime_secs}_{cols}x{rows}.pwc")
}

fn cache_path(dir: &Path, id: &str, mtime_secs: u64, cols: usize, rows: usize) -> PathBuf {
    dir.join(file_name(id, mtime_secs, cols, rows))
}

pub fn read(dir: &Path, id: &str, mtime_secs: u64, cols: usize, rows: usize) -> Option<Grid> {
    let bytes = fs::read(cache_path(dir, id, mtime_secs, cols, rows)).ok()?;
    if bytes.len() < 9 || &bytes[0..4] != MAGIC {
        return None;
    }
    let palette_len = bytes[4] as usize;
    let count = u32::from_le_bytes(bytes[5..9].try_into().ok()?) as usize;
    if count != cols * rows || palette_len == 0 {
        return None;
    }
    let expected = 9 + palette_len * 3 + count;
    if bytes.len() != expected {
        return None;
    }
    let mut palette = Vec::with_capacity(palette_len);
    for i in 0..palette_len {
        let o = 9 + i * 3;
        palette.push([bytes[o], bytes[o + 1], bytes[o + 2]]);
    }
    let indices = bytes[9 + palette_len * 3..].to_vec();
    if indices.iter().any(|&idx| (idx as usize) >= palette_len) {
        return None;
    }
    Some(Grid { palette, indices })
}

pub fn write(dir: &Path, id: &str, mtime_secs: u64, cols: usize, rows: usize, grid: &Grid) -> std::io::Result<()> {
    fs::create_dir_all(dir)?;
    let palette_len = grid.palette.len().min(255);
    let mut out = Vec::with_capacity(9 + palette_len * 3 + grid.indices.len());
    out.extend_from_slice(MAGIC);
    out.push(palette_len as u8);
    out.extend_from_slice(&(grid.indices.len() as u32).to_le_bytes());
    for c in &grid.palette[..palette_len] {
        out.extend_from_slice(c);
    }
    out.extend_from_slice(&grid.indices);
    let path = cache_path(dir, id, mtime_secs, cols, rows);
    let tmp = dir.join(format!("{}.tmp", file_name(id, mtime_secs, cols, rows)));
    fs::write(&tmp, &out)?;
    fs::rename(tmp, path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_and_invalid_size() {
        let dir = std::env::temp_dir().join("pw_test_cache");
        let _ = fs::remove_dir_all(&dir);
        let grid = Grid { palette: vec![[1, 2, 3], [250, 200, 100]], indices: vec![0, 1, 1, 0, 0, 1] };
        write(&dir, "test:1", 12345, 3, 2, &grid).unwrap();
        assert_eq!(read(&dir, "test:1", 12345, 3, 2), Some(grid));
        assert_eq!(read(&dir, "test:1", 12345, 2, 2), None);
        let _ = fs::remove_dir_all(&dir);
    }
}
