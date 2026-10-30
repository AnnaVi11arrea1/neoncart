// The slice of three.js the home page's 3D logo uses (neon_logo_controller.js),
// bundled into one ES module. three's add-ons import each other by relative
// path, which doesn't survive `bin/importmap pin`, so we bundle them instead.
//
// Rebuild after changing this file or bumping the version:
//
//   npm i --prefix tmp/three-bundle three@0.186.1 esbuild@0.28.2
//   NODE_PATH=tmp/three-bundle/node_modules tmp/three-bundle/node_modules/.bin/esbuild \
//     script/three_bundle.js --bundle --format=esm --minify --legal-comments=none \
//     --banner:js="// three@0.186.1 — built from script/three_bundle.js" \
//     --outfile=vendor/javascript/three-bundle.js
export {
  WebGLRenderer, WebGLRenderTarget, Scene, PerspectiveCamera, Group, Box3, Vector2, Vector3,
  MeshStandardMaterial, ShaderMaterial, AgXToneMapping, HalfFloatType
} from "three"
export { GLTFLoader } from "three/addons/loaders/GLTFLoader.js"
export { MeshoptDecoder } from "three/addons/libs/meshopt_decoder.module.js"
export { EffectComposer } from "three/addons/postprocessing/EffectComposer.js"
export { RenderPass } from "three/addons/postprocessing/RenderPass.js"
export { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js"
export { OutputPass } from "three/addons/postprocessing/OutputPass.js"
export { Pass, FullScreenQuad } from "three/addons/postprocessing/Pass.js"
