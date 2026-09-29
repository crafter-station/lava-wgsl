@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var linearSampler: sampler;

fn tap(uv: vec2f) -> vec3f {
  return textureSampleLevel(source, linearSampler, uv, 0.0).rgb;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let h = 1.0 / vec2f(textureDimensions(source));
  var sum = tap(uv) * 4.0;
  sum += tap(uv - h) + tap(uv + h);
  sum += tap(uv + vec2f(h.x, -h.y)) + tap(uv - vec2f(h.x, -h.y));
  return vec4f(sum / 8.0, 1.0);
}
