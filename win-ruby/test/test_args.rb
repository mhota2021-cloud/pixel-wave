#引数の読み取りの単体テスト
require 'minitest/autorun'
require_relative '../lib/args'

class TestArgs < Minitest::Test
  def test_no_args_is_settings
    assert_equal :settings, Args.parse_mode([])
  end

  def test_c_is_settings
    assert_equal :settings, Args.parse_mode(['/c'])
  end

  def test_s_is_screensaver
    assert_equal :screensaver, Args.parse_mode(['/s'])
    assert_equal :screensaver, Args.parse_mode(['-s'])
  end

  def test_p_is_preview
    assert_equal :preview, Args.parse_mode(['/p', '12345'])
  end

  def test_wallpaper_flag
    assert_equal :wallpaper, Args.parse_mode(['--wallpaper'])
  end
end
