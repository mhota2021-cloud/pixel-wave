#切り取り範囲の調整ウィンドウ（モニター比率でクロップ枠を移動・リサイズする）
require_relative 'window'
require_relative 'wic'
require_relative 'platform'

class CropWindow < NativeWindow
  HANDLE_SIZE = 10
  MIN_CROP_PIXELS = 40

  BG = [24, 24, 28].freeze
  FOOTER_BG = [32, 32, 38].freeze
  FG = [240, 240, 245].freeze
  SUB = [160, 160, 170].freeze
  BORDER = [60, 60, 70].freeze
  BTN_BG = [45, 45, 55].freeze
  BTN_HOVER = [60, 60, 75].freeze
  PRIMARY_BG = [40, 120, 220].freeze
  PRIMARY_HOVER = [50, 140, 245].freeze
  CROP_BORDER = [64, 160, 255].freeze
  HANDLE_COLOR = [255, 255, 255].freeze

  attr_reader :result

  def initialize(image_path:, initial_crop: nil, parent_hwnd: nil, screen_aspect: nil)
    @image_path = image_path
    @parent_hwnd = parent_hwnd

    # モニターの比率（省略時はプライマリ画面の解像度から計算）
    if screen_aspect && screen_aspect > 0
      @screen_aspect = screen_aspect.to_f
    else
      sw, sh = Platform::API_READY ? Platform.primary_screen : [1920, 1080]
      @screen_aspect = (sw > 0 && sh > 0) ? (sw.to_f / sh) : (16.0 / 9.0)
    end

    # 作業領域に合わせたウィンドウサイズ
    win_w = 980
    win_h = 760
    if Platform::API_READY
      _x, _y, work_w, work_h = Platform.work_area
      win_w = [win_w, work_w - 40].min
      win_h = [win_h, work_h - 40].min
    end

    super(
      class_name: 'PixelWaveCropWindowClass',
      title: "切り取り範囲の調整 [画面比率 #{format('%.2f', @screen_aspect)}:1] - Pixel Wave",
      width: win_w,
      height: win_h,
      style: Platform::WS_POPUP | Platform::WS_VISIBLE
    )

    @buffer = BackBuffer.new(@hwnd, @width, @height)
    @font_title = make_font(18, true)
    @font_body = make_font(14, false)
    @font_btn = make_font(14, true)

    # キャンバス領域（画像を表示するエリア）
    @canvas_x = 24
    @canvas_y = 60
    @canvas_w = @width - 48
    @canvas_h = @height - 140

    load_image
    init_crop_norm(initial_crop)

    @dragging = nil # nil, :move, :top_left, :top_right, :bottom_left, :bottom_right
    @drag_start_mouse = [0, 0]
    @drag_start_crop = @crop_norm.dup
    @hover_action = nil
    @result = nil

    redraw_all
    invalidate
  end

  def run_modal
    run
    @result
  end

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
    when WM_LBUTTONDOWN
      on_lbutton_down(lparam)
      0
    when WM_MOUSEMOVE
      on_mouse_move(lparam)
      0
    when WM_LBUTTONUP
      on_lbutton_up
      0
    when WM_KEYDOWN
      key = wparam.to_i
      if key == 13 # Enter
        confirm_crop
      elsif key == 27 # Escape
        cancel_crop
      end
      0
    when WM_DESTROY
      dispose_resources
      Platform.PostQuitMessage(0) if Platform::API_READY
      0
    else
      nil
    end
  end

  private

  def make_font(height, bold)
    return nil unless Platform::API_READY
    Platform.CreateFontW(
      height, 0, 0, 0, bold ? 700 : 400, 0, 0, 0, 1, 0, 0, 0, 0,
      Platform.wide('Yu Gothic UI')
    )
  end

  def load_image
    return unless File.exist?(@image_path)
    # キャンバスに収まる高品質プレビューを生成
    w, h, bgra = Wic.decode_thumb_bgra(@image_path, @canvas_w, @canvas_h)
    return unless w && h && bgra

    @thumb_w = w
    @thumb_h = h
    @img_aspect = w.to_f / h

    # キャンバスの中央に配置
    @img_x = @canvas_x + (@canvas_w - w) / 2
    @img_y = @canvas_y + (@canvas_h - h) / 2

    @bits_bright = Fiddle::Pointer.malloc(bgra.bytesize)
    @bits_bright[0, bgra.bytesize] = bgra

    # 暗い版（背景マスク用、輝度約35%）
    bgra_dark = bgra.dup
    len = w * h * 4
    i = 0
    while i < len
      bgra_dark.setbyte(i, (bgra_dark.getbyte(i) * 0.35).to_i)
      bgra_dark.setbyte(i + 1, (bgra_dark.getbyte(i + 1) * 0.35).to_i)
      bgra_dark.setbyte(i + 2, (bgra_dark.getbyte(i + 2) * 0.35).to_i)
      i += 4
    end
    @bits_dark = Fiddle::Pointer.malloc(bgra_dark.bytesize)
    @bits_dark[0, bgra_dark.bytesize] = bgra_dark

    @bmi = "\x00" * 40
    @bmi[0, 4] = [40].pack('L<')
    @bmi[4, 4] = [w].pack('l<')
    @bmi[8, 4] = [-h].pack('l<') # トップダウンDIB
    @bmi[12, 2] = [1].pack('S<')
    @bmi[14, 2] = [32].pack('S<')
  end

  def init_crop_norm(crop)
    if crop.is_a?(Hash)
      @crop_norm = {
        x: (crop['x'] || crop[:x] || 0.0).to_f,
        y: (crop['y'] || crop[:y] || 0.0).to_f,
        w: (crop['w'] || crop[:w] || 1.0).to_f,
        h: (crop['h'] || crop[:h] || 1.0).to_f
      }
      clamp_crop_norm
      return
    end

    # 初期計算：画像全体に収まる最大サイズのモニター比率枠（中央配置）
    img_asp = (@img_aspect && @img_aspect > 0) ? @img_aspect : 1.0
    scr_asp = (@screen_aspect && @screen_aspect > 0) ? @screen_aspect : (16.0 / 9.0)

    # 初期計算：画像全体に収まる最大サイズのモニター比率枠（中央配置）
    if img_asp > scr_asp
      nw = scr_asp / img_asp
      nh = 1.0
      nx = (1.0 - nw) / 2.0
      ny = 0.0
    else
      nw = 1.0
      nh = img_asp / scr_asp
      nx = 0.0
      ny = (1.0 - nh) / 2.0
    end
    @crop_norm = { x: nx, y: ny, w: nw, h: nh }
  end

  def clamp_crop_norm
    @crop_norm[:w] = [[@crop_norm[:w], 0.05].max, 1.0].min
    @crop_norm[:h] = [[@crop_norm[:h], 0.05].max, 1.0].min
    @crop_norm[:x] = [[@crop_norm[:x], 0.0].max, 1.0 - @crop_norm[:w]].min
    @crop_norm[:y] = [[@crop_norm[:y], 0.0].max, 1.0 - @crop_norm[:h]].min
  end

  def crop_pixel_rect
    return [0, 0, 0, 0] unless @thumb_w && @thumb_h
    bx = @img_x + (@thumb_w * @crop_norm[:x]).round
    by = @img_y + (@thumb_h * @crop_norm[:y]).round
    bw = (@thumb_w * @crop_norm[:w]).round
    bh = (@thumb_h * @crop_norm[:h]).round
    [bx, by, bw, bh]
  end

  def redraw_all
    @buffer.fill_all(BG)
    draw_header
    draw_canvas
    draw_footer
  end

  def draw_header
    draw_text('切り取り範囲の調整', [@canvas_x, 18, 300, 26], @font_title, FG)
    aspect_text = "画面サイズ比率: #{format('%.2f', @screen_aspect)}:1 - 枠をドラッグして移動、四隅で拡大縮小"
    draw_text(aspect_text, [@canvas_x + 220, 22, @width - @canvas_x - 240, 22], @font_body, SUB)
  end

  def draw_canvas
    return unless @bits_dark && @bits_bright

    # 1. 画像全体を暗い版で描画
    Platform.StretchDIBits(
      @buffer.dc, @img_x, @img_y, @thumb_w, @thumb_h,
      0, 0, @thumb_w, @thumb_h,
      @bits_dark, @bmi, 0, Platform::SRCCOPY
    )

# 2. クロップ枠の領域だけ明るい版で描画（GDIのStretchDIBitsのySrc反転を回避するためクリッピング領域を使用）
bx, by, bw, bh = crop_pixel_rect
rgn = Platform.CreateRectRgn(bx, by, bx + bw, by + bh)
Platform.SelectClipRgn(@buffer.dc, rgn)
Platform.StretchDIBits(
  @buffer.dc, @img_x, @img_y, @thumb_w, @thumb_h,
  0, 0, @thumb_w, @thumb_h,
  @bits_bright, @bmi, 0, Platform::SRCCOPY
)
Platform.SelectClipRgn(@buffer.dc, nil)
Platform.DeleteObject(rgn)

    # 3. 枠線の描画（水色）
    draw_rect_outline([bx, by, bw, bh], CROP_BORDER, 2)

    # 4. 四隅のハンドルの描画（白正方形）
    draw_handles(bx, by, bw, bh)
  end

  def draw_handles(bx, by, bw, bh)
    half = HANDLE_SIZE / 2
    handles = [
      [bx - half, by - half],                      # top-left
      [bx + bw - half, by - half],                 # top-right
      [bx - half, by + bh - half],                 # bottom-left
      [bx + bw - half, by + bh - half],            # bottom-right
    ]
    handles.each do |hx, hy|
      @buffer.fill([hx, hy, HANDLE_SIZE, HANDLE_SIZE], HANDLE_COLOR)
      draw_rect_outline([hx, hy, HANDLE_SIZE, HANDLE_SIZE], BORDER, 1)
    end
  end

  def draw_footer
    fy = @height - 70
    @buffer.fill([0, fy, @width, 70], FOOTER_BG)
    @buffer.fill([0, fy, @width, 1], BORDER)

    # ボタン矩形
    btn_w = 110
    btn_h = 36
    btn_y = fy + 17

    @rect_confirm = [@width - 24 - btn_w, btn_y, btn_w, btn_h]
    @rect_cancel = [@width - 24 - btn_w * 2 - 12, btn_y, btn_w, btn_h]
    @rect_reset = [24, btn_y, btn_w, btn_h]

    draw_button(@rect_reset, '中央に戻す', @hover_action == :reset ? BTN_HOVER : BTN_BG, FG)
    draw_button(@rect_cancel, 'キャンセル', @hover_action == :cancel ? BTN_HOVER : BTN_BG, FG)
    draw_button(@rect_confirm, '決定 (Enter)', @hover_action == :confirm ? PRIMARY_HOVER : PRIMARY_BG, [255, 255, 255])
  end

  def draw_button(rect, text, bg_color, text_color)
    @buffer.fill(rect, bg_color)
    draw_rect_outline(rect, BORDER, 1)
    x, y, w, h = rect
    draw_text_center(text, [x, y + 8, w, h], @font_btn, text_color)
  end

  def draw_rect_outline(rect, color, thickness)
    x, y, w, h = rect
    @buffer.fill([x, y, w, thickness], color) # 上
    @buffer.fill([x, y + h - thickness, w, thickness], color) # 下
    @buffer.fill([x, y, thickness, h], color) # 左
    @buffer.fill([x + w - thickness, y, thickness, h], color) # 右
  end

  def hit_test_handle(mx, my)
    bx, by, bw, bh = crop_pixel_rect
    half = HANDLE_SIZE
    return :top_left if (mx - bx).abs <= half && (my - by).abs <= half
    return :top_right if (mx - (bx + bw)).abs <= half && (my - by).abs <= half
    return :bottom_left if (mx - bx).abs <= half && (my - (by + bh)).abs <= half
    return :bottom_right if (mx - (bx + bw)).abs <= half && (my - (by + bh)).abs <= half
    return :move if mx >= bx && mx <= bx + bw && my >= by && my <= by + bh
    nil
  end

  def in_rect?(mx, my, rect)
    return false unless rect
    x, y, w, h = rect
    mx >= x && mx <= x + w && my >= y && my <= y + h
  end

  def on_lbutton_down(lparam)
    mx, my = mouse_pos(lparam)

    if in_rect?(mx, my, @rect_confirm)
      confirm_crop
      return
    elsif in_rect?(mx, my, @rect_cancel)
      cancel_crop
      return
    elsif in_rect?(mx, my, @rect_reset)
      init_crop_norm(nil)
      redraw_all
      invalidate
      return
    end

    target = hit_test_handle(mx, my)
    if target
      @dragging = target
      @drag_start_mouse = [mx, my]
      @drag_start_crop = @crop_norm.dup
    end
  end

  def on_mouse_move(lparam)
    mx, my = mouse_pos(lparam)

    if @dragging
      handle_drag(mx, my)
      redraw_all
      invalidate
      return
    end

    # ホバー状態の更新
    old_hover = @hover_action
    if in_rect?(mx, my, @rect_confirm)
      @hover_action = :confirm
    elsif in_rect?(mx, my, @rect_cancel)
      @hover_action = :cancel
    elsif in_rect?(mx, my, @rect_reset)
      @hover_action = :reset
    else
      @hover_action = nil
    end

    if old_hover != @hover_action
      redraw_all
      invalidate
    end
  end

  def handle_drag(mx, my)
    dx = mx - @drag_start_mouse[0]
    dy = my - @drag_start_mouse[1]
    return if @thumb_w.nil? || @thumb_w <= 0 || @thumb_h.nil? || @thumb_h <= 0

    dnx = dx.to_f / @thumb_w
    dny = dy.to_f / @thumb_h
    start = @drag_start_crop

    case @dragging
    when :move
      @crop_norm[:x] = [[start[:x] + dnx, 0.0].max, 1.0 - start[:w]].min
      @crop_norm[:y] = [[start[:y] + dny, 0.0].max, 1.0 - start[:h]].min
    when :bottom_right
      # アスペクト比を保ちながら右下を移動
      scale = @thumb_w.to_f / @thumb_h
      dw = dnx
      dh = dw * (@img_aspect / @screen_aspect)
      new_w = [[start[:w] + dw, 0.08].max, 1.0 - start[:x]].min
      new_h = new_w * (@img_aspect / @screen_aspect)
      if start[:y] + new_h > 1.0
        new_h = 1.0 - start[:y]
        new_w = new_h * (@screen_aspect / @img_aspect)
      end
      @crop_norm[:w] = new_w
      @crop_norm[:h] = new_h
    when :bottom_left
      dw = -dnx
      new_w = [[start[:w] + dw, 0.08].max, start[:x] + start[:w]].min
      new_h = new_w * (@img_aspect / @screen_aspect)
      if start[:y] + new_h > 1.0
        new_h = 1.0 - start[:y]
        new_w = new_h * (@screen_aspect / @img_aspect)
      end
      @crop_norm[:x] = start[:x] + start[:w] - new_w
      @crop_norm[:w] = new_w
      @crop_norm[:h] = new_h
    when :top_right
      dw = dnx
      new_w = [[start[:w] + dw, 0.08].max, 1.0 - start[:x]].min
      new_h = new_w * (@img_aspect / @screen_aspect)
      if start[:y] + start[:h] - new_h < 0.0
        new_h = start[:y] + start[:h]
        new_w = new_h * (@screen_aspect / @img_aspect)
      end
      @crop_norm[:y] = start[:y] + start[:h] - new_h
      @crop_norm[:w] = new_w
      @crop_norm[:h] = new_h
    when :top_left
      dw = -dnx
      new_w = [[start[:w] + dw, 0.08].max, start[:x] + start[:w]].min
      new_h = new_w * (@img_aspect / @screen_aspect)
      if start[:y] + start[:h] - new_h < 0.0
        new_h = start[:y] + start[:h]
        new_w = new_h * (@screen_aspect / @img_aspect)
      end
      @crop_norm[:x] = start[:x] + start[:w] - new_w
      @crop_norm[:y] = start[:y] + start[:h] - new_h
      @crop_norm[:w] = new_w
      @crop_norm[:h] = new_h
    end
    clamp_crop_norm
  end

  def on_lbutton_up
    @dragging = nil
  end

  def confirm_crop
    @result = {
      'x' => @crop_norm[:x].round(4),
      'y' => @crop_norm[:y].round(4),
      'w' => @crop_norm[:w].round(4),
      'h' => @crop_norm[:h].round(4)
    }
    close
  end

  def cancel_crop
    @result = nil
    close
  end

  def mouse_pos(lparam)
    value = lparam.to_i
    x = value & 0xFFFF
    y = (value >> 16) & 0xFFFF
    x -= 0x10000 if x >= 0x8000
    y -= 0x10000 if y >= 0x8000
    [x, y]
  end

  def draw_text(text, rect, font, color)
    return unless Platform::API_READY
    Platform.SelectObject(@buffer.dc, font) if font
    Platform.SetTextColor(@buffer.dc, color_ref(color))
    Platform.SetBkMode(@buffer.dc, 1) # TRANSPARENT
    ptr = Fiddle::Pointer.malloc(16)
    ptr[0, 16] = [rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]].pack('l<4')
    Platform.DrawTextW(@buffer.dc, Platform.wide(text), -1, ptr, 0x0020 | 0x0800) # DT_SINGLELINE | DT_NOPREFIX
  end

  def draw_text_center(text, rect, font, color)
    return unless Platform::API_READY
    Platform.SelectObject(@buffer.dc, font) if font
    Platform.SetTextColor(@buffer.dc, color_ref(color))
    Platform.SetBkMode(@buffer.dc, 1)
    ptr = Fiddle::Pointer.malloc(16)
    ptr[0, 16] = [rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]].pack('l<4')
    Platform.DrawTextW(@buffer.dc, Platform.wide(text), -1, ptr, 0x0001 | 0x0004 | 0x0020 | 0x0800) # DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX
  end

  def color_ref(rgb)
    rgb[0] | (rgb[1] << 8) | (rgb[2] << 16)
  end

  def dispose_resources
    @buffer&.dispose
    Platform.DeleteObject(@font_title) if @font_title && Platform::API_READY
    Platform.DeleteObject(@font_body) if @font_body && Platform::API_READY
    Platform.DeleteObject(@font_btn) if @font_btn && Platform::API_READY
  end
end
