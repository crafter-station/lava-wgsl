import { bilinear } from "./sample.wgsl";
import { Frame, reborn } from "./common.wgsl";

@group(0) @binding(0) var<uniform> frame: Frame;
@group(0) @binding(2) var flowTex: texture_2d<f32>;
@group(0) @binding(3) var coordsIn: texture_2d<f32>;
@group(0) @binding(4) var coordsOut: texture_storage_2d<rgba32float, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(coordsOut);
  if (id.x >= size.x || id.y >= size.y) {
    return;
  }
  let p = vec2f(id.xy) + 0.5;
  let flow = bilinear(flowTex, p / frame.world).xy;
  let origin = p - flow * frame.dt;
  let inside = clamp(origin, vec2f(0.5), frame.world - 0.5);
  let beyond = origin - inside;
  var coords = bilinear(coordsIn, inside / frame.world) + vec4f(beyond, beyond);
  if (reborn(frame, 0.0)) {
    coords = vec4f(p, coords.zw);
  }
  if (reborn(frame, 1.0)) {
    coords = vec4f(coords.xy, p);
  }
  textureStore(coordsOut, id.xy, coords);
}
