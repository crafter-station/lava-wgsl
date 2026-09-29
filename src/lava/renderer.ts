import { effect, frame, frameLoop, init, sampler, surface, target, uniforms, type Frame } from "vgpu";
import type { Settings } from "../state/settings";
import type { Store } from "../state/store";
import { createBloom } from "./bloom";
import { viewAt } from "./camera";
import presentWgsl from "./shaders/present.wgsl";
import sceneWgsl from "./shaders/scene.wgsl";
import { createSimulation, padFor, type Simulation } from "./simulation";
import { createWorld, SHAPE, worldFor, type Size, type World } from "./world";

const WARMUP = { steps: 240, dt: 0.05 };
const LONGEST_STEP = 1 / 20;
const BLOOM = 0.012;
const HAZE = 0.0012;
const GRAIN = 0.012;
const DENSITY: Record<Settings["quality"], number> = { draft: 0.5, hd: 1, ultra: 1.5 };
const MAX_PIXEL_RATIO = 2;

export interface Lava {
  readonly ready: Promise<void>;
  capture(): Promise<Blob>;
  dispose(): void;
}

const same = (a: Size, b: Size) => a[0] === b[0] && a[1] === b[1];

export function createLava(canvas: HTMLCanvasElement, settings: Store<Settings>): Lava {
  let dispose = () => {};

  const start = async () => {
    const gpu = await init({ powerPreference: "high-performance" });
    dispose = () => gpu.dispose();

    const output = surface(gpu, canvas, { autoResize: false });
    const hdr = target(gpu, { size: output.size, format: "rgba16float", label: "hdr" });
    const linear = sampler(gpu, { magFilter: "linear", minFilter: "linear" });

    let time = 0;
    let clock = 0;
    let world: World | undefined;
    let simulation: Simulation | undefined;
    let shaped = settings.get();

    const uniformsFor = (value: Settings, dt: number) => {
      const size = world?.size ?? [1, 1];
      const view = viewAt(size, output.size, clock, value);
      return {
        resolution: output.size,
        world: size,
        viewCenter: view.center,
        viewHalf: view.half,
        viewTurn: view.turn,
        time,
        dt,
        exposure: value.exposure,
        plate: shaped.plate,
        pad: padFor(shaped.plate),
        life: value.life,
        spin: value.spin,
        detail: value.detail,
        sheen: value.sheen,
        heat: value.heat,
        seed: shaped.seed,
      };
    };

    const frameData = uniforms(gpu, uniformsFor(settings.get(), 0));
    const shade = effect(gpu, sceneWgsl, {
      label: "scene",
      set: { frame: frameData, linearSampler: linear },
    });
    const bloom = createBloom(gpu, hdr, linear);
    const present = effect(gpu, presentWgsl, {
      label: "present",
      set: { hdrTex: hdr, bloomTex: bloom.result, linearSampler: linear },
    });
    await Promise.all([shade.compile(hdr), bloom.compile(), present.compile({ colors: [output.format] })]);

    const advance = (dt: number) => {
      frameData.set(uniformsFor(settings.get(), dt));
      simulation?.step();
    };

    const generate = () => {
      shaped = settings.get();
      simulation?.destroy();
      world?.destroy();
      world = createWorld(gpu, worldFor(shaped.layout, output.size), shaped);
      simulation = createSimulation(gpu, { terrain: world, frame: frameData, plate: shaped.plate });
      shade.set({ surfaceTex: world.surface, flowTex: world.flow, rockTex: world.rock });
      for (let i = 0; i < WARMUP.steps; i++) {
        time += i ? WARMUP.dt : 0;
        advance(i ? WARMUP.dt : 0);
      }
    };

    const fit = () => {
      const density = Math.min(devicePixelRatio, MAX_PIXEL_RATIO) * DENSITY[settings.get().quality];
      const size = [canvas.clientWidth, canvas.clientHeight].map((side) =>
        Math.max(1, Math.round(side * density)),
      ) as [number, number];
      if (!same(size, output.size)) {
        output.resize(size);
        hdr.resize(size);
        bloom.resize(size);
      }
      if (!world || !same(worldFor(settings.get().layout, size), world.size)) generate();
    };
    const observer = new ResizeObserver(fit);
    observer.observe(canvas);
    fit();

    settings.subscribe((value) => {
      fit();
      if (SHAPE.some((key) => value[key] !== shaped[key])) return generate();
      if (value.plate === shaped.plate) return;
      shaped = value;
      simulation?.rebuild(value.plate);
      advance(0);
    });

    const render = (current: Frame) => {
      if (!simulation) return;
      const value = settings.get();
      frameData.set(uniformsFor(value, 0));
      shade.set({ platesTex: simulation.plates, lookupTex: simulation.lookup });
      present.set({
        present: { time, bloom: BLOOM * value.glow, haze: HAZE * value.haze, grain: GRAIN * value.grain },
      });
      current.pass({ target: hdr }, shade);
      bloom.run(current);
      current.pass({ target: output }, present);
    };

    let last = performance.now();
    const loop = frameLoop(gpu, (current) => {
      const now = performance.now();
      const dt = Math.min(Math.max(now - last, 0) / 1000, LONGEST_STEP);
      last = now;
      const value = settings.get();
      if (value.motion === "play") {
        clock += dt;
        time += dt * value.speed;
        advance(dt * value.speed);
      }
      render(current);
    });

    dispose = () => {
      loop.stop();
      observer.disconnect();
      gpu.dispose();
    };
    return () => frame(gpu, render);
  };

  const running = start();

  return {
    ready: running.then(() => undefined),
    async capture() {
      const still = await running;
      still();
      return new Promise((resolve, reject) =>
        canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("Capture failed"))), "image/png"),
      );
    },
    dispose: () => dispose(),
  };
}
