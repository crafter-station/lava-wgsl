import { hash22 } from "./noise.wgsl";

export struct Frame {
  resolution: vec2f,
  world: vec2f,
  viewCenter: vec2f,
  viewHalf: vec2f,
  viewTurn: vec2f,
  time: f32,
  dt: f32,
  exposure: f32,
  plate: f32,
  pad: f32,
  life: f32,
  spin: f32,
  detail: f32,
  sheen: f32,
  heat: f32,
  seed: f32,
}

export fn layerPhase(frame: Frame, time: f32, layer: f32) -> f32 {
  return time / frame.life + 0.5 * layer;
}

export fn generation(frame: Frame, time: f32, layer: f32) -> f32 {
  return floor(layerPhase(frame, time, layer));
}

export fn reborn(frame: Frame, layer: f32) -> bool {
  return frame.dt == 0.0 || generation(frame, frame.time, layer) != generation(frame, frame.time - frame.dt, layer);
}

export fn seedOf(frame: Frame, cell: vec2f, layer: f32) -> vec2f {
  let born = generation(frame, frame.time, layer);
  let jitter = hash22(cell + vec2f(17.0 * layer + 3.0, 31.0 * born + 7.0));
  return (cell + 0.15 + 0.7 * jitter) * frame.plate - frame.pad;
}

export fn filmic(x: vec3f) -> vec3f {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3f(0.0), vec3f(1.0));
}

export fn unfilmic(display: vec3f) -> vec3f {
  let y = min(display, vec3f(0.97));
  let p = 0.03 - 0.59 * y;
  let q = 2.51 - 2.43 * y;
  return (-p + sqrt(p * p + 0.56 * y * q)) / (2.0 * q);
}
