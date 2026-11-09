#設定画面の配置計算（純粋関数）
module SettingsLayout
  MARGIN = 16
  PREVIEW_H = 256
  CARD_W = 160
  #縮小画像90pxの下に、作品名2行と作者1行（各19px）が収まる高さ
  CARD_H = 156
  CARD_GAP = 8
  THUMB_H = 90
  ACTIONS_H = 52

  module_function

  #配置を計算する（引数widthとheightはウィンドウの大きさ、引数item_countは項目の数、引数scrollはスクロール量。戻り値は名前から矩形への対応と、項目と矩形の組の配列）
  def layout(width, height, item_count, scroll)
    rects = {}
    rects[:preview] = [MARGIN, MARGIN, width - MARGIN * 2, PREVIEW_H]
    bar_y = MARGIN + PREVIEW_H + 8
    rects[:add] = [width - MARGIN - 44, bar_y, 44, 44]
    grid_y = bar_y + 44 + 8
    actions_y = height - MARGIN - ACTIONS_H
    rects[:grid] = [MARGIN, grid_y, width - MARGIN * 2, actions_y - grid_y - 8]
    wallpaper_w = (width - MARGIN * 2 - 8) * 55 / 100
    rects[:wallpaper] = [MARGIN, actions_y, wallpaper_w, ACTIONS_H]
    saver_x = MARGIN + wallpaper_w + 8
    rects[:saver] = [saver_x, actions_y, width - MARGIN - saver_x, ACTIONS_H]
    cols = columns(rects[:grid][2])
    cards = []
    item_count.times do |i|
      cx = MARGIN + (i % cols) * (CARD_W + CARD_GAP)
      cy = grid_y + (i / cols) * (CARD_H + CARD_GAP) - scroll
      cards << [i, [cx, cy, CARD_W, CARD_H]]
    end
    [rects, cards]
  end

  #1行に並ぶカードの数を返す（引数grid_widthは一覧の幅）
  def columns(grid_width)
    [(grid_width + CARD_GAP) / (CARD_W + CARD_GAP), 1].max
  end

  #一覧の全体の高さを返す（引数grid_widthは一覧の幅、引数item_countは項目の数）
  def total_height(grid_width, item_count)
    cols = columns(grid_width)
    rows = (item_count + cols - 1) / cols
    rows * (CARD_H + CARD_GAP)
  end

  #スクロール量の最大を返す（引数rectsは配置、引数item_countは項目の数）
  def max_scroll(rects, item_count)
    [total_height(rects[:grid][2], item_count) - rects[:grid][3], 0].max
  end

  #矩形の中か返す（引数rectは矩形、引数mxとmyは点）
  def inside?(rect, mx, my)
    x, y, w, h = rect
    mx >= x && mx < x + w && my >= y && my < y + h
  end

  #当たり判定（引数rectsは配置、引数cardsは項目と矩形の組、引数mxとmyはマウス位置。戻り値は対象の名前か、カードなら種類と番号）
  def hit_test(rects, cards, mx, my)
    return :add if inside?(rects[:add], mx, my)
    return :wallpaper if inside?(rects[:wallpaper], mx, my)
    return :saver if inside?(rects[:saver], mx, my)
    return nil unless inside?(rects[:grid], mx, my)
    cards.each do |index, rect|
      next unless inside?(rect, mx, my)
      x, y, w, _h = rect
      return [:delete, index] if inside?([x + w - 30, y, 30, 32], mx, my)
      return [:card, index]
    end
    nil
  end
end
