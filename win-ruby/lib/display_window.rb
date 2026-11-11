#表示ウィンドウ（壁紙とスクリーンセーバーで共用。GDIで描く）
#裏画面に描画し、WM_PAINTでは写すだけにする
require_relative 'window'
require_relative 'engine'
require_relative 'image_engine'
require_relative 'loader'
require_relative 'wic'
require_relative 'platform'
require_relative 'settings'
require_relative 'render_math'
require_relative 'tray_window'

class DisplayWindow < NativeWindow
  TIMER_TICK = 1
  TIMER_CHECK = 2

  attr_reader :render_mode

  #初期化（引数modeはwallpaperかscreensaver、引数paintingsは使う絵の一覧、引数cache_dirはキャッシュのフォルダ）
  def initialize(mode:, paintings:, cache_dir:, pause_on_battery: true, render_mode: :dotart)
    @mode = mode
    @paintings = paintings
    @cache_dir = cache_dir
    @render_mode = render_mode
    if mode == :wallpaper
      x, y, w, h = Platform::API_READY ? Platform.virtual_screen : [0, 0, 1280, 720]
      ex_style = Platform::WS_EX_LAYERED
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

    @image_engine = nil
    if @render_mode == :normal
      @image_engine = NormalImageEngine.new(paintings, w, h, hdc_ref: @buffer.dc)
      @image_engine.request_full_redraw
    end

    @engine_time = 0.0
    @last_tick_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @paused = false
    @mouse_origin = nil
    @pause_on_battery = pause_on_battery
    @tray_window = nil
    @wallpaper_hidden = false
  end

  #表示を始める（壁紙の貼り付けは、ウィンドウを作ったこのスレッドで行う）
  def start
    if @mode == :wallpaper
      #ログイン時の起動やインストーラー版の外側のexeを経由しても止められるよう、描く本人の番号を記録する
      File.write(File.join(Platform.data_dir, 'wallpaper.pid'), Process.pid.to_s) rescue nil
      attach_wallpaper
      @tray_window = TrayWindow.new(self) if Platform::API_READY
    end
    if @render_mode == :normal && @image_engine
      @image_engine.request_full_redraw
    else
      @engine.request_full_redraw
    end
    advance_frame
    invalidate(nil)
    Platform.UpdateWindow(@hwnd) if Platform::API_READY
    set_timer(TIMER_CHECK, 2000)
    schedule_tick
    run
  end

  #ウィンドウを閉じる
  def close
    @image_engine.dispose if @image_engine
    @tray_window.close if @tray_window
    super
  end

  #モード設定を再読み込みして切り替える
  def reload_mode
    data_dir = Platform.data_dir
    app_root = File.expand_path('..', __dir__)
    pdir = File.join(app_root, 'assets', 'paintings')
    pdir = File.expand_path('../assets/paintings', app_root) unless File.exist?(File.join(pdir, 'credits.json'))
    credits = Loader.credits(pdir)
    settings = AppSettings.load(data_dir, credits.map { |c| c['id'] })
    new_mode = settings['mode'] == 'normal' ? :normal : :dotart
    return if @render_mode == new_mode

    @render_mode = new_mode
    if @render_mode == :normal
      @image_engine.dispose if @image_engine
      @image_engine = NormalImageEngine.new(@paintings, @width, @height, hdc_ref: @buffer.dc)
      @image_engine.request_full_redraw
    else
      @image_engine.dispose if @image_engine
      @image_engine = nil
      @engine.request_full_redraw
    end
    @buffer.fill_all(WaveEngine::BACKGROUND)
    advance_frame
    invalidate(nil)
    Platform.UpdateWindow(@hwnd) if Platform::API_READY
    schedule_tick
  end

  #壁紙が非表示中か
  def wallpaper_hidden?
    @wallpaper_hidden
  end

  #壁紙を非表示にして描画タイマーを止める（トレイアイコンは残す）
  def hide_wallpaper
    return unless @mode == :wallpaper
    @wallpaper_hidden = true
    kill_timer(TIMER_TICK)
    Platform.ShowWindow(@hwnd, 0) if Platform::API_READY
  end

  #壁紙を再表示して描画タイマーを再開する
  def show_wallpaper
    return unless @mode == :wallpaper
    @wallpaper_hidden = false
    Platform.ShowWindow(@hwnd, 5) if Platform::API_READY
    Platform.keep_below_icons(@hwnd, File.join(Platform.data_dir, 'wallpaper.log')) if Platform::API_READY
    @last_tick_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    advance_frame
    invalidate(nil)
    Platform.UpdateWindow(@hwnd) if Platform::API_READY
    schedule_tick
  end

  #壁紙の表示と非表示を切り替える
  def toggle_wallpaper_visibility
    @wallpaper_hidden ? show_wallpaper : hide_wallpaper
  end

  #一時停止中か
  def paused?
    @paused
  end

  #一時停止と再開を切り替える
  def toggle_pause
    @paused = !@paused
    if !@paused
      advance_frame
      schedule_tick
    else
      kill_timer(TIMER_TICK)
    end
  end

  #設定画面を開く（すでに開いていれば前面に出し、無ければ新しく起動する）
  def open_settings
    if Platform::API_READY && Platform.mutex_taken?('PixelWaveSettingsMutex')
      hwnd = Platform.find_window('Pixel Wave')
      Platform.bring_to_front(hwnd) if hwnd
    else
      app_root = File.expand_path('..', __dir__)
      cmd = if ENV['OCRAN_EXECUTABLE']
              [ENV['OCRAN_EXECUTABLE']]
            else
              [RbConfig.ruby, '-Ilib', File.expand_path('../main.rb', __dir__)]
            end
      pid = spawn(*cmd, chdir: app_root)
      Process.detach(pid)
    end
  rescue StandardError => e
    File.open(File.join(Platform.data_dir, 'wallpaper.log'), 'a') { |f| f.puts "#{Time.now}: 設定画面起動失敗（#{e.message}）" } rescue nil
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
      wparam.to_i == TIMER_CHECK ? on_check : on_tick
      0
    when WM_DESTROY
      @image_engine.dispose if @image_engine
      @tray_window.close if @tray_window
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
    log_path = File.join(Platform.data_dir, 'wallpaper.log')
    Platform.attach_wallpaper(@hwnd, 0, 0, @width, @height, log_path)
  rescue StandardError => e
    File.open(log_path, 'a') { |f| f.puts "#{Time.now}: 貼り付け失敗（#{e.message}）" } rescue nil
  end

  #時間を進めて、裏画面を更新する
  def advance_frame
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if @render_mode == :normal && @image_engine
      @image_engine.render(@buffer.dc, now)
      invalidate(nil)
      Platform.UpdateWindow(@hwnd) if Platform::API_READY
    else
      changes = @engine.frame(now)
      return if changes.empty?
      changes.each do |col, row, rgb|
        @buffer.fill(RenderMath.dot_rect(col, row, WaveEngine::DOT, WaveEngine::FILL), rgb)
      end
      invalidate(RenderMath.union_rect(changes, WaveEngine::DOT))
      Platform.UpdateWindow(@hwnd) if Platform::API_READY
    end
  end

  #次のタイマーの間隔を決める（切り替え中は16ミリ秒、表示中は間引く）
  def schedule_tick
    if @paused
      kill_timer(TIMER_TICK)
    else
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      needs = if @render_mode == :normal && @image_engine
                @image_engine.needs_redraw?(now)
              else
                @engine.needs_redraw?(now)
              end
      if needs
        set_timer(TIMER_TICK, 16)
      else
        set_timer(TIMER_TICK, 250)
      end
    end
  end

  #タイマー（時間を進める）
  def on_tick
    return if @paused
    advance_frame
    schedule_tick
  end

  #タイマー（アイコン奥への重なり順の維持、2秒ごと）
  def on_check
    return unless Platform::API_READY
    return if @wallpaper_hidden
    Platform.keep_below_icons(@hwnd, File.join(Platform.data_dir, 'wallpaper.log')) if @mode == :wallpaper
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
