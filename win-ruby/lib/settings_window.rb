#設定画面（GDIで描く。プレビューと絵の一覧と2つのボタンだけ）
#裏画面に描き、操作があったときとプレビューが動いているときだけ描き直す
require 'fileutils'
require 'securerandom'
require_relative 'window'
require_relative 'engine'
require_relative 'loader'
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
  DT_END_ELLIPSIS = 0x8000

  BG = [24, 24, 28].freeze
  SURFACE = [40, 40, 47].freeze
  SURFACE_HOVER = [56, 56, 65].freeze
  FG = [238, 238, 242].freeze
  SUB = [178, 178, 190].freeze
  ACCENT = [11, 92, 173].freeze
  ACCENT_HOVER = [16, 108, 199].freeze
  CHECK = [120, 190, 255].freeze
  PREVIEW_BG = [20, 20, 24].freeze

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

  #プレビュー用のエンジンを作り直す
  def build_preview
    list = Loader.paintings(@settings, @paintings_dir, @data_dir)
    rects, _cards = SettingsLayout.layout(@width, @height, items.length, @scroll)
    cols = [(rects[:preview][2] / WaveEngine::DOT.to_f).ceil, 1].max
    rows = [(rects[:preview][3] / WaveEngine::DOT.to_f).ceil, 1].max
    grids = Loader.grids(list, cols, rows, Platform.cache_dir, Wic.method(:decode))
    @engine = WaveEngine.new(grids, cols, rows)
    @preview_cols = cols
    @dot_colors = {}
    @engine.request_full_redraw
    apply_preview_changes(@engine.frame(@engine_time))
  end

  #一覧の項目を作る（素材と追加した画像）
  def items
    list = @credits.map do |c|
      { id: c['id'], title: c['title'], artist: c['artist'], path: File.join(@paintings_dir, c['file']), builtin: true }
    end
    @settings['userImages'].each do |u|
      list << { id: u['id'], title: u['title'], artist: '', path: File.join(@data_dir, 'user-images', u['file']), builtin: false }
    end
    list
  end

  #プレビューの変わったドットを裏画面へ塗る（引数changesは変わったドット）
  def apply_preview_changes(changes)
    return if changes.nil? || changes.empty?
    rects, _cards = SettingsLayout.layout(@width, @height, items.length, @scroll)
    px, py = rects[:preview][0], rects[:preview][1]
    changes.each do |col, row, rgb|
      @dot_colors[row * @preview_cols + col] = rgb
      x, y, w, h = RenderMath.dot_rect(col, row, WaveEngine::DOT, WaveEngine::FILL)
      @buffer.fill([px + x, py + y, w, h], rgb)
    end
    union = RenderMath.union_rect(changes, WaveEngine::DOT)
    invalidate([px + union[0], py + union[1], union[2], union[3]]) if union
  end

  #タイマー（プレビューの時間を進める。切り替え中は速く、表示中は間引く）
  def on_tick
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    dt = now - @last_tick_at
    @last_tick_at = now
    @engine_time += dt
    apply_preview_changes(@engine.frame(@engine_time))
    set_timer(TIMER_TICK, @engine.needs_redraw?(@engine_time) ? 16 : 250)
  end

  #全体を裏画面へ描く
  def redraw_all
    rects, cards = SettingsLayout.layout(@width, @height, items.length, @scroll)
    @buffer.fill_all(BG)
    draw_preview(rects)
    draw_grid(rects, cards)
    draw_button(rects[:add], '＋', :normal, @hover == :add)
    draw_button(rects[:wallpaper], @settings['wallpaper'] ? '壁紙を止める' : '壁紙にする', :accent, @hover == :wallpaper)
    draw_button(rects[:saver], 'スクリーンセーバーにする', :normal, @hover == :saver)
  end

  #プレビューを描く（引数rectsは配置）
  def draw_preview(rects)
    x, y, w, h = rects[:preview]
    @buffer.fill([x, y, w, h], PREVIEW_BG)
    @dot_colors.each do |i, rgb|
      col = i % @preview_cols
      row = i / @preview_cols
      dx, dy, dw, dh = RenderMath.dot_rect(col, row, WaveEngine::DOT, WaveEngine::FILL)
      @buffer.fill([x + dx, y + dy, dw, dh], rgb)
    end
  end

  #一覧を描く（引数rectsは配置、引数cardsは項目と矩形の組）
  def draw_grid(rects, cards)
    gx, gy, gw, gh = rects[:grid]
    rgn = Platform.CreateRectRgn(gx, gy, gx + gw, gy + gh)
    Platform.SelectClipRgn(@buffer.dc, rgn)
    list = items
    cards.each do |index, rect|
      draw_card(list[index], rect)
    end
    Platform.SelectClipRgn(@buffer.dc, nil)
    Platform.DeleteObject(rgn)
  end

  #カードを描く（引数itemは項目、引数rectは矩形）
  def draw_card(item, rect)
    return if item.nil?
    x, y, w, h = rect
    @buffer.fill(rect, SURFACE)
    thumb = thumb_for(item)
    if thumb
      sx, sy, sw, sh = DotArt.croprect(thumb[:w], thumb[:h], 16, 9, :center)
      Platform.StretchDIBits(@buffer.dc, x, y, w, SettingsLayout::THUMB_H, sx, sy, sw, sh, thumb[:bits], thumb[:info], 0, Platform::SRCCOPY)
    end
    checked = @settings['enabled'].include?(item[:id])
    @buffer.fill([x + 6, y + 6, 26, 26], PREVIEW_BG)
    draw_text('✓', [x + 6, y + 4, 26, 26], @font_body, CHECK, DT_CENTER | DT_SINGLELINE) if checked
    draw_text('×', [x + w - 30, y + 2, 26, 26], @font_body, FG, DT_CENTER | DT_SINGLELINE) unless item[:builtin]
    lines = wrap_text(item[:title], w - 12, 2)
    lines.each_with_index do |line, i|
      draw_text(line, [x + 6, y + SettingsLayout::THUMB_H + 4 + i * 19, w - 12, 19], @font_body, FG, DT_SINGLELINE | DT_NOPREFIX)
    end
    unless item[:artist].empty?
      draw_text(fit_text(item[:artist], w - 12), [x + 6, y + SettingsLayout::THUMB_H + 4 + lines.length * 19, w - 12, 19], @font_body, SUB, DT_SINGLELINE | DT_NOPREFIX)
    end
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
    hover = hover[0] if hover.is_a?(Array)
    return if hover == @hover
    @hover = hover
    redraw_all
    invalidate
  end

  #クリックの処理（引数lparamは座標）
  def on_click(lparam)
    mx, my = mouse_pos(lparam)
    list = items
    rects, cards = SettingsLayout.layout(@width, @height, list.length, @scroll)
    target = SettingsLayout.hit_test(rects, cards, mx, my)
    case target
    when :add
      add_images_via_dialog
    when :wallpaper
      toggle_wallpaper
    when :saver
      register_screensaver
    when Array
      kind, index = target
      item = list[index]
      if kind == :delete && !item[:builtin]
        delete_user_image(item)
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

  #追加した画像を消す（引数itemは項目）
  def delete_user_image(item)
    @settings['userImages'] = @settings['userImages'].reject { |u| u['id'] == item[:id] }
    @settings['enabled'] = @settings['enabled'].reject { |id| id == item[:id] }
    @thumbs.delete(item[:id])
    File.delete(item[:path]) rescue nil
    if @settings['enabled'].empty?
      first = items.first
      @settings['enabled'] = [first[:id]] if first
    end
    persist
  end

  #ファイルを選んで画像を足す
  def add_images_via_dialog
    paths = Platform::API_READY ? Platform.open_image_dialog : []
    paths.each do |path|
      ext = File.extname(path).downcase
      next unless %w[.jpg .jpeg .png].include?(ext)
      id = "user_#{SecureRandom.hex(3)}"
      file = "#{id}#{ext}"
      dest_dir = File.join(@data_dir, 'user-images')
      FileUtils.mkdir_p(dest_dir)
      FileUtils.cp(path, File.join(dest_dir, file))
      title = File.basename(path, ext)
      @settings['userImages'] << { 'id' => id, 'file' => file, 'title' => title }
      @settings['enabled'] << id
    end
    persist unless paths.empty?
  end

  #壁紙の開始と停止
  def toggle_wallpaper
    if @settings['wallpaper']
      stop_wallpaper
      @settings['wallpaper'] = false
    else
      start_wallpaper
      @settings['wallpaper'] = true
    end
    AppSettings.save(@data_dir, @settings)
  end

  #壁紙のプロセスを起動する
  def start_wallpaper
    command = self_command(['--wallpaper'])
    pid = spawn(*command)
    Process.detach(pid)
    File.write(File.join(@data_dir, 'wallpaper.pid'), pid.to_s)
    Platform.set_run_entry('PixelWave', command.map { |c| "\"#{c}\"" }.join(' '))
  end

  #壁紙のプロセスを止める
  def stop_wallpaper
    pid_path = File.join(@data_dir, 'wallpaper.pid')
    if File.exist?(pid_path)
      pid = File.read(pid_path).strip.to_i
      Platform.kill_process(pid) if pid > 0 && Platform::API_READY
      File.delete(pid_path) rescue nil
    end
    Platform.delete_run_entry('PixelWave')
  end

  #スクリーンセーバーとして登録する
  def register_screensaver
    exe = ENV['OCRAN_EXECUTABLE']
    return if exe.nil?
    dest = File.join(@data_dir, 'PixelWave.scr')
    FileUtils.cp(exe, dest)
    Platform.register_screensaver(dest)
    spawn('control', 'desk.cpl,,@screensaver')
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
      [RbConfig.ruby, File.expand_path('../main.rb', __dir__), *extra]
    end
  end
end
