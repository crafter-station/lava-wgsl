import { noise2 } from "./noise.wgsl";

struct Shape {
  start: u32,
  count: u32,
  value: f32,
  pad: f32,
  low: vec2f,
  high: vec2f,
}

struct Outline {
  world: vec2f,
  origin: vec2f,
  traced: vec2f,
  shapes: u32,
  channels: u32,
}

@group(0) @binding(0) var<uniform> outline: Outline;
@group(0) @binding(1) var<storage, read> shapes: array<Shape>;
@group(0) @binding(2) var<storage, read> channels: array<Shape>;
@group(0) @binding(3) var<storage, read> points: array<vec2f>;
@group(0) @binding(4) var terrainOut: texture_storage_2d<rgba32float, write>;

const REACH = 40.0;
const SEAM = 36.0;

struct Rock {
  distance: f32,
  psi: f32,
}

fn segment(p: vec2f, a: vec2f, b: vec2f) -> f32 {
  let edge = b - a;
  let t = clamp(dot(p - a, edge) / max(dot(edge, edge), 1e-6), 0.0, 1.0);
  return length(p - a - edge * t);
}

fn onBorder(a: vec2f, b: vec2f) -> bool {
  let far = outline.traced - 1.0;
  return max(a.x, b.x) < 1.0 || min(a.x, b.x) > far.x || max(a.y, b.y) < 1.0 || min(a.y, b.y) > far.y;
}

fn tracedRock(p: vec2f) -> Rock {
  var distance = REACH;
  for (var s = 0u; s < outline.shapes; s++) {
    let shape = shapes[s];
    if (any(p < shape.low - REACH) || any(p > shape.high + REACH)) {
      continue;
    }
    var nearest = 1e9;
    var inside = false;
    var a = points[shape.start + shape.count - 1u];
    for (var i = 0u; i < shape.count; i++) {
      let b = points[shape.start + i];
      if (!onBorder(a, b)) {
        nearest = min(nearest, segment(p, a, b));
      }
      if ((a.y > p.y) != (b.y > p.y) && p.x < a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)) {
        inside = !inside;
      }
      a = b;
    }
    if (inside) {
      return Rock(-nearest, shape.value);
    }
    distance = min(distance, nearest);
  }
  return Rock(distance, 0.0);
}

fn shore(p: vec2f) -> f32 {
  return noise2(p / 55.0) * 11.0 + noise2(p / 17.0 + 3.1) * 4.0 + noise2(p / 6.0) * 1.2;
}

fn sideLava(point: vec2f, away: f32) -> f32 {
  let calm = smoothstep(0.0, 140.0, away);
  let p = point + vec2f(noise2(point / 190.0 + 4.0), noise2(point / 190.0 - 9.0)) * 55.0 * calm;
  let swell = mix(1.0, 0.72 + 0.5 * (noise2(point / 160.0 + 2.0) * 0.5 + 0.5), calm);
  var best = -REACH;
  for (var c = 0u; c < outline.channels; c++) {
    let channel = channels[c];
    var nearest = 1e9;
    for (var i = 1u; i < channel.count; i++) {
      nearest = min(nearest, segment(p, points[channel.start + i - 1u], points[channel.start + i]));
    }
    best = max(best, channel.value * swell - nearest);
  }
  return best;
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(terrainOut);
  if (id.x >= size.x || id.y >= size.y) {
    return;
  }
  let p = (vec2f(id.xy) + 0.5) * outline.world / vec2f(size);
  let local = p - outline.origin;
  let inside = clamp(local, vec2f(1.0), outline.traced - 1.0);
  let outside = length(local - clamp(local, vec2f(0.0), outline.traced));
  let traced = tracedRock(inside);
  if (outside <= 0.0) {
    textureStore(terrainOut, id.xy, vec4f(clamp(traced.distance, -REACH, REACH), traced.psi, select(0.0, 1.0, traced.distance < 0.0), 0.0));
    return;
  }
  let side = sideLava(p, outside) + shore(p) * mix(1.0, 1.8, smoothstep(0.0, 200.0, outside)) * smoothstep(0.0, SEAM, outside);
  let distance = mix(traced.distance, side, smoothstep(0.0, SEAM, outside));
  textureStore(terrainOut, id.xy, vec4f(clamp(distance, -REACH, REACH), 0.0, 0.0, 0.0));
}
