import { effect, target, type Frame, type Gpu, type Target } from "vgpu";
import downWgsl from "./shaders/bloom-down.wgsl";
import upWgsl from "./shaders/bloom-up.wgsl";

const LEVELS = 6;
const FORMAT = "rgba16float";

type Size = readonly [number, number];

export interface Bloom {
  readonly result: Target;
  resize(size: Size): void;
  compile(): Promise<unknown>;
  run(current: Frame): void;
}

const mip = ([width, height]: Size, level: number): Size => [
  Math.max(1, width >> level),
  Math.max(1, height >> level),
];

export function createBloom(gpu: Gpu, source: Target, linear: GPUSampler): Bloom {
  const levels = Array.from({ length: LEVELS }, (_, i) =>
    target(gpu, { size: mip(source.size, i + 1), format: FORMAT, label: `bloom-${i}` }),
  );
  const chain = [source, ...levels];
  const downs = levels.map((_, i) =>
    effect(gpu, downWgsl, { label: `bloom-down-${i}`, set: { source: chain[i], linearSampler: linear } }),
  );
  const ups = levels.map((level, i) =>
    effect(gpu, upWgsl, {
      label: `bloom-up-${i}`,
      blend: "additive",
      set: { source: level, linearSampler: linear },
    }),
  );
  return {
    result: levels[0],
    compile: () =>
      Promise.all([
        ...downs.map((pass, i) => pass.compile(levels[i])),
        ...ups.slice(1).map((pass, i) => pass.compile(levels[i])),
      ]),
    resize(size) {
      levels.forEach((level, i) => level.resize(mip(size, i + 1)));
    },
    run(current) {
      downs.forEach((pass, i) => current.pass({ target: levels[i] }, pass));
      for (let i = LEVELS - 1; i > 0; i--) current.pass({ target: levels[i - 1], clear: false }, ups[i]);
    },
  };
}
