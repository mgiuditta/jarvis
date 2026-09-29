// Shapes batch (dev-2): same contract as shapes.js.
Object.assign(ORB_SHAPES, {
  database: `
    vec3 q = p; q.yz = rot(.35) * q.yz;
    float d = 1e9;
    for (int i = 0; i < 3; i++) d = min(d, cyl(q - vec3(0., .48 - float(i) * .48, 0.), .58, .19) - .03);
    return d;`,

  server: `
    float d = 1e9;
    for (int i = 0; i < 3; i++) {
      vec3 q = p - vec3(0., .5 - float(i) * .5, 0.);
      float s = box(q, vec3(.8, .2, .35), .05);
      s = max(s, -box(q - vec3(-.18, 0., .38), vec3(.38, .045, .08), .02));
      s = max(s, -(length(q - vec3(.5, 0., .38)) - .07));
      s = max(s, -(length(q - vec3(.66, 0., .38)) - .07));
      d = min(d, s);
    }
    return d;`,

  chip: `
    float body = box(p, vec3(.52, .52, .1), .05);
    float die = box(p - vec3(0., 0., .1), vec3(.3, .3, .04), .03);
    vec3 a = abs(p);
    float pins = 1e9;
    for (int i = 0; i < 2; i++) {
      float o = float(i) * .3;
      pins = min(pins, box(vec3(a.x - .68, a.y - o, p.z), vec3(.16, .065, .035), .02));
      pins = min(pins, box(vec3(a.x - o, a.y - .68, p.z), vec3(.065, .16, .035), .02));
    }
    float d = min(min(body, die), pins);
    return max(d, -(length(p - vec3(-.38, .38, .12)) - .06));`,

  plug: `
    vec3 q = p; q.xy = rot(-.45) * q.xy;
    float body = box(q - vec3(0., .02, 0.), vec3(.3, .26, .22), .1);
    float head = cyl(q - vec3(0., .3, 0.), .36, .06) - .03;
    vec3 r = vec3(abs(q.x) - .16, q.y - .52, q.z);
    float prongs = box(r, vec3(.055, .2, .035), .02);
    float neck = rcone(q - vec3(0., -.42, 0.), .1, .2, .2);
    vec3 c = q; c.x += .1 * sin(c.y * 5. + 1.);
    float cable = cap(c, vec3(0., -.9, 0.), vec3(0., -.35, 0.), .085);
    return min(min(min(body, head), prongs), min(neck, cable * .8));`,

  pullrequest: `
    float n1 = torus((p - vec3(-.45, .62, 0.)).xzy, .15, .07);
    float n2 = torus((p - vec3(-.45, -.62, 0.)).xzy, .15, .07);
    float n3 = torus((p - vec3(.45, -.62, 0.)).xzy, .15, .07);
    float l1 = cap(p, vec3(-.45, -.45, 0.), vec3(-.45, .45, 0.), .07);
    float l2 = min(cap(p, vec3(.45, -.45, 0.), vec3(.45, .55, 0.), .07), cap(p, vec3(.45, .6, 0.), vec3(-.02, .6, 0.), .07));
    float ar = min(cap(p, vec3(-.06, .6, 0.), vec3(.14, .8, 0.), .07), cap(p, vec3(-.06, .6, 0.), vec3(.14, .4, 0.), .07));
    return min(min(min(n1, n2), n3), min(min(l1, l2), ar));`,

  testtube: `
    vec3 q = p; q.xy = rot(-.4) * q.xy;
    float tube = cap(q, vec3(0., -.55, 0.), vec3(0., .8, 0.), .27);
    float lvl = -.02 + .03 * sin(uTime * 2. + q.x * 6.);
    float glass = max(abs(tube) - .035, q.y - .72);
    glass = max(glass, -box(q - vec3(0., .36, .3), vec3(.23, .28, .22), .02));
    float liquid = max(tube + .015, q.y - lvl);
    liquid = max(liquid, -torus(q - vec3(0., lvl - .12, 0.), .27, .025));
    float lip = torus(q - vec3(0., .72, 0.), .29, .06);
    float b = 1e9;
    for (int i = 0; i < 2; i++) {
      float t = fract(uTime * .35 + float(i) * .5);
      b = min(b, length(q - vec3(-.07 + float(i) * .13, lvl + .05 + t * .6, 0.)) - .07 * (1. - t * .5));
    }
    return min(min(glass, liquid), min(lip, b));`,

  trafficlight: `
    float d = box(p, vec3(.36, .86, .24), .1);
    float on = floor(mod(uTime * .7, 3.));
    for (int i = 0; i < 3; i++) {
      vec3 q = p - vec3(0., .52 - float(i) * .52, 0.);
      float hood = max(max(abs(length(q.xy) - .25) - .05, -q.y + .02), abs(q.z - .32) - .09);
      d = min(d, hood);
      d = max(d, -(length(q - vec3(0., 0., .28)) - .2));
      if (float(i) == on) d = min(d, length(q - vec3(0., 0., .32)) - .17);
    }
    return d;`,

  scroll: `
    vec3 q = p; q.xy = rot(-.15) * q.xy;
    float sheet = box(q, vec3(.55, .58, .03), .02);
    float rolls = 1e9;
    for (int i = 0; i < 2; i++) {
      float y = i == 0 ? .6 : -.6;
      vec3 r = vec3(q.y - y, q.x, q.z);
      rolls = min(rolls, cyl(r, .14, .62) - .02);
      rolls = min(rolls, cyl(r, .06, .8) - .02);
    }
    float l = 1e9;
    for (int i = 0; i < 3; i++) { float y = .22 - float(i) * .22; l = min(l, cap(q, vec3(-.36, y, .05), vec3(i == 2 ? .08 : .36, y, .05), .04)); }
    return min(min(sheet, rolls), l);`,

  refresh: `
    vec3 q = p; q.xy = rot(uTime * .8) * q.xy;
    if (q.y < 0.) q.xy = -q.xy;
    float ring = torus(q.xzy, .58, .1);
    float arc = max(ring, -dot(q.xy, vec2(-.5, .866)));
    vec2 t = q.xy - vec2(.58, .3);
    float tri = max(-q.y + .02, max(dot(t, normalize(vec2(.3, .22))), dot(t, normalize(vec2(-.3, .22)))));
    float head = max(tri, abs(q.z) - .08) - .02;
    return min(arc, head);`,

  hash: `
    vec3 q = p; q.x -= .18 * q.y;
    float v = box(vec3(abs(q.x) - .26, q.y, q.z), vec3(.1, .78, .13), .03);
    float h = box(vec3(p.x, abs(p.y) - .25, p.z), vec3(.72, .1, .13), .03);
    return min(v, h) * .95;`,
});
