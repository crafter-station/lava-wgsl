import { bilinear } from "./sample.wgsl";
import { Frame } from "./common.wgsl";

@group(0) @binding(0) var<uniform> frame: Frame;
@group(0) @binding(2) var coordsTex: texture_2d<f32>;
@group(0) @binding(3) var platesTex: texture_2d<f32>;
@group(0) @binding(4) var lookupOut: texture_storage_2d<rgba32float, write>;

const REACH = 3;
const SLOTS = 8;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let cells = textureDimensions(lookupOut) / 2u;
  if (id.x >= cells.x || id.y >= cells.y * 2u) {
    return;
  }
  let layer = i32(id.y / cells.y);
  let cell = vec2f(f32(id.x), f32(id.y % cells.y));
  let q = (cell + 0.5) * frame.plate * 0.5;
  let coords = bilinear(coordsTex, q / frame.world);
  let material = select(coords.xy, coords.zw, layer == 1);

  let grid = vec2i(textureDimensions(platesTex)) / vec2i(1, 2);
  let home = vec2i(floor((material + frame.pad) / frame.plate));
  var ids: array<f32, SLOTS>;
  var far: array<f32, SLOTS>;
  for (var k = 0; k < SLOTS; k++) {
    ids[k] = -1.0;
    far[k] = 1e12;
  }
  for (var j = -REACH; j <= REACH; j++) {
    for (var i = -REACH; i <= REACH; i++) {
      let c = home + vec2i(i, j);
      if (any(c < vec2i(0)) || any(c >= grid)) {
        continue;
      }
      let plate = textureLoad(platesTex, c + vec2i(0, layer * grid.y), 0);
      let apart = plate.xy - q;
      let d = dot(apart, apart);
      if (d >= far[SLOTS - 1]) {
        continue;
      }
      var k = SLOTS - 1;
      while (k > 0 && far[k - 1] > d) {
        far[k] = far[k - 1];
        ids[k] = ids[k - 1];
        k--;
      }
      far[k] = d;
      ids[k] = f32(c.x + c.y * grid.x);
    }
  }
  textureStore(lookupOut, id.xy, vec4f(ids[0], ids[1], ids[2], ids[3]));
  textureStore(lookupOut, id.xy + vec2u(cells.x, 0u), vec4f(ids[4], ids[5], ids[6], ids[7]));
}
