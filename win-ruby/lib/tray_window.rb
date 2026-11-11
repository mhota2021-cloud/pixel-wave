#タスクトレイのアイコンを管理する不可視トップレベルウィンドウ
#Windowsの仕様上、トレイアイコンの親（hWnd）はトップレベルウィンドウである必要があるため、
#Progmanの子ウィンドウになる壁紙ウィンドウから分離して管理する
require_relative 'window'
require_relative 'platform'

class TrayWindow < NativeWindow
  #初期化（引数display_windowは操作対象のDisplayWindowインスタンス）
  def initialize(display_window)
    @display_window = display_window
    super(
      class_name: 'PixelWaveTrayHelper',
      title: 'PixelWaveTray',
      width: 0,
      height: 0,
      x: 0,
      y: 0,
      ex_style: Platform::WS_EX_TOOLWINDOW,
      style: Platform::WS_POPUP
    )
    Platform.add_tray_icon(@hwnd, 'Pixel Wave - 壁紙') if Platform::API_READY
  end

  #メッセージの処理
  def handle_message(hwnd, msg, wparam, lparam)
    case msg
    when Platform::WM_TRAYICON
      on_tray_icon(wparam, lparam)
      0
    when Platform::WM_USER_TOGGLE_WALLPAPER
      @display_window.toggle_wallpaper_visibility
      0
    when Platform::WM_USER_HIDE_WALLPAPER
      @display_window.hide_wallpaper
      0
    when Platform::WM_USER_SHOW_WALLPAPER
      @display_window.show_wallpaper
      0
    when Platform::WM_USER_SET_MODE
      @display_window.reload_mode
      0
    when WM_DESTROY
      Platform.remove_tray_icon(@hwnd) if Platform::API_READY
      0
    end
  end

  private

  #タスクトレイのマウス操作
  def on_tray_icon(_wparam, lparam)
    msg = lparam.to_i & 0xFFFF
    case msg
    when 0x0202, 0x0203
      @display_window.open_settings
    when 0x0205, 0x007B
      cmd = Platform.show_tray_menu(@hwnd, @display_window.paused?, @display_window.wallpaper_hidden?)
      case cmd
      when 101
        @display_window.open_settings
      when 102
        if @display_window.wallpaper_hidden?
          @display_window.show_wallpaper
        else
          @display_window.toggle_pause
        end
      when 103
        @display_window.close
      end
    end
  end
end
