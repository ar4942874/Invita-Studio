package com.invitationstudio.invitation_studio

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.Executors

/**
 * H.264 + AAC encoder used by Invita Studio's video export.
 *
 * Frames arrive from Flutter as RGBA8888 byte arrays with deterministic
 * presentation timestamps (frame index / fps). They are converted to the
 * encoder's YUV colour format on a single background thread, encoded with
 * MediaCodec and muxed with MediaMuxer. Optional music is decoded, trimmed,
 * gain/fade processed, encoded to AAC and muxed into the same file.
 *
 * No sample is uploaded anywhere; the MP4 is written to the path given by Dart.
 */
class VideoExportPlugin(context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "invita/video_export"
        private const val TAG = "VideoExport"
        private const val TIMEOUT_US = 10_000L
    }

    private val appContext = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val sessions = HashMap<String, ExportSession>()

    fun attach(channel: MethodChannel) {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            try {
                when (call.method) {
                    "open" -> open(call, result)
                    "addFrame" -> addFrame(call, result)
                    "finish" -> finish(call, result)
                    "cancel" -> cancel(call, result)
                    else -> reply(result) { result.notImplemented() }
                }
            } catch (error: Throwable) {
                reply(result) {
                    result.error("export_failed", error.message ?: "Video export failed", null)
                }
            }
        }
    }

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        val outputPath = call.argument<String>("outputPath")
            ?: throw IllegalArgumentException("outputPath is required")
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        val fps = call.argument<Int>("fps") ?: 30
        val frameCount = call.argument<Int>("frameCount") ?: 0
        val bitrate = call.argument<Int>("bitrate") ?: 8_000_000
        require(width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0) {
            "Unsupported video size"
        }
        require(fps in 1..60 && frameCount in 1..900) { "Unsupported video length" }
        val audio = call.argument<Map<String, Any?>>("audio")

        val session = ExportSession(
            width = width,
            height = height,
            fps = fps,
            outputPath = outputPath,
            frameCount = frameCount,
        )
        session.prepareVideo(bitrate)
        if (audio != null) {
            session.prepareAudio(
                path = audio["path"] as String,
                startMs = (audio["startMs"] as Number).toLong(),
                trimStartMs = (audio["trimStartMs"] as Number).toLong(),
                trimEndMs = (audio["trimEndMs"] as Number).toLong(),
                volume = (audio["volume"] as Number).toInt(),
                fadeInMs = (audio["fadeInMs"] as Number).toLong(),
                fadeOutMs = (audio["fadeOutMs"] as Number).toLong(),
                durationMs = (audio["durationMs"] as Number).toLong(),
            )
        }
        val id = UUID.randomUUID().toString()
        sessions[id] = session
        reply(result) { result.success(id) }
    }

    private fun addFrame(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("sessionId")
            ?: throw IllegalArgumentException("sessionId is required")
        val session = sessions[id] ?: throw IllegalStateException("Unknown session")
        val rgba = call.argument<ByteArray>("bytes")
            ?: throw IllegalArgumentException("Frame bytes are required")
        val ptsUs = (call.argument<Number>("timestampUs")?.toLong()) ?: 0L
        session.addFrame(rgba, ptsUs)
        reply(result) { result.success(null) }
    }

    private fun finish(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("sessionId")
            ?: throw IllegalArgumentException("sessionId is required")
        val session = sessions.remove(id) ?: throw IllegalStateException("Unknown session")
        val path = session.finish()
        reply(result) { result.success(path) }
    }

    private fun cancel(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("sessionId")
        val session = if (id != null) sessions.remove(id) else null
        session?.cancel()
        reply(result) { result.success(null) }
    }

    private fun reply(result: MethodChannel.Result, block: () -> Unit) {
        mainHandler.post(block)
    }

    private inner class ExportSession(
        private val width: Int,
        private val height: Int,
        private val fps: Int,
        private val outputPath: String,
        private val frameCount: Int,
    ) {
        private lateinit var codec: MediaCodec
        private lateinit var muxer: MediaMuxer
        private var colorFormat = MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar
        private var videoTrack = -1
        private var audioTrack = -1
        private var muxerStarted = false
        private val bufferInfo = MediaCodec.BufferInfo()
        private val pendingVideo = ArrayList<Pair<ByteArray, Long>>()
        private var audioSamples: List<EncodedSample> = emptyList()
        private var audioFormat: MediaFormat? = null
        private var yuv: ByteArray = ByteArray(width * height * 3 / 2)
        private var framesWritten = 0
        private var finished = false

        fun prepareVideo(bitrate: Int) {
            val codecInfo = selectAvcEncoder()
            colorFormat = selectColorFormat(codecInfo)
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height)
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, colorFormat)
            format.setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            format.setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, width * height * 3 / 2)
            format.setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
            format.setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.AVCLevel41)
            codec = MediaCodec.createByCodecName(codecInfo.name)
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        }

        fun prepareAudio(
            path: String,
            startMs: Long,
            trimStartMs: Long,
            trimEndMs: Long,
            volume: Int,
            fadeInMs: Long,
            fadeOutMs: Long,
            durationMs: Long,
        ) {
            val result = AudioEncoder.encode(
                path = path,
                startMs = startMs,
                trimStartMs = trimStartMs,
                trimEndMs = trimEndMs,
                volume = volume,
                fadeInMs = fadeInMs,
                fadeOutMs = fadeOutMs,
                durationMs = durationMs,
                targetAacBitrate = 128_000,
            )
            audioFormat = result.format
            audioSamples = result.samples
        }

        fun addFrame(rgba: ByteArray, ptsUs: Long) {
            check(!finished) { "Session already finished" }
            require(rgba.size == width * height * 4) {
                "Frame must be ${width * height * 4} bytes, got ${rgba.size}"
            }
            rgbaToYuv(rgba, yuv, width, height, colorFormat)
            var queued = false
            while (!queued) {
                val inputIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                if (inputIndex >= 0) {
                    val buffer = codec.getInputBuffer(inputIndex)
                        ?: throw IllegalStateException("Encoder input buffer missing")
                    buffer.clear()
                    buffer.put(yuv)
                    codec.queueInputBuffer(inputIndex, 0, yuv.size, ptsUs, 0)
                    queued = true
                }
                drainVideo(endOfStream = false)
            }
            framesWritten++
        }

        fun finish(): String {
            check(!finished) { "Session already finished" }
            finished = true
            var eosSent = false
            val deadline = System.currentTimeMillis() + 30_000
            while (!eosSent || !videoDone) {
                if (!eosSent) {
                    val inputIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (inputIndex >= 0) {
                        codec.queueInputBuffer(
                            inputIndex,
                            0,
                            0,
                            framesWritten * 1_000_000L / fps,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                        )
                        eosSent = true
                    }
                }
                drainVideo(endOfStream = true)
                if (System.currentTimeMillis() > deadline) break
                if (eosSent && videoDone) break
            }
            codec.stop()
            codec.release()
            if (muxerStarted) {
                muxer.stop()
            }
            muxer.release()
            if (framesWritten != frameCount) {
                throw IllegalStateException(
                    "Expected $frameCount frames but encoded $framesWritten",
                )
            }
            val file = File(outputPath)
            if (!file.exists() || file.length() < 1024) {
                throw IllegalStateException("Encoder produced no usable file")
            }
            return outputPath
        }

        fun cancel() {
            if (finished) return
            finished = true
            try {
                codec.stop()
            } catch (_: Throwable) {
            }
            try {
                codec.release()
            } catch (_: Throwable) {
            }
            try {
                if (muxerStarted) muxer.stop()
            } catch (_: Throwable) {
            }
            try {
                muxer.release()
            } catch (_: Throwable) {
            }
            File(outputPath).delete()
        }

        private var videoDone = false

        private fun drainVideo(endOfStream: Boolean) {
            while (true) {
                val outputIndex = codec.dequeueOutputBuffer(bufferInfo, if (endOfStream) TIMEOUT_US else 0)
                if (outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    return
                }
                if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    if (videoTrack < 0) {
                        videoTrack = muxer.addTrack(codec.outputFormat)
                    }
                    maybeStartMuxer()
                    continue
                }
                if (outputIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED) {
                    continue
                }
                if (outputIndex < 0) return
                val outputBuffer = codec.getOutputBuffer(outputIndex)
                    ?: throw IllegalStateException("Encoder output buffer missing")
                outputBuffer.position(bufferInfo.offset)
                outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                val sample = ByteArray(bufferInfo.size)
                outputBuffer.get(sample)
                val ptsUs = bufferInfo.presentationTimeUs
                codec.releaseOutputBuffer(outputIndex, false)
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    videoDone = true
                }
                if (bufferInfo.size > 0) {
                    if (muxerStarted && videoTrack >= 0) {
                        writeVideoSample(sample, ptsUs, bufferInfo.flags)
                    } else {
                        pendingVideo.add(sample to ptsUs)
                    }
                }
                if (videoDone) return
            }
        }

        private fun writeVideoSample(sample: ByteArray, ptsUs: Long, flags: Int) {
            val info = MediaCodec.BufferInfo()
            info.set(
                0,
                sample.size,
                ptsUs,
                if ((flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0) {
                    MediaCodec.BUFFER_FLAG_KEY_FRAME
                } else {
                    0
                },
            )
            muxer.writeSampleData(videoTrack, ByteBuffer.wrap(sample), info)
        }

        private fun maybeStartMuxer() {
            if (muxerStarted) return
            if (videoTrack < 0) return
            val audio = audioFormat
            if (audio != null && audioTrack < 0) {
                audioTrack = muxer.addTrack(audio)
            }
            muxer.start()
            muxerStarted = true
            for ((sample, ptsUs) in pendingVideo) {
                writeVideoSample(sample, ptsUs, 0)
            }
            pendingVideo.clear()
            if (audioTrack >= 0) {
                for (sample in audioSamples) {
                    val info = MediaCodec.BufferInfo()
                    info.set(0, sample.data.size, sample.ptsUs, 0)
                    muxer.writeSampleData(audioTrack, ByteBuffer.wrap(sample.data), info)
                }
                audioSamples = emptyList()
            }
        }

        private fun selectAvcEncoder(): MediaCodecInfo {
            val codecs = android.media.MediaCodecList(android.media.MediaCodecList.REGULAR_CODECS)
            for (info in codecs.codecInfos) {
                if (!info.isEncoder) continue
                for (type in info.supportedTypes) {
                    if (!type.equals(MediaFormat.MIMETYPE_VIDEO_AVC, ignoreCase = true)) continue
                    val caps = info.getCapabilitiesForType(type)
                    val profile = caps.profileLevels.any {
                        it.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline
                    }
                    if (profile) return info
                }
            }
            throw IllegalStateException("No H.264 encoder with Baseline profile found")
        }

        private fun selectColorFormat(info: MediaCodecInfo): Int {
            val caps = info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
            val preferred = intArrayOf(
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
            )
            for (candidate in preferred) {
                if (caps.colorFormats.contains(candidate)) {
                    // COLOR_FormatYUV420Flexible byte-buffer layout is undefined;
                    // fall back to Planar when only Flexible is advertised.
                    if (candidate == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible) {
                        continue
                    }
                    return candidate
                }
            }
            return if (caps.colorFormats.contains(MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar)) {
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar
            } else {
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar
            }
        }
    }
}

/** One encoded AAC buffer with its deterministic presentation timestamp. */
data class EncodedSample(val data: ByteArray, val ptsUs: Long)

class EncodedAudioResult(val format: MediaFormat, val samples: List<EncodedSample>)

/**
 * Decodes a music file to PCM, applies trim/window/gain/fades and re-encodes to
 * AAC. Everything is bounded by the target duration (5–30 s), so the encoded
 * samples fit comfortably in memory (~240 KB for 15 s at 128 kbps).
 */
object AudioEncoder {
    fun encode(
        path: String,
        startMs: Long,
        trimStartMs: Long,
        trimEndMs: Long,
        volume: Int,
        fadeInMs: Long,
        fadeOutMs: Long,
        durationMs: Long,
        targetAacBitrate: Int,
    ): EncodedAudioResult {
        val extractor = MediaExtractor()
        extractor.setDataSource(path)
        var trackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val candidate = extractor.getTrackFormat(i)
            val mime = candidate.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                trackIndex = i
                format = candidate
                break
            }
        }
        require(trackIndex >= 0 && format != null) { "No audio track in the music file" }
        extractor.selectTrack(trackIndex)
        val audioFormat = format!!
        val mime = audioFormat.getString(MediaFormat.KEY_MIME)!!

        val decoder = MediaCodec.createDecoderByType(mime)
        decoder.configure(audioFormat, null, null, 0)
        decoder.start()

        var sampleRate = audioFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channelCount = audioFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

        val audioEndMs = startMs + durationMs
        val trimStartUs = trimStartMs * 1000L
        val trimEndUs = if (trimEndMs > trimStartMs) trimEndMs * 1000L else Long.MAX_VALUE
        val gain = (volume.coerceIn(0, 100)) / 100.0
        val fadeInUs = fadeInMs.coerceAtLeast(0) * 1000L
        val fadeOutUs = fadeOutMs.coerceAtLeast(0) * 1000L

        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        var encoderConfigured = false
        var encoderFormat: MediaFormat? = null
        val samples = ArrayList<EncodedSample>()
        val bufferInfo = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        var encoderInputDone = false
        var writtenUs = 0L

        fun drainEncoder(endOfStream: Boolean) {
            while (true) {
                val index = encoder.dequeueOutputBuffer(bufferInfo, if (endOfStream) 10_000L else 0L)
                if (index == MediaCodec.INFO_TRY_AGAIN_LATER) return
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    encoderFormat = encoder.outputFormat
                    continue
                }
                if (index < 0) continue
                val buffer = encoder.getOutputBuffer(index) ?: continue
                if (bufferInfo.size > 0 &&
                    (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
                ) {
                    val data = ByteArray(bufferInfo.size)
                    buffer.position(bufferInfo.offset)
                    buffer.limit(bufferInfo.offset + bufferInfo.size)
                    buffer.get(data)
                    samples.add(EncodedSample(data, bufferInfo.presentationTimeUs))
                }
                encoder.releaseOutputBuffer(index, false)
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    outputDone = true
                    return
                }
            }
        }

        try {
            while (!inputDone || !outputDone) {
                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(10_000L)
                    if (inIndex >= 0) {
                        val buffer = decoder.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIndex = decoder.dequeueOutputBuffer(bufferInfo, 10_000L)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val outFormat = decoder.outputFormat
                    sampleRate = outFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channelCount = outFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    continue
                }
                if (outIndex < 0) continue
                val pcmBuffer = decoder.getOutputBuffer(outIndex)
                val size = bufferInfo.size
                val ptsUs = bufferInfo.presentationTimeUs
                val decFlags = bufferInfo.flags
                if (pcmBuffer != null && size > 0 && (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                    pcmBuffer.position(bufferInfo.offset)
                    pcmBuffer.limit(bufferInfo.offset + size)
                    val pcm = ShortArray(size / 2)
                    val shorts = pcmBuffer.asShortBuffer()
                    shorts.get(pcm)
                    if (!encoderConfigured) {
                        val outFormat = MediaFormat.createAudioFormat(
                            MediaFormat.MIMETYPE_AUDIO_AAC,
                            sampleRate,
                            channelCount,
                        )
                        outFormat.setInteger(
                            MediaFormat.KEY_AAC_PROFILE,
                            MediaCodecInfo.CodecProfileLevel.AACObjectLC,
                        )
                        outFormat.setInteger(MediaFormat.KEY_BIT_RATE, targetAacBitrate)
                        outFormat.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
                        encoder.configure(outFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                        encoder.start()
                        encoderConfigured = true
                    }
                    val localUs = ptsUs - trimStartUs
                    if (ptsUs < trimEndUs) {
                        val frameDurationUs = 1_000_000L / sampleRate
                        val outPcm = ShortArray(pcm.size)
                        var length = 0
                        for (i in pcm.indices) {
                            val sampleLocalUs = localUs + (i / channelCount) * frameDurationUs
                            if (sampleLocalUs < 0) continue
                            val outUs = startMs * 1000L + sampleLocalUs
                            if (outUs >= audioEndMs * 1000L) break
                            if (ptsUs + (i / channelCount) * frameDurationUs >= trimEndUs) break
                            var value = pcm[i].toDouble() * gain
                            if (fadeInUs > 0 && sampleLocalUs < fadeInUs) {
                                value *= sampleLocalUs.toDouble() / fadeInUs
                            }
                            val remainingUs = audioEndMs * 1000L - outUs
                            if (fadeOutUs > 0 && remainingUs < fadeOutUs) {
                                value *= (remainingUs.toDouble() / fadeOutUs).coerceIn(0.0, 1.0)
                            }
                            outPcm[length++] = value.toInt().coerceIn(-32768, 32767).toShort()
                            if (length == outPcm.size) break
                        }
                        if (length > 0) {
                            var offsetSamples = 0
                            while (offsetSamples < length) {
                                val encIndex = encoder.dequeueInputBuffer(10_000L)
                                if (encIndex < 0) continue
                                val encBuffer = encoder.getInputBuffer(encIndex)!!
                                encBuffer.clear()
                                val capacitySamples = encBuffer.remaining() / 2
                                val count = minOf(capacitySamples, length - offsetSamples)
                                val shortsBuffer = encBuffer.asShortBuffer()
                                shortsBuffer.put(outPcm, offsetSamples, count)
                                val pts = startMs * 1000L + writtenUs
                                encoder.queueInputBuffer(encIndex, 0, count * 2, pts, 0)
                                writtenUs += count.toLong() * 1_000_000L / (sampleRate * channelCount)
                                offsetSamples += count
                                drainEncoder(false)
                            }
                        }
                    }
                }
                decoder.releaseOutputBuffer(outIndex, false)
                if ((decFlags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
            }
            if (encoderConfigured && !encoderInputDone) {
                val encIndex = encoder.dequeueInputBuffer(10_000L)
                if (encIndex >= 0) {
                    encoder.queueInputBuffer(
                        encIndex,
                        0,
                        0,
                        startMs * 1000L + writtenUs,
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                    )
                    encoderInputDone = true
                }
                drainEncoder(true)
            }
        } finally {
            try {
                decoder.stop()
            } catch (_: Throwable) {
            }
            decoder.release()
            extractor.release()
            if (encoderConfigured) {
                try {
                    encoder.stop()
                } catch (_: Throwable) {
                }
            }
            encoder.release()
        }
        require(encoderConfigured && encoderFormat != null) { "Music could not be encoded" }
        return EncodedAudioResult(encoderFormat!!, samples)
    }
}

/** Converts RGBA8888 to I420 or NV12 (no row padding). */
fun rgbaToYuv(
    rgba: ByteArray,
    out: ByteArray,
    width: Int,
    height: Int,
    colorFormat: Int,
) {
    val ySize = width * height
    val chromaSize = ySize / 4
    val semiPlanar = colorFormat == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar
    var yIndex = 0
    var uIndex = ySize
    var vIndex = ySize + chromaSize
    var uvIndex = ySize
    for (y in 0 until height) {
        val row = y * width
        for (x in 0 until width) {
            val offset = (row + x) * 4
            val r = rgba[offset].toInt() and 0xff
            val g = rgba[offset + 1].toInt() and 0xff
            val b = rgba[offset + 2].toInt() and 0xff
            val luma = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
            out[yIndex++] = luma.coerceIn(0, 255).toByte()
            if ((y and 1) == 0 && (x and 1) == 0) {
                val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                val uByte = u.coerceIn(0, 255).toByte()
                val vByte = v.coerceIn(0, 255).toByte()
                if (semiPlanar) {
                    out[uvIndex++] = uByte
                    out[uvIndex++] = vByte
                } else {
                    out[uIndex++] = uByte
                    out[vIndex++] = vByte
                }
            }
        }
    }
}
