// Shapes batch (objects-1): same contract as shapes.js.
Object.assign(ORB_SHAPES, {
  compass: `
    float disk = cyl(p.xzy, .8, .07);
    float rim = torus(p.xzy, .8, .09);
    vec3 q = p - vec3(0., 0., .1); q.xy = rot(.35 * sin(uTime * .7)) * q.xy;
    float needle = ell(q, vec3(.2, .66, .12));
    float hub = length(p - vec3(0., 0., .2)) - .08;
    float ticks = min(cap(p, vec3(0., .56, .08), vec3(0., .7, .08), .04), cap(p, vec3(0., -.56, .08), vec3(0., -.7, .08), .04));
    ticks = min(ticks, min(cap(p, vec3(.56, 0., .08), vec3(.7, 0., .08), .04), cap(p, vec3(-.56, 0., .08), vec3(-.7, 0., .08), .04)));
    return min(min(min(disk, rim), min(needle, hub)), ticks);`,

  binoculars: `
    vec3 r = p; r.xz = rot(.45) * r.xz;
    vec3 q = vec3(abs(r.x) - .45, r.y, r.z);
    float tube = cyl(q.xzy, .4, .32);
    float lens = cyl(q.xzy - vec3(0., .33, 0.), .29, .06);
    tube = max(tube, -lens);
    float eye = cyl(q.xzy - vec3(0., -.42, .0), .24, .14);
    float bridge = box(r - vec3(0., .05, -.05), vec3(.2, .14, .14), .05);
    return min(min(tube, eye), bridge);`,

  radar: `
    float disk = cyl(p.xzy, .85, .05);
    float r1 = torus(p.xzy - vec3(0., .06, 0.), .84, .06), r2 = torus(p.xzy - vec3(0., .06, 0.), .52, .04);
    float a = uTime * 1.2;
    float sweep = cap(p, vec3(0., 0., .08), vec3(cos(a) * .78, sin(a) * .78, .08), .05);
    float blip = length(p - vec3(.35, .3, .1)) - .08;
    float hub = length(p - vec3(0., 0., .08)) - .09;
    return min(min(disk, min(r1, r2)), min(min(sweep, blip), hub));`,

  speech: `
    float b = box(p - vec3(0., .12, 0.), vec3(.88, .6, .12), .3);
    float tail = cap(p, vec3(-.3, -.35, 0.), vec3(-.62, -.85, 0.), .1);
    float d = smin(b, tail, .12);
    vec3 q = p - vec3(0., .12, .15); q.x = abs(q.x);
    float dots = min(length(q) - .1, length(q - vec3(.34, 0., 0.)) - .1);
    return min(d, dots);`,

  phone: `
    float b = box(p, vec3(.46, .88, .07), .12);
    float screen = box(p - vec3(0., -.04, .1), vec3(.37, .7, .05), .04);
    float cam = length(p - vec3(0., .78, .07)) - .045;
    return max(b, -min(screen, cam));`,

  megaphone: `
    vec3 q = p; q.xy = rot(-1.3) * q.xy;
    q -= vec3(0., -.55, 0.);
    float horn = rcone(q, .2, .55, 1.05);
    float hollow = rcone(q - vec3(0., .18, 0.), .1, .47, 1.);
    horn = max(horn, -hollow);
    float handle = cap(p, vec3(-.3, -.1, 0.), vec3(-.35, -.62, 0.), .09);
    return min(horn, handle);`,

  paperplane: `
    vec2 a = vec2(.8, .6), b = vec2(-.85, .05), c = vec2(-.2, -.75);
    vec2 q = p.xy;
    vec2 e0 = b - a, e1 = c - b, e2 = a - c, v0 = q - a, v1 = q - b, v2 = q - c;
    vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0., 1.);
    vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0., 1.);
    vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0., 1.);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)), vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))), vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    float tri = -sqrt(d.x) * sign(d.y);
    float wing = length(max(vec2(tri + .04, abs(p.z) - .02), 0.)) + min(max(tri + .04, abs(p.z) - .02), 0.) - .04;
    float fold = cap(p, vec3(a, .05), vec3(-.35, -.2, .05), .045);
    return min(wing, fold);`,

  braces: `
    vec3 q = vec3(abs(p.x), p.y, p.z);
    float x = .45, r = .075;
    float d = cap(q, vec3(x - .18, .8, 0.), vec3(x, .64, 0.), r);
    d = min(d, cap(q, vec3(x, .64, 0.), vec3(x, .16, 0.), r));
    d = min(d, cap(q, vec3(x, .16, 0.), vec3(x + .18, 0., 0.), r));
    d = min(d, cap(q, vec3(x + .18, 0., 0.), vec3(x, -.16, 0.), r));
    d = min(d, cap(q, vec3(x, -.16, 0.), vec3(x, -.64, 0.), r));
    d = min(d, cap(q, vec3(x, -.64, 0.), vec3(x - .18, -.8, 0.), r));
    return d;`,

  wrench: `
    vec3 q = p; q.xy = rot(-.785) * q.xy;
    float handle = cap(q, vec3(0., -.6, 0.), vec3(0., .35, 0.), .13);
    float head = cyl(q.xzy - vec3(0., 0., .62), .34, .09);
    head = max(head, -box(q - vec3(0., .88, 0.), vec3(.13, .3, .2), .0));
    float tail = cyl(q.xzy - vec3(0., 0., -.72), .22, .09);
    tail = max(tail, -cyl(q.xzy - vec3(0., 0., -.72), .1, .2));
    return min(smin(handle, head, .08), smin(handle, tail, .06));`,

  bug: `
    vec3 q = vec3(abs(p.x), p.y, p.z);
    float body = ell(p - vec3(0., -.12, 0.), vec3(.36, .52, .26));
    float head = length(p - vec3(0., .52, 0.)) - .22;
    float d = smin(body, head, .06);
    float ant = cap(q, vec3(.08, .68, 0.), vec3(.3, .95, 0.), .04);
    float legs = cap(q, vec3(.25, .12, 0.), vec3(.68, .32, 0.), .05);
    legs = min(legs, cap(q, vec3(.3, -.12, 0.), vec3(.72, -.12, 0.), .05));
    legs = min(legs, cap(q, vec3(.25, -.38, 0.), vec3(.66, -.62, 0.), .05));
    float line = box(p - vec3(0., -.12, .24), vec3(.015, .45, .04), .01);
    return max(min(d, min(ant, legs)), -line);`,

  rocket: `
    vec3 q = p; q.xy = rot(-.5) * q.xy;
    float body = cap(q, vec3(0., -.45, 0.), vec3(0., .25, 0.), .3);
    float nose = rcone(q - vec3(0., .25, 0.), .3, .03, .55);
    float d = smin(body, nose, .08);
    vec3 f = vec3(abs(q.x), q.y, q.z);
    f.xy = rot(.5) * (f.xy - vec2(.3, -.55));
    float fins = box(f, vec3(.1, .22, .04), .03);
    float win = torus((q - vec3(0., .1, .27)).xzy, .12, .04);
    float flame = ell(q - vec3(0., -.9 - .05 * sin(uTime * 12.), 0.), vec3(.14, .24 + .04 * sin(uTime * 9.), .14));
    return min(min(d, fins), min(win, flame));`,

  gitbranch: `
    float line = cap(p, vec3(-.3, -.55, 0.), vec3(-.3, .55, 0.), .07);
    float n1 = torus((p - vec3(-.3, .72, 0.)).xzy, .15, .07);
    float n2 = torus((p - vec3(-.3, -.72, 0.)).xzy, .15, .07);
    float n3 = torus((p - vec3(.38, .45, 0.)).xzy, .15, .07);
    float br = min(cap(p, vec3(.38, .28, 0.), vec3(.38, .05, 0.), .07), cap(p, vec3(.38, .05, 0.), vec3(-.3, -.35, 0.), .07));
    return min(min(line, br), min(n1, min(n2, n3)));`,

  book: `
    vec3 l = p - vec3(-.46, 0., 0.); l.xy = rot(-.15) * l.xy;
    vec3 r = p - vec3(.46, 0., 0.); r.xy = rot(.15) * r.xy;
    float pages = min(box(l, vec3(.43, .58, .05), .03), box(r, vec3(.43, .58, .05), .03));
    float cover = min(box(l - vec3(0., -.04, -.07), vec3(.46, .62, .03), .02), box(r - vec3(0., -.04, -.07), vec3(.46, .62, .03), .02));
    float spine = cap(p, vec3(0., -.62, -.02), vec3(0., .55, -.02), .06);
    vec3 t = vec3(abs(l.x - 0.), l.y, l.z);
    float lines = 1e9;
    for (int i = 0; i < 3; i++) { float y = .3 - float(i) * .25;
      lines = min(lines, min(cap(l, vec3(-.28, y, .07), vec3(.28, y, .07), .03), cap(r, vec3(-.28, y, .07), vec3(.28, y, .07), .03))); }
    return min(min(pages, cover), min(spine, lines));`,

  paperclip: `
    vec2 q = rot(-.4) * p.xy;
    vec2 o = q - vec2(0., -.05);
    float outer = length(vec2(o.x, max(abs(o.y) - .5, 0.))) - .34;
    vec2 i = q - vec2(-.04, .1);
    float inner = length(vec2(i.x, max(abs(i.y) - .42, 0.))) - .18;
    float wire = min(abs(outer), max(abs(inner), -(q.y + .38)));
    return length(vec2(wire, p.z)) - .07;`,

  trash: `
    float w = 1. + .14 * p.y;
    float body = box(vec3(p.x / w, p.y + .12, p.z), vec3(.46, .62, .36), .06) * .88;
    float grooves = 1e9;
    for (int i = -1; i <= 1; i++) grooves = min(grooves, cap(p, vec3(float(i) * .2, -.55, .34), vec3(float(i) * .23, .3, .36), .05));
    body = max(body, -grooves);
    float lid = box(p - vec3(0., .6, 0.), vec3(.64, .07, .42), .04);
    float handle = min(cap(p, vec3(-.18, .8, 0.), vec3(.18, .8, 0.), .05), min(cap(p, vec3(-.18, .8, 0.), vec3(-.18, .66, 0.), .05), cap(p, vec3(.18, .8, 0.), vec3(.18, .66, 0.), .05)));
    return min(min(body, lid), handle);`,

  box3d: `
    vec3 q = p; q.yz = rot(.45) * q.yz; q.xz = rot(.65) * q.xz;
    float b = box(q, vec3(.55, .5, .55), .04);
    float tape = min(box(q - vec3(0., .5, 0.), vec3(.13, .05, .58), .01), box(q - vec3(0., .1, .55), vec3(.13, .42, .05), .01));
    float seam = box(q - vec3(0., .52, 0.), vec3(.56, .015, .005), .0);
    return max(min(b, tape), -seam);`,
});
