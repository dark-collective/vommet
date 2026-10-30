package im.nether.chat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Collections
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Vommet issue 936: frames for Convert to GIF without the player.
 *
 * Seeking libmpv once per frame made a 10 s GIF take ~20 s, and its
 * filmstrip ~7 s. Here the system decoder (MediaCodec, which runs in
 * Android's sandboxed media process) goes through the clip once, and each
 * wanted frame is shrunk to the GIF's size as it comes out. The filmstrip
 * uses the nearest key frames, which need no decoding in between.
 *
 * Everything stays in memory: frames go to Dart over the channel and nothing
 * is written to disk or logged.
 */
object VommetVideoFrames {
    private const val CHANNEL = "im.nether.chat/video_frames"

    // Limits, so a broken or hostile file can't make us allocate without end.
    private const val MAX_FRAMES = 240
    private const val MAX_EDGE = 1024
    private const val MAX_THUMBNAILS = 16
    private const val MAX_SOURCE_EDGE = 8192
    private const val TIMEOUT_US = 10_000L
    // A decoder that stops giving frames this long is given up on (the
    // caller falls back to the player).
    private const val STALL_NS = 5_000_000_000L
    private const val DEADLINE_NS = 60_000_000_000L

    // Frames and thumbnails each get their own thread, so the filmstrip
    // never waits behind a conversion or the other way round.
    private val framesThread = Executors.newSingleThreadExecutor()
    private val thumbnailsThread = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val canceled = Collections.synchronizedSet(HashSet<Int>())

    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "thumbnails" -> {
                    val source = call.argument<String>("source")!!
                    val count = min(call.argument<Int>("count") ?: 8, MAX_THUMBNAILS)
                    val edge = min(call.argument<Int>("edge") ?: 96, MAX_EDGE)
                    thumbnailsThread.execute {
                        try {
                            val shots = thumbnails(app, source, count, edge)
                            main.post { result.success(shots) }
                        } catch (e: Exception) {
                            main.post { result.error("failed", e.javaClass.simpleName, null) }
                        }
                    }
                }
                "frames" -> {
                    val id = call.argument<Int>("id")!!
                    val source = call.argument<String>("source")!!
                    val times = call.argument<List<Number>>("timesUs")!!
                        .take(MAX_FRAMES).map { it.toLong() }.toLongArray()
                    val edge = min(call.argument<Int>("edge") ?: 480, MAX_EDGE)
                    framesThread.execute {
                        try {
                            val size = frames(app, id, source, times, edge) { index, rgb ->
                                main.post {
                                    channel.invokeMethod(
                                        "frame",
                                        mapOf("id" to id, "index" to index, "rgb" to rgb),
                                    )
                                }
                            }
                            main.post { result.success(size) }
                        } catch (e: Exception) {
                            main.post { result.error("failed", e.javaClass.simpleName, null) }
                        } finally {
                            canceled.remove(id)
                        }
                    }
                }
                "cancel" -> {
                    canceled.add(call.argument<Int>("id")!!)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isContentUri(source: String) =
        source.startsWith("content://") || source.startsWith("file://")

    // ---- Filmstrip ----

    /** [count] JPEGs spread along the video, at most [edge] px. */
    private fun thumbnails(context: Context, source: String, count: Int, edge: Int): List<ByteArray?> {
        val retriever = MediaMetadataRetriever()
        try {
            if (isContentUri(source)) {
                retriever.setDataSource(context, Uri.parse(source))
            } else {
                retriever.setDataSource(source)
            }
            val durationMs = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION,
            )?.toLongOrNull() ?: 0L
            return (0 until count).map { i ->
                val atUs = (durationMs * 1000 * (i + 0.5) / count).toLong()
                val frame = try {
                    if (Build.VERSION.SDK_INT >= 27) {
                        retriever.getScaledFrameAtTime(
                            atUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, edge, edge,
                        )
                    } else {
                        retriever.getFrameAtTime(atUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    }
                } catch (e: Exception) {
                    null
                } ?: return@map null
                val small = fit(frame, edge)
                val out = ByteArrayOutputStream()
                small.compress(Bitmap.CompressFormat.JPEG, 70, out)
                if (small !== frame) small.recycle()
                frame.recycle()
                out.toByteArray()
            }
        } finally {
            retriever.release()
        }
    }

    private fun fit(bitmap: Bitmap, edge: Int): Bitmap {
        val longest = max(bitmap.width, bitmap.height)
        if (longest <= edge) return bitmap
        val scale = edge.toDouble() / longest
        return Bitmap.createScaledBitmap(
            bitmap,
            max(1, (bitmap.width * scale).roundToInt()),
            max(1, (bitmap.height * scale).roundToInt()),
            true,
        )
    }

    // ---- GIF frames ----

    /**
     * Decodes [source] once from the key frame before the first time, and
     * hands [emit] packed RGB at most [edge] px (upright) for each time in
     * [timesUs] (ascending): the first decoded frame at or after it.
     * Returns the frames' size and how many there were; fewer than asked
     * when the video ends first.
     */
    private fun frames(
        context: Context,
        id: Int,
        source: String,
        timesUs: LongArray,
        edge: Int,
        emit: (Int, ByteArray) -> Unit,
    ): Map<String, Int> {
        require(timesUs.isNotEmpty())
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            if (isContentUri(source)) {
                extractor.setDataSource(context, Uri.parse(source), null)
            } else {
                extractor.setDataSource(source)
            }
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("video/") == true
            } ?: throw IllegalArgumentException("no video track")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            val rotation = if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                ((format.getInteger(MediaFormat.KEY_ROTATION) % 360) + 360) % 360
            } else {
                0
            }

            format.setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
            )
            if (Build.VERSION.SDK_INT >= 33) {
                // Ask for HDR to be tone-mapped; decoders that can't ignore it.
                format.setInteger(
                    MediaFormat.KEY_COLOR_TRANSFER_REQUEST,
                    MediaFormat.COLOR_TRANSFER_SDR_VIDEO,
                )
            }
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()
            extractor.seekTo(timesUs[0], MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            val info = MediaCodec.BufferInfo()
            // Stop reading half a second past the last time; B-frames can
            // come out of order up to then.
            val readUntil = timesUs.last() + 500_000
            // Timestamps in files are rounded; allow a little.
            val slackUs = 2_000L
            var inputDone = false
            var outputDone = false
            var next = 0
            var converter: FrameConverter? = null
            var outputFormat = codec.outputFormat
            val started = System.nanoTime()
            var lastOutput = started

            while (!outputDone && next < timesUs.size) {
                if (canceled.contains(id)) throw InterruptedException("canceled")
                val now = System.nanoTime()
                if (now - lastOutput > STALL_NS || now - started > DEADLINE_NS) {
                    throw IllegalStateException("decoder stalled")
                }
                if (!inputDone) {
                    val inIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (inIndex >= 0) {
                        val buffer = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buffer, 0)
                        val at = extractor.sampleTime
                        if (size < 0 || at > readUntil) {
                            codec.queueInputBuffer(
                                inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size, at, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    outputFormat = codec.outputFormat
                    converter = null
                    continue
                }
                if (outIndex < 0) continue
                lastOutput = System.nanoTime()
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                val empty = outputDone && info.size == 0
                val wanted = !empty && info.presentationTimeUs + slackUs >= timesUs[next]
                if (wanted) {
                    val image = codec.getOutputImage(outIndex)
                        ?: throw IllegalStateException("no image")
                    try {
                        val c = converter?.takeIf { it.fits(image) }
                            ?: FrameConverter(image, rotation, edge, outputFormat).also {
                                converter = it
                            }
                        val rgb = c.convert(image)
                        // A video slower than the GIF uses a frame more than once.
                        while (next < timesUs.size &&
                            info.presentationTimeUs + slackUs >= timesUs[next]
                        ) {
                            emit(next, rgb)
                            next++
                        }
                    } finally {
                        image.close()
                    }
                }
                codec.releaseOutputBuffer(outIndex, false)
            }

            val c = converter ?: throw IllegalStateException("no frames")
            return mapOf("width" to c.width, "height" to c.height, "count" to next)
        } finally {
            try {
                codec?.stop()
            } catch (e: Exception) {
            }
            codec?.release()
            extractor.release()
        }
    }

    /**
     * Turns a decoded YUV 4:2:0 [Image] into packed RGB, upright and shrunk
     * so its longest side is at most `edge`, averaging over each block.
     */
    private class FrameConverter(
        image: Image,
        private val rotation: Int,
        edge: Int,
        format: MediaFormat,
    ) {
        private val crop = image.cropRect
        private val sourceWidth = image.width
        private val sourceHeight = image.height
        private val sourceFormat = image.format
        val width: Int
        val height: Int

        // 10-bit frames keep each sample in 2 bytes, top bits in the second.
        private val high = if (image.format == ImageFormat.YCBCR_P010) 1 else 0
        private val planes = arrayOfNulls<ByteArray>(3)
        private val coefficients: IntArray
        private val fullRange: Boolean

        init {
            val cw = crop.width()
            val ch = crop.height()
            require(cw in 1..MAX_SOURCE_EDGE && ch in 1..MAX_SOURCE_EDGE)
            val turned = rotation == 90 || rotation == 270
            val (uw, uh) = if (turned) Pair(ch, cw) else Pair(cw, ch)
            val longest = max(uw, uh)
            if (longest <= edge) {
                width = uw
                height = uh
            } else {
                val scale = edge.toDouble() / longest
                width = max(1, (uw * scale).roundToInt())
                height = max(1, (uh * scale).roundToInt())
            }
            val standard = if (format.containsKey(MediaFormat.KEY_COLOR_STANDARD)) {
                format.getInteger(MediaFormat.KEY_COLOR_STANDARD)
            } else if (ch >= 720) {
                MediaFormat.COLOR_STANDARD_BT709
            } else {
                MediaFormat.COLOR_STANDARD_BT601_NTSC
            }
            fullRange = format.containsKey(MediaFormat.KEY_COLOR_RANGE) &&
                format.getInteger(MediaFormat.KEY_COLOR_RANGE) == MediaFormat.COLOR_RANGE_FULL
            // R = Y + a·V, G = Y − b·U − c·V, B = Y + d·U, ×1024.
            coefficients = when (standard) {
                MediaFormat.COLOR_STANDARD_BT709 -> intArrayOf(1613, 192, 479, 1900)
                MediaFormat.COLOR_STANDARD_BT2020 -> intArrayOf(1510, 168, 585, 1927)
                else -> intArrayOf(1436, 352, 731, 1815)
            }
        }

        fun fits(image: Image) = image.width == sourceWidth &&
            image.height == sourceHeight && image.format == sourceFormat &&
            image.cropRect == crop

        private fun copy(index: Int, image: Image): ByteArray {
            val buffer = image.planes[index].buffer
            val size = buffer.remaining()
            var bytes = planes[index]
            if (bytes == null || bytes.size < size) {
                bytes = ByteArray(size)
                planes[index] = bytes
            }
            buffer.get(bytes, 0, size)
            buffer.rewind()
            return bytes
        }

        fun convert(image: Image): ByteArray {
            val yp = image.planes[0]
            val up = image.planes[1]
            val vp = image.planes[2]
            return YuvToRgb.convert(
                Plane(copy(0, image), yp.rowStride, yp.pixelStride),
                Plane(copy(1, image), up.rowStride, up.pixelStride),
                Plane(copy(2, image), vp.rowStride, vp.pixelStride),
                high, crop.left, crop.top, crop.width(), crop.height(),
                rotation, width, height, coefficients, fullRange,
            )
        }
    }

    class Plane(val bytes: ByteArray, val rowStride: Int, val pixelStride: Int)

    /** The pixel math, apart from [Image] so it can be checked off-device. */
    object YuvToRgb {
        /**
         * The `cw`×`ch` picture at (`left`, `top`) in 4:2:0 planes, turned
         * `rotation`° clockwise and shrunk to [width]×[height] packed RGB,
         * averaging at most 4×4 luma samples per block. [high] is 1 for
         * 16-bit samples (P010), whose top 8 bits are in the second byte.
         */
        fun convert(
            yPlane: Plane,
            uPlane: Plane,
            vPlane: Plane,
            high: Int,
            left: Int,
            top: Int,
            cw: Int,
            ch: Int,
            rotation: Int,
            width: Int,
            height: Int,
            coefficients: IntArray,
            fullRange: Boolean,
        ): ByteArray {
            val yBytes = yPlane.bytes
            val uBytes = uPlane.bytes
            val vBytes = vPlane.bytes
            val yRow = yPlane.rowStride
            val yPixel = yPlane.pixelStride
            val uRow = uPlane.rowStride
            val uPixel = uPlane.pixelStride
            val vRow = vPlane.rowStride
            val vPixel = vPlane.pixelStride
            val turned = rotation == 90 || rotation == 270
            // The upright size, in source pixels.
            val bw = if (turned) ch else cw
            val bh = if (turned) cw else ch
            val out = ByteArray(width * height * 3)
            val a = coefficients[0]
            val b = coefficients[1]
            val c = coefficients[2]
            val d = coefficients[3]
            var o = 0
            for (ty in 0 until height) {
                val v0 = ty * bh / height
                val v1 = max(v0 + 1, (ty + 1) * bh / height)
                val vStep = max(1, (v1 - v0) / 4)
                for (tx in 0 until width) {
                    val u0 = tx * bw / width
                    val u1 = max(u0 + 1, (tx + 1) * bw / width)
                    val uStep = max(1, (u1 - u0) / 4)
                    var sum = 0
                    var n = 0
                    var uy = v0
                    while (uy < v1) {
                        var ux = u0
                        while (ux < u1) {
                            // Upright (ux, uy) back to the stored picture.
                            val sx: Int
                            val sy: Int
                            when (rotation) {
                                90 -> { sx = uy; sy = ch - 1 - ux }
                                180 -> { sx = cw - 1 - ux; sy = ch - 1 - uy }
                                270 -> { sx = cw - 1 - uy; sy = ux }
                                else -> { sx = ux; sy = uy }
                            }
                            sum += yBytes[(top + sy) * yRow + (left + sx) * yPixel + high]
                                .toInt() and 0xFF
                            n++
                            ux += uStep
                        }
                        uy += vStep
                    }
                    // Chroma is stored at half size: average 2×2 samples
                    // from the block's quarters.
                    var cu = 0
                    var cv = 0
                    for (q in 0 until 4) {
                        val mx = u0 + (u1 - u0) * (1 + 2 * (q and 1)) / 4
                        val my = v0 + (v1 - v0) * (1 + 2 * (q shr 1)) / 4
                        val cx: Int
                        val cy: Int
                        when (rotation) {
                            90 -> { cx = my; cy = ch - 1 - mx }
                            180 -> { cx = cw - 1 - mx; cy = ch - 1 - my }
                            270 -> { cx = cw - 1 - my; cy = mx }
                            else -> { cx = mx; cy = my }
                        }
                        val chromaX = (left + cx) shr 1
                        val chromaY = (top + cy) shr 1
                        cu += uBytes[chromaY * uRow + chromaX * uPixel + high].toInt() and 0xFF
                        cv += vBytes[chromaY * vRow + chromaX * vPixel + high].toInt() and 0xFF
                    }
                    var yy = sum / n
                    cu = (cu shr 2) - 128
                    cv = (cv shr 2) - 128
                    if (!fullRange) {
                        // Studio range 16–235 (Y) / 16–240 (UV) to 0–255.
                        yy = ((yy - 16) * 1192 + 512) shr 10
                        cu = (cu * 1166 + 512) shr 10
                        cv = (cv * 1166 + 512) shr 10
                    }
                    out[o++] = clamp(yy + ((a * cv + 512) shr 10))
                    out[o++] = clamp(yy - ((b * cu + c * cv + 512) shr 10))
                    out[o++] = clamp(yy + ((d * cu + 512) shr 10))
                }
            }
            return out
        }

        private fun clamp(v: Int): Byte = (if (v < 0) 0 else if (v > 255) 255 else v).toByte()
    }
}
