// Shapes batch (objects-2): same contract as shapes.js. Time, data, media, weather.
Object.assign(ORB_SHAPES, {
  clock: `
    vec3 q = p.xzy;
    float face = cyl(q, .8, .08);
    float rim = torus(q, .82, .1);
    float a = uTime * .6;
    vec2 m = rot(a) * vec2(0., .56), h = rot(a * .1) * vec2(.36, 0.);
    float hands = min(cap(p, vec3(0., 0., .16), vec3(m, .16), .075), cap(p, vec3(0., 0., .16), vec3(h, .16), .095));
    hands = min(hands, length(p - vec3(0., 0., .14)) - .12);
    float ticks = 1e9;
    for (int i = 0; i < 4; i++) { float t = float(i) * 1.5708; ticks = min(ticks, length(p - vec3(cos(t) * .62, sin(t) * .62, .1)) - .085); }
    return min(min(face, rim), min(hands, ticks));`,

  hourglass: `
    vec3 s = p; s.xy = rot(.12 * sin(uTime * .8)) * s.xy;
    vec3 m = vec3(s.x, abs(s.y), s.z);
    float glass = rcone(m - vec3(0., .02, 0.), .09, .44, .62);
    float plates = cyl(m - vec3(0., .8, 0.), .62, .07);
    float posts = cap(vec3(abs(s.x), s.y, s.z), vec3(.52, -.74, 0.), vec3(.52, .74, 0.), .05);
    return min(min(glass, plates), posts);`,

  alarm: `
    vec3 s = p; s.xy = rot(.06 * sin(uTime * 30.)) * s.xy;
    vec3 q = (s - vec3(0., -.1, 0.)).xzy;
    float body = cyl(q, .6, .18);
    float rim = torus(q, .6, .09);
    vec3 b = vec3(abs(s.x), s.y, s.z);
    vec3 bq = b - vec3(.42, .62, 0.); bq.xy = rot(-.6) * bq.xy;
    float bells = ell(bq, vec3(.27, .15, .22));
    float knob = length(s - vec3(0., .62, 0.)) - .08;
    float legs = cap(b, vec3(.34, -.62, 0.), vec3(.5, -.9, 0.), .065);
    float hands = min(cap(s, vec3(0., -.1, .22), vec3(0., .26, .22), .05), cap(s, vec3(0., -.1, .22), vec3(.24, -.1, .22), .05));
    return min(min(min(body, rim), min(bells, knob)), min(legs, hands));`,

  chart: `
    float d = cap(p, vec3(-.9, -.78, 0.), vec3(.9, -.78, 0.), .05);
    d = min(d, cap(p, vec3(-.9, -.78, 0.), vec3(-.9, .8, 0.), .05));
    for (int i = 0; i < 4; i++) {
      float x = -.55 + float(i) * .38, h = .16 + .16 * float(i) + .04 * sin(uTime * 2. + float(i));
      d = min(d, box(p - vec3(x, -.7 + h, 0.), vec3(.13, h, .12), .03));
    }
    return d;`,

  coin: `
    vec3 q = p.xzy;
    float disc = cyl(q, .8, .09);
    float rim = torus(q, .8, .1);
    float ring = length(vec2(length(p.xy) - .62, p.z - .09)) - .035;
    float arc = max(length(vec2(length(p.xy) - .3, p.z - .1)) - .055, p.x - .14);
    float bars = min(cap(p, vec3(-.42, .07, .1), vec3(.02, .07, .1), .045), cap(p, vec3(-.42, -.09, .1), vec3(.02, -.09, .1), .045));
    return min(min(disc, rim), min(ring, min(arc, bars)));`,

  cart: `
    vec3 q = p - vec3(.1, .1, 0.);
    float b = box(q, vec3(.62, .34, .22), .06);
    b = max(b, dot(vec2(abs(q.x), q.y), normalize(vec2(1., -.5))) - .45);
    for (int i = 0; i < 3; i++) b = max(b, -box(q - vec3(-.3 + float(i) * .3, .02, .22), vec3(.045, .2, .1), .02));
    float handle = cap(p, vec3(-.5, .44, 0.), vec3(-.95, .66, 0.), .065);
    float axle = cap(p, vec3(-.32, -.4, 0.), vec3(.55, -.4, 0.), .05);
    float wheels = min(length(p - vec3(-.25, -.64, 0.)) - .14, length(p - vec3(.45, -.64, 0.)) - .14);
    return min(min(b, handle), min(axle, wheels));`,

  piggy: `
    vec3 s = p - vec3(-.05, .05, 0.);
    float body = ell(s, vec3(.75, .55, .5));
    float snout = cyl((s - vec3(.72, -.02, 0.)).yxz, .2, .13);
    vec3 e = vec3(s.x, s.y, abs(s.z));
    float ears = rcone(e - vec3(.35, .38, .22), .14, .03, .28);
    vec3 l = vec3(abs(s.x + .02) , s.y, abs(s.z));
    float legs = cap(l, vec3(.4, -.3, .25), vec3(.4, -.72, .25), .11);
    float slot = box(s - vec3(-.05, .56, 0.), vec3(.2, .06, .03), .01);
    float tail = torus((s - vec3(-.8, .1, 0.)).yzx, .1, .03);
    return max(min(min(min(body, snout), ears), min(legs, tail)), -slot);`,

  calculator: `
    float b = box(p, vec3(.62, .88, .1), .08);
    b = max(b, -box(p - vec3(0., .56, .13), vec3(.48, .16, .06), .02));
    vec2 q = p.xy - vec2(0., -.28);
    vec2 id = vec2(clamp(floor(q.x / .34 + .5), -1., 1.), clamp(floor(q.y / .26) + .5, -1.5, 1.5));
    vec2 l = q - id * vec2(.34, .26);
    float keys = box(vec3(l, p.z - .12), vec3(.12, .085, .05), .03);
    return min(b, keys);`,

  note: `
    vec3 s = p - vec3(0., .05 * sin(uTime * 3.), 0.);
    vec3 h1 = s - vec3(-.42, -.52, 0.); h1.xy = rot(.45) * h1.xy;
    vec3 h2 = s - vec3(.4, -.32, 0.); h2.xy = rot(.45) * h2.xy;
    float heads = min(ell(h1, vec3(.25, .17, .13)), ell(h2, vec3(.25, .17, .13)));
    float stems = min(cap(s, vec3(-.2, -.48, 0.), vec3(-.2, .6, 0.), .05), cap(s, vec3(.62, -.28, 0.), vec3(.62, .8, 0.), .05));
    vec3 bq = s - vec3(.21, .72, 0.); bq.xy = rot(-.235) * bq.xy;
    float beam = box(bq, vec3(.44, .08, .07), .02);
    return min(min(heads, stems), beam);`,

  headphones: `
    float band = max(torus(p.xzy - vec3(0., 0., .05), .68, .08), -p.y - .1);
    vec3 m = vec3(abs(p.x), p.y, p.z);
    float cups = ell(m - vec3(.68, -.22, 0.), vec3(.2, .34, .28));
    float pads = ell(m - vec3(.54, -.22, 0.), vec3(.1, .3, .24));
    return min(band, smin(cups, pads, .05));`,

  camera: `
    float body = box(p - vec3(0., -.1, 0.), vec3(.88, .55, .22), .1);
    float hump = box(p - vec3(-.3, .5, 0.), vec3(.28, .1, .18), .05);
    float button = cyl(p - vec3(.52, .5, 0.), .11, .07);
    vec3 lq = (p - vec3(.05, -.12, .2)).xzy;
    float lens = cyl(lq, .38, .16);
    lens = max(lens, -cyl(lq - vec3(0., .2, 0.), .24, .1));
    float glass = length(p - vec3(.05, -.12, .06)) - .26;
    float ring = torus(lq - vec3(0., .16, 0.), .38, .05);
    return min(min(min(body, hump), button), min(min(lens, glass), ring));`,

  film: `
    vec3 s = p; s.xy = rot(uTime * .5) * s.xy;
    vec3 q = s.xzy;
    float reel = cyl(q, .82, .09);
    for (int i = 0; i < 5; i++) { float a = float(i) * 1.2566; reel = max(reel, -(length(s.xy - vec2(cos(a), sin(a)) * .46) - .17)); }
    float hub = cyl(q, .12, .14);
    float rim = torus(q, .82, .07);
    return min(min(reel, hub), rim);`,

  mic: `
    float head = ell(p - vec3(0., .38, 0.), vec3(.34, .44, .34));
    float band = torus(p - vec3(0., .3, 0.), .35, .045);
    float holder = max(torus(p.xzy - vec3(0., 0., .2), .45, .05), p.y - .2);
    float stem = cap(p, vec3(0., -.25, 0.), vec3(0., -.8, 0.), .06);
    float base = ell(p - vec3(0., -.85, 0.), vec3(.42, .08, .3));
    return min(min(head, band), min(min(holder, stem), base));`,

  sun: `
    vec3 s = p; s.xy = rot(uTime * .3) * s.xy;
    float d = length(p) - .48;
    for (int i = 0; i < 8; i++) { float a = float(i) * .7854; vec2 c = vec2(cos(a), sin(a));
      d = min(d, cap(s, vec3(c * .64, 0.), vec3(c * (.9 + .04 * sin(uTime * 3. + float(i))), 0.), .07)); }
    return d;`,

  cloud: `
    vec3 s = p - vec3(.04 * sin(uTime), 0., 0.);
    float d = length((s - vec3(-.48, -.12, 0.)) * vec3(1., 1., 1.4)) / 1.4 - .34;
    d = smin(d, length((s - vec3(.02, .14, 0.)) * vec3(1., 1., 1.4)) / 1.4 - .46, .12);
    d = smin(d, length((s - vec3(.5, -.06, 0.)) * vec3(1., 1., 1.4)) / 1.4 - .36, .12);
    d = smin(d, box(s - vec3(0., -.28, 0.), vec3(.72, .18, .22), .18), .12);
    return d;`,

  rain: `
    vec3 s = p - vec3(0., .38, 0.);
    float d = length(s - vec3(-.4, -.08, 0.)) - .28;
    d = smin(d, length(s - vec3(.02, .12, 0.)) - .38, .1);
    d = smin(d, length(s - vec3(.42, -.04, 0.)) - .3, .1);
    d = smin(d, box(s - vec3(0., -.22, 0.), vec3(.6, .12, .2), .12), .1);
    for (int i = 0; i < 3; i++) {
      float y = -.3 - fract(uTime * .6 + float(i) * .37) * .6, x = -.4 + float(i) * .4;
      d = min(d, cap(p, vec3(x, y, 0.), vec3(x - .05, y + .2, 0.), .08));
    }
    return d;`,

  bolt: `
    vec2 v[6] = vec2[](vec2(.22, .95), vec2(-.45, -.05), vec2(-.02, -.05), vec2(-.25, -.95), vec2(.5, .15), vec2(.06, .15));
    vec2 w = p.xy - v[0];
    float d2 = dot(w, w), sg = 1.;
    for (int i = 0, j = 5; i < 6; j = i, i++) {
      vec2 e = v[j] - v[i]; w = p.xy - v[i];
      vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0., 1.);
      d2 = min(d2, dot(b, b));
      bvec3 c = bvec3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);
      if (all(c) || all(not(c))) sg = -sg;
    }
    vec2 q = vec2(sg * sqrt(d2), abs(p.z) - .1);
    return min(max(q.x, q.y), 0.) + length(max(q, 0.)) - .04;`,

  snowflake: `
    vec3 s = p; s.xy = rot(uTime * .25) * s.xy;
    float r = length(s.xy), a = atan(s.y, s.x);
    a = mod(a + .5236, 1.0472) - .5236;
    vec3 q = vec3(cos(a) * r, abs(sin(a) * r), s.z);
    float d = cap(q, vec3(0.), vec3(.86, 0., 0.), .07);
    d = min(d, cap(q, vec3(.5, 0., 0.), vec3(.68, .18, 0.), .05));
    d = min(d, cap(q, vec3(.26, 0., 0.), vec3(.38, .13, 0.), .05));
    return d;`,

  moon: `
    vec3 s = p; s.xy = rot(.25 * sin(uTime * .5)) * s.xy;
    float c = max(length(s.xy) - .82, -(length(s.xy - vec2(.4, .2)) - .66));
    vec2 w = vec2(c + .06, abs(s.z) - .12);
    return min(max(w.x, w.y), 0.) + length(max(w, 0.)) - .06;`,

  flame: `
    vec3 s = p;
    s.x += .07 * sin(s.y * 5. + uTime * 7.) * (s.y + .4);
    float d = rcone(s - vec3(0., -.35, 0.), .52, .02, 1.2);
    vec3 t = s - vec3(.3, -.35, 0.); t.xy = rot(-.35) * t.xy;
    d = smin(d, rcone(t, .28, .02, .7), .12);
    return d * .8;`,

  leaf: `
    vec3 s = p; s.xy = rot(-.6 + .08 * sin(uTime)) * s.xy;
    vec2 q = abs(s.xy); float r = .95, dd = .58, b = sqrt(r * r - dd * dd);
    float v = ((q.y - b) * dd > q.x * b) ? length(q - vec2(0., b)) : length(q - vec2(-dd, 0.)) - r;
    vec2 w = vec2(v, abs(s.z) - .04);
    float blade = min(max(w.x, w.y), 0.) + length(max(w, 0.)) - .03;
    float rib = cap(s, vec3(0., -.7, .05), vec3(0., .65, .05), .03);
    float stem = cap(s, vec3(0., -.72, 0.), vec3(0., -1., 0.), .05);
    return min(min(blade, rib), stem);`,

  drop: `
    vec3 s = p; s.y += .04 * sin(uTime * 2.);
    return rcone(s - vec3(0., -.3, 0.), .55, .03, 1.1);`,
});
