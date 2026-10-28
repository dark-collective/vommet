# vommet_blur

Builds `web/vommet_blur/`, the camera background blur used by Vommet's web build
(Settings → Voice and video → Blur background). It wraps
[@livekit/track-processors](https://github.com/livekit/track-processors-js) 0.8.2,
the processor Element Call uses, and serves every asset itself: nothing is fetched
from a CDN at run time.

| File in `web/vommet_blur/` | From | License |
|---|---|---|
| `vommet_blur.js` | `src/` + @livekit/track-processors 0.8.2 + @mediapipe/tasks-vision 0.10.14, bundled by esbuild | Apache-2.0 |
| `wasm/vision_wasm_internal.{js,wasm}` | @mediapipe/tasks-vision 0.10.14 (SIMD build only; every browser that passes the support check has wasm SIMD) | Apache-2.0 |
| `selfie_segmenter.tflite` | MediaPipe selfie segmenter, float16 (same file Element Call ships) | Apache-2.0, as distributed with MediaPipe |

The app loads `vommet_blur.js` only when blur is switched on.

Rebuild after changing `src/` or a version:

```
npm install
npm run build
```
