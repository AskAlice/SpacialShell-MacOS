// Screen recording for runner.py's `record` step (#8), through ScreenCaptureKit.
//
//   record DIR SECONDS FPS WIDTH   the main display to DIR/f00000.png… for SECONDS
//
// ScreenCaptureKit delivers a frame only when the screen changed, so DIR/times.txt lists each
// frame with its time in seconds from the first; Scripts/e2e/media.sh turns that into a loop that
// plays at the speed it was recorded. Prints "ready" once frames are flowing, so the caller knows
// when to start acting. Needs Screen Recording (tart-guest-agent holds it in the guest).
//
// The guest has no GPU, so while recording this only copies each frame's pixels into memory; the
// PNGs are encoded after the capture stops (#149). Rendering and encoding every frame as it came
// used most of the guest's CPU, which dropped frames (5 fps for 30 asked) and slowed the shell
// being filmed by seconds.
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

let args = Array(CommandLine.arguments.dropFirst())
func die(_ msg: String) -> Never { fputs("record: \(msg)\n", stderr); exit(2) }
guard args.count == 4, let seconds = Double(args[1]), let fps = Int(args[2]), let width = Int(args[3]) else {
    die("usage: record DIR SECONDS FPS WIDTH")
}
let dir = args[0]

struct Frame { let pixels: Data; let width: Int; let height: Int; let rowBytes: Int; let time: Double }

final class Sink: NSObject, SCStreamOutput {
    var frames: [Frame] = []
    var first: CMTime?

    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              (info[.status] as? Int).flatMap(SCFrameStatus.init) == .complete,
              let px = CMSampleBufferGetImageBuffer(sb)
        else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        if first == nil { first = pts }
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return }
        let rowBytes = CVPixelBufferGetBytesPerRow(px), h = CVPixelBufferGetHeight(px)
        frames.append(Frame(pixels: Data(bytes: base, count: rowBytes * h), width: CVPixelBufferGetWidth(px),
                            height: h, rowBytes: rowBytes, time: CMTimeGetSeconds(CMTimeSubtract(pts, first!))))
    }
}

func writePNG(_ f: Frame, to path: String) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let provider = CGDataProvider(data: f.pixels as CFData),
          let img = CGImage(width: f.width, height: f.height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: f.rowBytes, space: space,
                            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                                     | CGImageAlphaInfo.noneSkipFirst.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                  UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(d, img, nil)
    CGImageDestinationFinalize(d)
}

/// A stream the system stops (seen in the guest when another client, such as the shell's own
/// hover-card capture, starts one) is logged and started again, so a recording never goes quiet.
final class Watch: NSObject, SCStreamDelegate {
    var stopped = false
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fputs("record: the stream stopped (\(error.localizedDescription)); restarting\n", stderr)
        stopped = true
    }
}

let sink = Sink()
let watch = Watch()
Task {
    do {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
        else { die("no display") }
        let cfg = SCStreamConfiguration()
        cfg.width = width
        cfg.height = width * display.height / display.width
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.colorSpaceName = CGColorSpace.sRGB
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        cfg.showsCursor = true
        cfg.queueDepth = 8
        let q = DispatchQueue(label: "record.frames")
        func start() async throws -> SCStream {
            let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: watch)
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: q)
            try await stream.startCapture()
            return stream
        }
        var stream = try await start()
        print("ready"); fflush(stdout)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            if watch.stopped {
                watch.stopped = false
                stream = try await start()
            }
        }
        try? await stream.stopCapture()
        let frames = q.sync { sink.frames }
        DispatchQueue.concurrentPerform(iterations: frames.count) { i in
            writePNG(frames[i], to: String(format: "%@/f%05d.png", dir, i))
        }
        let times = frames.enumerated().map { String(format: "f%05d.png %.3f\n", $0.offset, $0.element.time) }.joined()
        try times.write(toFile: "\(dir)/times.txt", atomically: true, encoding: .utf8)
        print("wrote \(frames.count) frames over \(seconds) s"); exit(0)
    } catch {
        die("\(error)")
    }
}
RunLoop.main.run()
