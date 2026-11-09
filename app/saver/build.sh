#!/bin/sh
#PixelWaveSaver.saverを組み立てる（Xcodeを使わずswiftcだけで作り、アドホック署名する）
set -e
cd "$(dirname "$0")"

OUT="dist/PixelWaveSaver.saver"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources/web/images"
cp Info.plist "$OUT/Contents/Info.plist"

#Webの中身をResourcesへ写す（セーバー用ページ、エンジン、素材の絵、初期設定）
cp ../saver-web/saver.html "$OUT/Contents/Resources/web/saver.html"
if [ ! -f ../../engine/dist/engine.js ]; then
  (cd ../../engine && npm run build)
fi
cp ../../engine/dist/engine.js "$OUT/Contents/Resources/web/engine.js"
cp ../../assets/paintings/*.jpg "$OUT/Contents/Resources/web/images/"
python3 -c "import json; c = json.load(open('../../assets/paintings/credits.json')); json.dump({'paintings': [{'src': 'images/' + p['file'], 'crop': p.get('crop', 'center')} for p in c]}, open('$OUT/Contents/Resources/web/default-settings.json', 'w'), ensure_ascii=False)"

#Swiftを2つのアーキテクチャでコンパイルし、ユニバーサルバイナリにする
for arch in arm64 x86_64; do
  swiftc -O \
    -target "$arch-apple-macos11.0" \
    -module-name PixelWaveSaver \
    -emit-library \
    -Xlinker -bundle \
    -framework ScreenSaver \
    -framework WebKit \
    -framework AppKit \
    -o "dist/PixelWaveSaver-$arch" \
    Sources/*.swift
done
lipo -create "dist/PixelWaveSaver-arm64" "dist/PixelWaveSaver-x86_64" \
  -output "$OUT/Contents/MacOS/PixelWaveSaver"
rm "dist/PixelWaveSaver-arm64" "dist/PixelWaveSaver-x86_64"

#アドホック署名（お金のかかる署名はしない）
codesign --force --deep -s - "$OUT"
echo "built: $OUT"
