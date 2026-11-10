//描画エンジンの純粋関数を集めたファイル（切り抜きと減色と波の判定とイージングと並び替え）
//このファイルは画面描画に触れないので単体テストで確かめられる

//正規化座標による切り抜き（割合0.0～1.0）
export interface NormalizedCrop {
  x: number;
  y: number;
  w: number;
  h: number;
}

//切り抜き位置（上か中央か下、または正規化矩形）
export type Crop = "top" | "center" | "bottom" | NormalizedCrop;

//絵の指定（idは識別子、srcは画像の場所、cropは切り抜き位置で省略すると中央になる）
export interface Painting {
  id: string;
  src: string;
  crop?: Crop;
}

//色（赤と緑と青が各0から255）
export type RGB = [number, number, number];

//切り抜く範囲（sxとsyは左上の座標、swとshは幅と高さ）
export interface CropRect {
  sx: number;
  sy: number;
  sw: number;
  sh: number;
}

//ドット絵（paletteは16色、indicesは各ドットの色番号、colsとrowsはドットの数）
export interface DotArt {
  palette: RGB[];
  glowPalette: RGB[];
  indices: Uint16Array;
  cols: number;
  rows: number;
}

//種から乱数を作る（mulberry32という方式で同じ種なら同じ並びになる）
export function createRng(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

//画像から目標の縦横比になる範囲を切り抜く計算（引数imageWidthとimageHeightは画像の大きさ、引数targetAspectは幅÷高さ、引数cropは切り抜き位置）
//横長すぎる画像は横を切り位置は常に中央になり、縦長すぎる画像は縦を切り位置をcropで選ぶ
export function computeCropRect(
  imageWidth: number,
  imageHeight: number,
  targetAspect: number,
  crop: Crop,
): CropRect {
  if (typeof crop === "object" && crop !== null) {
    return {
      sx: Math.round(imageWidth * crop.x),
      sy: Math.round(imageHeight * crop.y),
      sw: Math.round(imageWidth * crop.w),
      sh: Math.round(imageHeight * crop.h),
    };
  }
  const ratio = imageWidth / imageHeight;
  let sw = imageWidth;
  let sh = imageHeight;
  if (ratio > targetAspect) {
    sw = Math.round(imageHeight * targetAspect);
  } else {
    sh = Math.round(imageWidth / targetAspect);
  }
  const sx = Math.floor((imageWidth - sw) / 2);
  let sy = Math.floor((imageHeight - sh) / 2);
  if (crop === "top") {
    sy = 0;
  } else if (crop === "bottom") {
    sy = imageHeight - sh;
  }
  return { sx, sy, sw, sh };
}

//2色の距離の2乗を返す（引数aとbは色、引数offsetAとoffsetBは並んだ数値列での開始位置）
function distance2(
  a: ArrayLike<number>,
  offsetA: number,
  b: ArrayLike<number>,
  offsetB: number,
): number {
  const dr = a[offsetA] - b[offsetB];
  const dg = a[offsetA + 1] - b[offsetB + 1];
  const db = a[offsetA + 2] - b[offsetB + 2];
  return dr * dr + dg * dg + db * db;
}

//色を白に寄せる（引数colorは元の色、引数ratioは白の割合で0.6なら白に60％寄せる）
export function blendTowardWhite(color: RGB, ratio: number): RGB {
  return [
    Math.round(color[0] + (255 - color[0]) * ratio),
    Math.round(color[1] + (255 - color[1]) * ratio),
    Math.round(color[2] + (255 - color[2]) * ratio),
  ];
}

//k-means法で色を減らす（引数dataは赤緑青が並んだ画素列、引数kは色数、引数seedは乱数の種で同じ入力と種なら毎回同じ結果になる）
//初期の中心はk-means++の考え方で種付き乱数を使って選び、割り当てと中心の更新を最大100回繰り返す
export function kmeansQuantize(
  data: ArrayLike<number>,
  k: number,
  seed: number,
): { palette: RGB[]; indices: Uint16Array } {
  const count = Math.floor(data.length / 3);
  const rng = createRng(seed);
  const centers: number[] = [];

  //最初の中心は無作為に選んだ画素にする
  const first = Math.floor(rng() * count) * 3;
  centers.push(data[first], data[first + 1], data[first + 2]);

  //既存の中心からの距離に応じた確率で次の中心を選ぶ
  while (centers.length < k * 3) {
    let total = 0;
    const weights: number[] = new Array<number>(count);
    for (let i = 0; i < count; i++) {
      let min = Infinity;
      for (let c = 0; c < centers.length; c += 3) {
        min = Math.min(min, distance2(data, i * 3, centers, c));
      }
      weights[i] = min;
      total += min;
    }
    if (total === 0) {
      //色の種類がkより少ない場合は既存の中心を複製して色数をそろえる
      centers.push(centers[0], centers[1], centers[2]);
      continue;
    }
    let pick = rng() * total;
    let chosen = 0;
    for (let i = 0; i < count; i++) {
      pick -= weights[i];
      if (pick <= 0) {
        chosen = i;
        break;
      }
    }
    centers.push(data[chosen * 3], data[chosen * 3 + 1], data[chosen * 3 + 2]);
  }

  const indices = new Uint16Array(count);
  for (let iter = 0; iter < 100; iter++) {
    let changed = false;
    for (let i = 0; i < count; i++) {
      let best = 0;
      let bestDist = Infinity;
      for (let c = 0; c < k; c++) {
        const d = distance2(data, i * 3, centers, c * 3);
        if (d < bestDist) {
          bestDist = d;
          best = c;
        }
      }
      if (indices[i] !== best) {
        indices[i] = best;
        changed = true;
      }
    }

    const sums = new Float64Array(k * 4);
    for (let i = 0; i < count; i++) {
      const base = indices[i] * 4;
      sums[base] += data[i * 3];
      sums[base + 1] += data[i * 3 + 1];
      sums[base + 2] += data[i * 3 + 2];
      sums[base + 3] += 1;
    }
    for (let c = 0; c < k; c++) {
      const base = c * 4;
      if (sums[base + 3] > 0) {
        centers[c * 3] = sums[base] / sums[base + 3];
        centers[c * 3 + 1] = sums[base + 1] / sums[base + 3];
        centers[c * 3 + 2] = sums[base + 2] / sums[base + 3];
      }
    }
    if (!changed) break;
  }

  const palette: RGB[] = [];
  for (let c = 0; c < k; c++) {
    palette.push([
      Math.max(0, Math.min(255, Math.round(centers[c * 3]))),
      Math.max(0, Math.min(255, Math.round(centers[c * 3 + 1]))),
      Math.max(0, Math.min(255, Math.round(centers[c * 3 + 2]))),
    ]);
  }
  return { palette, indices };
}

//画素列からドット絵を作る（引数dataは赤緑青が並んだ画素列、引数colsとrowsはドットの数、引数seedは減色の種）
export function dotArtFromPixels(
  data: ArrayLike<number>,
  cols: number,
  rows: number,
  seed: number,
): DotArt {
  const { palette, indices } = kmeansQuantize(data, 16, seed);
  const glowPalette = palette.map((color) => blendTowardWhite(color, 0.6));
  return { palette, glowPalette, indices, cols, rows };
}

//点が円の内側にあるか調べる（引数xとyは点の座標、引数cxとcyは円の中心、引数radiusは半径、境界上は内側とする）
export function isInsideCircle(
  x: number,
  y: number,
  cx: number,
  cy: number,
  radius: number,
): boolean {
  const dx = x - cx;
  const dy = y - cy;
  return dx * dx + dy * dy <= radius * radius;
}

//点が波の先頭の帯にあるか調べる（引数xとyは点の座標、引数cxとcyは円の中心、引数radiusは半径、引数bandは帯の幅で帯は半径の内側にある）
export function isInWaveFront(
  x: number,
  y: number,
  cx: number,
  cy: number,
  radius: number,
  band: number,
): boolean {
  const dx = x - cx;
  const dy = y - cy;
  const d = Math.sqrt(dx * dx + dy * dy);
  return d <= radius && d > radius - band;
}

//3次ベジェ曲線のイージング関数を作る（引数は2つの制御点の座標で戻り値は進み具合を受けて進み具合を返す関数）
export function cubicBezierEasing(
  x1: number,
  y1: number,
  x2: number,
  y2: number,
): (x: number) => number {
  //ベジェ曲線の座標を返す（引数tは曲線のパラメータ、引数a1とa2は制御点の値）
  const sample = (t: number, a1: number, a2: number): number => {
    const u = 1 - t;
    return 3 * u * u * t * a1 + 3 * u * t * t * a2 + t * t * t;
  };
  return (x: number): number => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    //横の値からパラメータを二分探索で求めて縦の値を返す
    let lo = 0;
    let hi = 1;
    let t = x;
    for (let i = 0; i < 40; i++) {
      t = (lo + hi) / 2;
      if (sample(t, x1, x2) < x) {
        lo = t;
      } else {
        hi = t;
      }
    }
    return sample(t, y1, y2);
  };
}

//切り替えに使うイージング（cubic-bezier（0.37，0，0.63，1）でゆっくり始まりゆっくり終わる。減速だけの形では最初の1～2秒で画面のほとんどが替わり、速すぎたため）
export const transitionEasing = cubicBezierEasing(0.37, 0, 0.63, 1);

//画面の外周上の点を無作為に1つ選ぶ（引数widthとheightは画面の大きさ、引数rngは乱数、外周の長さに沿って均等に選ぶ）
export function pickPerimeterPoint(
  width: number,
  height: number,
  rng: () => number,
): { x: number; y: number } {
  const perimeter = 2 * (width + height);
  let s = rng() * perimeter;
  if (s < width) return { x: s, y: 0 };
  s -= width;
  if (s < height) return { x: width, y: s };
  s -= height;
  if (s < width) return { x: width - s, y: height };
  s -= width;
  return { x: 0, y: height - s };
}

//点から一番遠い画面の角までの距離を返す（引数xとyは点の座標、引数widthとheightは画面の大きさ）
export function farthestCornerDistance(
  x: number,
  y: number,
  width: number,
  height: number,
): number {
  const corners: Array<[number, number]> = [
    [0, 0],
    [width, 0],
    [0, height],
    [width, height],
  ];
  let max = 0;
  for (const [cx, cy] of corners) {
    const dx = x - cx;
    const dy = y - cy;
    max = Math.max(max, Math.sqrt(dx * dx + dy * dy));
  }
  return max;
}

//表示する順番をシャッフルして作る（引数countは絵の数、引数avoidFirstは先頭に来てはいけない番号で無い場合は負の数、引数rngは乱数）
export function shuffleOrder(
  count: number,
  avoidFirst: number,
  rng: () => number,
): number[] {
  const order: number[] = [];
  for (let i = 0; i < count; i++) order.push(i);
  for (let i = count - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    const tmp = order[i];
    order[i] = order[j];
    order[j] = tmp;
  }
  if (count > 1 && order[0] === avoidFirst) {
    const j = 1 + Math.floor(rng() * (count - 1));
    const tmp = order[0];
    order[0] = order[j];
    order[j] = tmp;
  }
  return order;
}
