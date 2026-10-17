import AVFoundation
import Flutter
import UIKit

/// Probes video/audio files and extracts the bounded JPEG proxy sequence that
/// both the preview and the exporter read.
public final class VideoMediaPlugin: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "studio.invita.video.media")
  private var channel: FlutterMethodChannel?
  private var cancelRequested = false

  public static func register(with registrar: FlutterPluginRegistrar?) {
    guard let registrar else { return }
    let channel = FlutterMethodChannel(
      name: "invita/video_media",
      binaryMessenger: registrar.messenger()
    )
    let instance = VideoMediaPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method == "cancelExtraction" {
      cancelRequested = true
      result(nil)
      return
    }
    queue.async {
      do {
        switch call.method {
        case "probeVideo":
          let path = args["path"] as? String ?? ""
          let asset = AVURLAsset(url: URL(fileURLWithPath: path))
          let durationMs = Int((CMTimeGetSeconds(asset.duration) * 1000).rounded())
          guard let track = asset.tracks(withMediaType: .video).first else {
            throw MediaError.message("That file has no video track")
          }
          let size = track.naturalSize.applying(track.preferredTransform)
          let width = Int(abs(size.width).rounded())
          let height = Int(abs(size.height).rounded())
          guard durationMs > 0, width > 0, height > 0 else {
            throw MediaError.message("That video could not be read")
          }
          let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty
          self.reply(result, [
            "durationMs": durationMs,
            "width": width,
            "height": height,
            "hasAudio": hasAudio,
          ])
        case "probeAudio":
          let path = args["path"] as? String ?? ""
          let asset = AVURLAsset(url: URL(fileURLWithPath: path))
          guard !asset.tracks(withMediaType: .audio).isEmpty else {
            throw MediaError.message("No audio track found")
          }
          let durationMs = Int((CMTimeGetSeconds(asset.duration) * 1000).rounded())
          guard durationMs > 0 else {
            throw MediaError.message("That audio file could not be read")
          }
          self.reply(result, durationMs)
        case "extractFrames":
          try self.extractFrames(args: args, result: result)
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "media_failed",
                              message: error.localizedDescription,
                              details: nil))
        }
      }
    }
  }

  private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func extractFrames(args: [String: Any], result: @escaping FlutterResult) throws {
    cancelRequested = false
    let sourcePath = args["sourcePath"] as? String ?? ""
    let outputDir = args["outputDir"] as? String ?? ""
    let fps = min(max(args["fps"] as? Int ?? 30, 1), 60)
    let maxFrames = min(max(args["maxFrames"] as? Int ?? 900, 1), 900)
    let maxWidth = min(max(args["maxWidth"] as? Int ?? 1080, 16), 4096)
    let maxHeight = min(max(args["maxHeight"] as? Int ?? 1920, 16), 4096)
    let pattern = args["framePattern"] as? String ?? "f%05d.jpg"

    let directory = URL(fileURLWithPath: outputDir, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let asset = AVURLAsset(url: URL(fileURLWithPath: sourcePath))
    guard let track = asset.tracks(withMediaType: .video).first else {
      throw MediaError.message("That file has no video track")
    }
    let durationSeconds = CMTimeGetSeconds(asset.duration)
    guard durationSeconds > 0 else {
      throw MediaError.message("Video has no duration")
    }
    let wanted = min(maxFrames, max(1, Int((durationSeconds * Double(fps)).rounded())))

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    let natural = track.naturalSize.applying(track.preferredTransform)
    let sourceWidth = abs(natural.width)
    let sourceHeight = abs(natural.height)
    guard sourceWidth > 0, sourceHeight > 0 else {
      throw MediaError.message("Video has no readable frame size")
    }
    let scale = min(1.0, min(CGFloat(maxWidth) / sourceWidth, CGFloat(maxHeight) / sourceHeight))
    var targetWidth = max(2, Int((sourceWidth * scale).rounded()))
    var targetHeight = max(2, Int((sourceHeight * scale).rounded()))
    targetWidth = targetWidth / 2 * 2
    targetHeight = targetHeight / 2 * 2
    generator.maximumSize = CGSize(width: targetWidth, height: targetHeight)

    var written = 0
    for index in 0..<wanted {
      if cancelRequested { break }
      let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
      do {
        let image = try generator.copyCGImage(at: time, actualTime: nil)
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.82) else {
          throw MediaError.message("A frame could not be encoded")
        }
        let name = String(format: pattern, index)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        written += 1
      } catch {
        if written == 0 { throw error }
        // A single unreadable frame is tolerated; the previous frame is
        // duplicated by re-writing it so the sequence stays contiguous.
        let previous = directory.appendingPathComponent(String(format: pattern, index - 1))
        let target = directory.appendingPathComponent(String(format: pattern, index))
        try? FileManager.default.copyItem(at: previous, to: target)
        written += 1
      }
      if written % 4 == 0 || written == wanted {
        let done = written
        let total = wanted
        DispatchQueue.main.async { [weak self] in
          self?.channel?.invokeMethod("extractionProgress",
                                      arguments: ["done": done, "total": total])
        }
      }
    }
    if cancelRequested {
      try? FileManager.default.removeItem(at: directory)
      throw MediaError.message("Import cancelled")
    }
    guard written > 0 else {
      throw MediaError.message("No frames were extracted")
    }
    reply(result, ["count": written, "width": targetWidth, "height": targetHeight])
  }
}

private enum MediaError: LocalizedError {
  case message(String)

  var errorDescription: String? {
    switch self {
    case let .message(text): return text
    }
  }
}
