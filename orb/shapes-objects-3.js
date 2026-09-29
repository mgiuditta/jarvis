// Shapes batch (objects-3): same contract as shapes.js.
Object.assign(ORB_SHAPES, {
  house: `
    float body = box(p - vec3(0., -.35, 0.), vec3(.6, .45, .32), .04);
    vec2 q = vec2(abs(p.x), p.y - .9);
    float roof2 = max(dot(q, normalize(vec2(.75, .85))), .08 - p.y);
    float roof = max(roof2, abs(p.z) - .4) - .03;
    float chim = box(p - vec3(.42, .62, 0.), vec3(.1, .22, .12), .02);
    float d = min(min(body, roof), chim);
    d = max(d, -box(p - vec3(0., -.55, .35), vec3(.15, .26, .12), .03));
    d = max(d, -box(p - vec3(-.32, -.25, .35), vec3(.1, .1, .08), .02));
    return d;`,

  bulb: `
    float glass = length(p - vec3(0., .25, 0.)) - .55;
    float neck = rcone(p - vec3(0., -.5, 0.), .26, .42, .5);
    float d = smin(glass, neck, .12);
    float base = cyl(p - vec3(0., -.68, 0.), .27, .16);
    for (int i = 0; i < 3; i++) base = min(base, torus(p - vec3(0., -.56 - float(i) * .11, 0.), .27, .045));
    float tip = length(p - vec3(0., -.88, 0.)) - .1;
    return min(min(d, base), tip);`,

  mug: `
    vec3 q = p - vec3(-.12, -.1, 0.);
    float body = cyl(q, .5, .5) - .03;
    body = max(body, -cyl(q - vec3(0., .15, 0.), .42, .5));
    vec3 h = q - vec3(.55, 0., 0.);
    float handle = max(torus(h.xzy, .25, .08), -h.x);
    float steam = 1e9;
    for (int i = 0; i < 2; i++) {
      float x = -.15 + float(i) * .3;
      vec3 s = p - vec3(x, .7, 0.);
      s.x -= .06 * sin(s.y * 10. - uTime * 3. + float(i) * 2.);
      steam = min(steam, cap(s, vec3(0., -.2, 0.), vec3(0., .2, 0.), .05));
    }
    return min(min(body, handle), steam * .8);`,

  key: `
    vec3 q = p; q.xy = rot(-.5) * q.xy;
    float bow = torus((q - vec3(-.5, 0., 0.)).xzy, .3, .1);
    float shaft = cap(q, vec3(-.22, 0., 0.), vec3(.88, 0., 0.), .08);
    float t1 = box(q - vec3(.62, -.16, 0.), vec3(.05, .12, .07), .02);
    float t2 = box(q - vec3(.8, -.14, 0.), vec3(.05, .1, .07), .02);
    return min(min(bow, shaft), min(t1, t2));`,

  lock: `
    float body = box(p - vec3(0., -.35, 0.), vec3(.52, .42, .2), .1);
    vec3 s = p - vec3(0., .12, 0.);
    float arc = max(torus(s.xzy, .3, .085), -s.y);
    float legs = min(cap(p, vec3(-.3, .12, 0.), vec3(-.3, -.05, 0.), .085), cap(p, vec3(.3, .12, 0.), vec3(.3, -.05, 0.), .085));
    float d = min(body, min(arc, legs));
    float hole = min(length(p.xy - vec2(0., -.28)) - .09, box(p - vec3(0., -.45, 0.), vec3(.04, .12, 1.), 0.));
    return max(d, -max(hole, -(p.z - .1)));`,

  bell: `
    vec3 q = p - vec3(0., .5, 0.);
    q.xy = rot(.25 * sin(uTime * 2.2)) * q.xy;
    q += vec3(0., .5, 0.);
    float body = rcone(q - vec3(0., -.5, 0.), .6, .36, .62);
    body = smin(body, length(q - vec3(0., .12, 0.)) - .38, .1);
    body = max(body, -(q.y + .52));
    float lip = torus(q - vec3(0., -.52, 0.), .64, .08);
    float knob = length(q - vec3(0., .38, 0.)) - .12;
    float clap = length(q - vec3(.08 * sin(uTime * 2.2 + 1.), -.68, 0.)) - .12;
    return min(min(body, lip), min(knob, clap));`,

  gift: `
    float b = box(p - vec3(0., -.2, 0.), vec3(.62, .48, .45), .03);
    float lid = box(p - vec3(0., .34, 0.), vec3(.7, .13, .52), .03);
    float r1 = box(p - vec3(0., -.05, 0.), vec3(.1, .52, .56), .02);
    float r2 = box(p - vec3(0., -.2, 0.), vec3(.66, .1, .49), .02);
    vec3 a = p - vec3(-.2, .6, 0.); a.xy = rot(-.5) * a.xy;
    vec3 c = p - vec3(.2, .6, 0.); c.xy = rot(.5) * c.xy;
    float bow = min(ell(a, vec3(.22, .12, .08)), ell(c, vec3(.22, .12, .08)));
    return min(min(min(b, lid), min(r1, r2)), bow);`,

  heart: `
    float s = 1.35 * (1. + .06 * pow(.5 + .5 * sin(uTime * 4.), 4.));
    vec2 q = p.xy / s + vec2(0., .52);
    q.x = abs(q.x);
    float d2;
    if (q.y + q.x > 1.) d2 = length(q - vec2(.25, .75)) - .35355;
    else { vec2 a = q - vec2(0., 1.), b = q - .5 * max(q.x + q.y, 0.); d2 = sqrt(min(dot(a, a), dot(b, b))) * sign(q.x - q.y); }
    d2 = d2 * s + .12;
    vec2 w = vec2(d2, abs(p.z) - .14);
    return min(max(w.x, w.y), 0.) + length(max(w, 0.)) - .12;`,

  star: `
    vec2 q = rot(.2 * sin(uTime * .8)) * p.xy;
    const vec2 k1 = vec2(.809016994, -.587785252);
    vec2 k2 = vec2(-k1.x, k1.y);
    q.x = abs(q.x);
    q -= 2. * max(dot(k1, q), 0.) * k1;
    q -= 2. * max(dot(k2, q), 0.) * k2;
    q.x = abs(q.x);
    q.y -= .95;
    vec2 ba = .45 * vec2(-k1.y, k1.x) - vec2(0., 1.);
    float h = clamp(dot(q, ba) / dot(ba, ba), 0., .95);
    float d2 = length(q - ba * h) * sign(q.y * ba.x - q.x * ba.y) + .09;
    vec2 w = vec2(d2, abs(p.z) - .1);
    return min(max(w.x, w.y), 0.) + length(max(w, 0.)) - .09;`,

  flag: `
    float pole = cap(p, vec3(-.62, -.95, 0.), vec3(-.62, .82, 0.), .055);
    float ball = length(p - vec3(-.62, .88, 0.)) - .09;
    vec3 q = p - vec3(-.08, .5, 0.);
    float k = (q.x + .52) / 1.04;
    q.z -= .1 * k * sin(q.x * 5. - uTime * 3.);
    q.y -= .05 * k * sin(q.x * 4. - uTime * 3. + 1.);
    float cloth = box(q, vec3(.52, .32, .035), .02) * .75;
    return min(min(pole, ball), cloth);`,

  pin: `
    vec3 q = p - vec3(0., .05 * sin(uTime * 2.), 0.);
    float head = length(q - vec3(0., .3, 0.)) - .52;
    float tail = rcone(q - vec3(0., -.9, 0.), .03, .38, .95);
    float d = smin(head, tail, .1);
    return max(d, -(length(q.xy - vec2(0., .3)) - .19));`,

  car: `
    vec3 q = p - vec3(0., .05, 0.);
    float body = box(q - vec3(0., -.15, 0.), vec3(.92, .2, .4), .1);
    float cab = box(q - vec3(-.08, .17, 0.), vec3(.48, .2, .36), .13);
    vec3 wq = vec3(abs(q.x + .08) - .2, q.y - .2, q.z);
    cab = max(cab, -box(wq - vec3(0., 0., .4), vec3(.14, .1, .1), .03));
    float d = smin(body, cab, .06);
    vec3 w = vec3(abs(q.x) - .56, q.y + .38, q.z);
    float wheel = cyl(w.xzy, .21, .44) - .02;
    d = max(d, -cyl(w.xzy, .26, .5));
    return min(d, wheel);`,

  trophy: `
    vec3 q = p - vec3(0., .05, 0.);
    float bowl = max(ell(q - vec3(0., .55, 0.), vec3(.52, .6, .52)), q.y - .55);
    float rim = torus(q - vec3(0., .55, 0.), .5, .05);
    vec3 h = vec3(abs(q.x) - .55, q.y - .38, q.z);
    float handles = max(torus(h.xzy, .18, .055), -h.x);
    float stem = cap(q, vec3(0., -.05, 0.), vec3(0., -.5, 0.), .08);
    float base = box(q - vec3(0., -.65, 0.), vec3(.36, .12, .26), .04);
    return min(min(min(bowl, rim), handles), min(stem, base));`,

  dice: `
    vec3 q = p;
    q.yz = rot(.4) * q.yz;
    q.xz = rot(.55 + .15 * sin(uTime * .7)) * q.xz;
    float b = box(q, vec3(.6), .14);
    float pip = 1e9;
    for (int i = 0; i < 5; i++) {
      vec2 o = i == 0 ? vec2(0.) : vec2(i < 3 ? -.28 : .28, mod(float(i), 2.) < .5 ? -.28 : .28);
      pip = min(pip, length(q - vec3(o, .66)) - .12);
    }
    pip = min(pip, min(length(q - vec3(-.25, .66, -.25)) - .12, length(q - vec3(.25, .66, .25)) - .12));
    return max(b, -pip);`,

  puzzle: `
    vec2 q = p.xy - vec2(-.08, -.08);
    float d2 = length(max(abs(q) - .52, 0.)) + min(max(abs(q.x) - .52, abs(q.y) - .52), 0.);
    d2 = min(d2, length(q - vec2(0., .7)) - .2);
    d2 = min(d2, length(q - vec2(.7, 0.)) - .2);
    d2 = max(d2, -(length(q - vec2(-.52, 0.)) - .2));
    d2 = max(d2, -(length(q - vec2(0., -.52)) - .2));
    d2 += .05;
    vec2 w = vec2(d2, abs(p.z) - .12);
    return min(max(w.x, w.y), 0.) + length(max(w, 0.)) - .05;`,

  brain: `
    float main = ell(p - vec3(0., .1, 0.), vec3(.85, .6, .5));
    float cereb = ell(p - vec3(.4, -.38, 0.), vec3(.32, .22, .3));
    float stem = cap(p, vec3(.15, -.3, 0.), vec3(.1, -.75, 0.), .1);
    float d = smin(smin(main, cereb, .08), stem, .08);
    d += .035 * sin(p.x * 11. + 2. * sin(p.y * 8.)) * sin(p.y * 10. + 2. * sin(p.x * 7.) + uTime * .5);
    return d * .8;`,

  eye: `
    float lens = max(length(p - vec3(0., -.6, 0.)) - 1.05, length(p - vec3(0., .6, 0.)) - 1.05);
    lens = max(lens, abs(p.z) - .22);
    vec2 look = vec2(.14 * sin(uTime * .7), .05 * sin(uTime * .45));
    float iris = length(p - vec3(look, .1)) - .36;
    float d = min(lens, iris);
    return max(d, -(length(p - vec3(look, .5)) - .18));`,

  thumbsup: `
    vec3 q = p - vec3(.1, -.1, 0.);
    float fist = box(q - vec3(.05, -.15, 0.), vec3(.32, .38, .28), .15);
    float fing = 1e9;
    for (int i = 0; i < 4; i++) { float y = .12 - float(i) * .19; fing = min(fing, cap(q, vec3(.05, y, .1), vec3(.42, y, .1), .1)); }
    float thumb = cap(q, vec3(-.12, .15, 0.), vec3(-.2, .78, 0.), .15);
    float cuff = box(q - vec3(-.5, -.2, 0.), vec3(.12, .38, .3), .05);
    return min(min(smin(fist, fing, .05), thumb), cuff);`,

  check: `
    float t = .08 * sin(uTime * 2.);
    float a = cap(p, vec3(-.68, .02, 0.), vec3(-.22, -.5, 0.), .16);
    float b = cap(p, vec3(-.22, -.5, 0.), vec3(.72, .6 + t, 0.), .16);
    return min(a, b);`,
});
