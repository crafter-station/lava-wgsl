struct Grid {
  world: vec2f,
  gain: f32,
}

@group(0) @binding(0) var<uniform> grid: Grid;
@group(0) @binding(1) var psiTex: texture_2d<f32>;
@group(0) @binding(2) var flowOut: texture_storage_2d<rgba32float, write>;

fn psi(cell: vec2i) -> f32 {
  return textureLoad(psiTex, clamp(cell, vec2i(0), vec2i(textureDimensions(psiTex)) - 1), 0).r;
}

fn velocity(cell: vec2i, h: vec2f) -> vec2f {
  let dx = (psi(cell + vec2i(1, 0)) - psi(cell - vec2i(1, 0))) / (2.0 * h.x);
  let dy = (psi(cell + vec2i(0, 1)) - psi(cell - vec2i(0, 1))) / (2.0 * h.y);
  return vec2f(-dy, dx) * grid.gain;
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(flowOut);
  if (id.x >= size.x || id.y >= size.y) {
    return;
  }
  let c = vec2i(id.xy);
  let h = grid.world / vec2f(size);
  let ux = (velocity(c + vec2i(1, 0), h) - velocity(c - vec2i(1, 0), h)) / (2.0 * h.x);
  let uy = (velocity(c + vec2i(0, 1), h) - velocity(c - vec2i(0, 1), h)) / (2.0 * h.y);
  let spin = 0.5 * (ux.y - uy.x);
  let strain = 0.5 * length(vec2f(ux.x - uy.y, uy.x + ux.y));
  textureStore(flowOut, c, vec4f(velocity(c, h), spin, strain));
}
