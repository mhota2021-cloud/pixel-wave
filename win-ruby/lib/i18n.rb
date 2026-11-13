#UI表示文言の多言語辞書（日本語と英語を切り替え）
module I18n
  STRINGS = {
    'ja' => {
      autostart_on: 'ログイン時起動ON',
      autostart_off: 'ログイン時起動OFF',
      mode_normal: 'モード:通常画像',
      mode_pixel: 'モード:ドット絵',
      wallpaper: '壁紙',
      screensaver: 'スクリーンセーバー',
      lang_toggle: 'EN',
      solid_title: '単色 (%s)',
      image_filter: '画像',
      tray_tooltip: 'Pixel Wave - 壁紙',
      tray_open_settings: '設定を開く',
      tray_show: '壁紙を表示',
      tray_resume: '壁紙を再開',
      tray_pause: '壁紙を一時停止',
      tray_exit: '終了',
      crop_window_title: '切り取り範囲の調整 [画面比率 %.2f:1] - Pixel Wave',
      crop_header: '切り取り範囲の調整',
      crop_sub: '画面サイズ比率: %.2f:1 - 枠をドラッグして移動、四隅で拡大縮小',
      crop_reset: '中央に戻す',
      crop_cancel: 'キャンセル',
      crop_confirm: '決定 (Enter)'
    },
    'en' => {
      autostart_on: 'Auto-start: ON',
      autostart_off: 'Auto-start: OFF',
      mode_normal: 'Mode: Original',
      mode_pixel: 'Mode: Pixel Art',
      wallpaper: 'Wallpaper',
      screensaver: 'Screensaver',
      lang_toggle: '日本語',
      solid_title: 'Solid (%s)',
      image_filter: 'Images',
      tray_tooltip: 'Pixel Wave - Wallpaper',
      tray_open_settings: 'Open Settings',
      tray_show: 'Show Wallpaper',
      tray_resume: 'Resume Wallpaper',
      tray_pause: 'Pause Wallpaper',
      tray_exit: 'Exit',
      crop_window_title: 'Adjust Crop Area [Aspect %.2f:1] - Pixel Wave',
      crop_header: 'Adjust Crop Area',
      crop_sub: 'Screen Aspect: %.2f:1 - Drag to move, drag corners to resize',
      crop_reset: 'Reset to Center',
      crop_cancel: 'Cancel',
      crop_confirm: 'Apply (Enter)'
    }
  }.freeze

  module_function

  #言語コード（'ja'または'en'）を正規化する
  def normalize(lang)
    lang == 'en' ? 'en' : 'ja'
  end

  #キーに対応する文字列を返す（引数argsがあればsprintfで埋め込む）
  def t(lang, key, *args)
    table = STRINGS[normalize(lang)]
    text = table[key] || STRINGS['ja'][key] || key.to_s
    args.empty? ? text : sprintf(text, *args)
  end
end
