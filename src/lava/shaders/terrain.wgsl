import { fbm, hash21, hash22, noise2 } from "./noise.wgsl";

struct Terrain {
  world: vec2f,
  seed: f32,
  width: f32,
  land: f32,
  islands: f32,
  meander: f32,
  flux: f32,
}

struct Channel {
  across: f32,
  width: f32,
}

@group(0) @binding(0) var<uniform> terrain: Terrain;
@group(0) @binding(1) var terrainOut: texture_storage_2d<rgba32float, write>;

const PLUG = 0.8;
const ISLAND_SPAN = 1.25;

fn spacing() -> f32 {
  return 2.0 * terrain.width + terrain.land;
}

fn salt(k: f32) -> f32 {
  return terrain.seed * 7.31 + k * 13.7;
}

fn centerOf(k: f32, y: f32) -> f32 {
  let bend = fbm(vec2f(y / 900.0, salt(k)), 3) * spacing() * 0.35 * terrain.meander;
  return terrain.world.x * 0.5 + k * spacing() + bend;
}

fn widthOf(k: f32, y: f32) -> f32 {
  return terrain.width * (1.0 + 0.35 * fbm(vec2f(y / 650.0, salt(k) + 5.0), 3));
}

fn shore(p: vec2f) -> f32 {
  return noise2(p / 55.0 + terrain.seed) * 14.0 + noise2(p / 17.0 - terrain.seed) * 5.0 + noise2(p / 6.0) * 1.5;
}

fn channel(k: f32, p: vec2f, rough: f32) -> Channel {
  let width = widthOf(k, p.y);
  return Channel((p.x + shore(p) * rough - centerOf(k, p.y)) / width, width);
}

fn carried(s: f32) -> f32 {
  let c = clamp(s, -1.0, 1.0);
  return 0.5 + 0.5 * (c - c * c * c * c * c / 5.0) / PLUG;
}

fn nearest(p: vec2f) -> f32 {
  return round((p.x - terrain.world.x * 0.5) / spacing());
}

fn stream(p: vec2f) -> f32 {
  let home = nearest(p);
  var psi = (home - 1.0) * terrain.flux;
  for (var k = home - 1.0; k <= home + 1.0; k += 1.0) {
    psi += terrain.flux * carried(channel(k, p, 0.0).across);
  }
  return psi;
}

fn banks(p: vec2f) -> f32 {
  let home = nearest(p);
  var inside = -1e4;
  for (var k = home - 1.0; k <= home + 1.0; k += 1.0) {
    let c = channel(k, p, 1.0);
    inside = max(inside, (1.0 - abs(c.across)) * c.width);
  }
  return inside;
}

struct Island {
  center: vec2f,
  radius: vec2f,
  angle: f32,
  id: f32,
}

fn islandAt(k: f32, row: f32) -> Island {
  let span = terrain.width * ISLAND_SPAN;
  let h = hash22(vec2f(k * 7.0 + salt(0.0), row));
  let y = (row + 0.2 + 0.6 * h.y) * span;
  let width = widthOf(k, y);
  let size = mix(0.07, 0.42, h.x * h.x) * width;
  let x = centerOf(k, y) + (hash21(vec2f(row, k + salt(1.0))) - 0.5) * 1.3 * (width - size);
  let slope = (centerOf(k, y + 40.0) - centerOf(k, y - 40.0)) / 80.0;
  let stretch = mix(1.1, 2.1, hash21(vec2f(k, row + 9.0)));
  let id = hash21(vec2f(row * 3.1 + k, salt(2.0)));
  return Island(vec2f(x, y), vec2f(size, size * stretch), atan(slope) + (id - 0.5) * 0.6, id);
}

fn islandDistance(p: vec2f, island: Island, rough: f32) -> f32 {
  let c = cos(island.angle);
  let s = sin(island.angle);
  let d = p - island.center;
  let q = vec2f(c * d.x - s * d.y, s * d.x + c * d.y);
  let r = min(island.radius.x, island.radius.y);
  let ellipse = (length(q / island.radius) - 1.0) * r;
  let lobes = fbm(p / (r * 0.9) + island.id * 31.0, select(2, 5, rough > 0.0)) * 0.55 * r;
  return ellipse + lobes + shore(p) * 0.6 * rough;
}

fn exists(k: f32, row: f32) -> bool {
  return hash21(vec2f(row + salt(3.0), k * 5.0)) < terrain.islands;
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(terrainOut);
  if (id.x >= size.x || id.y >= size.y) {
    return;
  }
  let p = (vec2f(id.xy) + 0.5) * terrain.world / vec2f(size);
  var psi = stream(p);
  var inside = banks(p);
  var rock = 1e4;
  let home = nearest(p);
  let span = terrain.width * ISLAND_SPAN;
  let row = floor(p.y / span);
  for (var k = home - 1.0; k <= home + 1.0; k += 1.0) {
    for (var r = row - 2.0; r <= row + 2.0; r += 1.0) {
      if (!exists(k, r)) {
        continue;
      }
      let island = islandAt(k, r);
      let reach = 12.0 + 0.45 * min(island.radius.x, island.radius.y);
      psi = mix(stream(island.center), psi, smoothstep(0.0, reach, islandDistance(p, island, 0.0)));
      rock = min(rock, islandDistance(p, island, 1.0));
    }
  }
  textureStore(terrainOut, id.xy, vec4f(min(inside, rock), psi, 1.0, 0.0));
}
