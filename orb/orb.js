// Liquid blob orb (three.js). Driven from Swift: orb.set({ state, level, color }).
// Noise-displaced sphere with recomputed normals, fresnel rim and a soft iridescent sheen, halo + dust.
// Transparent canvas (no bloom pass): the glow comes from the rim and the halo, so the blob floats on the desktop.
(() => {
  const { Color, Vector3 } = THREE;

  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, premultipliedAlpha: false });
  renderer.setClearColor(0x000000, 0);
  document.body.appendChild(renderer.domElement);
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(55, 1, 0.1, 100);
  camera.position.set(0, 0, 6.2);

  const tint = { main: new Color(), light: new Color(), deep: new Color() };

  // Ashima 3D simplex noise (MIT).
  const NOISE = `
    vec3 mod289(vec3 x){return x-floor(x*(1./289.))*289.;} vec4 mod289(vec4 x){return x-floor(x*(1./289.))*289.;}
    vec4 permute(vec4 x){return mod289(((x*34.)+1.)*x);} vec4 taylorInvSqrt(vec4 r){return 1.79284291400159-.85373472095314*r;}
    float snoise(vec3 v){
      const vec2 C=vec2(1./6.,1./3.); const vec4 D=vec4(0.,.5,1.,2.);
      vec3 i=floor(v+dot(v,C.yyy)); vec3 x0=v-i+dot(i,C.xxx);
      vec3 g=step(x0.yzx,x0.xyz); vec3 l=1.-g; vec3 i1=min(g.xyz,l.zxy); vec3 i2=max(g.xyz,l.zxy);
      vec3 x1=x0-i1+C.xxx; vec3 x2=x0-i2+C.yyy; vec3 x3=x0-D.yyy; i=mod289(i);
      vec4 p=permute(permute(permute(i.z+vec4(0.,i1.z,i2.z,1.))+i.y+vec4(0.,i1.y,i2.y,1.))+i.x+vec4(0.,i1.x,i2.x,1.));
      float n_=.142857142857; vec3 ns=n_*D.wyz-D.xzx; vec4 j=p-49.*floor(p*ns.z*ns.z);
      vec4 x_=floor(j*ns.z); vec4 y_=floor(j-7.*x_); vec4 x=x_*ns.x+ns.yyyy; vec4 y=y_*ns.x+ns.yyyy; vec4 h=1.-abs(x)-abs(y);
      vec4 b0=vec4(x.xy,y.xy); vec4 b1=vec4(x.zw,y.zw); vec4 s0=floor(b0)*2.+1.; vec4 s1=floor(b1)*2.+1.; vec4 sh=-step(h,vec4(0.));
      vec4 a0=b0.xzyw+s0.xzyw*sh.xxyy; vec4 a1=b1.xzyw+s1.xzyw*sh.zzww;
      vec3 p0=vec3(a0.xy,h.x); vec3 p1=vec3(a0.zw,h.y); vec3 p2=vec3(a1.xy,h.z); vec3 p3=vec3(a1.zw,h.w);
      vec4 norm=taylorInvSqrt(vec4(dot(p0,p0),dot(p1,p1),dot(p2,p2),dot(p3,p3))); p0*=norm.x; p1*=norm.y; p2*=norm.z; p3*=norm.w;
      vec4 m=max(.6-vec4(dot(x0,x0),dot(x1,x1),dot(x2,x2),dot(x3,x3)),0.); m=m*m;
      return 42.*dot(m*m,vec4(dot(p0,x0),dot(p1,x1),dot(p2,x2),dot(p3,x3)));
    }`;

  // 1. The blob.
  const uniforms = {
    uTime: { value: 0 }, uAmp: { value: 0.12 }, uFreq: { value: 0.9 }, uGlow: { value: 1 },
    uMain: { value: tint.main }, uLight: { value: tint.light }, uDeep: { value: tint.deep },
  };
  const blob = new THREE.Mesh(new THREE.IcosahedronGeometry(1.45, 48), new THREE.ShaderMaterial({
    uniforms,
    vertexShader: NOISE + `
      uniform float uTime, uAmp, uFreq;
      varying vec3 vN, vView; varying float vNoise;
      float field(vec3 p){ return snoise(p*uFreq + vec3(0., uTime*.35, 0.)) * .85 + snoise(p*uFreq*1.9 - uTime*.4) * .15; }
      vec3 displace(vec3 p){ return p * (1. + uAmp * field(p)); }
      void main(){
        vec3 n = normalize(normal);
        vec3 t = normalize(abs(n.y) > .99 ? cross(n, vec3(1.,0.,0.)) : cross(n, vec3(0.,1.,0.)));
        vec3 b = cross(n, t);
        vec3 p = displace(position);
        // Normals of the displaced surface from two nearby points: real shading instead of the sphere's.
        vec3 dn = normalize(cross(displace(position + t*.01) - p, displace(position + b*.01) - p));
        vNoise = field(position);
        vN = normalize(normalMatrix * dn);
        vec4 mv = modelViewMatrix * vec4(p, 1.);
        vView = -mv.xyz;
        gl_Position = projectionMatrix * mv;
      }`,
    fragmentShader: `
      uniform vec3 uMain, uLight, uDeep; uniform float uTime, uGlow;
      varying vec3 vN, vView; varying float vNoise;
      void main(){
        vec3 N = normalize(vN), V = normalize(vView);
        float fres = pow(1. - max(dot(N, V), 0.), 2.2);
        vec3 L = normalize(vec3(-.5, .8, .7));
        float diff = max(dot(N, L), 0.);
        float spec = pow(max(dot(reflect(-L, N), V), 0.), 60.);
        float spec2 = pow(max(dot(reflect(-normalize(vec3(.7,-.4,.5)), N), V), 0.), 20.) * .25;
        vec3 irid = .5 + .5 * cos(6.2831 * (vec3(0., .33, .67) + fres * .9 + vNoise * .25 + uTime * .03));
        vec3 col = mix(uDeep * .55, uMain, diff * .75 + .15);
        col += uLight * smoothstep(.1, .9, vNoise) * .18;           // soft inner veins
        col = mix(col, irid * uLight, fres * .35);                   // thin-film sheen at the edge
        col += uLight * fres * 1.1 * uGlow;                          // rim light
        col += vec3(1.) * spec * .9 + uLight * spec2;
        gl_FragColor = vec4(col, 1.);
        #include <colorspace_fragment>
      }`,
  }));
  scene.add(blob);

  // 2. Halo behind the blob: a camera-facing quad with a radial falloff.
  const haloMat = new THREE.ShaderMaterial({
    uniforms: { color: { value: tint.main }, strength: { value: 0.6 } },
    vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }`,
    fragmentShader: `uniform vec3 color; uniform float strength; varying vec2 vUv;
      void main(){ float d = length(vUv - .5) * 2.; gl_FragColor = vec4(color, strength * pow(max(1. - d, 0.), 2.2));
        #include <colorspace_fragment>
      }`,
    transparent: true, depthWrite: false,
  });
  const halo = new THREE.Mesh(new THREE.PlaneGeometry(5.6, 5.6), haloMat);
  halo.position.z = -1.5;
  scene.add(halo);

  // 3. Dust orbiting the blob.
  const N = 700, pos = new Float32Array(N * 3), size = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    const d = new Vector3().randomDirection().multiplyScalar(1.9 + Math.random() * 1.3);
    pos.set([d.x, d.y, d.z], i * 3); size[i] = 1 + Math.random() * 2.5;
  }
  const pGeo = new THREE.BufferGeometry();
  pGeo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  pGeo.setAttribute('size', new THREE.BufferAttribute(size, 1));
  const pMat = new THREE.ShaderMaterial({
    uniforms: { color: { value: tint.light }, level: { value: 0 }, scale: { value: 1 } },
    vertexShader: `attribute float size; uniform float level; uniform float scale; varying float vA;
      void main(){ vec4 mv = modelViewMatrix * vec4(position,1.); gl_PointSize = size * scale * (1. + level) * (6. / -mv.z); vA = .55; gl_Position = projectionMatrix * mv; }`,
    fragmentShader: `uniform vec3 color; varying float vA;
      void main(){ float d = length(gl_PointCoord - .5); if (d > .5) discard; gl_FragColor = vec4(color, vA * smoothstep(.5, .0, d));
        #include <colorspace_fragment>
      }`,
    transparent: true, blending: THREE.AdditiveBlending, depthWrite: false,
  });
  const particles = new THREE.Points(pGeo, pMat); scene.add(particles);

  // 4. Voice ripples: rings spreading out from the blob while Jarvis speaks, brighter on louder syllables.
  const rings = [0, 1, 2].map(() => {
    const m = new THREE.Mesh(new THREE.RingGeometry(1, 1.035, 128),
      new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false }));
    m.position.z = -0.2;
    scene.add(m);
    return m;
  });

  // State → motion. amp = wobble, freq = how many lumps, speed = how fast they flow. `level` is the voice (0…1).
  const STATES = {
    idle:      { amp: 0.08, freq: 0.7, speed: 0.5, glow: 0.9, pulse: () => 0.0 },
    listening: { amp: 0.11, freq: 0.8, speed: 0.9, glow: 1.1, pulse: (t) => 0.06 + 0.04 * Math.sin(t * 2.5) },
    thinking:  { amp: 0.14, freq: 1.1, speed: 2.2, glow: 1.2, pulse: (t) => 0.08 + 0.05 * Math.sin(t * 3) },
    speaking:  { amp: 0.10, freq: 0.9, speed: 1.2, glow: 1.2, pulse: () => 0.05 },
    confirm:   { amp: 0.13, freq: 0.9, speed: 1.0, glow: 1.3, pulse: (t) => 0.1 + 0.08 * Math.sin(t * 4), color: '#ffb020' },
    error:     { amp: 0.20, freq: 1.6, speed: 3.0, glow: 1.0, pulse: (t) => (Math.sin(t * 20) > 0.6 ? 0.15 : 0.0), color: '#ff3b3b' },
  };
  // low/high = voice bands (bass → breathing size, highs → sharper ripples on the surface), hover = mouse over the orb.
  let low = 0, high = 0, lowS = 0, highS = 0, hover = false, hoverS = 0, ripple = 0;
  let state = 'idle', level = 0, voice = 0, baseColor = '#9b5cff', shownColor = '';
  const eased = { amp: 0.08, freq: 0.7, speed: 0.5, glow: 0.9 };

  function applyColor(hex) {
    if (hex === shownColor) return;
    shownColor = hex;
    tint.main.set(hex);
    tint.light.set(hex).lerp(new Color('#ffffff'), 0.55);
    tint.deep.set(hex).multiplyScalar(0.5);
  }

  function resize() {
    const w = innerWidth, h = innerHeight;
    // Supersample small orbs (96 px) so the silhouette stays smooth.
    const ratio = Math.min(3, Math.max(2, devicePixelRatio, 400 / h));
    renderer.setPixelRatio(ratio);
    renderer.setSize(w, h);
    camera.aspect = w / h; camera.updateProjectionMatrix();
    pMat.uniforms.scale.value = ratio * h / 1400;
  }
  addEventListener('resize', resize); resize();

  window.orb = {
    set(o) {
      if (o.state in STATES) state = o.state;
      if (typeof o.level === 'number') voice = Math.max(0, Math.min(1, o.level));
      if (typeof o.low === 'number') low = Math.max(0, Math.min(1, o.low));
      if (typeof o.high === 'number') high = Math.max(0, Math.min(1, o.high));
      if ('hover' in o) hover = !!o.hover;
      if (o.color) baseColor = o.color;
    },
  };

  const clock = new THREE.Clock();
  renderer.setAnimationLoop(() => {
    const dt = Math.min(clock.getDelta(), 0.1), t = clock.elapsedTime, c = STATES[state];
    applyColor(c.color ?? baseColor);
    for (const k in eased) eased[k] += (c[k] - eased[k]) * Math.min(1, dt * 3); // smooth state changes
    level += (c.pulse(t) + voice * 0.9 - level) * 0.25;
    uniforms.uTime.value += dt * eased.speed * (1 + level * 2);  // accumulate: speed changes don't jump
    lowS += (low - lowS) * 0.3; highS += (high - highS) * 0.3;
    hoverS += ((hover ? 1 : 0) - hoverS) * Math.min(1, dt * 6);
    uniforms.uAmp.value = eased.amp + level * 0.2 + highS * 0.12;
    uniforms.uFreq.value = eased.freq + highS * 0.6;
    uniforms.uGlow.value = eased.glow + level * 0.8 + hoverS * 0.4;
    blob.rotation.y += dt * 0.15; blob.rotation.x = 0.2 + Math.sin(t * 0.3) * 0.1;
    blob.scale.setScalar(1 + level * 0.12 + lowS * 0.1 + hoverS * 0.04);
    haloMat.uniforms.strength.value = 0.35 + eased.glow * 0.25 + level * 0.4 + hoverS * 0.15;
    ripple += ((state === 'speaking' ? 1 : 0) - ripple) * Math.min(1, dt * 2);
    rings.forEach((r, i) => {
      const p = (t * 0.45 + i / 3) % 1;
      r.scale.setScalar(1.5 + p * 1.6);
      r.material.color.copy(tint.light);
      r.material.opacity = ripple * (1 - p) * (0.2 + level * 0.9);
    });
    particles.rotation.y += dt * 0.05 * eased.speed; particles.rotation.x += dt * 0.02;
    pMat.uniforms.level.value = level;
    renderer.render(scene, camera);
  });
})();
