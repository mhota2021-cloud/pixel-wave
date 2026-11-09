//描画エンジンの本体（ドット絵の表示と波による切り替えと負荷の制御）
import {
  computeCropRect,
  dotArtFromPixels,
  farthestCornerDistance,
  pickPerimeterPoint,
  shuffleOrder,
  transitionEasing,
} from "./dotart";
import type { DotArt, Painting } from "./dotart";

export type { Crop, Painting } from "./dotart";

//エンジンの操作（startは再生開始、stopは停止、setPaintingsは絵の入れ替え、destroyは破棄）
export interface Engine {
  start(): void;
  stop(): void;
  setPaintings(p: Painting[]): void;
  destroy(): void;
}

//固定の値（ドット1個は12ピクセル、塗る大きさは隙間2ピクセルを引いた分、表示は14秒、切り替えは10秒、背景色は#141418）
const DOT_SIZE = 12;
const GAP = 2;
const DISPLAY_MS = 14000;
const TRANSITION_MS = 10000;
const BG = "#141418";
const BG_RGB: [number, number, number] = [20, 20, 24];

//読み込み済みの絵（paintingは指定、imageは読み終えた画像、artは現在の画面用ドット絵）
interface LoadedPainting {
  painting: Painting;
  image: HTMLImageElement;
  art: DotArt | null;
  css: string[];
  glowCss: string[];
}

//切り替えの途中状態（distancesは各ドットの中心から中心までの距離、statesは各ドットの表示状態）
interface Transition {
  fromArt: DotArt;
  toArt: DotArt;
  cx: number;
  cy: number;
  maxRadius: number;
  distances: Float32Array;
  states: Uint8Array;
  startedAt: number;
  elapsedBefore: number;
  running: boolean;
}

//色をCSSの文字列にする（引数rとgとbは色）
function cssColor(r: number, g: number, b: number): string {
  return `rgb(${r},${g},${b})`;
}

//エンジンを作る（引数canvasは描く対象、引数paintingsは絵の一覧）
export function createEngine(canvas: HTMLCanvasElement, paintings: Painting[]): Engine {
  const context = canvas.getContext("2d");
  if (!context) {
    throw new Error("Canvas 2D context is not available");
  }
  const ctx: CanvasRenderingContext2D = context;

  let loaded: LoadedPainting[] = [];
  let loadToken = 0;
  let cols = 0;
  let rows = 0;
  let cellW = 0;
  let cellH = 0;
  let playOrder: number[] = [];
  let playPos = 0;
  let currentIndex = -1;
  let started = false;
  let suspended = false;
  let destroyed = false;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let timerStartedAt = 0;
  let timerDuration = 0;
  let timerRemaining: number | null = null;
  let rafId: number | null = null;
  let transition: Transition | null = null;

  //色番号からCSS文字列の表を作る（引数artはドット絵）
  function buildCss(art: DotArt): { css: string[]; glowCss: string[] } {
    return {
      css: art.palette.map((c) => cssColor(c[0], c[1], c[2])),
      glowCss: art.glowPalette.map((c) => cssColor(c[0], c[1], c[2])),
    };
  }

  //画像を現在の格子でドット絵に変換する（引数itemは読み込み済みの絵）
  function convert(item: LoadedPainting): void {
    if (cols <= 0 || rows <= 0) return;
    const off = document.createElement("canvas");
    off.width = cols;
    off.height = rows;
    const offCtx = off.getContext("2d");
    if (!offCtx) return;
    const rect = computeCropRect(
      item.image.naturalWidth,
      item.image.naturalHeight,
      cols / rows,
      item.painting.crop ?? "center",
    );
    offCtx.drawImage(
      item.image,
      rect.sx,
      rect.sy,
      rect.sw,
      rect.sh,
      0,
      0,
      cols,
      rows,
    );
    const imageData = offCtx.getImageData(0, 0, cols, rows);
    const raw = imageData.data;
    const flat = new Uint8ClampedArray(cols * rows * 3);
    for (let i = 0; i < cols * rows; i++) {
      const a = raw[i * 4 + 3] / 255;
      flat[i * 3] = raw[i * 4] * a + BG_RGB[0] * (1 - a);
      flat[i * 3 + 1] = raw[i * 4 + 1] * a + BG_RGB[1] * (1 - a);
      flat[i * 3 + 2] = raw[i * 4 + 2] * a + BG_RGB[2] * (1 - a);
    }
    item.art = dotArtFromPixels(flat, cols, rows, 42);
    const built = buildCss(item.art);
    item.css = built.css;
    item.glowCss = built.glowCss;
  }

  //背景色で全体を塗る
  function fillBackground(): void {
    ctx.fillStyle = BG;
    ctx.fillRect(0, 0, canvas.width, canvas.height);
  }

  //ドットを1個描く（引数itemは絵、引数indexはドットの番号、引数glowは光らせるかどうか）
  function drawDot(item: LoadedPainting, index: number, glow: boolean): void {
    if (!item.art) return;
    const col = index % cols;
    const row = Math.floor(index / cols);
    const colorIndex = item.art.indices[index];
    ctx.fillStyle = glow ? item.glowCss[colorIndex] : item.css[colorIndex];
    //マスの四隅を整数のピクセルにそろえる（端数の位置に描くと縁が半透明になり、光る輪の白が縁に残って、切り替えの後に全体の色が変わって見えるため）
    const x0 = Math.round(col * cellW);
    const y0 = Math.round(row * cellH);
    const x1 = Math.round((col + 1) * cellW);
    const y1 = Math.round((row + 1) * cellH);
    ctx.fillRect(x0 + GAP / 2, y0 + GAP / 2, x1 - x0 - GAP, y1 - y0 - GAP);
  }

  //絵を全面に描く（引数itemは絵）
  function drawAll(item: LoadedPainting): void {
    fillBackground();
    if (!item.art) return;
    for (let i = 0; i < cols * rows; i++) {
      drawDot(item, i, false);
    }
  }

  //表示タイマーを止める
  function clearDisplayTimer(): void {
    if (timer !== null) {
      clearTimeout(timer);
      timer = null;
    }
  }

  //表示タイマーを始める（引数msは次の切り替えまでの時間）
  function scheduleDisplay(ms: number): void {
    clearDisplayTimer();
    timerRemaining = null;
    if (!started || suspended || destroyed) return;
    if (loaded.length < 2 || currentIndex < 0) return;
    timerDuration = ms;
    timerStartedAt = performance.now();
    timer = setTimeout(() => {
      timer = null;
      beginTransition();
    }, ms);
  }

  //切り替えを始める
  function beginTransition(): void {
    if (loaded.length < 2 || currentIndex < 0) return;
    let nextPos = playPos + 1;
    if (nextPos >= playOrder.length) {
      playOrder = shuffleOrder(loaded.length, currentIndex, Math.random);
      nextPos = 0;
    }
    const nextIndex = playOrder[nextPos];
    const fromItem = loaded[currentIndex];
    const toItem = loaded[nextIndex];
    if (!fromItem.art || !toItem.art) return;
    playPos = nextPos;
    const center = pickPerimeterPoint(canvas.width, canvas.height, Math.random);
    const distances = new Float32Array(cols * rows);
    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < cols; col++) {
        const dx = (col + 0.5) * cellW - center.x;
        const dy = (row + 0.5) * cellH - center.y;
        distances[row * cols + col] = Math.sqrt(dx * dx + dy * dy);
      }
    }
    transition = {
      fromArt: fromItem.art,
      toArt: toItem.art,
      cx: center.x,
      cy: center.y,
      maxRadius: farthestCornerDistance(center.x, center.y, canvas.width, canvas.height),
      distances,
      states: new Uint8Array(cols * rows),
      startedAt: performance.now(),
      elapsedBefore: 0,
      running: true,
    };
    //切り替え先の番号を覚えておく（終わったときに現在の絵にする）
    pendingNextIndex = nextIndex;
    rafId = requestAnimationFrame(frame);
  }

  let pendingNextIndex = -1;

  //切り替えの各フレーム（引数nowは時刻、変わったドットと光る輪のドットだけを描き直す）
  function frame(now: number): void {
    if (!transition || destroyed) return;
    const t = transition;
    const elapsed = t.elapsedBefore + (now - t.startedAt);
    const ratio = Math.min(1, elapsed / TRANSITION_MS);
    const radius = t.maxRadius * transitionEasing(ratio);
    const band = 1.5 * cellW;
    const fromItem = loaded[currentIndex];
    const toItem = loaded[pendingNextIndex];
    if (!fromItem || !toItem) return;
    for (let i = 0; i < cols * rows; i++) {
      const d = t.distances[i];
      let desired = 0;
      if (d <= radius) {
        desired = d > radius - band ? 2 : 1;
      }
      if (desired !== t.states[i]) {
        t.states[i] = desired;
        if (desired === 0) {
          drawDot(fromItem, i, false);
        } else {
          drawDot(toItem, i, desired === 2);
        }
      }
    }
    if (ratio >= 1) {
      currentIndex = pendingNextIndex;
      pendingNextIndex = -1;
      transition = null;
      rafId = null;
      drawAll(loaded[currentIndex]);
      scheduleDisplay(DISPLAY_MS);
      return;
    }
    rafId = requestAnimationFrame(frame);
  }

  //実行を止める（タイマーとフレームを止め、切り替えと表示の残り時間を覚える）
  function suspendExecution(): void {
    if (timer !== null) {
      timerRemaining = Math.max(0, timerDuration - (performance.now() - timerStartedAt));
      clearDisplayTimer();
    }
    if (rafId !== null) {
      cancelAnimationFrame(rafId);
      rafId = null;
    }
    if (transition && transition.running) {
      transition.elapsedBefore += performance.now() - transition.startedAt;
      transition.running = false;
    }
  }

  //実行を再開する（止めていた続きから動かす）
  function resumeExecution(): void {
    if (!started || destroyed) return;
    if (transition) {
      transition.startedAt = performance.now();
      transition.running = true;
      rafId = requestAnimationFrame(frame);
      return;
    }
    if (currentIndex >= 0) {
      scheduleDisplay(timerRemaining ?? DISPLAY_MS);
    }
  }

  //画面の大きさに合わせ直す（格子が変わったらドット絵化からやり直す）
  function resize(): void {
    if (destroyed) return;
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    if (w <= 0 || h <= 0) return;
    if (canvas.width !== w) canvas.width = w;
    if (canvas.height !== h) canvas.height = h;
    const newCols = Math.max(1, Math.round(w / DOT_SIZE));
    const newRows = Math.max(1, Math.round(h / DOT_SIZE));
    cellW = w / newCols;
    cellH = h / newRows;
    if (newCols === cols && newRows === rows && currentIndex >= 0) {
      drawAll(loaded[currentIndex]);
      return;
    }
    cols = newCols;
    rows = newRows;
    //大きさが変わった途中の切り替えは終わったことにする
    if (transition) {
      currentIndex = pendingNextIndex;
      pendingNextIndex = -1;
      transition = null;
      if (rafId !== null) {
        cancelAnimationFrame(rafId);
        rafId = null;
      }
      clearDisplayTimer();
      timerRemaining = null;
    }
    for (const item of loaded) {
      convert(item);
    }
    if (currentIndex >= 0 && loaded[currentIndex]) {
      drawAll(loaded[currentIndex]);
      if (started && !suspended) {
        scheduleDisplay(DISPLAY_MS);
      }
    } else {
      fillBackground();
    }
  }

  //画像を読み込む（引数srcは画像の場所、失敗したら理由をコンソールに出してnullを返す）
  function loadImage(src: string): Promise<HTMLImageElement | null> {
    return new Promise((resolve) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = () => {
        console.error(`Pixel Wave: failed to load image: ${src}`);
        resolve(null);
      };
      image.src = src;
    });
  }

  //絵の一覧を読み込み直す（引数listは絵の一覧、読み込めた絵だけで順番を作り直す）
  async function loadPaintings(list: Painting[]): Promise<void> {
    const token = ++loadToken;
    clearDisplayTimer();
    resize();
    const results = await Promise.all(
      list.map(async (painting) => {
        const image = await loadImage(painting.src);
        if (!image) return null;
        const item: LoadedPainting = { painting, image, art: null, css: [], glowCss: [] };
        convert(item);
        return item;
      }),
    );
    if (token !== loadToken || destroyed) return;
    const previousId = currentIndex >= 0 ? loaded[currentIndex]?.painting.id : undefined;
    loaded = results.filter((item): item is LoadedPainting => item !== null);
    playOrder = shuffleOrder(loaded.length, -1, Math.random);
    playPos = 0;
    currentIndex = -1;
    if (loaded.length > 0) {
      const kept = previousId
        ? loaded.findIndex((item) => item.painting.id === previousId)
        : -1;
      if (kept >= 0) {
        currentIndex = kept;
        playPos = Math.max(0, playOrder.indexOf(kept));
      } else {
        currentIndex = playOrder[0];
        playPos = 0;
      }
      drawAll(loaded[currentIndex]);
      if (started && !suspended) {
        scheduleDisplay(DISPLAY_MS);
      }
    } else {
      fillBackground();
    }
  }

  //画面が隠れたら止め、戻ったら再開するための監視
  const onVisibility = (): void => {
    if (document.hidden) {
      if (started && !suspended) {
        suspended = true;
        suspendExecution();
      }
    } else if (suspended) {
      suspended = false;
      resumeExecution();
    }
  };
  document.addEventListener("visibilitychange", onVisibility);

  //画面の大きさの変化の監視
  let resizeObserver: ResizeObserver | null = null;
  if (typeof ResizeObserver !== "undefined") {
    resizeObserver = new ResizeObserver(() => resize());
    resizeObserver.observe(canvas);
  }
  window.addEventListener("resize", resize);

  resize();
  void loadPaintings(paintings);

  return {
    //再生を始める
    start(): void {
      if (destroyed || started) return;
      started = true;
      if (document.hidden) {
        suspended = true;
        return;
      }
      suspended = false;
      resumeExecution();
    },
    //止める（タイマーも止まる）
    stop(): void {
      if (!started) return;
      started = false;
      suspended = false;
      suspendExecution();
    },
    //絵を入れ替える（引数pは新しい絵の一覧、再生は続ける）
    setPaintings(p: Painting[]): void {
      if (destroyed) return;
      void loadPaintings(p);
    },
    //破棄する（監視とタイマーをすべて止める）
    destroy(): void {
      destroyed = true;
      started = false;
      clearDisplayTimer();
      if (rafId !== null) {
        cancelAnimationFrame(rafId);
        rafId = null;
      }
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("resize", resize);
      if (resizeObserver) {
        resizeObserver.disconnect();
        resizeObserver = null;
      }
    },
  };
}
