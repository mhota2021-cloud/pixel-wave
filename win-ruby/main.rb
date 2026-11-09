#Pixel Wave（Windows版、Ruby）の入口。引数で動きを変える
require_relative 'lib/args'
require_relative 'lib/settings'
require_relative 'lib/loader'
require_relative 'lib/platform'

#素材のフォルダを探す（引数app_rootはアプリの場所。exe化した中、リポジトリ直下のassets、の順に探す）
def paintings_dir(app_root)
  candidates = [
    File.join(app_root, 'assets', 'paintings'),
    File.expand_path('../assets/paintings', app_root),
  ]
  candidates.find { |c| File.exist?(File.join(c, 'credits.json')) } || candidates.first
end

begin
  mode = Args.parse_mode(ARGV)
  app_root = __dir__

  case mode
when :preview
  #プレビューは作らず、すぐ終了する
  exit(0)
when :screensaver, :wallpaper
  require_relative 'lib/display_window'
  data_dir = Platform.data_dir
  pdir = paintings_dir(app_root)
  builtin_ids = Loader.credits(pdir).map { |c| c['id'] }
  settings = AppSettings.load(data_dir, builtin_ids)
  list = Loader.paintings(settings, pdir, data_dir)
  DisplayWindow.new(
    mode: mode,
    paintings: list,
    cache_dir: Platform.cache_dir
  ).start
else
  #設定画面は1つだけにする（名前付きミューテックスで気づき、開いていれば前に出して終わる）
  if Platform::API_READY && Platform.mutex_taken?('PixelWaveSettingsMutex')
    hwnd = Platform.find_window('Pixel Wave')
    Platform.bring_to_front(hwnd) if hwnd
    exit(0)
  end
  require_relative 'lib/settings_window'
  width = 880
  height = 760
  if Platform::API_READY
    _x, _y, work_w, work_h = Platform.work_area
    width = [width, work_w].min
    height = [height, work_h].min
  end
  height = [height, 560].max
  SettingsWindow.new(
    data_dir: Platform.data_dir,
    paintings_dir: paintings_dir(app_root),
    width: width,
    height: height
  ).start
end
rescue => e
  log_path = File.join(Platform.data_dir, 'crash.log')
  File.open(log_path, 'a') do |f|
    f.puts "#{Time.now}: #{e.class} - #{e.message}"
    f.puts e.backtrace
  end
  raise
end
