#Loaderの単体テスト
require 'minitest/autorun'
require 'tmpdir'
require 'json'
require_relative '../lib/loader'

class TestLoader < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @paintings_dir = File.join(@tmpdir, 'paintings')
    @data_dir = File.join(@tmpdir, 'data')
    Dir.mkdir(@paintings_dir)
    Dir.mkdir(@data_dir)
    Dir.mkdir(File.join(@data_dir, 'user-images'))

    #素材画像2枚
    File.write(File.join(@paintings_dir, 'b1.jpg'), 'fake')
    File.write(File.join(@paintings_dir, 'b2.jpg'), 'fake')
    credits = [
      { 'id' => 'b1', 'file' => 'b1.jpg', 'title' => 'Builtin 1', 'artist' => 'Artist 1' },
      { 'id' => 'b2', 'file' => 'b2.jpg', 'title' => 'Builtin 2', 'artist' => 'Artist 2' }
    ]
    File.write(File.join(@paintings_dir, 'credits.json'), JSON.generate(credits))

    #ユーザー画像2枚
    File.write(File.join(@data_dir, 'user-images', 'u1.jpg'), 'fake')
    File.write(File.join(@data_dir, 'user-images', 'u2.jpg'), 'fake')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_paintings_order_and_hidden_builtin
    settings = {
      'enabled' => %w[b1 b2 u1 u2],
      'userImages' => [
        { 'id' => 'u2', 'file' => 'u2.jpg', 'title' => 'User 2' },
        { 'id' => 'u1', 'file' => 'u1.jpg', 'title' => 'User 1' }
      ],
      'builtinCrop' => {},
      'hiddenBuiltin' => ['b1']
    }

    list = Loader.paintings(settings, @paintings_dir, @data_dir)
    ids = list.map { |item| item[:id] }

    #ユーザー画像（u2, u1）が先頭に来て、非表示のb1は除外され、b2だけが続く
    assert_equal %w[u2 u1 b2], ids
  end

  def test_crop_key_is_deterministic
    crop1 = { x: 0.1, y: 0.2, w: 0.8, h: 0.7 }
    crop2 = { 'x' => 0.1, 'y' => 0.2, 'w' => 0.8, 'h' => 0.7 }
    assert_equal '0.1000_0.2000_0.8000_0.7000', Loader.crop_key(crop1)
    assert_equal '0.1000_0.2000_0.8000_0.7000', Loader.crop_key(crop2)
    assert_equal 'center', Loader.crop_key('center')
    assert_equal 'top', Loader.crop_key(:top)
  end
end
