//エンジン本体のビルド設定（アプリから読み込むESモジュールをdist/engine.jsに1ファイルで出す）
import { defineConfig } from "vite";

export default defineConfig({
  build: {
    lib: {
      entry: "src/engine.ts",
      formats: ["es"],
      fileName: () => "engine.js",
    },
    outDir: "dist",
    emptyOutDir: true,
    sourcemap: false,
  },
});
