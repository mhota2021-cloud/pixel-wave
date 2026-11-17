//! ドット絵と通常画像の共通アニメーション状態機械
//!
//! 壁紙・設定プレビュー・スクリーンセーバーが同じ `WaveClock` を共有することで、
//! 同一プロセス内で完全に同期しつつ、起動直後・壁紙ON直後は1.5秒で波が始まる。

use std::sync::atomic::{AtomicI64, Ordering};
use std::time::{Duration, Instant};

use crate::dotart::{self, Grid, Rgb};

pub const DISPLAY_SECONDS: f64 = 14.0;
pub const TRANSITION_SECONDS: f64 = 10.0;
pub const CYCLE_SECONDS: f64 = DISPLAY_SECONDS + TRANSITION_SECONDS; // 24.0秒
pub const INITIAL_WAIT_SECONDS: f64 = 1.5;

pub const DOT: i32 = 12;
pub const FILL: i32 = 10;
pub const BAND_DOTS: f64 = 1.5;
pub const GLOW_RATIO: f64 = 0.6;
pub const BACKGROUND: Rgb = [20, 20, 24];

/// 共通の波時計（プロセス起動時・壁紙ON時にリセットすると1.5秒後から波が始まる）
pub struct WaveClock {
    origin: Instant,
    /// originからのオフセット（ミリ秒）。初期状態では `DISPLAY_SECONDS - INITIAL_WAIT_SECONDS` に設定し、
    /// 起動後 `INITIAL_WAIT_SECONDS` 秒で最初の切り替えが始まるようにする。
    offset_ms: AtomicI64,
}

impl WaveClock {
    pub fn new() -> Self {
        let initial_offset_ms = ((DISPLAY_SECONDS - INITIAL_WAIT_SECONDS) * 1000.0) as i64;
        Self {
            origin: Instant::now(),
            offset_ms: AtomicI64::new(initial_offset_ms),
        }
    }

    /// 現在の波時刻（秒）を返す
    pub fn now_secs(&self) -> f64 {
        let elapsed_ms = self.origin.elapsed().as_millis() as i64;
        let offset = self.offset_ms.load(Ordering::Relaxed);
        (elapsed_ms + offset).max(0) as f64 / 1000.0
    }

    /// 次の波が `INITIAL_WAIT_SECONDS` 秒後に始まるように時刻を合わせる（壁紙ON・絵の入れ替え直後用）
    pub fn trigger_soon(&self) {
        let elapsed_ms = self.origin.elapsed().as_millis() as i64;
        let current_total = elapsed_ms + self.offset_ms.load(Ordering::Relaxed);
        let cycle_ms = (CYCLE_SECONDS * 1000.0) as i64;
        let display_ms = (DISPLAY_SECONDS * 1000.0) as i64;
        let wait_ms = (INITIAL_WAIT_SECONDS * 1000.0) as i64;
        let current_cycle = current_total / cycle_ms;
        // 次のサイクル、または現在のサイクルの切り替え直前に寄せる
        let target_total = current_cycle * cycle_ms + (display_ms - wait_ms);
        let target = if target_total >= current_total {
            target_total
        } else {
            (current_cycle + 1) * cycle_ms + (display_ms - wait_ms)
        };
        self.offset_ms.store(target - elapsed_ms, Ordering::Relaxed);
    }
}

/// 指定時刻での波の状態（通常画像モード・ドット絵モード共通）
#[derive(Clone, Copy, Debug)]
pub struct WavePhase {
    pub cycle: usize,
    pub from_idx: usize,
    pub to_idx: usize,
    /// `None` なら静止表示、`Some(progress 0..=1)` なら波が広がっている途中
    pub progress: Option<f64>,
}

pub fn phase_at(now: f64, count: usize) -> WavePhase {
    if count <= 1 {
        return WavePhase { cycle: 0, from_idx: 0, to_idx: 0, progress: None };
    }
    let cycle_f = (now / CYCLE_SECONDS).floor().max(0.0);
    let cycle = cycle_f as usize;
    let cycle_time = now - cycle_f * CYCLE_SECONDS;
    let from_idx = cycle % count;
    let to_idx = (cycle + 1) % count;
    let progress = if cycle_time < DISPLAY_SECONDS {
        None
    } else {
        let t = ((cycle_time - DISPLAY_SECONDS) / TRANSITION_SECONDS).clamp(0.0, 1.0);
        Some(dotart::ease_in_out(t))
    };
    WavePhase { cycle, from_idx, to_idx, progress }
}

/// 次の描画まで待つべきミリ秒（静止中は次の切り替え開始まで眠る）
pub fn next_timer_ms(now: f64, count: usize, anim_active: bool) -> u32 {
    if anim_active {
        return 16;
    }
    if count <= 1 {
        return 60_000;
    }
    let cycle_f = (now / CYCLE_SECONDS).floor().max(0.0);
    let cycle_time = now - cycle_f * CYCLE_SECONDS;
    if cycle_time >= DISPLAY_SECONDS {
        16
    } else {
        let remain_ms = ((DISPLAY_SECONDS - cycle_time) * 1000.0).ceil() as u32;
        remain_ms.clamp(16, 15_000)
    }
}

/// サイクル番号から波の中心点を決定論的に計算する
pub fn cycle_center(cycle: usize, w: f64, h: f64) -> (f64, f64) {
    let mut rng = dotart::Rng::new((cycle as u64).wrapping_add(1));
    dotart::perimeter_point(w, h, rng.next_f64())
}

/// ドット絵アニメーション状態機械
pub struct WaveEngine {
    pub grids: Vec<Grid>,
    pub cols: usize,
    pub rows: usize,
    pub dot: i32,
    pub fill: i32,
    shown: Vec<u16>,
    pending_full_redraw: bool,
    last_cycle: Option<usize>,
    center: (f64, f64),
    max_dist: f64,
    distances: Vec<f64>,
}

impl WaveEngine {
    pub fn new(grids: Vec<Grid>, cols: usize, rows: usize, dot: i32, fill: i32) -> Self {
        let count = cols * rows;
        Self {
            grids,
            cols,
            rows,
            dot,
            fill,
            shown: vec![u16::MAX; count],
            pending_full_redraw: true,
            last_cycle: None,
            center: (0.0, 0.0),
            max_dist: 1.0,
            distances: Vec::new(),
        }
    }

    pub fn set_grids(&mut self, grids: Vec<Grid>) {
        self.grids = grids;
        self.request_full_redraw();
    }

    pub fn request_full_redraw(&mut self) {
        self.pending_full_redraw = true;
        self.shown.fill(u16::MAX);
        self.last_cycle = None;
    }

    /// 状態を1フレーム進め、変わったドットをコールバックへ渡す。戻り値は更新領域 (x, y, w, h)
    pub fn advance<F: FnMut(usize, usize, Rgb)>(&mut self, now: f64, mut paint_dot: F) -> Option<(i32, i32, i32, i32)> {
        if self.grids.is_empty() {
            return None;
        }
        let phase = phase_at(now, self.grids.len());
        if self.grids.len() > 1 && self.last_cycle != Some(phase.cycle) {
            self.last_cycle = Some(phase.cycle);
            self.setup_cycle(phase.cycle);
        }

        let mut min_col = usize::MAX;
        let mut max_col = 0usize;
        let mut min_row = usize::MAX;
        let mut max_row = 0usize;
        let mut any = false;

        let count = self.cols * self.rows;
        match phase.progress {
            None => {
                let grid = &self.grids[phase.from_idx];
                let key = (phase.from_idx as u16) << 1;
                for i in 0..count {
                    if self.shown[i] != key {
                        self.shown[i] = key;
                        let col = i % self.cols;
                        let row = i / self.cols;
                        paint_dot(col, row, grid.color(i));
                        min_col = min_col.min(col);
                        max_col = max_col.max(col);
                        min_row = min_row.min(row);
                        max_row = max_row.max(row);
                        any = true;
                    }
                }
            }
            Some(ease) => {
                let radius = ease * self.max_dist;
                let band = BAND_DOTS * self.dot as f64;
                let band_start = radius - band;
                let from_grid = &self.grids[phase.from_idx];
                let to_grid = &self.grids[phase.to_idx];
                for i in 0..count {
                    let d = self.distances[i];
                    let painting = if d <= radius { phase.to_idx } else { phase.from_idx };
                    let glow = d <= radius && d > band_start;
                    let key = ((painting as u16) << 1) | u16::from(glow);
                    if self.shown[i] != key {
                        self.shown[i] = key;
                        let grid = if painting == phase.to_idx { to_grid } else { from_grid };
                        let mut rgb = grid.color(i);
                        if glow {
                            rgb = dotart::blend_toward_white(rgb, GLOW_RATIO);
                        }
                        let col = i % self.cols;
                        let row = i / self.cols;
                        paint_dot(col, row, rgb);
                        min_col = min_col.min(col);
                        max_col = max_col.max(col);
                        min_row = min_row.min(row);
                        max_row = max_row.max(row);
                        any = true;
                    }
                }
            }
        }

        self.pending_full_redraw = false;
        if !any {
            return None;
        }
        Some((
            min_col as i32 * self.dot,
            min_row as i32 * self.dot,
            (max_col - min_col + 1) as i32 * self.dot,
            (max_row - min_row + 1) as i32 * self.dot,
        ))
    }

    fn setup_cycle(&mut self, cycle: usize) {
        let w = self.cols as f64 * self.dot as f64;
        let h = self.rows as f64 * self.dot as f64;
        self.center = cycle_center(cycle, w, h);
        self.max_dist = dotart::farthest_corner_distance(self.center.0, self.center.1, w, h);
        let count = self.cols * self.rows;
        self.distances.resize(count, 0.0);
        let half = self.dot as f64 / 2.0;
        for i in 0..count {
            let cx = (i % self.cols) as f64 * self.dot as f64 + half;
            let cy = (i / self.cols) as f64 * self.dot as f64 + half;
            self.distances[i] = dotart::distance(cx, cy, self.center.0, self.center.1);
        }
    }
}

/// 次のタイマー時刻の計算用ヘルパー
pub fn _duration_ms(d: Duration) -> u32 {
    d.as_millis().min(u32::MAX as u128) as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dummy_grid(rgb: Rgb, count: usize) -> Grid {
        Grid { palette: vec![rgb], indices: vec![0; count] }
    }

    #[test]
    fn phase_transitions_from_display_to_wave() {
        let p0 = phase_at(1.0, 3);
        assert_eq!(p0.from_idx, 0);
        assert_eq!(p0.to_idx, 1);
        assert!(p0.progress.is_none());

        let p1 = phase_at(19.0, 3);
        assert!(p1.progress.is_some());
        let p2 = phase_at(25.0, 3);
        assert_eq!(p2.from_idx, 1);
        assert_eq!(p2.to_idx, 2);
        assert!(p2.progress.is_none());
    }

    #[test]
    fn wave_engine_emits_only_changed_dots() {
        let grids = vec![dummy_grid([10, 20, 30], 4), dummy_grid([200, 100, 50], 4)];
        let mut engine = WaveEngine::new(grids, 2, 2, 12, 10);
        let mut first = 0;
        engine.advance(0.0, |_, _, _| first += 1);
        assert_eq!(first, 4);

        let mut second = 0;
        assert!(engine.advance(1.0, |_, _, _| second += 1).is_none());
        assert_eq!(second, 0);
    }

    #[test]
    fn next_timer_sleeps_until_transition() {
        assert!(next_timer_ms(0.0, 2, false) > 10_000);
        assert_eq!(next_timer_ms(15.0, 2, false), 16);
        assert_eq!(next_timer_ms(0.0, 2, true), 16);
    }
}
