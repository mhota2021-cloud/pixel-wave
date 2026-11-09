#起動時の引数の読み取り
module Args
  module_function

  #起動モードを返す（引数argvは引数の配列。戻り値はsettingsかscreensaverかpreviewかwallpaperのどれか）
  def parse_mode(argv)
    return :wallpaper if argv.include?('--wallpaper')
    first = argv.find { |a| a.start_with?('/', '-') && a.length > 1 }
    return :settings if first.nil?
    token = first.downcase.sub(%r{\A-+}, '').sub(%r{\A/}, '')
    if token.start_with?('s')
      :screensaver
    elsif token.start_with?('p')
      :preview
    else
      :settings
    end
  end
end
