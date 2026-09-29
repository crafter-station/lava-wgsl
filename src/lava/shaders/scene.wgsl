import { Frame, generation, layerPhase, seedOf, unfilmic } from "./common.wgsl";
import { emission, SKY, sky } from "./light.wgsl";
import { cells, fbm, noise2, noised } from "./noise.wgsl";

@group(0) @binding(0) var<uniform> frame: Frame;
@group(0) @binding(1) var linearSampler: sampler;
@group(0) @binding(2) var surfaceTex: texture_2d<f32>;
@group(0) @binding(3) var flowTex: texture_2d<f32>;
@group(0) @binding(4) var platesTex: texture_2d<f32>;
@group(0) @binding(5) var lookupTex: texture_2d<f32>;
@group(0) @binding(6) var rockTex: texture_2d<f32>;

const SLOTS = 8;

fn worldUv(p: vec2f) -> vec2f {
  return p / frame.world;
}

struct Skin {
  tone: vec4f,
  slope: vec2f,
  raft: f32,
}

fn blend(a: Skin, b: Skin, t: f32) -> Skin {
  return Skin(mix(a.tone, b.tone, t), mix(a.slope, b.slope, t), mix(a.raft, b.raft, t));
}

fn crustAt(material: vec2f, motion: vec4f) -> Skin {
  let flow = motion.xy;
  let speed = length(flow);
  let along = select(vec2f(0.0, 1.0), flow / speed, speed > 1e-3);
  let stretch = mix(1.0, 3.6, smoothstep(2.0, 14.0, speed)) * mix(1.0, 2.2, smoothstep(0.08, 0.4, motion.w));
  let u = vec2f(along.y * material.x - along.x * material.y, dot(material, along) * 3.6 / stretch);
  let bend = vec2f(noise2(u / 40.0) * 7.0, 0.0);
  let rafts = fbm((u + bend) * vec2f(1.0 / 20.0, 1.0 / 95.0), 3);
  let tears = fbm((u + bend) * vec2f(1.0 / 5.0, 1.0 / 26.0) + 9.0, 2);
  let platelet = cells((u + bend) * vec2f(1.0 / 15.0, 1.0 / 24.0) + 5.0);
  let grain = (platelet.id - 0.5) * 1.2 + 0.5 * noise2(u * vec2f(0.9, 0.35) + 4.0);
  let speck = pow(max(noise2(u * vec2f(0.7, 0.25) + 21.0), 0.0), 2.0);
  let vein = pow(max(1.0 - abs(noise2((u + bend * 0.5) * vec2f(0.22, 0.035) + 41.0)), 0.0), 10.0);
  let across = vec2f(along.y, -along.x);
  let fine = noised(u * vec2f(1.0 / 2.0, 1.0 / 4.2));
  let coarse = noised(u * vec2f(1.0 / 5.0, 1.0 / 10.0) + 17.0);
  let slope = (across * (fine.y / 2.0 + coarse.y / 5.0 * 1.6) + along * (fine.z / 4.2 + coarse.z / 10.0 * 1.6) * 3.6 / stretch) * 1.4;
  let crowd = smoothstep(-0.2, 0.25, noise2(material / 160.0 + 51.0) * 0.5);
  var raft = 0.0;
  var dome = vec2f(0.0);
  if (crowd > 0.0) {
    let block = cells(material / 24.0 + 31.0);
    let reach = length(block.offset) + 0.12 * noise2(material / 3.0);
    raft = step(block.id, 0.11 * crowd) * smoothstep(0.42, 0.3, reach);
    dome = block.offset / max(reach, 0.05) * smoothstep(0.1, 0.42, reach) * raft * 2.2;
  }
  let seam = platelet.edge + 0.08 * tears + 0.05 * rafts;
  return Skin(vec4f(seam, grain, speck + 1.3 * vein, noise2(u * vec2f(0.3, 0.12) + 13.0)), slope + dome, raft);
}

fn carried(p: vec2f, id: f32, plate: vec4f, layer: i32) -> Skin {
  let columns = i32(textureDimensions(platesTex).x);
  let cell = vec2f(f32(i32(id) % columns), f32(i32(id) / columns));
  let seed = seedOf(frame, cell, f32(layer));
  let turn = vec2f(cos(plate.z), sin(plate.z));
  let offset = p - plate.xy;
  let material = seed + vec2f(turn.x * offset.x + turn.y * offset.y, turn.x * offset.y - turn.y * offset.x);
  let motion = textureSampleLevel(flowTex, linearSampler, worldUv(clamp(seed, vec2f(0.0), frame.world)), 0.0);
  return crustAt(material + f32(layer) * 311.0, motion);
}

fn crust(p: vec2f, layer: i32, px: f32) -> Skin {
  let cells = vec2i(textureDimensions(lookupTex)) / 2;
  let grid = vec2i(textureDimensions(platesTex)) / vec2i(1, 2);
  let cell = clamp(vec2i(floor(p / (frame.plate * 0.5))), vec2i(0), cells - 1) + vec2i(0, layer * cells.y);
  let near = textureLoad(lookupTex, cell, 0);
  let far = textureLoad(lookupTex, cell + vec2i(cells.x, 0), 0);
  let ids = array<f32, SLOTS>(near.x, near.y, near.z, near.w, far.x, far.y, far.z, far.w);

  var plates: array<vec4f, SLOTS>;
  var own = 0;
  var best = 1e12;
  for (var k = 0; k < SLOTS; k++) {
    let id = i32(max(ids[k], 0.0));
    plates[k] = textureLoad(platesTex, vec2i(id % grid.x, id / grid.x + layer * grid.y), 0);
    let apart = plates[k].xy - p;
    let d = select(dot(apart, apart), 1e12, ids[k] < 0.0);
    if (d < best) {
      best = d;
      own = k;
    }
  }
  var other = own;
  var edge = 1e9;
  for (var k = 0; k < SLOTS; k++) {
    let gap = plates[k].xy - plates[own].xy;
    let span = length(gap);
    if (k == own || ids[k] < 0.0 || span < 1e-3) {
      continue;
    }
    let d = dot(0.5 * (plates[k].xy + plates[own].xy) - p, gap / span);
    if (d < edge) {
      edge = d;
      other = k;
    }
  }
  let inside = carried(p, ids[own], plates[own], layer);
  let weight = clamp(0.5 + 0.5 * edge / (0.75 * px), 0.5, 1.0);
  if (weight >= 1.0) {
    return inside;
  }
  return blend(carried(p, ids[other], plates[other], layer), inside, weight);
}

fn layerWeight(layer: f32) -> f32 {
  return 1.0 - abs(2.0 * fract(layerPhase(frame, frame.time, layer)) - 1.0);
}

fn glint(slope: vec2f) -> f32 {
  let n = normalize(vec3f(-slope, 1.0));
  let mirror = vec3f(2.0 * n.z * n.xy, 2.0 * n.z * n.z - 1.0);
  return sky(mirror) / 0.3;
}

fn shadeLava(p: vec2f, surface: vec4f, px: f32) -> vec3f {
  let wa = layerWeight(0.0);
  let wb = layerWeight(1.0);
  var tone = vec4f(0.0);
  var slope = vec2f(0.0);
  var raft = 0.0;
  for (var layer = 0; layer < 2; layer++) {
    let w = select(wa, wb, layer == 1);
    let skin = crust(p, layer, px);
    tone += w * skin.tone;
    slope += w * skin.slope;
    raft = max(raft, skin.raft * w / max(wa, wb));
  }
  let seam = tone.x / (wa + wb);
  tone /= sqrt(wa * wa + wb * wb);
  slope /= wa + wb;
  let mean = surface.g + frame.heat;
  let streak = surface.a * frame.detail;
  let width = clamp(0.06 + (mean - 0.2) * 1.1 + 0.06 * streak, 0.0, 0.6);
  let open = 1.0 - smoothstep(width - 0.03, width + 0.03, mix(0.3, seam, frame.detail));
  let base = mix(mean * 0.72, mean * 1.3 + 0.08, open);
  let vein = pow(max(streak, 0.0), 3.0);
  let heat = (base + 0.12 * vein + frame.detail * (0.1 * tone.y + 0.14 * tone.z * mix(0.45, 1.0, open))) * (1.0 - raft);
  let relief = glint(slope * frame.detail);
  let sheen = surface.b * mix(0.5, 0.35, open) * (1.0 - 0.35 * streak) * mix(1.0, relief, frame.detail) * mix(1.0, 0.7, raft) * frame.sheen;
  return emission(heat) + max(sheen, 0.0) * mix(SKY, vec3f(0.95, 0.72, 1.0), 1.0 - open);
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let local = (uv * 2.0 - 1.0) * frame.viewHalf;
  let turn = frame.viewTurn;
  let p = frame.viewCenter + vec2f(turn.x * local.x - turn.y * local.y, turn.y * local.x + turn.x * local.y);
  let px = 2.0 * frame.viewHalf.y / frame.resolution.y;
  let surface = textureSampleLevel(surfaceTex, linearSampler, worldUv(p), 0.0);
  let coverage = smoothstep(-0.75 * px, 0.75 * px, surface.r);
  var color = pow(textureSampleLevel(rockTex, linearSampler, worldUv(p), 0.0).rgb, vec3f(2.2));
  if (coverage > 0.0) {
    color = mix(color, shadeLava(p, surface, px), coverage);
  }
  return vec4f(unfilmic(color) * frame.exposure, 1.0);
}
