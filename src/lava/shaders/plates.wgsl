import { Frame, reborn, seedOf } from "./common.wgsl";

@group(0) @binding(0) var<uniform> frame: Frame;
@group(0) @binding(1) var linearSampler: sampler;
@group(0) @binding(2) var flowTex: texture_2d<f32>;
@group(0) @binding(3) var platesIn: texture_2d<f32>;
@group(0) @binding(4) var platesOut: texture_storage_2d<rgba32float, write>;

fn flowAt(p: vec2f) -> vec3f {
  return textureSampleLevel(flowTex, linearSampler, p / frame.world, 0.0).xyz;
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(platesOut);
  if (id.x >= size.x || id.y >= size.y) {
    return;
  }
  let rows = size.y / 2u;
  let layer = f32(id.y / rows);
  let cell = vec2f(f32(id.x), f32(id.y % rows));
  var plate = textureLoad(platesIn, vec2i(id.xy), 0);
  if (reborn(frame, layer)) {
    plate = vec4f(seedOf(frame, cell, layer), 0.0, 0.0);
  } else {
    let halfway = plate.xy + flowAt(plate.xy).xy * frame.dt * 0.5;
    let flow = flowAt(halfway);
    plate = vec4f(plate.xy + flow.xy * frame.dt, plate.z + flow.z * frame.spin * frame.dt, 0.0);
  }
  textureStore(platesOut, id.xy, plate);
}
