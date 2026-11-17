//! 設定画面の配置計算と当たり判定（純粋関数）

pub const MARGIN: i32 = 16;
pub const PREVIEW_H: i32 = 240;
pub const CARD_W: i32 = 160;
pub const CARD_H: i32 = 156;
pub const CARD_GAP: i32 = 8;
pub const THUMB_H: i32 = 90;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

impl Rect {
    pub const fn new(x: i32, y: i32, w: i32, h: i32) -> Self {
        Self { x, y, w, h }
    }

    pub fn contains(self, mx: i32, my: i32) -> bool {
        mx >= self.x && mx < self.x + self.w && my >= self.y && my < self.y + self.h
    }

    pub fn intersect(self, other: Rect) -> Option<Rect> {
        let x0 = self.x.max(other.x);
        let y0 = self.y.max(other.y);
        let x1 = (self.x + self.w).min(other.x + other.w);
        let y1 = (self.y + self.h).min(other.y + other.h);
        if x1 > x0 && y1 > y0 {
            Some(Rect::new(x0, y0, x1 - x0, y1 - y0))
        } else {
            None
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HitTarget {
    Autostart,
    Mode,
    Lang,
    Solid,
    Add,
    Wallpaper,
    Saver,
    Card(usize),
    Crop(usize),
    Delete(usize),
}

pub struct Layout {
    pub preview_screen: Rect,
    pub preview_bezel: Rect,
    pub autostart: Rect,
    pub mode: Rect,
    pub lang: Rect,
    pub solid: Rect,
    pub add: Rect,
    pub divider_y: i32,
    pub grid: Rect,
    pub wallpaper: Rect,
    pub saver: Rect,
    pub cards: Vec<(usize, Rect)>,
}

pub fn preview_screen_rect(preview: Rect, aspect: f64) -> Rect {
    let aspect = if aspect > 0.0 { aspect } else { 16.0 / 9.0 };
    let max_h = (preview.h - 16).max(1);
    let max_w = (preview.w - 16).max(1);
    let (mut sw, mut sh) = if (max_w as f64 / max_h as f64) > aspect {
        let sh = max_h;
        ((sh as f64 * aspect).round() as i32, sh)
    } else {
        let sw = max_w;
        (sw, (sw as f64 / aspect).round() as i32)
    };
    if sw % 2 != 0 {
        sw += 1;
    }
    if sh % 2 != 0 {
        sh += 1;
    }
    let sx = preview.x + (preview.w - sw) / 2;
    let sy = preview.y + (preview.h - sh) / 2;
    Rect::new(sx, sy, sw, sh)
}

pub fn columns(grid_width: i32) -> usize {
    ((grid_width + CARD_GAP) / (CARD_W + CARD_GAP)).max(1) as usize
}

pub fn total_height(grid_width: i32, item_count: usize) -> i32 {
    let cols = columns(grid_width);
    let rows = item_count.div_ceil(cols);
    rows as i32 * (CARD_H + CARD_GAP)
}

pub fn layout(width: i32, height: i32, item_count: usize, scroll: i32, aspect: f64) -> Layout {
    let preview = Rect::new(MARGIN, MARGIN, width - MARGIN * 2, PREVIEW_H);
    let preview_screen = preview_screen_rect(preview, aspect);
    let preview_bezel = Rect::new(
        preview_screen.x - 4,
        preview_screen.y - 4,
        preview_screen.w + 8,
        preview_screen.h + 8,
    );

    // 設定項目をプレビュー下の2段にまとめる（上下に分けず、下に絵の候補を並べる）
    let row1_y = MARGIN + PREVIEW_H + 10;
    let row1_h = 44;
    let inner_w = (width - MARGIN * 2).max(300);
    let toggle_w = (inner_w - 16) / 3;
    let wallpaper = Rect::new(MARGIN, row1_y, toggle_w, row1_h);
    let saver = Rect::new(MARGIN + toggle_w + 8, row1_y, toggle_w, row1_h);
    let autostart_x = MARGIN + (toggle_w + 8) * 2;
    let autostart = Rect::new(autostart_x, row1_y, width - MARGIN - autostart_x, row1_h);

    let row2_y = row1_y + row1_h + 8;
    let row2_h = 40;
    let mode = Rect::new(MARGIN, row2_y + 2, 180, 36);
    let lang = Rect::new(MARGIN + 180 + 8, row2_y + 2, 64, 36);
    let add = Rect::new(width - MARGIN - 44, row2_y, 44, row2_h);
    let solid = Rect::new(add.x - 8 - 44, row2_y, 44, row2_h);

    let divider_y = row2_y + row2_h + 10;
    let grid_y = divider_y + 10;
    let grid = Rect::new(MARGIN, grid_y, width - MARGIN * 2, (height - MARGIN - grid_y).max(1));

    let cols = columns(grid.w);
    let mut cards = Vec::with_capacity(item_count);
    for i in 0..item_count {
        let cx = MARGIN + (i % cols) as i32 * (CARD_W + CARD_GAP);
        let cy = grid_y + (i / cols) as i32 * (CARD_H + CARD_GAP) - scroll;
        cards.push((i, Rect::new(cx, cy, CARD_W, CARD_H)));
    }

    Layout {
        preview_screen,
        preview_bezel,
        autostart,
        mode,
        lang,
        solid,
        add,
        divider_y,
        grid,
        wallpaper,
        saver,
        cards,
    }
}

pub fn max_scroll(l: &Layout, item_count: usize) -> i32 {
    (total_height(l.grid.w, item_count) - l.grid.h).max(0)
}

pub fn hit_test(l: &Layout, mx: i32, my: i32) -> Option<HitTarget> {
    if l.wallpaper.contains(mx, my) {
        return Some(HitTarget::Wallpaper);
    }
    if l.saver.contains(mx, my) {
        return Some(HitTarget::Saver);
    }
    if l.autostart.contains(mx, my) {
        return Some(HitTarget::Autostart);
    }
    if l.mode.contains(mx, my) {
        return Some(HitTarget::Mode);
    }
    if l.lang.contains(mx, my) {
        return Some(HitTarget::Lang);
    }
    if l.solid.contains(mx, my) {
        return Some(HitTarget::Solid);
    }
    if l.add.contains(mx, my) {
        return Some(HitTarget::Add);
    }
    if !l.grid.contains(mx, my) {
        return None;
    }
    for &(idx, r) in &l.cards {
        if !r.contains(mx, my) {
            continue;
        }
        if Rect::new(r.x + r.w - 30, r.y, 30, 32).contains(mx, my) {
            return Some(HitTarget::Delete(idx));
        }
        if Rect::new(r.x + r.w - 62, r.y, 30, 32).contains(mx, my) {
            return Some(HitTarget::Crop(idx));
        }
        return Some(HitTarget::Card(idx));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preview_screen_respects_aspect_and_even_dimensions() {
        let r = preview_screen_rect(Rect::new(16, 16, 848, 240), 16.0 / 9.0);
        assert_eq!(r.w % 2, 0);
        assert_eq!(r.h % 2, 0);
        assert!((r.w as f64 / r.h as f64 - 16.0 / 9.0).abs() < 0.05);
    }

    #[test]
    fn hit_test_card_buttons() {
        let l = layout(880, 760, 4, 0, 16.0 / 9.0);
        let (_, c0) = l.cards[0];
        assert_eq!(hit_test(&l, c0.x + 10, c0.y + 10), Some(HitTarget::Card(0)));
        assert_eq!(hit_test(&l, c0.x + c0.w - 10, c0.y + 10), Some(HitTarget::Delete(0)));
        assert_eq!(hit_test(&l, c0.x + c0.w - 45, c0.y + 10), Some(HitTarget::Crop(0)));
    }
}
