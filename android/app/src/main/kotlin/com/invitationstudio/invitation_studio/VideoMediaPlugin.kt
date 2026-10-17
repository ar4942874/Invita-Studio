package com.invitationstudio.invitation_studio

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Native media probing and frame extraction for background video clips.
 *
 * Frames are decoded once at import time into a bounded JPEG sequence in the
 * app's managed media directory. Preview and export then read that sequence,
 * which keeps export deterministic and avoids decoding video during playback.
 */
class VideoMediaPlugin(context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "invita/video_media"
        private const val JPEG_QUALITY = 82
    }

    private val appContext = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    @Volatile
    private var cancelRequested = false

    fun attach(methodChannel: MethodChannel) {
        channel = methodChannel
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cancelExtraction" -> {
                cancelRequested = true
                result.success(null)
            }
            else -> executor.execute {
                try {
                    when (call.method) {
                        "probeVideo" -> probeVideo(call, result)
                        "probeAudio" -> probeAudio(call, result)
                        "extractFrames" -> extractFrames(call, result)
                        else -> post { result.notImplemented() }
                    }
                } catch (error: Throwable) {
                    post {
                        result.error(
                            "media_failed",
                            error.message ?: "Media operation failed",
                            null,
                        )
                    }
                }
            }
        }
    }

    private fun post(block: () -> Unit) = mainHandler.post(block)

    private fun probeVideo(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
            ?: throw IllegalArgumentException("path is required")
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val duration = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            var width = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            var height = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            val rotation = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) {
                val swapped = width
                width = height
                height = swapped
            }
            val hasAudio = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            if (duration <= 0 || width <= 0 || height <= 0) {
                throw IllegalArgumentException("That file has no readable video track")
            }
            post {
                result.success(
                    mapOf(
                        "durationMs" to duration,
                        "width" to width,
                        "height" to height,
                        "hasAudio" to hasAudio,
                    ),
                )
            }
        } finally {
            retriever.release()
        }
    }

    private fun probeAudio(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
            ?: throw IllegalArgumentException("path is required")
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("audio/")) continue
                val durationUs = format.getLong(MediaFormat.KEY_DURATION)
                post { result.success((durationUs / 1000L).toInt()) }
                return
            }
            throw IllegalArgumentException("No audio track found")
        } finally {
            extractor.release()
        }
    }

    private fun extractFrames(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
            ?: throw IllegalArgumentException("sourcePath is required")
        val outputDir = call.argument<String>("outputDir")
            ?: throw IllegalArgumentException("outputDir is required")
        val fps = (call.argument<Int>("fps") ?: 30).coerceIn(1, 60)
        val maxFrames = (call.argument<Int>("maxFrames") ?: 900).coerceIn(1, 900)
        val maxWidth = (call.argument<Int>("maxWidth") ?: 1080).coerceIn(16, 4096)
        val maxHeight = (call.argument<Int>("maxHeight") ?: 1920).coerceIn(16, 4096)
        val pattern = call.argument<String>("framePattern") ?: "f%05d.jpg"

        cancelRequested = false
        val dir = File(outputDir)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("Could not create the frame directory")
        }
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(sourcePath)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            if (durationMs <= 0) throw IllegalArgumentException("Video has no duration")
            val wanted = minOf(maxFrames, ((durationMs * fps) / 1000L).toInt().coerceAtLeast(1))
            var written = 0
            var lastBitmap: Bitmap? = null
            var targetWidth = 0
            var targetHeight = 0
            for (index in 0 until wanted) {
                if (cancelRequested) break
                val timeUs = index * 1_000_000L / fps
                val frame = retriever.getFrameAtTime(
                    timeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST,
                )
                val bitmap = frame ?: lastBitmap
                if (bitmap == null) {
                    throw IllegalStateException("The video has no decodable frames")
                }
                if (lastBitmap == null) {
                    val scale = minOf(
                        maxWidth.toFloat() / bitmap.width,
                        maxHeight.toFloat() / bitmap.height,
                        1f,
                    )
                    targetWidth = (bitmap.width * scale).toInt().coerceAtLeast(2)
                    targetHeight = (bitmap.height * scale).toInt().coerceAtLeast(2)
                    // H.264 4:2:0 prefers even dimensions; keep the proxy even.
                    targetWidth = targetWidth / 2 * 2
                    targetHeight = targetHeight / 2 * 2
                }
                val scaled = if (bitmap.width == targetWidth && bitmap.height == targetHeight) {
                    bitmap
                } else {
                    Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
                }
                val fileName = pattern.replace("%05d", String.format("%05d", index))
                FileOutputStream(File(dir, fileName)).use { out ->
                    scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
                }
                if (scaled !== bitmap) scaled.recycle()
                if (frame != null) {
                    lastBitmap?.recycle()
                    lastBitmap = frame
                }
                written++
                if (written % 4 == 0 || written == wanted) {
                    val done = written
                    val total = wanted
                    channel?.let { ch ->
                        mainHandler.post {
                            ch.invokeMethod(
                                "extractionProgress",
                                mapOf("done" to done, "total" to total),
                            )
                        }
                    }
                }
            }
            lastBitmap?.recycle()
            if (cancelRequested) {
                dir.listFiles()?.forEach { it.delete() }
                throw IllegalStateException("Import cancelled")
            }
            if (written == 0) throw IllegalStateException("No frames were extracted")
            post {
                result.success(
                    mapOf(
                        "count" to written,
                        "width" to targetWidth,
                        "height" to targetHeight,
                    ),
                )
            }
        } finally {
            retriever.release()
        }
    }
}
