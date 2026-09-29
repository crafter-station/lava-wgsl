@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var linearSampler: sampler;

fn tap(uv: vec2f) -> vec3f {
  return textureSampleLevel(source, linearSampler, uv, 0.0).rgb;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let h = 0.5 / vec2f(textureDimensions(source));
  var sum = tap(uv + vec2f(-2.0 * h.x, 0.0)) + tap(uv + vec2f(2.0 * h.x, 0.0));
  sum += tap(uv + vec2f(0.0, -2.0 * h.y)) + tap(uv + vec2f(0.0, 2.0 * h.y));
  sum += (tap(uv + h) + tap(uv - h) + tap(uv + vec2f(h.x, -h.y)) + tap(uv - vec2f(h.x, -h.y))) * 2.0;
  return vec4f(sum / 12.0, 1.0);
}
