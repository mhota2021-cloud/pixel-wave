#Platform連携の単体テスト
require 'minitest/autorun'
require_relative '../lib/platform'

class TestPlatform < Minitest::Test
  def test_battery_powered_returns_boolean
    result = Platform.battery_powered?
    assert_includes [true, false], result
  end

  def test_foreground_fullscreen_returns_boolean
    result = Platform.foreground_fullscreen?(nil)
    assert_includes [true, false], result
  end

  def test_screensaver_active_returns_boolean
    result = Platform.screensaver_active?
    assert_includes [true, false], result
  end

  def test_screensaver_path_does_not_crash
    #環境によりnilまたはString
    path = Platform.screensaver_path
    assert path.nil? || path.is_a?(String)
  end

  def test_notify_icon_struct_layout
    #976バイトの構造体バイナリが生成されること
    buf = Platform.notify_icon_struct(1234, 'Pixel Wave Test')
    assert_equal 976, buf.size
    assert_equal 976, buf[0, 4].unpack1('L<')
    assert_equal 1234, buf[8, 8].unpack1('Q<')
  end

  def test_add_and_remove_tray_icon_does_not_crash
    #GUI環境外でも例外を吐かず安全に終了すること
    assert_includes [true, false], Platform.add_tray_icon(nil)
    assert_includes [true, false], Platform.remove_tray_icon(nil)
  end
end
