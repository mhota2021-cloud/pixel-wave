#アニメーションの状態機械（描画から切り離した純粋な部分。値はTypeScript版のエンジンに合わせる）
require_relative 'dotart'

class WaveEngine
  DISPLAY_SECONDS = 14.0
  TRANSITION_SECONDS = 10.0
  CYCLE_SECONDS = DISPLAY_SECONDS + TRANSITION_SECONDS # 24.0秒
  DOT = 12
  FILL = 10
  BAND_DOTS = 1.5
  GLOW_RATIO = 0.6
  BACKGROUND = [20, 20, 24].freeze

  attr_reader :dot, :fill

  #初期化（引数gridsはパレットと番号の組の配列、引数colsとrowsはドットの数、引数rngは乱数、引数dotとfillはドットの大きさと塗りつぶし幅）
  def initialize(grids, cols, rows, rng: Random.new, dot: DOT, fill: FILL)
    @grids = grids
    @cols = cols
    @rows = rows
    @dot = dot
    @fill = fill
    @rng = rng
    count = cols * rows
    @shown = Array.new(count) { [-1, false] }
    @pending_full_redraw = true
    @last_cycle = nil
    @center = nil
    @max_dist = 1.0
    @distances = nil
  end

  #ドットの数を返す
  def dot_count
    @cols * @rows
  end

  #時刻で状態を進める（引数nowは秒。絶対時刻でも相対時刻でも決定論的に全プロセスで同期する）
  def frame(now)
    return [] if @grids.empty?

    #絵が1枚のときは常にその絵を表示
    if @grids.length == 1
      changes = []
      dot_count.times do |i|
        update_dot(changes, i, 0, false)
      end
      @pending_full_redraw = false
      return changes
    end

    cycle = (now / CYCLE_SECONDS).floor
    cycle_time = now - (cycle * CYCLE_SECONDS)

    #サイクルが変わったら波の中心点を計算（サイクル番号で全インスタンスで同じ位置から波が出る）
    if @last_cycle != cycle
      @last_cycle = cycle
      setup_cycle(cycle)
    end

    from_idx = cycle % @grids.length
    to_idx = (cycle + 1) % @grids.length
    changes = []

    if cycle_time < DISPLAY_SECONDS
      #静止表示フェーズ（fromの絵を表示）
      dot_count.times do |i|
        update_dot(changes, i, from_idx, false)
      end
    else
      #波切り替えフェーズ（fromからtoへ波が広がる）
      t = (cycle_time - DISPLAY_SECONDS) / TRANSITION_SECONDS
      t = [[t, 0.0].max, 1.0].min
      radius = DotArt.ease_in_out(t) * @max_dist
      band = BAND_DOTS * @dot
      dot_count.times do |i|
        d = @distances[i]
        painting = d <= radius ? to_idx : from_idx
        glow = DotArt.in_wave_front?(d, radius, band)
        update_dot(changes, i, painting, glow)
      end
    end

    @pending_full_redraw = false
    changes
  end

  #描き直しが必要か返す（引数nowは秒。表示だけの間は偽になる）
  def needs_redraw?(now)
    return false if @grids.empty?
    return true if @pending_full_redraw
    return false if @grids.length <= 1

    cycle = (now / CYCLE_SECONDS).floor
    cycle_time = now - (cycle * CYCLE_SECONDS)

    cycle_time >= DISPLAY_SECONDS || @last_cycle != cycle
  end

  #最初の描画のために全ドットを対象にする
  def request_full_redraw
    @pending_full_redraw = true
    @shown.map! { [-1, false] }
  end

  private

  #サイクルの波の中心点と距離マップを計算する（サイクル番号で決定論的に生成）
  def setup_cycle(cycle)
    w = @cols * @dot.to_f
    h = @rows * @dot.to_f
    rng = Random.new(cycle)
    perimeter = 2.0 * (w + h)
    t = rng.rand * perimeter
    if t < w
      @center = [t, 0.0]
    elsif t < w + h
      @center = [w, t - w]
    elsif t < 2.0 * w + h
      @center = [t - w - h, h]
    else
      @center = [0.0, t - 2.0 * w - h]
    end
    @max_dist = DotArt.farthest_corner_distance(@center[0], @center[1], w, h)
    @distances = Array.new(dot_count) do |i|
      cx = (i % @cols) * @dot + @dot / 2.0
      cy = (i / @cols) * @dot + @dot / 2.0
      DotArt.distance(cx, cy, @center[0], @center[1])
    end
  end

  #ドットの色を返す（引数paintingは絵の番号、引数iはドットの位置、引数glowは光らせるかどうか）
  def color_for(painting, i, glow)
    grid = @grids[painting]
    rgb = grid[:palette][grid[:indices][i]]
    glow ? DotArt.blend_toward_white(rgb, GLOW_RATIO) : rgb
  end

  #ドットの状態を更新し、変わったら一覧に足す（引数changesは一覧、引数iはドットの位置、引数paintingは絵の番号、引数glowは光らせるかどうか）
  def update_dot(changes, i, painting, glow)
    return if @shown[i] == [painting, glow]
    @shown[i] = [painting, glow]
    changes << [i % @cols, i / @cols, color_for(painting, i, glow)]
  end
end
