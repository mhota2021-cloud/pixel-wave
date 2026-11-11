#単色画像生成の単体テスト
require 'minitest/autorun'
require_relative '../lib/wic'
require_relative '../lib/settings_window'

class TestSolidColor < Minitest::Test
  def test_create_solid_bmp_decodes_exact_color
    #SettingsWindowのcreate_solid_bmpを検証
    win_class = Class.new do
      include SettingsWindow::ColorHelper rescue nil
    end
    #直接SettingsWindowインスタンスメソッドから借用
    helper = Object.new.extend(Module.new {
      def create_solid_bmp(r, g, b, w = 16, h = 9)
        row_bytes = (w * 3 + 3) & ~3
        image_size = row_bytes * h
        file_size = 54 + image_size
        file_header = ['BM', file_size, 0, 0, 54].pack('a2L<S<S<L<')
        info_header = [40, w, h, 1, 24, 0, image_size, 2835, 2835, 0, 0].pack('L<l<l<S<S<L<L<l<l<L<L<')
        pad = "\x00" * (row_bytes - w * 3)
        pixel = [b, g, r].pack('C3')
        row = (pixel * w) + pad
        file_header + info_header + (row * h)
      end
    })

    bmp_data = helper.create_solid_bmp(45, 120, 200, 16, 9)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'solid.bmp')
      File.binwrite(path, bmp_data)
      w, h, pixels = Wic.decode(path)
      assert_equal 16, w
      assert_equal 9, h
      assert_equal [45, 120, 200], pixels.first
      assert_equal [45, 120, 200], pixels.last
    end
  end
end
