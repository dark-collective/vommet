# selfie_segmenter.bin

MediaPipe's selfie segmenter (float16; Apache-2.0, as distributed with
MediaPipe), the same model as `commet/web/vommet_blur/selfie_segmenter.tflite`
(sha256 `191ac9529ae506ee0beefa6b2c945a172dab9d07d1e802a290a4e4038226658b`), converted with:

    python3 rust/blur/tools/export_weights.py \
        commet/web/vommet_blur/selfie_segmenter.tflite \
        rust/blur/model/selfie_segmenter.bin

(needs the `tflite` and `numpy` Python packages). The weights are copied
unchanged as float16; only the graph is rewritten into the small format
`src/segmenter.rs` reads (described in the script).
