require 'minitest/autorun'
require_relative '../lib/platform'
require_relative '../lib/tray_window'

class FakeDisplayWindow
  attr_accessor :paused

  def initialize
    @paused = false
    @opened = false
    @closed = false
  end

  def open_settings
    @opened = true
  end

  def paused?
    @paused
  end

  def toggle_pause
    @paused = !@paused
  end

  def close
    @closed = true
  end
end

class TestTrayWindow < Minitest::Test
  def test_tray_window_lifecycle
    fake = FakeDisplayWindow.new
    tray = TrayWindow.new(fake)
    assert tray.hwnd
    refute_equal 0, tray.hwnd.to_i
    tray.close
  end
end
