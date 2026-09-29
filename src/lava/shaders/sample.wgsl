export fn bilinear(tex: texture_2d<f32>, uv: vec2f) -> vec4f {
  let size = vec2i(textureDimensions(tex));
  let p = uv * vec2f(size) - 0.5;
  let base = vec2i(floor(p));
  let f = p - floor(p);
  let a = clamp(base, vec2i(0), size - 1);
  let b = clamp(base + 1, vec2i(0), size - 1);
  let low = mix(textureLoad(tex, a, 0), textureLoad(tex, vec2i(b.x, a.y), 0), f.x);
  let high = mix(textureLoad(tex, vec2i(a.x, b.y), 0), textureLoad(tex, b, 0), f.x);
  return mix(low, high, f.y);
}
