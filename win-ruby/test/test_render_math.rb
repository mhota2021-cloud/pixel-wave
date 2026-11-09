#描画の座標計算の単体テスト
require 'minitest/autorun'
require_relative '../lib/render_math'

class TestRenderMath < Minitest::Test
  #ドットの塗る範囲は整数で、マスの中に1pxずつ余る
  def test_dot_rect_is_integer_and_inset
    assert_equal [1, 1, 10, 10], RenderMath.dot_rect(0, 0, 12, 10)
    assert_equal [25, 13, 10, 10], RenderMath.dot_rect(2, 1, 12, 10)
    assert RenderMath.dot_rect(3, 3, 12, 10).all? { |v| v.is_a?(Integer) }
  end

  #変わった範囲は、端のドットまで含む
  def test_union_rect
    assert_equal [0, 0, 36, 12], RenderMath.union_rect([[0, 0, nil], [2, 0, nil]], 12)
    assert_equal [12, 24, 12, 12], RenderMath.union_rect([[1, 2, nil]], 12)
    assert_nil RenderMath.union_rect([], 12)
  end

  #COLORREFは赤が下位バイト
  def test_colorref
    assert_equal 0x000000, RenderMath.colorref([0, 0, 0])
    assert_equal 0x0000FF, RenderMath.colorref([255, 0, 0])
    assert_equal 0xFF0000, RenderMath.colorref([0, 0, 255])
    assert_equal 20 | (20 << 8) | (24 << 16), RenderMath.colorref([20, 20, 24])
  end

  #矩形の変換
  def test_rect_array
    assert_equal [1, 2, 11, 22], RenderMath.rect_array([1, 2, 10, 20])
  end
end
