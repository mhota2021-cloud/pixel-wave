#Windows連携（fiddleでWin32 APIを呼び、win32/registryでレジストリを触る。Windows以外では読み込むだけ）
#ポインタと同じ大きさの値（HWNDやWPARAMやLPARAMやLRESULT）は、必ずvoid*かintptr_tかuintptr_tで受け渡す（longはWindowsでは32ビットしかないため）
require 'fiddle/import'
require 'fileutils'

module Platform
  extend Fiddle::Importer

  begin
    dlload 'user32.dll', 'kernel32.dll', 'comdlg32.dll', 'gdi32.dll'
    #ウィンドウ全般
    extern 'void* FindWindowW(void*, void*)'
    extern 'void* FindWindowExW(void*, void*, void*, void*)'
    extern 'int EnumWindows(void*, intptr_t)'
    extern 'intptr_t SendMessageTimeoutW(void*, unsigned int, uintptr_t, intptr_t, unsigned int, unsigned int, void*)'
    extern 'void* SetParent(void*, void*)'
    extern 'int SetWindowPos(void*, void*, int, int, int, int, unsigned int)'
    extern 'void* GetForegroundWindow()'
    extern 'int GetWindowRect(void*, void*)'
    extern 'int GetClassNameW(void*, void*, int)'
    extern 'int GetSystemMetrics(int)'
    extern 'int SetForegroundWindow(void*)'
    extern 'int ShowWindow(void*, int)'
    extern 'int SystemParametersInfoW(unsigned int, unsigned int, void*, unsigned int)'
    extern 'int SetSysColors(int, void*, void*)'
    extern 'intptr_t GetWindowLongPtrW(void*, int)'
    extern 'intptr_t SetWindowLongPtrW(void*, int, intptr_t)'
    extern 'int SetLayeredWindowAttributes(void*, unsigned int, unsigned char, unsigned int)'
    extern 'int GetSystemPowerStatus(void*)'
    #ウィンドウの作成とメッセージ
    extern 'unsigned short RegisterClassExW(void*)'
    extern 'void* CreateWindowExW(unsigned int, void*, void*, unsigned int, int, int, int, int, void*, void*, void*, void*)'
    extern 'intptr_t DefWindowProcW(void*, unsigned int, uintptr_t, intptr_t)'
    extern 'int GetMessageW(void*, void*, unsigned int, unsigned int)'
    extern 'int TranslateMessage(void*)'
    extern 'intptr_t DispatchMessageW(void*)'
    extern 'void PostQuitMessage(int)'
    extern 'int DestroyWindow(void*)'
    extern 'int UpdateWindow(void*)'
    extern 'uintptr_t SetTimer(void*, uintptr_t, unsigned int, void*)'
    extern 'int KillTimer(void*, uintptr_t)'
    extern 'void* GetDC(void*)'
    extern 'int ReleaseDC(void*, void*)'
    extern 'void* BeginPaint(void*, void*)'
    extern 'int EndPaint(void*, void*)'
    extern 'int InvalidateRect(void*, void*, int)'
    extern 'int FillRect(void*, void*, void*)'
    extern 'int DrawTextW(void*, void*, int, void*, unsigned int)'
    extern 'int GetClientRect(void*, void*)'
    #GDI
    extern 'void* CreateCompatibleDC(void*)'
    extern 'void* CreateCompatibleBitmap(void*, int, int)'
    extern 'void* SelectObject(void*, void*)'
    extern 'int DeleteObject(void*)'
    extern 'int DeleteDC(void*)'
    extern 'int BitBlt(void*, int, int, int, int, void*, int, int, unsigned int)'
    extern 'void* CreateSolidBrush(unsigned int)'
    extern 'void* CreateFontW(int, int, int, int, int, int, int, int, int, int, int, int, int, void*)'
    extern 'unsigned int SetTextColor(void*, unsigned int)'
    extern 'int SetBkMode(void*, int)'
    extern 'void* CreateRectRgn(int, int, int, int)'
    extern 'int SelectClipRgn(void*, void*)'
    extern 'int GetTextExtentPoint32W(void*, void*, int, void*)'
    extern 'int StretchDIBits(void*, int, int, int, int, int, int, int, int, void*, void*, unsigned int, unsigned int)'
    #カーネル
    extern 'void* GetModuleHandleW(void*)'
    extern 'void* CreateMutexW(void*, int, void*)'
    extern 'int GetLastError()'
    extern 'void* OpenProcess(int, int, int)'
    extern 'int TerminateProcess(void*, int)'
    extern 'int CloseHandle(void*)'
    #ファイルを選ぶ画面
    extern 'int GetOpenFileNameW(void*)'
    API_READY = true
  rescue StandardError
    API_READY = false
  end

  #定数
  WS_CHILD = 0x40000000
  WS_POPUP = 0x80000000
  WS_VISIBLE = 0x10000000
  WS_EX_LAYERED = 0x00080000
  WS_EX_TOPMOST = 0x00000008
  GWL_STYLE = -16
  GWL_EXSTYLE = -20
  SWP_NOACTIVATE = 0x0010
  SWP_FRAMECHANGED = 0x0020
  SWP_SHOWWINDOW = 0x0040
  LWA_ALPHA = 0x00000002
  SRCCOPY = 0x00CC0020

  module_function

  #文字列をヌル終端のUTF-16にする（引数sは文字列）
  def wide(s)
    "#{s}\x00".encode('UTF-16LE')
  end

  #データフォルダを返す（%APPDATA%\PixelWave、無ければ作る）
  def data_dir
    base = ENV['APPDATA'] || File.expand_path('~/.pixelwave')
    dir = File.join(base, 'PixelWave')
    FileUtils.mkdir_p(dir)
    dir
  end

  #キャッシュのフォルダを返す
  def cache_dir
    dir = File.join(data_dir, 'cache')
    FileUtils.mkdir_p(dir)
    dir
  end

  #ウィンドウの中身の大きさを返す（引数hwndはウィンドウ。戻り値は幅と高さ）
  def client_size(hwnd)
    buffer = "\x00" * 16
    return [0, 0] if GetClientRect(hwnd, buffer) == 0
    left, top, right, bottom = buffer.unpack('l<4')
    [right - left, bottom - top]
  rescue StandardError
    [0, 0]
  end

  #名前付きミューテックスを取る（引数nameは名前。戻り値は多重起動ならtrue）
  def mutex_taken?(name)
    handle = CreateMutexW(nil, 0, wide(name))
    return false if handle.nil? || handle.null?
    GetLastError() == 183
  end

  #タイトルでウィンドウを探す（引数titleはタイトル。無ければnil）
  def find_window(title)
    hwnd = FindWindowW(nil, wide(title))
    return nil if hwnd.nil? || hwnd.null?
    hwnd
  end

  #ウィンドウを前に出す（引数hwndはウィンドウ）
  def bring_to_front(hwnd)
    ShowWindow(hwnd, 9)
    SetForegroundWindow(hwnd)
  end

  #ウィンドウのクラス名を読む（引数hwndはウィンドウ）
  def class_name(hwnd)
    buffer = "\x00" * 512
    len = GetClassNameW(hwnd, buffer, 256)
    return '' if len <= 0
    buffer[0, len * 2].force_encoding('UTF-16LE').encode('UTF-8')
  rescue StandardError
    ''
  end

#壁紙として貼り付ける（引数hwndは自ウィンドウ、引数xとyは置く場所、引数wとhは大きさ、引数log_pathは記録の場所）
  #Windows 11 24H2の階層構造に対応：
  #1. 競合する壁紙描画WorkerWを非表示にする
  #2. ProgmanにWS_CLIPCHILDRENを付与して子ウィンドウ領域を保護する
  #3. レイヤードを排した通常のGDI可視子ウィンドウとしてProgmanの子にし、defview直後に配置する
  def attach_wallpaper(hwnd, x, y, w, h, log_path)
    progman = FindWindowW(wide('Progman'), nil)
    raise 'Progmanが見つかりません' if progman.nil? || progman.null?

    result = Fiddle::Pointer.malloc(8)
    SendMessageTimeoutW(progman, 0x052C, 0xD, 0, 0, 1000, result)
    SendMessageTimeoutW(progman, 0x052C, 0xD, 1, 0, 1000, result)

    defview = FindWindowExW(progman, nil, wide('SHELLDLL_DefView'), nil)
    raise 'SHELLDLL_DefViewが見つかりません' if defview.nil? || defview.null?

    #1. 競合する壁紙WorkerWがあれば非表示にする
    workerw = FindWindowExW(progman, nil, wide('WorkerW'), nil)
    workerw_hidden = false
    if workerw && !workerw.null?
      ShowWindow(workerw, 0)
      workerw_hidden = true
    end

    #2. ProgmanにWS_CLIPCHILDRENを付与
    progman_style = GetWindowLongPtrW(progman, GWL_STYLE)
    SetWindowLongPtrW(progman, GWL_STYLE, progman_style | 0x02000000)

    #3. 通常のGDI子ウィンドウとしてProgmanの子にする
    style = GetWindowLongPtrW(hwnd, GWL_STYLE)
    SetWindowLongPtrW(hwnd, GWL_STYLE, (style & ~WS_POPUP & ~0x00C00000 & ~0x00040000) | WS_CHILD | WS_VISIBLE | 0x04000000)
    SetParent(hwnd, progman)

    #4. アイコン層（defview）の直後に配置
    SetWindowPos(hwnd, defview, x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED)
    InvalidateRect(hwnd, nil, 1)
    UpdateWindow(hwnd)

    File.open(log_path, 'a') { |f| f.puts "#{Time.now}: Progmanの子にし、defview直後へ配置（WorkerW非表示=#{workerw_hidden}）" } rescue nil
    true
  end
  alias attach_24h2 attach_wallpaper

  #前面のアプリが全画面か調べる（引数own_hwndは自ウィンドウで、自分は除く）
  def foreground_fullscreen?(own_hwnd)
    fg = GetForegroundWindow()
    return false if fg.nil? || fg.null?
    return false if own_hwnd && fg.to_i == own_hwnd.to_i
    name = class_name(fg)
    return false if %w[Progman WorkerW Shell_TrayWnd Shell_SecondaryTrayWnd].include?(name)
    buffer = "\x00" * 16
    return false if GetWindowRect(fg, buffer) == 0
    left, top, right, bottom = buffer.unpack('l<4')
    sw = GetSystemMetrics(0)
    sh = GetSystemMetrics(1)
    left <= 0 && top <= 0 && right >= sw && bottom >= sh
  rescue StandardError
    false
  end

  #電池で動いているか調べる（交流電源につながっていないとき真）
  def battery_powered?
    buffer = "\x00" * 12
    return false if GetSystemPowerStatus(buffer) == 0
    buffer.getbyte(0) == 0
  rescue StandardError
    false
  end

  #仮想画面の範囲を返す（戻り値はxとyと幅と高さ）
  def virtual_screen
    [GetSystemMetrics(76), GetSystemMetrics(77), GetSystemMetrics(78), GetSystemMetrics(79)]
  rescue StandardError
    [0, 0, 1280, 720]
  end

  #主な画面の大きさを返す（戻り値は幅と高さ）
  def primary_screen
    [GetSystemMetrics(0), GetSystemMetrics(1)]
  rescue StandardError
    [1280, 720]
  end

  #作業領域を返す（タスクバーを除いた範囲。戻り値はxとyと幅と高さ）
  def work_area
    buffer = "\x00" * 16
    if SystemParametersInfoW(48, 0, buffer, 0) != 0
      left, top, right, bottom = buffer.unpack('l<4')
      return [left, top, right - left, bottom - top]
    end
    [0, 0, 1280, 720]
  rescue StandardError
    [0, 0, 1280, 720]
  end

  #プロセスを終了させる（引数pidはプロセスID）
  #プロセスが動いているか調べる
  def process_alive?(pid)
    return false if pid.nil? || pid <= 0
    handle = OpenProcess(0x1000, 0, pid)
    return false if handle.nil? || handle.null?
    CloseHandle(handle)
    true
  rescue StandardError
    false
  end

  #プロセスを強制終了する
  def kill_process(pid)
    handle = OpenProcess(1, 0, pid)
    return false if handle.nil? || handle.null?
    ok = TerminateProcess(handle, 0)
    CloseHandle(handle)
    ok != 0
  rescue StandardError
    false
  end

  #画像ファイルを選ぶ画面を開く（戻り値は選ばれた場所の配列、取り消しなら空）
  def open_image_dialog
    filter = wide("画像\0*.jpg;*.jpeg;*.png\0\0")
    file_buffer = Fiddle::Pointer.malloc(32768 * 2)
    file_buffer[0, 32768 * 2] = "\x00" * (32768 * 2)
    filter_ptr = Fiddle::Pointer.malloc(filter.bytesize)
    filter_ptr[0, filter.bytesize] = filter
    struct = "\x00" * 152
    struct[0, 4] = [152].pack('L<')
    struct[24, 8] = [filter_ptr.to_i].pack('Q<')
    struct[48, 8] = [file_buffer.to_i].pack('Q<')
    struct[56, 4] = [32768].pack('L<')
    struct[96, 4] = [0x200 | 0x1000 | 0x80000].pack('L<')
    struct_ptr = Fiddle::Pointer.malloc(152)
    struct_ptr[0, 152] = struct
    return [] if GetOpenFileNameW(struct_ptr) == 0
    text = file_buffer[0, 32768 * 2].force_encoding('UTF-16LE').encode('UTF-8')
    parts = text.split("\x00").reject(&:empty?)
    return parts if parts.length <= 1
    dir = parts[0]
    parts[1..].map { |name| File.join(dir, name) }
  rescue StandardError
    []
  end

  #自動起動の登録をする（引数nameは登録名、引数commandは起動コマンド）
  def set_run_entry(name, command)
    require 'win32/registry'
    Win32::Registry::HKEY_CURRENT_USER.create('Software\Microsoft\Windows\CurrentVersion\Run') do |reg|
      reg[name] = command
    end
  rescue StandardError
    nil
  end

  #自動起動の登録を消す（引数nameは登録名）
  def delete_run_entry(name)
    require 'win32/registry'
    Win32::Registry::HKEY_CURRENT_USER.open('Software\Microsoft\Windows\CurrentVersion\Run', Win32::Registry::KEY_WRITE) do |reg|
      reg.delete_value(name)
    end
  rescue StandardError
    nil
  end

  #スクリーンセーバーとして登録する（引数pathは.scrの場所）
  def register_screensaver(path)
    require 'win32/registry'
    Win32::Registry::HKEY_CURRENT_USER.create('Control Panel\Desktop') do |reg|
      reg['SCRNSAVE.EXE'] = path
      reg['ScreenSaveActive'] = '1'
    end
  rescue StandardError
    nil
  end

  SPI_GETCLIENTAREAANIMATION = 0x1042
  SPI_SETCLIENTAREAANIMATION = 0x1043
  SPI_SETDESKWALLPAPER = 0x0014
  SPIF_UPDATEINIFILE = 0x01
  SPIF_SENDCHANGE = 0x02

  #元の壁紙の保存ファイル
  def backup_wallpaper_path
    File.join(data_dir, 'original_wallpaper.json')
  end

  #現在の壁紙設定を退避して覚える（既に退避済みなら上書きしない）
  def backup_wallpaper
    return unless API_READY
    path = backup_wallpaper_path
    if File.exist?(path)
      begin
        return JSON.parse(File.read(path, encoding: 'UTF-8'))
      rescue StandardError
        #破損時は再作成へ進む
      end
    end

    require 'win32/registry'
    require 'json'
    info = {
      'wallpaper' => '',
      'wallpaper_style' => '10',
      'tile_wallpaper' => '0',
      'background' => '0 0 0'
    }

    begin
      Win32::Registry::HKEY_CURRENT_USER.open('Control Panel\Desktop') do |reg|
        info['wallpaper'] = (reg['Wallpaper'] rescue '') || ''
        info['wallpaper_style'] = (reg['WallpaperStyle'] rescue '10') || '10'
        info['tile_wallpaper'] = (reg['TileWallpaper'] rescue '0') || '0'
      end
    rescue StandardError => e
      warn "Control Panel\\Desktopの読み取りに失敗: #{e.message}"
    end

    begin
      Win32::Registry::HKEY_CURRENT_USER.open('Control Panel\Colors') do |reg|
        info['background'] = (reg['Background'] rescue '0 0 0') || '0 0 0'
      end
    rescue StandardError => e
      warn "Control Panel\\Colorsの読み取りに失敗: #{e.message}"
    end

    File.write(path, JSON.pretty_generate(info), encoding: 'UTF-8')
    info
  rescue StandardError => e
    warn "壁紙設定のバックアップに失敗: #{e.message}"
    nil
  end

  #デスクトップの壁紙画像を設定する
  def set_desktop_wallpaper(image_path, style = '10')
    return false unless API_READY
    return false unless File.exist?(image_path)

    require 'win32/registry'
    begin
      Win32::Registry::HKEY_CURRENT_USER.open('Control Panel\Desktop', Win32::Registry::KEY_WRITE) do |reg|
        reg['WallpaperStyle'] = style.to_s
        reg['TileWallpaper'] = '0'
      end
    rescue StandardError => e
      warn "レジストリ書き込み失敗: #{e.message}"
    end

    path_w = wide(image_path)
    ptr = Fiddle::Pointer.malloc(path_w.bytesize)
    ptr[0, path_w.bytesize] = path_w
    res = SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, ptr, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)
    res != 0
  rescue StandardError => e
    warn "壁紙画像の設定に失敗: #{e.message}"
    false
  end

  #元の壁紙設定に復元する
  def restore_wallpaper
    return false unless API_READY
    path = backup_wallpaper_path
    return false unless File.exist?(path)

    require 'win32/registry'
    require 'json'
    info = begin
      JSON.parse(File.read(path, encoding: 'UTF-8'))
    rescue StandardError => e
      warn "バックアップファイルの読み取りに失敗: #{e.message}"
      return false
    end

    wallpaper = info['wallpaper'] || ''
    style = info['wallpaper_style'] || '10'
    tile = info['tile_wallpaper'] || '0'
    bg = info['background'] || '0 0 0'

    if wallpaper.strip.empty?
      begin
        Win32::Registry::HKEY_CURRENT_USER.open('Control Panel\Desktop', Win32::Registry::KEY_WRITE) do |reg|
          reg['Wallpaper'] = ''
        end
        Win32::Registry::HKEY_CURRENT_USER.open('Control Panel\Colors', Win32::Registry::KEY_WRITE) do |reg|
          reg['Background'] = bg
        end
      rescue StandardError => e
        warn "単色レジストリ復元失敗: #{e.message}"
      end

      rgb_parts = bg.split.map(&:to_i)
      r = rgb_parts[0] || 0
      g = rgb_parts[1] || 0
      b = rgb_parts[2] || 0
      color_val = r | (g << 8) | (b << 16)
      elements = [1].pack('l')
      colors = [color_val].pack('l')
      SetSysColors(1, elements, colors)

      empty_w = wide('')
      ptr = Fiddle::Pointer.malloc(empty_w.bytesize)
      ptr[0, empty_w.bytesize] = empty_w
      SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, ptr, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)
    else
      begin
        Win32::Registry::HKEY_CURRENT_USER.open('Control Panel\Desktop', Win32::Registry::KEY_WRITE) do |reg|
          reg['WallpaperStyle'] = style
          reg['TileWallpaper'] = tile
        end
      rescue StandardError => e
        warn "画像壁紙レジストリ復元失敗: #{e.message}"
      end

      path_w = wide(wallpaper)
      ptr = Fiddle::Pointer.malloc(path_w.bytesize)
      ptr[0, path_w.bytesize] = path_w
      SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, ptr, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)
    end

    progman = FindWindowW(wide('Progman'), nil)
    if progman && !progman.null?
      workerw = FindWindowExW(progman, nil, wide('WorkerW'), nil)
      ShowWindow(workerw, 5) if workerw && !workerw.null?
    end
    File.delete(path) rescue nil
    true
  rescue StandardError => e
    warn "壁紙の復元に失敗: #{e.message}"
    false
  end

  #動的壁紙に必要なWindows環境（アニメーション）を整える
  def ensure_wallpaper_prerequisites
    return unless API_READY

    buffer = Fiddle::Pointer.malloc(4)
    if SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, buffer, 0) != 0
      anim = buffer[0, 4].unpack1('L<')
      if anim == 0
        SystemParametersInfoW(SPI_SETCLIENTAREAANIMATION, 0, Fiddle::Pointer.new(1), SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)
      end
    end
  rescue StandardError => e
    warn "Windows環境の自動調整に失敗しました：#{e.message}"
  end
end
