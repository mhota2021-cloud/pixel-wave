# Pixel Wave（Windows版、Ruby）

Windows版をTauriからRubyに置き換えたものです。macOS版と
Linux版は `../app/` のTauriのままです。描画はWindowsの
API（GDI）を標準の `fiddle` で呼び、画像の読み込みは
Windows Imaging Component（WIC）を使います。gemは
`ocran`（exe化）だけです。常駐アイコンは作らず、壁紙は
別のプロセスとして裏で動きます。

## 開発時の起動

```powershell
bundle install
bundle exec ruby main.rb
```

引数で動きが変わります。

| 引数 | 動き |
| --- | --- |
| なし、`/c` | 設定画面 |
| `/s` | スクリーンセーバー（全画面、入力で終了） |
| `/p <HWND>` | すぐ終了 |
| `--wallpaper` | 壁紙（設定画面が裏で起動する） |

設定画面は1つだけ起動します。2つ目を起動すると、名前付き
ミューテックスで気づき、開いている設定画面を前に出して
終わります。壁紙のプロセスIDは
`%APPDATA%\PixelWave\wallpaper.pid` に書き、「壁紙を止める」で
そのプロセスを終了させます。

## テスト

```powershell
bundle exec ruby -Itest -e "Dir['test/test_*.rb'].each { |f| require File.expand_path(f) }"
```

対象は切り抜き、縮小、k-means（種を固定して毎回同じ結果）、
波の中のドットの判定、引数の読み取り、設定の読み書きと
壊れたファイルの退避、ドットの座標と変わった範囲の計算、
設定画面の配置と当たり判定です。画面とWindows連携は
含みません。

## ビルド

```powershell
.\build.ps1
```

`ocran` でRuby本体と `../assets/` の素材をまとめ、
`PixelWave.exe` を作ります。スクリーンセーバー用の
`PixelWave.scr` は同じファイルのコピーです（タグを押した
ときのGitHub Actionsが両方をReleasesに置きます）。

## 仕組み

- `lib/dotart.rb`：切り抜き、マスごとの平均による縮小、
  k-means、波の判定、イージングの共通部品です。
  `../kadai/convert.rb` もこれを使います（この部品と
  変換ツールの出力は、描画を替えても変えていません）。
- `lib/engine.rb`：アニメーションの状態機械です。値は
  TypeScript版（`../engine/`）の手本どおり、1ドット12px、
  塗り10px、表示14秒、切り替え10秒、イージングは
  cubic-bezier（0.37、0、0.63、1）相当、波の先頭の帯は
  1.5ドット分を白に60%寄せます。
- `lib/window.rb`：`RegisterClassExW` と `CreateWindowExW`
  で枠なしのウィンドウを指定の大きさのとおりに作ります。
  ウィンドウプロシージャは `Fiddle::Closure::BlockCaller`
  で作り、変数に持ち続けて消えないようにします。画面と
  同じ大きさのメモリ上のビットマップ（裏画面）を1枚持ち、
  最初に背景色（#141418）で塗って、変わったドットだけを
  `FillRect` で塗ります。`WM_PAINT` では裏画面を `BitBlt`
  で写すだけです。塗った範囲は `InvalidateRect` で
  描き直しの対象にします。ブラシは色ごとに作って
  使い回し、終了時に `DeleteObject` で消します。
- 時間は `SetTimer` で進めます。切り替え中は16ミリ秒
  ごと、表示しているだけの間は間引いて起きるだけにし、
  電池と全画面の判定は2秒ごとに行います。
- ウィンドウを作った直後に `request_full_redraw` で全部の
  ドットを描かせるので、電池で動いていて切り替えを止めて
  いるときも最初の1枚は出ます。
- `lib/wic.rb`：WICをCOMの関数表経由で呼び、JPEGとPNGを
  32ビットRGBAに変換して読みます。設定画面の縮小画像は
  WICの拡大縮小で作り、`StretchDIBits` で描きます。
- `lib/platform.rb`：Win32 APIの定義です。ポインタと
  同じ大きさの値（HWND・WPARAM・LPARAM・LRESULT）は
  必ず `void*` か `intptr_t`・`uintptr_t` で受け渡します
  （`long` はWindowsでは32ビットしかなく、以前ここで
  変換エラーになり壁紙が貼れませんでした）。
- 変換結果は `%APPDATA%\PixelWave\cache\` に、絵のidと
  ファイルの更新日時と列数と行数ごとにMarshalで保存し、
  2回目からは読むだけにします。
- 設定は `%APPDATA%\PixelWave\settings.json` に、Tauri版と
  同じ形で保存します。壊れていたら `settings.broken.json`
  に退避して初期設定で起動します。

## 設定画面

配置は前の版と同じです。文字は `CreateFontW`（「Yu Gothic
UI」、名前で指定）と `DrawTextW` で描き、作品名と作者は
16px、ボタンは18pxです。クリックは `WM_LBUTTONUP`、
マウスが乗った所は `WM_MOUSEMOVE` で色を変えます。
描き直すのはプレビューが動いているときと操作があった
ときだけです。ウィンドウの高さは、作業領域（画面から
タスクバーを引いた高さ）に収まるように決めます。

## 壁紙（Windows 11 24H2以降への対応）

実機でアイコンの後ろに見えた方法（`attach_24h2`）です。

- Progmanに `0x052C` を送った後、ウィンドウをProgmanの
  直接の子にします（`WS_CHILD`）。
- 重なり順を `SHELLDLL_DefView` のすぐ奥にします。
- `WS_EX_LAYERED` と `SetLayeredWindowAttributes`（255）
  でレイヤードにします（WorkerWの子にすると合成されず
  見えませんでした）。
- スタイルを変えた後の `SetWindowPos` には
  `SWP_FRAMECHANGED` を付け、古いタイトルバーが残らない
  ようにします。
- 貼り付けは、ウィンドウを作ったスレッドから呼びます。
- 前面のアプリが全画面のときと電池で動いているときは
  描画を止めます。
- 壁紙がオンの間は `HKCU\...\Run` に `--wallpaper` 付きで
  登録し、オフで消します。

## スクリーンセーバー

全画面の大きさで最前面（`WS_EX_TOPMOST`）に出します。
マウスの移動（数ピクセルの揺れは無視）、クリック、キー
入力で終了します。「スクリーンセーバーにする」は、exeを
`%APPDATA%\PixelWave\PixelWave.scr` にコピーし、HKCUの
`SCRNSAVE.EXE` に登録して、Windowsのスクリーンセーバー
の設定画面を開きます。管理者権限は使いません。

## 起動にかかる時間とCPU（1920×1080、8枚）

このマシン（Linux、Ruby 3.2）で測った値です。画像の
読み込みは本番のWICより遅い経路（ffmpegとPPM）で、
変換とキャッシュの部分を測っています。

|  | 時間 |
| --- | --- |
| 最初の起動（変換とキャッシュ書き込み） | 約8.4秒 |
| 2回目（キャッシュを読むだけ） | 約5ミリ秒 |

CPUの使用率は、エンジンの計算部分を測った値です。

|  | 1コアあたり |
| --- | --- |
| 表示しているだけの14秒間 | 約0% |
| 切り替えの10秒間 | 1フレーム約6.5ミリ秒（16ミリ秒の間隔に収まる） |

前のGosu版は、何もしていなくても約30%を使い続けました。
GDI版は表示中はタイマーで間引いて起きるだけで、裏画面へ
塗るのは変わったドットだけなので、表示中はほぼ0%に
なります。切り替え中はドットの判定の計算が主な負荷で、
描画は変わったドット分だけです。Windows実機での値は
確認項目で確かめてください。

## Tauri版との違い

- 常駐アイコンがありません。壁紙を止めるときは設定画面を
  もう一度開きます。
- 画像の追加はファイルを選ぶ画面からだけです（ドラッグ＆
  ドロップの受け取りはありません）。
- スクリーンセーバーの表示はメインディスプレイだけです。
