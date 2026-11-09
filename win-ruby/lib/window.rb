#Win32ウィンドウの枠組み（クラス登録と作成とメッセージループ）と、メモリ上に描く裏画面
#ウィンドウプロシージャはガベージコレクションで消えないよう、クラス変数に持ち続ける
require 'fiddle'
require_relative 'platform'
require_relative 'render_math'

class NativeWindow
  WM_DESTROY = 0x0002
  WM_CLOSE = 0x0010
  WM_PAINT = 0x000F
  WM_TIMER = 0x0113
  WM_ERASEBKGND = 0x0014
  WM_KEYDOWN = 0x0100
  WM_MOUSEMOVE = 0x0200
  WM_LBUTTONDOWN = 0x0201
  WM_LBUTTONUP = 0x0202
  WM_MOUSEWHEEL = 0x020A

  @@procs = {}
  @@registered = {}
  @@handlers = {}
  @@pending = nil

  attr_reader :hwnd, :width, :height

  #初期化（引数class_nameはウィンドウクラス名、引数titleはタイトル、引数widthとheightは大きさ、引数xとyは場所、引数ex_styleとstyleはスタイル）
  def initialize(class_name:, title:, width:, height:, x: 0, y: 0, ex_style: 0, style: Platform::WS_POPUP | Platform::WS_VISIBLE)
    @width = width
    @height = height
    register_class(class_name)
    @@pending = self
    @hwnd = Platform.CreateWindowExW(
      ex_style, Platform.wide(class_name), Platform.wide(title), style,
      x, y, width, height, nil, nil, Platform.GetModuleHandleW(nil), nil
    )
    @@pending = nil
    raise 'ウィンドウを作れませんでした' if @hwnd.nil? || @hwnd.null?
    @@handlers[@hwnd.to_i] = self
    Platform.UpdateWindow(@hwnd)
  end

  #メッセージループを回す（ウィンドウが閉じるまで戻らない）
  def run
    msg = Fiddle::Pointer.malloc(64)
    while (result = Platform.GetMessageW(msg, nil, 0, 0)) > 0
      Platform.TranslateMessage(msg)
      Platform.DispatchMessageW(msg)
    end
    result
  end

  #タイマーを置く（引数idは番号、引数msは間隔）
  def set_timer(id, ms)
    Platform.SetTimer(@hwnd, id, ms, nil)
  end

  #タイマーを止める（引数idは番号）
  def kill_timer(id)
    Platform.KillTimer(@hwnd, id)
  end

  #描き直しの対象にする（引数rectはxとyと幅と高さ、nilなら全体）
  def invalidate(rect = nil)
    if rect.nil?
      Platform.InvalidateRect(@hwnd, nil, 0)
    else
      Platform.InvalidateRect(@hwnd, rect_pointer(rect), 0)
    end
  end

  #ウィンドウを閉じる
  def close
    Platform.DestroyWindow(@hwnd)
  end

  #メッセージの処理（継承先で置き換える。戻り値がnilなら既定の処理に任せる）
  def handle_message(_hwnd, _msg, _wparam, _lparam)
    nil
  end

  #矩形をRECTのメモリにする（引数rectはxとyと幅と高さ）
  def rect_pointer(rect)
    ptr = Fiddle::Pointer.malloc(16)
    ptr[0, 16] = RenderMath.rect_array(rect).pack('l<4')
    ptr
  end

  private

  #ウィンドウクラスを登録する（引数class_nameはクラス名、1回だけ）
  def register_class(class_name)
    return if @@registered[class_name]
    wndproc = Fiddle::Closure::BlockCaller.new(
      Fiddle::Types::VOIDP,
      [Fiddle::Types::VOIDP, Fiddle::Types::UINT, Fiddle::Types::VOIDP, Fiddle::Types::VOIDP]
    ) do |hwnd, msg, wparam, lparam|
      target = @@handlers[hwnd.to_i] || @@pending
      handled = nil
      if target
        begin
          handled = target.handle_message(hwnd, msg, wparam, lparam)
        rescue StandardError
          handled = nil
        end
      end
      handled.nil? ? Platform.DefWindowProcW(hwnd, msg, wparam, lparam) : handled
    end
    @@procs[class_name] = wndproc
    wc = "\x00" * 80
    wc[0, 4] = [80].pack('L<')
    wc[8, 8] = [wndproc.to_i].pack('Q<')
    hinstance = Platform.GetModuleHandleW(nil)
    wc[24, 8] = [hinstance.to_i].pack('Q<')
    cursor = load_arrow_cursor
    wc[40, 8] = [cursor.to_i].pack('Q<') if cursor
    name = Platform.wide(class_name)
    name_ptr = Fiddle::Pointer.malloc(name.bytesize)
    name_ptr[0, name.bytesize] = name
    wc[64, 8] = [name_ptr.to_i].pack('Q<')
    wc_ptr = Fiddle::Pointer.malloc(80)
    wc_ptr[0, 80] = wc
    Platform.RegisterClassExW(wc_ptr)
    @@registered[class_name] = true
  end

  #矢印カーソルを読む（失敗したらnil）
  def load_arrow_cursor
    fn = Fiddle::Function.new(
      Fiddle.dlopen('user32.dll')['LoadCursorW'],
      [Fiddle::Types::VOIDP, Fiddle::Types::VOIDP],
      Fiddle::Types::VOIDP
    )
    fn.call(nil, Fiddle::Pointer.new(32512))
  rescue StandardError
    nil
  end
end

#裏画面（メモリ上のビットマップに描き、WM_PAINTでは写すだけにする。ブラシは色ごとに作って使い回す）
class BackBuffer
  attr_reader :dc, :width, :height

  #初期化（引数hwndはウィンドウ、引数widthとheightは大きさ）
  def initialize(hwnd, width, height)
    @width = width
    @height = height
    screen_dc = Platform.GetDC(hwnd)
    @dc = Platform.CreateCompatibleDC(screen_dc)
    @bitmap = Platform.CreateCompatibleBitmap(screen_dc, width, height)
    @old_bitmap = Platform.SelectObject(@dc, @bitmap)
    Platform.ReleaseDC(hwnd, screen_dc)
    @brushes = {}
  end

  #矩形を塗る（引数rectはxとyと幅と高さ、引数rgbは色）
  def fill(rect, rgb)
    brush = @brushes[rgb] ||= Platform.CreateSolidBrush(RenderMath.colorref(rgb))
    ptr = Fiddle::Pointer.malloc(16)
    ptr[0, 16] = RenderMath.rect_array(rect).pack('l<4')
    Platform.FillRect(@dc, ptr, brush)
  end

  #全体を塗る（引数rgbは色）
  def fill_all(rgb)
    fill([0, 0, @width, @height], rgb)
  end

  #ウィンドウへ写す（引数hdcは描き先）
  def blit_to(hdc)
    Platform.BitBlt(hdc, 0, 0, @width, @height, @dc, 0, 0, Platform::SRCCOPY)
  end

  #後片付け（ビットマップとブラシを消す）
  def dispose
    Platform.SelectObject(@dc, @old_bitmap) if @old_bitmap
    Platform.DeleteObject(@bitmap) if @bitmap
    Platform.DeleteDC(@dc) if @dc
    @brushes.each_value { |brush| Platform.DeleteObject(brush) }
    @brushes.clear
  end
end
