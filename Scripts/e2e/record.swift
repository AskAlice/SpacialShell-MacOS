// Screen recording for runner.py's `record` step (#8), through ScreenCaptureKit.
//
//   record DIR SECONDS FPS WIDTH   the main display to DIR/f00000.png… for SECONDS
//
// ScreenCaptureKit delivers a frame only when the screen changed, so DIR/times.txt lists each
// frame with its time in seconds from the first; Scripts/e2e/media.sh turns that into a loop that
// plays at the speed it was recorded. Prints "ready" once frames are flowing, so the caller knows
// when to start acting. Needs Screen Recording (tart-guest-agent holds it in the guest).
import CoreImage
import CoreMedia
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

final class Sink: NSObject, SCStreamOutput {
    var written = 0
    var first: CMTime?
    var times = ""
    let ctx = CIContext()
    let io = DispatchQueue(label: "record.io")

    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              (info[.status] as? Int).flatMap(SCFrameStatus.init) == .complete,
              let px = CMSampleBufferGetImageBuffer(sb),
              let img = ctx.createCGImage(CIImage(cvPixelBuffer: px), from: CGRect(x: 0, y: 0,
                                          width: CVPixelBufferGetWidth(px), height: CVPixelBufferGetHeight(px)))
        else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        if first == nil { first = pts }
        let name = String(format: "f%05d.png", written)
        times += String(format: "%@ %.3f\n", name, CMTimeGetSeconds(CMTimeSubtract(pts, first!)))
        written += 1
        io.async {
            guard let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(dir)/\(name)") as CFURL,
                                                          UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(d, img, nil)
            CGImageDestinationFinalize(d)
        }
    }
}

let sink = Sink()
Task {
    do {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
        else { die("no display") }
        let cfg = SCStreamConfiguration()
        cfg.width = width
        cfg.height = width * display.height / display.width
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        cfg.showsCursor = true
        cfg.queueDepth = 8
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: nil)
        let q = DispatchQueue(label: "record.frames")
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: q)
        try await stream.startCapture()
        print("ready"); fflush(stdout)
        try await Task.sleep(for: .seconds(seconds))
        try await stream.stopCapture()
        q.sync {}
        sink.io.sync {}
        try sink.times.write(toFile: "\(dir)/times.txt", atomically: true, encoding: .utf8)
        print("wrote \(sink.written) frames over \(seconds) s"); exit(0)
    } catch {
        die("\(error)")
    }
}
RunLoop.main.run()
