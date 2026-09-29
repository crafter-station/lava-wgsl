import { BASALT, emission, SUN } from "./light.wgsl";
import { cells, fbm, noise2 } from "./noise.wgsl";

struct Rock {
  world: vec2f,
  seed: f32,
}

@group(0) @binding(0) var<uniform> look: Rock;
@group(0) @binding(1) var surfaceTex: texture_2d<f32>;
@group(0) @binding(2) var linearSampler: sampler;
@group(0) @binding(3) var rockOut: texture_storage_2d<rgba8unorm, write>;

struct Ground {
  height: f32,
  crease: f32,
}

fn ground(p: vec2f) -> Ground {
  let q = p + vec2f(fbm(p / 160.0 + look.seed, 3), fbm(p / 160.0 + look.seed + 5.2, 3)) * 55.0;
  let bent = q + vec2f(fbm(q / 45.0, 3), fbm(q / 45.0 + 3.3, 3)) * 34.0;
  let toe = cells(bent / 72.0);
  let dome = sqrt(clamp(toe.edge / 0.45, 0.0, 1.0)) * (0.6 + 0.6 * toe.id);
  let lobes = fbm(q / 130.0, 3);
  let buds = fbm(q / 30.0 + 7.0, 2);
  let ropy = smoothstep(0.15, 0.5, fract(toe.id * 7.1)) * smoothstep(0.03, 0.1, toe.edge) * (1.0 - smoothstep(0.18, 0.34, toe.edge));
  let wave = 0.5 + 0.5 * sin(toe.edge * 72.0 / 3.6 * 6.2832 + noise2(bent / 11.0) * 1.5);
  let rope = wave * wave * ropy;
  let grit = noise2(p / 1.3) * 0.35 + noise2(p / 3.2) * 0.45;
  let height = 34.0 * dome + 40.0 * lobes + 8.0 * buds + 2.2 * rope + grit;
  let crease = smoothstep(0.0, 0.09, toe.edge) * smoothstep(-0.5, 0.2, buds);
  return Ground(height, crease);
}

fn gloss(r: vec3f) -> f32 {
  let horizon = 1.0 - clamp(r.z, 0.0, 1.0);
  return 0.015 + 0.3 * horizon * horizon * horizon + 3.2 * pow(max(dot(r, normalize(SUN)), 0.0), 12.0);
}

fn shadeRock(p: vec2f, surface: vec4f, e: f32) -> vec3f {
  let here = ground(p);
  let hx = ground(p + vec2f(e, 0.0)).height;
  let hy = ground(p + vec2f(0.0, e)).height;
  let n = normalize(vec3f(-(hx - here.height) / e, -(hy - here.height) / e, 1.0));
  let mirror = vec3f(2.0 * n.z * n.xy, 2.0 * n.z * n.z - 1.0);
  let fresnel = 0.04 + 0.96 * pow(1.0 - n.z, 5.0);
  let occlusion = mix(0.05, 1.0, here.crease);
  let tone = 0.8 + 0.4 * noise2(p / 23.0 + look.seed);
  let diffuse = BASALT * tone * (0.25 + 2.2 * pow(max(dot(n, normalize(SUN)), 0.0), 2.0)) * occlusion;
  let specular = vec3f(0.7, 0.8, 1.1) * fresnel * gloss(mirror) * occlusion * 0.36;
  let glow = emission(0.4) * 0.6 * exp(surface.r / 1.5);
  return diffuse + specular + glow;
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(rockOut);
  if (id.x >= size.x || id.y >= size.y) {
    return;
  }
  let p = (vec2f(id.xy) + 0.5) * look.world / vec2f(size);
  let surface = textureSampleLevel(surfaceTex, linearSampler, p / look.world, 0.0);
  let color = shadeRock(p, surface, look.world.y / f32(size.y));
  textureStore(rockOut, id.xy, vec4f(pow(max(color, vec3f(0.0)), vec3f(1.0 / 2.2)), 1.0));
}
