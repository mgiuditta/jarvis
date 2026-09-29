// Shapes batch (dev-1): same contract as shapes.js. Developer-tool homages: evoke, don't copy the logos.
Object.assign(ORB_SHAPES, {
  octocat: `
    vec3 q = p; q.x = abs(q.x);
    float head = ell(p - vec3(0., .25, 0.), vec3(.62, .48, .42));
    float ear = cap(q, vec3(.32, .45, 0.), vec3(.52, .8, 0.), .1);
    float d = smin(head, ear, .12);
    float body = ell(p - vec3(0., -.22, 0.), vec3(.36, .3, .3));
    d = smin(d, body, .12);
    float w = .04 * sin(uTime * 3. + p.x * 4.);
    float t1 = min(cap(q, vec3(.12, -.3, 0.), vec3(.2, -.72, .05), .09), cap(q, vec3(.2, -.72, .05), vec3(.08 + w, -.88, .1), .06));
    float t2 = min(cap(q, vec3(.25, -.25, 0.), vec3(.55, -.6, 0.), .09), cap(q, vec3(.55, -.6, 0.), vec3(.72, -.5 + w, 0.), .06));
    d = smin(d, min(t1, t2), .08);
    vec3 e = q - vec3(.22, .24, .4);
    d = max(d, -ell(e, vec3(.09, .13, .2)));
    return d;`,

  tanuki: `
    vec2 v[9]; v[0] = vec2(0., -.78); v[1] = vec2(.88, -.05); v[2] = vec2(.64, .72); v[3] = vec2(.38, .08); v[4] = vec2(-.38, .08);
    v[5] = vec2(-.64, .72); v[6] = vec2(-.88, -.05); v[7] = vec2(-.5, -.5); v[8] = vec2(.5, -.5);
    vec2 s = p.xy; float dd = 1e9, sg = 1.;
    for (int i = 0; i < 7; i++) {
      vec2 a = v[i], b = v[i == 6 ? 0 : i + 1];
      vec2 e = b - a, w = s - a, h = w - e * clamp(dot(w, e) / dot(e, e), 0., 1.);
      dd = min(dd, dot(h, h));
      bvec3 c = bvec3(s.y >= a.y, s.y < b.y, e.x * w.y > e.y * w.x);
      if (all(c) || all(not(c))) sg = -sg;
    }
    float poly = sg * sqrt(dd);
    float ax = abs(p.x);
    float front = min(min(.34 - .4 * ax + .15 * p.y, .12 + .5 * (p.y + .78)), .3 - .5 * (ax - .38) - .15 * (p.y - .08));
    float d = max(poly, max(p.z - front, -p.z - .12));
    return d;`,

  whale: `
    vec3 q = p - vec3(.05, -.32, 0.);
    float body = ell(q, vec3(.78, .3, .34));
    body = max(body, q.y - .14);
    float head = ell(q - vec3(.45, .02, 0.), vec3(.38, .26, .32));
    float d = smin(body, head, .1);
    float tail = cap(p, vec3(-.62, -.3, 0.), vec3(-.82, .02, 0.), .07);
    float fl = min(cap(p, vec3(-.82, .02, 0.), vec3(-.95, .16, 0.), .06), cap(p, vec3(-.82, .02, 0.), vec3(-.7, .18, 0.), .06));
    d = smin(d, min(tail, fl), .08);
    d = max(d, -(length(p - vec3(.6, -.26, .3)) - .05));
    float c = 1e9; const float S = .23;
    { vec3 b = p - vec3(-.44, -.06, 0.); b.x -= S * clamp(round(b.x / S), 0., 3.); c = min(c, box(b, vec3(.095, .095, .16), .015)); }
    { vec3 b = p - vec3(-.21, .17, 0.); b.x -= S * clamp(round(b.x / S), 0., 2.); c = min(c, box(b, vec3(.095, .095, .16), .015)); }
    c = min(c, box(p - vec3(.02, .4, 0.), vec3(.095, .095, .16), .015));
    return min(d, c);`,

  atom: `
    vec3 q0 = p; q0.xz = rot(.35 * sin(uTime * .5)) * q0.xz;
    float d = length(p) - .17;
    for (int i = 0; i < 3; i++) {
      vec3 q = q0; q.xy = rot(float(i) * 1.0472 + uTime * .25) * q.xy;
      vec2 ab = vec2(.86, .3);
      float k0 = length(q.xy / ab), k1 = length(q.xy / (ab * ab));
      float e = k0 * (k0 - 1.) / k1;
      d = min(d, length(vec2(e, q.z)) - .05);
    }
    return d;`,

  swallow: `
    vec3 q = p; q.xy = rot(-.5) * q.xy;
    float body = ell(q - vec3(0., .0, 0.), vec3(.18, .44, .17));
    float head = length(q - vec3(0., .4, .02)) - .16;
    float d = smin(body, head, .08);
    vec3 w = q; w.x = abs(w.x);
    vec2 c = w.xy - vec2(.45, -.35);
    float wing = max(max(length(c) - .72, -(length(c - vec2(.08, -.2)) - .66)), max(-w.x + .05, w.y - .5));
    wing = max(wing, abs(q.z) - .07);
    float tail = cap(w, vec3(.02, -.3, 0.), vec3(.24, -.84, 0.), .07);
    return smin(d, min(wing, tail), .05);`,

  snakes: `
    float d = 1e9;
    for (int i = 0; i < 2; i++) {
      vec3 q = i == 0 ? p : vec3(-p.x, -p.y, p.z);
      float head = box(q - vec3(-.12, .56, 0.), vec3(.32, .24, .14), .14);
      float col = box(q - vec3(-.55, .08, 0.), vec3(.24, .46, .14), .14);
      float band = box(q - vec3(-.18, .15, 0.), vec3(.46, .11, .14), .1);
      float s = min(min(head, col), band);
      s = max(s, -(length(q - vec3(-.26, .62, .15)) - .07));
      d = min(d, s);
    }
    return d;`,

  helm: `
    vec3 q = p; q.xy = rot(uTime * .3) * q.xy;
    float rim = torus(q.xzy, .58, .07);
    float hub = cyl(q.xzy, .17, .1);
    float a = atan(q.y, q.x), sec = 6.2832 / 7.;
    a = mod(a + sec * .5, sec) - sec * .5;
    vec3 s = vec3(length(q.xy) * cos(a), length(q.xy) * sin(a), q.z);
    float spoke = cap(s, vec3(.1, 0., 0.), vec3(.74, 0., 0.), .045);
    float knob = cap(s, vec3(.7, 0., 0.), vec3(.86, 0., 0.), .07);
    return min(min(rim, hub), min(spoke, knob));`,

  gopher: `
    vec3 q = p; q.x = abs(q.x);
    float body = ell(p - vec3(0., -.08, 0.), vec3(.6, .78, .5));
    float ear = length(q - vec3(.44, .62, -.05)) - .13;
    float d = smin(body, ear, .06);
    vec3 e = q - vec3(.24, .28, .36);
    float eye = length(e) - .2;
    d = min(d, eye);
    d = max(d, -(length(e - vec3(.05, 0., .2)) - .08));
    float snout = ell(p - vec3(0., -.02, .42), vec3(.2, .13, .14));
    d = smin(d, snout, .04);
    float nose = ell(p - vec3(0., .06, .56), vec3(.08, .05, .05));
    float teeth = box(q - vec3(.035, -.2, .48), vec3(.03, .07, .03), .01);
    float arm = cap(q, vec3(.52, -.25, .1), vec3(.68, -.35, .2), .08);
    return min(min(d, nose), min(teeth, arm));`,

  elephant: `
    p *= .86;
    float head = ell(p - vec3(.12, .25, 0.), vec3(.46, .44, .4));
    float ear = ell(p - vec3(-.42, .2, -.12), vec3(.36, .5, .09));
    float d = smin(head, ear, .08);
    vec3 a = vec3(.3, .05, .3), b = vec3(.34, -.4, .32), c = vec3(.46, -.66, .3), e = vec3(.66, -.58, .28);
    float trunk = min(cap(p, a, b, .15), min(cap(p, b, c, .11), cap(p, c, e, .08)));
    d = smin(d, trunk, .1);
    float tusk = cap(p, vec3(.05, -.08, .28), vec3(.0, -.32, .36), .045);
    d = min(d, tusk);
    d = max(d, -(length(p - vec3(.3, .35, .36)) - .06));
    return d / .86;`,

  shield: `
    vec2 s = vec2(abs(p.x), p.y);
    float sh = max(max(s.y - .84, dot(s - vec2(.8, .84), normalize(vec2(1., .09)))), dot(s - vec2(0., -.94), normalize(vec2(.66, -.62))));
    float d = max(sh, abs(p.z) - .1) - .02;
    float rim = max(d, -max(sh + .1, p.z - .02));
    float leg = cap(vec3(s, 0.), vec3(0., .5, 0.), vec3(.32, -.5, 0.), .075);
    float bar = cap(vec3(p.xy, 0.), vec3(-.17, -.12, 0.), vec3(.17, -.12, 0.), .065);
    return max(rim, -min(leg, bar));`,

  npmcube: `
    vec3 q = p; q.xz = rot(.785 + uTime * .2) * q.xz; q.yz = rot(-.6) * q.yz;
    const float S = .37;
    vec3 r = q - S * clamp(round(q / S), -1., 1.);
    return box(r, vec3(.155), .03);`,
});
