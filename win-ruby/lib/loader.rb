#絵の読み込みとドット絵化（キャッシュを使い、変換はDotArtの共通部品で行う）
require 'json'
require_relative 'dotart'
require_relative 'cache'

module Loader
  module_function

  #素材の情報を読む（引数paintings_dirは素材のフォルダ。戻り値はidとfileとtitleとartistとcropの組の配列）
  def credits(paintings_dir)
    path = File.join(paintings_dir, 'credits.json')
    return [] unless File.exist?(path)
    JSON.parse(File.read(path))
  rescue StandardError
    []
  end

  #使う絵の一覧を作る（引数settingsは設定、引数paintings_dirは素材のフォルダ、引数data_dirはデータフォルダ。戻り値はidとpathとcropの組の配列）
  def paintings(settings, paintings_dir, data_dir)
    builtin_crops = settings['builtinCrop'] || {}
    hidden_builtins = settings['hiddenBuiltin'] || []
    user_list = []
    settings['userImages'].each do |u|
      next unless settings['enabled'].include?(u['id'])
      path = File.join(data_dir, 'user-images', u['file'])
      crop = u['crop'] || 'center'
      crop = crop.to_sym if crop.is_a?(String)
      user_list << { id: u['id'], path: path, crop: crop } if File.exist?(path)
    end
    builtin_list = []
    credits(paintings_dir).each do |c|
      next if hidden_builtins.include?(c['id'])
      next unless settings['enabled'].include?(c['id'])
      path = File.join(paintings_dir, c['file'])
      crop = builtin_crops[c['id']] || c['crop'] || 'center'
      crop = crop.to_sym if crop.is_a?(String)
      builtin_list << { id: c['id'], path: path, crop: crop } if File.exist?(path)
    end
    user_list + builtin_list
  end

  #切り取り指定からキャッシュ用の文字を作る（引数cropは切り取り指定）
  def crop_key(crop)
    return crop.to_s unless crop.is_a?(Hash)
    x = crop[:x] || crop['x'] || 0
    y = crop[:y] || crop['y'] || 0
    w = crop[:w] || crop['w'] || 1
    h = crop[:h] || crop['h'] || 1
    sprintf('%.4f_%.4f_%.4f_%.4f', x.to_f, y.to_f, w.to_f, h.to_f)
  end

  #絵をドット絵データにする（引数paintingは絵の情報、引数colsとrowsはドットの数、引数cache_dirはキャッシュのフォルダ、引数decodeは画像を読む手続きで幅と高さと色の配列を返す。戻り値はパレットと番号の組、読めなければnil）
  def grid_for(painting, cols, rows, cache_dir, decode)
    mtime = File.mtime(painting[:path])
    cache_id = "#{painting[:id]}_#{crop_key(painting[:crop])}"
    cached = DotCache.read(cache_dir, cache_id, mtime, cols, rows)
    return cached if cached
    w, h, pixels = decode.call(painting[:path])
    rect = DotArt.croprect(w, h, cols, rows, painting[:crop])
    cropped, cw, ch = DotArt.apply_crop(pixels, w, rect)
    dots = DotArt.shrink(cropped, cw, ch, cols, rows)
    palette, indices = DotArt.kmeans(dots, 16, 42)
    data = { palette: palette, indices: indices }
    DotCache.write(cache_dir, cache_id, mtime, cols, rows, data)
    data
  rescue StandardError => e
    warn "画像を読み込めませんでした：#{painting[:path]}（#{e.message}）"
    nil
  end

  #使う絵すべてのドット絵データを作る（引数listは絵の一覧、他の引数はgrid_forと同じ）
  def grids(list, cols, rows, cache_dir, decode)
    list.filter_map { |p| grid_for(p, cols, rows, cache_dir, decode) }
  end
end
