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

  // Mirror the on-chain wheel layout. Order is fixed: 10 segments × 36° each,
  // starting from -18° at the top of the wheel.
  const SEGMENTS = [
    { m: 1, color: '#FFD3DF' },
    { m: 2, color: '#FFC0D0' },
    { m: 1, color: '#FFD3DF' },
    { m: 4, color: '#FFE29A' },
    { m: 1, color: '#FFD3DF' },
    { m: 2, color: '#FFC0D0' },
    { m: 7, color: '#D7B5F5' },
    { m: 1, color: '#FFD3DF' },
    { m: 2, color: '#FFC0D0' },
    { m: 20, color: '#FF8A7E' }
  ];

  const HAND_LABELS = ['✊', '✋', '✌️'];
  const BUTTON_COLORS = [0xff6b6b, 0xffd466, 0x6fa8ff];
  const BUTTON_X = [-1.2, 0, 1.2];

  let host: HTMLDivElement | null = null;

  // Three.js objects
  let renderer: THREE.WebGLRenderer | null = null;
  let scene: THREE.Scene;
  let camera: THREE.PerspectiveCamera;
  let cabinet: THREE.Group;
  let wheelGroup: THREE.Group;
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

  // Tween state for wheel
  let currentAngle = 0;
  let tweenStart = 0;
  let tweenFromAngle = 0;
  let tweenToAngle = 0;
  const TWEEN_DURATION = 3600;

  // Button press animation state — drops to -0.1 then eases back
  const buttonOffsets = [0, 0, 0];
  const BUTTON_BASE_Y = -1.45;
  const BUTTON_PRESS_DEPTH = -0.06;

  // ─── Texture builders ──────────────────────────────────────────────
  function makeWheelTexture(size = 1024): THREE.CanvasTexture {
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const ctx = c.getContext('2d')!;
    const cx = size / 2;
    const cy = size / 2;
    const radius = size / 2 - 8;

    for (let i = 0; i < 10; i++) {
      const a0 = ((i * 36 - 18 - 90) * Math.PI) / 180;
      const a1 = (((i + 1) * 36 - 18 - 90) * Math.PI) / 180;
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.arc(cx, cy, radius, a0, a1);
      ctx.closePath();
      ctx.fillStyle = SEGMENTS[i].color;
      ctx.fill();
      ctx.strokeStyle = 'rgba(0,0,0,0.18)';
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    ctx.fillStyle = '#0B0F17';
    ctx.font = 'bold 64px system-ui, -apple-system, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (let i = 0; i < 10; i++) {
      const ang = ((i * 36 - 90) * Math.PI) / 180;
      const r = radius * 0.78;
      const x = cx + r * Math.cos(ang);
      const y = cy + r * Math.sin(ang);
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(ang + Math.PI / 2);
      ctx.fillText(`${SEGMENTS[i].m}×`, 0, 0);
      ctx.restore();
    }

    const rg = ctx.createRadialGradient(cx, cy, radius * 0.6, cx, cy, radius);
    rg.addColorStop(0, 'rgba(0,0,0,0)');
    rg.addColorStop(1, 'rgba(0,0,0,0.22)');
    ctx.fillStyle = rg;
    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.fill();

    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = 8;
    return tex;
  }

  function makeMarqueeTexture(size = 1024): THREE.CanvasTexture {
    const c = document.createElement('canvas');
    c.width = size;
    c.height = Math.floor(size / 6);
    const ctx = c.getContext('2d')!;
    ctx.clearRect(0, 0, c.width, c.height);

    // Title
    ctx.font = 'bold 96px system-ui, -apple-system, sans-serif';
    ctx.fillStyle = '#ffffff';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.shadowColor = '#ffffff';
    ctx.shadowBlur = 24;
    ctx.fillText('JANKENMAN', c.width / 2, c.height / 2);
    ctx.shadowBlur = 0;

    // Border dots
    ctx.fillStyle = '#FFE29A';
    const dotRadius = 8;
    const dotCount = 8;
    for (let i = 0; i < dotCount; i++) {
      const x = (c.width / (dotCount + 1)) * (i + 1);
      ctx.beginPath();
      ctx.arc(x, dotRadius * 2, dotRadius, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(x, c.height - dotRadius * 2, dotRadius, 0, Math.PI * 2);
      ctx.fill();
    }

    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }

  function makeButtonLabelTexture(emoji: string, size = 256): THREE.CanvasTexture {
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const ctx = c.getContext('2d')!;
    ctx.clearRect(0, 0, size, size);
    ctx.font = `${Math.floor(size * 0.62)}px system-ui, "Apple Color Emoji", "Segoe UI Emoji", sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(emoji, size / 2, size / 2 + size * 0.04);
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }

  function drawDisplay(emoji: string, kind: ResultKind, cyc: boolean) {
    if (!displayCanvas) return;
    const ctx = displayCanvas.getContext('2d')!;
    const size = displayCanvas.width;
    const cx = size / 2;
    const cy = size / 2;

    const ringColor =
      kind === 'win'
        ? '#7FE3AD'
        : kind === 'lose'
          ? '#FF8A8A'
          : kind === 'draw'
            ? '#FFE29A'
            : '#ff4040';

    ctx.fillStyle = '#150303';
    ctx.fillRect(0, 0, size, size);
    const grad = ctx.createRadialGradient(cx, cy, 12, cx, cy, size * 0.55);
    grad.addColorStop(0, '#3a0c0c');
    grad.addColorStop(1, '#080000');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, size, size);

    ctx.fillStyle = 'rgba(255,0,0,0.12)';
    for (let x = 0; x < size; x += 4) ctx.fillRect(x, 0, 1, size);
    for (let y = 0; y < size; y += 4) ctx.fillRect(0, y, size, 1);

    ctx.strokeStyle = ringColor;
    ctx.lineWidth = 4;
    ctx.shadowColor = ringColor;
    ctx.shadowBlur = 24;
    ctx.strokeRect(8, 8, size - 16, size - 16);
    ctx.shadowBlur = 0;

    ctx.globalAlpha = cyc ? 0.92 : 1;
    ctx.font = `${Math.floor(size * 0.62)}px system-ui, "Apple Color Emoji", "Segoe UI Emoji", sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.shadowColor = ringColor;
    ctx.shadowBlur = 18;
    ctx.fillText(emoji, cx, cy + size * 0.04);
    ctx.shadowBlur = 0;
    ctx.globalAlpha = 1;

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

    camera = new THREE.PerspectiveCamera(40, w / h, 0.1, 100);
    camera.position.set(0, 0.4, 9);
    camera.lookAt(0, 0, 0);

    // Lights ---------------------------------------------------------
    scene.add(new THREE.AmbientLight(0xffffff, 0.5));

    const key = new THREE.DirectionalLight(0xffffff, 0.7);
    key.position.set(2, 4, 5);
    scene.add(key);

    const blueRim = new THREE.PointLight(0x2a72e5, 1.4, 12);
    blueRim.position.set(0, 3, 1.5);
    scene.add(blueRim);

    resultLight = new THREE.PointLight(0xff4040, 1.0, 6);
    resultLight.position.set(0, 0.4, 1.5);
    scene.add(resultLight);

    // Cabinet --------------------------------------------------------
    cabinet = new THREE.Group();
    scene.add(cabinet);

    // Outer black frame
    const frameMat = new THREE.MeshStandardMaterial({
      color: 0x000000,
      roughness: 0.7,
      metalness: 0.2
    });
    const frame = new THREE.Mesh(new THREE.BoxGeometry(4.2, 6.2, 1.05), frameMat);
    frame.position.z = -0.05;
    cabinet.add(frame);

    // Cabinet body (slightly inset on top of the frame)
    const bodyMat = new THREE.MeshStandardMaterial({
      color: 0x131927,
      roughness: 0.55,
      metalness: 0.25
    });
    const body = new THREE.Mesh(new THREE.BoxGeometry(4, 6, 1), bodyMat);
    cabinet.add(body);

    // Marquee panel ----------------------------------------------
    const marqueePanelMat = new THREE.MeshStandardMaterial({
      color: 0x1a56b8,
      emissive: 0x2a72e5,
      emissiveIntensity: 0.55,
      roughness: 0.35,
      metalness: 0.2
    });
    const marquee = new THREE.Mesh(
      new THREE.BoxGeometry(3.6, 0.7, 0.06),
      marqueePanelMat
    );
    marquee.position.set(0, 2.4, 0.52);
    cabinet.add(marquee);

    const marqueeTex = makeMarqueeTexture();
    const marqueeText = new THREE.Mesh(
      new THREE.PlaneGeometry(3.5, 0.6),
      new THREE.MeshBasicMaterial({ map: marqueeTex, transparent: true, toneMapped: false })
    );
    marqueeText.position.set(0, 2.4, 0.56);
    cabinet.add(marqueeText);

    // Marquee blinker dots (3D)
    const dotMat = new THREE.MeshStandardMaterial({
      color: 0xffe29a,
      emissive: 0xffe29a,
      emissiveIntensity: 1.2
    });
    for (let i = -2; i <= 2; i++) {
      if (i === 0) continue;
      const dot = new THREE.Mesh(new THREE.SphereGeometry(0.04, 8, 8), dotMat.clone());
      dot.position.set(i * 0.3, 2.78, 0.6);
      dot.userData.isDot = true;
      dot.userData.phase = (i + 2) * 0.18;
      cabinet.add(dot);
    }

    // Screen recess --------------------------------------------------
    // Black frame around the screen
    const screenFrame = new THREE.Mesh(
      new THREE.BoxGeometry(3.4, 2.8, 0.04),
      new THREE.MeshStandardMaterial({ color: 0x000000, roughness: 0.6 })
    );
    screenFrame.position.set(0, 0.5, 0.515);
    cabinet.add(screenFrame);

    // Recessed screen back (slightly behind cabinet front)
    const screenBack = new THREE.Mesh(
      new THREE.BoxGeometry(3.2, 2.6, 0.02),
      new THREE.MeshStandardMaterial({ color: 0x05060d, roughness: 0.4 })
    );
    screenBack.position.set(0, 0.5, 0.49);
    cabinet.add(screenBack);

    // Wheel ----------------------------------------------------------
    wheelGroup = new THREE.Group();
    wheelGroup.position.set(0, 0.5, 0.51);
    cabinet.add(wheelGroup);

    const wheelTex = makeWheelTexture(1024);
    const wheelMesh = new THREE.Mesh(
      new THREE.CylinderGeometry(1.05, 1.05, 0.05, 96, 1, false),
      [
        new THREE.MeshStandardMaterial({ color: 0x000000 }),
        new THREE.MeshStandardMaterial({
          map: wheelTex,
          roughness: 0.35,
          metalness: 0.05
        }),
        new THREE.MeshStandardMaterial({ color: 0x000000 })
      ]
    );
    wheelMesh.rotation.x = -Math.PI / 2; // top face → +Z (toward camera)
    wheelGroup.add(wheelMesh);

    // Wheel rim (slightly larger torus on the front face)
    const wheelRim = new THREE.Mesh(
      new THREE.TorusGeometry(1.07, 0.03, 12, 96),
      new THREE.MeshStandardMaterial({ color: 0x000000, roughness: 0.6 })
    );
    wheelRim.position.z = 0.025;
    cabinet.add(wheelRim);
    // Note: rim outside wheelGroup so it doesn't spin

    // Pointer at top of the wheel
    const pointer = new THREE.Mesh(
      new THREE.ConeGeometry(0.1, 0.22, 4),
      new THREE.MeshStandardMaterial({
        color: 0xffe29a,
        emissive: 0xffe29a,
        emissiveIntensity: 0.7
      })
    );
    pointer.rotation.x = Math.PI; // tip points down
    pointer.position.set(0, 1.65, 0.55);
    cabinet.add(pointer);

    // LED display in the middle of the wheel
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
    displayMesh = new THREE.Mesh(new THREE.PlaneGeometry(0.6, 0.6), displayMat);
    displayMesh.position.set(0, 0.5, 0.6);
    cabinet.add(displayMesh);

    // Control deck (sloped panel below the screen) ------------------
    const deck = new THREE.Mesh(
      new THREE.BoxGeometry(3.6, 0.32, 1.1),
      new THREE.MeshStandardMaterial({
        color: 0x243049,
        roughness: 0.6,
        metalness: 0.15
      })
    );
    deck.position.set(0, -1.7, 0.6);
    deck.rotation.x = -Math.PI / 9;
    cabinet.add(deck);

    // Three buttons --------------------------------------------------
    for (let i = 0; i < 3; i++) {
      const group = new THREE.Group();

      const cap = new THREE.Mesh(
        new THREE.CylinderGeometry(0.32, 0.36, 0.18, 32),
        new THREE.MeshStandardMaterial({
          color: BUTTON_COLORS[i],
          emissive: BUTTON_COLORS[i],
          emissiveIntensity: 0.06,
          roughness: 0.35,
          metalness: 0.05
        })
      );
      group.add(cap);

      // Black ring under the cap
      const skirt = new THREE.Mesh(
        new THREE.CylinderGeometry(0.4, 0.42, 0.06, 32),
        new THREE.MeshStandardMaterial({ color: 0x000000, roughness: 0.7 })
      );
      skirt.position.y = -0.12;
      group.add(skirt);

      // Emoji label on top
      const labelTex = makeButtonLabelTexture(HAND_LABELS[i]);
      const label = new THREE.Mesh(
        new THREE.CircleGeometry(0.28, 32),
        new THREE.MeshBasicMaterial({
          map: labelTex,
          transparent: true,
          toneMapped: false
        })
      );
      label.rotation.x = -Math.PI / 2;
      label.position.y = 0.092;
      group.add(label);

      group.position.set(BUTTON_X[i], BUTTON_BASE_Y, 0.95);
      group.rotation.x = -Math.PI / 9; // match deck slope
      group.userData = { handIdx: i };

      cabinet.add(group);
      buttonGroups.push(group);
      buttonCaps.push(cap);
      // raycast against everything in the group
      group.traverse((c) => pickables.push(c));
    }

    // Pointer / raycaster --------------------------------------------
    raycaster = new THREE.Raycaster();
    pointerVec = new THREE.Vector2();
    renderer.domElement.addEventListener('pointerdown', onPointerDown);
    renderer.domElement.style.cursor = 'pointer';

    animate(performance.now());
  }

  // Cubic-bezier-ish ease-out
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
      buttonOffsets[idx] = BUTTON_PRESS_DEPTH;
      onSelectHand?.(idx);
    }
  }

  function animate(now: number) {
    if (!renderer) return;
    frameId = requestAnimationFrame(animate);

    // Wheel rotation tween
    if (tweenStart > 0) {
      const t = (now - tweenStart) / TWEEN_DURATION;
      const k = easeOut(t);
      currentAngle = tweenFromAngle + (tweenToAngle - tweenFromAngle) * k;
      if (t >= 1) {
        currentAngle = tweenToAngle;
        tweenStart = 0;
      }
    }
    if (wheelGroup) wheelGroup.rotation.z = currentAngle;

    // Buttons: ease offset back toward 0, plus a static depression for selected
    for (let i = 0; i < buttonGroups.length; i++) {
      // Selected hand stays slightly pressed and brighter
      const selectedDepth = selectedHand === i ? -0.025 : 0;
      const target = selectedDepth;
      buttonOffsets[i] += (target - buttonOffsets[i]) * 0.18;
      const g = buttonGroups[i];
      // Recompute position keeping the slope: the deck tilts -PI/9 around X.
      // We just nudge buttons along their local Y down/up.
      g.position.y = BUTTON_BASE_Y + buttonOffsets[i];

      // Selected glow
      const cap = buttonCaps[i];
      const m = cap.material as THREE.MeshStandardMaterial;
      const targetEmissive = selectedHand === i ? 0.6 : 0.06;
      m.emissiveIntensity += (targetEmissive - m.emissiveIntensity) * 0.15;
    }

    // Marquee blinker dots
    cabinet.traverse((o) => {
      if (o.userData?.isDot) {
        const m = (o as THREE.Mesh).material as THREE.MeshStandardMaterial;
        const phase = o.userData.phase as number;
        const v = 0.5 + 0.5 * Math.sin(now * 0.005 + phase * 4);
        m.emissiveIntensity = 0.4 + v * 1.2;
      }
    });

    // Subtle camera drift
    camera.position.x = Math.sin(now * 0.00025) * 0.18;
    camera.position.y = 0.4 + Math.sin(now * 0.0004) * 0.05;
    camera.lookAt(0, 0, 0);

    renderer.render(scene, camera);
  }

  // ─── Reactive bridges ─────────────────────────────────────────────
  let lastTargetDeg = 0;
  $effect(() => {
    if (!renderer) return;
    if (targetRotationDeg === lastTargetDeg) return;
    lastTargetDeg = targetRotationDeg;
    const target = -(targetRotationDeg * Math.PI) / 180; // CSS-clockwise → -Z
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

    // Wait for measurable dimensions before initializing.
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
    min-height: 360px;
    aspect-ratio: 4 / 5;
    position: relative;
    overflow: hidden;
    border-radius: 12px;
    background: radial-gradient(ellipse at 50% 30%, #0d1a40 0%, #050b22 100%);
    user-select: none;
    touch-action: none;
  }
  .cabinet3d :global(canvas) {
    display: block;
    width: 100% !important;
    height: 100% !important;
  }
</style>
