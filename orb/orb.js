// Holographic orb (three.js). Driven from Swift: orb.set({ state, level, color }).
// Look approved in docs/superpowers/specs/assets/orb-prototype.html.
(() => {
  const { Color, Vector2, Vector3 } = THREE;
  const rnd = (a, b) => a + Math.random() * (b - a);

  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setClearColor(0x05020a, 1);
  document.body.appendChild(renderer.domElement);
  const scene = new THREE.Scene();
  scene.fog = new THREE.FogExp2(0x05020a, 0.05);
  const camera = new THREE.PerspectiveCamera(55, 1, 0.1, 100);
  camera.position.set(0, 0, 6.2);

  const composer = new THREE.EffectComposer(renderer);
  composer.addPass(new THREE.RenderPass(scene, camera));
  const bloom = new THREE.UnrealBloomPass(new Vector2(256, 256), 1.6, 0.9, 0.02);
  composer.addPass(bloom);

  // Palette derived from one base color; every material keeps its role so recoloring is one loop.
  const tint = { main: new Color(), light: new Color(), deep: new Color(), core: new Color('#f3eaff') };
  const colored = []; // [material, role, base opacity]
  const mat = (m, role) => (colored.push([m, role, m.opacity]), m);
  const lineMat = (role, opacity) => mat(new THREE.LineBasicMaterial({ transparent: true, opacity, blending: THREE.AdditiveBlending, depthWrite: false }), role);
  const glowMat = (role, opacity) => mat(new THREE.MeshBasicMaterial({ transparent: true, opacity, blending: THREE.AdditiveBlending }), role);

  const orb = new THREE.Group(); scene.add(orb);
  const add = (o) => (orb.add(o), o);
  const arcPoints = (r, a0, a1, n = 64) => Array.from({ length: n + 1 }, (_, i) => {
    const a = a0 + (a1 - a0) * i / n; return new Vector3(Math.cos(a) * r, Math.sin(a) * r, 0);
  });
  const line = (pts, m) => new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), m);
  const randomAxis = () => new Vector3(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)).normalize();

  // 1. Tilted rings of broken arcs, each spinning on its own axis; the first four carry a thick band.
  const rings = [];
  for (let i = 0; i < 12; i++) {
    const g = new THREE.Group(), r = rnd(1.2, 3.6);
    for (let a = rnd(0, Math.PI * 2), end = a + Math.PI * 2; a < end;) {
      const len = rnd(0.2, 1.4);
      g.add(line(arcPoints(r, a, a + len, 40), lineMat(i % 2 ? 'main' : 'light', rnd(0.4, 0.9))));
      a += len + rnd(0.05, 0.5);
    }
    if (i < 4) g.add(new THREE.Mesh(new THREE.TorusGeometry(r, 0.025, 6, 120, rnd(1, 2.5)), glowMat('main', 0.8)));
    g.rotation.set(rnd(0, Math.PI), rnd(0, Math.PI), 0);
    rings.push({ g, speed: rnd(-0.4, 0.4) || 0.2, axis: randomAxis() });
    add(g);
  }

  // 1b. HUD tick rings.
  for (const [R, n, len] of [[3.9, 180, 0.08], [2.1, 90, 0.12], [3.3, 60, 0.2]]) {
    const pts = [];
    for (let i = 0; i < n; i++) {
      const a = i / n * Math.PI * 2, l = i % 5 ? len : len * 2.2;
      pts.push(new Vector3(Math.cos(a) * R, Math.sin(a) * R, 0), new Vector3(Math.cos(a) * (R + l), Math.sin(a) * (R + l), 0));
    }
    const ticks = new THREE.LineSegments(new THREE.BufferGeometry().setFromPoints(pts), lineMat('light', 0.55));
    ticks.rotation.set(rnd(-0.6, 0.6), rnd(-0.6, 0.6), 0);
    rings.push({ g: ticks, speed: rnd(0.1, 0.3) * (Math.random() < 0.5 ? -1 : 1), axis: new Vector3(0, 0, 1) });
    add(ticks);
  }

  // 2. Wireframe shell: partial meridians + latitudes.
  const shell = new THREE.Group();
  for (let i = 0; i < 14; i++) {
    const m = line(arcPoints(2.6, rnd(0, 3), rnd(3, 6.3), 80), lineMat('main', 0.35));
    m.rotation.y = (i / 14) * Math.PI; shell.add(m);
  }
  for (let i = 1; i < 6; i++) {
    const y = -2.6 + i * (5.2 / 6);
    const l = line(arcPoints(Math.sqrt(2.6 * 2.6 - y * y), 0, Math.PI * 2, 96), lineMat('main', 0.22));
    l.rotation.x = Math.PI / 2; l.position.y = y; shell.add(l);
  }
  add(shell);

  // 3. Spokes from the core.
  for (let i = 0; i < 40; i++) {
    const d = randomAxis();
    add(line([d.clone().multiplyScalar(0.5), d.clone().multiplyScalar(rnd(2.5, 4.5))], lineMat('light', rnd(0.15, 0.45))));
  }

  // 4. Circuit traces: short manhattan walks on a sphere.
  const traces = new THREE.Group();
  for (let i = 0; i < 220; i++) {
    let lat = rnd(-1.2, 1.2), lon = rnd(0, Math.PI * 2);
    const R = rnd(2.7, 3.4), pts = [];
    for (let s = 0, n = 4 + (Math.random() * 10 | 0); s < n; s++) {
      pts.push(new Vector3(R * Math.cos(lat) * Math.cos(lon), R * Math.sin(lat), R * Math.cos(lat) * Math.sin(lon)));
      if (Math.random() < 0.5) lon += rnd(-0.25, 0.25); else lat += rnd(-0.2, 0.2);
    }
    traces.add(line(pts, lineMat(Math.random() < 0.3 ? 'light' : 'main', rnd(0.4, 1))));
  }
  add(traces);

  // 5. Core: tunnel of stacked rings + bright heart. Faces the camera, doesn't tumble.
  const core = new THREE.Group();
  for (let i = 0; i < 8; i++) {
    const t = new THREE.Mesh(new THREE.TorusGeometry(0.35 + i * 0.07, 0.012, 8, 80), glowMat(i < 3 ? 'core' : 'light', 1 - i * 0.1));
    t.position.z = -i * 0.12; core.add(t);
  }
  core.add(new THREE.Mesh(new THREE.SphereGeometry(0.22, 32, 32), mat(new THREE.MeshBasicMaterial(), 'core')));
  scene.add(core);

  // 6. Bokeh / dust.
  const N = 3500, pos = new Float32Array(N * 3), size = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    const d = randomAxis().multiplyScalar(Math.sqrt(Math.random()) * 4.2);
    pos.set([d.x, d.y, d.z], i * 3); size[i] = Math.random() < 0.04 ? rnd(14, 28) : rnd(1.5, 5);
  }
  const pGeo = new THREE.BufferGeometry();
  pGeo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  pGeo.setAttribute('size', new THREE.BufferAttribute(size, 1));
  const pMat = new THREE.ShaderMaterial({
    uniforms: { color: { value: tint.light }, level: { value: 0 }, scale: { value: 1 } },
    vertexShader: `attribute float size; uniform float level; uniform float scale; varying float vA;
      void main(){ vec4 mv = modelViewMatrix * vec4(position,1.); gl_PointSize = size * scale * (1. + level) * (6. / -mv.z); vA = size > 10. ? .25 : .9; gl_Position = projectionMatrix * mv; }`,
    fragmentShader: `uniform vec3 color; varying float vA;
      void main(){ float d = length(gl_PointCoord - .5); if (d > .5) discard; gl_FragColor = vec4(color, vA * smoothstep(.5, .0, d)); }`,
    transparent: true, blending: THREE.AdditiveBlending, depthWrite: false,
  });
  const particles = new THREE.Points(pGeo, pMat); add(particles);

  // State → motion. `level` is the real voice level from Swift (0…1).
  const STATES = {
    idle:      { spin: 0.25, bloom: 1.0, pulse: () => 0.05 },
    listening: { spin: 0.5,  bloom: 1.3, pulse: (t) => 0.15 + 0.08 * Math.sin(t * 2.5) },
    thinking:  { spin: 1.8,  bloom: 1.5, pulse: (t) => 0.25 + 0.1 * Math.sin(t * 3) },
    speaking:  { spin: 0.7,  bloom: 1.5, pulse: () => 0.15 },
    confirm:   { spin: 0.6,  bloom: 1.4, pulse: (t) => 0.3 + 0.15 * Math.sin(t * 4), color: '#ffb020' },
    error:     { spin: 0.2,  bloom: 0.8, pulse: (t) => (Math.sin(t * 20) > 0.6 ? 0.3 : 0.05), color: '#ff3b3b' },
  };
  let state = 'idle', level = 0, voice = 0, baseColor = '#9b5cff', shownColor = '';

  function applyColor(hex) {
    if (hex === shownColor) return;
    shownColor = hex;
    tint.main.set(hex);
    tint.light.set(hex).lerp(new Color('#ffffff'), 0.55);
    tint.deep.set(hex).multiplyScalar(0.6);
    for (const [m, role] of colored) m.color.copy(tint[role]);
  }

  // Tuned at ~700 px. Smaller: render at higher density so lines stay hairline, and fade lines + bloom.
  let small = 1;
  function resize() {
    const w = innerWidth, h = innerHeight;
    small = Math.min(1, h / 700);
    renderer.setPixelRatio(Math.min(3, Math.max(devicePixelRatio, 700 / h)));
    renderer.setSize(w, h); composer.setSize(w, h);
    for (const [m, , o] of colored) m.opacity = o * (0.45 + 0.55 * small);
    // Same geometry in fewer pixels reads as a violet fog: show a share of the traces and dust.
    const share = Math.max(0.3, small);
    traces.children.forEach((c, i) => (c.visible = i < traces.children.length * share));
    pGeo.setDrawRange(0, Math.round(N * share));
    bloom.threshold = 0.02 + 0.2 * (1 - small);
    camera.aspect = w / h; camera.updateProjectionMatrix();
    pMat.uniforms.scale.value = renderer.getPixelRatio() * h / 1400; // gl_PointSize is in device px; tuned at 700 px × DPR 2
  }
  addEventListener('resize', resize); resize();

  window.orb = {
    set(o) {
      if (o.state in STATES) state = o.state;
      if (typeof o.level === 'number') voice = Math.max(0, Math.min(1, o.level));
      if (o.color) baseColor = o.color;
    },
  };

  const clock = new THREE.Clock();
  renderer.setAnimationLoop(() => {
    const dt = Math.min(clock.getDelta(), 0.1), t = clock.elapsedTime, c = STATES[state];
    applyColor(c.color ?? baseColor);
    level += (c.pulse(t) + voice * 0.8 - level) * 0.2;
    for (const r of rings) r.g.rotateOnAxis(r.axis, r.speed * c.spin * dt);
    shell.rotation.y += 0.05 * c.spin * dt;
    traces.rotation.y -= 0.08 * c.spin * dt;
    particles.rotation.y += 0.03 * dt;
    orb.rotation.set(0.3, orb.rotation.y + 0.04 * dt, 0);
    orb.scale.setScalar(1 + level * 0.08);
    core.scale.setScalar(1 + level * 0.6);
    core.children.forEach((m, i) => (m.rotation.z = t * (0.5 + i * 0.2) * (i % 2 ? -1 : 1)));
    pMat.uniforms.level.value = level;
    bloom.strength = (c.bloom + level * 1.2) * (0.35 + 0.65 * small);
    composer.render();
  });
})();
