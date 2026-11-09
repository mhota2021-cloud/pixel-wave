require 'minitest/autorun'
require 'fileutils'
require 'json'
require_relative '../lib/platform'

class TestPlatformWallpaper < Minitest::Test
  def setup
    @backup_path = Platform.backup_wallpaper_path
    @temp_backup = "#{@backup_path}.test_backup"
    FileUtils.cp(@backup_path, @temp_backup) if File.exist?(@backup_path)
    File.delete(@backup_path) rescue nil
  end

  def teardown
    File.delete(@backup_path) rescue nil
    FileUtils.mv(@temp_backup, @backup_path) if File.exist?(@temp_backup)
  end

  def test_backup_creates_file_and_does_not_overwrite
    skip 'Windows API環境のみ' unless Platform::API_READY

    info1 = Platform.backup_wallpaper
    assert File.exist?(@backup_path), 'バックアップファイルが作成されること'
    assert info1.key?('wallpaper')
    assert info1.key?('background')

    # 意図的に別のダミー内容を書き込む
    dummy_data = { 'wallpaper' => 'dummy_path.jpg', 'background' => '1 2 3' }
    File.write(@backup_path, JSON.pretty_generate(dummy_data), encoding: 'UTF-8')

    # 再度backup_wallpaperを呼んでも既存ファイルを上書きしないこと
    info2 = Platform.backup_wallpaper
    assert_equal 'dummy_path.jpg', info2['wallpaper']
  end

  def test_restore_removes_backup_file
    skip 'Windows API環境のみ' unless Platform::API_READY

    # 現在の設定をバックアップ
    Platform.backup_wallpaper
    assert File.exist?(@backup_path)

    # 復元を実行
    res = Platform.restore_wallpaper
    assert res, 'restore_wallpaperが成功すること'
    refute File.exist?(@backup_path), '復元完了後にバックアップファイルが削除されること'
  end
end
