import { bilinear } from "./sample.wgsl";
struct Level {
  world: vec2f,
  guess: f32,
  refine: f32,
  drag: f32,
  reach: f32,
}

@group(0) @binding(0) var<uniform> level: Level;
@group(0) @binding(1) var terrainTex: texture_2d<f32>;
@group(0) @binding(2) var coarseTex: texture_2d<f32>;
@group(0) @binding(4) var psiIn: texture_2d<f32>;
@group(0) @binding(5) var psiOut: texture_storage_2d<r32float, write>;
@group(0) @binding(6) var anchorTex: texture_2d<f32>;

fn terrainAt(cell: vec2i, size: vec2i) -> vec4f {
  let terrain = vec2i(textureDimensions(terrainTex));
  let c = clamp(cell, vec2i(0), size - 1);
  let texel = min(vec2i((vec2f(c) + 0.5) / vec2f(size) * vec2f(terrain)), terrain - 1);
  return textureLoad(terrainTex, texel, 0);
}

fn known(cell: vec2u, size: vec2u) -> vec2f {
  let terrain = terrainAt(vec2i(cell), vec2i(size));
  if (terrain.b > 0.5 || terrain.r >= 0.0) {
    return terrain.gb;
  }
  let anchors = vec2u(textureDimensions(anchorTex));
  let texel = min(vec2u((vec2f(cell) + 0.5) / vec2f(size) * vec2f(anchors)), anchors - 1u);
  let anchor = textureLoad(anchorTex, texel, 0).rg;
  return vec2f(anchor.x, select(0.0, 1.0, anchor.y > 0.5));
}

const STONE = 400.0;

fn resistance(cell: vec2i, size: vec2i) -> f32 {
  let terrain = terrainAt(cell, size);
  if (terrain.r < 0.0 && terrain.b < 0.5) {
    return STONE;
  }
  return 1.0 + level.drag * exp(-max(terrain.r, 0.0) / level.reach);
}

fn value(cell: vec2i, size: vec2i) -> f32 {
  return textureLoad(psiIn, clamp(cell, vec2i(0), size - 1), 0).r;
}

@compute @workgroup_size(8, 8)
fn start(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(psiOut);
  if (id.x >= size.x || id.y >= size.y) {
    return;
  }
  let fixed = known(id.xy, size);
  let uv = (vec2f(id.xy) + 0.5) / vec2f(size);
  let coarse = bilinear(coarseTex, uv).r;
  let guess = select(level.guess, coarse, level.refine > 0.5);
  textureStore(psiOut, id.xy, vec4f(select(guess, fixed.x, fixed.y > 0.5), 0.0, 0.0, 0.0));
}

@compute @workgroup_size(8, 8)
fn relax(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(psiOut);
  if (id.x >= size.x || id.y >= size.y) {
    return;
  }
  let fixed = known(id.xy, size);
  let c = vec2i(id.xy);
  let s = vec2i(size);
  let own = resistance(c, s);
  var sum = 0.0;
  var weight = 0.0;
  for (var k = 0; k < 4; k++) {
    let step = array<vec2i, 4>(vec2i(1, 0), vec2i(-1, 0), vec2i(0, 1), vec2i(0, -1))[k];
    let w = own + resistance(c + step, s);
    sum += w * value(c + step, s);
    weight += w;
  }
  textureStore(psiOut, id.xy, vec4f(select(sum / weight, fixed.x, fixed.y > 0.5), 0.0, 0.0, 0.0));
}
