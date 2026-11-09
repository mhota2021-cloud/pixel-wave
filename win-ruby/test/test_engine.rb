#エンジンの状態機械の単体テスト（表示の間は変わらず、切り替えで全部入れ替わる）
require 'minitest/autorun'
require_relative '../lib/engine'

class TestEngine < Minitest::Test
  #2枚分のダミーのドット絵データを作る（引数baseは色の基準）
  def grid(base)
    { palette: Array.new(16) { |i| [base + i, base + i, base + i] }, indices: Array.new(100, 0) }
  end

  def setup
    @engine = WaveEngine.new([grid(0), grid(100)], 10, 10, rng: Random.new(1))
  end

  def test_first_frame_draws_everything
    changes = @engine.frame(0.0)
    assert_equal 100, changes.length
  end

  def test_show_phase_is_quiet
    @engine.frame(0.0)
    assert_equal [], @engine.frame(1.0)
    assert_equal [], @engine.frame(13.9)
    refute @engine.needs_redraw?(13.9)
  end

  def test_transition_finishes_to_next_painting
    @engine.frame(0.0)
    @engine.frame(14.0)
    assert @engine.needs_redraw?(14.1)
    last = nil
    t = 14.0
    while t < 24.5
      last = @engine.frame(t)
      t += 0.5
    end
    colors = last.map { |c| c[2] }
    assert colors.all? { |rgb| rgb[0] >= 100 }, '切り替え後は次の絵の色になっている'
    refute @engine.needs_redraw?(25.0)
  end

  def test_single_painting_never_transitions
    engine = WaveEngine.new([grid(0)], 10, 10, rng: Random.new(1))
    engine.frame(0.0)
    assert_equal [], engine.frame(100.0)
    refute engine.needs_redraw?(100.0)
  end

  def test_no_paintings_is_quiet
    engine = WaveEngine.new([], 10, 10, rng: Random.new(1))
    assert_equal [], engine.frame(0.0)
    refute engine.needs_redraw?(0.0)
  end
end
