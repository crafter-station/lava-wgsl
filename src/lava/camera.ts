import type { Settings } from "../state/settings";
import { FIELD_CENTER, FIELD_DURATION, FIELD_SCALE, FIELD_WORLD } from "./field";

type Vec2 = [number, number];

export interface View {
  readonly center: Vec2;
  readonly half: Vec2;
  readonly turn: Vec2;
}

interface Flight {
  readonly scale: number;
  readonly center: Vec2;
}

const PERIOD = 30;
const BREATH = 0.09;
const DRIFT = 0.04;

function recorded(seconds: number, hold: number | null, world: readonly [number, number]): Flight {
  const origin = (world[0] - FIELD_WORLD[0]) / 2;
  const cycle = (seconds / FIELD_DURATION) % 2;
  const at = (hold ?? 1 - Math.abs(cycle - 1)) * (FIELD_SCALE.length - 1);
  const i = Math.max(0, Math.min(Math.floor(at), FIELD_SCALE.length - 2));
  const mix = (from: number, to: number) => from + (to - from) * (at - i);
  return {
    scale: mix(FIELD_SCALE[i], FIELD_SCALE[i + 1]),
    center: [
      origin + mix(FIELD_CENTER[i * 2], FIELD_CENTER[i * 2 + 2]),
      mix(FIELD_CENTER[i * 2 + 1], FIELD_CENTER[i * 2 + 3]),
    ],
  };
}

function wandering(seconds: number, hold: number | null, world: readonly [number, number]): Flight {
  const phase = (hold ?? seconds / PERIOD) * Math.PI * 2;
  return {
    scale: 1 - BREATH * (0.5 - 0.5 * Math.cos(phase)),
    center: [
      world[0] * (0.5 + DRIFT * Math.sin(phase * 0.5 + 1.3)),
      world[1] * (0.5 + DRIFT * Math.sin(phase + 0.4)),
    ],
  };
}

export function viewAt(
  world: readonly [number, number],
  size: readonly [number, number],
  seconds: number,
  settings: Settings,
): View {
  const hold = settings.drone === "hold" ? settings.position : null;
  const flight =
    settings.layout === "field" ? recorded(seconds, hold, world) : wandering(seconds, hold, world);
  const scale = flight.scale / settings.zoom;
  const aspect = size[0] / size[1];
  const halfX = Math.min((scale * world[1] * aspect) / 2, (scale * world[0]) / 2);
  const angle = (settings.turn * Math.PI) / 180;
  const [cos, sin] = [Math.cos(angle), Math.sin(angle)];
  const reach = (x: number, y: number): Vec2 => [
    Math.abs(cos) * x + Math.abs(sin) * y,
    Math.abs(sin) * x + Math.abs(cos) * y,
  ];
  const [reachX, reachY] = reach(halfX, halfX / aspect);
  const fit = Math.min(1, world[0] / 2 / reachX, world[1] / 2 / reachY);
  const bounds = reach(halfX * fit, (halfX * fit) / aspect);
  const pan = [settings.panX, settings.panY];
  const center = flight.center.map((c, axis) => {
    const [low, high] = [bounds[axis], world[axis] - bounds[axis]];
    return Math.min(high, Math.max(low, c + (pan[axis] * (high - low)) / 2));
  }) as Vec2;
  return { center, half: [halfX * fit, (halfX * fit) / aspect], turn: [cos, sin] };
}
