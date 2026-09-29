import { filmic } from "./common.wgsl";
import { hash21, noise3 } from "./noise.wgsl";

struct Present {
  time: f32,
  bloom: f32,
  haze: f32,
  grain: f32,
}

@group(0) @binding(0) var<uniform> present: Present;
@group(0) @binding(1) var hdrTex: texture_2d<f32>;
@group(0) @binding(2) var bloomTex: texture_2d<f32>;
@group(0) @binding(3) var linearSampler: sampler;

fn toSrgb(c: vec3f) -> vec3f {
  return select(1.055 * pow(c, vec3f(1.0 / 2.4)) - 0.055, c * 12.92, c <= vec3f(0.0031308));
}

@fragment
fn fs_main(@builtin(position) position: vec4f, @location(0) uv: vec2f) -> @location(0) vec4f {
  let size = vec2f(textureDimensions(hdrTex));
  let glow = textureSampleLevel(bloomTex, linearSampler, uv, 0.0).rgb;
  let heat = clamp(dot(glow, vec3f(0.5, 0.35, 0.15)) * 0.8, 0.0, 1.0);
  let q = vec3f(uv * vec2f(size.x / size.y, 1.0) * 18.0 + vec2f(0.0, present.time * 0.9), present.time * 0.6);
  var shimmer = vec2f(0.0);
  if (present.haze * heat > 0.0) {
    shimmer = vec2f(noise3(q), noise3(q + 17.3)) * present.haze * heat;
  }
  let hdr = textureSampleLevel(hdrTex, linearSampler, uv + shimmer, 0.0).rgb;

  let color = filmic(hdr + glow * present.bloom);
  let luma = dot(color, vec3f(0.2126, 0.7152, 0.0722));
  var srgb = toSrgb(color);
  let grain = hash21(position.xy + fract(present.time * 7.13) * 431.0) - 0.5;
  srgb += grain * present.grain * (1.0 - luma * 0.6);
  return vec4f(srgb, 1.0);
}
