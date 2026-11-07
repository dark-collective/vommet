// Vommet camera background blur for the web build (window.vommetBlur).
// Wraps @livekit/track-processors (the same processor Element Call uses) with
// every asset served from this directory, so nothing is fetched from a CDN.
import { BackgroundBlur, supportsBackgroundProcessors } from '@livekit/track-processors';

const base = new URL('.', import.meta.url).href;
const assetPaths = {
  tasksVisionFileSet: base + 'wasm',
  modelAssetPath: base + 'selfie_segmenter.tflite',
};

function isSupported() {
  try {
    return supportsBackgroundProcessors();
  } catch (e) {
    return false;
  }
}

// Blurs `track` (a camera MediaStreamTrack). Resolves to
// { track, destroy() }. `onSlow` runs once when segmentation keeps taking
// longer than `slowMs` per frame, so the app can switch blur off.
async function create(track, blurRadius, slowMs, onSlow) {
  const element = document.createElement('video');
  element.muted = true;
  element.playsInline = true;
  element.srcObject = new MediaStream([track]);
  await element.play().catch(() => {});

  let slowFrames = 0;
  let reported = false;
  const onFrameProcessed = (stats) => {
    const ms = (stats.segmentationTimeMs || 0) + (stats.filterTimeMs || 0);
    slowFrames = ms > slowMs ? slowFrames + 1 : Math.max(0, slowFrames - 1);
    if (!reported && slowFrames >= 60) {
      reported = true;
      if (onSlow) onSlow();
    }
  };

  const processor = BackgroundBlur(blurRadius, undefined, onFrameProcessed, { assetPaths });
  await processor.init({ kind: 'video', track, element });
  return {
    track: processor.processedTrack,
    destroy: async () => {
      try {
        await processor.destroy();
      } finally {
        element.srcObject = null;
      }
    },
  };
}

window.vommetBlur = { isSupported, create };
