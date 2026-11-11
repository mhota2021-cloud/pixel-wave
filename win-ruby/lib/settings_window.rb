#設定画面（GDIで描く。プレビューと絵の一覧と2つのボタンだけ）
#裏画面に描き、操作があったときとプレビューが動いているときだけ描き直す
require 'fileutils'
require 'securerandom'
require_relative 'window'
require_relative 'engine'
require_relative 'loader'
require_relative 'crop_window'
require_relative 'wic'
require_relative 'platform'
require_relative 'settings'
require_relative 'settings_layout'
require_relative 'render_math'
require_relative 'dotart'

class SettingsWindow < NativeWindow
  TIMER_TICK = 1
  WS_OVERLAPPEDWINDOW = 0x00CF0000
  DT_CENTER = 0x0001
  DT_VCENTER = 0x0004
  DT_SINGLELINE = 0x0020
  DT_NOPREFIX = 0x0800

  BG = [24, 24, 28].freeze
  SURFACE = [40, 40, 47].freeze
  SURFACE_HOVER = [56, 56, 65].freeze
  FG = [238, 238, 242].freeze
  SUB = [178, 178, 190].freeze
  ACCENT = [11, 92, 173].freeze
  ACCENT_HOVER = [16, 108, 199].freeze
  CHECK = [120, 190, 255].freeze
  PREVIEW_BG = [20, 20, 24].freeze
  PREVIEW_DOT = 8
  PREVIEW_FILL = 7

  #初期化（引数data_dirはデータフォルダ、引数paintings_dirは素材のフォルダ、引数widthとheightはウィンドウの大きさ）
  def initialize(data_dir:, paintings_dir:, width:, height:)
    @data_dir = data_dir
    @paintings_dir = paintings_dir
    @credits = Loader.credits(paintings_dir)
    builtin_ids = @credits.map { |c| c['id'] }
    @settings = AppSettings.load(data_dir, builtin_ids)
    super(class_name: 'PixelWaveSettings', title: 'Pixel Wave', width: width, height: height, style: WS_OVERLAPPEDWINDOW)
    client_w, client_h = Platform::API_READY ? Platform.client_size(@hwnd) : [width, height]
    @width = client_w if client_w > 0
    @height = client_h if client_h > 0
    @buffer = BackBuffer.new(@hwnd, @width, @height)
    @font_body = make_font(16)
    @font_button = make_font(18)
    @thumbs = {}
    @scroll = 0
    @hover = nil
    @engine_time = 0.0
    @last_tick_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sync_wallpaper_state
    @switch_anims = {
      autostart: (@settings['autostart'] ? 1.0 : 0.0),
      wallpaper: (@settings['wallpaper'] ? 1.0 : 0.0),
      saver: (Platform.screensaver_active? ? 1.0 : 0.0)
    }
    build_preview
  end

  #表示を始める
  def start
    redraw_all
    #WS_VISIBLEを付けずに作っているので、ここで見えるようにする（SW_SHOWNORMALは1）
    Platform.ShowWindow(@hwnd, 1)
    Platform.SetForegroundWindow(@hwnd)
    invalidate
    set_timer(TIMER_TICK, 250)
    run
    @buffer.dispose
    Platform.DeleteObject(@font_body)
    Platform.DeleteObject(@font_button)
  end

  #メッセージの処理
  def handle_message(hwnd, msg, wparam, lparam)
    case msg
    when WM_PAINT
      paint_struct = Fiddle::Pointer.malloc(128)
      hdc = Platform.BeginPaint(hwnd, paint_struct)
      @buffer.blit_to(hdc)
      Platform.EndPaint(hwnd, paint_struct)
      0
    when WM_ERASEBKGND
      1
    when WM_TIMER
      on_tick
      0
    when WM_MOUSEMOVE
      on_mouse_move(lparam)
      0
    when WM_LBUTTONUP
      on_click(lparam)
      0
    when WM_MOUSEWHEEL
      on_wheel(wparam)
      0
    when WM_CLOSE
      close
      0
    when WM_DESTROY
      Platform.PostQuitMessage(0)
      0
    end
  end

  private

  #フォントを作る（引数pxは大きさ。名前で指定する）
  def make_font(px)
    name = Platform.wide('Yu Gothic UI')
    name_ptr = Fiddle::Pointer.malloc(name.bytesize)
    name_ptr[0, name.bytesize] = name
    Platform.CreateFontW(-px, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 0, 0, name_ptr)
  end

  #プレビュー用のエンジンを作り直す（実際の画面と同じ16:9の比率で中央に表示し、絵が横長に切り抜かれすぎないようにする）
  def build_preview
    list = Loader.paintings(@settings, @paintings_dir, @data_dir)
    rects, _cards = SettingsLayout.layout(@width, @height, items.length, @scroll)
    px, py, pw, ph = rects[:preview]
    #16:9で内接する大きさを計算
    target_aspect = 16.0 / 9.0
    if pw.to_f / ph > target_aspect
      content_h = ph
      content_w = (ph * target_aspect).round
    else
      content_w = pw
      content_h = (pw / target_aspect).round
    end
    cols = [(content_w / PREVIEW_DOT.to_f).ceil, 1].max
    rows = [(content_h / PREVIEW_DOT.to_f).ceil, 1].max
    @preview_offset_x = px + (pw - cols * PREVIEW_DOT) / 2
    @preview_offset_y = py + (ph - rows * PREVIEW_DOT) / 2
    grids = Loader.grids(list, cols, rows, Platform.cache_dir, Wic.method(:decode))
    @engine = WaveEngine.new(grids, cols, rows, dot: PREVIEW_DOT, fill: PREVIEW_FILL)
    @preview_cols = cols
    @preview_rows = rows
    @dot_colors = {}
    @engine.request_full_redraw
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    apply_preview_changes(@engine.frame(now))
  end

  #一覧の項目を作る（追加した画像を先頭にし、非表示の内蔵素材は除く）
  def items
    builtin_crops = @settings['builtinCrop'] || {}
    hidden_builtins = @settings['hiddenBuiltin'] || []

    user_list = []
    @settings['userImages'].each do |u|
      crop = u['crop'] || 'center'
      crop = crop.to_sym if crop.is_a?(String)
      user_list << { id: u['id'], title: u['title'], artist: '', path: File.join(@data_dir, 'user-images', u['file']), crop: crop, builtin: false }
    end

    builtin_list = []
    @credits.each do |c|
      next if hidden_builtins.include?(c['id'])
      crop = builtin_crops[c['id']] || c['crop'] || 'center'
      crop = crop.to_sym if crop.is_a?(String)
      builtin_list << { id: c['id'], title: c['title'], artist: c['artist'], path: File.join(@paintings_dir, c['file']), crop: crop, builtin: true }
    end

    user_list + builtin_list
  end

  #プレビューの変わったドットを裏画面へ塗る（引数changesは変わったドット）
  def apply_preview_changes(changes)
    return if changes.nil? || changes.empty?
    rects, _cards = SettingsLayout.layout(@width, @height, items.length, @scroll)
    px = @preview_offset_x || rects[:preview][0]
    py = @preview_offset_y || rects[:preview][1]
    changes.each do |col, row, rgb|
      @dot_colors[row * @preview_cols + col] = rgb
      x, y, w, h = RenderMath.dot_rect(col, row, PREVIEW_DOT, PREVIEW_FILL)
      @buffer.fill([px + x, py + y, w, h], rgb)
    end
    union = RenderMath.union_rect(changes, PREVIEW_DOT)
    invalidate([px + union[0], py + union[1], union[2], union[3]]) if union
  end

  #タイマー（プレビューの時間を進める。切り替え中は速く、表示中は間引く）
  #スイッチの移動アニメーションを進める（引数dtは経過秒数。戻り値は動いているか）
  def update_switch_animations(dt)
    targets = {
      autostart: (@settings['autostart'] ? 1.0 : 0.0),
      wallpaper: (@settings['wallpaper'] ? 1.0 : 0.0),
      saver: (Platform.screensaver_active? ? 1.0 : 0.0)
    }
    moving = false
    speed = 9.0
    targets.each do |key, target|
      current = @switch_anims[key] || 0.0
      next if current == target
      moving = true
      diff = target - current
      step = dt * speed
      if diff.abs <= step
        @switch_anims[key] = target
      else
        @switch_anims[key] = current + (diff > 0 ? step : -step)
      end
    end
    moving
  end

  def on_tick
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    dt = now - @last_tick_at
    @last_tick_at = now
    @engine_time += dt
    anim_moving = update_switch_animations(dt)
    redraw_all if anim_moving
    if @engine.needs_redraw?(now)
      apply_preview_changes(@engine.frame(now))
      set_timer(TIMER_TICK, 16)
    elsif anim_moving
      invalidate
      set_timer(TIMER_TICK, 16)
    else
      set_timer(TIMER_TICK, 250)
    end
  end

  #全体を裏画面へ描く
  def redraw_all
    rects, cards = SettingsLayout.layout(@width, @height, items.length, @scroll)
    @buffer.fill_all(BG)
    draw_preview(rects)
    draw_grid(rects, cards)
    autostart_label = @settings['autostart'] ? 'ログイン時起動 ON' : 'ログイン時起動 OFF'
    draw_toggle_button(rects[:autostart], autostart_label, :autostart, @hover == :autostart)
    draw_button(rects[:solid], '🎨', :normal, @hover == :solid)
    draw_button(rects[:add], '＋', :normal, @hover == :add)
    draw_toggle_button(rects[:wallpaper], '壁紙', :wallpaper, @hover == :wallpaper)
    draw_toggle_button(rects[:saver], 'スクリーンセーバー', :saver, @hover == :saver)
  end

  #プレビューを描く（引数rectsは配置）
  def draw_preview(rects)
    x, y, w, h = rects[:preview]
    @buffer.fill([x, y, w, h], PREVIEW_BG)
    ox = @preview_offset_x || x
    oy = @preview_offset_y || y
    pw = (@preview_cols || 1) * PREVIEW_DOT
    ph = (@preview_rows || 1) * PREVIEW_DOT
    @buffer.fill([ox, oy, pw, ph], PREVIEW_BG)
    @dot_colors.each do |i, rgb|
      col = i % @preview_cols
      row = i / @preview_cols
      dx, dy, dw, dh = RenderMath.dot_rect(col, row, PREVIEW_DOT, PREVIEW_FILL)
      @buffer.fill([ox + dx, oy + dy, dw, dh], rgb)
    end
  end

  #一覧を描く（引数rectsは配置、引数cardsは項目と矩形の組）
  def draw_grid(rects, cards)
    gx, gy, gw, gh = rects[:grid]
    rgn = Platform.CreateRectRgn(gx, gy, gx + gw, gy + gh)
    Platform.SelectClipRgn(@buffer.dc, rgn)
    list = items
    cards.each do |index, rect|
      draw_card(list[index], rect, index)
    end
    Platform.SelectClipRgn(@buffer.dc, nil)
    Platform.DeleteObject(rgn)
  end

  #チェックボックスを描く（引数rectは矩形、引数checkedは選択中か、引数hoverはホバー中か）
  def draw_checkbox(rect, checked, hover)
    x, y, w, h = rect
    hdc = @buffer.dc

    if checked
      bg_color = hover ? ACCENT_HOVER : ACCENT
      border_color = bg_color
    else
      bg_color = [24, 24, 30]
      border_color = hover ? [215, 215, 235] : [135, 135, 150]
    end

    r_bg, g_bg, b_bg = bg_color
    r_bd, g_bd, b_bd = border_color

    brush = Platform.CreateSolidBrush(r_bg | (g_bg << 8) | (b_bg << 16))
    pen = Platform.CreatePen(Platform::PS_SOLID, 2, r_bd | (g_bd << 8) | (b_bd << 16))
    old_brush = Platform.SelectObject(hdc, brush)
    old_pen = Platform.SelectObject(hdc, pen)

    Platform.RoundRect(hdc, x, y, x + w, y + h, 6, 6)

    Platform.SelectObject(hdc, old_brush)
    Platform.SelectObject(hdc, old_pen)
    Platform.DeleteObject(brush)
    Platform.DeleteObject(pen)

    if checked
      draw_text('✓', [x, y, w, h], @font_body, [255, 255, 255], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
    end
  end

  #角丸アイコンボタンを描く（引数rectは矩形、引数iconは文字、引数hoverはホバー中か、引数kindは種類）
  def draw_icon_button(rect, icon, hover, kind = :accent)
    x, y, w, h = rect
    hdc = @buffer.dc

    if hover
      if kind == :danger
        bg_color = [180, 40, 40]
        border_color = [220, 80, 80]
      else
        bg_color = ACCENT
        border_color = ACCENT_HOVER
      end
      text_color = [255, 255, 255]
    else
      bg_color = [24, 24, 30]
      border_color = [110, 110, 125]
      text_color = [210, 210, 220]
    end

    r_bg, g_bg, b_bg = bg_color
    r_bd, g_bd, b_bd = border_color

    brush = Platform.CreateSolidBrush(r_bg | (g_bg << 8) | (b_bg << 16))
    pen = Platform.CreatePen(Platform::PS_SOLID, 1, r_bd | (g_bd << 8) | (b_bd << 16))
    old_brush = Platform.SelectObject(hdc, brush)
    old_pen = Platform.SelectObject(hdc, pen)

    Platform.RoundRect(hdc, x, y, x + w, y + h, 6, 6)

    Platform.SelectObject(hdc, old_brush)
    Platform.SelectObject(hdc, old_pen)
    Platform.DeleteObject(brush)
    Platform.DeleteObject(pen)

    draw_text(icon, [x, y, w, h], @font_body, text_color, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
  end

  #カードを描く（引数itemは項目、引数rectは矩形、引数indexは番号）
  def draw_card(item, rect, index = nil)
    return if item.nil?
    x, y, w, h = rect
    card_hover = index && @hover.is_a?(Array) && @hover[1] == index
    base = card_hover ? SURFACE_HOVER : SURFACE
    @buffer.fill(rect, base)
    thumb = thumb_for(item)
    if thumb
      sx, sy, sw, sh = DotArt.croprect(thumb[:w], thumb[:h], 16, 9, item[:crop] || :center)
      Platform.StretchDIBits(@buffer.dc, x, y, w, SettingsLayout::THUMB_H, sx, sy, sw, sh, thumb[:bits], thumb[:info], 0, Platform::SRCCOPY)
    end
    checked = @settings['enabled'].include?(item[:id])
    draw_checkbox([x + 7, y + 7, 24, 24], checked, card_hover)

    is_solid = item[:id].to_s.start_with?('solid_')
    del_hover = index && @hover == [:delete, index]
    crop_hover = index && @hover == [:crop, index]

    draw_icon_button([x + w - 31, y + 7, 24, 24], '×', del_hover, :danger)
    unless is_solid
      draw_icon_button([x + w - 61, y + 7, 24, 24], '✂', crop_hover, :accent)
    end
    lines = wrap_text(item[:title], w - 12, 2)
    lines.each_with_index do |line, i|
      draw_text(line, [x + 6, y + SettingsLayout::THUMB_H + 4 + i * 19, w - 12, 19], @font_body, FG, DT_SINGLELINE | DT_NOPREFIX)
    end
    unless item[:artist].empty?
      draw_text(fit_text(item[:artist], w - 12), [x + 6, y + SettingsLayout::THUMB_H + 4 + lines.length * 19, w - 12, 19], @font_body, SUB, DT_SINGLELINE | DT_NOPREFIX)
    end
  end

#トグルスイッチボタンを描く（引数rectは矩形、引数labelは文字、引数keyは識別子、引数hoverは乗っているか）
def draw_toggle_button(rect, label, key, hover)
  x, y, w, h = rect
  base = hover ? SURFACE_HOVER : SURFACE
  @buffer.fill(rect, base)

  anim_pos = @switch_anims[key] || 0.0

  track_h = h >= 48 ? 26 : 22
  track_w = (track_h * 1.85).round
  track_y = y + (h - track_h) / 2
  track_x = x + w - track_w - 14

  text_rect = [x + 14, y, track_x - x - 20, h]
  text_color = hover ? [255, 255, 255] : FG
  font = h >= 48 ? @font_button : @font_body
  draw_text(label, text_rect, font, text_color, DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX)

  draw_toggle_switch(@buffer.dc, [track_x, track_y, track_w, track_h], anim_pos)
end

#スイッチのピル形状とノブを描く（引数hdcは描画先、引数track_rectは[x, y, w, h]、引数anim_posは0.0〜1.0）
def draw_toggle_switch(hdc, track_rect, anim_pos)
  tx, ty, tw, th = track_rect
  off_color = [60, 60, 70]
  on_color = [11, 92, 173]
  r = (off_color[0] + (on_color[0] - off_color[0]) * anim_pos).round
  g = (off_color[1] + (on_color[1] - off_color[1]) * anim_pos).round
  b = (off_color[2] + (on_color[2] - off_color[2]) * anim_pos).round

  brush = Platform.CreateSolidBrush(r | (g << 8) | (b << 16))
  old_brush = Platform.SelectObject(hdc, brush)
  null_pen = Platform.GetStockObject(Platform::NULL_PEN)
  old_pen = Platform.SelectObject(hdc, null_pen)

  Platform.RoundRect(hdc, tx, ty, tx + tw, ty + th, th, th)

  pad = 3
  knob_d = th - pad * 2
  travel = tw - knob_d - pad * 2
  kx = tx + pad + (travel * anim_pos).round
  ky = ty + pad

  knob_brush = Platform.CreateSolidBrush(0x00FFFFFF)
  Platform.SelectObject(hdc, knob_brush)
  Platform.Ellipse(hdc, kx, ky, kx + knob_d, ky + knob_d)

  Platform.SelectObject(hdc, old_brush)
  Platform.SelectObject(hdc, old_pen)
  Platform.DeleteObject(brush)
  Platform.DeleteObject(knob_brush)
end

#ボタンを描く（引数rectは矩形、引数labelは文字、引数kindは種類、引数hoverは上に乗っているかどうか）
def draw_button(rect, label, kind, hover)
    base = if kind == :accent
             hover ? ACCENT_HOVER : ACCENT
           else
             hover ? SURFACE_HOVER : SURFACE
           end
    @buffer.fill(rect, base)
    draw_text(label, rect, @font_button, [255, 255, 255], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
  end

  #文字を描く（引数textは文字、引数rectは矩形、引数fontはフォント、引数rgbは色、引数flagsは寄せ方）
  def draw_text(text, rect, font, rgb, flags)
    dc = @buffer.dc
    Platform.SelectObject(dc, font)
    Platform.SetTextColor(dc, RenderMath.colorref(rgb))
    Platform.SetBkMode(dc, 1)
    wide = Platform.wide(text)
    ptr = Fiddle::Pointer.malloc(wide.bytesize)
    ptr[0, wide.bytesize] = wide
    Platform.DrawTextW(dc, ptr, -1, rect_pointer(rect), flags)
  end

  #文字の幅を測る（引数fontはフォント、引数textは文字）
  def text_width(font, text)
    Platform.SelectObject(@buffer.dc, font)
    wide = Platform.wide(text)
    ptr = Fiddle::Pointer.malloc(wide.bytesize)
    ptr[0, wide.bytesize] = wide
    size_ptr = Fiddle::Pointer.malloc(8)
    Platform.GetTextExtentPoint32W(@buffer.dc, ptr, text.length, size_ptr)
    size_ptr[0, 4].unpack1('l<')
  end

  #文字を幅に収める（引数textは文字、引数max_widthは幅）
  def fit_text(text, max_width)
    return text if text_width(@font_body, text) <= max_width
    t = text.dup
    t = t[0...-1] while t.length > 1 && text_width(@font_body, "#{t}…") > max_width
    "#{t}…"
  end

  #文字を折り返す（引数textは文字、引数max_widthは幅、引数max_linesは行数）
  def wrap_text(text, max_width, max_lines)
    lines = []
    rest = text.dup
    while lines.length < max_lines && !rest.empty?
      if text_width(@font_body, rest) <= max_width
        lines << rest
        rest = ''
        break
      end
      cut = rest.length
      cut -= 1 while cut > 1 && text_width(@font_body, rest[0...cut]) > max_width
      if lines.length == max_lines - 1
        lines << fit_text(rest, max_width)
        rest = ''
      else
        lines << rest[0...cut]
        rest = rest[cut..]
      end
    end
    lines
  end

  #カード用の縮小画像を返す（引数itemは項目。戻り値は幅と高さと画素とBITMAPINFOの組、読めなければnil）
  def thumb_for(item)
    return @thumbs[item[:id]] if @thumbs.key?(item[:id])
    w, h, bgra = Wic.decode_thumb_bgra(item[:path], SettingsLayout::CARD_W * 2, SettingsLayout::THUMB_H * 2)
    bits = Fiddle::Pointer.malloc(bgra.bytesize)
    bits[0, bgra.bytesize] = bgra
    info = Fiddle::Pointer.malloc(40)
    header = [40, w, -h, 1, 32, 0, w * h * 4, 0, 0, 0, 0].pack('L<l<l<vvL<L<l<l<L<L<')
    info[0, 40] = header
    @thumbs[item[:id]] = { w: w, h: h, bits: bits, info: info }
  rescue StandardError
    @thumbs[item[:id]] = nil
  end

  #マウスが乗った対象を覚える（引数lparamは座標）
  def on_mouse_move(lparam)
    mx, my = mouse_pos(lparam)
    rects, cards = SettingsLayout.layout(@width, @height, items.length, @scroll)
    hover = SettingsLayout.hit_test(rects, cards, mx, my)
    if hover.is_a?(Array) && hover[0] == :crop
      list = items
      item = list[hover[1]]
      hover = [:card, hover[1]] if item && item[:id].to_s.start_with?('solid_')
    end
    return if hover == @hover
    @hover = hover
    redraw_all
    invalidate
  end

  #クリックの処理（引数lparamは座標）
  #クリックの処理（引数lparamは座標）
  def on_click(lparam)
    mx, my = mouse_pos(lparam)
    list = items
    rects, cards = SettingsLayout.layout(@width, @height, list.length, @scroll)
    target = SettingsLayout.hit_test(rects, cards, mx, my)
    case target
    when :autostart
      @settings['autostart'] = !@settings['autostart']
      apply_autostart
      persist
      set_timer(TIMER_TICK, 16)
    when :solid
      add_solid_color_via_dialog
    when :add
      add_images_via_dialog
    when :wallpaper
      toggle_wallpaper
      set_timer(TIMER_TICK, 16)
    when :saver
      toggle_screensaver
      set_timer(TIMER_TICK, 16)
    when Array
      kind, index = target
      item = list[index]
      if kind == :delete
        delete_item(item)
      elsif kind == :crop && !item[:id].to_s.start_with?('solid_')
        edit_image_crop(item)
      elsif kind == :card
        toggle_check(item)
      end
    end
    redraw_all
    invalidate
  end

  #ホイールで一覧をスクロールする（引数wparamはホイールの情報）
  def on_wheel(wparam)
    raw = (wparam.to_i >> 16) & 0xFFFF
    delta = raw >= 0x8000 ? raw - 0x10000 : raw
    rects, _cards = SettingsLayout.layout(@width, @height, items.length, @scroll)
    max_scroll = SettingsLayout.max_scroll(rects, items.length)
    @scroll = [[@scroll - (delta / 120) * 40, 0].max, max_scroll].min
    redraw_all
    invalidate
  end

  #マウス座標を取り出す（引数lparamは座標）
  def mouse_pos(lparam)
    value = lparam.to_i
    x = value & 0xFFFF
    y = (value >> 16) & 0xFFFF
    x -= 0x10000 if x >= 0x8000
    y -= 0x10000 if y >= 0x8000
    [x, y]
  end

  #チェックを切り替える（引数itemは項目、最後の1枚は外せない）
  def toggle_check(item)
    if @settings['enabled'].include?(item[:id])
      return if @settings['enabled'].length <= 1
      @settings['enabled'] = @settings['enabled'].reject { |id| id == item[:id] }
    else
      @settings['enabled'] << item[:id]
    end
    persist
  end

  #項目を削除または非表示にする（引数itemは項目）
  def delete_item(item)
    return if item.nil?
    if item[:builtin]
      @settings['hiddenBuiltin'] ||= []
      @settings['hiddenBuiltin'] << item[:id] unless @settings['hiddenBuiltin'].include?(item[:id])
    else
      @settings['userImages'] = @settings['userImages'].reject { |u| u['id'] == item[:id] }
      File.delete(item[:path]) rescue nil
    end
    @settings['enabled'] = @settings['enabled'].reject { |id| id == item[:id] }
    @thumbs.delete(item[:id])
    if @settings['enabled'].empty?
      first = items.first
      @settings['enabled'] = [first[:id]] if first
    end
    persist
  end

  #ファイルを選んで画像を足す
  #色を選んで単色画像を足す
  def add_solid_color_via_dialog
    rgb = Platform::API_READY ? Platform.choose_color_dialog(@hwnd) : nil
    return if rgb.nil?

    r, g, b = rgb
    hex = sprintf('#%02X%02X%02X', r, g, b)
    id = "solid_#{sprintf('%02x%02x%02x', r, g, b)}_#{SecureRandom.hex(2)}"
    file = "#{id}.bmp"
    dest_dir = File.join(@data_dir, 'user-images')
    FileUtils.mkdir_p(dest_dir)
    bmp_path = File.join(dest_dir, file)
    File.binwrite(bmp_path, create_solid_bmp(r, g, b))

    title = "単色 (#{hex})"
    @settings['userImages'].unshift({ 'id' => id, 'file' => file, 'title' => title, 'crop' => 'center' })
    @settings['enabled'].unshift(id)
    persist
    build_preview
  end

  #単色のBMP画像データを作る（引数r, g, bは色、引数wとhは大きさ）
  def create_solid_bmp(r, g, b, w = 16, h = 9)
    row_bytes = (w * 3 + 3) & ~3
    image_size = row_bytes * h
    file_size = 54 + image_size
    file_header = ['BM', file_size, 0, 0, 54].pack('a2L<S<S<L<')
    info_header = [40, w, h, 1, 24, 0, image_size, 2835, 2835, 0, 0].pack('L<l<l<S<S<L<L<l<l<L<L<')
    pad = "\x00" * (row_bytes - w * 3)
    pixel = [b, g, r].pack('C3')
    row = (pixel * w) + pad
    file_header + info_header + (row * h)
  end

  #ファイルを選んで画像を足す（切り取り範囲を調整してから保存する）
  def add_images_via_dialog
    paths = Platform::API_READY ? Platform.open_image_dialog : []
    added = false
    paths.each do |path|
      ext = File.extname(path).downcase
      next unless %w[.jpg .jpeg .png].include?(ext)

      crop_win = CropWindow.new(image_path: path, parent_hwnd: @hwnd)
      crop = crop_win.run_modal
      next if crop.nil?

      id = "user_#{SecureRandom.hex(3)}"
      file = "#{id}#{ext}"
      dest_dir = File.join(@data_dir, 'user-images')
      FileUtils.mkdir_p(dest_dir)
      FileUtils.cp(path, File.join(dest_dir, file))
      title = File.basename(path, ext)
      @settings['userImages'].unshift({ 'id' => id, 'file' => file, 'title' => title, 'crop' => crop })
      @settings['enabled'].unshift(id)
      added = true
    end
    if added
      persist
      build_preview
    end
  end

  #画像の切り取り位置を変更する
  def edit_image_crop(item)
    crop_win = CropWindow.new(image_path: item[:path], initial_crop: item[:crop], parent_hwnd: @hwnd)
    crop = crop_win.run_modal
    return if crop.nil?

    if item[:builtin]
      @settings['builtinCrop'] ||= {}
      @settings['builtinCrop'][item[:id]] = crop
    else
      target = @settings['userImages'].find { |u| u['id'] == item[:id] }
      target['crop'] = crop if target
    end
    persist
    @thumbs.delete(item[:id])
    build_preview
  end

  #壁紙プロセスの実際の状態と設定を合わせる
  def sync_wallpaper_state
    pid_path = File.join(@data_dir, 'wallpaper.pid')
    running = false
    if File.exist?(pid_path)
      pid = File.read(pid_path).strip.to_i
      running = Platform.process_alive?(pid)
      File.delete(pid_path) unless running
    end
    if @settings['wallpaper'] && !running
      start_wallpaper
    end
  end

  #壁紙の開始と停止
  def toggle_wallpaper
    if @settings['wallpaper']
      stop_wallpaper
    else
      start_wallpaper
    end
    persist
  end

  #壁紙を表示する（常駐プロセスがいれば再表示、いなければ起動する）
  #Windowsの壁紙は書き換えない（ドット絵のウィンドウが写真の手前を覆うため不要で、書き換えるとDefenderに怪しまれる）
  def start_wallpaper
    tray_hwnd = Platform::API_READY ? Platform.FindWindowW(Platform.wide('PixelWaveTrayHelper'), nil) : nil
    if tray_hwnd && !tray_hwnd.null?
      Platform.PostMessageW(tray_hwnd, Platform::WM_USER_SHOW_WALLPAPER, 0, 0)
    else
      command = self_command(['--wallpaper'])
      err_log = File.join(@data_dir, 'wallpaper_error.log')
      app_root = File.expand_path('..', __dir__)
      pid = spawn(*command, chdir: app_root, [:out, :err] => [err_log, 'a'])
      Process.detach(pid)
      File.write(File.join(@data_dir, 'wallpaper.pid'), pid.to_s)
    end
    @settings['wallpaper'] = true
    apply_autostart
  end

  #ログイン時の起動を設定に合わせる（オンで壁紙が動いているときだけ、スタートアップにショートカットを置く）
  def apply_autostart
    if @settings['autostart'] && @settings['wallpaper']
      command = self_command(['--wallpaper'])
      Platform.create_startup_shortcut(command[0], command[1..])
    else
      Platform.delete_startup_shortcut
    end
  end

  #壁紙を非表示にする（プロセスとトレイ常駐は維持する）
  def stop_wallpaper
    tray_hwnd = Platform::API_READY ? Platform.FindWindowW(Platform.wide('PixelWaveTrayHelper'), nil) : nil
    if tray_hwnd && !tray_hwnd.null?
      Platform.PostMessageW(tray_hwnd, Platform::WM_USER_HIDE_WALLPAPER, 0, 0)
    end
    @settings['wallpaper'] = false
    apply_autostart
  end
  #スクリーンセーバーの有効化と無効化を切り替える
  def toggle_screensaver
    if Platform.screensaver_active?
      Platform.disable_screensaver
    else
      Platform.enable_screensaver
    end
    redraw_all
    invalidate
  end

  #設定を保存してプレビューを作り直す
  def persist
    AppSettings.save(@data_dir, @settings)
    build_preview
    redraw_all
    invalidate
  end

  #自分の起動コマンドを返す（引数extraは追加の引数。exe化されていればそのパス、無ければRubyとmain.rb）
  def self_command(extra)
    if ENV['OCRAN_EXECUTABLE']
      [ENV['OCRAN_EXECUTABLE'], *extra]
    else
      [RbConfig.ruby, '-Ilib', File.expand_path('../main.rb', __dir__), *extra]
    end
  end
end
