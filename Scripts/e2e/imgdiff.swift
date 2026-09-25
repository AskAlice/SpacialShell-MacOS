// imgdiff REF CANDIDATE DIFF_OUT [TOLERANCE] [THRESHOLD]
// Both images are drawn at 480 px wide (scaling irons out caret blink and sub-pixel text noise),
// a pixel "differs" when any channel moves by more than THRESHOLD/255 (default 24), and the run fails when the
// differing fraction exceeds TOLERANCE (default 0.01). DIFF_OUT is the candidate, dimmed, with
// differing pixels in red. Exit: 0 match · 1 regression · 2 usage/IO.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: imgdiff REF CANDIDATE DIFF_OUT [TOLERANCE]\n".utf8))
    exit(2)
}
let tolerance = args.count > 4 ? Double(args[4]) ?? 0.01 : 0.01
let threshold = args.count > 5 ? Int(args[5]) ?? 24 : 24

func load(_ path: String) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        FileHandle.standardError.write(Data("imgdiff: cannot read \(path)\n".utf8)); exit(2)
    }
    return img
}

let ref = load(args[1]), cand = load(args[2])
let refAspect = Double(ref.height) / Double(ref.width), candAspect = Double(cand.height) / Double(cand.width)
guard abs(refAspect - candAspect) < 0.01 else {
    print("aspect differs: ref \(ref.width)x\(ref.height), candidate \(cand.width)x\(cand.height)")
    exit(1)
}
let w = 480, h = Int((Double(w) * refAspect).rounded())

func pixels(_ img: CGImage) -> [UInt8] {
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    buf.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return buf
}

let a = pixels(ref), b = pixels(cand)
var out = b, differing = 0
for p in stride(from: 0, to: a.count, by: 4) {
    let delta = (0..<3).map { abs(Int(a[p + $0]) - Int(b[p + $0])) }.max()!
    if delta > threshold {
        differing += 1
        out[p] = 255; out[p + 1] = 0; out[p + 2] = 0
    } else {
        for c in 0..<3 { out[p + c] = UInt8(Int(b[p + c]) / 3) }
    }
    out[p + 3] = 255
}

let ratio = Double(differing) / Double(w * h)
out.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[3]) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(dst, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dst)
    }
}
print(String(format: "%.4f of pixels differ by more than %d/255 (tolerance %.4f)", ratio, threshold, tolerance))
exit(ratio > tolerance ? 1 : 0)
