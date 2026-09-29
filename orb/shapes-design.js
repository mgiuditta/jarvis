// Shapes batch (design): same contract as shapes.js. Brand-flavoured ones are loose homages, not the real logos.
Object.assign(ORB_SHAPES, {
  figmapills: `
    vec3 q = p; q.y -= .02 * sin(uTime * 1.5);
    float h = .1, s = .25;
    float tl = min(cyl((q - vec3(-.29, .56, 0.)).xzy, s, h), box(q - vec3(-.16, .56, 0.), vec3(.13, s, h), 0.));
    float ml = min(cyl((q - vec3(-.29, 0., 0.)).xzy, s, h), box(q - vec3(-.16, 0., 0.), vec3(.13, s, h), 0.));
    float bl = min(cyl((q - vec3(-.29, -.56, 0.)).xzy, s, h), box(q - vec3(-.16, -.435, 0.), vec3(.13, .125, h), 0.));
    bl = min(bl, box(q - vec3(-.29, -.435, 0.), vec3(.26, .125, h), 0.));
    float tr = min(cyl((q - vec3(.29, .56, 0.)).xzy, s, h), box(q - vec3(.16, .56, 0.), vec3(.13, s, h), 0.));
    float mr = cyl((q - vec3(.29, 0., .05 * sin(uTime * 2.))).xzy, s, h);
    return min(min(min(tl, ml), min(bl, tr)), mr) - .02;`,

  diamond: `
    vec3 q = p - vec3(0., .1, 0.); q.xz = rot(uTime * .4) * q.xz;
    float a = mod(atan(q.z, q.x), .7854) - .3927;
    vec2 r = vec2(length(q.xz) * cos(a), q.y);
    float table = r.y - .38;
    float crown = dot(r - vec2(.88, .05), normalize(vec2(.35, .6)));
    float girdle = r.x - .9;
    float pav = dot(r - vec2(.9, 0.), normalize(vec2(.9, -.95)));
    return max(max(table, crown), max(girdle, pav));`,

  pentool: `
    vec3 q = p; q.xy = rot(-.5) * q.xy; q.y -= .05;
    vec2 u = vec2(abs(q.x), q.y);
    float nib = max(max(dot(u - vec2(0., -.9), normalize(vec2(1., -.5))), u.y - .25), u.x - .48);
    nib = max(nib, -(length(u - vec2(0., -.12)) - .11));
    nib = max(nib, -max(u.x - .025, max(u.y + .12, -u.y - .95)));
    vec2 w = vec2(nib, abs(q.z) - .08);
    float d = min(max(w.x, w.y), 0.) + length(max(w, 0.)) - .03;
    return min(d, box(q - vec3(0., .52, 0.), vec3(.34, .16, .12), .05));`,

  ruler: `
    vec3 q = p; q.xy = rot(.55 + .05 * sin(uTime)) * q.xy;
    float d = box(q, vec3(.95, .26, .07), .03);
    float i = clamp(floor(q.x / .15 + .5), -5., 5.);
    float len = mod(i, 2.) == 0. ? .15 : .08;
    float tick = box(vec3(q.x - i * .15, q.y - .26, q.z), vec3(.022, len, .2), 0.);
    return max(d, -tick);`,

  setsquare: `
    vec3 q = p; q.xy = rot(.1 * sin(uTime * .7)) * q.xy;
    float o = max(max(-(q.x + .7), -(q.y + .7)), dot(q.xy, vec2(.7071)) - .06);
    float d2 = max(o, -(o + .24));
    vec2 w = vec2(d2 + .02, abs(q.z) - .05);
    return min(max(w.x, w.y), 0.) + length(max(w, 0.)) - .02;`,

  layers: `
    float d = 1e9, g = .08 * sin(uTime * 1.5);
    for (int i = 0; i < 3; i++) {
      vec3 q = p - vec3(0., .42 - float(i) * (.42 + g), 0.);
      q.yz = rot(-1.) * q.yz;
      q.xz = rot(.7854) * q.xz;
      d = min(d, box(q, vec3(.5, .045, .5), .04));
    }
    return d;`,

  grid: `
    float d = box(p, vec3(.86, .86, .08), .06);
    vec2 c = clamp(floor(p.xy / .56 + .5), -1., 1.);
    vec2 q = p.xy - c * .56;
    float k = .5 + .5 * sin(uTime * 2. - (c.x - c.y) * 1.2);
    float cell = box(vec3(q, p.z - .1), vec3(.2, .2, .1 + .06 * k), .03);
    return max(d, -cell);`,

  eyedropper: `
    vec3 q = p; q.xy = rot(.7854) * q.xy;
    float bulb = cap(q, vec3(0., .5, 0.), vec3(0., .78, 0.), .19);
    float collar = cyl(q - vec3(0., .32, 0.), .23, .055) - .02;
    float tube = rcone(q - vec3(0., -.72, 0.), .035, .1, 1.);
    float drip = length(q - vec3(0., -.82 - .08 * fract(uTime * .8), 0.)) - .06 * (1. - fract(uTime * .8) * .5);
    return min(min(bulb, collar), min(tube, drip));`,

  bucket: `
    p /= 1.15;
    vec3 q = p - vec3(-.25, -.05, 0.); q.xy = rot(-.85) * q.xy; q.yz = rot(.55) * q.yz;
    float rr = .3 + .2 * (q.y + .45) / .75;
    float body = max(length(q.xz) - rr, abs(q.y + .075) - .375) * .9;
    body = max(body, -max(length(q.xz) - rr + .06, -(q.y + .37)));
    float rim = torus(q - vec3(0., .3, 0.), .46, .05);
    vec3 hq = q - vec3(0., .3, 0.);
    float handle = max(torus(hq.xzy, .46, .04), -hq.y);
    float t = fract(uTime * .7);
    vec3 dq = p - vec3(.66, -.05 - .6 * t, 0.);
    float drop = smin(length(dq) - .15, length(dq - vec3(0., .2, 0.)) - .02, .14);
    return min(min(min(body, rim), handle), drop) * 1.15;`,

  nodes: `
    vec3 c = p - vec3(0., -.35, 0.);
    float arc = max(torus(c.xzy, .7, .04), -(p.y + .38));
    float sq = min(min(box(p - vec3(-.7, -.4, 0.), vec3(.12, .12, .09), .02), box(p - vec3(.7, -.4, 0.), vec3(.12, .12, .09), .02)),
                   box(p - vec3(0., .35, 0.), vec3(.13, .13, .1), .02));
    float hx = .5 + .06 * sin(uTime * 1.5);
    float hnd = cap(p, vec3(-hx, .35, .06), vec3(hx, .35, .06), .025);
    hnd = min(hnd, min(length(p - vec3(-hx, .35, .06)) - .075, length(p - vec3(hx, .35, .06)) - .075));
    return min(min(arc, sq), hnd);`,

  cursor: `
    vec3 q = p - vec3(.02, .02 + .04 * sin(uTime * 2.), 0.);
    q.xy = rot(.08 * sin(uTime * 1.3)) * q.xy;
    float head = max(max(-(q.x + .45), dot(q.xy - vec2(-.45, -.3), normalize(vec2(.25, -.85)))), dot(q.xy - vec2(.4, -.05), normalize(vec2(.9, .85))));
    vec2 t = rot(.4) * (q.xy - vec2(.1, -.42));
    vec2 tb = abs(t) - vec2(.1, .34);
    float tail = length(max(tb, 0.)) + min(max(tb.x, tb.y), 0.);
    float d2 = min(head, tail) + .03;
    vec2 w = vec2(d2, abs(q.z) - .08);
    return min(max(w.x, w.y), 0.) + length(max(w, 0.)) - .05;`,

  browserwin: `
    float d = box(p, vec3(.92, .72, .08), .08);
    float groove = box(p - vec3(0., .4, .1), vec3(1., .025, .05), 0.);
    float dots = 1e9;
    for (int i = 0; i < 3; i++) dots = min(dots, length(p.xy - vec2(-.72 + float(i) * .17, .56)) - .055);
    float url = box(p - vec3(.3, .56, .1), vec3(.44, .06, .05), .05);
    float img = box(p - vec3(-.42, -.14, .1), vec3(.34, .36, .06), .04);
    float ln = min(box(p - vec3(.38, .08, .1), vec3(.36, .05, .05), .04), box(p - vec3(.3, -.14, .1), vec3(.28, .05, .05), .04));
    ln = min(ln, box(p - vec3(.34, -.36, .1), vec3(.32, .05, .05), .04));
    float carve = min(min(groove, max(dots, abs(p.z - .1) - .05)), min(url, min(img, ln)));
    return max(d, -carve);`,

  mobile: `
    vec3 q = p; q.xy = rot(-.18) * q.xy; q.y -= .03 * sin(uTime * 1.6);
    float body = box(q, vec3(.48, .9, .07), .06);
    float screen = box(q - vec3(0., 0., .1), vec3(.41, .83, .08), .05);
    float d = max(body, -screen);
    float island = box(q - vec3(0., .7, .02), vec3(.1, .035, .03), .035);
    vec2 c = clamp(floor((q.xy - vec2(-.24, .4)) / vec2(.24, -.26) + .5), vec2(0.), vec2(2., 3.));
    vec2 g = q.xy - vec2(-.24, .4) - c * vec2(.24, -.26);
    float icons = box(vec3(g, q.z - .02), vec3(.085, .085, .03), .03);
    float btn = box(q - vec3(.5, .35, 0.), vec3(.03, .16, .03), .02);
    return min(min(d, island), min(icons, btn));`,

  fontaa: `
    vec3 q = p; q.xy = rot(.06 * sin(uTime)) * q.xy; q.y += .05;
    float A = min(cap(q, vec3(-.92, -.52, 0.), vec3(-.52, .62, 0.), .1), cap(q, vec3(-.52, .62, 0.), vec3(-.12, -.52, 0.), .1));
    A = min(A, cap(q, vec3(-.74, -.12, 0.), vec3(-.3, -.12, 0.), .085));
    vec3 o = q - vec3(.4, -.28, 0.);
    float a = torus(o.xzy, .23, .085);
    a = min(a, cap(q, vec3(.68, -.52, 0.), vec3(.68, .05, 0.), .085));
    vec3 h = q - vec3(.44, .05, 0.);
    a = min(a, max(torus(h.xzy, .24, .085), -h.y));
    return min(A, a);`,

  component: `
    vec3 q = p; q.xy = rot(.7854 + .15 * sin(uTime * .8)) * q.xy;
    vec2 r = abs(q.xy) - .34;
    float d = box(vec3(r, q.z), vec3(.25, .25, .09), .06);
    return d;`,
});
