require 'minitest/autorun'
require 'fileutils'
require_relative '../lib/platform'

class TestPlatformWallpaper < Minitest::Test
  def setup
    @backup_path = Platform.backup_wallpaper_path
    @temp_backup = "#{@backup_path}.test_backup"
    FileUtils.mv(@backup_path, @temp_backup) if File.exist?(@backup_path)
  end

  def teardown
    FileUtils.mv(@temp_backup, @backup_path) if File.exist?(@temp_backup)
  end

  def test_restore_does_nothing_without_backup
    refute Platform.restore_wallpaper, '退避ファイルが無ければ壁紙に触らないこと'
  end
end
