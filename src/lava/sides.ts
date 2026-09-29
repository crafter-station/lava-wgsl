import { FIELD_EXITS, FIELD_WORLD } from "./field";
import type { Outline } from "./layout";

const SPACING = 150;
const TURN = 90;
const SAMPLES = 10;

type Point = readonly [number, number];

interface Exit {
  readonly side: -1 | 1;
  readonly middle: number;
  readonly half: number;
  readonly inflow: boolean;
}

const exits: readonly Exit[] = Array.from({ length: FIELD_EXITS.length / 4 }, (_, i) => {
  const [side, from, to, inflow] = FIELD_EXITS.slice(i * 4, i * 4 + 4);
  return { side: side < 0 ? -1 : 1, middle: (from + to) / 2, half: (to - from) / 2, inflow: inflow > 0 };
});

function smooth(points: readonly Point[]): number[] {
  const at = (i: number) => points[Math.max(0, Math.min(points.length - 1, i))];
  const out: number[] = [];
  for (let i = 0; i < points.length - 1; i++) {
    for (let k = 0; k < SAMPLES; k++) {
      const t = k / SAMPLES;
      const [a, b, c, d] = [at(i - 1), at(i), at(i + 1), at(i + 2)];
      const blend = (axis: 0 | 1) =>
        0.5 *
        (2 * b[axis] +
          (c[axis] - a[axis]) * t +
          (2 * a[axis] - 5 * b[axis] + 4 * c[axis] - d[axis]) * t * t +
          (3 * b[axis] - a[axis] - 3 * c[axis] + d[axis]) * t * t * t);
      out.push(blend(0), blend(1));
    }
  }
  out.push(...points[points.length - 1]);
  return out;
}

function rank(exit: Exit): number {
  return exits.filter(
    (other) =>
      other.side === exit.side &&
      other.inflow === exit.inflow &&
      (exit.inflow ? other.middle < exit.middle : other.middle > exit.middle),
  ).length;
}

export function continuations(world: readonly [number, number]): Outline[] {
  const origin = (world[0] - FIELD_WORLD[0]) / 2;
  if (origin <= 0) return [];
  return exits.map((exit) => {
    const seam = exit.side < 0 ? origin : origin + FIELD_WORLD[0];
    const reach = Math.min(TURN + exit.half + rank(exit) * SPACING, origin - exit.half);
    const edge = exit.inflow ? -exit.half : world[1] + exit.half;
    const out = (distance: number) => seam + exit.side * distance;
    const bend = exit.middle + (edge - exit.middle) * 0.25;
    return {
      psi: exit.half,
      points: smooth([
        [out(-12), exit.middle],
        [out(reach * 0.5), exit.middle],
        [out(reach), bend],
        [out(reach * 1.08), edge],
      ]),
    };
  });
}
