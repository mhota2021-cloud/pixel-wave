#設定画面の配置計算の単体テスト
require 'minitest/autorun'
require_relative '../lib/settings_layout'

class TestSettingsLayout < Minitest::Test
  #880×760では、カードが5列になり、ボタンが画面の中に収まる
  def test_layout_fits
    rects, cards = SettingsLayout.layout(880, 760, 8, 0)
    assert_equal 5, SettingsLayout.columns(rects[:grid][2])
    assert_equal 8, cards.length
    _x, y, _w, h = rects[:wallpaper]
    assert y + h <= 760 - 16 + 52 - 52 + 16
    assert_equal 760 - 16, y + h
  end

  #当たり判定（ボタンとカードと削除）
  def test_hit_test
    rects, cards = SettingsLayout.layout(880, 760, 8, 0)
    sx, sy, sw, _sh = rects[:autostart]
    assert_equal :autostart, SettingsLayout.hit_test(rects, cards, sx + 2, sy + 2)
    assert sx + sw < rects[:add][0], '自動起動のボタンが＋と重ならないこと'
    assert sx + sw < rects[:solid][0], '自動起動のボタンが単色ボタンと重ならないこと'
    sol_x, sol_y, _sol_w, _sol_h = rects[:solid]
    assert_equal :solid, SettingsLayout.hit_test(rects, cards, sol_x + 2, sol_y + 2)
    ax, ay, _aw, _ah = rects[:add]
    assert_equal :add, SettingsLayout.hit_test(rects, cards, ax + 2, ay + 2)
    wx, wy, _ww, _wh = rects[:wallpaper]
    assert_equal :wallpaper, SettingsLayout.hit_test(rects, cards, wx + 2, wy + 2)
    _i, rect = cards[0]
    assert_equal [:card, 0], SettingsLayout.hit_test(rects, cards, rect[0] + 10, rect[1] + 60)
    assert_equal [:delete, 0], SettingsLayout.hit_test(rects, cards, rect[0] + rect[2] - 5, rect[1] + 5)
    assert_nil SettingsLayout.hit_test(rects, cards, 4, 4)
  end

  #スクロールの最大は、全体が収まれば0
  def test_max_scroll
    rects, _cards = SettingsLayout.layout(880, 760, 8, 0)
    assert_equal 0, SettingsLayout.max_scroll(rects, 8)
    assert SettingsLayout.max_scroll(rects, 40) > 0
  end
end
