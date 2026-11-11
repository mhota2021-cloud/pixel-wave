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
end
