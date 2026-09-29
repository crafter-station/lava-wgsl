@group(0) @binding(0) var terrainTex: texture_2d<f32>;
@group(0) @binding(1) var anchorIn: texture_2d<f32>;
@group(0) @binding(2) var anchorOut: texture_storage_2d<rg32float, write>;

const LAVA = -1.0;
const OPEN = 0.0;
const HELD = 1.0;

fn terrainAt(cell: vec2u, size: vec2u) -> vec4f {
  let terrain = textureDimensions(terrainTex);
  let texel = min(vec2u((vec2f(cell) + 0.5) / vec2f(size) * vec2f(terrain)), terrain - 1u);
  return textureLoad(terrainTex, texel, 0);
}

@compute @workgroup_size(8, 8)
fn start(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(anchorOut);
  if (id.x >= size.x || id.y >= size.y) {
    return;
  }
  let terrain = terrainAt(id.xy, size);
  let state = select(select(OPEN, HELD, terrain.b > 0.5), LAVA, terrain.r >= 0.0);
  textureStore(anchorOut, id.xy, vec4f(terrain.g, state, 0.0, 0.0));
}

@compute @workgroup_size(8, 8)
fn spread(@builtin(global_invocation_id) id: vec3u) {
  let size = vec2i(textureDimensions(anchorOut));
  let c = vec2i(id.xy);
  if (c.x >= size.x || c.y >= size.y) {
    return;
  }
  let own = textureLoad(anchorIn, c, 0).rg;
  if (own.y != OPEN) {
    textureStore(anchorOut, c, vec4f(own, 0.0, 0.0));
    return;
  }
  var sum = 0.0;
  var count = 0.0;
  for (var k = 0; k < 4; k++) {
    let step = array<vec2i, 4>(vec2i(1, 0), vec2i(-1, 0), vec2i(0, 1), vec2i(0, -1))[k];
    let next = clamp(c + step, vec2i(0), size - 1);
    let other = textureLoad(anchorIn, next, 0).rg;
    if (other.y == HELD) {
      sum += other.x;
      count += 1.0;
    }
  }
  let held = count > 0.0;
  textureStore(anchorOut, c, vec4f(select(0.0, sum / max(count, 1.0), held), select(OPEN, HELD, held), 0.0, 0.0));
}
