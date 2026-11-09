#!/bin/sh
#macOS版をまとめてビルドする（エンジン、セーバー、アプリのユニバーサルバイナリ、同梱DMGの順）
set -e
cd "$(dirname "$0")/.."

#描画エンジンとセーバーを先に作る（アプリはセーバーを資源として取り込むため）
(cd ../engine && npm install && npm run build)
(cd saver && ./build.sh)

#ユニバーサルバイナリに必要なRustのターゲットを入れる
rustup target add aarch64-apple-darwin x86_64-apple-darwin

npm install
npx tauri build --target universal-apple-darwin --bundles app

#アプリとセーバーを入れたDMGを作る（Tauri標準のDMGはアプリだけなので、配布用はこちらを使う）
STAGE=$(mktemp -d)
cp -R "src-tauri/target/universal-apple-darwin/release/bundle/macos/Pixel Wave.app" "$STAGE/"
cp -R saver/dist/PixelWaveSaver.saver "$STAGE/"
cp scripts/使い方-macOS.txt "$STAGE/使い方.txt"
hdiutil create -volname "Pixel Wave" -srcfolder "$STAGE" -ov -format UDZO "PixelWave-macOS.dmg"
rm -rf "$STAGE"
echo "built: PixelWave-macOS.dmg"
