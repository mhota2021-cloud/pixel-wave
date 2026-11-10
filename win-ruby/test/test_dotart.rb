#DotArtの単体テスト（切り抜き、縮小、k-means、波の判定、イージング）
require 'minitest/autorun'
require_relative '../lib/dotart'

class TestDotArt < Minitest::Test
  #横長の画像を3:2に切り抜くと、幅が絞られて中央に来る
  def test_croprect_wide
    x, y, w, h = DotArt.croprect(400, 200, 3, 2, :center)
    assert_equal [50, 0, 300, 200], [x, y, w, h]
  end

  #縦長の画像では、切り抜く位置でyが変わる
  def test_croprect_tall_positions
    assert_equal 0, DotArt.croprect(200, 400, 3, 2, :top)[1]
    assert_equal 267, DotArt.croprect(200, 400, 3, 2, :bottom)[1]
    y = DotArt.croprect(200, 400, 3, 2, :center)[1]
    assert_in_delta 133, y, 1
  end

  #縮小はマスごとの平均になる（555÷4＝138.75を四捨五入して139）
  def test_shrink_average
    pixels = [[0, 0, 0], [100, 100, 100], [200, 200, 200], [255, 255, 255]]
    out = DotArt.shrink(pixels, 2, 2, 1, 1)
    assert_equal [[139, 139, 139]], out
  end

  #k-meansは種を固定すると毎回同じ結果になり、色数と番号の範囲が合う
  def test_kmeans_deterministic
    rng = Random.new(7)
    pixels = Array.new(500) { [rng.rand(256), rng.rand(256), rng.rand(256)] }
    palette1, indices1 = DotArt.kmeans(pixels, 16, 42)
    palette2, indices2 = DotArt.kmeans(pixels, 16, 42)
    assert_equal palette1, palette2
    assert_equal indices1, indices2
    assert_equal 16, palette1.length
    assert_equal 500, indices1.length
    assert indices1.all? { |i| i >= 0 && i < 16 }
  end

  #k-meansは画素が多いときも（間引いても）決定的に動く
  def test_kmeans_sampling_deterministic
    rng = Random.new(9)
    pixels = Array.new(5000) { [rng.rand(256), rng.rand(256), rng.rand(256)] }
    a = DotArt.kmeans(pixels, 16, 3)
    b = DotArt.kmeans(pixels, 16, 3)
    assert_equal a, b
    assert_equal 5000, a[1].length
  end

  #波の先頭の帯の判定（半径ちょうどは含み、内側すぎると含まない）
  def test_wave_front
    assert DotArt.in_wave_front?(95, 100, 18)
    assert DotArt.in_wave_front?(100, 100, 18)
    refute DotArt.in_wave_front?(80, 100, 18)
    refute DotArt.in_wave_front?(101, 100, 18)
  end

  #イージングは両端が0と1で、真ん中が0.5（対称な曲線）になる
  def test_ease_in_out
    assert_in_delta 0.0, DotArt.ease_in_out(0.0)
    assert_in_delta 1.0, DotArt.ease_in_out(1.0)
    assert_in_delta 0.5, DotArt.ease_in_out(0.5), 0.001
    assert DotArt.ease_in_out(0.25) < 0.25
    assert DotArt.ease_in_out(0.75) > 0.75
  end

  #シャッフルは同じ絵が先頭に続かない
  def test_shuffled_order_avoids_first
    rng = Random.new(5)
    10.times do
      order = DotArt.shuffled_order(4, rng, 2)
      refute_equal 2, order[0]
      assert_equal [0, 1, 2, 3], order.sort
    end
  end

  #外周上の点は外周の上にある
  def test_perimeter_point
    rng = Random.new(3)
    20.times do
      x, y = DotArt.pick_perimeter_point(1920, 1080, rng)
      assert(x == 0.0 || x == 1920.0 || y == 0.0 || y == 1080.0)
    end
  end

  #一番遠い角は対角の角になる
  def test_farthest_corner
    d = DotArt.farthest_corner_distance(0, 0, 300, 200)
    assert_in_delta Math.sqrt(300 * 300 + 200 * 200), d, 0.001
  end

  #白へ寄せると明るくなる
  def test_blend_toward_white
    assert_equal [169, 169, 169], DotArt.blend_toward_white([40, 40, 40], 0.6)
  end
end
