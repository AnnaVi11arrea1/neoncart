import { Controller } from "@hotwired/stimulus"

// Home-page hero: the Ever Fluorescent logo, modelled in Blender, rendered
// live as a glowing neon wireframe that sways and leans toward the pointer.
// The model is just the glowing outline mesh (Curve.001 in EverFluorescent.blend)
// exported to GLB and meshopt-compressed; its look is rebuilt here:
//   - emission colour: Blender's Voronoi (scale 5.2) → colour ramp
//     black → teal → violet, with the cells drifting so the tube shimmers
//   - glow: bloom, plus horizontal/vertical light streaks standing in for
//     the compositor's Glare node (Streaks, violet tint)
// The canvas draws on black with mix-blend-mode: screen, so only the light
// lands on the page background.
//
// The poster <img> is shown until the first frame is drawn, and stays put when
// WebGL is unavailable, the visitor prefers reduced motion, or anything fails
// to load.
//   <div data-controller="neon-logo" data-neon-logo-model-url-value="…glb">
//     <img data-neon-logo-target="poster" …>
//   </div>
const RAMP_FLOOR = 0.2     // keeps Voronoi's near-black cells from going fully dark
const EMISSION = 3.8       // Blender's 54.5 strength, rescaled for three's exposure
const STREAK_TINT = [0.92, 0.12, 1.0]

export default class extends Controller {
  static targets = ["poster"]
  static values = { modelUrl: String }

  async connect() {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return

    try {
      this.three = await import("three-bundle")
      if (!this.element.isConnected) return
      this.setUp()
      await this.loadModel()
    } catch (error) {
      console.warn("neon-logo: keeping the poster image", error)
      this.tearDown()
      return
    }
    if (!this.renderer) return

    this.start = performance.now()
    if (!this.frame) this.tick()
  }

  disconnect() {
    this.tearDown()
  }

  setUp() {
    const T = this.three
    this.renderer = new T.WebGLRenderer({ antialias: true, powerPreference: "high-performance" })
    this.renderer.setClearColor(0x000000, 1)
    this.renderer.toneMapping = T.AgXToneMapping
    this.renderer.toneMappingExposure = 0.9

    this.canvas = this.renderer.domElement
    this.canvas.className = "hero__logo-canvas"
    this.canvas.setAttribute("aria-hidden", "true")
    this.element.appendChild(this.canvas)

    this.scene = new T.Scene()
    this.camera = new T.PerspectiveCamera(28, 1, 0.1, 50)

    this.composer = new T.EffectComposer(this.renderer)
    this.composer.addPass(new T.RenderPass(this.scene, this.camera))
    this.composer.addPass(createStreakPass(T))
    this.bloom = new T.UnrealBloomPass(new T.Vector2(1, 1), 0.6, 0.15, 1.0)
    this.composer.addPass(this.bloom)
    this.composer.addPass(new T.OutputPass())

    this.pointer = new T.Vector2()
    this.tilt = new T.Vector2()
    this.onPointerMove = (event) => {
      const box = this.element.getBoundingClientRect()
      this.pointer.set(
        clamp((event.clientX - (box.left + box.width / 2)) / (box.width / 2), -1, 1),
        clamp((event.clientY - (box.top + box.height / 2)) / box.height, -1, 1)
      )
    }
    window.addEventListener("pointermove", this.onPointerMove, { passive: true })

    this.resizeObserver = new ResizeObserver(() => this.resize())
    this.resizeObserver.observe(this.element)
    this.visible = true
    this.intersectionObserver = new IntersectionObserver(([entry]) => {
      this.visible = entry.isIntersecting
      if (this.visible && this.pivot && !this.frame) this.tick()
    })
    this.intersectionObserver.observe(this.element)
  }

  async loadModel() {
    const T = this.three
    const loader = new T.GLTFLoader().setMeshoptDecoder(T.MeshoptDecoder)
    const gltf = await loader.loadAsync(this.modelUrlValue)
    if (!this.renderer) return

    this.logo = gltf.scene
    // Exported Y-up, the logo lies flat facing +Y; stand it up to face the camera.
    this.logo.rotation.x = Math.PI / 2
    this.logo.updateMatrixWorld(true)
    const box = new T.Box3().setFromObject(this.logo)
    const center = box.getCenter(new T.Vector3())
    this.logo.position.sub(center)
    this.size = box.getSize(new T.Vector3())

    this.material = createNeonMaterial(T)
    this.logo.traverse((node) => {
      if (!node.isMesh) return
      node.geometry.computeBoundingBox()
      const { min, max } = node.geometry.boundingBox
      this.material.userData.uniforms.uBoxMin.value.copy(min)
      this.material.userData.uniforms.uBoxSize.value.subVectors(max, min)
      node.material = this.material
    })

    this.pivot = new T.Group()
    this.pivot.add(this.logo)
    this.scene.add(this.pivot)
    this.resize()
  }

  resize() {
    if (!this.renderer) return
    const { width, height } = this.element.getBoundingClientRect()
    if (!width || !height) return

    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5))
    this.renderer.setSize(width, height, false)
    this.composer.setPixelRatio(this.renderer.getPixelRatio())
    this.composer.setSize(width, height)
    this.camera.aspect = width / height

    if (this.size) {
      // Fit the logo's width (with room for the sway) inside the frame.
      const halfFov = (this.camera.fov * Math.PI) / 360
      const fitWidth = (this.size.x * 0.66) / (Math.tan(halfFov) * this.camera.aspect)
      const fitHeight = (this.size.y * 0.8) / Math.tan(halfFov)
      this.camera.position.set(0, 0, Math.max(fitWidth, fitHeight))
    }
    this.camera.updateProjectionMatrix()
  }

  tick = () => {
    this.frame = null
    if (!this.renderer || !this.visible) return

    const t = (performance.now() - this.start) / 1000
    if (this.pivot) {
      this.tilt.lerp(this.pointer, 0.06)
      this.pivot.rotation.set(
        -0.18 + Math.sin(t * 0.5) * 0.05 + this.tilt.y * 0.22,
        Math.sin(t * 0.35) * 0.32 + this.tilt.x * 0.35,
        -0.04 + Math.sin(t * 0.27) * 0.03
      )
      this.material.userData.uniforms.uTime.value = t
    }
    this.composer.render()

    if (this.pivot && !this.shown) {
      this.shown = true
      this.element.classList.add("is-live")
    }
    this.frame = requestAnimationFrame(this.tick)
  }

  tearDown() {
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = null
    window.removeEventListener("pointermove", this.onPointerMove)
    this.resizeObserver?.disconnect()
    this.intersectionObserver?.disconnect()
    this.logo?.traverse((node) => node.geometry?.dispose())
    this.material?.dispose()
    this.composer?.dispose()
    this.renderer?.dispose()
    this.canvas?.remove()
    this.element.classList.remove("is-live")
    this.renderer = this.composer = this.canvas = this.pivot = this.logo = this.material = null
    this.shown = false
  }
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}

// Emissive-only material whose emission is a drifting Voronoi cell pattern
// pushed through the Blender colour ramp, in the mesh's 0–1 bounding-box
// ("Generated") coordinates like the original node setup.
function createNeonMaterial(T) {
  const material = new T.MeshStandardMaterial({ color: 0x000000, roughness: 0.5 })
  const uniforms = {
    uTime: { value: 0 },
    uBoxMin: { value: new T.Vector3() },
    uBoxSize: { value: new T.Vector3(1, 1, 1) }
  }
  material.userData.uniforms = uniforms
  material.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms)
    shader.vertexShader = shader.vertexShader
      .replace("#include <common>", "#include <common>\nuniform vec3 uBoxMin;\nuniform vec3 uBoxSize;\nvarying vec3 vGenerated;")
      .replace("#include <begin_vertex>", "#include <begin_vertex>\nvGenerated = (position - uBoxMin) / uBoxSize;")
    shader.fragmentShader = shader.fragmentShader
      .replace("#include <common>", `#include <common>
        uniform float uTime;
        varying vec3 vGenerated;
        vec3 hash3(vec3 p) {
          p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
          return fract(sin(p) * 43758.5453123);
        }
        // F1 Voronoi; returns the nearest cell's random value. Feature points
        // orbit slowly, standing in for Blender's 4D (W) Voronoi.
        float voronoiCell(vec3 p) {
          vec3 cell = floor(p), local = fract(p);
          float best = 8.0, value = 0.0;
          for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
            vec3 offset = vec3(x, y, z);
            vec3 h = hash3(cell + offset);
            vec3 point = offset + 0.5 + 0.5 * sin(uTime * 0.6 + 6.2831 * h);
            float d = dot(point - local, point - local);
            if (d < best) { best = d; value = fract(h.x * 7.13 + h.y * 3.71); }
          }
          return value;
        }
        vec3 neonRamp(float t) {
          t = mix(${RAMP_FLOOR.toFixed(2)}, 1.0, t);
          vec3 teal = vec3(0.0, 0.318, 0.5), violet = vec3(0.754, 0.0, 1.0);
          return t < 0.5 ? teal * (t / 0.5) : mix(teal, violet, (t - 0.5) / 0.5);
        }`)
      .replace("vec3 totalEmissiveRadiance = emissive;",
        `vec3 totalEmissiveRadiance = neonRamp(voronoiCell(vGenerated * 5.2)) * ${EMISSION.toFixed(1)};`)
  }
  return material
}

// Light streaks from the bright parts of the frame, along both axes — the
// Glare node's "Streaks" mode. The bright pass is taken at quarter resolution,
// smeared with three widening passes per axis, then added back tinted.
function createStreakPass(T) {
  const quad = new T.FullScreenQuad()
  const vertexShader = "varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }"
  const bright = new T.ShaderMaterial({
    uniforms: { tDiffuse: { value: null }, uThreshold: { value: 1.5 } },
    vertexShader,
    fragmentShader: `uniform sampler2D tDiffuse; uniform float uThreshold; varying vec2 vUv;
      void main() { vec3 c = texture2D(tDiffuse, vUv).rgb; float l = max(c.r, max(c.g, c.b));
        gl_FragColor = vec4(c * smoothstep(uThreshold, uThreshold * 2.0, l), 1.0); }`
  })
  const smear = new T.ShaderMaterial({
    uniforms: { tDiffuse: { value: null }, uStep: { value: new T.Vector2() } },
    vertexShader,
    fragmentShader: `uniform sampler2D tDiffuse; uniform vec2 uStep; varying vec2 vUv;
      void main() { vec3 c = texture2D(tDiffuse, vUv).rgb; float w = 1.0, total = 1.0;
        for (int i = 1; i <= 4; i++) { w *= 0.8; total += 2.0 * w;
          c += w * (texture2D(tDiffuse, vUv + uStep * float(i)).rgb + texture2D(tDiffuse, vUv - uStep * float(i)).rgb); }
        gl_FragColor = vec4(c / total, 1.0); }`
  })
  const combine = new T.ShaderMaterial({
    uniforms: { tDiffuse: { value: null }, tH: { value: null }, tV: { value: null },
      uTint: { value: new T.Vector3(...STREAK_TINT) }, uStrength: { value: 0.35 } },
    vertexShader,
    fragmentShader: `uniform sampler2D tDiffuse, tH, tV; uniform vec3 uTint; uniform float uStrength; varying vec2 vUv;
      void main() { vec4 base = texture2D(tDiffuse, vUv);
        gl_FragColor = vec4(base.rgb + uTint * uStrength * (texture2D(tH, vUv).rgb + texture2D(tV, vUv).rgb), base.a); }`
  })
  const target = () => new T.WebGLRenderTarget(1, 1, { type: T.HalfFloatType })
  const targets = { bright: target(), a: target(), h: target(), v: target() }

  const pass = new T.Pass()
  pass.setSize = (width, height) => {
    const w = Math.max(1, Math.round(width / 4)), h = Math.max(1, Math.round(height / 4))
    Object.values(targets).forEach((t) => t.setSize(w, h))
    pass.texel = new T.Vector2(1 / w, 1 / h)
  }
  pass.render = (renderer, writeBuffer, readBuffer) => {
    const draw = (material, output) => { quad.material = material; renderer.setRenderTarget(output); quad.render(renderer) }
    bright.uniforms.tDiffuse.value = readBuffer.texture
    draw(bright, targets.bright)

    // Each axis: smear bright → out → a → out, with steps of 1, 5 and 25 texels.
    const streak = (axis, out) => {
      let source = targets.bright, chain = [out, targets.a, out]
      ;[1, 5, 25].forEach((scale, i) => {
        smear.uniforms.tDiffuse.value = source.texture
        smear.uniforms.uStep.value.set(axis === "h" ? pass.texel.x * scale : 0, axis === "v" ? pass.texel.y * scale : 0)
        draw(smear, chain[i])
        source = chain[i]
      })
      return source
    }
    combine.uniforms.tH.value = streak("h", targets.h).texture
    combine.uniforms.tV.value = streak("v", targets.v).texture
    combine.uniforms.tDiffuse.value = readBuffer.texture
    draw(combine, pass.renderToScreen ? null : writeBuffer)
  }
  pass.dispose = () => {
    Object.values(targets).forEach((t) => t.dispose())
    ;[bright, smear, combine].forEach((m) => m.dispose())
    quad.dispose()
  }
  return pass
}
