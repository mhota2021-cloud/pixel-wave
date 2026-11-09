# PixelWaveSaver（macOSのスクリーンセーバー）

Swiftで作る `.saver` バンドルです。`ScreenSaverView` を継承した
ビューが `WKWebView` を持ち、描画エンジン（`engine.js`）を表示します。
Xcodeのプロジェクトは使わず、`build.sh` が `swiftc` だけで
組み立てます（Mac上で実行してください）。

```sh
./build.sh   # dist/PixelWaveSaver.saver ができ、アドホック署名される
```

中身は次のとおりです。

- `Sources/PixelWaveSaverView.swift`：ビュー本体と、Web一式を渡す
  `pixelwave` スキームの係。
- `Info.plist`：バンドルの情報。主体クラスは `PixelWaveSaverView`。
- `Contents/Resources/web/`（ビルド時に生成）：`saver.html`、
  `engine.js`、素材の絵（`images/`）、初期設定
  （`default-settings.json`）。

## 設定の読み方

セーバーは他社製のため `legacyScreenSaver` のサンドボックスの中で
動き、アプリのデータフォルダを読めません。そのため、アプリが
`~/Library/Application Support/PixelWave/` へ設定
（`saver-settings.json`）と使う絵（`images/`）を書き出しておき、
セーバーはそこを読みます。この場所はサンドボックスの中から
読み取りだけできることが実測で知られています。なお、サンドボックスの
中では `NSHomeDirectory()` がコンテナを指すため、本当のホームは
`getpwuid` で取ります。
書き出しは、設定を変えるたびと「スクリーンセーバーにする」を
押したときに行われます。書き出した設定が無いときは、バンドルの
初期設定（素材8枚）で動きます。

## macOS 14以降の既知の問題への対策

スクリーンセーバーを終了しても `stopAnimation` が呼ばれず、
処理が裏に残り続ける問題があります。分散通知
`com.apple.screensaver.willstop` を受けたら、そのビューの実例を
無力化し（再び描画を始めない）、`WKWebView` を片付けます。
`stopAnimation` は設定画面のプレビュー用に残してあります。
プロセスごと終了させる方法（`exit`）は、すぐに再起動したときに
黒画面になる競合が報告されているため使いません。
