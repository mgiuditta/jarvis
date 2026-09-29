// SDF bodies for the orb's shapes: one GLSL function body per shape, `p` in unit space (fits a radius-1 ball, front = +z),
// returns the signed distance. orb.js wraps each as `float sh_<id>(vec3 p)`. Helpers (smin, box, cap, torus, cyl, rcone,
// ell, rot, snoise, uTime) live in orb.js. Add a shape here + a row in variants.js; check it in gallery.html at 96 px.
var ORB_SHAPES = {
  lens: `
    vec3 q = p - vec3(-.18, .22, 0.);
    float ring = torus(q.xzy, .48, .12);
    float glass = cyl(q.xzy, .44, .03);
    return min(min(ring, glass), cap(p, vec3(.17, -.13, 0.), vec3(.68, -.64, 0.), .13));`,

  globe: `
    float s = length(p) - .72;
    float eq = torus(p, .76, .045);
    vec3 a = p; a.xz = rot(.8 + uTime * .3) * a.xz;
    vec3 b = p; b.xz = rot(-.8 + uTime * .3) * b.xz;
    float m1 = torus(a.yxz, .76, .045), m2 = torus(b.yxz, .76, .045);
    float lat = min(torus(p - vec3(0., .4, 0.), .63, .04), torus(p + vec3(0., .4, 0.), .63, .04));
    return min(s, min(min(eq, lat), min(m1, m2)));`,

  envelope: `
    float b = box(p, vec3(.92, .6, .09), .05);
    float f = min(cap(p, vec3(-.84, .5, .13), vec3(0., -.1, .13), .07), cap(p, vec3(.84, .5, .13), vec3(0., -.1, .13), .07));
    return min(b, f);`,

  gear: `
    vec3 q = p; q.xy = rot(uTime * .6) * q.xy;
    float a = atan(q.y, q.x), r = length(q.xy);
    float teeth = .72 + .17 * smoothstep(-.25, .25, sin(a * 8.));
    float g = max(r - teeth, abs(q.z) - .2);
    return max(g, -(r - .26));`,

  terminal: `
    float b = box(p, vec3(.95, .7, .08), .07);
    float bar = box(p - vec3(0., .6, .06), vec3(.95, .1, .06), .02);
    float chev = min(cap(p, vec3(-.62, .25, .13), vec3(-.36, .02, .13), .06), cap(p, vec3(-.36, .02, .13), vec3(-.62, -.21, .13), .06));
    float us = cap(p, vec3(-.18, -.24, .13), vec3(.28, -.24, .13), .06);
    return min(min(b, bar), min(chev, us));`,

  pencil: `
    vec3 q = p; q.xy = rot(-.785) * q.xy;
    float body = cap(q, vec3(0., -.95, 0.), vec3(0., .45, 0.), .24);
    float tip = rcone(q - vec3(0., .45, 0.), .24, .03, .5);
    float band = cyl(q - vec3(0., -.62, 0.), .27, .07);
    return min(min(body, tip), band);`,

  document: `
    float b = box(p, vec3(.6, .8, .05), .03);
    b = max(b, dot(p.xy - vec2(.6, .8), normalize(vec2(1., 1.))) + .22);
    float l = 1e9;
    for (int i = 0; i < 4; i++) { float y = .3 - float(i) * .25; l = min(l, cap(p, vec3(-.38, y, .08), vec3(i == 3 ? .1 : .36, y, .08), .035)); }
    return min(b, l);`,

  folder: `
    float b = box(p - vec3(0., -.06, 0.), vec3(.9, .58, .1), .06);
    float tab = box(p - vec3(-.52, .58, 0.), vec3(.32, .1, .1), .05);
    float lip = box(p - vec3(0., -.14, .13), vec3(.86, .46, .03), .03);
    return min(min(b, tab), lip);`,

  calendar: `
    float b = box(p - vec3(0., -.08, 0.), vec3(.78, .72, .09), .07);
    float head = box(p - vec3(0., .5, .04), vec3(.78, .16, .1), .05);
    float rings = min(cap(p, vec3(-.42, .6, .12), vec3(-.42, .92, .12), .07), cap(p, vec3(.42, .6, .12), vec3(.42, .92, .12), .07));
    vec2 q = p.xy - vec2(0., -.3);
    vec2 id = clamp(floor(q / .38 + .5), -1., 1.);
    float dots = length(vec3(q - id * .38, p.z - .1)) - .09;
    return min(min(b, head), min(rings, dots));`,

  palette: `
    float e = ell(p, vec3(.95, .74, .1));
    e = max(e, -(length(p.xy - vec2(.42, -.3)) - .16));
    float paint = 1e9;
    for (int i = 0; i < 4; i++) { float a = 1.9 + float(i) * .75; paint = min(paint, length(p - vec3(cos(a) * .55, sin(a) * .42 + .05, .1)) - .15); }
    return smin(e, paint, .05);`,

  robot: `
    vec3 q = p - vec3(0., -.05, 0.);
    float head = box(q - vec3(0., .42, 0.), vec3(.42, .3, .3), .1);
    float eyes = min(length(q - vec3(-.18, .45, .38)) - .09, length(q - vec3(.18, .45, .38)) - .09);
    float ant = min(cap(q, vec3(0., .72, 0.), vec3(0., .92, 0.), .04), length(q - vec3(0., .96, 0.)) - .08);
    float body = box(q - vec3(0., -.35, 0.), vec3(.38, .36, .26), .08);
    float s = sin(uTime * 2.);
    float arms = min(cap(q, vec3(-.52, -.2, 0.), vec3(-.72, -.55 + .15 * s, .1), .09), cap(q, vec3(.52, -.2, 0.), vec3(.72, -.55 - .15 * s, .1), .09));
    return min(min(min(head, eyes), ant), min(body, arms));`,

  person: `
    vec3 q = p * 1.25;
    float s = sin(uTime * 2.);
    float d = length(q - vec3(0., 1., 0.)) - .36;
    d = smin(d, cap(q, vec3(0., .55, 0.), vec3(0., -.35, 0.), .38), .25);
    d = smin(d, cap(q, vec3(-.42, .45, 0.), vec3(-.8, -.35 + .1 * s, .15), .13), .15);
    d = smin(d, cap(q, vec3(.42, .45, 0.), vec3(.8, -.35 - .1 * s, .15), .13), .15);
    d = smin(d, cap(q, vec3(-.18, -.4, 0.), vec3(-.26, -1.3, 0.), .16), .15);
    d = smin(d, cap(q, vec3(.18, -.4, 0.), vec3(.26, -1.3, 0.), .16), .15);
    return d / 1.25;`,

  symbiote: `
    vec3 q = p * 1.25;
    float s = sin(uTime * 1.6);
    float d = ell(q - vec3(0., 1., .02), vec3(.36, .42, .36));
    d = smin(d, cap(q, vec3(0., .55, 0.), vec3(0., -.35, 0.), .42), .25);
    d = smin(d, cap(q, vec3(-.46, .45, 0.), vec3(-.95, -.1 + .25 * s, .2), .14), .15);
    d = smin(d, cap(q, vec3(.46, .45, 0.), vec3(.95, .2 - .25 * s, .2), .14), .15);
    d = smin(d, cap(q, vec3(-.18, -.4, 0.), vec3(-.3, -1.3, 0.), .17), .15);
    d = smin(d, cap(q, vec3(.18, -.4, 0.), vec3(.3, -1.3, 0.), .17), .15);
    for (int i = 0; i < 4; i++) {
      float a = float(i) * 1.57 + uTime * .8;
      d = smin(d, cap(q, vec3(0., .3, 0.), vec3(cos(a) * 1.25, .3 + sin(uTime * 1.3 + float(i)) * .75, sin(a) * .55), .06), .3);
    }
    d += .03 * snoise(q * 2.5 + uTime);
    return d / 1.25 * .9;`,
};
