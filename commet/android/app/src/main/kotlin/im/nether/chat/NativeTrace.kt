package im.nether.chat

// Reads the crashing thread's backtrace from an Android tombstone (the
// protobuf ApplicationExitInfo.getTraceInputStream() returns for native
// crashes on Android 12+; format: AOSP system/core/debuggerd/proto/tombstone.proto).
// Keeps code identifiers only: library file name (no path), symbol name and
// offset. The abort message is free text, so only a coarse category of it is
// kept, never the text.
object NativeTrace {
    data class Result(
        val frames: List<String>,
        val thread: String?,
        val abortKind: String,
    )

    private class Reader(val buf: ByteArray, var pos: Int, val end: Int) {
        fun more() = pos < end
        fun varint(): Long {
            var shift = 0
            var result = 0L
            while (pos < end) {
                val b = buf[pos++].toInt() and 0xff
                result = result or ((b and 0x7f).toLong() shl shift)
                if (b and 0x80 == 0) return result
                shift += 7
                if (shift > 63) break
            }
            return result
        }
        fun bytes(): Reader {
            val len = varint().toInt()
            val r = Reader(buf, pos, minOf(end, pos + len))
            pos = minOf(end, pos + len)
            return r
        }
        fun string(): String = bytes().let { String(buf, it.pos, it.end - it.pos, Charsets.UTF_8) }
        fun skip(wire: Int) {
            when (wire) {
                0 -> varint()
                1 -> pos += 8
                2 -> bytes()
                5 -> pos += 4
                else -> pos = end
            }
        }
    }

    private val fileName = Regex("^[A-Za-z0-9_.+-]{1,80}$")
    private val symbol = Regex("^[A-Za-z0-9_$.]{1,200}$")

    fun parse(data: ByteArray): Result? {
        try {
            val r = Reader(data, 0, data.size)
            var tid = -1L
            var abort = ""
            val threads = HashMap<Long, Reader>()
            while (r.more()) {
                val tag = r.varint()
                val field = (tag ushr 3).toInt()
                val wire = (tag and 7).toInt()
                when {
                    field == 6 && wire == 0 -> tid = r.varint()
                    field == 14 && wire == 2 -> abort = r.string()
                    field == 16 && wire == 2 -> {
                        // map<uint32, Thread> entry: key = 1, value = 2
                        val e = r.bytes()
                        var key = -1L
                        var value: Reader? = null
                        while (e.more()) {
                            val t = e.varint()
                            val f = (t ushr 3).toInt()
                            val w = (t and 7).toInt()
                            if (f == 1 && w == 0) key = e.varint()
                            else if (f == 2 && w == 2) value = e.bytes()
                            else e.skip(w)
                        }
                        if (value != null) threads[key] = value
                    }
                    else -> r.skip(wire)
                }
            }
            val thread = threads[tid] ?: return null
            var name: String? = null
            val frames = ArrayList<String>()
            while (thread.more()) {
                val t = thread.varint()
                val f = (t ushr 3).toInt()
                val w = (t and 7).toInt()
                if (f == 2 && w == 2) {
                    name = thread.string()
                } else if (f == 4 && w == 2 && frames.size < 30) {
                    frames.add(frame(thread.bytes()))
                } else {
                    thread.skip(w)
                }
            }
            return Result(frames, name?.takeIf { Regex("^[A-Za-z0-9_ .:#/-]{1,32}$").matches(it) }, abortKind(abort))
        } catch (_: Throwable) {
            return null
        }
    }

    // BacktraceFrame: rel_pc = 1, function_name = 4, function_offset = 5, file_name = 6
    private fun frame(r: Reader): String {
        var relPc = 0L
        var fn = ""
        var fnOff = 0L
        var file = ""
        while (r.more()) {
            val t = r.varint()
            val f = (t ushr 3).toInt()
            val w = (t and 7).toInt()
            when {
                f == 1 && w == 0 -> relPc = r.varint()
                f == 4 && w == 2 -> fn = r.string()
                f == 5 && w == 0 -> fnOff = r.varint()
                f == 6 && w == 2 -> file = r.string()
                else -> r.skip(w)
            }
        }
        val lib = file.substringAfterLast('/').let { if (fileName.matches(it)) it else "?" }
        return if (fn.isNotEmpty() && symbol.matches(fn)) {
            "$lib!$fn+0x${java.lang.Long.toHexString(fnOff)}"
        } else {
            "$lib+0x${java.lang.Long.toHexString(relPc)}"
        }
    }

    private fun abortKind(msg: String): String = when {
        msg.isEmpty() -> "none"
        msg.contains("Check failed") || msg.contains("#\n# Fatal error") -> "check_failed"
        msg.contains("panicked") -> "rust_panic"
        msg.startsWith("JNI DETECTED ERROR") || msg.contains("JNI DETECTED") -> "jni"
        msg.contains("FORTIFY") -> "fortify"
        msg.contains("Scudo ERROR") || msg.contains("scudo") -> "heap"
        else -> "other"
    }
}
