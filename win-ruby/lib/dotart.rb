#ドット絵化と波の共通部品（アプリと変換ツールで共用する純粋関数だけを置く）
module DotArt
  module_function

  #切り抜き範囲を返す（引数src_wとsrc_hは元の大きさ、引数target_wとtarget_hは目標の縦横比、引数cropは位置でtopかcenterかbottom。戻り値は左上のxとyと幅と高さ）
  def croprect(src_w, src_h, target_w, target_h, crop)
    target_aspect = target_w.to_f / target_h
    src_aspect = src_w.to_f / src_h
    if src_aspect > target_aspect
      w = (src_h * target_aspect).round
      h = src_h
      x = (src_w - w) / 2
      y = 0
    else
      w = src_w
      h = (src_w / target_aspect).round
      x = 0
      y = case crop
          when :top then 0
          when :bottom then src_h - h
          else (src_h - h) / 2
          end
    end
    [x, y, w, h]
  end

  #範囲を取り出す（引数pixelsは色の配列、引数wは元の幅、引数rectは切り抜き範囲。戻り値は取り出した色の配列と幅と高さ）
  def apply_crop(pixels, w, rect)
    x0, y0, cw, ch = rect
    out = []
    ch.times do |row|
      base = (y0 + row) * w + x0
      out.concat(pixels[base, cw])
    end
    [out, cw, ch]
  end

  #縮小する（引数pixelsは色の配列、引数wとhは元の幅と高さ、引数colsとrowsはドットの数。マスごとに平均した色の配列を返す）
  def shrink(pixels, w, h, cols, rows)
    result = Array.new(cols * rows)
    rows.times do |row|
      y0 = row * h / rows
      y1 = (row + 1) * h / rows
      y1 = y0 + 1 if y1 <= y0
      cols.times do |col|
        x0 = col * w / cols
        x1 = (col + 1) * w / cols
        x1 = x0 + 1 if x1 <= x0
        sr = 0
        sg = 0
        sb = 0
        n = 0
        (y0...y1).each do |y|
          base = y * w
          (x0...x1).each do |x|
            p = pixels[base + x]
            sr += p[0]
            sg += p[1]
            sb += p[2]
            n += 1
          end
        end
        #平均は四捨五入する（切り捨てると、どの色も平均で0.5ずつ暗くなる）
        result[row * cols + col] = [(sr.to_f / n).round, (sg.to_f / n).round, (sb.to_f / n).round]
      end
    end
    result
  end

  #色同士の距離の2乗を返す（引数aとbは色）
  def dist2(a, b)
    dr = a[0] - b[0]
    dg = a[1] - b[1]
    db = a[2] - b[2]
    dr * dr + dg * dg + db * db
  end

  #一番近い代表色の番号を返す（引数colorは色、引数centersは代表色の配列）
  def nearest(color, centers)
    best = 0
    best_d = nil
    centers.each_with_index do |c, i|
      d = dist2(color, c)
      if best_d.nil? || d < best_d
        best_d = d
        best = i
      end
    end
    best
  end

  #k-meansで色を減らす（引数pixelsは色の配列、引数countは色数、引数seedは乱数の種。代表色を決める計算は間引いた画素で行い、最後に全部を割り当てる。戻り値はパレットと番号の配列）
  def kmeans(pixels, count, seed)
    return [[], []] if pixels.empty?
    rng = Random.new(seed)
    sample = pixels
    if pixels.length > 2000
      step = pixels.length.to_f / 2000
      sample = []
      i = 0.0
      while i < pixels.length
        sample << pixels[i.floor]
        i += step
      end
    end
    centers = [sample[rng.rand(sample.length)]]
    while centers.length < count
      dists = sample.map { |p| centers.map { |c| dist2(p, c) }.min }
      total = dists.sum
      break if total <= 0
      r = rng.rand * total
      acc = 0.0
      chosen = sample[-1]
      sample.each_with_index do |p, idx|
        acc += dists[idx]
        if acc >= r
          chosen = p
          break
        end
      end
      centers << chosen
    end
    #代表色は小数のまま更新し、割り当てが変わらなくなるまで（最大100回）繰り返す
    centers = centers.map { |c| c.map(&:to_f) }
    labels = Array.new(sample.length, 0)
    100.times do
      changed = false
      sample.each_with_index do |p, i|
        best = nearest(p, centers)
        if labels[i] != best
          labels[i] = best
          changed = true
        end
      end
      sums = Array.new(centers.length) { [0, 0, 0, 0] }
      sample.each_with_index do |p, i|
        s = sums[labels[i]]
        s[0] += p[0]
        s[1] += p[1]
        s[2] += p[2]
        s[3] += 1
      end
      centers = centers.each_with_index.map do |c, i|
        s = sums[i]
        s[3] > 0 ? [s[0].to_f / s[3], s[1].to_f / s[3], s[2].to_f / s[3]] : c
      end
      break unless changed
    end
    palette = centers.map { |c| c.map { |v| v.round.clamp(0, 255) } }
    indices = sample.equal?(pixels) ? labels : pixels.map { |p| nearest(p, centers) }
    [palette, indices]
  end

  #ベジェ曲線の1軸分の値を返す（引数tは媒介変数、引数aとbは制御点の値）
  def bezier_component(t, a, b)
    u = 1.0 - t
    3 * u * u * t * a + 3 * u * t * t * b + t * t * t
  end

  #3次ベジェ曲線のイージングを返す（引数x1とy1とx2とy2は制御点、引数xは進み具合。対応するyを返す）
  def cubic_bezier_easing(x1, y1, x2, y2, x)
    return 0.0 if x <= 0.0
    return 1.0 if x >= 1.0
    lo = 0.0
    hi = 1.0
    t = x
    50.times do
      t = (lo + hi) / 2
      if bezier_component(t, x1, x2) < x
        lo = t
      else
        hi = t
      end
    end
    bezier_component(t, y1, y2)
  end

  #ゆっくり始まりゆっくり終わるイージングを返す（引数xは進み具合。cubic-bezier（0.37、0、0.63、1）に相当する）
  def ease_in_out(x)
    cubic_bezier_easing(0.37, 0.0, 0.63, 1.0, x)
  end

  #2点の距離を返す（引数x1とy1とx2とy2は座標）
  def distance(x1, y1, x2, y2)
    dx = x1 - x2
    dy = y1 - y2
    Math.sqrt(dx * dx + dy * dy)
  end


  #距離が波の先頭の帯の中か返す（引数distは中心からの距離、引数radiusは今の半径、引数bandは帯の幅）
  def in_wave_front?(dist, radius, band)
    dist <= radius && dist > radius - band
  end

  #一番遠い角までの距離を返す（引数pxとpyは中心、引数wとhは画面の大きさ）
  def farthest_corner_distance(px, py, w, h)
    [distance(px, py, 0, 0), distance(px, py, w, 0), distance(px, py, 0, h), distance(px, py, w, h)].max
  end

  #外周上のランダムな点を返す（引数wとhは画面の大きさ、引数rngは乱数。戻り値はxとy）
  def pick_perimeter_point(w, h, rng)
    perimeter = 2.0 * (w + h)
    t = rng.rand * perimeter
    if t < w
      [t, 0.0]
    elsif t < w + h
      [w.to_f, t - w]
    elsif t < 2 * w + h
      [t - w - h, h.to_f]
    else
      [0.0, t - 2 * w - h]
    end
  end

  #順番をシャッフルして返す（引数countは数、引数rngは乱数、引数avoid_firstは先頭に来てはいけない値で無ければnil）
  def shuffled_order(count, rng, avoid_first = nil)
    order = (0...count).to_a
    (count - 1).downto(1) do |i|
      j = rng.rand(i + 1)
      order[i], order[j] = order[j], order[i]
    end
    if !avoid_first.nil? && count > 1 && order[0] == avoid_first
      order[0], order[1] = order[1], order[0]
    end
    order
  end

  #色を白へ寄せて返す（引数colorは色、引数ratioは寄せる割合）
  def blend_toward_white(color, ratio)
    color.map { |v| (v + (255 - v) * ratio).round }
  end
end
