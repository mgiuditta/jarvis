// Shapes batch (characters-1): same contract as shapes.js. Homages, not copies.
Object.assign(ORB_SHAPES, {
  plumber: `
    float head = length(p - vec3(0., .05, 0.)) - .46;
    float capTop = max(length(p - vec3(0., .1, -.02)) - .54, -(p.y - .16));
    float brim = ell(p - vec3(0., .18, .36), vec3(.46, .07, .34));
    float nose = length(p - vec3(0., -.02, .46)) - .17;
    vec3 m = p - vec3(0., -.19, .4); m.x = abs(m.x) - .17; m.xy = rot(.35) * m.xy;
    float stache = ell(m, vec3(.24, .1, .12));
    float body = ell(p - vec3(0., -.78, 0.), vec3(.72, .34, .4));
    float d = smin(head, body, .15);
    d = min(d, min(capTop, brim));
    return min(min(d, nose), stache);`,

  ghost: `
    float top = length(p - vec3(0., .15, 0.)) - .68;
    float skirt = cyl(p - vec3(0., -.22, 0.), .68, .37);
    float d = min(top, skirt);
    float w = -.62 + .1 * sin(atan(p.z, p.x) * 6. + uTime * 3.);
    d = max(d, w - p.y);
    vec3 e = p - vec3(0., .22, .58); e.x = abs(e.x) - .24;
    d = max(d, -ell(e, vec3(.13, .17, .2)));
    return d;`,

  chomper: `
    vec3 q = p - vec3(-.18, 0., 0.);
    float s = length(q) - .8;
    float a = .15 + .45 * abs(sin(uTime * 4.));
    vec2 w = vec2(q.x, abs(q.y));
    float wedge = max(dot(w, vec2(-sin(a), cos(a))), -q.x + .02);
    float d = max(s, -wedge);
    d = max(d, -(length(q - vec3(.08, .45, .6)) - .1));
    float t = fract(uTime * .7);
    float pel = min(length(p - vec3(.95 - t * .3, 0., 0.)) - .1, length(p - vec3(1.3 - t * .3, 0., 0.)) - .1);
    return min(d, pel);`,

  invader: `
    vec3 q = p; q.x = abs(q.x);
    float leg = step(0., sin(uTime * 4.)) * .15;
    float d = box(q - vec3(0., .02, 0.), vec3(.6, .23, .13), .01);
    d = min(d, box(q - vec3(0., .32, 0.), vec3(.3, .09, .13), .01));
    d = min(d, box(q - vec3(.3, .47, 0.), vec3(.075, .075, .13), .01));
    d = min(d, box(q - vec3(.45, .62, 0.), vec3(.075, .075, .13), .01));
    d = min(d, box(q - vec3(.75, -.05 + leg, 0.), vec3(.075, .3, .13), .01));
    d = min(d, box(q - vec3(.45, -.38, 0.), vec3(.075, .14, .13), .01));
    d = min(d, box(q - vec3(.22 + leg, -.55, 0.), vec3(.14, .075, .13), .01));
    d = max(d, -box(q - vec3(.22, .07, 0.), vec3(.075, .075, .3), 0.));
    return d;`,

  bean: `
    float body = cap(p, vec3(0., -.2, 0.), vec3(0., .35, 0.), .5);
    vec3 l = p; l.x = abs(l.x) - .22;
    float legs = cap(l, vec3(0., -.72, 0.), vec3(0., -.5, 0.), .2);
    float d = smin(body, legs, .08);
    float visor = ell(p - vec3(.1, .32, .38), vec3(.33, .18, .16));
    float pack = box(p - vec3(0., -.05, -.52), vec3(.3, .36, .14), .1);
    return min(min(d, visor), pack);`,

  hero: `
    vec3 q = p * 1.25;
    float s = sin(uTime * 2.);
    float d = length(q - vec3(0., 1., 0.)) - .34;
    d = smin(d, cap(q, vec3(0., .55, 0.), vec3(0., -.35, 0.), .4), .25);
    d = smin(d, cap(q, vec3(-.44, .45, 0.), vec3(-.55, -.2, .15), .13), .15);
    d = smin(d, cap(q, vec3(.44, .45, 0.), vec3(.95, 1.2, 0.), .13), .15);
    d = smin(d, cap(q, vec3(-.18, -.4, 0.), vec3(-.3, -1.3, 0.), .16), .15);
    d = smin(d, cap(q, vec3(.18, -.4, 0.), vec3(.3, -1.3, 0.), .16), .15);
    vec3 c = q - vec3(0., -.25, -.42);
    c.x /= 1. + (.6 - c.y) * .35;
    c.z += .12 * sin(c.y * 3. + uTime * 4.) - .15 * (.6 - c.y);
    float cape = box(c, vec3(.42, .85, .02), .01);
    vec3 e = q - vec3(0., .35, .4); e.xy = rot(.785) * e.xy;
    float emb = box(e, vec3(.12, .12, .04), .01);
    return min(min(d, cape * .8), emb) / 1.25;`,

  knight: `
    float helm = cap(p, vec3(0., -.05, 0.), vec3(0., .38, 0.), .44);
    helm = max(helm, -box(p - vec3(0., .2, .45), vec3(.32, .045, .2), 0.));
    helm = max(helm, -box(p - vec3(0., -.02, .45), vec3(.04, .16, .2), 0.));
    float ridge = box(p - vec3(0., .35, .1), vec3(.03, .45, .35), .02);
    ridge = max(ridge, length(p - vec3(0., .1, 0.)) - .52);
    float plume = cap(p, vec3(0., .82, 0.), vec3(0., .92 + .04 * sin(uTime * 2.), -.45), .11);
    plume = smin(plume, cap(p, vec3(0., .92, -.45), vec3(0., .65, -.75), .09), .1);
    float body = ell(p - vec3(0., -.78, 0.), vec3(.78, .32, .42));
    return min(min(smin(helm, body, .12), ridge), plume);`,

  ninja: `
    float head = length(p - vec3(0., .1, 0.)) - .55;
    head = max(head, -box(p - vec3(0., .15, .5), vec3(.34, .07, .15), .02));
    vec3 e = p - vec3(0., .15, .42); e.x = abs(e.x) - .15;
    float eyes = length(e) - .07;
    float band = torus(p - vec3(0., .38, 0.), .5, .06);
    float s = sin(uTime * 3.);
    float tails = min(cap(p, vec3(0., .38, -.48), vec3(-.55, .05 + .1 * s, -.8), .08), cap(p, vec3(0., .38, -.48), vec3(.5, -.1 - .1 * s, -.8), .08));
    float body = ell(p - vec3(0., -.75, 0.), vec3(.72, .32, .4));
    return min(min(smin(head, body, .15), eyes), min(band, tails));`,

  wizard: `
    vec3 h = p - vec3(0., .28, 0.); h.xy = rot(-.12) * h.xy;
    float hat = rcone(h, .5, .02, .88);
    float brim = cyl(p - vec3(0., .28, 0.), .78, .035);
    float head = length(p - vec3(0., .02, 0.)) - .38;
    vec3 b = p - vec3(0., -.12, .22); b.y = -b.y;
    float beard = rcone(b, .3, .05, .7);
    float body = ell(p - vec3(0., -.72, -.1), vec3(.62, .3, .36));
    return min(min(min(hat, brim), smin(head, beard, .08)), body);`,

  zombie: `
    vec3 q = p * 1.25; q.xz = rot(.75) * q.xz;
    float b = sin(uTime * 2.) * .08;
    float d = length(q - vec3(.1, .98, .05)) - .36;
    d = smin(d, cap(q, vec3(0., .55, 0.), vec3(0., -.35, 0.), .38), .25);
    d = smin(d, cap(q, vec3(-.42, .45, 0.), vec3(-.4, .5 + b, 1.), .13), .15);
    d = smin(d, cap(q, vec3(.42, .45, 0.), vec3(.4, .4 - b, 1.), .13), .15);
    d = smin(d, cap(q, vec3(-.18, -.4, 0.), vec3(-.3, -1.3, .2), .16), .15);
    d = smin(d, cap(q, vec3(.18, -.4, 0.), vec3(.22, -1.3, -.15), .16), .15);
    vec3 e = q - vec3(.1, 1.02, .38); e.x = abs(e.x - .0) - .13;
    d = max(d, -(length(e) - .08));
    return d / 1.25;`,

  pirate: `
    float head = length(p - vec3(0., .05, 0.)) - .44;
    vec2 xz = p.xz;
    float tri = max(max(dot(xz, vec2(0., 1.)), dot(xz, vec2(.866, -.5))), dot(xz, vec2(-.866, -.5))) - .42;
    float brim = max(max(abs(p.y - .4 - .5 * p.x * p.x) * .8 - .06, tri), length(p.xz) - .66);
    float crown = max(length(p - vec3(0., .38, 0.)) - .38, .38 - p.y);
    vec3 e = p - vec3(.17, .1, .4);
    float ep = cyl(e.xzy, .13, .04);
    float strap = cap(p, vec3(-.42, .32, .1), vec3(.44, -.08, .2), .03);
    strap = max(strap, -(length(p - vec3(0., .05, 0.)) - .43));
    float body = ell(p - vec3(0., -.78, 0.), vec3(.72, .32, .4));
    return min(min(smin(head, body, .15), min(brim, crown)), min(ep, strap));`,

  vampire: `
    float head = ell(p - vec3(0., .15, 0.), vec3(.36, .47, .38));
    vec3 c = p - vec3(0., .12, -.12); c.x = abs(c.x) - .34; c.xy = rot(.4) * c.xy; c.xz = rot(-.5) * c.xz;
    float collar = box(c, vec3(.13, .44, .025), .01);
    vec3 er = p - vec3(0., .2, 0.); er.x = abs(er.x) - .35; er.xy = rot(-1.2) * er.xy;
    float ears = rcone(er, .08, .01, .22);
    float body = ell(p - vec3(0., -.72, -.05), vec3(.9, .38, .45));
    body = min(body, box(p - vec3(0., -.55, 0.), vec3(.95, .06, .3), .05));
    vec3 f = p - vec3(0., -.12, .33); f.x = abs(f.x) - .07; f.y = -f.y;
    float fangs = rcone(f, .03, .005, .09);
    return min(min(smin(head, body, .12), collar), min(ears, fangs));`,

  alien: `
    float head = ell(p - vec3(0., .38, 0.), vec3(.58, .52, .48));
    head = smin(head, ell(p - vec3(0., .02, .05), vec3(.26, .3, .28)), .2);
    vec3 e = p - vec3(0., .3, .44); e.x = abs(e.x) - .24; e.xy = rot(.5) * e.xy;
    head = max(head, -ell(e, vec3(.2, .09, .18)));
    float neck = cap(p, vec3(0., -.15, 0.), vec3(0., -.9, 0.), .14);
    float s = sin(uTime * 1.5) * .1;
    vec3 a = p; a.x = abs(a.x);
    float arms = cap(a, vec3(.1, -.35, 0.), vec3(.45, -.8 + s, .1), .06);
    return min(smin(head, neck, .1), arms);`,

  skeleton: `
    float skull = length(p - vec3(0., .22, 0.)) - .56;
    skull = smin(skull, box(p - vec3(0., -.12, .06), vec3(.3, .18, .3), .12), .12);
    vec3 e = p - vec3(0., .18, .47); e.x = abs(e.x) - .2;
    skull = max(skull, -(length(e) - .16));
    skull = max(skull, -ell(p - vec3(0., -.02, .55), vec3(.06, .09, .15)));
    float o = .02 + .04 * abs(sin(uTime * 3.));
    float jaw = box(p - vec3(0., -.38 - o, .1), vec3(.27, .08, .25), .06);
    vec3 t = p - vec3(0., -.27, .37); t.x = mod(t.x + .06, .12) - .06;
    float teeth = max(box(t, vec3(.035, .05, .04), .01), abs(p.x) - .22);
    return min(min(skull, jaw), teeth);`,

  detective: `
    float head = length(p - vec3(0., .02, 0.)) - .42;
    vec3 hp = p - vec3(0., .42, 0.); hp.xy = rot(.1) * hp.xy;
    float crown = cyl(hp - vec3(0., .16, 0.), .4, .17);
    crown = max(crown, -box(hp - vec3(0., .36, 0.), vec3(.05, .06, .5), .02));
    float brim = cyl(hp, .72, .03);
    float band = cyl(hp - vec3(0., .06, 0.), .41, .05);
    float bowl = cyl(p - vec3(.42, -.2, .42), .1, .12);
    bowl = max(bowl, -cyl(p - vec3(.42, -.12, .42), .06, .12));
    float stem = cap(p, vec3(.1, -.2, .4), vec3(.38, -.3, .42), .035);
    float body = ell(p - vec3(0., -.78, 0.), vec3(.75, .32, .42));
    return min(min(smin(head, body, .15), min(crown, min(brim, band))), min(bowl, stem));`,
});
