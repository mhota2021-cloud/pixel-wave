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
  #実機でアイコンの後ろに見えた方法：Progmanの直接の子にし、重なり順をSHELLDLL_DefViewのすぐ奥にし、レイヤードにする
  #呼び出しは、ウィンドウを作ったスレッドから行うこと
  def attach_wallpaper(hwnd, x, y, w, h, log_path)
    progman = FindWindowW(wide('Progman'), nil)
    raise 'Progmanが見つかりません' if progman.nil? || progman.null?

    result = Fiddle::Pointer.malloc(8)
    SendMessageTimeoutW(progman, 0x052C, 0xD, 0, 0, 1000, result)
    SendMessageTimeoutW(progman, 0x052C, 0xD, 1, 0, 1000, result)

    defview = FindWindowExW(progman, nil, wide('SHELLDLL_DefView'), nil)
    raise 'SHELLDLL_DefViewが見つかりません' if defview.nil? || defview.null?

    # 1. トップレベルウィンドウの段階でレイヤード属性を確実に付与・設定する（子ウィンドウ化後はAPIが失敗するため）
    exstyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, exstyle | WS_EX_LAYERED)
    res_layered = SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA)
    err_layered = GetLastError()

    # 2. 子ウィンドウのスタイルに変更してProgmanの直接の子にする
    style = GetWindowLongPtrW(hwnd, GWL_STYLE)
    SetWindowLongPtrW(hwnd, GWL_STYLE, (style & ~WS_POPUP & ~0x00C00000 & ~0x00040000) | WS_CHILD | WS_VISIBLE | 0x04000000)
    SetParent(hwnd, progman)

    # 3. SHELLDLL_DefView（アイコン層）のすぐ奥に配置する
    SetWindowPos(hwnd, defview, x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED)
    InvalidateRect(hwnd, nil, 1)
    UpdateWindow(hwnd)

    File.open(log_path, 'a') { |f| f.puts "#{Time.now}: Progmanの子にし、SHELLDLL_DefViewのすぐ奥へ置いた (layered=#{res_layered}, err=#{err_layered})" } rescue nil
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

  #動的壁紙に必要なWindows環境（アニメーションと壁紙画像）を整える
  def ensure_wallpaper_prerequisites
    return unless API_READY

    #1. ウィンドウアニメーションの有効化
    buffer = Fiddle::Pointer.malloc(4)
    if SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, buffer, 0) != 0
      anim = buffer[0, 4].unpack1('L<')
      if anim == 0
        SystemParametersInfoW(SPI_SETCLIENTAREAANIMATION, 0, Fiddle::Pointer.new(1), SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)
      end
    end

    #2. 壁紙が単色（空文字）の場合、Windows標準の壁紙画像を設定してWorkerWの生成を促す
    require 'win32/registry' rescue nil
    wallpaper_path = ''
    begin
      Win32::Registry::HKEY_CURRENT_USER.open('Control Panel\Desktop') do |reg|
        wallpaper_path = reg['Wallpaper'] rescue ''
      end
    rescue StandardError
      wallpaper_path = ''
    end

    if wallpaper_path.nil? || wallpaper_path.strip.empty?
      default_candidates = [
        'C:\Windows\Web\Wallpaper\Windows\img0.jpg',
        File.expand_path('../../assets/paintings/hokusai_great_wave.jpg', __dir__)
      ]
      img = default_candidates.find { |p| File.exist?(p) }
      if img
        path_w = wide(img)
        ptr = Fiddle::Pointer.malloc(path_w.bytesize)
        ptr[0, path_w.bytesize] = path_w
        SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, ptr, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)
      end
    end
  rescue StandardError => e
    warn "Windows環境の自動調整に失敗しました：#{e.message}"
  end
end