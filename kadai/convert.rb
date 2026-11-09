# 名画の画像を、課題版（kadai6b.rb）に貼り付けるドット絵のデータに変換する
#
# 使い方:
#   ruby convert.rb ../assets/paintings/hokusai_great_wave.jpg ../assets/paintings/vangogh_starry_night.jpg
#   画像の後ろに「:top」「:bottom」を付けると、切り抜く位置を上端・下端にする（既定は中央）
#
# 1. ffmpegでJPEGなどをPPM（P6）に変換して読み込む（Rubyの標準ライブラリはJPEGを読めないため）
# 2. 縦横比3:2に切り抜き、30×20のマスごとに色を平均して縮小する
# 3. k-means法で16色に減らす（乱数の種を固定し、何度実行しても同じ結果にする）
#    切り抜き・縮小・k-meansは、Windows版のアプリと共通の部品（win-ruby/lib/dotart.rb）を使う
# 4. 「$palettes」「$paintings」をRubyのコードとして「paintings.rb.txt」に書き出す

require_relative "../win-ruby/lib/dotart"

COLS = 30
ROWS = 20
COLORS = 16
SEED = 42

# 画像をPPMとして読み込み、[幅, 高さ, 画素の配列（[r, g, b] の並び）] を返す
def readimage(path)
  data = IO.popen(["ffmpeg", "-v", "error", "-i", path, "-f", "image2pipe", "-vcodec", "ppm", "-"], "rb", &:read)
  raise "#{path} を読めなかった" if data.nil? || data.empty?
  header = data.match(/\AP6\s+(\d+)\s+(\d+)\s+(\d+)\s/)
  raise "#{path} がP6のPPMになっていない" unless header
  w = header[1].to_i
  h = header[2].to_i
  bytes = data.byteslice(header[0].bytesize, w * h * 3).bytes
  [w, h, bytes.each_slice(3).to_a]
end

# 数の並びを、1行15個までで折り返した文字列にする
def numberlines(nums, indent)
  nums.each_slice(15).map { |s| s.join(",") }.join(",\n" + " " * indent)
end

if ARGV.empty?
  warn "使い方：ruby convert.rb（画像のパスを並べる。後ろに「:top」「:bottom」を付けてもよい）"
  exit 1
end

palettes = []
paintings = []
ARGV.each do |arg|
  path, crop = arg.split(/:(?=top$|bottom$|center$)/)
  w, h, pixels = readimage(path)
  rect = DotArt.croprect(w, h, COLS, ROWS, (crop || "center").to_sym)
  cropped, cw, ch = DotArt.apply_crop(pixels, w, rect)
  colors = DotArt.shrink(cropped, cw, ch, COLS, ROWS)
  palette, labels = DotArt.kmeans(colors, COLORS, SEED)
  palettes << palette
  paintings << labels.each_slice(COLS).to_a
  warn "#{File.basename(path)}: #{w}×#{h} → #{COLS}×#{ROWS}、#{COLORS}色"
end

out = +"$palettes = [\n"
out << palettes.map { |pal|
  "  [\n" + pal.each_slice(4).map { |s| "    " + s.map { |c| "[#{c.join(',')}]" }.join(", ") }.join(",\n") + "\n  ]"
}.join(",\n")
out << "\n]\n$paintings = [\n"
out << paintings.map { |rows|
  "  [\n" + rows.map { |r| "    [" + numberlines(r, 5) + "]" }.join(",\n") + "\n  ]"
}.join(",\n")
out << "\n]\n"
File.write("paintings.rb.txt", out)
warn "paintings.rb.txtに書き出した"
