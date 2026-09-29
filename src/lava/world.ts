import { compute, storage, texture, type Gpu, type Texture } from "vgpu";
import type { Settings } from "../state/settings";
import { FIELD_HEAT, FIELD_OUTLINES, FIELD_WORLD } from "./field";
import { pack } from "./layout";
import { continuations } from "./sides";
import anchorWgsl from "./shaders/anchor.wgsl";
import flowWgsl from "./shaders/flow.wgsl";
import outlineWgsl from "./shaders/outline.wgsl";
import relaxWgsl from "./shaders/relax.wgsl";
import rockWgsl from "./shaders/rock.wgsl";
import surfaceWgsl from "./shaders/surface.wgsl";
import terrainWgsl from "./shaders/terrain.wgsl";

const HEIGHT = 1280;
const SNAP = 32;
const MEAN_SPEED = 24;
const FIELD_GAIN = 1.4;
const DRAG = { drag: 6, reach: 18 };
const GROUP = 8;
const ROCK_DETAIL = 2.5;
const ROCK_LIMIT = 6144;
const ANCHOR = { divide: 8, steps: 480 };
const LEVELS = [
  { divide: 16, steps: 900 },
  { divide: 8, steps: 300 },
  { divide: 4, steps: 200 },
  { divide: 2, steps: 200 },
];

export type Size = readonly [number, number];

export interface World {
  readonly size: Size;
  readonly flow: Texture;
  readonly surface: Texture;
  readonly rock: Texture;
  destroy(): void;
}

export type Shape = Pick<Settings, "layout" | "seed" | "width" | "land" | "islands" | "meander">;

export const SHAPE: readonly (keyof Shape)[] = ["layout", "seed", "width", "land", "islands", "meander"];

export function worldFor(layout: Settings["layout"], [width, height]: Size): Size {
  const tall = layout === "field" ? FIELD_WORLD[1] : HEIGHT;
  const wide = Math.round((tall * width) / height / SNAP) * SNAP;
  return [Math.max(wide, layout === "field" ? FIELD_WORLD[0] : Math.round(tall * (9 / 16))), tall];
}

export const originOf = (world: Size): number => (world[0] - FIELD_WORLD[0]) / 2;

const groups = ([width, height]: Size) => [Math.ceil(width / GROUP), Math.ceil(height / GROUP)] as const;

export function createWorld(gpu: Gpu, size: Size, shape: Shape): World {
  const owned: Texture[] = [];
  const field = (extent: Size, format: GPUTextureFormat, label: string) => {
    const made = texture(gpu, {
      kind: "2d",
      size: extent,
      format,
      usage: ["storage_binding", "texture_binding"],
      label,
    });
    owned.push(made);
    return made;
  };
  const terrain = field(size, "rgba32float", "terrain");
  let guess = 0;

  if (shape.layout === "field") {
    const sides = continuations(size);
    const packed = pack([...FIELD_OUTLINES, ...sides]);
    const buffer = (data: ArrayBuffer) => {
      const made = storage(gpu, Math.max(data.byteLength, 32), "read");
      made.write(data);
      return made;
    };
    const table = new Uint8Array(packed.shapes);
    const split = FIELD_OUTLINES.length * 32;
    guess = pack(FIELD_OUTLINES).guess;
    compute(gpu, outlineWgsl, {
      label: "outline",
      set: {
        outline: {
          world: size,
          origin: [originOf(size), 0],
          traced: FIELD_WORLD,
          shapes: FIELD_OUTLINES.length,
          channels: sides.length,
        },
        shapes: buffer(table.slice(0, split).buffer),
        channels: buffer(table.slice(split).buffer),
        points: buffer(packed.points.buffer as ArrayBuffer),
        terrainOut: terrain,
      },
    }).dispatch(...groups(size));
  } else {
    compute(gpu, terrainWgsl, {
      label: "terrain",
      set: {
        terrainOut: terrain,
        terrain: {
          world: size,
          seed: shape.seed,
          width: shape.width,
          land: shape.land,
          islands: shape.islands,
          meander: shape.meander,
          flux: 2 * shape.width * MEAN_SPEED,
        },
      },
    }).dispatch(...groups(size));
  }

  const anchorSize: Size = [Math.ceil(size[0] / ANCHOR.divide), Math.ceil(size[1] / ANCHOR.divide)];
  const anchors = [field(anchorSize, "rg32float", "anchor-a"), field(anchorSize, "rg32float", "anchor-b")];
  compute(gpu, anchorWgsl, {
    label: "anchor-start",
    entry: "start",
    set: { terrainTex: terrain, anchorIn: anchors[1], anchorOut: anchors[0] },
  }).dispatch(...groups(anchorSize));
  const spread = compute(gpu, anchorWgsl, { label: "anchor", entry: "spread", set: { terrainTex: terrain } });
  const reach = shape.layout === "field" ? ANCHOR.steps : 0;
  for (let k = 0; k < reach; k++) {
    spread.set({ anchorIn: anchors[k % 2], anchorOut: anchors[1 - (k % 2)] }).dispatch(...groups(anchorSize));
  }
  const anchorTex = anchors[reach % 2];

  const start = compute(gpu, relaxWgsl, { label: "relax-start", entry: "start" });
  const relax = compute(gpu, relaxWgsl, { label: "relax", entry: "relax" });
  let coarse = field([1, 1], "r32float", "psi-seed");
  LEVELS.forEach(({ divide, steps }, i) => {
    const extent: Size = [Math.ceil(size[0] / divide), Math.ceil(size[1] / divide)];
    const pair = [field(extent, "r32float", `psi-${divide}-a`), field(extent, "r32float", `psi-${divide}-b`)];
    const level = { world: size, guess, refine: i ? 1 : 0, ...DRAG };
    const common = { level, terrainTex: terrain, coarseTex: coarse, anchorTex };
    start.set({ ...common, psiIn: coarse, psiOut: pair[0] }).dispatch(...groups(extent));
    const count = shape.layout === "field" ? steps : 0;
    for (let k = 0; k < count; k++) {
      relax.set({ ...common, psiIn: pair[k % 2], psiOut: pair[1 - (k % 2)] }).dispatch(...groups(extent));
    }
    coarse = pair[count % 2];
  });

  const psi = coarse;
  const flow = field(psi.size as Size, "rgba32float", "flow");
  compute(gpu, flowWgsl, {
    label: "flow",
    set: {
      grid: { world: size, gain: shape.layout === "field" ? FIELD_GAIN : 1 },
      psiTex: psi,
      flowOut: flow,
    },
  }).dispatch(...groups(psi.size as Size));
  const heat = new Float32Array(shape.layout === "field" ? FIELD_HEAT : [0, 0, 1, 0]);
  const blobs = storage(gpu, heat.byteLength, "read");
  blobs.write(heat);
  const surface = field(size, "rgba32float", "surface");
  compute(gpu, surfaceWgsl, {
    label: "surface",
    set: {
      look: { world: size, seed: shape.seed, blobs: heat.length / 4, origin: [originOf(size), 0] },
      blobs,
      terrainTex: terrain,
      flowTex: flow,
      surfaceOut: surface,
      psiTex: psi,
    },
  }).dispatch(...groups(size));

  const detail = Math.min(ROCK_DETAIL, ROCK_LIMIT / size[0]);
  const rockSize: Size = [Math.round(size[0] * detail), Math.round(size[1] * detail)];
  const rock = field(rockSize, "rgba8unorm", "rock");
  compute(gpu, rockWgsl, {
    label: "rock",
    set: {
      look: { world: size, seed: shape.seed },
      surfaceTex: surface,
      rockOut: rock,
    },
  }).dispatch(...groups(rockSize));

  return {
    size,
    flow,
    surface,
    rock,
    destroy() {
      owned.forEach((t) => t.destroy());
    },
  };
}
