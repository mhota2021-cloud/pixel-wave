#表示ウィンドウ（壁紙とスクリーンセーバーで共用。GDIで描く）
#裏画面に変わったドットだけを塗り、WM_PAINTでは写すだけにする
require_relative 'window'
require_relative 'engine'
require_relative 'loader'
require_relative 'wic'
require_relative 'platform'
require_relative 'render_math'

class DisplayWindow < NativeWindow
  TIMER_TICK = 1
  TIMER_CHECK = 2

  #初期化（引数modeはwallpaperかscreensaver、引数paintingsは使う絵の一覧、引数cache_dirはキャッシュのフォルダ）
  def initialize(mode:, paintings:, cache_dir:, pause_on_battery: true)
    @mode = mode
    if mode == :wallpaper
      x, y, w, h = Platform::API_READY ? Platform.virtual_screen : [0, 0, 1280, 720]
      ex_style = 0
    else
      x = 0
      y = 0
      w, h = Platform::API_READY ? Platform.primary_screen : [1280, 720]
      ex_style = Platform::WS_EX_TOPMOST
    end
    cols = [(w / WaveEngine::DOT.to_f).ceil, 1].max
    rows = [(h / WaveEngine::DOT.to_f).ceil, 1].max
    grids = Loader.grids(paintings, cols, rows, cache_dir, Wic.method(:decode))
    @engine = WaveEngine.new(grids, cols, rows)
    @engine.request_full_redraw
    super(
      class_name: 'PixelWaveDisplay',
      title: mode == :wallpaper ? 'PixelWaveWallpaper' : 'PixelWaveSaver',
      width: w, height: h, x: x, y: y, ex_style: ex_style
    )
    @buffer = BackBuffer.new(@hwnd, w, h)
    @buffer.fill_all(WaveEngine::BACKGROUND)
    @engine_time = 0.0
    @last_tick_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @paused = false
    @mouse_origin = nil
    @pause_on_battery = pause_on_battery
  end

  #表示を始める（壁紙の貼り付けは、ウィンドウを作ったこのスレッドで行う）
  def start
    attach_wallpaper if @mode == :wallpaper
    @engine.request_full_redraw
    advance_frame
    invalidate(nil)
    Platform.UpdateWindow(@hwnd) if Platform::API_READY
    set_timer(TIMER_CHECK, 2000)
    schedule_tick
    run
  end

  #メッセージの処理
  def handle_message(hwnd, msg, wparam, lparam)
    File.open(File.join(Platform.data_dir, 'wallpaper_debug.log'), 'a') { |f| f.puts "msg=0x#{msg.to_s(16)}" } rescue nil if msg != 0x0113 && msg != 0x0200
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
      wparam.to_i == TIMER_CHECK ? on_check : on_tick
      0
    when WM_DESTROY
      @buffer.dispose
      Platform.PostQuitMessage(0)
      0
    when WM_KEYDOWN, WM_LBUTTONDOWN
      close if @mode == :screensaver
      0
    when WM_MOUSEMOVE
      on_mouse_move(lparam) if @mode == :screensaver
      0
    end
  end

  private

  #壁紙として貼り付ける（失敗しても表示は続ける）
  def attach_wallpaper
    Platform.ensure_wallpaper_prerequisites
    log_path = File.join(Platform.data_dir, 'wallpaper.log')
    Platform.attach_wallpaper(@hwnd, 0, 0, @width, @height, log_path)
  rescue StandardError => e
    File.open(log_path, 'a') { |f| f.puts "#{Time.now}: 貼り付け失敗（#{e.message}）" } rescue nil
  end

  #時間を進めて、変わったドットだけ裏画面に塗る
  def advance_frame
    changes = @engine.frame(@engine_time)
    return if changes.empty?
    changes.each do |col, row, rgb|
      @buffer.fill(RenderMath.dot_rect(col, row, WaveEngine::DOT, WaveEngine::FILL), rgb)
    end
    invalidate(RenderMath.union_rect(changes, WaveEngine::DOT))
    Platform.UpdateWindow(@hwnd) if Platform::API_READY
  end

  #次のタイマーの間隔を決める（切り替え中は16ミリ秒、表示中は間引く）
  def schedule_tick
    if @paused
      kill_timer(TIMER_TICK)
    elsif @engine.needs_redraw?(@engine_time)
      set_timer(TIMER_TICK, 16)
    else
      set_timer(TIMER_TICK, 250)
    end
  end

  #タイマー（時間を進める）
  def on_tick
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    dt = now - @last_tick_at
    @last_tick_at = now
    return if @paused
    @engine_time += dt
    advance_frame
    schedule_tick
  end

  #タイマー（電池と全画面の判定、2秒ごと）
  def on_check
    @last_tick_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return unless Platform::API_READY
    was_paused = @paused
    battery_paused = @pause_on_battery && Platform.battery_powered?\n    @paused = Platform.foreground_fullscreen?(@hwnd) || battery_paused
    if was_paused && !@paused
      advance_frame
      schedule_tick
    elsif @paused
      kill_timer(TIMER_TICK)
    end
  end

  #スクリーンセーバーのマウス移動（数ピクセルの揺れは無視する。引数lparamは座標）
  def on_mouse_move(lparam)
    value = lparam.to_i
    x = value & 0xFFFF
    y = (value >> 16) & 0xFFFF
    x -= 0x10000 if x >= 0x8000
    y -= 0x10000 if y >= 0x8000
    if @mouse_origin.nil?
      @mouse_origin = [x, y]
      return
    end
    dx = x - @mouse_origin[0]
    dy = y - @mouse_origin[1]
    close if dx * dx + dy * dy > 25
  end
end
