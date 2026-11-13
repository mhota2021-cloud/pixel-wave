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
  title_en?: string;
  artist: string;
  artist_en?: string;
  year?: string;
  year_en?: string;
  source?: string;
  crop?: Painting["crop"];
}

type Lang = "ja" | "en";

const MESSAGES = {
  ja: {
    addImage: "画像を追加",
    deleteImage: "削除",
    setWallpaper: "壁紙にする",
    stopWallpaper: "壁紙を止める",
    viewFullscreen: "全画面で表示",
    stopDisplay: "表示を止める",
    setScreensaver: "スクリーンセーバーにする",
    credits: "出典",
    sourceLink: "出典",
    imageFilter: "画像",
    langToggle: "English",
    wallpaperStartError: (err: string) => `壁紙を始められませんでした：${err}`,
    wallpaperStopError: (err: string) => `壁紙を止められませんでした：${err}`,
    saverError: "スクリーンセーバーとして登録できませんでした",
  },
  en: {
    addImage: "Add Image",
    deleteImage: "Delete",
    setWallpaper: "Set as Wallpaper",
    stopWallpaper: "Stop Wallpaper",
    viewFullscreen: "View Fullscreen",
    stopDisplay: "Stop Display",
    setScreensaver: "Set as Screensaver",
    credits: "Credits",
    sourceLink: "Source",
    imageFilter: "Images",
    langToggle: "日本語",
    wallpaperStartError: (err: string) => `Failed to start wallpaper: ${err}`,
    wallpaperStopError: (err: string) => `Failed to stop wallpaper: ${err}`,
    saverError: "Failed to register as screensaver",
  },
} as const;

const LANG_KEY = "pixel_wave_lang";

function detectInitialLang(): Lang {
  const fromUrl = new URLSearchParams(window.location.search).get("lang");
  if (fromUrl === "ja" || fromUrl === "en") return fromUrl;
  try {
    const saved = window.localStorage.getItem(LANG_KEY);
    if (saved === "ja" || saved === "en") return saved;
  } catch {
    //ignore
  }
  return navigator.language.toLowerCase().startsWith("ja") ? "ja" : "en";
}

let currentLang: Lang = detectInitialLang();

function msg(): (typeof MESSAGES)[Lang] {
  return MESSAGES[currentLang];
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
    title: currentLang === "en" && c.title_en ? c.title_en : c.title,
    artist: currentLang === "en" && c.artist_en ? c.artist_en : c.artist,
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
      del.setAttribute("aria-label", msg().deleteImage);
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
    wallpaperButton.textContent = settings.wallpaper ? msg().stopWallpaper : msg().setWallpaper;
  }
  const fullscreenButton = document.getElementById("fullscreenButton");
  if (fullscreenButton) {
    fullscreenButton.textContent = settings.wallpaper ? msg().stopDisplay : msg().viewFullscreen;
  }
}

//出典一覧を現在の言語で描き直す
function renderCredits(): void {
  const creditsPanel = document.getElementById("creditsPanel");
  if (!creditsPanel) return;
  creditsPanel.textContent = "";
  for (const c of creditList) {
    const line = document.createElement("p");
    line.className = "creditLine";
    const head = document.createElement("span");
    const title = currentLang === "en" && c.title_en ? c.title_en : c.title;
    const artist = currentLang === "en" && c.artist_en ? c.artist_en : c.artist;
    const year = currentLang === "en" && c.year_en ? c.year_en : c.year;
    if (currentLang === "en") {
      head.textContent = year ? `${title} (${artist}, ${year})` : `${title} (${artist})`;
    } else {
      head.textContent = year ? `${title}（${artist}、${year}）` : `${title}（${artist}）`;
    }
    line.appendChild(head);
    if (c.source) {
      const link = document.createElement("a");
      link.href = c.source;
      link.textContent = msg().sourceLink;
      link.target = "_blank";
      link.rel = "noreferrer";
      line.appendChild(document.createTextNode(currentLang === "en" ? " " : "　"));
      line.appendChild(link);
    }
    creditsPanel.appendChild(line);
  }
}

//固定ボタン類と言語属性を現在の言語へ合わせる
function applyLanguage(): void {
  document.documentElement.lang = currentLang;
  const addButton = document.getElementById("addButton");
  addButton?.setAttribute("aria-label", msg().addImage);
  const saverButton = document.getElementById("saverButton");
  if (saverButton) saverButton.textContent = msg().setScreensaver;
  const creditsButton = document.getElementById("creditsButton");
  if (creditsButton) creditsButton.textContent = msg().credits;
  const langButton = document.getElementById("langButton");
  if (langButton) langButton.textContent = msg().langToggle;
  renderCredits();
  render();
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
  applyLanguage();

  const addButton = document.getElementById("addButton");
  const fileInput = document.getElementById("fileInput") as HTMLInputElement | null;
  addButton?.addEventListener("click", async () => {
    if (isTauri()) {
      const selected = await open({
        multiple: true,
        filters: [{ name: msg().imageFilter, extensions: ["jpg", "jpeg", "png", "webp"] }],
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
      const errText = target ? msg().wallpaperStartError(String(e)) : msg().wallpaperStopError(String(e));
      window.alert(errText);
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
      window.alert(msg().saverError);
    }
  });

  //出典パネルの開閉と言語切り替えボタン
  const creditsPanel = document.getElementById("creditsPanel");
  const creditsButton = document.getElementById("creditsButton");
  creditsButton?.addEventListener("click", () => {
    if (creditsPanel) {
      creditsPanel.hidden = !creditsPanel.hidden;
    }
  });
  const langButton = document.getElementById("langButton");
  langButton?.addEventListener("click", () => {
    currentLang = currentLang === "ja" ? "en" : "ja";
    try {
      window.localStorage.setItem(LANG_KEY, currentLang);
    } catch {
      //ignore
    }
    applyLanguage();
  });
}

void main();
