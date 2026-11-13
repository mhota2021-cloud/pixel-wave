require 'minitest/autorun'
require_relative '../lib/i18n'

class TestI18n < Minitest::Test
  def test_normalize
    assert_equal 'en', I18n.normalize('en')
    assert_equal 'ja', I18n.normalize('ja')
    assert_equal 'ja', I18n.normalize(nil)
    assert_equal 'ja', I18n.normalize('fr')
  end

  def test_translate_ja_and_en
    assert_equal '壁紙', I18n.t('ja', :wallpaper)
    assert_equal 'Wallpaper', I18n.t('en', :wallpaper)
    assert_equal 'EN', I18n.t('ja', :lang_toggle)
    assert_equal '日本語', I18n.t('en', :lang_toggle)
  end

  def test_translate_with_format
    assert_equal 'Solid (#FF0000)', I18n.t('en', :solid_title, '#FF0000')
    assert_equal '単色 (#FF0000)', I18n.t('ja', :solid_title, '#FF0000')
  end
end
