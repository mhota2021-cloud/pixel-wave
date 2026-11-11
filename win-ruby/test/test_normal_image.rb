#通常画像モード（WIC・NormalImageEngine・レイアウト）の単体テスト
require 'minitest/autorun'
require_relative '../lib/wic'
require_relative '../lib/image_engine'
require_relative '../lib/settings_layout'
require_relative '../lib/platform'

class TestNormalImage < Minitest::Test
  PAINTING_PATH = File.expand_path('../../assets/paintings/hokusai_great_wave.jpg', __dir__)

  def test_wic_decode_cropped_bgra
    skip 'テスト画像がありません' unless File.exist?(PAINTING_PATH)
    w, h, bgra = Wic.decode_cropped_bgra(PAINTING_PATH, 320, 180, :center)
    assert_equal 320, w
    assert_equal 180, h
    assert_equal 320 * 180 * 4, bgra.bytesize

    # クロップ指定（Hash）
    w2, h2, bgra2 = Wic.decode_cropped_bgra(PAINTING_PATH, 200, 100, { x: 0.1, y: 0.1, w: 0.8, h: 0.8 })
    assert_equal 200, w2
    assert_equal 100, h2
    assert_equal 200 * 100 * 4, bgra2.bytesize
  end

  def test_engine_deterministic_center
    engine1 = NormalImageEngine.allocate
    engine1.instance_variable_set(:@width, 1920)
    engine1.instance_variable_set(:@height, 1080)

    engine2 = NormalImageEngine.allocate
    engine2.instance_variable_set(:@width, 1920)
    engine2.instance_variable_set(:@height, 1080)

    10.times do |cycle|
      c1 = engine1.compute_center(cycle)
      c2 = engine2.compute_center(cycle)
      assert_equal c1, c2, "サイクル #{cycle} での中心点が一致しません"
      # 外周上にあることの検証
      on_edge = (c1[0] == 0 || c1[0] == 1920 || c1[1] == 0 || c1[1] == 1080)
      assert on_edge, "中心点 #{c1.inspect} が外周上にありません"
    end
  end

  def test_engine_needs_redraw
    engine = NormalImageEngine.allocate
    engine.instance_variable_set(:@images, [1, 2])
    engine.instance_variable_set(:@pending_redraw, false)
    engine.instance_variable_set(:@last_cycle, 0)

    # 静止表示中（5.0秒）は描き直し不要
    refute engine.needs_redraw?(5.0)

    # 波切り替え中（15.0秒）は描き直し必要
    assert engine.needs_redraw?(15.0)

    # サイクル遷移時（24.1秒、サイクル1）は描き直し必要
    assert engine.needs_redraw?(24.1)
  end

  def test_settings_layout_mode_button
    rects, cards = SettingsLayout.layout(880, 760, 8, 0)
    assert rects.key?(:mode)
    mx, my, mw, mh = rects[:mode]
    assert_equal 180, mw
    assert_equal 36, mh

    # hit_testの検証
    hit = SettingsLayout.hit_test(rects, cards, mx + 5, my + 5)
    assert_equal :mode, hit
  end
end
