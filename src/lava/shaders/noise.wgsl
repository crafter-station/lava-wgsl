const ROT = mat2x2f(0.8, 0.6, -0.6, 0.8);

export fn hash21(p: vec2f) -> f32 {
  var q = fract(vec3f(p.xyx) * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

export fn hash22(p: vec2f) -> vec2f {
  var q = fract(vec3f(p.xyx) * vec3f(0.1031, 0.1030, 0.0973));
  q += dot(q, q.yzx + 33.33);
  return fract((q.xx + q.yz) * q.zy);
}

fn hash33(p: vec3f) -> vec3f {
  var q = fract(p * vec3f(0.1031, 0.1030, 0.0973));
  q += dot(q, q.yxz + 33.33);
  return fract((q.xxy + q.yxx) * q.zyx);
}

export fn noise2(p: vec2f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  let a = dot(hash22(i) * 2.0 - 1.0, f);
  let b = dot(hash22(i + vec2f(1.0, 0.0)) * 2.0 - 1.0, f - vec2f(1.0, 0.0));
  let c = dot(hash22(i + vec2f(0.0, 1.0)) * 2.0 - 1.0, f - vec2f(0.0, 1.0));
  let d = dot(hash22(i + vec2f(1.0, 1.0)) * 2.0 - 1.0, f - vec2f(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.4;
}

fn corner3(i: vec3f, f: vec3f, o: vec3f) -> f32 {
  return dot(hash33(i + o) * 2.0 - 1.0, f - o);
}

export fn noise3(p: vec3f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  let x00 = mix(corner3(i, f, vec3f(0.0, 0.0, 0.0)), corner3(i, f, vec3f(1.0, 0.0, 0.0)), u.x);
  let x10 = mix(corner3(i, f, vec3f(0.0, 1.0, 0.0)), corner3(i, f, vec3f(1.0, 1.0, 0.0)), u.x);
  let x01 = mix(corner3(i, f, vec3f(0.0, 0.0, 1.0)), corner3(i, f, vec3f(1.0, 0.0, 1.0)), u.x);
  let x11 = mix(corner3(i, f, vec3f(0.0, 1.0, 1.0)), corner3(i, f, vec3f(1.0, 1.0, 1.0)), u.x);
  return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z) * 1.3;
}

export fn fbm(p: vec2f, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var q = p;
  for (var i = 0; i < octaves; i++) {
    sum += amp * noise2(q);
    q = ROT * q * 2.03 + 1.7;
    amp *= 0.5;
  }
  return sum;
}

export fn ridged(p: vec2f, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var q = p;
  for (var i = 0; i < octaves; i++) {
    let r = 1.0 - abs(noise2(q));
    sum += amp * r * r;
    q = ROT * q * 2.07 + 3.1;
    amp *= 0.5;
  }
  return sum;
}

export struct Cell {
  edge: f32,
  id: f32,
  offset: vec2f,
}

export fn cells(x: vec2f) -> Cell {
  let n = floor(x);
  let f = fract(x);
  var nearest = vec2f(0.0);
  var home = vec2f(0.0);
  var best = 8.0;
  for (var j = -1; j <= 1; j++) {
    for (var i = -1; i <= 1; i++) {
      let g = vec2f(f32(i), f32(j));
      let r = g + hash22(n + g) * 0.8 + 0.1 - f;
      let d = dot(r, r);
      if (d < best) {
        best = d;
        nearest = r;
        home = g;
      }
    }
  }
  var edge = 8.0;
  for (var j = -1; j <= 1; j++) {
    for (var i = -1; i <= 1; i++) {
      let g = home + vec2f(f32(i), f32(j));
      let r = g + hash22(n + g) * 0.8 + 0.1 - f;
      let gap = r - nearest;
      if (dot(gap, gap) > 1e-5) {
        edge = min(edge, dot(0.5 * (nearest + r), normalize(gap)));
      }
    }
  }
  return Cell(edge, hash21(n + home), -nearest);
}

export fn noised(p: vec2f) -> vec3f {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  let du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
  let ga = hash22(i) * 2.0 - 1.0;
  let gb = hash22(i + vec2f(1.0, 0.0)) * 2.0 - 1.0;
  let gc = hash22(i + vec2f(0.0, 1.0)) * 2.0 - 1.0;
  let gd = hash22(i + vec2f(1.0, 1.0)) * 2.0 - 1.0;
  let va = dot(ga, f);
  let vb = dot(gb, f - vec2f(1.0, 0.0));
  let vc = dot(gc, f - vec2f(0.0, 1.0));
  let vd = dot(gd, f - vec2f(1.0, 1.0));
  let value = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * (va - vb - vc + vd);
  let slope = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
    + du * (u.yx * (va - vb - vc + vd) + vec2f(vb, vc) - va);
  return vec3f(value, slope) * 1.4;
}
