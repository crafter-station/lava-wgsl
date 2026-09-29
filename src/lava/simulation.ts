import { compute, texture, type Gpu, type SharedUniforms, type Texture } from "vgpu";
import type { World } from "./world";
import lookupWgsl from "./shaders/lookup.wgsl";
import platesWgsl from "./shaders/plates.wgsl";
import simWgsl from "./shaders/sim.wgsl";

const GROUP = 8;
const REACH = 9;
const COORDS = 2;

type Size = readonly [number, number];
type Pair = [Texture, Texture];

export interface Simulation {
  readonly plates: Texture;
  readonly lookup: Texture;
  step(): void;
  rebuild(plate: number): void;
  destroy(): void;
}

export const padFor = (plate: number) => plate * REACH;

export interface SimulationOptions {
  readonly terrain: World;
  readonly frame: SharedUniforms;
  readonly linear: GPUSampler;
  readonly plate: number;
}

export function createSimulation(gpu: Gpu, { terrain, frame, linear, plate }: SimulationOptions): Simulation {
  const world = terrain.size;
  const field = (size: Size, label: string) =>
    texture(gpu, {
      kind: "2d",
      size,
      format: "rgba32float",
      usage: ["storage_binding", "texture_binding"],
      label,
    });
  const pair = (size: Size, label: string): Pair => [field(size, `${label}-a`), field(size, `${label}-b`)];
  const common = { frame, linearSampler: linear, flowTex: terrain.flow };
  const sim = compute(gpu, simWgsl, { label: "sim", set: common });
  const plates = compute(gpu, platesWgsl, { label: "plates", set: common });
  const lookup = compute(gpu, lookupWgsl, { label: "lookup", set: { frame } });
  const run = (pass: typeof sim, [width, height]: Size) =>
    pass.dispatch(Math.ceil(width / GROUP), Math.ceil(height / GROUP));

  const coarse: Size = [Math.ceil(world[0] / COORDS), Math.ceil(world[1] / COORDS)];
  const coords = pair(coarse, "coords");
  let current = 0;
  let layout = build(plate);

  function build(size: number) {
    const pad = padFor(size);
    const grid = world.map((extent) => Math.ceil((extent + 2 * pad) / size));
    const cells = world.map((extent) => Math.ceil((2 * extent) / size));
    const stack: Size = [grid[0], grid[1] * 2];
    return {
      stack,
      cells: [cells[0], cells[1] * 2] as Size,
      plates: pair(stack, "plates"),
      lookup: field([cells[0] * 2, cells[1] * 2], "lookup"),
    };
  }

  return {
    get plates() {
      return layout.plates[current];
    },
    get lookup() {
      return layout.lookup;
    },
    step() {
      const next = 1 - current;
      run(sim.set({ coordsIn: coords[current], coordsOut: coords[next] }), coarse);
      run(plates.set({ platesIn: layout.plates[current], platesOut: layout.plates[next] }), layout.stack);
      current = next;
      const read = {
        coordsTex: coords[current],
        platesTex: layout.plates[current],
        lookupOut: layout.lookup,
      };
      run(lookup.set(read), layout.cells);
    },
    destroy() {
      [...coords, ...layout.plates, layout.lookup].forEach((old) => old.destroy());
    },
    rebuild(size) {
      [...layout.plates, layout.lookup].forEach((old) => old.destroy());
      layout = build(size);
    },
  };
}
