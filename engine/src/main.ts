//確認用ページの入口（画面全体にエンジンを表示し、URLの引数か素材一覧から絵を決める）
import { createEngine } from "./engine";
import type { Painting } from "./engine";

//予備の絵の一覧（素材一覧が読めなかったときに使う）
const FALLBACK_FILES = [
  "hokusai_great_wave.jpg",
  "vangogh_starry_night.jpg",
  "monet_impression_sunrise.jpg",
  "klimt_the_kiss.jpg",
  "velazquez_las_meninas.jpg",
  "botticelli_birth_of_venus.jpg",
  "munch_the_scream.jpg",
  "vermeer_girl_with_a_pearl_earring.jpg",
];

//ファイル名から拡張子を除いたものを識別子にする（引数fileはファイル名）
function idFromFile(file: string): string {
  const base = file.split("/").pop() ?? file;
  return base.replace(/\.[^.]*$/, "");
}

//絵の一覧を決める（URLの引数imagesがあればそれを使い、無ければ素材のcredits.jsonを読む）
async function resolvePaintings(): Promise<Painting[]> {
  const params = new URLSearchParams(window.location.search);
  const images = params.get("images");
  if (images) {
    return images
      .split(",")
      .map((src) => src.trim())
      .filter((src) => src.length > 0)
      .map((src) => ({ id: idFromFile(src), src }));
  }
  try {
    const response = await fetch("assets/paintings/credits.json");
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const credits = (await response.json()) as Array<{
      id: string;
      file: string;
      crop?: Painting["crop"];
    }>;
    return credits.map((c) => ({
      id: c.id,
      src: `assets/paintings/${c.file}`,
      crop: c.crop,
    }));
  } catch {
    return FALLBACK_FILES.map((file) => ({
      id: idFromFile(file),
      src: `assets/paintings/${file}`,
    }));
  }
}

//入口（canvasを探してエンジンを作り再生を始める）
async function main(): Promise<void> {
  const canvas = document.getElementById("screen") as HTMLCanvasElement | null;
  if (!canvas) return;
  const paintings = await resolvePaintings();
  const engine = createEngine(canvas, paintings);
  engine.start();
}

void main();
