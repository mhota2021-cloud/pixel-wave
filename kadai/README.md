# 変換ツール（Ruby）

名画の画像を30×20のドット絵データ（パレットと番号）にして、
`paintings.rb.txt` へ書き出すツールです。切り抜きと縮小と
k-meansの計算は `../win-ruby/lib/dotart.rb` の共通部品を使い、
画像の読み込みはffmpegでPPMに変換して行います。

## 使い方

```sh
ruby convert.rb ../assets/paintings/hokusai_great_wave.jpg ../assets/paintings/vangogh_starry_night.jpg ../assets/paintings/monet_impression_sunrise.jpg ../assets/paintings/klimt_the_kiss.jpg:top
```

- 引数は画像ファイルの並びです。後ろに `:top` や `:bottom` を
  付けると切り抜く位置を指定できます（既定は中央）。
- 出力の `paintings.rb.txt` は、課題版のRubyプログラムの先頭に
  貼り付ける形（`$palettes` と `$paintings`）です。
