import { bilinear } from "./sample.wgsl";
import { fbm, noise2 } from "./noise.wgsl";

struct Look {
  world: vec2f,
  origin: vec2f,
  seed: f32,
  blobs: u32,
}

@group(0) @binding(0) var<uniform> look: Look;
@group(0) @binding(1) var terrainTex: texture_2d<f32>;
@group(0) @binding(2) var flowTex: texture_2d<f32>;
@group(0) @binding(3) var linearSampler: sampler;
@group(0) @binding(4) var surfaceOut: texture_storage_2d<rgba16float, write>;
@group(0) @binding(5) var psiTex: texture_2d<f32>;
@group(0) @binding(6) var<storage, read> blobs: array<vec4f>;

fn warmth(p: vec2f) -> f32 {
  var sum = 0.0;
  for (var i = 0u; i < look.blobs; i++) {
    let blob = blobs[i];
    let apart = p - look.origin - blob.xy;
    sum += blob.w * exp(-dot(apart, apart) / (2.0 * blob.z * blob.z));
  }
  return sum;
}

fn filaments(psi: f32, p: vec2f) -> f32 {
  let wander = fbm(p / 260.0 + look.seed * 3.0, 2) * 300.0;
  let x = (psi + wander) / 120.0;
  let lines = noise2(vec2f(x, p.y / 500.0 + look.seed)) + 0.6 * noise2(vec2f(x * 2.3, p.y / 260.0 - look.seed)) + 0.35 * noise2(vec2f(x * 5.1, p.y / 150.0));
  let broken = smoothstep(-0.35, 0.45, fbm(p / 45.0 + look.seed * 5.0, 3));
  return lines * mix(0.25, 1.0, broken);
}

fn bump(x: f32, middle: f32, width: f32) -> f32 {
  let t = (x - middle) / width;
  return exp(-t * t);
}

fn raw(cell: vec2i) -> f32 {
  return textureLoad(terrainTex, clamp(cell, vec2i(0), vec2i(textureDimensions(terrainTex)) - 1), 0).r;
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(surfaceOut);
  if (id.x >= size.x || id.y >= size.y) {
    return;
  }
  let c = vec2i(id.xy);
  let h = look.world / vec2f(size);
  let p = (vec2f(c) + 0.5) * h;
  let slope = vec2f(raw(c + vec2i(1, 0)) - raw(c - vec2i(1, 0)), raw(c + vec2i(0, 1)) - raw(c - vec2i(0, 1))) / (2.0 * h);
  let distance = raw(c) / max(length(slope), 0.25);
  let shear = min(textureSampleLevel(flowTex, linearSampler, p / look.world, 0.0).a, 0.25);
  let near = bump(distance, 6.0, 3.0);
  let band = bump(distance, 14.0, 6.0);
  let drift = fbm(p / 120.0 + look.seed, 4);
  let psi = bilinear(psiTex, p / look.world).r;
  let streak = filaments(psi, p);
  let patchy = 2.2 * smoothstep(-0.05, 0.4, fbm(p / 55.0 - look.seed * 2.0, 3));
  let contact = exp(-max(distance, 0.0) / 3.0);
  let heat = 0.13 + (0.07 * near + 0.09 * band + 0.14 * contact) * patchy + 0.39 * shear + 0.8 * warmth(p) + 0.05 * drift + 0.04 * streak;
  let sheen = 0.0265 + 0.0063 * near - 0.003 * band - 0.0296 * shear + 0.006 * fbm(p / 90.0 - look.seed, 3);
  textureStore(surfaceOut, c, vec4f(distance, heat, sheen, streak));
}
