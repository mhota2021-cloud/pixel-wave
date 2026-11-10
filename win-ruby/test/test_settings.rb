#設定の読み書きの単体テスト
require 'minitest/autorun'
require 'tmpdir'
require 'json'
require_relative '../lib/settings'

class TestSettings < Minitest::Test
  IDS = %w[a b c].freeze

  def test_missing_file_gives_defaults
    Dir.mktmpdir do |dir|
      s = AppSettings.load(dir, IDS)
      assert_equal IDS, s['enabled']
      assert_equal [], s['userImages']
      assert_equal false, s['wallpaper']
      assert_equal false, s['autostart']
      assert_equal({}, s['builtinCrop'])
    end
  end

  def test_roundtrip
    Dir.mktmpdir do |dir|
      original = { 'enabled' => ['a'], 'userImages' => [{ 'id' => 'u1', 'file' => 'u1.jpg', 'title' => 'x' }], 'wallpaper' => true, 'autostart' => true, 'builtinCrop' => {} }
      AppSettings.save(dir, original)
      assert_equal original, AppSettings.load(dir, IDS)
    end
  end

  def test_broken_file_is_moved_aside
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'settings.json'), '{壊れたjson')
      s = AppSettings.load(dir, IDS)
      assert_equal IDS, s['enabled']
      assert File.exist?(File.join(dir, 'settings.broken.json'))
      refute File.exist?(File.join(dir, 'settings.json'))
    end
  end

  def test_wrong_shape_is_moved_aside
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'settings.json'), JSON.generate({ 'enabled' => 'abc' }))
      s = AppSettings.load(dir, IDS)
      assert_equal IDS, s['enabled']
      assert File.exist?(File.join(dir, 'settings.broken.json'))
    end
  end
end
