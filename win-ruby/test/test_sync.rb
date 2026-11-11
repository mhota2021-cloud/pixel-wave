require 'minitest/autorun'
require_relative '../lib/engine'

class TestEngineSyncIntegration < Minitest::Test
  def grid(base, count)
    { palette: Array.new(16) { |i| [base + i, base + i, base + i] }, indices: Array.new(count, 0) }
  end

  def test_wallpaper_and_preview_sync_at_any_time
    grids_wall = [grid(10, 160 * 90), grid(100, 160 * 90), grid(200, 160 * 90)]
    grids_prev = [grid(10, 40 * 22), grid(100, 40 * 22), grid(200, 40 * 22)]

    wall = WaveEngine.new(grids_wall, 160, 90, dot: 12)
    prev = WaveEngine.new(grids_prev, 40, 22, dot: 8)

    # 任意の絶対時刻（例: 5000.0秒）
    now = 5000.0
    c_wall = wall.frame(now)
    c_prev = prev.frame(now)

    # 初回フレーム描画でどちらも全ドットを吐き出す
    assert_equal 160 * 90, c_wall.length
    assert_equal 40 * 22, c_prev.length

    # 1秒後（静止フェーズ内）は差分なし
    assert_equal [], wall.frame(now + 1.0)
    assert_equal [], prev.frame(now + 1.0)

    # 15秒後（波遷移フェーズ内、14.0秒で開始）はどちらも再描画要求あり
    assert wall.needs_redraw?(now + 15.0)
    assert prev.needs_redraw?(now + 15.0)

    # どちらも同じ波の進行度で差分ドットを出力
    diff_wall = wall.frame(now + 15.0)
    diff_prev = prev.frame(now + 15.0)
    refute diff_wall.empty?
    refute diff_prev.empty?
  end
end
