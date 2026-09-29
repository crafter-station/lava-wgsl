export interface Outline {
  readonly psi: number;
  readonly points: readonly number[];
}

const SHAPE_FLOATS = 8;

export function pack(outlines: readonly Outline[]) {
  const shapes = new ArrayBuffer(outlines.length * SHAPE_FLOATS * 4);
  const points = new Float32Array(outlines.flatMap((outline) => outline.points));
  let start = 0;
  outlines.forEach(({ psi, points: flat }, i) => {
    const xs = flat.filter((_, k) => k % 2 === 0);
    const ys = flat.filter((_, k) => k % 2 === 1);
    const count = flat.length / 2;
    new Uint32Array(shapes, i * SHAPE_FLOATS * 4, 2).set([start, count]);
    new Float32Array(shapes, i * SHAPE_FLOATS * 4 + 8, 6).set([
      psi,
      0,
      Math.min(...xs),
      Math.min(...ys),
      Math.max(...xs),
      Math.max(...ys),
    ]);
    start += count;
  });
  return { shapes, points, guess: outlines.reduce((sum, o) => sum + o.psi, 0) / outlines.length };
}
