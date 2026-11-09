//アプリの画面のビルド設定（設定画面と表示画面の2つの入口を持ち、素材の画像を配信する）
import { cpSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import type { Plugin } from "vite";

const rootDir = path.dirname(fileURLToPath(import.meta.url));
//素材は全体で1か所（pixel-wave/assets/paintings）に置く
const paintingsDir = path.join(rootDir, "..", "assets", "paintings");

//素材を開発サーバーで配信し、ビルド先にも写す（プラグイン名はserve-paintings）
function servePaintings(): Plugin {
  return {
    name: "serve-paintings",
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const url = req.url ?? "";
        const prefix = "/assets/paintings/";
        if (!url.startsWith(prefix)) {
          next();
          return;
        }
        const name = path.basename(decodeURIComponent(url.slice(prefix.length)));
        try {
          const data = readFileSync(path.join(paintingsDir, name));
          res.setHeader(
            "Content-Type",
            name.endsWith(".json") ? "application/json" : "image/jpeg",
          );
          res.end(data);
        } catch {
          next();
        }
      });
    },
    writeBundle(options) {
      const outDir = options.dir ?? path.join(rootDir, "dist");
      cpSync(paintingsDir, path.join(outDir, "assets", "paintings"), {
        recursive: true,
      });
    },
  };
}

export default defineConfig({
  plugins: [servePaintings()],
  server: {
    port: 5174,
    strictPort: true,
    //エンジン（../engine）と素材（../assets）を読み込めるようにする
    fs: { allow: [path.join(rootDir, "..")] },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        index: path.join(rootDir, "index.html"),
        display: path.join(rootDir, "display.html"),
      },
    },
  },
});
