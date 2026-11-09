//表示画面の動き（壁紙とスクリーンセーバーと全画面で共通、エンジンを画面全体に表示する）
import { listen } from "@tauri-apps/api/event";
import { createEngine } from "../../engine/src/engine";
import type { Painting } from "../../engine/src/engine";
import credits from "../../assets/paintings/credits.json";
import { exitApp, getDataDir, getMode, getSettings, isTauri, stopFullscreen, userImageSrc } from "./tauri";

//素材の情報（credits.jsonの1件分）
interface Credit {
  id: string;
  file: string;
  crop?: Painting["crop"];
}

const creditList = credits as Credit[];

//入口
async function main(): Promise<void> {
  const canvas = document.getElementById("screen") as HTMLCanvasElement | null;
  if (!canvas) return;
  const mode = await getMode();
  const settings = await getSettings();
  const dataDir = await getDataDir();

  const paintings: Painting[] = [];
  for (const c of creditList) {
    if (settings.enabled.includes(c.id)) {
      paintings.push({ id: c.id, src: `assets/paintings/${c.file}`, crop: c.crop });
    }
  }
  for (const user of settings.userImages) {
    if (settings.enabled.includes(user.id)) {
      paintings.push({ id: user.id, src: userImageSrc(dataDir, user.file), crop: "center" });
    }
  }

  const engine = createEngine(canvas, paintings);
  engine.start();

  //電源の状態で止めたり再開したりする（Rust側からの通知）
  if (isTauri()) {
    await listen<boolean>("pixelwave-power", (event) => {
      if (event.payload) {
        engine.stop();
      } else {
        engine.start();
      }
    });
  }

  //入力で終わる処理（スクリーンセーバーはアプリごと終了し、全画面表示は表示だけを閉じる）
  const finish = mode === "screensaver" ? exitApp : mode === "fullscreen" ? stopFullscreen : null;
  if (finish) {
    let originX: number | null = null;
    let originY: number | null = null;
    window.addEventListener("mousemove", (e) => {
      //数ピクセルの揺れは無視する（スクリーンセーバー用、全画面表示でも同じ扱いにする）
      if (mode !== "screensaver") {
        return;
      }
      if (originX === null || originY === null) {
        originX = e.clientX;
        originY = e.clientY;
        return;
      }
      const dx = e.clientX - originX;
      const dy = e.clientY - originY;
      if (dx * dx + dy * dy > 25) {
        void finish();
      }
    });
    window.addEventListener("mousedown", () => {
      void finish();
    });
    window.addEventListener("keydown", () => {
      void finish();
    });
  }
}

void main();
