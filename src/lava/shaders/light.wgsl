export const SKY = vec3f(0.81, 0.8, 1.0);
export const SUN = vec3f(-0.38, -0.52, 0.76);
export const BASALT = vec3f(0.0021, 0.0024, 0.0064);

fn sigmoid(h: f32, scale: f32, middle: f32, width: f32, power: f32) -> f32 {
  return scale / pow(1.0 + exp(-(h - middle) / width), power);
}

export fn emission(heat: f32) -> vec3f {
  let h = clamp(heat, 0.0, 1.0);
  return vec3f(
    sigmoid(h, 1.0988, -0.1203, 0.225, 10.0),
    sigmoid(h, 1.0244, 0.8333, 0.1287, 1.2823),
    sigmoid(h, 0.1225, 0.446, 0.1778, 10.0),
  );
}

export fn sky(r: vec3f) -> f32 {
  let horizon = 1.0 - clamp(r.z, 0.0, 1.0);
  return 0.05 + 0.35 * horizon * horizon * horizon + 1.6 * pow(max(dot(r, normalize(SUN)), 0.0), 5.0);
}

