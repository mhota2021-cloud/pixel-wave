# Pixel Waveの引き継ぎ（Claude CodeからAntigravityへ、2026-11-09）

Claudeの枠が少ないので、ここからはAntigravity（agy）で進める。全体のルール（CLAUDE.mdとskill）は同じものが読まれる。このファイルには、このプロジェクトの今の状態と、作業で分かったことだけを書く。

## 何を作っているか

名画8枚をドット絵にし、画面の外周のランダムな点から広がる同心円の波で、次の絵へ切り替えるソフト「Pixel Wave」。壁紙とスクリーンセーバーとして使う。基礎プログラミング第6回の自由課題（美しいと思う絵を生成する）から始まった。

- Windows版：Ruby（`win-ruby/`）。描画をGosuからGDIに替える作業を、Museに頼むところ。
- macOS版とLinux版：Tauri（`app/`）と、TypeScriptの描画エンジン（`engine/`）。
- 実装はMuse（別のAI）が行い、こちらは受け取った物を確かめて直す。Museへの頼み方は`PROMPTS.md`の章ごとに書く。

## フォルダ

| 場所 | 中身 |
| --- | --- |
| `assets/paintings/` | 名画8枚と`credits.json`（全体でここだけ。ほかに写しを作らない） |
| `kadai/` | 課題版。`kadai6b.rb`（提出する絵を作る）、`convert.rb`（名画をドット絵のデータにする） |
| `engine/` | TypeScriptの描画エンジン。値の手本（12px・隙間2px・14秒・10秒・イージング） |
| `app/` | Tauriアプリ（macOS・Linux版。Windowsのビルドは使わない） |
| `win-ruby/` | Ruby版のWindows版 |
| `.github/workflows/` | 3つのOS向けのビルドと配布 |
| `PROMPTS.md` | Museへの頼み方。1～7章。今は7章（描画をGDIに替える）を渡すところ |
| `TODO.md` | あとでやること |
| `muse/`・`muse2/` | Museから届いたZIPの中身（元の形のまま。取り込んだ後の正は上のフォルダ） |
| `preview/` | 動きを確かめる試作のページ（`http://localhost:8123/preview/`） |

gitの管理はまだしていない。

## 今の状態

### 済んだこと
- 名画8枚を決めた：神奈川沖浪裏（北斎）、星月夜（ゴッホ）、睡蓮の池と日本の橋（モネ）、民衆を導く自由の女神（ドラクロワ）、アダムの創造（ミケランジェロ）、ヴィーナスの誕生（ボッティチェリ）、叫び（ムンク）、真珠の耳飾りの少女（フェルメール）。どれも作者の死後70年を過ぎ、Wikimedia Commonsのパブリックドメイン。出典は`credits.json`。
- 課題のレポート：`H:\マイドライブ\大学\基礎プログラミング\#06\提出\`に`assignment06.tex`・`.pdf`・`mypicture.eps`・`t.ppm`がある。未提出。日付・考察・アンケートは本人が直す。
- Ruby版のWindows版：設定画面が動き、Rubyで計算した波でプレビューが切り替わる。単体テスト26件が通る（`cd win-ruby; ruby -Ilib -Itest test\test_dotart.rb`など、4ファイル）。
- 壁紙：Ruby版のウィンドウが、デスクトップのアイコンの後ろに見えるようになった（下の「分かったこと」の24H2の方法）。

### 残っていること（上から順に）
1. **Museに`PROMPTS.md`の7章を渡し、描画をGDIに替えてもらう。** 届いたら下の「受け取った物の確かめ方」で確かめる。
2. Ruby版で直したが、GDIに替えると消える問題（Museの7章に書いた）：壁紙が1280×720に縮む、ドット絵が出ない（最初の全部描く指示が無い）、古いタイトルバーが残る、設定画面がCPUを1コアの約30%使い続ける、文字が11px前後で小さい。
3. `wallpaper.pid`が、`--wallpaper`で直接起動したときに新しいプロセスの番号に変わらなかった。「壁紙を止める」で止まるか確かめる。
4. スクリーンセーバー（`/s`）、二重起動の防止、全画面のアプリと電池で止まるか、元の壁紙に戻るか、をまだ確かめていない。
5. レポートの構想の段落は「描画はTypeScript、OSに組み込む部分はRust」と書いてある。Windows版がRubyになったので、GDIの版が動いたら書き直す（下の「レポートを直すとき」）。
6. `TODO.md`の残り：普通の画像モード（アプリ版だけ）、`devicePixelRatio`への対応、縦長の絵の切り抜き位置の確認。
7. 配布：GitHubのリポジトリを作り、タグでReleasesに置く。まだリポジトリが無い。作る前にユーザーに確かめる（公開・非公開、名前）。

## 受け取った物の確かめ方

Museの報告は、そのまま信じない。これまでに次の食い違いがあった。

- 「出力が1バイトも変わらない」と頼んだのに、乱数の種・書き出しの形・平均の丸め方・k-meansの計算が変わっていた。
- パスを`:`で区切り、`C:\...`のパスで壊れる不具合を入れた。
- `[x].ceil`のように、丸括弧の所を角括弧にして起動時に落ちた。
- Windowsの`long`（32ビット）でハンドルを受け渡し、壁紙が貼れなかった。

毎回、次を行う。
1. ZIPを`muse3/`のような新しいフォルダに展開し、`diff`で今の版と比べてから取り込む。
2. `kadai`で`ruby -w convert.rb ..\assets\paintings\hokusai_great_wave.jpg ..\assets\paintings\vangogh_starry_night.jpg`を実行し、`paintings.rb.txt`が取り込む前と1バイトも変わらないことを`cmp`で確かめる（変わると課題の絵とレポートが変わる）。
3. 単体テストを全部実行する。
4. 実際に起動して、画面を撮って見る。`PrintWindow`（フラグ2）でウィンドウだけを撮れる。デスクトップの壁紙は撮れないので、ユーザーに見てもらう。

## 分かったこと

- **Windows 11 26H2のデスクトップ**：ProgmanがWS_EX_NOREDIRECTIONBITMAP（0x200000）を持ち、子にSHELLDLL_DefViewとWorkerWがある。WorkerWの子にしたウィンドウは見えない。Progmanの直接の子にし、SHELLDLL_DefViewのすぐ奥に置き、レイヤード（不透明度255）にすると見えた。レイヤードの設定は、ウィンドウを持つプロセスの中からしかできなかった（PowerShellから外部で行うと失敗した）。
- **Tauri版の壁紙が応答なしになる件**：Windowsで同期のコマンドの中からウィンドウを作るとデッドロックするので`async`にしたが、それでも応答なしになった。原因は未解決（上の24H2の構造を見つけられていない可能性が高い）。Windows版はRubyに替えたので、追わずに置いている。
- **Gosuの日本語**：フォントは名前ではなくファイルの場所（`C:/Windows/Fonts/YuGothM.ttc`）で指定しないと、日本語の無いArialになる。
- **Ruby版の準備**：RubyInstallerに付いているMSYS2の鍵が無効だった。`C:\Ruby34-x64\msys64\usr\bin\bash.exe -lc "pacman-key --init && pacman-key --populate msys2"`で直し、`pacman -S mingw-w64-ucrt-x86_64-libffi mingw-w64-ucrt-x86_64-SDL2`を入れた。gemは`win-ruby\vendor\bundle`にある（`bundle install`済み）。
- **確認用のPowerShell**：`FindWindowW`をP/Invokeで呼ぶときは`CharSet=CharSet.Unicode`を付け、名前の引数は`$null`ではなく`[NullString]::Value`か`string n`を`null`で渡す。付けないとProgmanが見つからない。
- **Commonsの画像**：短時間に何度も問い合わせると`429 Too Many Requests`になる。
- **名画の選び方**：ドット絵（16色）にした後の明暗の幅と彩度を測って選んだ。測る道具は`%TEMP%\claude-pw\sheet.py`（一覧画像を作る）。

## レポートを直すとき

- 先に`/school-writing`の「授業ごとの指定」（基礎プログラミング）と`writing/checklist.md`を読む。コードにコメントを書かない、授業で出た構文だけ、メソッド名は教科書の付け方、の決まりがある。
- 本文の元は`%LOCALAPPDATA%\Temp\claude\…\scratchpad\assignment06_body.tex`にあったが、一時フォルダなので消えている可能性がある。そのときは提出フォルダの`assignment06.tex`を直接直す。
- コンパイルは提出フォルダで`platex -kanji=utf8 assignment06.tex`と`dvipdfmx assignment06.dvi`。`\verb`は途中で改行できないので、長い`\verb`は本文に入れない。
- ドライブのファイルを変えたら、Notionの「🗂️ ドライブ目録」の基礎プログラミングの節を直す。

## Claudeに戻すこと

ブラウザの操作、Claudeの定期タスク、Artifactは、Claudeの枠が戻ってから行う。
