<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import * as THREE from 'three';

  type ResultKind = '' | 'win' | 'lose' | 'draw';

  type Props = {
    targetRotationDeg: number;
    displayEmoji: string;
    resultKind: ResultKind;
    cycling: boolean;
    selectedHand: number | null;
    onSelectHand?: (hand: number) => void;
    busy?: boolean;
  };

  let {
    targetRotationDeg = 0,
    displayEmoji = '✊',
    resultKind = '' as ResultKind,
    cycling = true,
    selectedHand = null,
    onSelectHand,
    busy = false
  }: Props = $props();

  // Mirror the on-chain layout. Photo's wheel uses red/green/yellow segments —
  // we use the same multiplier weights but keep the segment colors readable.
  const SEGMENTS = [
    { m: 1, color: '#3FB95F' }, // green
    { m: 2, color: '#FFC83C' }, // yellow
    { m: 1, color: '#3FB95F' },
    { m: 4, color: '#E84A4A' }, // red
    { m: 1, color: '#3FB95F' },
    { m: 2, color: '#FFC83C' },
    { m: 7, color: '#E84A4A' },
    { m: 1, color: '#3FB95F' },
    { m: 2, color: '#FFC83C' },
    { m: 20, color: '#E84A4A' }
  ];

  // Photo button order (left → right): 가위(red) / 바위(yellow) / 보(green).
  // Hand index from the contract: 0=rock, 1=paper, 2=scissors.
  // So slot[0] = scissors(red), slot[1] = rock(yellow), slot[2] = paper(green).
  const BUTTON_LAYOUT = [
    { idx: 2, color: 0xe84a4a, label: '가위' }, // scissors — red
    { idx: 0, color: 0xffc83c, label: '바위' }, // rock     — yellow
    { idx: 1, color: 0x3fb95f, label: '보' } //   paper    — green
  ];
  const BUTTON_X = [-1.1, 0, 1.1];

  let host: HTMLDivElement | null = null;

  let renderer: THREE.WebGLRenderer | null = null;
  let scene: THREE.Scene;
  let camera: THREE.PerspectiveCamera;
  let cabinet: THREE.Group;
  let wheelMesh: THREE.Mesh;
  let displayMesh: THREE.Mesh;
  let displayMat: THREE.MeshBasicMaterial;
  let displayTex: THREE.CanvasTexture;
  let displayCanvas: HTMLCanvasElement;
  let resultLight: THREE.PointLight;
  let buttonGroups: THREE.Group[] = [];
  let buttonCaps: THREE.Mesh[] = [];
  let pickables: THREE.Object3D[] = [];
  let raycaster: THREE.Raycaster;
  let pointerVec: THREE.Vector2;

  let frameId: number | null = null;
  let resizeObs: ResizeObserver | null = null;

  let currentAngle = 0;
  let tweenStart = 0;
  let tweenFromAngle = 0;
  let tweenToAngle = 0;
  const TWEEN_DURATION = 3600;

  const buttonOffsets = [0, 0, 0];
  const BUTTON_BASE_Y = -1.78;
  const BUTTON_PRESS_DEPTH = -0.05;

  // ─── Canvas builders ──────────────────────────────────────────────
  function makeWheelTexture(size = 1024): THREE.CanvasTexture {
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const ctx = c.getContext('2d')!;
    const cx = size / 2;
    const cy = size / 2;
    const radius = size / 2 - 8;

    // Outer green ring (the gold/green outer band around the segmented wheel)
    ctx.fillStyle = '#3FB95F';
    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.fill();

    // Segments — start from -18° at top, sweep clockwise.
    for (let i = 0; i < 10; i++) {
      const a0 = ((i * 36 - 18 - 90) * Math.PI) / 180;
      const a1 = (((i + 1) * 36 - 18 - 90) * Math.PI) / 180;
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.arc(cx, cy, radius * 0.96, a0, a1);
      ctx.closePath();
      ctx.fillStyle = SEGMENTS[i].color;
      ctx.fill();
      ctx.strokeStyle = 'rgba(0,0,0,0.35)';
      ctx.lineWidth = 3;
      ctx.stroke();
    }

    // Multiplier labels in each segment (chunky white outline like arcade signage)
    ctx.font = 'bold 88px "Pretendard", system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (let i = 0; i < 10; i++) {
      const ang = ((i * 36 - 90) * Math.PI) / 180;
      const r = radius * 0.74;
      const x = cx + r * Math.cos(ang);
      const y = cy + r * Math.sin(ang);
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(ang + Math.PI / 2);
      ctx.lineWidth = 8;
      ctx.strokeStyle = '#ffffff';
      ctx.strokeText(`${SEGMENTS[i].m}`, 0, 0);
      ctx.fillStyle = '#0B0F17';
      ctx.fillText(`${SEGMENTS[i].m}`, 0, 0);
      ctx.restore();
    }

    // Inner dark hub (where the LED hand sits over)
    ctx.beginPath();
    ctx.arc(cx, cy, radius * 0.42, 0, Math.PI * 2);
    ctx.fillStyle = '#0d2510';
    ctx.fill();
    ctx.lineWidth = 6;
    ctx.strokeStyle = '#000000';
    ctx.stroke();

    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = 8;
    return tex;
  }

  function makeScreenBackgroundTexture(size = 1024): THREE.CanvasTexture {
    // 4:3 screen — cyan background with title bar + side art labels
    const W = size;
    const H = Math.floor(size * 0.78);
    const c = document.createElement('canvas');
    c.width = W;
    c.height = H;
    const ctx = c.getContext('2d')!;

    // Cyan/blue gradient like the photo
    const g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#3da7e6');
    g.addColorStop(1, '#1e6db3');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);

    // Top yellow title
    ctx.font = 'bold 72px "Pretendard", system-ui, sans-serif';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.lineWidth = 8;
    ctx.strokeStyle = '#0B0F17';
    ctx.fillStyle = '#FFE74E';
    ctx.strokeText('JANKENMAN', 40, 60);
    ctx.fillText('JANKENMAN', 40, 60);

    // Korean win/lose/draw rim labels around the wheel area (decorative)
    // The wheel itself sits at left-center; rim labels go around it.
    const cx = W * 0.32;
    const cy = H * 0.55;
    const labelRadius = H * 0.42;

    ctx.font = 'bold 30px "Pretendard", system-ui, sans-serif';
    const rimLabels = [
      { text: '이겼다', ang: -90, color: '#E84A4A' },
      { text: '비겼다', ang: -54, color: '#FFC83C' },
      { text: '졌다', ang: 90, color: '#E84A4A' },
      { text: '비겼다', ang: 54, color: '#FFC83C' }
    ];
    for (const l of rimLabels) {
      const a = (l.ang * Math.PI) / 180;
      const x = cx + Math.cos(a) * labelRadius;
      const y = cy + Math.sin(a) * labelRadius;
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(a + Math.PI / 2);
      ctx.lineWidth = 6;
      ctx.strokeStyle = '#ffffff';
      ctx.strokeText(l.text, 0, 0);
      ctx.fillStyle = l.color;
      ctx.fillText(l.text, 0, 0);
      ctx.restore();
    }

    // Right side panel: stats area
    const panelX = W * 0.62;
    const panelW = W * 0.34;
    const panelY = H * 0.18;
    const panelH = H * 0.7;

    // Panel block
    ctx.fillStyle = 'rgba(0,0,0,0.18)';
    ctx.fillRect(panelX, panelY, panelW, panelH);
    ctx.strokeStyle = 'rgba(255,255,255,0.5)';
    ctx.lineWidth = 2;
    ctx.strokeRect(panelX, panelY, panelW, panelH);

    // Panel labels
    ctx.font = 'bold 28px "Pretendard", system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillStyle = '#ffffff';
    ctx.fillText('POOL TVL', panelX + panelW / 2, panelY + 50);

    // 7-seg-style display stub (we'll re-render this dynamically)
    ctx.fillStyle = '#1a0808';
    ctx.fillRect(panelX + 16, panelY + 70, panelW - 32, 60);
    ctx.font = 'bold 36px "JetBrains Mono", monospace';
    ctx.fillStyle = '#FF4040';
    ctx.fillText('— ETH', panelX + panelW / 2, panelY + 100);

    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 28px "Pretendard", system-ui, sans-serif';
    ctx.fillText('VRF COMMIT', panelX + panelW / 2, panelY + 170);
    ctx.fillStyle = '#1a0808';
    ctx.fillRect(panelX + 16, panelY + 190, panelW - 32, 60);
    ctx.fillStyle = '#FF4040';
    ctx.font = 'bold 36px "JetBrains Mono", monospace';
    ctx.fillText('#—', panelX + panelW / 2, panelY + 220);

    // Action hint
    ctx.fillStyle = 'rgba(255,255,255,0.85)';
    ctx.font = 'bold 24px "Pretendard", system-ui, sans-serif';
    ctx.fillText('SELECT A HAND', panelX + panelW / 2, panelY + 320);

    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = 8;
    return tex;
  }

  function makeButtonLabelTexture(label: string, size = 256): THREE.CanvasTexture {
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const ctx = c.getContext('2d')!;
    ctx.clearRect(0, 0, size, size);
    ctx.font = `bold ${Math.floor(size * 0.32)}px "Pretendard", system-ui, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.lineWidth = size * 0.06;
    ctx.strokeStyle = '#ffffff';
    ctx.strokeText(label, size / 2, size / 2);
    ctx.fillStyle = '#0B0F17';
    ctx.fillText(label, size / 2, size / 2);
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }

  // LED dot-matrix hand renderer (to mimic the photo's pixelated white-dot LED face).
  function drawDisplay(emoji: string, kind: ResultKind, cyc: boolean) {
    if (!displayCanvas) return;
    const ctx = displayCanvas.getContext('2d')!;
    const size = displayCanvas.width;

    // Decide ring + LED color from the result
    const ringColor =
      kind === 'win'
        ? '#7FE3AD'
        : kind === 'lose'
          ? '#FF8A8A'
          : kind === 'draw'
            ? '#FFE29A'
            : '#ffffff';

    // Background (the recessed dark hub of the wheel)
    ctx.fillStyle = '#0a1a0a';
    ctx.fillRect(0, 0, size, size);

    // Step 1: render the emoji at large size into a temp mask canvas
    const tmp = document.createElement('canvas');
    tmp.width = tmp.height = size;
    const tctx = tmp.getContext('2d')!;
    tctx.font = `${Math.floor(size * 0.78)}px system-ui, "Apple Color Emoji", "Segoe UI Emoji", sans-serif`;
    tctx.textAlign = 'center';
    tctx.textBaseline = 'middle';
    tctx.fillStyle = '#ffffff';
    tctx.fillText(emoji, size / 2, size / 2 + size * 0.04);
    const data = tctx.getImageData(0, 0, size, size).data;

    // Step 2: dot-matrix sampling
    const dotSpacing = Math.max(8, Math.floor(size / 36));
    const dotRadius = dotSpacing * 0.36;
    const flickerSeed = cyc ? Math.random() * 0.18 : 0;

    for (let y = dotSpacing / 2; y < size; y += dotSpacing) {
      for (let x = dotSpacing / 2; x < size; x += dotSpacing) {
        const idx = (Math.floor(y) * size + Math.floor(x)) * 4;
        const alpha = data[idx + 3];
        const lit = alpha > 70;
        if (lit) {
          ctx.beginPath();
          ctx.arc(x, y, dotRadius, 0, Math.PI * 2);
          ctx.shadowColor = ringColor;
          ctx.shadowBlur = 10;
          ctx.fillStyle = ringColor;
          ctx.globalAlpha = 1 - flickerSeed;
          ctx.fill();
          ctx.shadowBlur = 0;
          ctx.globalAlpha = 1;
        } else {
          // Dim LED (always present, just off)
          ctx.beginPath();
          ctx.arc(x, y, dotRadius * 0.45, 0, Math.PI * 2);
          ctx.fillStyle = 'rgba(255,255,255,0.04)';
          ctx.fill();
        }
      }
    }

    if (displayTex) displayTex.needsUpdate = true;
    if (resultLight) resultLight.color = new THREE.Color(ringColor);
  }

  // ─── Scene setup ───────────────────────────────────────────────────
  function setup(w: number, h: number) {
    if (!host) return;

    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(w, h, false);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    host.appendChild(renderer.domElement);

    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0c14);

    camera = new THREE.PerspectiveCamera(38, w / h, 0.1, 100);
    camera.position.set(0.6, 0.6, 8.5);
    camera.lookAt(0, 0.2, 0);

    // Lights ---------------------------------------------------------
    scene.add(new THREE.AmbientLight(0xffffff, 0.7));
    const key = new THREE.DirectionalLight(0xffffff, 0.9);
    key.position.set(3, 6, 6);
    scene.add(key);
    const fill = new THREE.DirectionalLight(0xb8d4ff, 0.4);
    fill.position.set(-4, 2, 4);
    scene.add(fill);

    resultLight = new THREE.PointLight(0xffffff, 0.6, 4);
    resultLight.position.set(-1.05, 0.4, 1.2);
    scene.add(resultLight);

    // Cabinet --------------------------------------------------------
    cabinet = new THREE.Group();
    scene.add(cabinet);

    const bodyColor = 0xf2efe6; // warm cream/off-white from the photo
    const trimColor = 0xb8b4a8; // silver/chrome trim

    // Outer trim frame (slightly larger and silver)
    const trimMat = new THREE.MeshStandardMaterial({
      color: trimColor,
      roughness: 0.45,
      metalness: 0.6
    });
    const trim = new THREE.Mesh(new THREE.BoxGeometry(4.7, 6.5, 1.3), trimMat);
    trim.position.z = -0.02;
    cabinet.add(trim);

    // Body
    const bodyMat = new THREE.MeshStandardMaterial({
      color: bodyColor,
      roughness: 0.65,
      metalness: 0.05
    });
    const body = new THREE.Mesh(new THREE.BoxGeometry(4.55, 6.35, 1.25), bodyMat);
    cabinet.add(body);

    // Screen — the BIG flat panel on the upper portion of the cabinet
    const screenW = 4.2;
    const screenH = 3.0;
    const screenY = 0.85;

    // Black bezel around the screen
    const bezelMat = new THREE.MeshStandardMaterial({
      color: 0x0c0c10,
      roughness: 0.4,
      metalness: 0.3
    });
    const bezel = new THREE.Mesh(
      new THREE.BoxGeometry(screenW + 0.18, screenH + 0.18, 0.05),
      bezelMat
    );
    bezel.position.set(0, screenY, 0.626);
    cabinet.add(bezel);

    // Screen background (cyan painted/printed face)
    const bgTex = makeScreenBackgroundTexture(1024);
    const screenBg = new THREE.Mesh(
      new THREE.PlaneGeometry(screenW, screenH),
      new THREE.MeshBasicMaterial({ map: bgTex, toneMapped: false })
    );
    screenBg.position.set(0, screenY, 0.652);
    cabinet.add(screenBg);

    // Wheel — separate plane, slightly in front of the screen so it can spin
    // independently. Centered over the LEFT half of the screen as in the photo.
    const wheelTex = makeWheelTexture(1024);
    const wheelDiam = screenH * 0.92;
    wheelMesh = new THREE.Mesh(
      new THREE.PlaneGeometry(wheelDiam, wheelDiam),
      new THREE.MeshBasicMaterial({
        map: wheelTex,
        transparent: true,
        toneMapped: false
      })
    );
    wheelMesh.position.set(-screenW * 0.18, screenY - 0.05, 0.66);
    cabinet.add(wheelMesh);

    // LED display in the center of the wheel
    displayCanvas = document.createElement('canvas');
    displayCanvas.width = displayCanvas.height = 512;
    drawDisplay(displayEmoji, resultKind, cycling);
    displayTex = new THREE.CanvasTexture(displayCanvas);
    displayTex.colorSpace = THREE.SRGBColorSpace;
    displayMat = new THREE.MeshBasicMaterial({
      map: displayTex,
      transparent: true,
      toneMapped: false
    });
    const dispSize = wheelDiam * 0.42;
    displayMesh = new THREE.Mesh(new THREE.PlaneGeometry(dispSize, dispSize), displayMat);
    displayMesh.position.set(-screenW * 0.18, screenY - 0.05, 0.668);
    cabinet.add(displayMesh);

    // Pointer (small triangle at top of the wheel)
    const pointerGeom = new THREE.Shape();
    pointerGeom.moveTo(0, 0);
    pointerGeom.lineTo(-0.07, 0.16);
    pointerGeom.lineTo(0.07, 0.16);
    pointerGeom.lineTo(0, 0);
    const pointerMesh = new THREE.Mesh(
      new THREE.ShapeGeometry(pointerGeom),
      new THREE.MeshBasicMaterial({ color: 0xff3333, toneMapped: false })
    );
    pointerMesh.position.set(-screenW * 0.18, screenY - 0.05 + wheelDiam / 2 - 0.04, 0.665);
    cabinet.add(pointerMesh);

    // Speaker section (decorative grille) ----------------------------
    function makeSpeakerGrille(): THREE.Mesh {
      const c = document.createElement('canvas');
      c.width = c.height = 256;
      const cc = c.getContext('2d')!;
      cc.fillStyle = '#5a5a5a';
      cc.fillRect(0, 0, 256, 256);
      cc.fillStyle = '#1a1a1a';
      const spacing = 14;
      for (let y = spacing; y < 256; y += spacing) {
        for (let x = spacing; x < 256; x += spacing) {
          cc.beginPath();
          cc.arc(x, y, 4, 0, Math.PI * 2);
          cc.fill();
        }
      }
      const tex = new THREE.CanvasTexture(c);
      tex.colorSpace = THREE.SRGBColorSpace;
      const m = new THREE.Mesh(
        new THREE.CircleGeometry(0.42, 32),
        new THREE.MeshStandardMaterial({
          map: tex,
          roughness: 0.6,
          metalness: 0.2
        })
      );
      return m;
    }

    const spkY = -0.95;
    const spkLeft = makeSpeakerGrille();
    spkLeft.position.set(-1.6, spkY, 0.626);
    cabinet.add(spkLeft);
    const spkRight = makeSpeakerGrille();
    spkRight.position.set(1.6, spkY, 0.626);
    cabinet.add(spkRight);

    // Center toggle/coin slot strip between speakers
    const stripMat = new THREE.MeshStandardMaterial({
      color: 0x2a2a2a,
      roughness: 0.4,
      metalness: 0.5
    });
    const strip = new THREE.Mesh(new THREE.BoxGeometry(1.4, 0.32, 0.08), stripMat);
    strip.position.set(0, spkY, 0.66);
    cabinet.add(strip);

    // Control deck (sloped panel below speakers) --------------------
    const deckMat = new THREE.MeshStandardMaterial({
      color: bodyColor,
      roughness: 0.6
    });
    const deck = new THREE.Mesh(new THREE.BoxGeometry(4.55, 0.36, 1.4), deckMat);
    deck.position.set(0, -2.0, 0.6);
    deck.rotation.x = -Math.PI / 8;
    cabinet.add(deck);

    // Three buttons: 가위 / 바위 / 보 in photo's left-to-right order ---
    for (let slot = 0; slot < 3; slot++) {
      const layout = BUTTON_LAYOUT[slot];
      const group = new THREE.Group();

      // Black collar/skirt
      const skirt = new THREE.Mesh(
        new THREE.CylinderGeometry(0.42, 0.44, 0.08, 32),
        new THREE.MeshStandardMaterial({ color: 0x000000, roughness: 0.6 })
      );
      skirt.position.y = -0.13;
      group.add(skirt);

      // Cap with a slightly translucent feel (real arcade buttons are glossy)
      const cap = new THREE.Mesh(
        new THREE.CylinderGeometry(0.36, 0.4, 0.2, 32),
        new THREE.MeshStandardMaterial({
          color: layout.color,
          emissive: layout.color,
          emissiveIntensity: 0.08,
          roughness: 0.25,
          metalness: 0.05
        })
      );
      group.add(cap);

      // Korean label below the button on the deck (small floating plane)
      const labelTex = makeButtonLabelTexture(layout.label, 256);
      const label = new THREE.Mesh(
        new THREE.PlaneGeometry(0.6, 0.3),
        new THREE.MeshBasicMaterial({ map: labelTex, transparent: true, toneMapped: false })
      );
      label.position.set(0, -0.18, 0.5);
      label.rotation.x = -Math.PI / 2;
      group.add(label);

      // Position group on the deck, tilted to match the deck slope
      group.position.set(BUTTON_X[slot], BUTTON_BASE_Y, 1.05);
      group.rotation.x = -Math.PI / 8;
      group.userData = { handIdx: layout.idx };

      cabinet.add(group);
      buttonGroups.push(group);
      buttonCaps.push(cap);
      group.traverse((c) => pickables.push(c));
    }

    // Pointer / raycaster
    raycaster = new THREE.Raycaster();
    pointerVec = new THREE.Vector2();
    renderer.domElement.addEventListener('pointerdown', onPointerDown);
    renderer.domElement.style.cursor = 'pointer';

    animate(performance.now());
  }

  function easeOut(t: number): number {
    const c = Math.max(0, Math.min(1, t));
    return 1 - Math.pow(1 - c, 4);
  }

  function onPointerDown(ev: PointerEvent) {
    if (!renderer || busy) return;
    const rect = renderer.domElement.getBoundingClientRect();
    pointerVec.x = ((ev.clientX - rect.left) / rect.width) * 2 - 1;
    pointerVec.y = -((ev.clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointerVec, camera);
    const hits = raycaster.intersectObjects(pickables, false);
    if (hits.length === 0) return;
    let obj: THREE.Object3D | null = hits[0].object;
    while (obj && obj.userData?.handIdx === undefined) obj = obj.parent;
    if (obj && typeof obj.userData?.handIdx === 'number') {
      const idx = obj.userData.handIdx as number;
      // Find which slot this hand index belongs to
      const slot = BUTTON_LAYOUT.findIndex((b) => b.idx === idx);
      if (slot >= 0) buttonOffsets[slot] = BUTTON_PRESS_DEPTH;
      onSelectHand?.(idx);
    }
  }

  function animate(now: number) {
    if (!renderer) return;
    frameId = requestAnimationFrame(animate);

    if (tweenStart > 0) {
      const t = (now - tweenStart) / TWEEN_DURATION;
      const k = easeOut(t);
      currentAngle = tweenFromAngle + (tweenToAngle - tweenFromAngle) * k;
      if (t >= 1) {
        currentAngle = tweenToAngle;
        tweenStart = 0;
      }
    }
    if (wheelMesh) wheelMesh.rotation.z = currentAngle;

    // Buttons — selected slot stays slightly pressed and brighter
    for (let i = 0; i < buttonGroups.length; i++) {
      const layout = BUTTON_LAYOUT[i];
      const isSelected = selectedHand === layout.idx;
      const target = isSelected ? -0.02 : 0;
      buttonOffsets[i] += (target - buttonOffsets[i]) * 0.18;
      buttonGroups[i].position.y = BUTTON_BASE_Y + buttonOffsets[i];

      const cap = buttonCaps[i];
      const m = cap.material as THREE.MeshStandardMaterial;
      const targetEmissive = isSelected ? 0.55 : 0.08;
      m.emissiveIntensity += (targetEmissive - m.emissiveIntensity) * 0.15;
    }

    // Subtle camera bob
    camera.position.y = 0.6 + Math.sin(now * 0.0004) * 0.04;
    camera.lookAt(0, 0.2, 0);

    renderer.render(scene, camera);
  }

  // ─── Reactive bridges ─────────────────────────────────────────────
  let lastTargetDeg = 0;
  $effect(() => {
    if (!renderer) return;
    if (targetRotationDeg === lastTargetDeg) return;
    lastTargetDeg = targetRotationDeg;
    const target = -(targetRotationDeg * Math.PI) / 180;
    tweenFromAngle = currentAngle;
    tweenToAngle = target;
    tweenStart = performance.now();
  });

  $effect(() => {
    if (!displayCanvas) return;
    drawDisplay(displayEmoji, resultKind, cycling);
  });

  let cycleAnimId: number | null = null;
  $effect(() => {
    if (!displayCanvas) return;
    if (cycleAnimId) {
      clearInterval(cycleAnimId);
      cycleAnimId = null;
    }
    if (cycling) {
      cycleAnimId = window.setInterval(
        () => drawDisplay(displayEmoji, resultKind, cycling),
        90
      );
    }
    return () => {
      if (cycleAnimId) {
        clearInterval(cycleAnimId);
        cycleAnimId = null;
      }
    };
  });

  // ─── Lifecycle ─────────────────────────────────────────────────────
  onMount(() => {
    if (!host) return;
    resizeObs = new ResizeObserver(() => {
      if (!host) return;
      const w = host.clientWidth;
      const h = host.clientHeight;
      if (w === 0 || h === 0) return;
      if (!renderer) {
        setup(w, h);
      } else {
        renderer.setSize(w, h, false);
        camera.aspect = w / h;
        camera.updateProjectionMatrix();
      }
    });
    resizeObs.observe(host);
    const w0 = host.clientWidth;
    const h0 = host.clientHeight;
    if (w0 > 0 && h0 > 0) setup(w0, h0);
  });

  onDestroy(() => {
    if (frameId) cancelAnimationFrame(frameId);
    if (cycleAnimId) clearInterval(cycleAnimId);
    if (resizeObs) resizeObs.disconnect();
    if (renderer) {
      renderer.domElement.removeEventListener('pointerdown', onPointerDown);
      renderer.dispose();
      if (renderer.domElement.parentNode) {
        renderer.domElement.parentNode.removeChild(renderer.domElement);
      }
    }
  });
</script>

<div class="cabinet3d" bind:this={host}></div>

<style>
  .cabinet3d {
    width: 100%;
    height: 100%;
    min-height: 420px;
    aspect-ratio: 4 / 5;
    position: relative;
    overflow: hidden;
    border-radius: 12px;
    background: #0a0c14;
    user-select: none;
    touch-action: none;
  }
  .cabinet3d :global(canvas) {
    display: block;
    width: 100% !important;
    height: 100% !important;
  }
</style>
