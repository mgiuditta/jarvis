// Shapes batch (characters-2): same contract as shapes.js. Homages, not copies of anyone's design.
Object.assign(ORB_SHAPES, {
  cowboy: `
    float d = ell(p - vec3(0., -.14, 0.), vec3(.3, .34, .3));                          // head
    d = smin(d, cap(p, vec3(0., -.35, 0.), vec3(0., -.55, 0.), .15), .1);             // neck
    d = smin(d, ell(p - vec3(0., -.8, 0.), vec3(.62, .26, .36)), .15);                // shoulders
    d = max(d, -(length(p - vec3(-.11, -.12, .28)) - .05));                          // eyes
    d = max(d, -(length(p - vec3(.11, -.12, .28)) - .05));
    vec3 q = p - vec3(0., .14, 0.);
    q.y -= .45 * q.x * q.x;                                                           // brim curls up at the sides
    float brim = (cyl(q, .74, .025) - .025) * .75;
    vec3 c = p - vec3(0., .3, 0.);
    float crown = ell(c, vec3(.36, .48, .34));
    crown = max(crown, -ell(c - vec3(0., .5, 0.), vec3(.07, .14, .4)));               // dent on top
    crown = max(crown, -(c.y + .14));
    return min(d, min(brim, crown));`,

  cat: `
    float d = ell(p - vec3(0., -.08, 0.), vec3(.64, .52, .48));
    for (int i = -1; i <= 1; i += 2) {
      float s = float(i);
      vec3 q = p - vec3(s * .36, .3, 0.);
      q.xy = rot(s * .4) * q.xy;
      d = smin(d, rcone(q, .22, .03, .42), .06);                                     // ear
      d = max(d, -ell(p - vec3(s * .22, 0., .44), vec3(.08, .12, .12)));             // eye slit
      d = min(d, cap(p, vec3(s * .26, -.2, .4), vec3(s * .88, -.1, .3), .018));      // whiskers
      d = min(d, cap(p, vec3(s * .26, -.25, .4), vec3(s * .86, -.32, .3), .018));
    }
    d = min(d, ell(p - vec3(0., -.14, .47), vec3(.08, .05, .05)));                   // nose
    return d;`,

  dog: `
    float d = ell(p - vec3(0., .05, 0.), vec3(.5, .52, .45));
    d = smin(d, ell(p - vec3(0., -.22, .33), vec3(.3, .22, .3)), .12);                // snout
    d = min(d, ell(p - vec3(0., -.14, .62), vec3(.12, .08, .08)));                   // nose
    float sw = .15 * sin(uTime * 2.);
    for (int i = -1; i <= 1; i += 2) {
      float s = float(i);
      vec3 q = p - vec3(s * .52, .05, 0.);
      q.xy = rot(s * (.25 + sw)) * (q.xy + vec2(0., -.3)) - vec2(0., -.3);
      d = smin(d, ell(q - vec3(0., -.12, 0.), vec3(.16, .4, .12)), .05);             // floppy ear
      d = max(d, -(length(p - vec3(s * .2, .18, .4)) - .08));                        // eye
    }
    d = max(d, -cap(p, vec3(-.12, -.36, .5), vec3(.12, -.36, .5), .025));            // mouth
    return d;`,

  owl: `
    float d = ell(p - vec3(0., -.1, 0.), vec3(.62, .82, .52));
    for (int i = -1; i <= 1; i += 2) {
      float s = float(i);
      vec3 q = p - vec3(s * .27, .22, .42);
      d = min(d, cyl(q.xzy, .25, .07) - .02);                                        // eye disc
      d = max(d, -(length(p - vec3(s * .27, .22, .56)) - .11));                      // pupil
      vec3 t = p - vec3(s * .36, .6, 0.);
      t.xy = rot(-s * .5) * t.xy;
      d = smin(d, rcone(t, .14, .02, .38), .05);                                     // ear tuft
      d = smin(d, ell(p - vec3(s * .56, -.2, -.05), vec3(.12, .45, .3)), .06);       // wing
    }
    vec3 b = p - vec3(0., .1, .5);
    d = min(d, rcone(vec3(b.x, -b.y, b.z), .07, .01, .2));                           // beak
    d = min(d, ell(p - vec3(-.18, -.9, .2), vec3(.14, .05, .12)));                    // feet
    d = min(d, ell(p - vec3(.18, -.9, .2), vec3(.14, .05, .12)));
    return d;`,

  dragon: `
    float f = sin(uTime * 2.5) * .25;
    float d = ell(p - vec3(0., -.55, 0.), vec3(.42, .38, .36));                      // body
    d = smin(d, cap(p, vec3(0., -.45, 0.), vec3(0., .25, .05), .18), .15);           // neck
    d = smin(d, ell(p - vec3(0., .4, .18), vec3(.33, .28, .46)), .12);              // head, snout forward
    for (int i = -1; i <= 1; i += 2) {
      float s = float(i);
      vec3 h = p - vec3(s * .16, .55, -.05);
      h.yz = rot(.6) * h.yz;
      d = min(d, rcone(h, .07, .01, .35));                                           // horn
      d = max(d, -(length(p - vec3(s * .15, .45, .5)) - .06));                       // eye
      vec3 w = p - vec3(s * .55, -.2, -.15);
      w.xy = rot(s * (-.5 + f)) * w.xy;
      float wing = box(w, vec3(.42, .3, .02), .01);
      wing = max(wing, dot(w.xy, normalize(vec2(-s * .6, 1.))) - .05);               // triangular membrane
      d = min(d, wing);
    }
    d = smin(d, cap(p, vec3(0., -.8, -.1), vec3(.25 * sin(uTime), -1., -.4), .07), .1); // tail
    return d;`,

  dino: `
    vec3 q = p; q.xz = rot(.4 + .1 * sin(uTime * .8)) * q.xz;                         // 3/4 view, facing +x
    vec3 b = q - vec3(-.1, -.05, 0.); b.xy = rot(.3) * b.xy;
    float d = ell(b, vec3(.46, .32, .28));                                            // body
    d = smin(d, cap(q, vec3(.18, .1, 0.), vec3(.36, .36, 0.), .17), .1);              // neck
    d = smin(d, box(q - vec3(.5, .46, 0.), vec3(.28, .13, .15), .08), .08);           // skull
    d = smin(d, box(q - vec3(.5, .27, 0.), vec3(.24, .05, .12), .04), .04);           // jaw
    d = max(d, -box(q - vec3(.66, .37, 0.), vec3(.2, .022, .3), 0.));                 // mouth gap
    d = max(d, -(length(q - vec3(.55, .53, .14)) - .05));                             // eye
    vec3 t = q - vec3(-.45, -.12, 0.);
    vec2 dir = normalize(vec2(-1., -.4));
    d = smin(d, rcone(vec3(dot(t.xy, vec2(-dir.y, dir.x)), dot(t.xy, dir), t.z), .22, .03, .58), .1); // tail
    for (int i = -1; i <= 1; i += 2) {
      float s = float(i);
      d = smin(d, cap(q, vec3(-.05, -.25, s * .13), vec3(0., -.82, s * .15), .11), .06); // leg
      d = smin(d, ell(q - vec3(.08, -.9, s * .15), vec3(.16, .06, .1)), .04);          // foot
    }
    d = min(d, cap(q, vec3(.28, -.02, .12), vec3(.42, -.1, .2), .04));               // tiny arm
    return d;`,

  octopus: `
    float d = ell(p - vec3(0., .3, 0.), vec3(.5, .55, .48));
    d = max(d, -(length(p - vec3(-.18, .22, .44)) - .09));
    d = max(d, -(length(p - vec3(.18, .22, .44)) - .09));
    for (int i = 0; i < 8; i++) {
      float a = float(i) * .785 + .39;
      float w = sin(uTime * 2. + float(i) * 1.3) * .15;
      vec3 s = vec3(cos(a) * .3, -.05, sin(a) * .3);
      vec3 e = vec3(cos(a + w) * .82, -.72 + w, sin(a + w) * .6);
      d = smin(d, cap(p, s, e, .08), .12);
    }
    return d;`,

  penguin: `
    float d = ell(p - vec3(0., -.08, 0.), vec3(.5, .78, .44));
    d = smin(d, ell(p - vec3(0., -.2, .18), vec3(.38, .55, .32)), .05);               // belly
    vec3 b = p - vec3(0., .32, .38);
    d = min(d, rcone(vec3(b.x, b.z, -b.y), .08, .01, .22));                          // beak, forward
    d = max(d, -(length(p - vec3(-.15, .42, .36)) - .06));                            // eyes
    d = max(d, -(length(p - vec3(.15, .42, .36)) - .06));
    float f = sin(uTime * 3.) * .2;
    for (int i = -1; i <= 1; i += 2) {
      float s = float(i);
      vec3 w = p - vec3(s * .5, 0., 0.);
      w.xy = rot(s * (.35 + f)) * (w.xy - vec2(0., .2)) + vec2(0., .2);
      d = smin(d, ell(w - vec3(0., -.15, 0.), vec3(.09, .38, .16)), .04);              // flipper
      d = min(d, ell(p - vec3(s * .18, -.86, .15), vec3(.15, .05, .2)));               // foot
    }
    return d;`,

  unicorn: `
    vec3 q = p; q.xz = rot(.55) * q.xz;                                               // 3/4 profile, facing +x
    float d = cap(q, vec3(-.18, .3, 0.), vec3(.35, -.15, 0.), .22);                   // skull → muzzle
    d = smin(d, length(q - vec3(.4, -.2, 0.)) - .2, .1);                              // muzzle
    d = smin(d, cap(q, vec3(-.22, .25, 0.), vec3(-.42, -.85, 0.), .26), .12);         // neck
    d = min(d, rcone((q - vec3(-.2, .5, .08)) * vec3(1., 1., 1.), .07, .02, .22));   // ear
    vec3 h = q - vec3(-.02, .5, 0.); h.xy = rot(-.6) * h.xy;
    float horn = rcone(h, .085, .01, .58);
    horn += .012 * sin(h.y * 60. + atan(h.z, h.x) * 1.);                               // spiral ridges
    d = min(d, horn);
    for (int i = 0; i < 5; i++) {
      float t = float(i) / 4.;
      d = smin(d, length(q - vec3(-.42 - .08 * sin(uTime * 2. + t * 6.), .35 - t * 1.05, 0.)) - .13, .08); // mane
    }
    d = max(d, -(length(q - vec3(.05, .25, .18)) - .05));                             // eye
    d = max(d, -(length(q - vec3(.5, -.18, .14)) - .04));                             // nostril
    return d;`,

  slime: `
    float b = abs(sin(uTime * 2.2));
    vec3 q = p - vec3(0., -.1 + .12 * b, 0.);
    q.y /= .85 + .15 * b;                                                             // squash and stretch
    float d = ell(q - vec3(0., -.28, 0.), vec3(.78, .5, .62));
    d = smin(d, rcone(q - vec3(0., -.1, 0.), .46, .04, .72), .2);                     // drop tip
    d *= .85;
    d = max(d, -ell(p - vec3(-.22, -.18 + .1 * b, .52), vec3(.07, .13, .2)));         // eyes
    d = max(d, -ell(p - vec3(.22, -.18 + .1 * b, .52), vec3(.07, .13, .2)));
    return d;`,

  mushroom: `
    vec3 c = p - vec3(0., .12, 0.);
    float cap_ = ell(c, vec3(.82, .6, .82));
    cap_ = max(cap_, -(c.y + .02));                                                   // dome only
    for (int i = 0; i < 5; i++) {
      float a = float(i) * 1.256 + .6;
      vec3 sp = vec3(cos(a) * .55, .32, sin(a) * .5 + .12);
      if (i == 4) sp = vec3(0., .6, .1);
      cap_ = min(cap_, max(length(c - sp) - .19, ell(c, vec3(.86, .64, .86))));        // raised spots, hugging the dome
    }
    float stem = ell(p - vec3(0., -.38, 0.), vec3(.42, .46, .4));
    stem = max(stem, -ell(p - vec3(-.14, -.3, .38), vec3(.06, .12, .12)));            // eyes
    stem = max(stem, -ell(p - vec3(.14, -.3, .38), vec3(.06, .12, .12)));
    return min(cap_, stem);`,

  qblock: `
    vec3 q = p - vec3(0., .06 * sin(uTime * 2.5), 0.);
    float d = box(q, vec3(.62), .07);
    vec3 m = q - vec3(0., .16, .62);                                                  // the "?" on the front face
    float arc = max(length(vec2(length(m.xy) - .22, m.z)) - .075, -m.y);              // upper half ring
    float mark = min(arc, cap(q, vec3(.22, .16, .62), vec3(0., -.06, .62), .075));   // hook back to the center
    mark = min(mark, cap(q, vec3(0., -.06, .62), vec3(0., -.18, .62), .075));         // stem
    mark = min(mark, length(q - vec3(0., -.38, .62)) - .085);                          // dot
    for (int i = 0; i < 4; i++) {                                                     // rivets in the corners
      vec2 r = vec2(i < 2 ? -.47 : .47, (i == 0 || i == 2) ? -.47 : .47);
      mark = min(mark, length(q - vec3(r, .63)) - .045);
    }
    return min(d, mark);`,
});
