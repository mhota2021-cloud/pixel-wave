//純粋関数の単体テスト（切り抜きと減色と波の判定とイージングと並び替え）
import { describe, expect, it } from "vitest";
import {
  blendTowardWhite,
  computeCropRect,
  createRng,
  cubicBezierEasing,
  farthestCornerDistance,
  isInWaveFront,
  isInsideCircle,
  kmeansQuantize,
  pickPerimeterPoint,
  shuffleOrder,
  transitionEasing,
} from "../src/dotart";

describe("computeCropRect", () => {
  it("横長の画像は横を切って中央を返す", () => {
    const rect = computeCropRect(400, 200, 3 / 2, "center");
    expect(rect).toEqual({ sx: 50, sy: 0, sw: 300, sh: 200 });
  });

  it("縦長の画像はtopで上、bottomで下を返す", () => {
    const top = computeCropRect(200, 600, 3 / 2, "top");
    expect(top.sy).toBe(0);
    expect(top.sh).toBe(133);
    const bottom = computeCropRect(200, 600, 3 / 2, "bottom");
    expect(bottom.sy).toBe(600 - 133);
    const center = computeCropRect(200, 600, 3 / 2, "center");
    expect(center.sy).toBe(Math.floor((600 - 133) / 2));
  });

it("縦横比が合う画像は切らない", () => {
  const rect = computeCropRect(300, 200, 3 / 2, "center");
  expect(rect).toEqual({ sx: 0, sy: 0, sw: 300, sh: 200 });
});

it("正規化座標（割合）の指定ならその範囲を切り抜く", () => {
  const rect = computeCropRect(1000, 800, 16 / 9, { x: 0.1, y: 0.2, w: 0.8, h: 0.5 });
  expect(rect).toEqual({ sx: 100, sy: 160, sw: 800, sh: 400 });
});
});

describe("kmeansQuantize", () => {
  //赤と青だけの画素列を作る（引数countは各色の数）
  function twoColorData(count: number): Uint8ClampedArray {
    const data = new Uint8ClampedArray(count * 2 * 3);
    for (let i = 0; i < count; i++) {
      data[i * 3] = 255;
    }
    for (let i = count; i < count * 2; i++) {
      data[i * 3 + 2] = 255;
    }
    return data;
  }

  it("同じ種なら毎回同じ結果になる", () => {
    const data = twoColorData(50);
    const a = kmeansQuantize(data, 2, 123);
    const b = kmeansQuantize(data, 2, 123);
    expect(a.palette).toEqual(b.palette);
    expect(Array.from(a.indices)).toEqual(Array.from(b.indices));
  });

  it("2色の画像は2つのグループに分かれる", () => {
    const data = twoColorData(50);
    const { palette, indices } = kmeansQuantize(data, 2, 7);
    expect(palette).toHaveLength(2);
    const firstHalf = new Set(Array.from(indices.slice(0, 50)));
    const secondHalf = new Set(Array.from(indices.slice(50)));
    expect(firstHalf.size).toBe(1);
    expect(secondHalf.size).toBe(1);
    expect([...firstHalf][0]).not.toBe([...secondHalf][0]);
    const colors = palette.map((c) => c.join(",")).sort();
    expect(colors).toEqual(["0,0,255", "255,0,0"]);
  });

  it("色数は16になり番号の数が画素数と一致する", () => {
    const rng = createRng(99);
    const data = new Uint8ClampedArray(30 * 20 * 3);
    for (let i = 0; i < data.length; i++) {
      data[i] = Math.floor(rng() * 256);
    }
    const { palette, indices } = kmeansQuantize(data, 16, 42);
    expect(palette).toHaveLength(16);
    expect(indices).toHaveLength(30 * 20);
    for (const idx of indices) {
      expect(idx).toBeGreaterThanOrEqual(0);
      expect(idx).toBeLessThan(16);
    }
  });
});

describe("blendTowardWhite", () => {
  it("0.6なら白に60％寄る", () => {
    expect(blendTowardWhite([0, 100, 255], 0.6)).toEqual([153, 193, 255]);
  });
});

describe("isInsideCircle", () => {
  it("内側と境界は真、外側は偽", () => {
    expect(isInsideCircle(10, 0, 0, 0, 20)).toBe(true);
    expect(isInsideCircle(20, 0, 0, 0, 20)).toBe(true);
    expect(isInsideCircle(21, 0, 0, 0, 20)).toBe(false);
    expect(isInsideCircle(0, 0, 100, 100, 10)).toBe(false);
  });
});

describe("isInWaveFront", () => {
  it("帯の中だけが真になる", () => {
    //中心からの距離が95の点は半径100と帯36の帯の中
    expect(isInWaveFront(95, 0, 0, 0, 100, 36)).toBe(true);
    //距離が50の点は帯より内側なので偽
    expect(isInWaveFront(50, 0, 0, 0, 100, 36)).toBe(false);
    //距離が120の点は円の外なので偽
    expect(isInWaveFront(120, 0, 0, 0, 100, 36)).toBe(false);
  });
});

describe("cubicBezierEasing", () => {
  it("両端は0と1になる", () => {
    const ease = cubicBezierEasing(0.23, 1, 0.32, 1);
    expect(ease(0)).toBe(0);
    expect(ease(1)).toBe(1);
    expect(transitionEasing(0)).toBe(0);
    expect(transitionEasing(1)).toBe(1);
  });

  it("単調に増え、ゆっくり始まりゆっくり終わる", () => {
    let prev = 0;
    for (let i = 1; i <= 10; i++) {
      const v = transitionEasing(i / 10);
      expect(v).toBeGreaterThan(prev);
      prev = v;
    }
    expect(transitionEasing(0.1)).toBeLessThan(0.1);
    expect(transitionEasing(0.5)).toBeCloseTo(0.5, 2);
    expect(transitionEasing(0.9)).toBeGreaterThan(0.9);
  });
});

describe("pickPerimeterPoint", () => {
  it("外周上の点が返る", () => {
    const rng = createRng(5);
    for (let i = 0; i < 50; i++) {
      const p = pickPerimeterPoint(300, 200, rng);
      const onEdge = p.x === 0 || p.x === 300 || p.y === 0 || p.y === 200;
      expect(onEdge).toBe(true);
      expect(p.x).toBeGreaterThanOrEqual(0);
      expect(p.x).toBeLessThanOrEqual(300);
      expect(p.y).toBeGreaterThanOrEqual(0);
      expect(p.y).toBeLessThanOrEqual(200);
    }
  });
});

describe("farthestCornerDistance", () => {
  it("角の点からは対角の角までの距離になる", () => {
    const d = farthestCornerDistance(0, 0, 300, 200);
    expect(d).toBeCloseTo(Math.sqrt(300 * 300 + 200 * 200), 5);
  });
});

describe("shuffleOrder", () => {
  it("全ての番号が1回ずつ現れる", () => {
    const order = shuffleOrder(8, -1, createRng(3));
    expect([...order].sort((a, b) => a - b)).toEqual([0, 1, 2, 3, 4, 5, 6, 7]);
  });

  it("避ける番号は先頭に来ない", () => {
    for (let seed = 1; seed <= 20; seed++) {
      const order = shuffleOrder(4, 2, createRng(seed));
      expect(order[0]).not.toBe(2);
    }
  });

  it("1枚だけならそのままになる", () => {
    expect(shuffleOrder(1, 0, createRng(1))).toEqual([0]);
  });
});
