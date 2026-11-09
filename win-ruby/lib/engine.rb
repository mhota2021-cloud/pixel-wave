#アニメーションの状態機械（描画から切り離した純粋な部分。値はTypeScript版のエンジンに合わせる）
require_relative 'dotart'

class WaveEngine
  DISPLAY_SECONDS = 14.0
  TRANSITION_SECONDS = 10.0
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
    @order = DotArt.shuffled_order(grids.length, rng)
    @pos = 0
    @phase = :show
    @phase_started = nil
    @from = @order[0] || 0
    @target = @from
    @center = nil
    @max_dist = 1.0
    @distances = nil
    count = cols * rows
    @shown = Array.new(count) { [@from, false] }
    @pending = grids.empty? ? nil : all_changes
  end

  #ドットの数を返す
  def dot_count
    @cols * @rows
  end

  #時刻で状態を進める（引数nowは秒。戻り値は変わったドットの配列で、要素は列と行と色）
  def frame(now)
    return [] if @grids.empty?
    @phase_started = now if @phase_started.nil?
    if @phase == :show
      if @grids.length > 1 && now - @phase_started >= DISPLAY_SECONDS
        start_transition(now)
        transition_frame(now)
      else
        initial = @pending
        @pending = nil
        initial || []
      end
    else
      transition_frame(now)
    end
  end

  #描き直しが必要か返す（引数nowは秒。表示だけの間は偽になる）
  def needs_redraw?(now)
    return false if @grids.empty?
    return true if @phase_started.nil?
    return true if @phase == :transition
    return true if !@pending.nil?
    @grids.length > 1 && now - @phase_started >= DISPLAY_SECONDS
  end

  #最初の描画のために全ドットを対象にする
  def request_full_redraw
    return if @grids.empty?
    @pending = all_changes
  end

  private

  #今の表示状態で全ドットの変更一覧を作る
  def all_changes
    changes = []
    dot_count.times do |i|
      painting, glow = @shown[i]
      changes << [i % @cols, i / @cols, color_for(painting, i, glow)]
    end
    changes
  end

  #ドットの色を返す（引数paintingは絵の番号、引数iはドットの位置、引数glowは光らせるかどうか）
  def color_for(painting, i, glow)
    grid = @grids[painting]
    rgb = grid[:palette][grid[:indices][i]]
    glow ? DotArt.blend_toward_white(rgb, GLOW_RATIO) : rgb
  end

  #切り替えを始める（引数nowは秒）
  def start_transition(now)
    @phase = :transition
    @phase_started = now
    @from = @order[@pos]
    @pos = (@pos + 1) % @order.length
    @order = DotArt.shuffled_order(@grids.length, @rng, @from) if @pos == 0
    @target = @order[@pos]
    w = @cols * @dot
    h = @rows * @dot
    @center = DotArt.pick_perimeter_point(w, h, @rng)
    @max_dist = DotArt.farthest_corner_distance(@center[0], @center[1], w, h)
    @distances = Array.new(dot_count) do |i|
      cx = (i % @cols) * @dot + @dot / 2.0
      cy = (i / @cols) * @dot + @dot / 2.0
      DotArt.distance(cx, cy, @center[0], @center[1])
    end
  end

  #切り替え中の1フレーム（引数nowは秒。戻り値は変わったドットの配列）
  def transition_frame(now)
    t = (now - @phase_started) / TRANSITION_SECONDS
    changes = []
    if t >= 1.0
      dot_count.times do |i|
        update_dot(changes, i, @target, false)
      end
      @phase = :show
      @phase_started = now
      return changes
    end
    radius = DotArt.ease_in_out(t) * @max_dist
    band = BAND_DOTS * @dot
    dot_count.times do |i|
      d = @distances[i]
      painting = d <= radius ? @target : @from
      glow = DotArt.in_wave_front?(d, radius, band)
      update_dot(changes, i, painting, glow)
    end
    changes
  end

  #ドットの状態を更新し、変わったら一覧に足す（引数changesは一覧、引数iはドットの位置、引数paintingは絵の番号、引数glowは光らせるかどうか）
  def update_dot(changes, i, painting, glow)
    return if @shown[i] == [painting, glow]
    @shown[i] = [painting, glow]
    changes << [i % @cols, i / @cols, color_for(painting, i, glow)]
  end
end
