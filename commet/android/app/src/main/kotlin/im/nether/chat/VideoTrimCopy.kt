package im.nether.chat

import android.annotation.TargetApi
import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer

/** Vommet issue 1051: bounded API 35 AVC/AAC-LC copying, never transcoding. */
@TargetApi(35)
object VideoTrimCopy {
    const val MAX_BYTES = 64L * 1024 * 1024
    private const val MAX_US = 120_000_000L
    private const val MAX_SAMPLE = 2 * 1024 * 1024
    data class Info(val formats: List<Pair<Int, MediaFormat>>, val cuts: List<Long>, val duration: Long)

    fun inspect(source: String, check: () -> Unit): Info {
        require(File(source).length() in 1..MAX_BYTES)
        val header = ByteArray(12)
        File(source).inputStream().use { require(it.read(header) == 12) }
        require(ByteBuffer.wrap(header).getInt(4) == 0x66747970 &&
            String(header, 8, 4, Charsets.US_ASCII) in listOf("isom", "iso2", "mp41", "mp42", "avc1", "M4V "))
        val reader = MediaExtractor()
        try {
            reader.setDataSource(source)
            val formats = (0 until reader.trackCount).map { it to reader.getTrackFormat(it) }
            require(formats.size in 1..2)
            val videos = formats.filter { it.second.getString(MediaFormat.KEY_MIME) == "video/avc" }
            require(videos.size == 1)
            val (track, video) = videos.single()
            require(video.getInteger(MediaFormat.KEY_WIDTH) in 1..1920 && video.getInteger(MediaFormat.KEY_HEIGHT) in 1..1920)
            require(video.getInteger(MediaFormat.KEY_COLOR_STANDARD, 0) == MediaFormat.COLOR_STANDARD_BT709 &&
                video.getInteger(MediaFormat.KEY_COLOR_TRANSFER, 0) == MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
            val sps = video.getByteBuffer("csd-0")!!.duplicate()
            require(sps.remaining() > 6 && sps.getInt(0) == 1 && (sps.get(4).toInt() and 31) == 7 &&
                (sps.get(5).toInt() and 255) in listOf(66, 77, 88, 100))
            for ((i, format) in formats) if (i != track) {
                require(format.getString(MediaFormat.KEY_MIME) == "audio/mp4a-latm")
                val config = format.getByteBuffer("csd-0")!!.duplicate()
                val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                require(channels in 1..2 && format.getInteger(MediaFormat.KEY_SAMPLE_RATE) == 48000)
                // Standard 1024-sample AAC-LC only; no HE/SBR or short-frame extension.
                require(config.remaining() in listOf(2, 5) &&
                    (config.getShort(0).toInt() and 65535) == (0x1180 or (channels shl 3)))
                if (config.remaining() == 5) require(config.get(2) == 0x56.toByte() &&
                    config.get(3) == 0xe5.toByte() && config.get(4) == 0.toByte())
            }
            val duration = video.getLong(MediaFormat.KEY_DURATION)
            require(duration in 1..MAX_US)
            reader.selectTrack(track)
            val cuts = mutableListOf<Long>()
            val buffer = ByteBuffer.allocate(MAX_SAMPLE)
            var count = 0
            do {
                check()
                require(++count <= 7200 && reader.sampleTime in 0..duration)
                require(reader.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC.inv() == 0)
                require(reader.sampleSize in 1..MAX_SAMPLE.toLong())
                if (reader.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                    buffer.clear()
                    val size = reader.readSampleData(buffer, 0)
                    require(idr(buffer, size))
                    cuts.add(reader.sampleTime)
                    require(cuts.size <= 256)
                }
            } while (reader.advance())
            require(cuts.firstOrNull() == 0L && cuts.zipWithNext().all { it.first < it.second })
            return Info(formats, cuts, duration)
        } finally { reader.release() }
    }

    // Android's extractor supplies Annex B. Reject ambiguous/other NAL framing.
    private fun idr(data: ByteBuffer, size: Int): Boolean {
        require(size >= 5 && data.getInt(0) == 1)
        var found = false
        var at = 4
        while (at < size) {
            val type = data.get(at).toInt() and 31
            require(type in 1..23 && type != 1) // no non-IDR VCL in a safe sync sample
            if (type == 5) found = true
            at++
            while (at + 3 < size && !(data.get(at) == 0.toByte() && data.get(at + 1) == 0.toByte() &&
                    (data.get(at + 2) == 1.toByte() || (data.get(at + 2) == 0.toByte() && data.get(at + 3) == 1.toByte())))) at++
            if (at + 3 >= size) break
            at += if (data.get(at + 2) == 1.toByte()) 3 else 4
        }
        return found
    }

    fun copy(source: String, target: String, start: Long, end: Long?, check: () -> Unit): Map<String, Any> {
        require(File(source).canonicalFile != File(target).canonicalFile)
        val readers = mutableMapOf<Int, MediaExtractor>()
        var muxer: MediaMuxer? = null
        var success = false
        try {
            val info = inspect(source, check)
            require(start in info.cuts && (end == null || end in info.cuts && end > start))
            for ((input, format) in info.formats) {
                val reader = MediaExtractor()
                readers[input] = reader
                reader.setDataSource(source)
                reader.selectTrack(input)
                if (format.getString(MediaFormat.KEY_MIME)!!.startsWith("video/"))
                    reader.seekTo(start, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                var count = 0
                while (reader.sampleTrackIndex >= 0 && reader.sampleTime < start) {
                    check(); require(++count <= 15000)
                    if (!reader.advance()) break
                }
                require(reader.sampleTime >= start && (end == null || reader.sampleTime < end))
            }
            val rotationReader = MediaMetadataRetriever()
            val rotation = try {
                rotationReader.setDataSource(source)
                rotationReader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)!!.toInt()
            } finally { rotationReader.release() }
            val writer = MediaMuxer(target, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = writer
            val tracks = info.formats.associate { (i, f) -> i to (f to writer.addTrack(f)) }
            writer.setOrientationHint(rotation)
            writer.start()
            val live = readers.toMutableMap()
            val initialized = mutableSetOf<Int>()
            val audioEnds = mutableMapOf<Int, Long>()
            val buffer = ByteBuffer.allocate(MAX_SAMPLE)
            val sample = MediaCodec.BufferInfo()
            var count = 0
            var videoStarted = false
            while (live.isNotEmpty()) {
                // Finish initializing declared tracks before canceling a partial muxer.
                if (initialized.size == tracks.size) check()
                require(++count <= 15000)
                val (input, reader) = live.minBy { it.value.sampleTime }
                val (format, output) = tracks.getValue(input)
                val audio = format.getString(MediaFormat.KEY_MIME)!!.startsWith("audio/")
                val pts = reader.sampleTime
                val sync = reader.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0
                if (pts < 0 || (end != null && pts >= end && (audio || sync))) {
                    live.remove(input); continue
                }
                require(pts >= start && (audio || end == null || pts < end))
                if (!audio) {
                    if (!videoStarted) require(pts == start && sync)
                    videoStarted = true
                }
                val packet = if (audio) 1_024_000_000L / format.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 0L
                if (!audio || end == null || pts + packet <= end) {
                    require(reader.sampleSize in 1..MAX_SAMPLE.toLong())
                    require(reader.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC.inv() == 0)
                    buffer.clear()
                    val size = reader.readSampleData(buffer, 0)
                    require(size > 0 && size <= MAX_SAMPLE)
                    sample.set(0, size, pts - start, if (sync) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                    writer.writeSampleData(output, buffer, sample)
                    initialized.add(input)
                    if (audio) audioEnds[output] = pts - start + packet
                }
                if (!reader.advance()) live.remove(input)
            }
            require(initialized.size == tracks.size)
            check()
            for ((format, output) in tracks.values) {
                val audio = format.getString(MediaFormat.KEY_MIME)!!.startsWith("audio/")
                if (audio || end != null) {
                    sample.set(0, 0, if (audio) audioEnds.getValue(output) else end!! - start, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    writer.writeSampleData(output, ByteBuffer.allocate(0), sample)
                }
            }
            writer.stop()
            check()
            val metadata = metadata(target)
            require(File(target).length() in 1..MAX_BYTES)
            success = true
            return metadata
        } finally {
            readers.values.forEach { it.release() }
            try { muxer?.release() } finally { if (!success) File(target).delete() }
        }
    }

    private fun metadata(path: String): Map<String, Any> {
        val reader = MediaMetadataRetriever()
        try {
            reader.setDataSource(path)
            fun value(key: Int) = reader.extractMetadata(key)!!.toInt()
            val rotation = value(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            val w = value(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val h = value(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val duration = value(MediaMetadataRetriever.METADATA_KEY_DURATION)
            require(w > 0 && h > 0 && duration > 0)
            val frame = reader.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 256, 256)!!
            val jpeg = ByteArrayOutputStream()
            try { require(frame.compress(Bitmap.CompressFormat.JPEG, 80, jpeg)) } finally { frame.recycle() }
            return mapOf("durationMs" to duration, "width" to if (rotation % 180 == 0) w else h,
                "height" to if (rotation % 180 == 0) h else w, "thumbnail" to jpeg.toByteArray())
        } finally { reader.release() }
    }
}
