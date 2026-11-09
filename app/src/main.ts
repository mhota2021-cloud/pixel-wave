//設定画面の動き（プレビューと絵の一覧とボタン、OSでボタンの出し分けをする）
import { open } from "@tauri-apps/plugin-dialog";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";
import { listen } from "@tauri-apps/api/event";
import { createEngine } from "../../engine/src/engine";
import type { Painting } from "../../engine/src/engine";
import credits from "../../assets/paintings/credits.json";
import {
  addUserImage,
  getDataDir,
  getPlatform,
  getSettings,
  isTauri,
  registerScreensaver,
  removeUserImage,
  saveSettings,
  setMockSettings,
  setWallpaper,
  userImageSrc,
} from "./tauri";
import type { SettingsData } from "./tauri";
import "./style.css";

//素材の情報（credits.jsonの1件分）
interface Credit {
  id: string;
  file: string;
  title: string;
  artist: string;
  year?: string;
  source?: string;
  crop?: Painting["crop"];
}

const creditList = credits as Credit[];

//一覧の1件分（builtinは素材かどうか、srcは表示用URL）
interface ListItem {
  id: string;
  title: string;
  artist: string;
  thumbSrc: string;
  painting: Painting;
  builtin: boolean;
}

let settings: SettingsData = {
  enabled: creditList.map((c) => c.id),
  userImages: [],
  wallpaper: false,
};
let dataDir = "";
let engine: ReturnType<typeof createEngine> | null = null;

//一覧を作る
function buildItems(): ListItem[] {
  const items: ListItem[] = creditList.map((c) => ({
    id: c.id,
    title: c.title,
    artist: c.artist,
    thumbSrc: `assets/paintings/${c.file}`,
    painting: { id: c.id, src: `assets/paintings/${c.file}`, crop: c.crop },
    builtin: true,
  }));
  for (const user of settings.userImages) {
    const src = userImageSrc(dataDir, user.file);
    items.push({
      id: user.id,
      title: user.title,
      artist: "",
      thumbSrc: src,
      painting: { id: user.id, src, crop: "center" },
      builtin: false,
    });
  }
  return items;
}

//選ばれている絵だけをエンジン用に返す
function selectedPaintings(): Painting[] {
  return buildItems()
    .filter((item) => settings.enabled.includes(item.id))
    .map((item) => item.painting);
}

//プレビューへ反映する
function refreshPreview(): void {
  if (engine) {
    engine.setPaintings(selectedPaintings());
  }
}

//設定を保存して画面へ反映する
async function persist(): Promise<void> {
  await saveSettings(settings);
  render();
  refreshPreview();
}

//一覧とボタンを描き直す
function render(): void {
  const grid = document.getElementById("grid");
  if (!grid) return;
  grid.textContent = "";
  const onlyOne = settings.enabled.length <= 1;
  for (const item of buildItems()) {
    const card = document.createElement("div");
    card.className = "card";

    const wrap = document.createElement("div");
    wrap.className = "thumbWrap";
    const img = document.createElement("img");
    img.src = item.thumbSrc;
    img.alt = item.title;
    wrap.appendChild(img);

    const check = document.createElement("input");
    check.type = "checkbox";
    check.className = "check";
    check.checked = settings.enabled.includes(item.id);
    check.setAttribute("aria-label", item.title);
    if (check.checked && onlyOne) {
      check.disabled = true;
    }
    check.addEventListener("change", () => {
      if (check.checked) {
        if (!settings.enabled.includes(item.id)) {
          settings.enabled.push(item.id);
        }
      } else {
        if (settings.enabled.length <= 1) {
          check.checked = true;
          return;
        }
        settings.enabled = settings.enabled.filter((id) => id !== item.id);
      }
      void persist();
    });
    wrap.appendChild(check);

    if (!item.builtin) {
      const del = document.createElement("button");
      del.type = "button";
      del.className = "deleteButton";
      del.textContent = "×";
      del.setAttribute("aria-label", "削除");
      del.addEventListener("click", async () => {
        if (isTauri()) {
          await removeUserImage(item.id);
          settings = await getSettings();
        } else {
          settings.userImages = settings.userImages.filter((u) => u.id !== item.id);
          settings.enabled = settings.enabled.filter((id) => id !== item.id);
          if (settings.enabled.length === 0 && buildItems().length > 1) {
            settings.enabled = [buildItems()[0].id];
          }
        }
        await persist();
      });
      wrap.appendChild(del);
    }
    card.appendChild(wrap);

    const caption = document.createElement("div");
    caption.className = "caption";
    const title = document.createElement("span");
    title.className = "title";
    title.textContent = item.title;
    caption.appendChild(title);
    if (item.artist) {
      const artist = document.createElement("span");
      artist.className = "artist";
      artist.textContent = item.artist;
      caption.appendChild(artist);
    }
    card.appendChild(caption);
    grid.appendChild(card);
  }

  const wallpaperButton = document.getElementById("wallpaperButton");
  if (wallpaperButton) {
    wallpaperButton.textContent = settings.wallpaper ? "壁紙を止める" : "壁紙にする";
  }
  const fullscreenButton = document.getElementById("fullscreenButton");
  if (fullscreenButton) {
    fullscreenButton.textContent = settings.wallpaper ? "表示を止める" : "全画面で表示";
  }
}

//画像を追加する（引数pathsは元の画像の場所の一覧）
async function addImages(paths: string[]): Promise<void> {
  for (const path of paths) {
    await addUserImage(path);
  }
  settings = await getSettings();
  await persist();
}

//入口
async function main(): Promise<void> {
  setMockSettings(settings);
  dataDir = await getDataDir();
  settings = await getSettings();
  if (settings.enabled.length === 0) {
    settings.enabled = creditList.map((c) => c.id);
  }

  const canvas = document.getElementById("previewCanvas") as HTMLCanvasElement | null;
  if (canvas) {
    engine = createEngine(canvas, selectedPaintings());
    engine.start();
  }
  render();

  const addButton = document.getElementById("addButton");
  const fileInput = document.getElementById("fileInput") as HTMLInputElement | null;
  addButton?.addEventListener("click", async () => {
    if (isTauri()) {
      const selected = await open({
        multiple: true,
        filters: [{ name: "画像", extensions: ["jpg", "jpeg", "png", "webp"] }],
      });
      if (!selected) return;
      const paths = Array.isArray(selected) ? selected : [selected];
      await addImages(paths);
    } else {
      fileInput?.click();
    }
  });
  fileInput?.addEventListener("change", () => {
    const files = fileInput.files;
    if (!files) return;
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const id = `user_${Date.now().toString(36)}_${i}`;
      settings.userImages.push({
        id,
        file: URL.createObjectURL(file),
        title: file.name.replace(/\.[^.]*$/, ""),
      });
      settings.enabled.push(id);
    }
    void persist();
  });

  if (isTauri()) {
    const webview = getCurrentWebviewWindow();
    await webview.onDragDropEvent(async (event) => {
      if (event.payload.type === "drop" && event.payload.paths.length > 0) {
        await addImages(event.payload.paths);
      }
    });
  }

  const toggleDisplay = async (): Promise<void> => {
    const target = !settings.wallpaper;
    try {
      await setWallpaper(target);
    } catch (e) {
      //失敗を握りつぶすと、押しても何も起きないように見えるので知らせる
      console.error("壁紙の切り替えに失敗した:", e);
      window.alert(`壁紙を${target ? "始め" : "止め"}られませんでした：${String(e)}`);
    }
    settings = await getSettings();
    render();
  };
  const wallpaperButton = document.getElementById("wallpaperButton");
  wallpaperButton?.addEventListener("click", () => {
    void toggleDisplay();
  });
  const fullscreenButton = document.getElementById("fullscreenButton");
  fullscreenButton?.addEventListener("click", () => {
    void toggleDisplay();
  });

  //Linuxでは壁紙とスクリーンセーバーのボタンを隠し、全画面表示のボタンだけにする
  const platform = await getPlatform();
  if (platform === "linux") {
    if (wallpaperButton) wallpaperButton.hidden = true;
    const saverButtonElement = document.getElementById("saverButton");
    if (saverButtonElement) saverButtonElement.hidden = true;
    if (fullscreenButton) fullscreenButton.hidden = false;
  }

  //表示側の操作（全画面表示の終了など）で状態が変わったらボタンの表示を合わせる
  if (isTauri()) {
    await listen<boolean>("pixelwave-wallpaper", (event) => {
      settings.wallpaper = event.payload;
      render();
    });
  }

  const saverButton = document.getElementById("saverButton");
  saverButton?.addEventListener("click", async () => {
    try {
      await registerScreensaver();
      settings = await getSettings();
    } catch {
      window.alert("スクリーンセーバーとして登録できませんでした");
    }
  });

  //出典の一覧を作り、押すたびに開閉する
  const creditsPanel = document.getElementById("creditsPanel");
  if (creditsPanel) {
    for (const c of creditList) {
      const line = document.createElement("p");
      line.className = "creditLine";
      const head = document.createElement("span");
      head.textContent = c.year ? `${c.title}（${c.artist}、${c.year}）` : `${c.title}（${c.artist}）`;
      line.appendChild(head);
      if (c.source) {
        const link = document.createElement("a");
        link.href = c.source;
        link.textContent = "出典";
        link.target = "_blank";
        link.rel = "noreferrer";
        line.appendChild(document.createTextNode("　"));
        line.appendChild(link);
      }
      creditsPanel.appendChild(line);
    }
  }
  const creditsButton = document.getElementById("creditsButton");
  creditsButton?.addEventListener("click", () => {
    if (creditsPanel) {
      creditsPanel.hidden = !creditsPanel.hidden;
    }
  });
}

void main();
