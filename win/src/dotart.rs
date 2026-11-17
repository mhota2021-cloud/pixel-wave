//! ドット絵化と波の共通部品（OSに依存しない純粋な関数だけを置く）

use serde::{Deserialize, Serialize};

/// 切り取り指定（位置の名前か、画像に対する割合の矩形）
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Crop {
    Rect {
        #[serde(default)]
        x: f64,
        #[serde(default)]
        y: f64,
        #[serde(default = "one")]
        w: f64,
        #[serde(default = "one")]
        h: f64,
    },
    Named(String),
}

fn one() -> f64 {
    1.0
}

impl Default for Crop {
    fn default() -> Self {
        Crop::Named("center".to_string())
    }
}

impl Crop {
    /// 割合の矩形を作る（小数第4位で丸める。設定ファイルの形を旧版と揃える）
    pub fn rect(x: f64, y: f64, w: f64, h: f64) -> Crop {
        let r = |v: f64| (v * 10000.0).round() / 10000.0;
        Crop::Rect { x: r(x), y: r(y), w: r(w), h: r(h) }
    }
}

/// 色（赤・緑・青）
pub type Rgb = [u8; 3];

/// ドット絵1枚分（16色のパレットと、ドットごとのパレット番号）
#[derive(Clone, Debug, PartialEq)]
pub struct Grid {
    pub palette: Vec<Rgb>,
    pub indices: Vec<u8>,
}

impl Grid {
    pub fn color(&self, i: usize) -> Rgb {
        self.palette[self.indices[i] as usize]
    }
}

/// 切り抜く範囲を返す（元の大きさ、目標の縦横比、切り取り指定から、左上のxとyと幅と高さ）
pub fn croprect(src_w: u32, src_h: u32, target_w: u32, target_h: u32, crop: &Crop) -> (u32, u32, u32, u32) {
    let (sw, sh) = (src_w.max(1) as f64, src_h.max(1) as f64);
    match crop {
        Crop::Rect { x, y, w, h } => {
            let px = ((sw * x).round() as i64).clamp(0, src_w as i64 - 1);
            let py = ((sh * y).round() as i64).clamp(0, src_h as i64 - 1);
            let pw = ((sw * w).round() as i64).max(1).min(src_w as i64 - px);
            let ph = ((sh * h).round() as i64).max(1).min(src_h as i64 - py);
            (px as u32, py as u32, pw as u32, ph as u32)
        }
        Crop::Named(name) => {
            let target_aspect = target_w.max(1) as f64 / target_h.max(1) as f64;
            let src_aspect = sw / sh;
            if src_aspect > target_aspect {
                let w = ((sh * target_aspect).round() as u32).clamp(1, src_w);
                ((src_w - w) / 2, 0, w, src_h)
            } else {
                let h = ((sw / target_aspect).round() as u32).clamp(1, src_h);
                let y = match name.as_str() {
                    "top" => 0,
                    "bottom" => src_h - h,
                    _ => (src_h - h) / 2,
                };
                (0, y, src_w, h)
            }
        }
    }
}

/// 決定論的な乱数（SplitMix64。種が同じなら、どのプロセスでも同じ列になる）
pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Rng {
        Rng(seed)
    }

    pub fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// 0以上1未満の小数
    pub fn next_f64(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
    }

    /// 0以上n未満の整数
    pub fn below(&mut self, n: usize) -> usize {
        (self.next_f64() * n as f64) as usize % n.max(1)
    }
}

fn dist2(a: &[f64; 3], b: &[f64; 3]) -> f64 {
    let (dr, dg, db) = (a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    dr * dr + dg * dg + db * db
}

fn nearest(color: &[f64; 3], centers: &[[f64; 3]]) -> usize {
    let mut best = 0;
    let mut best_d = f64::MAX;
    for (i, c) in centers.iter().enumerate() {
        let d = dist2(color, c);
        if d < best_d {
            best_d = d;
            best = i;
        }
    }
    best
}

/// k-meansで色を減らす（代表色は間引いた2000画素で決め、最後に全部を割り当てる）
pub fn kmeans(pixels: &[Rgb], count: usize, seed: u64) -> Grid {
    if pixels.is_empty() {
        return Grid { palette: vec![[0, 0, 0]], indices: vec![] };
    }
    let all: Vec<[f64; 3]> = pixels.iter().map(|p| [p[0] as f64, p[1] as f64, p[2] as f64]).collect();
    let sample: Vec<[f64; 3]> = if all.len() > 2000 {
        let step = all.len() as f64 / 2000.0;
        let mut s = Vec::with_capacity(2001);
        let mut i = 0.0;
        while (i as usize) < all.len() {
            s.push(all[i as usize]);
            i += step;
        }
        s
    } else {
        all.clone()
    };

    // k-means++で最初の代表色を選ぶ
    let mut rng = Rng::new(seed);
    let mut centers = vec![sample[rng.below(sample.len())]];
    let mut dists: Vec<f64> = sample.iter().map(|p| dist2(p, &centers[0])).collect();
    while centers.len() < count {
        let total: f64 = dists.iter().sum();
        if total <= 0.0 {
            break;
        }
        let r = rng.next_f64() * total;
        let mut acc = 0.0;
        let mut chosen = sample[sample.len() - 1];
        for (idx, p) in sample.iter().enumerate() {
            acc += dists[idx];
            if acc >= r {
                chosen = *p;
                break;
            }
        }
        centers.push(chosen);
        for (idx, p) in sample.iter().enumerate() {
            let d = dist2(p, &chosen);
            if d < dists[idx] {
                dists[idx] = d;
            }
        }
    }

    // 割り当てが変わらなくなるまで（最大100回）繰り返す
    let mut labels = vec![usize::MAX; sample.len()];
    for _ in 0..100 {
        let mut changed = false;
        for (i, p) in sample.iter().enumerate() {
            let best = nearest(p, &centers);
            if labels[i] != best {
                labels[i] = best;
                changed = true;
            }
        }
        let mut sums = vec![[0.0f64; 4]; centers.len()];
        for (i, p) in sample.iter().enumerate() {
            let s = &mut sums[labels[i]];
            s[0] += p[0];
            s[1] += p[1];
            s[2] += p[2];
            s[3] += 1.0;
        }
        for (c, s) in centers.iter_mut().zip(sums.iter()) {
            if s[3] > 0.0 {
                *c = [s[0] / s[3], s[1] / s[3], s[2] / s[3]];
            }
        }
        if !changed {
            break;
        }
    }

    let palette = centers
        .iter()
        .map(|c| [c[0].round().clamp(0.0, 255.0) as u8, c[1].round().clamp(0.0, 255.0) as u8, c[2].round().clamp(0.0, 255.0) as u8])
        .collect();
    let indices = all.iter().map(|p| nearest(p, &centers) as u8).collect();
    Grid { palette, indices }
}

fn bezier_component(t: f64, a: f64, b: f64) -> f64 {
    let u = 1.0 - t;
    3.0 * u * u * t * a + 3.0 * u * t * t * b + t * t * t
}

/// 3次ベジェ曲線のイージング（xに対応するyを二分探索で求める）
pub fn cubic_bezier_easing(x1: f64, y1: f64, x2: f64, y2: f64, x: f64) -> f64 {
    if x <= 0.0 {
        return 0.0;
    }
    if x >= 1.0 {
        return 1.0;
    }
    let (mut lo, mut hi, mut t) = (0.0, 1.0, x);
    for _ in 0..50 {
        t = (lo + hi) / 2.0;
        if bezier_component(t, x1, x2) < x {
            lo = t;
        } else {
            hi = t;
        }
    }
    bezier_component(t, y1, y2)
}

/// ゆっくり始まりゆっくり終わるイージング（cubic-bezier(0.37, 0, 0.63, 1)）
pub fn ease_in_out(x: f64) -> f64 {
    cubic_bezier_easing(0.37, 0.0, 0.63, 1.0, x)
}

pub fn distance(x1: f64, y1: f64, x2: f64, y2: f64) -> f64 {
    ((x1 - x2).powi(2) + (y1 - y2).powi(2)).sqrt()
}

/// 一番遠い角までの距離
pub fn farthest_corner_distance(px: f64, py: f64, w: f64, h: f64) -> f64 {
    [distance(px, py, 0.0, 0.0), distance(px, py, w, 0.0), distance(px, py, 0.0, h), distance(px, py, w, h)]
        .into_iter()
        .fold(0.0, f64::max)
}

/// 外周上の点（tは0以上1未満の割合）
pub fn perimeter_point(w: f64, h: f64, t: f64) -> (f64, f64) {
    let p = t * 2.0 * (w + h);
    if p < w {
        (p, 0.0)
    } else if p < w + h {
        (w, p - w)
    } else if p < 2.0 * w + h {
        (p - w - h, h)
    } else {
        (0.0, p - 2.0 * w - h)
    }
}

/// 色を白へ寄せる
pub fn blend_toward_white(c: Rgb, ratio: f64) -> Rgb {
    let f = |v: u8| (v as f64 + (255.0 - v as f64) * ratio).round().clamp(0.0, 255.0) as u8;
    [f(c[0]), f(c[1]), f(c[2])]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn croprect_center_wide_source() {
        assert_eq!(croprect(400, 100, 16, 9, &Crop::default()), (111, 0, 178, 100));
    }

    #[test]
    fn croprect_top_and_bottom_tall_source() {
        let top = croprect(90, 400, 16, 9, &Crop::Named("top".into()));
        let bottom = croprect(90, 400, 16, 9, &Crop::Named("bottom".into()));
        assert_eq!(top, (0, 0, 90, 51));
        assert_eq!(bottom, (0, 349, 90, 51));
    }

    #[test]
    fn croprect_rect_is_clamped() {
        let r = croprect(100, 100, 16, 9, &Crop::Rect { x: 0.9, y: -0.5, w: 0.5, h: 2.0 });
        assert_eq!(r, (90, 0, 10, 100));
    }

    #[test]
    fn crop_json_round_trip() {
        let named: Crop = serde_json::from_str("\"top\"").unwrap();
        assert_eq!(named, Crop::Named("top".into()));
        let rect: Crop = serde_json::from_str(r#"{"x":0.1,"y":0.2,"w":0.3,"h":0.4}"#).unwrap();
        assert_eq!(rect, Crop::Rect { x: 0.1, y: 0.2, w: 0.3, h: 0.4 });
        let partial: Crop = serde_json::from_str(r#"{"y":0.5}"#).unwrap();
        assert_eq!(partial, Crop::Rect { x: 0.0, y: 0.5, w: 1.0, h: 1.0 });
    }

    #[test]
    fn kmeans_is_deterministic_and_limits_colors() {
        let mut pixels = Vec::new();
        for i in 0..5000u32 {
            pixels.push([(i % 256) as u8, (i * 7 % 256) as u8, (i * 13 % 256) as u8]);
        }
        let a = kmeans(&pixels, 16, 42);
        let b = kmeans(&pixels, 16, 42);
        assert_eq!(a, b);
        assert!(a.palette.len() <= 16);
        assert_eq!(a.indices.len(), pixels.len());
    }

    #[test]
    fn kmeans_single_color() {
        let g = kmeans(&[[10, 20, 30]; 50], 16, 42);
        assert_eq!(g.palette, vec![[10, 20, 30]]);
        assert!(g.indices.iter().all(|&i| i == 0));
    }

    #[test]
    fn easing_end_points_and_symmetry() {
        assert_eq!(ease_in_out(0.0), 0.0);
        assert_eq!(ease_in_out(1.0), 1.0);
        assert!((ease_in_out(0.5) - 0.5).abs() < 1e-6);
        assert!((ease_in_out(0.25) + ease_in_out(0.75) - 1.0).abs() < 1e-6);
    }

    #[test]
    fn perimeter_covers_all_sides() {
        assert_eq!(perimeter_point(100.0, 50.0, 0.0), (0.0, 0.0));
        assert_eq!(perimeter_point(100.0, 50.0, 0.4), (100.0, 20.0));
        assert_eq!(perimeter_point(100.0, 50.0, 0.6), (30.0, 50.0));
        assert_eq!(perimeter_point(100.0, 50.0, 0.9), (0.0, 20.0));
    }

    #[test]
    fn blend_white() {
        assert_eq!(blend_toward_white([0, 100, 255], 0.6), [153, 193, 255]);
    }
}
