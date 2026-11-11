#通常画像モードの描画エンジン（GDI円形リージョンによる超軽量・高速波切り替え）
require_relative 'platform'
require_relative 'render_math'
require_relative 'dotart'
require_relative 'wic'

class NormalImageEngine
  DISPLAY_SECONDS = 14.0
  TRANSITION_SECONDS = 10.0
  CYCLE_SECONDS = DISPLAY_SECONDS + TRANSITION_SECONDS # 24.0秒

  attr_reader :width, :height, :images

  #初期化（引数paintingsは絵の情報一覧、引数widthとheightは表示解像度、引数hdc_refは互換DC用ハンドル）
  def initialize(paintings, width, height, hdc_ref: nil)
    @width = [width, 1].max
    @height = [height, 1].max
    @images = paintings.dup
    @image_dcs = []
    @image_bitmaps = []
    @old_bitmaps = []
    @pending_redraw = true
    @last_cycle = nil

    release_ref = false
    if hdc_ref.nil? || (hdc_ref.respond_to?(:null?) && hdc_ref.null?)
      hdc_ref = Platform.GetDC(nil)
      release_ref = true
    end

    begin
      load_images(hdc_ref)
    ensure
      Platform.ReleaseDC(nil, hdc_ref) if release_ref && Platform::API_READY
    end
  end

  #描き直しが必要か返す（引数nowは秒。静止表示中は偽になる）
  def needs_redraw?(now)
    return false if @images.empty?
    return true if @pending_redraw
    return false if @images.length <= 1

    cycle = (now / CYCLE_SECONDS).floor
    cycle_time = now - (cycle * CYCLE_SECONDS)

    cycle_time >= DISPLAY_SECONDS || @last_cycle != cycle
  end

  #最初の描画や設定変更時に全体描き直しを要求する
  def request_full_redraw
    @pending_redraw = true
  end

  #指定されたDCへフレームを描画する（引数target_dcは描画先、引数nowは時刻、引数offset_xとoffset_yは描画開始位置）
  def render(target_dc, now, offset_x: 0, offset_y: 0)
    return if @image_dcs.empty?

    if @images.length == 1
      Platform.BitBlt(target_dc, offset_x, offset_y, @width, @height, @image_dcs[0], 0, 0, Platform::SRCCOPY)
      @pending_redraw = false
      return
    end

    cycle = (now / CYCLE_SECONDS).floor
    cycle_time = now - (cycle * CYCLE_SECONDS)
    @last_cycle = cycle

    from_idx = cycle % @images.length
    to_idx = (cycle + 1) % @images.length
    from_dc = @image_dcs[from_idx]
    to_dc = @image_dcs[to_idx]

    if cycle_time < DISPLAY_SECONDS
      # 静止表示フェーズ（fromの絵を全体表示）
      Platform.BitBlt(target_dc, offset_x, offset_y, @width, @height, from_dc, 0, 0, Platform::SRCCOPY)
    else
      # 波切り替えフェーズ（fromからtoへ円形波が広がる）
      # 1. まずベース画像としてfromを描画
      Platform.BitBlt(target_dc, offset_x, offset_y, @width, @height, from_dc, 0, 0, Platform::SRCCOPY)

      # 2. 決定論的中心点と半径の計算
      cx, cy = compute_center(cycle)
      max_dist = DotArt.farthest_corner_distance(cx, cy, @width.to_f, @height.to_f)
      t = (cycle_time - DISPLAY_SECONDS) / TRANSITION_SECONDS
      t = [[t, 0.0].max, 1.0].min
      r = (DotArt.ease_in_out(t) * max_dist).round

      if r > 0
        rect_rgn = Platform.CreateRectRgn(offset_x, offset_y, offset_x + @width, offset_y + @height)
        ellip_rgn = Platform.CreateEllipticRgn(offset_x + cx - r, offset_y + cy - r, offset_x + cx + r, offset_y + cy + r)
        clip_rgn = Platform.CreateRectRgn(0, 0, 0, 0)
        Platform.CombineRgn(clip_rgn, rect_rgn, ellip_rgn, 1)

        # 3. 円形リージョンでクリッピングしてto画像を描画（枠内限定）
        Platform.SelectClipRgn(target_dc, clip_rgn)
        Platform.BitBlt(target_dc, offset_x, offset_y, @width, @height, to_dc, 0, 0, Platform::SRCCOPY)

        # 4. 枠内のみに波面の光輪（白いグローリング）を描画
        Platform.SelectClipRgn(target_dc, rect_rgn)
        draw_wave_front(target_dc, offset_x + cx, offset_y + cy, r)

        Platform.SelectClipRgn(target_dc, nil)
        Platform.DeleteObject(clip_rgn)
        Platform.DeleteObject(ellip_rgn)
        Platform.DeleteObject(rect_rgn)
      end
    end

    @pending_redraw = false
  end

  #リソースを解放する
  def dispose
    return unless Platform::API_READY
    @image_dcs.each_with_index do |dc, i|
      Platform.SelectObject(dc, @old_bitmaps[i]) if @old_bitmaps[i]
      Platform.DeleteObject(@image_bitmaps[i]) if @image_bitmaps[i]
      Platform.DeleteDC(dc) if dc
    end
    @image_dcs.clear
    @image_bitmaps.clear
    @old_bitmaps.clear
  end

  #サイクル番号から波の中心点を計算する（決定論的・全インスタンス同期）
  def compute_center(cycle)
    w = @width.to_f
    h = @height.to_f
    rng = Random.new(cycle)
    perimeter = 2.0 * (w + h)
    t = rng.rand * perimeter
    if t < w
      [t.round, 0]
    elsif t < w + h
      [w.round, (t - w).round]
    elsif t < 2.0 * w + h
      [(t - w - h).round, h.round]
    else
      [0, (t - 2.0 * w - h).round]
    end
  end

  private

  #画像を読み込み、メモリDCとビットマップを作成する
  def load_images(hdc_ref)
    return unless Platform::API_READY
    @images.each do |painting|
      path = painting[:path]
      crop = painting[:crop]
      next unless path && File.exist?(path)

      w, h, bgra = Wic.decode_cropped_bgra(path, @width, @height, crop)
      next unless w && h && bgra

      mem_dc = Platform.CreateCompatibleDC(hdc_ref)
      hbm = Platform.CreateCompatibleBitmap(hdc_ref, @width, @height)
      old_bm = Platform.SelectObject(mem_dc, hbm)

      bmi = [40, w, -h, 1, 32, 0, w * h * 4, 0, 0, 0, 0].pack('L<l<2S<2L<6')
      bmi_ptr = Fiddle::Pointer.malloc(40)
      bmi_ptr[0, 40] = bmi
      bits_ptr = Fiddle::Pointer.malloc(bgra.bytesize)
      bits_ptr[0, bgra.bytesize] = bgra

      Platform.StretchDIBits(mem_dc, 0, 0, w, h, 0, 0, w, h, bits_ptr, bmi_ptr, 0, Platform::SRCCOPY)

      @image_dcs << mem_dc
      @image_bitmaps << hbm
      @old_bitmaps << old_bm
    end
  end

  #波面の光輪を描画する
  def draw_wave_front(target_dc, cx, cy, r)
    band_w = [(@width / 500.0).round, 2].max
    pen = Platform.CreatePen(0, band_w, RenderMath.colorref([255, 255, 255]))
    old_pen = Platform.SelectObject(target_dc, pen)
    null_brush = Platform.GetStockObject(5) # NULL_BRUSH
    old_brush = Platform.SelectObject(target_dc, null_brush)

    Platform.Ellipse(target_dc, cx - r, cy - r, cx + r, cy + r)

    Platform.SelectObject(target_dc, old_pen)
    Platform.SelectObject(target_dc, old_brush)
    Platform.DeleteObject(pen)
  end
end
