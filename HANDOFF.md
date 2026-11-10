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
3. 済み（2026-11-10）：壁紙のプロセスが起動時に自分の番号を`wallpaper.pid`に書くので、ショートカットやインストーラー版の外側のexeから起動しても「壁紙を止める」で止まる。
4. スクリーンセーバー（`/s`）、二重起動の防止、全画面のアプリと電池で止まるか、をまだ確かめていない。
8. **別のPCで試す。** 1つのexeに詰めた版は、相手のPCで「壁紙にする」を押したときにDefenderに消された。次の3つを直し、このPCでは設定画面のボタン操作まで通して確かめた（2026-11-10）。相手のPCでインストーラー版（`win-ruby\Output\PixelWaveSetup.exe`）を試す。
   - 配布をInno Setupのインストーラーにし、`%TEMP%`に展開して実行する動きを無くした。
   - 「壁紙にする」でWindowsの壁紙を書き換えない。古い版が残した`original_wallpaper.json`があれば、「止める」で元に戻す。
   - ログイン時の起動は、設定画面の切り替え（初期値はオフ）でスタートアップのショートカットを置く。Runキーは使わない。
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

- **Windows 11 26H2のデスクトップ**：ProgmanがWS_EX_NOREDIRECTIONBITMAP（0x200000）を持ち、子にSHELLDLL_DefView（アイコン）とWorkerW（写真の壁紙）がある。動く手順は`Platform.attach_wallpaper`の順番どおりで、順番を変えると見えなくなる（2026-11-09にデスクトップを撮って確認）。
  1. 自ウィンドウを`WS_CHILD`にして`SetParent(hwnd, progman)`。
  2. 子になった**後で**`WS_EX_LAYERED`と`SetLayeredWindowAttributes(255)`を付ける。
  3. `SetWindowPos(hwnd, defview, …)`でアイコンのすぐ奥に置く。
  4. `SetWindowPos(workerw, hwnd, …, SWP_NOMOVE|SWP_NOSIZE)`でWorkerWを自ウィンドウの奥へ移す。これが無いと写真が手前に来てドット絵が隠れる。
- うまくいかなかった構成：WorkerWの子にする（写真しか出ない）、WorkerWを`SW_HIDE`する（写真も消える）、レイヤードにしない（Progmanの下ではGDIの絵が届かない）。`ruby.exe`のマニフェストにWindows 8以降の互換宣言が無いのも疑ったが、宣言を足した写しと元の`ruby.exe`の両方で同じように映ったので関係ない。
- レイヤードの設定は、ウィンドウを持つプロセスの中からしかできなかった（PowerShellから外部で行うと失敗した）。
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

## Antigravityでの作業履歴と失敗の記録（Claudeへの引き継ぎ、2026-11-09）

### 完了したこと
1. **壁紙のバックアップと復元**（コミット `e5bb4c1`）
   - 壁紙開始時に `%APPDATA%\PixelWave\original_wallpaper.json` へ元設定（壁紙パス、スタイル、背景色）を保存。
   - 壁紙停止時に単色黒（背景色反映＋空文字）または画像壁紙を正確に復元。
2. **バッテリー駆動停止ガードの解除トグル**（コミット `f79c4cb`）
   - ノートPCのバッテリー駆動時に起動2秒で描画タイマー（`TIMER_TICK`）が強制停止していた原因を突き止め、設定画面に「バッテリー時：一時停止／常に動かす」トグルを追加。
   - 設定ファイル `%APPDATA%\PixelWave\settings.json` の `"pauseOnBattery": false` で常時描画可能。
3. **単体テスト全35件通過**（`ruby -Ilib -e 'Dir.glob("test/test_*.rb").each { |f| load f }'`）。

### Windows 11 24H2の動的壁紙で試してうまくいかなかったことと判明した事実

#### 失敗1: Progman直下・DefView奥・レイヤード（不透明度255）配置
- **現象**: 写真は出るが、ドット絵アニメーションが一切見えない。
- **調査結果**: `wallpaper_debug.log` では `msg=0xf`（`WM_PAINT`）が毎フレーム発行され続けており、タイマーとGDI描画自体は正常に動き続けていた。
- **原因**: Windows 11 24H2ではProgman直下に `SHELLDLL_DefView`（アイコン）と `WorkerW`（壁紙写真を描画するレイヤー）の2つが存在する。Progmanの子に配置すると、自ウィンドウと `WorkerW` が兄弟ウィンドウになるが、Z-order上で写真壁紙を描く `WorkerW` が手前に来るため、背後にある自ウィンドウの描画が写真で完全に覆い隠されていた。

#### 失敗2: 競合WorkerWの非表示化＋非レイヤード通常GDI子ウィンドウ化
- **現象**: 写真すら消え、ドット絵も出ない（完全に未描画／真っ黒）。
- **原因**:
  1. `WorkerW` はWindows Explorerが壁紙写真を描画しているレイヤーそのものだったため、`ShowWindow(workerw, 0)` で非表示にするとOS側の写真描画が消えた。
  2. Windows 11 24H2の `Progman` はトップレベルで `WS_EX_NOREDIRECTIONBITMAP` を持っている。この属性を持つウィンドウ配下の通常GDI子ウィンドウ（非レイヤード）には、DWMが描画リダイレクションバッファを割り当てない。そのため、GDI（`BitBlt`）で描画してもDWMの画面合成パイプラインに届かず、完全に透明（画面に一切現れない状態）になった。

#### 失敗3: WorkerWの子にする（コミットa556f16）
- 写真しか出なかった（Claude Codeで撮って確認）。

#### 解決（Claude Code、2026-11-09）
- 「分かったこと」の26H2の手順に直し、アイコンの後ろでドット絵が動き、次の絵へ波で切り替わることを撮って確かめた。失敗1との差は、レイヤードを付ける順番と、WorkerWを奥へ移す手順である。
- `display_window.rb`の、全メッセージを`wallpaper_debug.log`に書く調査用の行を消した。
