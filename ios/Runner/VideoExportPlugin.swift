import AVFoundation
import CoreVideo
import Flutter
import UIKit

/// H.264 (+AAC) export for Invita Studio on iOS.
///
/// Frames arrive from Flutter as RGBA8888 with deterministic presentation
/// timestamps. They are converted to BGRA CVPixelBuffers and appended to an
/// AVAssetWriter. When music is enabled the silent video is combined with the
/// trimmed/offset music track in a second pass so volume and fades are applied.
public final class VideoExportPlugin: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "studio.invita.video.export")
  private var sessions: [String: ExportSession] = [:]

  public static func register(with registrar: FlutterPluginRegistrar?) {
    guard let registrar else { return }
    let channel = FlutterMethodChannel(
      name: "invita/video_export",
      binaryMessenger: registrar.messenger()
    )
    let instance = VideoExportPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "open":
      queue.async {
        do {
          let session = try ExportSession(
            outputPath: args["outputPath"] as? String ?? "",
            width: args["width"] as? Int ?? 0,
            height: args["height"] as? Int ?? 0,
            fps: args["fps"] as? Int ?? 30,
            frameCount: args["frameCount"] as? Int ?? 0,
            bitrate: args["bitrate"] as? Int ?? 8_000_000,
            audio: args["audio"] as? [String: Any]
          )
          let id = UUID().uuidString
          self.sessions[id] = session
          self.reply(result, id)
        } catch {
          self.fail(result, error)
        }
      }
    case "addFrame":
      let id = args["sessionId"] as? String ?? ""
      queue.async {
        guard let session = self.sessions[id] else {
          self.fail(result, NSError(domain: "invita", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Unknown session"]))
          return
        }
        do {
          let bytes = args["bytes"] as? FlutterStandardTypedData
          let pts = args["timestampUs"] as? Int64 ?? 0
          try session.addFrame(rgba: bytes?.data ?? Data(), timestampUs: pts)
          self.reply(result, nil)
        } catch {
          self.fail(result, error)
        }
      }
    case "finish":
      let id = args["sessionId"] as? String ?? ""
      queue.async {
        guard let session = self.sessions.removeValue(forKey: id) else {
          self.fail(result, NSError(domain: "invita", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Unknown session"]))
          return
        }
        do {
          let path = try session.finish()
          self.reply(result, path)
        } catch {
          self.fail(result, error)
        }
      }
    case "cancel":
      let id = args["sessionId"] as? String ?? ""
      queue.async {
        if let session = self.sessions.removeValue(forKey: id) {
          session.cancel()
        }
        self.reply(result, nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func fail(_ result: @escaping FlutterResult, _ error: Error) {
    DispatchQueue.main.async {
      result(FlutterError(code: "export_failed",
                          message: error.localizedDescription,
                          details: nil))
    }
  }
}

private struct ExportAudioSpec {
  let path: String
  let startMs: Int
  let trimStartMs: Int
  let trimEndMs: Int
  let volume: Int
  let fadeInMs: Int
  let fadeOutMs: Int
  let durationMs: Int

  init?(map: [String: Any]?) {
    guard let map, let path = map["path"] as? String else { return nil }
    self.path = path
    startMs = map["startMs"] as? Int ?? 0
    trimStartMs = map["trimStartMs"] as? Int ?? 0
    trimEndMs = map["trimEndMs"] as? Int ?? 0
    volume = map["volume"] as? Int ?? 80
    fadeInMs = map["fadeInMs"] as? Int ?? 0
    fadeOutMs = map["fadeOutMs"] as? Int ?? 0
    durationMs = map["durationMs"] as? Int ?? 0
  }
}

private enum ExportError: LocalizedError {
  case message(String)

  var errorDescription: String? {
    switch self {
    case let .message(text): return text
    }
  }
}

private final class ExportSession {
  private let writer: AVAssetWriter
  private let videoInput: AVAssetWriterInput
  private let adaptor: AVAssetWriterInputPixelBufferAdaptor
  private let width: Int
  private let height: Int
  private let fps: Int
  private let frameCount: Int
  private let outputURL: URL
  private let audio: ExportAudioSpec?
  private var framesWritten = 0
  private var started = false
  private var cancelled = false

  init(
    outputPath: String,
    width: Int,
    height: Int,
    fps: Int,
    frameCount: Int,
    bitrate: Int,
    audio: [String: Any]?
  ) throws {
    guard !outputPath.isEmpty, width > 0, height > 0 else {
      throw ExportError.message("Unsupported video size")
    }
    guard width % 2 == 0, height % 2 == 0 else {
      throw ExportError.message("Unsupported video size")
    }
    guard fps > 0, frameCount > 0, frameCount <= 900 else {
      throw ExportError.message("Unsupported video length")
    }
    self.width = width
    self.height = height
    self.fps = fps
    self.frameCount = frameCount
    self.audio = ExportAudioSpec(map: audio)
    outputURL = URL(fileURLWithPath: outputPath)
    try? FileManager.default.removeItem(at: outputURL)

    writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: bitrate,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoMaxKeyFrameIntervalKey: fps,
        AVVideoAllowFrameReorderingKey: false,
      ],
    ]
    videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    videoInput.expectsMediaDataInRealTime = false
    adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      ]
    )
    guard writer.canAdd(videoInput) else {
      throw ExportError.message("The device cannot encode this video size")
    }
    writer.add(videoInput)
  }

  func addFrame(rgba: Data, timestampUs: Int64) throws {
    if cancelled { throw ExportError.message("Export cancelled") }
    guard rgba.count == width * height * 4 else {
      throw ExportError.message("Frame size does not match the video size")
    }
    if !started {
      guard writer.startWriting() else {
        throw ExportError.message(writer.error?.localizedDescription ?? "Could not start writing")
      }
      writer.startSession(atSourceTime: .zero)
      started = true
    }
    guard let pool = adaptor.pixelBufferPool else {
      throw ExportError.message("No pixel buffer pool")
    }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let pixelBuffer = buffer else {
      throw ExportError.message("Could not allocate a frame buffer")
    }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      throw ExportError.message("Frame buffer has no storage")
    }
    let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let dst = base.assumingMemoryBound(to: UInt8.self)
    rgba.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let src = raw.bindMemory(to: UInt8.self).baseAddress else { return }
      for y in 0..<height {
        let srcRow = src + y * width * 4
        let dstRow = dst + y * stride
        for x in 0..<width {
          let i = x * 4
          dstRow[i] = srcRow[i + 2]
          dstRow[i + 1] = srcRow[i + 1]
          dstRow[i + 2] = srcRow[i]
          dstRow[i + 3] = 255
        }
      }
    }
    let time = CMTime(value: timestampUs, timescale: 1_000_000)
    var waited = 0
    while !videoInput.isReadyForMoreMediaData {
      if cancelled { throw ExportError.message("Export cancelled") }
      Thread.sleep(forTimeInterval: 0.004)
      waited += 4
      if waited > 15_000 { throw ExportError.message("The encoder stalled") }
    }
    guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
      throw ExportError.message(writer.error?.localizedDescription ?? "Frame was rejected")
    }
    framesWritten += 1
  }

  func finish() throws -> String {
    if cancelled { throw ExportError.message("Export cancelled") }
    videoInput.markAsFinished()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting { semaphore.signal() }
    semaphore.wait()
    if writer.status != .completed {
      throw ExportError.message(writer.error?.localizedDescription ?? "Video could not be written")
    }
    guard framesWritten == frameCount else {
      throw ExportError.message("Expected \(frameCount) frames but wrote \(framesWritten)")
    }
    guard FileManager.default.fileExists(atPath: outputURL.path),
          (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0 > 1024
    else {
      throw ExportError.message("The encoder produced no usable file")
    }
    if let audio {
      return try muxAudio(spec: audio)
    }
    return outputURL.path
  }

  func cancel() {
    if cancelled { return }
    cancelled = true
    if writer.status == .writing {
      writer.cancelWriting()
    }
    try? FileManager.default.removeItem(at: outputURL)
  }

  /// Second pass: combine the silent video with the trimmed music track.
  ///
  /// A passthrough export is used when no volume/fade processing is needed so
  /// the H.264 stream stays untouched. Otherwise the preset re-encodes both
  /// streams, which is the only way AVFoundation applies an audio mix.
  private func muxAudio(spec: ExportAudioSpec) throws -> String {
    let composition = AVMutableComposition()
    let videoAsset = AVURLAsset(url: outputURL)
    guard let videoTrack = videoAsset.tracks(withMediaType: .video).first,
          let compositionVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
          )
    else {
      throw ExportError.message("The silent video could not be reopened")
    }
    try compositionVideo.insertTimeRange(
      CMTimeRange(start: .zero, duration: videoAsset.duration),
      of: videoTrack,
      at: .zero
    )

    let source = AVURLAsset(url: URL(fileURLWithPath: spec.path))
    guard let sourceAudio = source.tracks(withMediaType: .audio).first,
          let compositionAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
          )
    else {
      throw ExportError.message("The music file has no audio track")
    }
    let start = CMTime(value: CMTimeValue(max(0, spec.startMs)), timescale: 1000)
    let trimStart = CMTime(value: CMTimeValue(max(0, spec.trimStartMs)), timescale: 1000)
    let trimEnd = spec.trimEndMs > spec.trimStartMs
      ? CMTime(value: CMTimeValue(spec.trimEndMs), timescale: 1000)
      : source.duration
    let window = CMTimeSubtract(trimEnd, trimStart)
    let remaining = CMTimeSubtract(videoAsset.duration, start)
    let insert = CMTimeMinimum(window, remaining)
    if insert.seconds > 0 {
      try compositionAudio.insertTimeRange(
        CMTimeRange(start: trimStart, duration: insert),
        of: sourceAudio,
        at: start
      )
    }

    let volume = Float(max(0, min(100, spec.volume))) / 100.0
    let needsMix = spec.fadeInMs > 0 || spec.fadeOutMs > 0 || volume < 0.999
    let mix = AVMutableAudioMix()
    if needsMix {
      let parameters = AVMutableAudioMixInputParameters(track: compositionAudio)
      parameters.setVolume(volume, at: .zero)
      let fadeIn = CMTime(value: CMTimeValue(max(0, spec.fadeInMs)), timescale: 1000)
      if spec.fadeInMs > 0 {
        parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: volume,
                                 timeRange: CMTimeRange(start: start, duration: fadeIn))
      }
      let end = CMTimeAdd(start, insert)
      let fadeOut = CMTime(value: CMTimeValue(max(0, spec.fadeOutMs)), timescale: 1000)
      if spec.fadeOutMs > 0, CMTimeCompare(end, fadeOut) > 0 {
        parameters.setVolumeRamp(
          fromStartVolume: volume,
          toEndVolume: 0,
          timeRange: CMTimeRange(start: CMTimeSubtract(end, fadeOut), duration: fadeOut)
        )
      }
      mix.inputParameters = [parameters]
    }

    let preset = needsMix
      ? AVAssetExportPresetHighestQuality
      : AVAssetExportPresetPassthrough
    guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else {
      throw ExportError.message("The audio could not be combined with the video")
    }
    let finalURL = outputURL.deletingLastPathComponent()
      .appendingPathComponent("muxed-\(outputURL.lastPathComponent)")
    try? FileManager.default.removeItem(at: finalURL)
    exporter.outputURL = finalURL
    exporter.outputFileType = .mp4
    exporter.shouldOptimizeForNetworkUse = true
    if needsMix { exporter.audioMix = mix }
    let semaphore = DispatchSemaphore(value: 0)
    exporter.exportAsynchronously { semaphore.signal() }
    semaphore.wait()
    guard exporter.status == .completed else {
      throw ExportError.message(exporter.error?.localizedDescription ?? "Audio muxing failed")
    }
    try? FileManager.default.removeItem(at: outputURL)
    return finalURL.path
  }
}
