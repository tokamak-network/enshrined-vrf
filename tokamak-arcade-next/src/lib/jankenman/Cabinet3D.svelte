<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import * as THREE from 'three';

  type ResultKind = '' | 'win' | 'lose' | 'draw';

  type Props = {
    targetRotationDeg: number;
    displayEmoji: string;
    resultKind: ResultKind;
    cycling: boolean;
  };

  let {
    targetRotationDeg = 0,
    displayEmoji = '✊',
    resultKind = '' as ResultKind,
    cycling = true
  }: Props = $props();

  // Mirror the on-chain wheel layout used by the rest of the page.
  // Order is fixed: 10 segments × 36° each, starting from -18° at the top.
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

  let host = $state<HTMLDivElement | null>(null);
  let renderer: THREE.WebGLRenderer | null = null;
  let scene: THREE.Scene;
  let camera: THREE.PerspectiveCamera;
  let wheel: THREE.Group;
  let displayMesh: THREE.Mesh;
  let displayMat: THREE.MeshBasicMaterial;
  let displayTexture: THREE.CanvasTexture;
  let displayCanvas: HTMLCanvasElement;
  let pointLight: THREE.PointLight;

  let frameId: number | null = null;
  let resizeObs: ResizeObserver | null = null;

  // Tween state — interpolate currentAngle toward targetAngle on prop change.
  let currentAngle = 0; // radians
  let tweenStart = 0;
  let tweenFromAngle = 0;
  let tweenToAngle = 0;
  let tweenDuration = 3600;

  // ─── Texture builders ──────────────────────────────────────────────
  function makeWheelTexture(size = 1024): THREE.CanvasTexture {
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const ctx = c.getContext('2d')!;
    const cx = size / 2;
    const cy = size / 2;
    const radius = size / 2 - 6;

    // Segments — start from -18° (top centre of segment 0) and sweep clockwise.
    for (let i = 0; i < 10; i++) {
      const a0 = ((i * 36 - 18 - 90) * Math.PI) / 180;
      const a1 = (((i + 1) * 36 - 18 - 90) * Math.PI) / 180;
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.arc(cx, cy, radius, a0, a1);
      ctx.closePath();
      ctx.fillStyle = SEGMENTS[i].color;
      ctx.fill();
      // Soft inner shadow on the right edge for depth
      ctx.strokeStyle = 'rgba(0,0,0,0.18)';
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    // Multiplier labels
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

    // Outer ring shadow ring for depth
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

    // Background — dark with radial glow
    ctx.fillStyle = '#150303';
    ctx.fillRect(0, 0, size, size);
    const grad = ctx.createRadialGradient(cx, cy, 12, cx, cy, size * 0.55);
    grad.addColorStop(0, '#3a0c0c');
    grad.addColorStop(1, '#080000');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, size, size);

    // LED grid overlay
    ctx.fillStyle = 'rgba(255,0,0,0.10)';
    for (let x = 0; x < size; x += 4) ctx.fillRect(x, 0, 1, size);
    for (let y = 0; y < size; y += 4) ctx.fillRect(0, y, size, 1);

    // Outer glow ring
    ctx.strokeStyle = ringColor;
    ctx.lineWidth = 4;
    ctx.shadowColor = ringColor;
    ctx.shadowBlur = 24;
    ctx.strokeRect(8, 8, size - 16, size - 16);
    ctx.shadowBlur = 0;

    // Emoji — flicker-friendly: render slightly dimmer when cycling
    ctx.globalAlpha = cyc ? 0.92 : 1;
    ctx.font = `${Math.floor(size * 0.62)}px system-ui, "Apple Color Emoji", "Segoe UI Emoji", sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.shadowColor = ringColor;
    ctx.shadowBlur = 18;
    ctx.fillText(emoji, cx, cy + size * 0.04);
    ctx.shadowBlur = 0;
    ctx.globalAlpha = 1;

    displayTexture.needsUpdate = true;

    // Reflect on the point light too
    if (pointLight) {
      pointLight.color = new THREE.Color(ringColor);
    }
  }

  // ─── Scene setup ───────────────────────────────────────────────────
  function setup() {
    if (!host) return;
    const w = host.clientWidth;
    const h = host.clientHeight;

    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(w, h, false);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    host.appendChild(renderer.domElement);

    scene = new THREE.Scene();

    camera = new THREE.PerspectiveCamera(36, w / h, 0.1, 100);
    camera.position.set(0, 4.6, 4.2);
    camera.lookAt(0, 0.1, 0);

    // Lighting
    scene.add(new THREE.AmbientLight(0xffffff, 0.55));

    const key = new THREE.DirectionalLight(0xffffff, 0.9);
    key.position.set(2, 5, 3);
    scene.add(key);

    const rim = new THREE.PointLight(0x2a72e5, 1.2, 12);
    rim.position.set(-2, 2, -2);
    scene.add(rim);

    pointLight = new THREE.PointLight(0xff4040, 1.6, 6);
    pointLight.position.set(0, 0.8, 0);
    scene.add(pointLight);

    // Wheel group
    wheel = new THREE.Group();
    scene.add(wheel);

    const wheelTex = makeWheelTexture(1024);
    const wheelGeom = new THREE.CylinderGeometry(2, 2, 0.22, 96, 1, false);
    const sideMat = new THREE.MeshStandardMaterial({
      color: 0x080a12,
      roughness: 0.6,
      metalness: 0.2
    });
    const faceMat = new THREE.MeshStandardMaterial({
      map: wheelTex,
      roughness: 0.4,
      metalness: 0.05
    });
    const wheelMesh = new THREE.Mesh(wheelGeom, [sideMat, faceMat, sideMat]);
    wheel.add(wheelMesh);

    // Outer black rim
    const rimGeom = new THREE.TorusGeometry(2.02, 0.06, 16, 96);
    const rimMat = new THREE.MeshStandardMaterial({
      color: 0x000000,
      roughness: 0.55,
      metalness: 0.4
    });
    const rimMesh = new THREE.Mesh(rimGeom, rimMat);
    rimMesh.rotation.x = Math.PI / 2;
    rimMesh.position.y = 0.11;
    wheel.add(rimMesh);

    // Inner green hub ring (independent of wheel — doesn't rotate)
    const hubGeom = new THREE.CylinderGeometry(1.05, 1.05, 0.28, 64);
    const hubMat = new THREE.MeshStandardMaterial({
      color: 0xb5ead7,
      roughness: 0.35,
      metalness: 0.05
    });
    const hub = new THREE.Mesh(hubGeom, hubMat);
    hub.position.y = 0.14;
    scene.add(hub);

    const hubRimGeom = new THREE.TorusGeometry(1.07, 0.03, 12, 64);
    const hubRimMat = new THREE.MeshStandardMaterial({
      color: 0x000000,
      roughness: 0.6
    });
    const hubRim = new THREE.Mesh(hubRimGeom, hubRimMat);
    hubRim.rotation.x = Math.PI / 2;
    hubRim.position.y = 0.28;
    scene.add(hubRim);

    // LED display (center)
    displayCanvas = document.createElement('canvas');
    displayCanvas.width = displayCanvas.height = 512;
    drawDisplay(displayEmoji, resultKind, cycling);

    displayTexture = new THREE.CanvasTexture(displayCanvas);
    displayTexture.colorSpace = THREE.SRGBColorSpace;

    const dispGeom = new THREE.BoxGeometry(0.85, 0.06, 0.85);
    const dispSide = new THREE.MeshStandardMaterial({ color: 0x080000, roughness: 0.7 });
    displayMat = new THREE.MeshBasicMaterial({
      map: displayTexture,
      toneMapped: false
    });
    displayMesh = new THREE.Mesh(dispGeom, [
      dispSide, // +X
      dispSide, // -X
      displayMat, // +Y (top — what the camera sees)
      dispSide, // -Y
      dispSide, // +Z
      dispSide // -Z
    ]);
    displayMesh.position.y = 0.32;
    scene.add(displayMesh);

    // Pointer at the top of the wheel — fixed, not part of the rotating group
    const pointerGeom = new THREE.ConeGeometry(0.16, 0.34, 4);
    const pointerMat = new THREE.MeshStandardMaterial({
      color: 0xffe29a,
      emissive: 0xffe29a,
      emissiveIntensity: 0.5,
      roughness: 0.4
    });
    const pointer = new THREE.Mesh(pointerGeom, pointerMat);
    pointer.rotation.x = Math.PI; // tip points down toward wheel
    pointer.position.set(0, 0.5, -2.05);
    scene.add(pointer);

    // Initial render
    animate(performance.now());
  }

  // Cubic-bezier-ish ease-out (mimics cubic-bezier(0.18, 0.9, 0.24, 1)).
  function easeOut(t: number): number {
    const c = Math.max(0, Math.min(1, t));
    return 1 - Math.pow(1 - c, 4);
  }

  function animate(now: number) {
    if (!renderer) return;
    frameId = requestAnimationFrame(animate);

    // Tween wheel rotation
    if (tweenStart > 0) {
      const t = (now - tweenStart) / tweenDuration;
      const k = easeOut(t);
      currentAngle = tweenFromAngle + (tweenToAngle - tweenFromAngle) * k;
      if (t >= 1) {
        currentAngle = tweenToAngle;
        tweenStart = 0;
      }
    }
    if (wheel) wheel.rotation.y = currentAngle;

    // Subtle camera bob for liveliness
    if (camera) {
      const bob = Math.sin(now * 0.0006) * 0.015;
      camera.position.y = 4.6 + bob;
      camera.lookAt(0, 0.1, 0);
    }

    // Display flicker — quick small alpha modulation while cycling
    if (cycling && displayMat) {
      // Subtle modulation; main flicker is the canvas-side dimming below
    }

    renderer.render(scene, camera);
  }

  // ─── Reactive bridges ─────────────────────────────────────────────
  let lastTargetDeg = 0;
  $effect(() => {
    if (!renderer) return;
    if (targetRotationDeg === lastTargetDeg) return;
    lastTargetDeg = targetRotationDeg;
    // Three.js Y rotation matches CSS rotate visually if we negate.
    const target = -(targetRotationDeg * Math.PI) / 180;
    tweenFromAngle = currentAngle;
    tweenToAngle = target;
    tweenStart = performance.now();
  });

  // Re-draw display when emoji/kind/cycling change
  let cycleAnimId: number | null = null;
  $effect(() => {
    if (!displayCanvas) return;
    drawDisplay(displayEmoji, resultKind, cycling);
  });

  // Cycling drives a slow re-paint loop (the emoji prop changes from outside,
  // but we still want a flicker even when prop is stable). Keep it cheap:
  // re-paint at ~12fps while cycling, idle otherwise.
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
    setup();

    if (host) {
      resizeObs = new ResizeObserver(() => {
        if (!renderer || !host) return;
        const w = host.clientWidth;
        const h = host.clientHeight;
        renderer.setSize(w, h, false);
        camera.aspect = w / h;
        camera.updateProjectionMatrix();
      });
      resizeObs.observe(host);
    }
  });

  onDestroy(() => {
    if (frameId) cancelAnimationFrame(frameId);
    if (cycleAnimId) clearInterval(cycleAnimId);
    if (resizeObs) resizeObs.disconnect();
    if (renderer) {
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
    aspect-ratio: 1 / 1;
    position: relative;
    overflow: hidden;
    border-radius: 12px;
    /* Crisp, dark background under the canvas in case alpha shows through */
    background: radial-gradient(ellipse at 50% 30%, #0d1a40 0%, #050b22 100%);
  }
  .cabinet3d :global(canvas) {
    display: block;
    width: 100% !important;
    height: 100% !important;
  }
</style>
