#Windows連携（fiddleでWin32 APIを呼び、win32/registryでレジストリを触る。Windows以外では読み込むだけ）
#ポインタと同じ大きさの値（HWNDやWPARAMやLPARAMやLRESULT）は、必ずvoid*かintptr_tかuintptr_tで受け渡す（longはWindowsでは32ビットしかないため）
require 'fiddle/import'
require 'fileutils'

module Platform
  extend Fiddle::Importer

  begin
    dlload 'user32.dll', 'kernel32.dll', 'comdlg32.dll', 'gdi32.dll', 'shell32.dll'
    #ウィンドウ全般
    extern 'void* FindWindowW(void*, void*)'
    extern 'void* FindWindowExW(void*, void*, void*, void*)'
    extern 'int EnumWindows(void*, intptr_t)'
    extern 'intptr_t SendMessageTimeoutW(void*, unsigned int, uintptr_t, intptr_t, unsigned int, unsigned int, void*)'
    extern 'void* SetParent(void*, void*)'
    extern 'void* GetWindow(void*, unsigned int)'
    extern 'int SetWindowPos(void*, void*, int, int, int, int, unsigned int)'
    extern 'void* GetForegroundWindow()'
    extern 'int GetWindowRect(void*, void*)'
    extern 'int GetClassNameW(void*, void*, int)'
    extern 'int GetSystemPowerStatus(void*)'
    extern 'int GetSystemMetrics(int)'
    extern 'int SetForegroundWindow(void*)'
    extern 'int ShowWindow(void*, int)'
    extern 'int SystemParametersInfoW(unsigned int, unsigned int, void*, unsigned int)'
    extern 'intptr_t GetWindowLongPtrW(void*, int)'
    extern 'intptr_t SetWindowLongPtrW(void*, int, intptr_t)'
    extern 'int SetLayeredWindowAttributes(void*, unsigned int, unsigned char, unsigned int)'
    #ウィンドウの作成とメッセージ
    extern 'unsigned short RegisterClassExW(void*)'
    extern 'void* CreateWindowExW(unsigned int, void*, void*, unsigned int, int, int, int, int, void*, void*, void*, void*)'
    extern 'intptr_t DefWindowProcW(void*, unsigned int, uintptr_t, intptr_t)'
    extern 'int GetMessageW(void*, void*, unsigned int, unsigned int)'
    extern 'int TranslateMessage(void*)'
    extern 'intptr_t DispatchMessageW(void*)'
    extern 'void PostQuitMessage(int)'
    extern 'int PostMessageW(void*, unsigned int, uintptr_t, intptr_t)'
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
    extern 'void* GetStockObject(int)'
    extern 'int RoundRect(void*, int, int, int, int, int, int)'
    extern 'int Ellipse(void*, int, int, int, int)'
    extern 'void* CreatePen(int, int, unsigned int)'
    #カーネル
    extern 'void* GetModuleHandleW(void*)'
    extern 'void* CreateMutexW(void*, int, void*)'
    extern 'int GetLastError()'
    extern 'void* OpenProcess(int, int, int)'
    extern 'int TerminateProcess(void*, int)'
    extern 'int CloseHandle(void*)'
    #ファイルを選ぶ画面
    extern 'int GetOpenFileNameW(void*)'
    #色を選ぶ画面
    extern 'int ChooseColorW(void*)'
    #タスクトレイ・メニュー
    extern 'int Shell_NotifyIconW(unsigned int, void*)'
    extern 'void* ExtractIconW(void*, void*, unsigned int)'
    extern 'void* LoadIconW(void*, void*)'
    extern 'void* LoadImageW(void*, void*, unsigned int, int, int, unsigned int)'
    extern 'void* CreatePopupMenu()'
    extern 'int AppendMenuW(void*, unsigned int, uintptr_t, void*)'
    extern 'int TrackPopupMenu(void*, unsigned int, int, int, int, void*, void*)'
    extern 'int DestroyMenu(void*)'
    extern 'int GetCursorPos(void*)'
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
  WS_EX_TOOLWINDOW = 0x00000080
  GWL_STYLE = -16
  GWL_EXSTYLE = -20
  SWP_NOSIZE = 0x0001
  SWP_NOMOVE = 0x0002
  SWP_NOACTIVATE = 0x0010
  SWP_FRAMECHANGED = 0x0020
  SWP_SHOWWINDOW = 0x0040
  LWA_ALPHA = 0x00000002
  SRCCOPY = 0x00CC0020
  NULL_PEN = 8
  PS_SOLID = 0
  NIM_ADD = 0x00000000
  NIM_MODIFY = 0x00000001
  NIM_DELETE = 0x00000002
  NIF_MESSAGE = 0x00000001
  NIF_ICON = 0x00000002
  NIF_TIP = 0x00000004
  WM_TRAYICON = 0x8001
  WM_USER_TOGGLE_WALLPAPER = 0x8002
  WM_USER_HIDE_WALLPAPER   = 0x8003
  WM_USER_SHOW_WALLPAPER   = 0x8004
  MF_STRING = 0x00000000
  MF_SEPARATOR = 0x00000800
  TPM_RIGHTBUTTON = 0x0002
  TPM_RETURNCMD = 0x0100
  IMAGE_ICON = 1
  LR_LOADFROMFILE = 0x00000010
  LR_DEFAULTSIZE = 0x00000040

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
    return '' if len == 0
    buffer[0, len * 2].force_encoding('UTF-16LE').encode('UTF-8')
  rescue StandardError
    ''
  end

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


#壁紙用の受け皿ウィンドウ（WorkerW）を探す（Lively Wallpaperの手法）
  def find_workerw
    progman = nil
    5.times do
      progman = FindWindowW(wide('Progman'), nil)
      break if progman && !progman.null?
      sleep 0.1
    end
    raise 'Progmanが見つかりません' if progman.nil? || progman.null?

    result = Fiddle::Pointer.malloc(8)
    SendMessageTimeoutW(progman, 0x052C, 0xD, 0, 0, 1000, result)
    SendMessageTimeoutW(progman, 0x052C, 0xD, 1, 0, 1000, result)

    #方法1: Windows 11 24H2（Progmanの直接の子にWorkerWがいる構成）
    workerw = nil
    5.times do
      workerw = FindWindowExW(progman, nil, wide('WorkerW'), nil)
      break if workerw && !workerw.null?
      sleep 0.05
    end
    return workerw if workerw && !workerw.null?

    #方法2: Windows 10 / 11（SHELLDLL_DefViewを持つトップレベルウィンドウの次の兄弟WorkerW）
    target_workerw = nil
    callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INTPTR_T]) do |top_hwnd, _lparam|
      defview = FindWindowExW(top_hwnd, nil, wide('SHELLDLL_DefView'), nil)
      if defview && !defview.null?
        target_workerw = FindWindowExW(nil, top_hwnd, wide('WorkerW'), nil)
        0
      else
        1
      end
    end
    EnumWindows(callback, 0)
    return target_workerw if target_workerw && !target_workerw.null?

    progman
  end

  #壁紙として貼り付ける（引数hwndは自ウィンドウ、引数xとyは置く場所、引数wとhは大きさ、引数log_pathは記録の場所）
  def attach_wallpaper(hwnd, x, y, w, h, log_path)
    host = find_workerw
    raise '壁紙の配置先ウィンドウが見つかりません' if host.nil? || host.null?
    progman = FindWindowW(wide('Progman'), nil)
    defview = FindWindowExW(progman, nil, wide('SHELLDLL_DefView'), nil)
    raise 'SHELLDLL_DefViewが見つかりません' if defview.nil? || defview.null?

    style = GetWindowLongPtrW(hwnd, GWL_STYLE)
    SetWindowLongPtrW(hwnd, GWL_STYLE, (style & ~WS_POPUP & ~0x00C00000 & ~0x00040000) | WS_CHILD | WS_VISIBLE | 0x04000000)
    SetParent(hwnd, progman)
    ex_style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex_style | WS_EX_LAYERED)
    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA)
    SetWindowPos(hwnd, defview, x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED)
    SetWindowPos(host, hwnd, 0, 0, 0, 0, SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE) if host.to_i != progman.to_i
    InvalidateRect(hwnd, nil, 1)
    UpdateWindow(hwnd)

    ex_now = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
    File.open(log_path, 'a') { |f| f.puts "#{Time.now}: 配置完了（ex=0x#{ex_now.to_s(16)}、#{progman_children_order(hwnd)}）" } rescue nil
    true
  end

  #Progmanの子の重なり順を、手前から並べた文字列にする（引数hwndは自ウィンドウ）
  def progman_children_order(hwnd)
    progman = FindWindowW(wide('Progman'), nil)
    names = []
    child = GetWindow(progman, 5)
    while child && !child.null? && names.size < 20
      names << (child.to_i == hwnd.to_i ? '自分' : class_name(child))
      child = GetWindow(child, 2)
    end
    "手前から: #{names.join(' > ')}"
  rescue StandardError
    '重なり順: 読めない'
  end

  #自ウィンドウがアイコンのすぐ奥にあるか確かめ、崩れていたら並べ直す（引数hwndは自ウィンドウ、引数log_pathは記録の場所。並べ直したら真）
  def keep_below_icons(hwnd, log_path)
    progman = FindWindowW(wide('Progman'), nil)
    return false if progman.nil? || progman.null?
    defview = FindWindowExW(progman, nil, wide('SHELLDLL_DefView'), nil)
    return false if defview.nil? || defview.null?
    return false if GetWindow(defview, 2).to_i == hwnd.to_i

    before = progman_children_order(hwnd)
    SetWindowPos(hwnd, defview, 0, 0, 0, 0, SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE)
    workerw = FindWindowExW(progman, nil, wide('WorkerW'), nil)
    SetWindowPos(workerw, hwnd, 0, 0, 0, 0, SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE) if workerw && !workerw.null?
    File.open(log_path, 'a') { |f| f.puts "#{Time.now}: 重なり順が崩れたので直した（前 #{before} → 後 #{progman_children_order(hwnd)}）" } rescue nil
    true
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

  #色を選ぶ画面を開く（引数owner_hwndは親ウィンドウ、引数initial_rgbは初期色[R, G, B]。戻り値は選ばれた[R, G, B]、取り消しならnil）
  def choose_color_dialog(owner_hwnd = nil, initial_rgb = [0, 0, 0])
    return nil unless API_READY

    cust_colors = Fiddle::Pointer.malloc(64)
    cust_colors[0, 64] = "\xFF" * 64

    init_colorref = (initial_rgb[0] & 0xFF) | ((initial_rgb[1] & 0xFF) << 8) | ((initial_rgb[2] & 0xFF) << 16)

    struct = "\x00" * 72
    struct[0, 4] = [72].pack('L<')
    struct[8, 8] = [owner_hwnd.to_i].pack('Q<') if owner_hwnd
    struct[24, 4] = [init_colorref].pack('L<')
    struct[32, 8] = [cust_colors.to_i].pack('Q<')
    struct[40, 4] = [0x00000001 | 0x00000002].pack('L<')

    struct_ptr = Fiddle::Pointer.malloc(72)
    struct_ptr[0, 72] = struct

    return nil if ChooseColorW(struct_ptr) == 0

    result_ref = struct_ptr[24, 4].unpack1('L<')
    r = result_ref & 0xFF
    g = (result_ref >> 8) & 0xFF
    b = (result_ref >> 16) & 0xFF
    [r, g, b]
  rescue StandardError
    nil
  end

  #アプリのアイコンハンドルを取得する（icoファイル、exe埋め込みアイコン、無ければ標準アプリ枠）
  def app_icon_handle
    return Fiddle::Pointer.new(0) unless API_READY
    ico_candidates = [
      File.expand_path('../../assets/icon.ico', __dir__),
      File.expand_path('../assets/icon.ico', __dir__),
      File.join(data_dir, 'icon.ico')
    ]
    ico_path = ico_candidates.find { |p| File.exist?(p) }
    if ico_path
      icon = LoadImageW(nil, wide(ico_path), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE)
      return icon if icon && !icon.null?
    end
    exe = ENV['OCRAN_EXECUTABLE']
    if exe && File.exist?(exe)
      icon = ExtractIconW(GetModuleHandleW(nil), wide(exe), 0)
      return icon if icon && !icon.null? && icon.to_i > 1
    end
    LoadIconW(nil, Fiddle::Pointer.new(32512))
  rescue StandardError
    Fiddle::Pointer.new(0)
  end

  #NOTIFYICONDATAW構造体のバイナリを作る（引数hwndはウィンドウ、引数tip_textは説明文字）
  def notify_icon_struct(hwnd, tip_text = 'Pixel Wave')
    sz = 976
    buf = Fiddle::Pointer.malloc(sz)
    buf[0, sz] = "\x00" * sz
    buf[0, 4] = [sz].pack('L<')
    buf[8, 8] = [hwnd.to_i].pack('Q<')
    buf[16, 4] = [1].pack('L<')
    buf[20, 4] = [NIF_MESSAGE | NIF_ICON | NIF_TIP].pack('L<')
    buf[24, 4] = [WM_TRAYICON].pack('L<')
    icon = app_icon_handle
    buf[32, 8] = [icon.to_i].pack('Q<')
    tip = wide(tip_text[0, 63])
    buf[40, [tip.bytesize, 254].min] = tip[0, [tip.bytesize, 254].min]
    buf
  end

  #タスクトレイにアイコンを追加する（引数hwndはウィンドウ、引数tip_textは説明文字）
  def add_tray_icon(hwnd, tip_text = 'Pixel Wave')
    return false unless API_READY
    buf = notify_icon_struct(hwnd, tip_text)
    Shell_NotifyIconW(NIM_ADD, buf) != 0
  rescue StandardError
    false
  end

  #タスクトレイからアイコンを削除する（引数hwndはウィンドウ）
  def remove_tray_icon(hwnd)
    return false unless API_READY
    buf = notify_icon_struct(hwnd)
    Shell_NotifyIconW(NIM_DELETE, buf) != 0
  rescue StandardError
    false
  end

  #タスクトレイの右クリックメニューを表示する（引数hwndはウィンドウ、引数pausedは一時停止中か、引数hiddenは非表示中か。戻り値は選ばれた番号）
  def show_tray_menu(hwnd, paused, hidden = false)
    return 0 unless API_READY
    menu = CreatePopupMenu()
    return 0 if menu.nil? || menu.null?

    wallpaper_label = if hidden
                        '壁紙を表示'
                      elsif paused
                        '壁紙を再開'
                      else
                        '壁紙を一時停止'
                      end
    AppendMenuW(menu, MF_STRING, 101, wide('設定を開く'))
    AppendMenuW(menu, MF_SEPARATOR, 0, nil)
    AppendMenuW(menu, MF_STRING, 102, wide(wallpaper_label))
    AppendMenuW(menu, MF_SEPARATOR, 0, nil)
    AppendMenuW(menu, MF_STRING, 103, wide('終了'))

    point = Fiddle::Pointer.malloc(8)
    GetCursorPos(point)
    x, y = point[0, 8].unpack('l<2')

    SetForegroundWindow(hwnd)
    cmd = TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_RETURNCMD, x, y, 0, hwnd, nil)
    DestroyMenu(menu)
    cmd
  rescue StandardError
    0
  end

  #スタートアップフォルダに置くショートカットの場所
  def startup_shortcut_path
    require 'win32ole'
    folder = WIN32OLE.new('WScript.Shell').SpecialFolders('Startup')
    File.join(folder, 'Pixel Wave.lnk')
  end

  #ログイン時に起動するショートカットを作る（引数targetは実行ファイル、引数argsは引数の配列）
  def create_startup_shortcut(target, args)
    require 'win32ole'
    link = WIN32OLE.new('WScript.Shell').CreateShortcut(startup_shortcut_path.tr('/', '\\'))
    link.TargetPath = target.tr('/', '\\')
    link.Arguments = args.map { |a| a.include?(' ') ? "\"#{a}\"" : a }.join(' ')
    link.WorkingDirectory = File.dirname(target).tr('/', '\\')
    link.Save
    true
  rescue StandardError
    false
  end

  #ログイン時に起動するショートカットを消す
  def delete_startup_shortcut
    path = startup_shortcut_path
    File.delete(path) if File.exist?(path)
  rescue StandardError
    nil
  end

  #スクリーンセーバーのファイル（PixelWave.scr）の場所を返す
  def screensaver_path
    if ENV['OCRAN_EXECUTABLE']
      exe = ENV['OCRAN_EXECUTABLE']
      scr = File.join(File.dirname(exe), 'PixelWave.scr')
      FileUtils.cp(exe, scr) unless File.exist?(scr)
      scr
    else
      local_scr = File.expand_path('~/AppData/Local/Programs/PixelWave/PixelWave.scr')
      File.exist?(local_scr) ? local_scr : nil
    end
  rescue StandardError
    nil
  end

  #スクリーンセーバーが有効（PixelWaveが設定されている）か調べる
  def screensaver_active?
    require 'win32/registry'
    active = false
    Win32::Registry::HKEY_CURRENT_USER.open('Control Panel\Desktop') do |reg|
      scr = (reg['SCRNSAVE.EXE'] rescue nil)
      active_flag = (reg['ScreenSaveActive'] rescue '0')
      active = (active_flag == '1' && scr && File.basename(scr).downcase == 'pixelwave.scr')
    end
    active
  rescue StandardError
    false
  end

  #スクリーンセーバーを有効化する（引数pathは.scrの場所、nilなら既定の場所）
  def enable_screensaver(path = nil)
    scr = path || screensaver_path
    return false unless scr && File.exist?(scr)
    require 'win32/registry'
    Win32::Registry::HKEY_CURRENT_USER.create('Control Panel\Desktop') do |reg|
      reg['SCRNSAVE.EXE'] = scr.gsub('/', 92.chr)
      reg['ScreenSaveActive'] = '1'
      reg['ScreenSaveTimeOut'] = '600' unless (reg['ScreenSaveTimeOut'] rescue nil)
    end
    SystemParametersInfoW(17, 1, nil, 2) rescue nil
    true
  rescue StandardError
    false
  end

  #スクリーンセーバーを無効化する
  def disable_screensaver
    require 'win32/registry'
    Win32::Registry::HKEY_CURRENT_USER.create('Control Panel\Desktop') do |reg|
      reg['ScreenSaveActive'] = '0'
    end
    SystemParametersInfoW(17, 0, nil, 2) rescue nil
    true
  rescue StandardError
    false
  end

  #スクリーンセーバーとして登録する（互換用）
  alias register_screensaver enable_screensaver
end
